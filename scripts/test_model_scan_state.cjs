// node scripts/test_model_scan_state.cjs <path/to/typescript.js>
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(process.argv[2] || 'typescript');
const source = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/state/ChatViewModel.ets'), 'utf8');
const ast = ts.createSourceFile('ChatViewModel.ts', source, ts.ScriptTarget.Latest, true);
class Stub { static create() { return new Stub(); } }
const context = { exports: {}, Observed: value => value, Scroller: Stub, setTimeout, clearTimeout };
for (const node of ast.statements.filter(ts.isImportDeclaration)) {
  const clause = node.importClause;
  if (clause.name) context[clause.name.text] = Stub;
  for (const binding of clause.namedBindings?.elements || []) {
    const name = binding.name.text;
    context[name] = /^[A-Z_]+$/.test(name) ? 0 : Stub;
  }
}
context.formatError = error => error.message;
vm.runInNewContext(ts.transpileModule(ast.statements.find(ts.isClassDeclaration).getText(ast), {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020, experimentalDecorators: true }
}).outputText, context);
function create() {
  const view = new context.exports.ChatViewModel();
  view.notify = () => {};
  view.toastCallback = () => {};
  view.modelProfiles = () => [];
  view.status = 'existing status';
  view.importedModelNameInput = 'unsaved draft';
  view.modelManager = { updateImportedProfiles() { throw Error('Unexpected profile replacement'); } };
  view.prepareImportedModelEditor = () => { throw Error('Unexpected draft reset'); };
  return view;
}
(async () => {
  const view = create();
  let complete, calls = 0;
  view.modelLifecycleService = { scanPushedModels: () => {
    calls++;
    return new Promise(resolve => { complete = resolve; });
  }};
  const pending = view.scanPushedModelDirectories();
  assert.equal(view.modelScanning, true);
  assert.equal(view.busy, false);
  assert.equal(view.modelImporting, false);
  await view.scanPushedModelDirectories();
  assert.equal(calls, 1);
  for (const method of ['switchModel', 'importModelPackage', 'requestDeleteModel', 'confirmDeleteModel',
    'moveModelToIndex', 'unloadModel', 'loadModel', 'applyRuntimeConfigAndLoad', 'startModelLoad',
    'startBuiltinModelInstall', 'installCatalogItem', 'openModelLoadDialog']) {
    view[method]('test', 0); // Without the scan guard, unstubbed dependencies fail.
  }
  assert.equal(await view.saveImportedModelProfile(), false);
  view.setApiServerEnabled(true);
  await view.sendMessage();
  await view.startSpeechRecognition();
  if (view.startBenchmark) view.startBenchmark();
  await assert.rejects(view.runApiGeneration({}, () => {}), /正在扫描/);
  complete({ profiles: [], addedProfiles: [], errors: [], skippedCount: 0 });
  await pending;
  assert.equal(view.modelScanning, false);
  assert.equal(view.status, 'existing status');
  assert.equal(view.importedModelNameInput, 'unsaved draft');
  assert.match(view.modelImportMessage, /未发现/);
  console.log('PASS scan isolation, duplicate suppression, conflicting operations, and unchanged draft');

  for (const failure of ['reject', 'throw']) {
    view.modelLifecycleService.scanPushedModels = () => {
      if (failure === 'throw') throw Error('disk error');
      return Promise.reject(Error('disk error'));
    };
    await view.scanPushedModelDirectories();
    assert.equal(view.modelScanning, false);
    assert.equal(view.busy, false);
    assert.equal(view.modelImporting, false);
    assert.equal(view.status, 'existing status');
    assert.match(view.modelImportMessage, /扫描失败.*disk error/);
  }
  console.log('PASS synchronous/asynchronous failures release scan lock');

  const added = create();
  const profile = { id: 'new', shortName: 'New model' };
  let updates = 0, resets = 0;
  added.modelManager = {
    updateImportedProfiles() { updates++; },
    switchModel(id) { assert.equal(id, 'new'); return profile; }
  };
  added.prepareImportedModelEditor = () => {};
  added.resetGenerationSettings = () => {};
  added.session = { resetForModelSwitch() {} };
  added.syncMessages = () => {};
  added.resetLoadedModel = () => { resets++; };
  added.modelLifecycleService = { scanPushedModels: async () => ({
    profiles: [profile], addedProfiles: [profile], errors: [], skippedCount: 0
  }) };
  await added.scanPushedModelDirectories();
  assert.equal(updates, 1);
  assert.equal(resets, 1);
  assert.equal(added.modelScanning, false);
  assert.match(added.modelImportMessage, /已添加 1 个模型/);
  added.modelManager.updateImportedProfiles = () => { throw Error('commit error'); };
  await added.scanPushedModelDirectories();
  assert.equal(added.modelScanning, false);
  assert.match(added.modelImportMessage, /commit error/);
  console.log('PASS new-model selection and commit failure cleanup');
  const blocked = create();
  blocked.modelLifecycleService = { scanPushedModels() { throw Error('must not scan'); } };
  const fields = ['busy', 'modelLoading', 'modelImporting', 'builtinModelInstalling', 'apiServerStarting'];
  if (blocked.startBenchmark) fields.push('benchmarkRunning', 'knowledgeBusy');
  for (const field of fields) {
    blocked[field] = true;
    await blocked.scanPushedModelDirectories();
    assert.equal(blocked.modelScanning, false);
    assert.equal(blocked[field], true);
    assert.ok(!blocked.modelImportMessage.includes('must not scan'));
    blocked[field] = false;
  }
  console.log('PASS existing operations prevent a conflicting scan');
  const empty = create();
  const toasts = [];
  empty.toastCallback = message => toasts.push(message);
  for (const skippedCount of [0, 1]) {
    empty.modelLifecycleService = { scanPushedModels: async () => ({
      profiles: [], addedProfiles: [], errors: [], skippedCount
    }) };
    await empty.scanPushedModelDirectories();
    assert.match(toasts.pop(), /hdc.*files\/model-imports/);
  }
  empty.modelLifecycleService = { scanPushedModels: async () => ({
    profiles: [], addedProfiles: [], errors: ['invalid config'], skippedCount: 0
  }) };
  await empty.scanPushedModelDirectories();
  assert.equal(toasts.length, 0);
  console.log('PASS empty scan guidance excludes failed imports');
})().catch(error => { console.error(error); process.exitCode = 1; });
