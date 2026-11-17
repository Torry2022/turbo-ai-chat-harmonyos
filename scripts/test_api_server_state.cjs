// node scripts/test_api_server_state.cjs <path/to/typescript.js>
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(process.argv[2] || 'typescript');
const source = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/state/ChatViewModel.ets'), 'utf8');
const ast = ts.createSourceFile('ChatViewModel.ts', source, ts.ScriptTarget.Latest, true);
class Stub { static create() { return new Stub(); } }
const context = { exports: {}, Observed: value => value, Scroller: Stub, setTimeout, clearTimeout, setInterval, clearInterval };
for (const node of ast.statements.filter(ts.isImportDeclaration)) {
  const clause = node.importClause;
  if (clause.name) context[clause.name.text] = Stub;
  for (const binding of clause.namedBindings?.elements || []) {
    const name = binding.name.text;
    context[name] = /^[A-Z_]+$/.test(name) ? 0 : Stub;
  }
}
let layaReady = false;
context.isDecisionReady = () => layaReady;
let decisionLoaded = false;
context.isDecisionLoaded = () => decisionLoaded;
context.loadedDecisionModel = () => decisionLoaded ? {id: 'laya', name: 'Laya', shortName: 'Laya'} : undefined;
context.formatError = error => error.message;
vm.runInNewContext(ts.transpileModule(ast.statements.find(ts.isClassDeclaration).getText(ast), {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020, experimentalDecorators: true }
}).outputText, context);
const tick = () => new Promise(resolve => setImmediate(resolve));
const tabSource = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/components/ApiServerTab.ets'), 'utf8').replace(/\r\n/g, '\n');
const capabilityMethods = tabSource.slice(tabSource.indexOf('  private capabilityModel('), tabSource.indexOf('  @Builder\n  private CapabilityHeader('));
const Capability = vm.runInNewContext(ts.transpileModule(`class Capability { ${capabilityMethods} }`, {
  compilerOptions: { target: ts.ScriptTarget.ES2020 }
}).outputText + '\nCapability');
const capability = new Capability();
let loadedDecisionModel, loadedRerankModel;
Object.assign(capability, {
  loaded: false, currentModelName: 'Selected chat', apiRequestKind: '',
  viewModel: {
    loadedDecision: () => loadedDecisionModel,
    loadedReranker: () => loadedRerankModel,
    decisionRuntimeState: 'idle', modelLoading: false, rerankLoading: false,
    reranker: { busy: false }
  }
});
for (const mode of ['chat', 'decision', 'rerank']) {
  assert.equal(capability.capabilityModel(mode), '');
  assert.equal(capability.capabilityState(mode), '未加载');
}
capability.loaded = true;
capability.currentModelName = 'Loaded chat';
loadedDecisionModel = { name: 'Loaded decision', shortName: 'Short decision' };
loadedRerankModel = { name: 'Loaded rerank', shortName: 'Short rerank' };
capability.viewModel.decisionRuntimeState = 'loaded';
for (const mode of ['chat', 'decision', 'rerank']) {
  assert.equal(capability.capabilityModel(mode), `Loaded ${mode}`);
  assert.equal(capability.capabilityState(mode), '已加载');
}
capability.apiRequestKind = 'decision';
assert.equal(capability.capabilityState('decision'), '处理中');
capability.apiRequestKind = '';
capability.viewModel.decisionRuntimeState = 'releasing';
assert.equal(capability.capabilityState('decision'), '释放中');
loadedDecisionModel = loadedRerankModel = undefined;
capability.loaded = false;
capability.viewModel.decisionRuntimeState = 'loading';
capability.viewModel.modelLoading = capability.viewModel.rerankLoading = true;
for (const mode of ['chat', 'decision', 'rerank']) {
  assert.equal(capability.capabilityModel(mode), '');
  assert.equal(capability.capabilityState(mode), '加载中');
}
console.log('PASS service capabilities use loaded models and runtime states without selected-model fallbacks');
(async () => {
  const view = new context.exports.ChatViewModel();
  view.notify = view.notifyAndScroll = view.saveApiServerSettings = view.appendApiServerLog = () => {};
  view.nativeService = { modelThreadInfo: () => ({ chat: { requested: 4, actual: 4 } }) };
  view.loaded = false;
  view.threadNum = 6;
  assert.equal(view.threadConfigHint(), '下次加载时使用此配置');
  view.loaded = true;
  view.threadNum = 4;
  assert.equal(view.threadConfigHint(), '');
  view.threadNum = 6;
  view.runtimeConfigDirty = true;
  assert.equal(view.threadConfigHint(), '当前使用 4 线程，重新加载后生效');
  view.nativeService.modelThreadInfo = () => ({ chat: { requested: 6, actual: 6 } });
  view.runtimeConfigDirty = false;
  assert.equal(view.threadConfigHint(), '');
  view.loaded = false;
  console.log('PASS thread hint distinguishes pending settings from loaded runtime without duplicate values');
  let prompted = 0, toasts = 0, starts = 0, stops = 0, resolveStart, rejectStart;
  view.toastCallback = () => { toasts++; };
  view.openModelLoadDialog = () => { prompted++; view.showModelLoadDialog = true; };
  view.apiServerKey = 'test-key';
  view.apiServer = {
    start: () => { starts++; return new Promise((resolve, reject) => { resolveStart = resolve; rejectStart = reject; }); },
    stop: async () => { stops++; }
  };
  view.evidenceOwnerId = 'test-owner';
  view.setApiServerEnabled(true);
  assert.equal(starts, 1);
  assert.equal(prompted, 0);
  assert.equal(view.apiServerStarting, true);
  assert.equal(view.apiServerRunning, false);
  resolveStart('http://localhost:8080');
  await tick();
  assert.equal(view.apiServerRunning, true);
  view.stopApiServerForModelChange(true);
  assert.equal(view.apiServerRunning, true);
  assert.equal(view.apiServerStartAfterModelLoad, false);
  assert.equal(stops, 0);
  view.setApiServerEnabled(false);
  await tick();
  assert.equal(stops, 1);
  assert.equal(view.apiServerRunning, false);
  console.log('PASS server starts without a model and survives model changes');

  view.setApiServerEnabled(true);
  rejectStart(new Error('port occupied'));
  await tick();
  assert.equal(view.apiServerRunning, false);
  assert.equal(view.apiServerStarting, false);
  assert.match(view.apiServerStatus, /port occupied/);
  view.apiServerPortInput = '0';
  view.setApiServerEnabled(true);
  assert.equal(starts, 2);
  assert.equal(view.apiServerRunning, false);
  view.apiServerPortInput = '8080';
  view.busy = true;
  view.setApiServerEnabled(true);
  assert.equal(starts, 2);
  console.log('PASS startup failure, invalid port and active inference guards');

  view.busy = false;
  view.loaded = true;
  view.reranker = { busy: false };
  view.nativeService = { cancelTitleGeneration: async () => {} };
  view.modelLifecycleService = {
    recordSuccessfulLoad: async () => {},
    recordFailedLoad: async () => {}
  };
  let resolveLoad, resolveDecision, rejectDecision, releaseCalls = 0;
  context.loadDecision = () => new Promise(resolve => { resolveLoad = () => { decisionLoaded = true; resolve(); }; });
  context.decide = () => new Promise((resolve, reject) => { resolveDecision = resolve; rejectDecision = reject; });
  context.releaseDecision = async () => { releaseCalls++; decisionLoaded = false; };
  await assert.rejects(view.runDecision('x', 'choice', 'q', ['a','b']), /先在模型页加载/);
  const loading = view.loadDecisionModel();
  assert.equal(view.busy, true);
  assert.equal(view.modelLoadTarget, 'decision');
  assert.equal(view.showModelLoadDialog, true);
  assert.equal(view.status, '正在加载 Laya...');
  await tick();
  await assert.rejects(view.runApiGeneration({}, () => {}), /当前已有任务/);
  await view.releaseDecisionModel();
  assert.equal(releaseCalls, 0);
  resolveLoad();
  await loading;
  assert.equal(view.busy, false);
  assert.equal(view.loaded, true);
  assert.equal(view.status, 'Laya 决策模型已加载');
  assert.equal(view.modelLoadDialogName(), 'Laya（决策模型）');
  assert.equal(view.modelLoadDialogComplete(), true);
  const deciding = view.runDecision('x', 'choice', 'q', ['a','b']);
  assert.equal(view.busy, true);
  await tick();
  await assert.rejects(view.runDecision('x', 'choice', 'q', ['a','b']), /当前模型任务/);
  resolveDecision('{}');
  await deciding;
  assert.equal(view.busy, false);
  const failed = view.runDecision('x', 'choice', 'q', ['a','b']);
  await tick();
  rejectDecision(new Error('decision failed'));
  await assert.rejects(failed);
  assert.equal(view.busy, false);
  await view.releaseDecisionModel();
  assert.equal(decisionLoaded, false);
  assert.equal(view.loaded, true);
  console.log('PASS decision loading and inference block conflicting work and preserve the loaded chat model');
  view.temperature = .25; view.topP = .65; view.topK = 17;
  view.maxNewTokens = 1024; view.penaltyWindow = 0;
  view.updateRepetitionPenalty(.8, false);
  assert.equal(view.repetitionPenalty, 1);
  view.generationDefaultsForCurrentModel = () => ({});
  view.ensureCurrentModelInstalled = async () => true;
  let loadedSettings;
  view.startModelLoad = () => { loadedSettings = { ...view.currentGenerationSettings(), maxNewTokens: view.maxNewTokens }; };
  view.loadModel(); await tick();
  assert.deepEqual(JSON.parse(JSON.stringify(loadedSettings)), {
    temperature: .25, topP: .65, topK: 17, repetitionPenalty: 1,
    frequencyPenalty: view.frequencyPenalty, presencePenalty: view.presencePenalty,
    penaltyWindow: 0, maxNewTokens: 1024
  });
  console.log('PASS manual loading preserves configured generation values and repetition penalty lower bound');
})().catch(error => { console.error(error); process.exitCode = 1; });
