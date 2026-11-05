// node scripts/test_streaming_display.cjs <path/to/typescript.js>
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(process.argv[2] || 'typescript');
const root = path.resolve(__dirname, '../entry/src/main/ets');
const options = { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020, experimentalDecorators: true };
const graphemes = { exports: {} };
vm.runInNewContext(ts.transpileModule(fs.readFileSync(path.join(root, 'utils/graphemeBoundaries.js'), 'utf8'),
  { compilerOptions: options }).outputText, graphemes);
const smooth = { exports: {}, require: () => graphemes.exports };
vm.runInNewContext(ts.transpileModule(fs.readFileSync(path.join(root, 'utils/streamingDisplay.ets'), 'utf8'),
  { compilerOptions: options }).outputText, smooth);
const { advanceStreamingDisplay: advance, STREAM_DISPLAY_INTERVAL_MS: interval } = smooth.exports;
assert.equal(interval, 50);
assert.equal(advance('', 'x'.repeat(100), 50).length, 8);
assert.equal(advance('', 'x'.repeat(1000), 50).length, 8);
assert.equal(advance('', '你好', 50), '你');
assert.equal(advance('', '😀你好', 50), '😀');
assert.equal(advance('old', 'corrected', 50), 'corrected');
assert.equal(advance('', 'all', 500), 'al');
for (const cluster of ['👨‍👩‍👧‍👦', '👍🏽', '🇨🇳', 'e\u0301', '1️⃣', 'क्‍ष']) {
  assert.equal(advance('', cluster + '后', 50), cluster);
}
// A compound emoji arriving across chunks must stay pending until its boundary is known.
assert.equal(advance('', '👩', 50), '');
assert.equal(advance('', '👩‍', 50), '');
assert.equal(advance('', '👩‍💻', 50), '');
assert.equal(advance('', '👩‍💻好', 50), '👩‍💻');
assert.equal(advance('👩‍💻', '👩‍💻好啊', 50), '👩‍💻好');
let shown = '';
const text = '<think>分析😀</think>\n## 答案\n```js\nconst x = 1;\n```\n完成';
for (let i = 0; i < 100; i++) {
  const next = advance(shown, text, 50);
  assert(text.startsWith(next));
  assert(next.length >= shown.length);
  assert(!/[\uD800-\uDBFF]$/.test(next));
  shown = next;
}
assert.equal(shown, text.slice(0, -1), 'The trailing cluster is reserved for the final flush');

// Execute the real view model with a deterministic clock and timer.
const source = fs.readFileSync(path.join(root, 'state/ChatViewModel.ets'), 'utf8');
const ast = ts.createSourceFile('view.ts', source, ts.ScriptTarget.Latest, true);
class Stub { static create() { return new Stub(); } }
let now = 0, timer = null, clears = 0;
const context = { exports: {}, Observed: value => value, Scroller: Stub,
  Date: { now: () => now },
  setInterval: (callback, delay) => { assert.equal(delay, 50); assert.equal(timer, null); timer = callback; return 1; },
  clearInterval: () => { timer = null; clears++; },
  setTimeout, clearTimeout };
for (const node of ast.statements.filter(ts.isImportDeclaration)) {
  const clause = node.importClause;
  if (clause.name) context[clause.name.text] = Stub;
  for (const binding of clause.namedBindings?.elements || []) context[binding.name.text] = Stub;
}
Object.assign(context, smooth.exports);
vm.runInNewContext(ts.transpileModule(ast.statements.find(ts.isClassDeclaration).getText(ast),
  { compilerOptions: options }).outputText, context);
const view = new context.exports.ChatViewModel();
let saves = 0, refreshes = 0;
view.session = { messages: [{ id: 7, role: 'assistant', content: '', generationState: 'generating' }],
  updateMessage(id, content) { this.messages = this.messages.map(m => m.id === id ? { ...m, content } : m); } };
view.streamDisplayMessageId = 7;
view.scheduleHistorySave = () => { saves++; };
view.notifyAndMaybeScroll = () => { refreshes++; };
view.handleStreamUpdate(7, { text, characterCount: text.length });
assert.equal(view.session.messages[0].content, text, 'Persistence/context must receive the full text immediately');
assert.equal(view.messageContentForDisplay(view.session.messages[0]), '');
assert.equal(saves, 1);
now = 50; timer();
assert.equal(view.messageContentForDisplay(view.session.messages[0]), advance('', text, 50));
assert.equal(refreshes, 1);
view.generationStopping = true;
view.status = '正在停止生成...';
view.handleStreamUpdate(7, { text: text + '尾', characterCount: text.length + 1 });
now = 100; timer();
assert.equal(view.status, '正在停止生成...');
for (const state of ['complete', 'stopped', 'failed', 'interrupted']) {
  assert.equal(view.messageContentForDisplay({ ...view.session.messages[0], generationState: state }), text + '尾');
}
view.stopStreamDisplay();
assert.equal(timer, null);
assert.equal(clears, 1);
assert.equal(view.messageContentForDisplay(view.session.messages[0]), text + '尾');
assert.equal(view.messageContentForDisplay({ id: 8, role: 'assistant', content: '历史回答', generationState: 'complete' }), '历史回答');
view.streamDisplayMessageId = 7;
view.generationStopping = false;
view.handleStreamUpdate(7, { text: '新的回答', characterCount: 4 });
assert.equal(view.messageContentForDisplay(view.session.messages[0]), '', 'A regenerated answer starts with a fresh display buffer');
now = 150; timer();
assert.equal(view.messageContentForDisplay(view.session.messages[0]), '新');
view.stopStreamDisplay();
view.handleStreamUpdate(7, { text: '结束后的迟到回调', characterCount: 9 });
assert.equal(timer, null, 'A late callback must not restart the display timer after completion or disposal');
console.log('PASS adaptive streaming display, Unicode, complete-text storage, terminal flush and timer reset');
