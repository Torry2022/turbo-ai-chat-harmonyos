// node scripts/test_startup_focus.cjs <path/to/typescript.js>
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(process.argv[2] || 'typescript');
const source = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/pages/Index.ets'), 'utf8')
  .replace(/\r\n/g, '\n').replace('struct Index', 'class Index');
const ast = ts.createSourceFile('Index.ts', source, ts.ScriptTarget.Latest, true);
const page = ast.statements.find(ts.isClassDeclaration);
const names = ['modalFocusId', 'updateModalFocus'];
const methods = page.members.filter(member => names.includes(member.name?.text)).map(member => member.getText(ast));
assert.equal(methods.length, names.length);
const pending = new Map();
let nextTimer = 0;
const calls = [];
const context = { exports: {}, DIALOG_MOTION_DURATION: 200,
  setTimeout: (callback, delay) => { const id = ++nextTimer; pending.set(id, { callback, delay }); return id; },
  clearTimeout: id => pending.delete(id) };
vm.runInNewContext(ts.transpileModule(`export class FocusPage { ${methods.join('\n')} }`, {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }
}).outputText, context);
const instance = new context.exports.FocusPage();
Object.assign(instance, { viewModel: { knowledgeConfirmAction: '' }, focusScope: '', focusTimer: -1, showLaunch: true,
  apiUsageMode: '', helpDialog: '', showSettings: false, showLayaDecision: false });
instance.getUIContext = () => ({ getFocusController: () => ({
  clearFocus: () => calls.push('root'), requestFocus: id => calls.push(id)
}) });
function flush() {
  const timers = [...pending.values()]; pending.clear();
  timers.forEach(timer => timer.callback());
}
instance.updateModalFocus(); flush();
assert.deepEqual(calls, [], 'The launch overlay must not focus a control behind it');
instance.showLaunch = false;
instance.updateModalFocus(true); flush();
assert.deepEqual(calls, ['root'], 'Finishing launch clears focus to the page root');
instance.updateModalFocus(); flush();
assert.equal(calls.length, 1, 'Runtime refreshes preserve focus after the user taps an input');
instance.viewModel.showModelLoadDialog = true;
instance.updateModalFocus(); flush();
assert.equal(calls.at(-1), 'load-dialog');
instance.viewModel.showModelLoadDialog = false;
instance.updateModalFocus();
assert.equal(instance.dialogExitBlocking, true);
assert.equal([...pending.values()][0].delay, 220);
flush();
assert.equal(calls.at(-1), 'root', 'Closing a dialog cannot restore a previously focused text editor');
assert.equal(instance.dialogExitBlocking, false);
instance.showSettings = true;
instance.updateModalFocus();
instance.showSettings = false;
instance.apiUsageMode = 'overview';
instance.updateModalFocus(); flush();
assert.equal(calls.at(-1), 'api-usage-dialog', 'Pending focus follows the current dialog');
assert(source.includes('themeService.finishLaunch()\n      this.updateModalFocus(true)'));
assert(source.includes(".focusable(!this.showLaunch && !this.dialogExitBlocking && this.modalFocusId() === 'app-content')"));
console.log('PASS startup and dialog exit avoid input focus, user input and modal focus remain available');
