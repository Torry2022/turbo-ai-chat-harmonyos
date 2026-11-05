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
  atEnd = false; instance.updateChatAutoScroll(); assert(!follow);
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
