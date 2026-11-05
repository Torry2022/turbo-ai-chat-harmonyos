// node scripts/test_streaming_text_fade.cjs <path/to/typescript.js>
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(process.argv[2] || 'typescript');
const root = path.resolve(__dirname, '../entry/src/main/ets');
const compilerOptions = { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 };
const modules = new Map();
function load(name) {
  if (modules.has(name)) return modules.get(name);
  const file = path.join(root, 'utils', name + (name === 'graphemeBoundaries' ? '.js' : '.ets'));
  const context = { exports: {}, require: dependency => load(dependency.slice(2)) };
  vm.runInNewContext(ts.transpileModule(fs.readFileSync(file, 'utf8'), { compilerOptions }).outputText, context);
  modules.set(name, context.exports);
  return context.exports;
}
const { StreamingTextFade, STREAM_TEXT_FADE_MS } = load('streamingTextFade');
const { parseInlineMarkdown } = load('markdown');
const { graphemeBoundaries } = load('graphemeBoundaries');
const plain = text => [{ text, bold: false }];
const fade = new StreamingTextFade();
fade.update('你好', true, 1000);
assert(fade.active(1000));
assert.equal(fade.spans(plain('你好'), 1000).map(part => part.span.text).join(''), '你好');
assert.equal(fade.spans(plain('你好'), 1000)[0].opacity, 0);
assert(fade.spans(plain('你好'), 1090)[0].opacity > 0.5);
assert(fade.spans(plain('你好'), 1090)[0].opacity < 1);
assert(!fade.active(1000 + STREAM_TEXT_FADE_MS + 48));
assert.equal(fade.spans(plain('你好'), 1300).length, 1, 'Completed text is coalesced');
fade.update('你好世界', true, 1400);
const appended = fade.spans(plain('你好世界'), 1400);
assert.equal(appended[0].span.text, '你好');
assert.equal(appended[0].opacity, 1, 'Old text must not replay its fade');
assert.equal(appended[1].opacity, 0);
fade.update('你好世界', false, 1401);
assert(!fade.active(1401), 'Completion, stop, failure and selection flush the fade');
assert(fade.spans(plain('你好世界'), 1401).every(part => part.opacity === 1));
fade.update('另一版回答', true, 1500);
assert(!fade.active(1500), 'A discontinuity does not animate already-visible text again');

for (const text of ['👩🏽‍💻你好', 'e\u0301 与 🇨🇳', '中文 **加粗** 和 `code()`', '[链接](https://example.com)']) {
  const inline = parseInlineMarkdown(text);
  const visible = inline.map(span => span.text).join('');
  const state = new StreamingTextFade();
  state.update(visible, true, 2000);
  const ends = new Set([0, ...graphemeBoundaries(visible)]);
  for (const now of [2000, 2016, 2090, 2228]) {
    const parts = state.spans(inline, now);
    assert.equal(parts.map(part => part.span.text).join(''), visible);
    for (const part of parts) {
      assert(ends.has(part.start));
      assert(ends.has(part.start + part.span.text.length));
      assert(part.opacity >= 0 && part.opacity <= 1);
      if (part.span.code) assert.equal(part.opacity, 1, 'Inline code bypasses fading');
      if (part.span.link) assert.equal(part.span.link, 'https://example.com');
    }
  }
}

// Replay the exact unclosed bold sequence visible at 18–19 seconds in the user recording.
for (const marker of ['**', '***', '*', '~~']) {
  const complete = marker + '本地 AI 助手' + marker;
  for (let length = marker.length; length <= complete.length; length++) {
    const source = complete.slice(0, length);
    const spans = parseInlineMarkdown(source, true);
    const expected = source.slice(marker.length).replace(/[\*~]+$/, '');
    assert.equal(spans.map(span => span.text).join(''), expected, source);
    if (expected) {
      if (marker.includes('*') && marker.length > 1) assert(spans.every(span => span.bold));
      if (marker === '*') assert(spans.every(span => span.italic));
      if (marker === '~~') assert(spans.every(span => span.strikethrough));
    }
  }
}
assert.equal(parseInlineMarkdown('**未闭合', false).map(s => s.text).join(''), '**未闭合');
assert.equal(parseInlineMarkdown('**未闭合', true).map(s => s.text).join(''), '未闭合');
assert.equal(parseInlineMarkdown('例如**隐私保护', true).map(s => s.text).join(''), '例如隐私保护');
for (const source of ['2 * 3 = 6', 'value*pointer', '这是普通文本', '`**代码中的星号`']) {
  assert.equal(parseInlineMarkdown(source, true).map(s => s.text).join(''),
    parseInlineMarkdown(source, false).map(s => s.text).join(''));
}

const component = fs.readFileSync(path.join(root, 'components/StreamingText.ets'), 'utf8').replace(/\r\n/g, '\n');
assert(component.includes('.copyOption(CopyOptions.LocalDevice)'));
assert(component.includes('.textSelectable(TextSelectableMode.SELECTABLE_FOCUSABLE)'));
assert(component.includes('aboutToDisappear(): void {\n    this.stopFadeTimer()'));
assert(!component.includes('notifyAndMaybeScroll'), 'Paint ticks stay local to the native Text');
const bubble = fs.readFileSync(path.join(root, 'components/MessageBubble.ets'), 'utf8').replace(/\r\n/g, '\n');
assert(bubble.includes('`${blockIndex}:${block.type}`'), 'Growing blocks retain their native nodes');
assert(!bubble.includes('JSON.stringify(block)'));

// Run the component's actual update/teardown methods with a deterministic paint clock.
let now = 3000, tick = null;
const instanceSource = component.slice(component.indexOf('export struct StreamingText'),
  component.indexOf('  build()')).replace('export struct', 'export class')
  .replace(/@Prop|@State|@Watch\('[^']*'\)/g, '') + '}';
const context = { exports: {}, StreamingTextFade, parseInlineMarkdown,
  $r: name => name, Date: { now: () => now },
  setInterval: (callback, interval) => {
    assert.equal(interval, 16);
    assert.equal(tick, null);
    tick = callback;
    return 1;
  },
  clearInterval: () => { tick = null; } };
vm.runInNewContext(ts.transpileModule(instanceSource, { compilerOptions }).outputText, context);
const nativeText = new context.exports.StreamingText();
nativeText.text = '实机前的颜色动画回归';
nativeText.streaming = true;
nativeText.aboutToAppear();
assert(tick);
assert.equal(nativeText.parts[0].opacity, 0);
now += 90; tick();
assert(nativeText.parts[0].opacity > 0 && nativeText.parts[0].opacity < 1);
nativeText.streaming = false;
nativeText.updateText();
assert.equal(tick, null);
assert(nativeText.parts.every(part => part.opacity === 1));
nativeText.text += '再次生成';
nativeText.streaming = true;
nativeText.updateText();
assert(tick);
nativeText.aboutToDisappear();
assert.equal(tick, null, 'Unmounting cannot leave a paint timer running');
console.log('PASS incremental text fade, stable prefixes, Unicode, Markdown, terminal flush and native selection');
