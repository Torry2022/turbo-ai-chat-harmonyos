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
const { StreamingDisplay, STREAM_DISPLAY_INTERVAL_MS: interval } = smooth.exports;
assert.equal(interval, 16);
const burst = new StreamingDisplay();
assert.equal(burst.advance('x'.repeat(100), 16).length, 1, 'The first complete cluster appears on the first frame');
for (let frame = 0; frame < 100; frame++) {
  const before = burst.text.length;
  burst.advance('x'.repeat(100), 16);
  assert(burst.text.length - before <= 4, 'Bursts are spread over frames');
}
assert.equal(burst.text.length, 99, 'The trailing cluster waits for the final flush');
const paced = new StreamingDisplay();
paced.advance('abcdefghij', 16);
assert.equal(paced.advance('abcdefghij', 16), 'a', 'A fractional budget must not round up every frame');
assert.equal(paced.advance('abcdefghij', 16), 'ab', 'Fractional time carries to the next frame');
assert(paced.advance('x'.repeat(100), 500) === 'x'.repeat(100), 'Corrections remain authoritative');
paced.reset();
paced.advance('a'.repeat(1000), 16);
assert(paced.advance('a'.repeat(1000), 500).length <= 5, 'A delayed frame cannot release a large batch');
for (const cluster of ['\ud83d\ude00', '👨‍👩‍👧‍👦', '👍🏽', '🇨🇳', 'e\u0301', '1️⃣', 'क्‍ष']) {
  const display = new StreamingDisplay();
  assert.equal(display.advance(cluster + '后', 16), cluster);
}
const compound = new StreamingDisplay();
for (const part of ['👩', '👩‍', '👩‍💻']) assert.equal(compound.advance(part, 16), '');
assert.equal(compound.advance('👩‍💻好', 16), '👩‍💻');
let shown = '';
const text = '<think>分析😀</think>\n## 答案\n```js\nconst x = 1;\n```\n完成';
const display = new StreamingDisplay();
for (let i = 0; i < 300; i++) {
  const next = display.advance(text, 16);
  assert(text.startsWith(next));
  assert(next.length >= shown.length);
  assert(!/[\uD800-\uDBFF]$/.test(next));
  shown = next;
}
assert.equal(shown, text.slice(0, -1));
// Execute the real view model with a deterministic clock and timer.
const source = fs.readFileSync(path.join(root, 'state/ChatViewModel.ets'), 'utf8');
const ast = ts.createSourceFile('view.ts', source, ts.ScriptTarget.Latest, true);
class Stub { static create() { return new Stub(); } }
let now = 0;
const frames = [];
const context = { exports: {}, Observed: value => value, Scroller: Stub,
  Date: { now: () => now },
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
let saves = 0, refreshes = 0, scrolls = 0;
view.postStreamFrame = callback => frames.push(callback);
function frame(elapsed = 16) { now += elapsed; const callback = frames.shift(); assert(callback); callback(); }
view.session = { messages: [{ id: 7, role: 'assistant', content: '', generationState: 'generating' }],
  updateMessage(id, content) { this.messages = this.messages.map(m => m.id === id ? { ...m, content } : m); } };
view.streamDisplayMessageId = 7;
view.scheduleHistorySave = () => { saves++; };
view.notify = () => { refreshes++; };
view.scrollToBottom = smooth => { assert.equal(smooth, true); scrolls++; };
view.handleStreamUpdate(7, { text, characterCount: text.length });
assert.equal(view.session.messages[0].content, text, 'Persistence/context must receive the full text immediately');
assert.equal(view.messageContentForDisplay(view.session.messages[0]), '');
assert.equal(saves, 1);
assert.equal(frames.length, 1);
frame();
assert.equal(view.messageContentForDisplay(view.session.messages[0]), '<');
assert.equal(refreshes, 1);
assert.equal(scrolls, 1);
view.generationStopping = true;
view.status = '正在停止生成...';
view.handleStreamUpdate(7, { text: text + '尾', characterCount: text.length + 1 });
frame();
assert.equal(view.status, '正在停止生成...');
for (const state of ['complete', 'stopped', 'failed', 'interrupted']) {
  assert.equal(view.messageContentForDisplay({ ...view.session.messages[0], generationState: state }), text + '尾');
}
view.stopStreamDisplay();
const lateFrame = frames.shift();
assert(lateFrame); lateFrame();
assert.equal(frames.length, 0, 'A stopped frame cannot reschedule itself');
assert.equal(view.messageContentForDisplay(view.session.messages[0]), text + '尾');
assert.equal(view.messageContentForDisplay({ id: 8, role: 'assistant', content: '历史回答', generationState: 'complete' }), '历史回答');
view.streamDisplayMessageId = 7;
view.generationStopping = false;
view.handleStreamUpdate(7, { text: '新的回答', characterCount: 4 });
assert.equal(view.messageContentForDisplay(view.session.messages[0]), '', 'A regenerated answer starts with a fresh display buffer');
frame();
assert.equal(view.messageContentForDisplay(view.session.messages[0]), '新');
view.stopStreamDisplay();
view.handleStreamUpdate(7, { text: '结束后的迟到回调', characterCount: 9 });
const stoppedFrame = frames.shift();
assert(stoppedFrame); stoppedFrame();
assert.equal(frames.length, 0, 'A late frame cannot restart display after completion or disposal');
console.log('PASS adaptive streaming display, Unicode, complete-text storage, terminal flush and frame cancellation');
