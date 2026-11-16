// node scripts/test_chat_archive.cjs <path/to/typescript.js>
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const vm = require('node:vm');
const { execFileSync } = require('node:child_process');
const ts = require(process.argv[2] || 'typescript');
const modules = new Map();
function load(name) {
  if (modules.has(name)) return modules.get(name);
  const source = fs.readFileSync(path.resolve(__dirname, '../entry/src/main/ets/utils', name + '.ets'), 'utf8');
  const module = { exports: {} };
  vm.runInNewContext(ts.transpileModule(source, { compilerOptions: {
    module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020
  }}).outputText, { module, exports: module.exports, Uint8Array, DataView,
    require: name => load(name.replace('./', '')) });
  modules.set(name, module.exports);
  return module.exports;
}
const { inspectChatArchiveZip } = load('chatArchiveZip');
const { conversationMarkdown, parseChatArchive } = load('chatArchive');
const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'turbo-chat-archive-'));
function inspect(buffer) {
  return inspectChatArchiveZip(buffer.length, (offset, length) => {
    assert(offset >= 0 && offset + length <= buffer.length);
    return new Uint8Array(buffer.subarray(offset, offset + length));
  });
}
function zip(names, symlink = false) {
  const target = path.join(directory, 'fixture.zip');
  execFileSync(process.env.PYTHON || 'python', ['-c', `
import sys,json,zipfile
with zipfile.ZipFile(sys.argv[1], 'w', compression=zipfile.ZIP_DEFLATED) as archive:
 for name in json.loads(sys.argv[2]):
  info=zipfile.ZipInfo(name)
  info.filename=name
  info.create_system=3
  info.external_attr=(0o120777 if sys.argv[3]=='true' else 0o100600)<<16
  archive.writestr(info, b'fixture')
`, target, JSON.stringify(names), String(symlink)]);
  return fs.readFileSync(target);
}
try {
  assert.equal(inspect(zip(['manifest.json', 'images/0-1'])), 14);
  assert.equal(inspect(zip(['backup/', 'backup/manifest.json', 'backup/images/0-1'])), 21);
  for (const names of [
    ['manifest.json', '../outside'], ['manifest.json', '/absolute'],
    ['manifest.json', 'images\\0-1'], ['manifest.json', 'images/0-1.exe'],
    ['manifest.json', 'manifest.json'], ['images/0-1'], ['manifest.json', 'backup/images/0-1']
  ]) assert.throws(() => inspect(zip(names)), JSON.stringify(names));
  assert.throws(() => inspect(zip(['manifest.json'], true)));
  const bad = zip(['manifest.json']); bad[30] = 0x78;
  assert.throws(() => inspect(bad));
  assert.throws(() => inspect(zip(['manifest.json']).subarray(0, 16)));
  console.log('PASS ZIP traversal, symlinks, duplicate entries, root consistency, local headers and truncation');
  const record = { version: 1, id: 'c-source', title: '测试\n标题', createdAt: 1, updatedAt: 2, messages: [
    { id: 1, role: 'user', kind: 'message', content: '问题', imageUri: 'images/0-1', time: '12:00', includeInContext: true, thinkingExpanded: false },
    { id: 2, role: 'assistant', kind: 'message', content: '```\n  原文\n```', imageUri: '', modelName: '模型', time: '12:01', includeInContext: true, thinkingExpanded: false },
    { id: 3, role: 'assistant', kind: 'notice', content: '加载通知', imageUri: '', time: '12:00', includeInContext: false, thinkingExpanded: false }
  ] };
  const markdown = conversationMarkdown(record);
  assert(markdown.includes('![图片](images/0-1)'));
  assert(markdown.includes('```\n  原文\n```'));
  assert(!markdown.includes('加载通知'));
  assert(markdown.startsWith('# 测试 标题\n'));
  const archive = { format: 'turbo-ai-chat-history', version: 1, createdAt: 3, conversations: [record] };
  assert.equal(parseChatArchive(JSON.stringify(archive)).conversations.length, 1);
  for (const uri of ['../../data', '/data/secret', 'file://secret', 'images/0-1/../../secret']) {
    const invalid = JSON.parse(JSON.stringify(archive)); invalid.conversations[0].messages[0].imageUri = uri;
    assert.throws(() => parseChatArchive(JSON.stringify(invalid)));
  }
  console.log('PASS Markdown fidelity and portable archive validation');
} finally {
  assert(path.basename(directory).startsWith('turbo-chat-archive-'));
  fs.rmSync(directory, { recursive: true, force: true });
}
