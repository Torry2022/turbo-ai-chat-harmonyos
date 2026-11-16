// node scripts/test_generation_result.cjs
// Compile the actual result helpers against a minimal MNN context.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const source = fs.readFileSync(path.join(__dirname, '../entry/src/main/cpp/mnn_llm_runner.cpp'), 'utf8');
const temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'turbo-generation-result-'));
const status = source.slice(source.indexOf('std::string MapStopReason('), source.indexOf('int TokenCount('));
const helpers = source.slice(source.indexOf('int ResolveGeneratedTokens('), source.indexOf('} // namespace'));
const imagePrompt = source.slice(source.indexOf('std::string ImagePromptForTurns('), source.indexOf('int ResolveGeneratedTokens('));
const fixture = `
#include <algorithm>
#include <cassert>
#include <string>
#include <vector>
enum class LlmStatus { NORMAL_FINISHED, MAX_TOKENS_FINISHED, USER_CANCEL, TIMEOUT, INTERNAL_ERROR, RUNNING };
struct Context { int prompt_len = 17; long long prefill_us = 12345; long long decode_us = 23456; long long vision_us = 0; LlmStatus status = LlmStatus::RUNNING; std::vector<int> output_tokens; };
namespace MNN { namespace Transformer { using ChatMessages = std::vector<std::pair<std::string, std::string>>; } }
struct Llm { std::string apply_chat_template(const MNN::Transformer::ChatMessages& turns) { std::string result; for (const auto& turn : turns) result += turn.first + ":" + turn.second + "|"; return result; } Context context; Context* getContext() { return &context; } bool is_stop(int token) { return token == 3; } };
struct MnnLlmRunner {
  struct ChatTurn { std::string role; std::string content; bool hasImage = false; };
  struct GenerationResult { std::string text; int generatedTokens = 0; int inputTokens = -1; bool generatedTokensEstimated = false; double prefillMs = -1; double decodeMs = -1; double visionMs = -1; std::string stopReason; };
};
int TokenCount(Llm*, const std::string& value) { return value.size(); }
${status}
${imagePrompt}
${helpers}
int main() {
  const std::vector<MnnLlmRunner::ChatTurn> visualTurns = {
    {"system", "old-system"}, {"user", "old-question", true}, {"assistant", "old-answer"}, {"user", "  new-question\\n"}
  };
  Llm visualLlm;
  const auto visualPrompt = ImagePromptForTurns(&visualLlm, visualTurns);
  assert(visualPrompt.find("<img>image_0</img>\\nold-question") != std::string::npos);
  assert(visualPrompt.find("  new-question\\n") != std::string::npos);
  assert(visualPrompt.find("old-system") != std::string::npos);
  assert(visualPrompt.find("old-answer") != std::string::npos);
  assert(ImagePromptForTurns(&visualLlm, {{"assistant", "answer"}}).empty());
  const std::string text = "  code\\n---\\n<s>old</s>\\n<|im_end|>  \\n\\n";
  for (const auto state : {LlmStatus::NORMAL_FINISHED, LlmStatus::MAX_TOKENS_FINISHED,
       LlmStatus::USER_CANCEL, LlmStatus::TIMEOUT, LlmStatus::INTERNAL_ERROR}) {
    Llm llm; llm.context.status = state; llm.context.output_tokens = {1, 2, 3};
    const auto result = BuildGenerationResult(&llm, text, 128);
    assert(result.text == text);
    assert(result.prefillMs == 12.345);
    assert(result.decodeMs == 23.456);
    assert(result.visionMs == 0);
    assert(result.inputTokens == (state == LlmStatus::INTERNAL_ERROR ? -1 : 17));
    assert(result.stopReason == MapStopReason(state));
    assert(result.generatedTokens == (state == LlmStatus::NORMAL_FINISHED ? 2 : 3));
  }
  Llm empty; empty.context.status = LlmStatus::NORMAL_FINISHED;
  assert(BuildGenerationResult(nullptr, "", 128).prefillMs == -1);
  assert(BuildGenerationResult(&empty, "", 128).generatedTokens == 0);
  Llm estimated; estimated.context.status = LlmStatus::NORMAL_FINISHED;
  assert(BuildGenerationResult(&estimated, "fallback", 128).generatedTokensEstimated);
  Llm withoutStop; withoutStop.context.status = LlmStatus::NORMAL_FINISHED;
  withoutStop.context.output_tokens = {1, 2};
  assert(BuildGenerationResult(&withoutStop, "answer", 128).generatedTokens == 2);
  Llm stopped; stopped.context.status = LlmStatus::MAX_TOKENS_FINISHED;
  stopped.context.output_tokens = {1, 2};
  auto result = BuildGenerationResult(&stopped, "literal <|im_end|>", 2);
  ApplyUserStop(result, true);
  assert(result.stopReason == "user_stop");
  assert(result.text == "literal <|im_end|>");
}
`;
try {
  const test = path.join(temporary, 'test.cpp');
  const binary = path.join(temporary, process.platform === 'win32' ? 'test.exe' : 'test');
  fs.writeFileSync(test, fixture);
  const compiler = process.env.CXX || (process.platform === 'win32' ? 'g++' : 'c++');
  const compiled = spawnSync(compiler, ['-std=c++17', test, '-o', binary], { encoding: 'utf8' });
  assert.equal(compiled.status, 0, compiled.error?.message || compiled.stderr);
  const executed = spawnSync(binary, [], { encoding: 'utf8' });
  assert.equal(executed.status, 0, executed.stderr);
  assert.ok(!source.includes('StripTrailingStopSequence'));
  assert.ok(!source.includes('&output, nullptr, sampling.maxNewTokens'));
  console.log('PASS native result fidelity, stop reasons and terminal-token accounting');
} finally {
  fs.rmSync(temporary, { recursive: true, force: true });
}
