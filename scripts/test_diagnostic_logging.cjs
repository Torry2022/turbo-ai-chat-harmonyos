// node scripts/test_diagnostic_logging.cjs
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const root = path.join(__dirname, '..');
const source = fs.readFileSync(path.join(root, 'entry/src/main/cpp/mnn_llm_runner.cpp'), 'utf8');
function functionBody(start) {
  const offset = source.indexOf(start);
  assert.ok(offset >= 0, start);
  const opening = source.indexOf('{', offset);
  let depth = 1, end = opening + 1;
  while (depth && end < source.length) {
    if (source[end] === '{') depth++;
    if (source[end] === '}') depth--;
    end++;
  }
  return source.slice(offset, end);
}
const temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'turbo-diagnostic-'));
try {
  const logPath = path.join(temporary, 'raw_output_debug.txt');
  const fixture = `
#include <cassert>
#include <cerrno>
#include <cstdio>
#include <fstream>
#include <mutex>
#include <string>
#include <thread>
#include <atomic>
#ifdef _WIN32
#include <windows.h>
// The local MinGW uses Win32 threads and does not provide std::mutex/std::thread.
// Supply the mutex dependency with the same lock contract for this host fixture.
class DiagnosticTestMutex {
  CRITICAL_SECTION lock_;
public:
  DiagnosticTestMutex() { InitializeCriticalSection(&lock_); }
  ~DiagnosticTestMutex() { DeleteCriticalSection(&lock_); }
  void lock() { EnterCriticalSection(&lock_); }
  void unlock() { LeaveCriticalSection(&lock_); }
};
#else
using DiagnosticTestMutex = std::mutex;
#endif
struct Context { std::string end_with; int status = 0; std::string output_tokens; };
struct Llm { Context context; const Context* getContext() const { return &context; } };
struct MnnLlmRunner {
  struct SamplingConfig {
    int maxNewTokens = 128, topK = 20, penaltyWindow = 256;
    double temperature = .7, topP = .8, repetitionPenalty = 1.05, frequencyPenalty = 0, presencePenalty = 0;
  };
  struct GenerationResult { int inputTokens = 17, generatedTokens = 2; std::string stopReason = "eos"; };
  static bool setDiagnosticLogging(bool enabled);
};
DiagnosticTestMutex diagnosticMutex;
bool diagnosticLoggingEnabled = false;
constexpr const char* diagnosticPath = ${JSON.stringify(logPath.replaceAll('\\', '/'))};
${functionBody('void DumpRawPromptDebug(').replaceAll('std::mutex', 'DiagnosticTestMutex')}
${functionBody('bool MnnLlmRunner::setDiagnosticLogging(').replaceAll('std::mutex', 'DiagnosticTestMutex')}
bool exists() { return std::ifstream(diagnosticPath).good(); }
std::atomic_bool started{false};
void writeRepeatedly() {
  started = true;
  for (int i = 0; i < 100; ++i) DumpRawPromptDebug("input", "answer", {}, {}, nullptr);
}
#ifdef _WIN32
DWORD WINAPI runWorker(LPVOID) { writeRepeatedly(); return 0; }
#endif
int main() {
  MnnLlmRunner::SamplingConfig sampling;
  MnnLlmRunner::GenerationResult result;
  auto write = [&]() { DumpRawPromptDebug("private input", "private answer", sampling, result, nullptr); };
  write(); assert(!exists());
  { std::ofstream old(diagnosticPath); old << "old private record"; }
  assert(MnnLlmRunner::setDiagnosticLogging(false)); assert(!exists());
  assert(MnnLlmRunner::setDiagnosticLogging(true)); write(); assert(exists());
  { std::ifstream file(diagnosticPath); std::string data((std::istreambuf_iterator<char>(file)), {});
    assert(data.find("private input") != std::string::npos);
    assert(data.find("private answer") != std::string::npos); }
  assert(MnnLlmRunner::setDiagnosticLogging(false)); assert(!exists());
  write(); assert(!exists());
  assert(MnnLlmRunner::setDiagnosticLogging(false));
  assert(MnnLlmRunner::setDiagnosticLogging(true));
#ifdef _WIN32
  HANDLE worker = CreateThread(nullptr, 0, runWorker, nullptr, 0, nullptr);
  assert(worker != nullptr);
  while (!started.load()) Sleep(0);
#else
  std::thread worker(writeRepeatedly);
  while (!started.load()) std::this_thread::yield();
#endif
  assert(MnnLlmRunner::setDiagnosticLogging(false));
#ifdef _WIN32
  WaitForSingleObject(worker, INFINITE); CloseHandle(worker);
#else
  worker.join();
#endif
  assert(!exists());
}
`;
  const test = path.join(temporary, 'test.cpp');
  const binary = path.join(temporary, process.platform === 'win32' ? 'test.exe' : 'test');
  fs.writeFileSync(test, fixture);
  const compiler = process.env.CXX || (process.platform === 'win32' ? 'g++' : 'c++');
  const compiled = spawnSync(compiler, ['-std=c++17', ...(process.platform === 'win32' ? [] : ['-pthread']), test, '-o', binary], { encoding: 'utf8' });
  assert.equal(compiled.status, 0, compiled.error?.message || compiled.stderr);
  const executed = spawnSync(binary, [], { encoding: 'utf8' });
  assert.equal(executed.status, 0, executed.stderr);
  const vm = fs.readFileSync(path.join(root, 'entry/src/main/ets/state/ChatViewModel.ets'), 'utf8');
  const initialize = vm.slice(vm.indexOf('  initialize(context: common.UIAbilityContext)'), vm.indexOf('  private async loadModelCatalog('));
  assert.ok(initialize.indexOf('this.setDiagnosticLogging(false, false)') >= 0);
  assert.ok(initialize.indexOf('this.setDiagnosticLogging(false, false)') < initialize.indexOf('this.modelManager.initialize('));
  assert.match(vm, /async deleteConversation\(id\?: string\): Promise<void> \{\s*if \(!this.canManageConversations\(\)\) return\s*this.setDiagnosticLogging\(false, false\)/);
  console.log('PASS diagnostics default off, explicit opt-in, old-file cleanup and concurrent disable');
} finally {
  fs.rmSync(temporary, { recursive: true, force: true });
}
