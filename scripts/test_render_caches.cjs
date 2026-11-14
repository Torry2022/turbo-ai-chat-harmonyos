// node scripts/test_render_caches.cjs <path/to/typescript.js>
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(process.argv[2] || 'typescript');
function load(name) {
  const source = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/utils', name + '.ets'), 'utf8');
  const context = {exports: {}};
  vm.runInNewContext(ts.transpileModule(source, {compilerOptions: {
    module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020
  }}).outputText, context);
  return context.exports;
}
const markdown = load('markdown');
const thinking = load('thinking');
for (const [name, parse, limit] of [
  ['inline Markdown', markdown.parseInlineMarkdown, 360],
  ['block Markdown', markdown.parseLightMarkdown, 160],
  ['thinking blocks', thinking.parseAssistantText, 240],
]) {
  const first = parse('entry-0');
  const second = parse('entry-1');
  const third = parse('entry-2');
  for (let i = 3; i < limit; i++) parse('entry-' + i);
  parse('entry-' + limit);
  assert.equal(parse('entry-1'), second, name + ' keeps unaffected cached objects at capacity');
  assert.notEqual(parse('entry-0'), first, name + ' evicts the oldest entry');
  assert.equal(parse('entry-2'), third, name + ' stays reusable after another insertion');
  console.log('PASS', name, 'bounded incremental eviction');
}

const source = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/components/ChatTab.ets'), 'utf8');
const ast = ts.createSourceFile('chat.ts', source.replace('export struct ChatTab', 'class ChatTab'), ts.ScriptTarget.Latest, true);
const component = ast.statements.find(n => ts.isClassDeclaration(n));
const members = component.members.filter(n => n.name &&
  ['messageSnapshots', 'snapshotVersion', 'snapshotConversationId', 'messageForRender'].includes(n.name.getText(ast)));
const Chat = vm.runInNewContext(ts.transpileModule(`class Chat {${members.map(n => n.getText(ast)).join('\n')}}; Chat`,
  { compilerOptions: { target: ts.ScriptTarget.ES2020 } }).outputText, {});
const chat = new Chat();
let message = {id: 1, role: 'assistant', content: 'before', answerVersionIndex: 0};
chat.viewModel = {activeConversationId: 'a', messages: [message], messageContentForDisplay: m => m.content};
const firstSnapshot = chat.messageForRender(message, 1);
assert.equal(chat.messageForRender(message, 1), firstSnapshot, 'Layout and scrolling reuse the message snapshot');
message.content = 'streamed';
assert.equal(chat.messageForRender(message, 2).content, 'streamed', 'Streaming notifications refresh visible text');
message.answerVersionIndex = 1;
assert.equal(chat.messageForRender(message, 3).answerVersionIndex, 1, 'Answer version switches refresh the snapshot');
message = {id: 1, role: 'user', content: 'other conversation'};
chat.viewModel.activeConversationId = 'b'; chat.viewModel.messages = [message];
assert.equal(chat.messageForRender(message, 3).content, 'other conversation', 'Conversation IDs isolate reused message IDs');
assert.equal(chat.messageSnapshots.size, 1, 'Previous conversation snapshots are released');
console.log('PASS message snapshots survive scrolling and refresh on streaming, version and conversation changes');
