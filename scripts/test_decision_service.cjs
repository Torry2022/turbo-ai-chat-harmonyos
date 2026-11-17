// node scripts/test_decision_service.cjs <path/to/typescript.js>
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(process.argv[2] || 'typescript');
const states = [];
let legacyLoaded = false;
let resolveRun;
let failLoad = false;
let threadConfig = {};
let loadedThreads;
const native = {
  h2oLoadAsync: async (_path, threads) => { loadedThreads = threads; if (failLoad) throw new Error('load failed'); return JSON.stringify({cpu_threads:Math.min(threads,6)}); },
  h2oReleaseAsync: async () => {},
  h2oDecideAsync: () => new Promise(resolve => { resolveRun = resolve; }),
};
const legacy = {
  loadLaya: async () => { legacyLoaded = true; },
  releaseLaya: async () => { legacyLoaded = false; },
  isLayaReady: () => true,
  isLayaLoaded: () => legacyLoaded,
  decideLaya: async () => { legacyLoaded = false; throw new Error('legacy failure'); },
};
const executionContext={exports:{}};
vm.runInNewContext(ts.transpileModule(fs.readFileSync(path.join(__dirname,'../entry/src/main/ets/services/ModelExecutionService.ets'),'utf8'),
 {compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2020}}).outputText,executionContext);
const execution=executionContext.exports;
const context = {exports:{}, require: name => {
  if (name.includes('ModelExecutionService')) return execution;
  if (name.includes('NativeInferenceService')) return {NativeInferenceService:class {async cancelTitleGeneration(){}}};
  if (name === 'libentry.so') return {default:native};
  if (name === '@ohos.file.fs') return {default:{statSync:()=>({isFile:()=>true}),readText:async()=>JSON.stringify(threadConfig)}};
  if (name.includes('LayaDecisionService')) return legacy;
  if (name.includes('LayaModelConfig')) return {LAYA_MODEL_ID:'laya'};
  if (name.includes('RerankerService')) return {isRerankerActive:()=>false};
  if (name.includes('ModelDirectoryPreflightService')) return {
    ModelDirectoryPreflightService:class {async requireCompatible(){}}
  };
  return {};
}};
const source = fs.readFileSync(path.join(__dirname,'../entry/src/main/ets/services/DecisionService.ets'),'utf8');
vm.runInNewContext(ts.transpileModule(source, {compilerOptions:{module:ts.ModuleKind.CommonJS,
  target:ts.ScriptTarget.ES2020}}).outputText,context);
const service = context.exports;
const h2o = {id:'h2o',configPath:'/h2o/config.json'};
(async () => {
  service.observeDecisionRuntime(state => states.push(state));
  const releaseChat = execution.ModelExecutionService.acquire('chat');
  await assert.rejects(service.loadDecision('/files',h2o), /当前模型任务/);
  assert.equal(service.isDecisionLoaded(),false);
  releaseChat();
  assert.equal(await service.loadDecision('/files',h2o),4);
  assert.equal(service.loadedDecisionModel().id,'h2o');
  assert.equal(loadedThreads,4);
  const pending = service.decide('/files','record','choice','question',['a','b'],['a','b'],['a','b']);
  await assert.rejects(service.releaseDecision());
  await assert.rejects(service.loadDecision('/files',h2o));
  await assert.rejects(service.decide('/files','record','choice','question',[],[],[]));
  resolveRun('result');
  assert.equal(await pending,'result');
  assert.equal(states.at(-1),'loaded');
  await service.releaseDecision();
  await service.releaseDecision();
  assert.equal(service.isDecisionLoaded(),false);
  threadConfig = {thread_num: 8};
  await service.loadDecision('/files', h2o);
  assert.equal(loadedThreads, 8);
  await service.releaseDecision();
  for (const invalid of [0, 17, 4.5, '8']) {
    threadConfig = {thread_num: invalid};
    await assert.rejects(service.loadDecision('/files', h2o), /thread_num/);
    assert.equal(service.isDecisionLoaded(), false);
    assert.equal(states.at(-1), 'idle');
  }
  threadConfig = {thread_num: 8};
  await service.loadDecision('/files', h2o, 2);
  assert.equal(loadedThreads, 2);
  await service.releaseDecision();
  await service.loadDecision('/files', h2o, 12);
  assert.equal(loadedThreads, 12);
  await service.releaseDecision();
  threadConfig = {};
  failLoad = true;
  await assert.rejects(service.loadDecision('/files',h2o));
  assert.equal(service.isDecisionLoaded(),false);
  assert.equal(states.at(-1),'idle');
  await service.loadDecision('/files',{id:'laya'});
  await assert.rejects(service.decide('/files','record','choice','question',['a','b'],['a','b'],['a','b']));
  assert.equal(service.isDecisionLoaded(),false);
  assert.equal(states.at(-1),'idle');
  console.log('PASS H2O and Laya lifecycle, busy guards, failed loads and legacy failure cleanup');
})().catch(error => {console.error(error);process.exitCode=1;});
