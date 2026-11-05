// node scripts/test_chat_scroll.cjs <path/to/typescript.js>
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(process.argv[2] || 'typescript');
const source = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/components/ChatTab.ets'), 'utf8')
  .replace(/\r\n/g, '\n').replace('export struct ChatTab', 'export class ChatTab');
const ast = ts.createSourceFile('ChatTab.ts', source, ts.ScriptTarget.Latest, true);
const chat = ast.statements.find(ts.isClassDeclaration);
const names = ['onChatWillScroll', 'updateChatAutoScroll'];
const methods = chat.members.filter(member => names.includes(member.name?.text)).map(member => member.getText(ast));
assert.equal(methods.length, names.length, 'The list must restore follow mode after a manual scroll reaches the end');
const ScrollSource = { DRAG: 0, FLING: 1, EDGE_EFFECT: 2, OTHER_USER_INPUT: 3, SCROLL_BAR: 4,
  SCROLL_BAR_FLING: 5, SCROLLER: 6, SCROLLER_ANIMATION: 7 };
const context = { exports: {}, ScrollSource };
vm.runInNewContext(ts.transpileModule(`export class ChatScroll { ${methods.join('\n')} }`, {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }
}).outputText, context);
const instance = new context.exports.ChatScroll();
instance.active = true;
let atEnd = false, follow = true, highlighted = true;
instance.viewModel = { chatScroller: { isAtEnd: () => atEnd },
  pauseChatAutoScroll: () => { follow = false; },
  resumeChatAutoScroll: () => { follow = true; highlighted = false; } };
for (const source of [ScrollSource.DRAG, ScrollSource.FLING, ScrollSource.OTHER_USER_INPUT,
  ScrollSource.SCROLL_BAR, ScrollSource.SCROLL_BAR_FLING]) {
  follow = true; atEnd = false; instance.keepChatBottomOnResize = true;
  instance.onChatWillScroll(12, source);
  assert(!follow, 'Manual scrolling pauses follow mode');
  assert(!instance.keepChatBottomOnResize, 'Manual scrolling cancels keyboard anchoring');
  instance.updateChatAutoScroll(); assert(!follow, 'Reading history stays paused');
  atEnd = true; instance.updateChatAutoScroll();
  assert(follow, 'Manually returning to the bottom resumes follow mode');
  atEnd = false; instance.updateChatAutoScroll();
  assert(follow, 'An animated follow update cannot be mistaken for continued manual history reading');
  instance.onChatWillScroll(-12, source); instance.updateChatAutoScroll();
  assert(!follow, 'A new manual scroll pauses following again');
  instance.chatUserScrolling = false;
}
for (const source of [ScrollSource.SCROLLER, ScrollSource.SCROLLER_ANIMATION, ScrollSource.EDGE_EFFECT]) {
  instance.chatUserScrolling = false; follow = false; atEnd = true; highlighted = true;
  instance.onChatWillScroll(12, source); instance.updateChatAutoScroll();
  assert(!follow, 'Programmatic search/resize scrolling cannot resume follow mode');
  assert(highlighted, 'Programmatic scrolling preserves the search highlight');
}
instance.chatUserScrolling = false; follow = false; atEnd = true;
instance.onChatWillScroll(0, ScrollSource.OTHER_USER_INPUT); instance.updateChatAutoScroll();
assert(!follow, 'A zero-offset callback must not resume text-selection pauses');
instance.active = false; instance.chatUserScrolling = true; instance.updateChatAutoScroll();
assert(!follow, 'Inactive chats cannot change follow mode');
assert(source.includes('.onDidScroll(() => this.updateChatAutoScroll())'));
assert(source.includes('.onScrollStop(() => {\n        this.updateChatAutoScroll()\n        this.chatUserScrolling = false'));
console.log('PASS manual bottom return resumes streaming follow, history/search/selection/resize stay paused');

const viewSource = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/state/ChatViewModel.ets'), 'utf8');
const viewAst = ts.createSourceFile('ViewModel.ts', viewSource, ts.ScriptTarget.Latest, true);
const view = viewAst.statements.find(ts.isClassDeclaration);
const scrollMethod = view.members.find(member => member.name?.text === 'scrollToBottom').getText(viewAst);
let queued = null, height = 500, offset = 0;
const calls = [];
const scrollContext = { exports: {}, Math, ScrollAlign: { START: 'start', END: 'end' }, Edge: { Bottom: 'bottom' },
  setTimeout: callback => { assert.equal(queued, null); queued = callback; } };
vm.runInNewContext(ts.transpileModule(`export class StreamScroll { ${scrollMethod} }`, {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }
}).outputText, scrollContext);
const follower = new scrollContext.exports.StreamScroll();
Object.assign(follower, { autoScrollPending: false, autoScrollSmooth: false, streamScrollEnd: -1,
  chatScrollTargetId: 0, chatAutoScrollEnabled: true, messages: [{ id: 1 }, { id: 2 }] });
follower.chatScroller = {
  getItemRect: () => ({ y: -offset, height }), currentOffset: () => ({ yOffset: offset }),
  scrollToIndex: (index, smooth, align) => calls.push({ index, smooth, align }),
  scrollEdge: () => calls.push('edge')
};
function flushScroll() { const callback = queued; queued = null; assert(callback); callback(); }
follower.scrollToBottom(true); flushScroll();
assert.deepEqual(calls.at(-1), { index: 1, smooth: true, align: 'end' });
offset = 20;
follower.scrollToBottom(true); flushScroll();
assert.equal(calls.length, 1, 'An in-flight scroll does not restart for unchanged content height');
height += 21;
follower.scrollToBottom(true); flushScroll();
assert.equal(calls.length, 2, 'A new line updates the animated target');
follower.scrollToBottom(true);
follower.chatAutoScrollEnabled = false;
flushScroll();
assert.equal(calls.length, 2, 'Touching history cancels a queued streaming scroll');
follower.chatAutoScrollEnabled = true;
follower.scrollToBottom(true);
follower.chatScrollTargetId = 1;
follower.chatAutoScrollEnabled = false;
follower.scrollToBottom();
flushScroll();
assert.deepEqual(calls.at(-1), { index: 0, smooth: false, align: 'start' }, 'Explicit search navigation overrides pending following');
follower.chatScrollTargetId = 0;
follower.chatAutoScrollEnabled = true;
follower.scrollToBottom();
follower.scrollToBottom(true);
flushScroll();
assert.equal(calls.at(-1).smooth, false, 'Sending and explicit navigation retain immediate positioning');
console.log('PASS streaming follow retargets on height changes, manual interruption and search retain priority');
