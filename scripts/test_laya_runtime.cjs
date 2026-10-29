// node scripts/test_laya_runtime.cjs <path/to/typescript.js>
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(process.argv[2] || 'typescript');
const root = path.join(__dirname, '../entry/src/main/ets');
const source = fs.readFileSync(path.join(root, 'services/LayaDecisionService.ets'), 'utf8');
const configContext = { exports: {} };
vm.runInNewContext(ts.transpileModule(fs.readFileSync(path.join(root, 'models/LayaModelConfig.ets'), 'utf8'), {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
}).outputText, configContext);
const config = configContext.exports;
let resolveDecision, rejectDecision, calls = 0, releases = 0;
let nativePaths;
const installedFiles = new Map(config.LAYA_DOWNLOAD_SPEC.files.map(file =>
  [`/files/${config.LAYA_MODEL_DIRECTORY}/${file.relativePath}`, file.sizeBytes]));
const native = {
  layaDecideAsync: (modelPath, tokenizerPath) => { nativePaths = [modelPath, tokenizerPath]; calls++; return new Promise((resolve, reject) => {
    resolveDecision = resolve; rejectDecision = reject;
  }); },
  layaReleaseAsync: async () => { releases++; }
};
const context = { exports: {}, require: name => {
  if (name.includes('LayaModelConfig')) return config;
  if (name.includes('RerankerService')) return {isRerankerActive:()=>false};
  return { default: name === 'libentry.so' ? native : {
    statSync: file => ({ isFile: () => installedFiles.has(file), size: installedFiles.get(file) })
  } };
} };
vm.runInNewContext(ts.transpileModule(source, {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
}).outputText, context);
const api = context.exports;
(async () => {
  const states = [];
  assert.equal(api.isLayaReady('/files'), true);
  const tokenizerPath = `/files/${config.LAYA_MODEL_DIRECTORY}/${config.LAYA_TOKENIZER_FILE}`;
  installedFiles.set(tokenizerPath, config.LAYA_TOKENIZER_BYTES - 1);
  assert.equal(api.isLayaReady('/files'), false);
  installedFiles.set(tokenizerPath, config.LAYA_TOKENIZER_BYTES);
  assert.equal(api.isLayaReady('/missing'), false);
  api.observeLayaRuntime(state => states.push(state));
  const first = api.decideLaya('/files', 'text', 'choice', 'question', ['a', 'b']);
  assert.deepEqual(nativePaths, [
    `/files/${config.LAYA_MODEL_DIRECTORY}/${config.LAYA_MODEL_FILE}`, tokenizerPath
  ]);
  assert.equal(states.at(-1), 'loading');
  await assert.rejects(api.decideLaya('/files', 'text', 'choice', 'question', ['a', 'b']));
  await assert.rejects(api.releaseLaya());
  assert.equal(calls, 1);
  resolveDecision('{}');
  await first;
  assert.equal(states.at(-1), 'loaded');
  const second = api.decideLaya('/files', 'text', 'choice', 'question', ['a', 'b']);
  assert.equal(states.at(-1), 'running');
  rejectDecision(new Error('inference failed'));
  await assert.rejects(second);
  assert.equal(states.at(-1), 'idle');
  assert.equal(releases, 1);
  await api.releaseLaya();
  assert.equal(states.at(-1), 'idle');
  console.log('PASS Laya cold/warm state, concurrent request guard, release guard and error cleanup');
})().catch(error => { console.error(error); process.exitCode = 1; });
