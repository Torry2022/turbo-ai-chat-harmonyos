// node scripts/test_api_server_state.cjs <path/to/typescript.js>
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
const tick = () => new Promise(resolve => setImmediate(resolve));
(async () => {
  const view = new context.exports.ChatViewModel();
  view.notify = view.notifyAndScroll = view.saveApiServerSettings = view.appendApiServerLog = () => {};
  let prompted = 0, toasts = 0, starts = 0, resolveStart, rejectStart;
  view.toastCallback = () => { toasts++; };
  view.openModelLoadDialog = () => { prompted++; view.showModelLoadDialog = true; };
  view.apiServerKey = 'test-key';
  view.apiServer = {
    start: () => { starts++; return new Promise((resolve, reject) => { resolveStart = resolve; rejectStart = reject; }); },
    stop: async () => {}
  };
  view.setApiServerEnabled(true);
  assert.equal(view.apiServerRunning, false);
  assert.equal(view.apiServerStarting, false);
  assert.equal(starts, 0);
  assert.equal(prompted, 1);
  assert.equal(toasts, 1);
  view.closeModelLoadDialog();
  assert.equal(view.apiServerStartAfterModelLoad, false);
  view.loaded = true;
  view.startPendingApiServerIfReady();
  assert.equal(starts, 0);
  console.log('PASS unloaded request and cancelled load keep service off');

  view.loaded = false;
  view.setApiServerEnabled(true);
  view.loaded = true;
  view.startPendingApiServerIfReady();
  assert.equal(starts, 1);
  assert.equal(view.apiServerStarting, true);
  assert.equal(view.apiServerRunning, false);
  resolveStart('http://localhost:8080');
  await tick();
  assert.equal(view.apiServerRunning, true);
  assert.equal(view.apiServerStarting, false);
  view.setApiServerEnabled(false);
  await tick();
  assert.equal(view.apiServerRunning, false);
  console.log('PASS loaded model starts pending service only after listener succeeds');

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
  console.log('PASS startup rejection and invalid port keep service off');
})().catch(error => { console.error(error); process.exitCode = 1; });
