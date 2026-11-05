// node scripts/test_keyboard_layout.cjs <path/to/typescript.js>
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(process.argv[2] || 'typescript');
const source = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/pages/Index.ets'), 'utf8')
  .replace('struct Index', 'class Index');
const ast = ts.createSourceFile('Index.ts', source, ts.ScriptTarget.Latest, true);
const entry = ast.statements.find(ts.isClassDeclaration);
const names = ['onKeyboardWillShow', 'onKeyboardWillHide', 'updateKeyboardVisibility'];
const methods = entry.members.filter(member => names.includes(member.name?.text)).map(member => member.getText(ast));
assert.equal(methods.length, 3);
let animations = [], insideAnimation = false;
const context = { exports: {}, Curve: { Linear: 'linear' },
  window: { WindowAnimationCurve: { LINEAR: 0, INTERPOLATION_SPRING: 1, CUBIC_BEZIER: 2 } },
  curves: {
    cubicBezierCurve: (...params) => ({ kind: 'bezier', params }),
    interpolatingSpring: (...params) => ({ kind: 'spring', params })
  } };
vm.runInNewContext(ts.transpileModule(`export class KeyboardLayout { ${methods.join('\n')} }`, {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }
}).outputText, context);
const page = new context.exports.KeyboardLayout();
let visible = false;
Object.defineProperty(page, 'keyboardVisible', {
  get: () => visible,
  set: next => {
    if (animations.length && animations.at(-1).expectAnimated) assert(insideAnimation);
    visible = next;
  }
});
page.getUIContext = () => ({ animateTo: (options, apply) => {
  animations.push({ options, expectAnimated: true });
  insideAnimation = true;
  try { apply(); } finally { insideAnimation = false; }
} });
const spring = { animated: true, config: { curve: 1, param: [0, 1, 342, 37] } };
page.onKeyboardWillShow(spring);
assert(visible);
assert.equal(animations[0].options.curve.kind, 'spring');
assert.deepEqual(animations[0].options.curve.params, [0, 1, 342, 37]);
const bezier = { animated: true, config: { curve: 2, duration: 320, param: [.2, 0, .2, 1] } };
page.onKeyboardWillHide(bezier);
assert(!visible);
assert.equal(animations[1].options.duration, 320);
assert.equal(animations[1].options.curve.kind, 'bezier');
assert.deepEqual(animations[1].options.curve.params, [.2, 0, .2, 1]);
page.onKeyboardWillHide(bezier);
assert.equal(animations.length, 2, 'Repeated events cannot restart layout motion');
page.onKeyboardWillShow({ animated: true, config: { curve: 0, duration: 180 } });
assert.equal(animations[2].options.curve, 'linear');
assert.equal(animations[2].options.duration, 180);
animations = [];
page.onKeyboardWillHide({ animated: false });
assert(!visible);
assert.equal(animations.length, 0, 'A nonanimated keyboard change stays immediate');
page.onKeyboardWillShow({});
assert(visible);
assert.equal(animations.length, 0);
for (const event of ['keyboardWillShow', 'keyboardWillHide']) {
  assert(source.includes(`.on('${event}'`));
  assert(source.includes(`.off('${event}'`));
}
assert(!source.includes(".on('keyboardHeightChange'"), 'Height notifications must not restore the tab inset early');

const chatSource = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/components/ChatTab.ets'), 'utf8')
  .replace('export struct ChatTab', 'export class ChatTab');
const chatAst = ts.createSourceFile('ChatTab.ts', chatSource, ts.ScriptTarget.Latest, true);
const chat = chatAst.statements.find(ts.isClassDeclaration);
const anchorMethods = chat.members.filter(member =>
  ['onKeyboardVisibilityChange', 'onChatViewportResize'].includes(member.name?.text)).map(member => member.getText(chatAst));
assert.equal(anchorMethods.length, 2);
context.Edge = { Bottom: 'bottom' };
vm.runInNewContext(ts.transpileModule(`export class ChatViewport { ${anchorMethods.join('\n')} }`, {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }
}).outputText, context);
const viewport = new context.exports.ChatViewport();
let atBottom = true, pins = 0;
viewport.active = true;
viewport.viewModel = { chatScroller: { isAtEnd: () => atBottom, scrollEdge: edge => {
  assert.equal(edge, 'bottom'); pins++;
} } };
viewport.onKeyboardVisibilityChange();
viewport.onChatViewportResize({ height: 600 }, { height: 320 });
assert.equal(pins, 1, 'The previous bottom stays anchored after the viewport shrinks');
viewport.onChatViewportResize({ height: 320 }, { height: 600 });
assert.equal(pins, 2, 'The bottom stays anchored when the viewport expands');
viewport.onChatViewportResize({ height: 600 }, { height: 600 });
viewport.onChatViewportResize({ height: 0 }, { height: 600 });
assert.equal(pins, 2, 'Initial layout and unchanged size do not trigger extra scrolling');
atBottom = false;
viewport.onKeyboardVisibilityChange();
viewport.onChatViewportResize({ height: 600 }, { height: 320 });
assert.equal(pins, 2, 'Reading earlier messages must not pull the reader to the bottom');
atBottom = true;
viewport.onKeyboardVisibilityChange();
viewport.keepChatBottomOnResize = false;
viewport.onChatViewportResize({ height: 600 }, { height: 320 });
assert.equal(pins, 2, 'Manual scrolling cancels the captured anchor');
viewport.active = false;
viewport.onKeyboardVisibilityChange();
viewport.onChatViewportResize({ height: 320 }, { height: 600 });
assert.equal(pins, 2, 'Inactive chat pages cannot scroll');
console.log('PASS keyboard layout follows native show/hide timing, curve parameters and interrupted motion');
