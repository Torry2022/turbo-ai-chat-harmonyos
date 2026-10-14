// Run: node scripts/test_chat_history.cjs <path/to/typescript.js>
// Executes the real ArkTS state/storage code with a host file-I/O adapter.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(process.argv[2] || 'typescript');
const project = path.resolve(__dirname, '..');
const temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'turbo-chat-history-'));
let rejectRename = false;
const fileIo = {
  OpenMode: { READ_ONLY: 'r', WRITE_ONLY: 1, CREATE: 2, TRUNC: 4 },
  openSync: (name, mode) => ({ fd: fs.openSync(name, mode === 'r' ? 'r' : 'w') }),
  closeSync: file => fs.closeSync(typeof file === 'number' ? file : file.fd),
  readText: async name => fs.readFileSync(name, 'utf8'),
  listFile: async name => fs.readdirSync(name),
  access: async name => fs.existsSync(name),
  mkdir: async name => fs.mkdirSync(name, { recursive: true }),
  stat: async name => fs.statSync(name),
  statSync: name => fs.statSync(name),
  write: async (fd, text) => fs.writeSync(fd, text),
  fsync: async fd => fs.fsyncSync(fd),
  copyFile: async (fd, name) => fs.writeFileSync(name, fs.readFileSync(fd)),
  unlink: async name => fs.unlinkSync(name),
  rmdir: async name => fs.rmdirSync(name),
  rename: async (source, target) => {
    if (rejectRename && target.endsWith('/conversation.json')) {
      rejectRename = false;
      throw new Error('injected replacement failure');
    }
    fs.renameSync(source, target);
  }
};
const tests = [];
const hypium = {
  describe: (_name, register) => register(),
  it: (name, _flags, run) => tests.push({ name, run }),
  expect: value => ({
    assertEqual: expected => assert.equal(value, expected),
    assertTrue: () => assert.equal(value, true),
    assertFalse: () => assert.equal(value, false),
    assertUndefined: () => assert.equal(value, undefined),
    assertNull: () => assert.equal(value, null),
    assertContain: part => assert.ok(value.includes(part))
  })
};
const sdkStub = new Proxy(function () {}, {
  get: (_target, key) => key === 'then' ? undefined : sdkStub,
  construct: () => sdkStub,
  apply: () => sdkStub
});
const cache = new Map();
function load(filename) {
  filename = path.resolve(filename);
  if (cache.has(filename)) return cache.get(filename).exports;
  const module = { exports: {} };
  cache.set(filename, module);
  const source = fs.readFileSync(filename, 'utf8');
  const result = ts.transpileModule(source, { compilerOptions: {
    module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020,
    experimentalDecorators: true, esModuleInterop: true
  }});
  const requireSource = name => {
    if (name.startsWith('.')) return load(path.resolve(path.dirname(filename), name + '.ets'));
    if (name === '@ohos.file.fs') return fileIo;
    if (name === '@ohos/hypium') return hypium;
    if (name === '@kit.ArkTS') return { buffer: Buffer };
    return sdkStub;
  };
  vm.runInNewContext(result.outputText, {
    module, exports: module.exports, require: requireSource, console, ArrayBuffer, Buffer,
    setTimeout, clearTimeout, setInterval, clearInterval,
    Observed: type => type, Scroller: class {}, $r: name => name
  }, { filename });
  return module.exports;
}
function add(name, run) { tests.push({ name, run }); }
const ets = path.join(project, 'entry/src/main/ets');
const { ChatSession } = load(path.join(ets, 'state/ChatSession.ets'));
const { ChatHistoryService } = load(path.join(ets, 'services/ChatHistoryService.ets'));
const { conversationTitle, historyGroup } = load(path.join(ets, 'models/ChatHistoryTypes.ets'));
function conversation(id = 'c-test-1') {
  const session = new ChatSession();
  session.prepareModel('model-a', '模型甲');
  session.appendMessage('user', '问题一', '', true);
  session.appendMessage('assistant', '<think>思考</think>回答一。', '', true);
  return { version: 1, id, title: '测试对话', createdAt: 1000, updatedAt: 2000, messages: session.messages };
}
add('cross-model context and message metadata survive every update', () => {
  const session = new ChatSession();
  session.prepareModel('a', '模型甲');
  session.appendMessage('user', '旧问题');
  const first = session.appendMessage('assistant', '<think>旧思考</think>旧回答。');
  const timestamp = session.messages[1].createdAt;
  session.resetForModelSwitch('模型乙');
  session.prepareModel('b', '模型乙');
  assert.equal(session.messages.length, 3);
  assert.equal(session.messages[2].kind, 'notice');
  session.toggleThinkingExpanded(first);
  session.updateMessage(first, '<think>旧思考</think>旧回答。');
  session.appendToMessage(first, '');
  assert.equal(session.messages[1].modelName, '模型甲');
  assert.equal(session.messages[1].createdAt, timestamp);
  if (session.setKnowledgeReferences) {
    session.setKnowledgeReferences(first, [{ documentId: 'd', documentName: '资料', text: '原文', score: 0.9 }]);
    session.toggleReferencesExpanded(first);
    assert.equal(session.messages[1].modelName, '模型甲');
    assert.equal(session.messages[1].knowledgeReferences[0].text, '原文');
  }
  const turns = session.composeChatTurns('system', '新问题', 6);
  assert.equal(turns.length, 4);
  assert.equal(turns[1].content, '旧问题');
  assert.equal(turns[2].content, '旧回答。');
});
add('interrupted restoration excludes incomplete context and recovers IDs', () => {
  const session = new ChatSession();
  const messages = conversation().messages;
  messages[1].generationState = 'generating';
  session.restore(messages);
  assert.equal(session.messages[1].generationState, 'interrupted');
  assert.equal(session.messages[1].includeInContext, false);
  assert.equal(session.composeChatTurns('system', 'new', 6).length, 2);
  assert.equal(session.appendMessage('user', 'next'), 3);
});
add('titles and calendar groups respect unicode and local days', () => {
  assert.equal(conversationTitle('  第一行\n 第二行  '), '第一行 第二行');
  assert.equal(Array.from(conversationTitle('😀'.repeat(40))).length, 32);
  const now = new Date(2026, 9, 13, 12).getTime();
  assert.equal(historyGroup(new Date(2026, 9, 13, 0).getTime(), now), '今天');
  assert.equal(historyGroup(new Date(2026, 9, 12, 23).getTime(), now), '昨天');
  assert.equal(historyGroup(new Date(2026, 9, 7, 12).getTime(), now), '近七天');
  assert.equal(historyGroup(new Date(2026, 9, 6, 12).getTime(), now), '更早');
});
add('persistent snapshots, restart, rename and backup recovery', async () => {
  const directory = path.join(temporary, 'roundtrip');
  const service = new ChatHistoryService();
  await service.initialize(directory);
  const record = conversation();
  const pending = service.save(record);
  record.messages[1].content = 'changed after scheduling';
  await pending;
  assert.equal((await service.load(record.id)).messages[1].content, '<think>思考</think>回答一。');
  await service.rename(record.id, '新名称');
  const restarted = new ChatHistoryService();
  const index = await restarted.initialize(directory);
  assert.equal(index.activeId, record.id);
  assert.equal(restarted.list()[0].title, '新名称');
  const recordPath = path.join(directory, 'chat-history', record.id, 'conversation.json');
  fs.writeFileSync(recordPath, '{broken');
  assert.equal((await restarted.load(record.id)).title, '测试对话');
  assert.ok(fs.readdirSync(path.dirname(recordPath)).some(name => name.includes('.invalid-')));
  rejectRename = true;
  await assert.rejects(restarted.save(record), /replacement failure/);
  assert.equal((await restarted.load(record.id)).messages[1].content, '<think>思考</think>回答一。');
});
add('image copies persist independently; missing images retain text and retry', async () => {
  const directory = path.join(temporary, 'images');
  const service = new ChatHistoryService();
  await service.initialize(directory);
  const record = conversation('c-image-1');
  const source = path.join(temporary, 'picked-image.png');
  record.messages[0].imageUri = source;
  await assert.rejects(service.save(record), /图片未能保存/);
  const unavailable = await service.load(record.id);
  assert.equal(unavailable.messages[0].content, '问题一');
  assert.equal(unavailable.messages[0].imageUnavailable, true);
  fs.writeFileSync(source, Buffer.from([1, 2, 3, 4]));
  await service.save(record);
  fs.unlinkSync(source);
  const saved = await service.load(record.id);
  assert.deepEqual([...fs.readFileSync(saved.messages[0].imageUri)], [1, 2, 3, 4]);
  await service.save(record); // Original picker URI has expired; the saved copy is reused.
  await service.remove(record.id);
  assert.equal(fs.existsSync(saved.messages[0].imageUri), false);
  await assert.rejects(service.save(record), /已删除/);
});
add('clear removes damaged records; a corrupt index cannot resurrect deletion', async () => {
  const directory = path.join(temporary, 'clear');
  const service = new ChatHistoryService();
  await service.initialize(directory);
  await service.save(conversation('c-first'));
  await service.save(conversation('c-second'));
  const damaged = path.join(directory, 'chat-history/c-damaged');
  fs.mkdirSync(damaged);
  fs.writeFileSync(path.join(damaged, 'conversation.json'), '{');
  await service.clear();
  fs.writeFileSync(path.join(directory, 'chat-history/index.json'), '{');
  const restarted = new ChatHistoryService();
  await restarted.initialize(directory);
  assert.equal(restarted.list().length, 0);
  assert.equal(fs.existsSync(damaged), false);
  assert.equal(fs.readdirSync(path.join(directory, 'chat-history')).filter(name => name.startsWith('c-')).length, 0);
});
add('history actions preserve loaded model and reject busy transitions', async () => {
  const { ChatViewModel } = load(path.join(ets, 'state/ChatViewModel.ets'));
  const view = new ChatViewModel();
  view.notify = view.notifyAndScroll = view.notifyAndMaybeScroll = () => {};
  view.historyReady = true;
  view.loaded = true;
  await view.historyService.initialize(path.join(temporary, 'viewmodel'));
  await view.historyService.save(conversation('c-view-1'));
  const modelId = view.selectedModelId;
  assert.equal(await view.openConversation('c-view-1'), true);
  assert.equal(view.loaded, true);
  assert.equal(view.selectedModelId, modelId);
  view.busy = true;
  assert.equal(await view.openConversation('c-other'), false);
  view.newChat();
  assert.equal(view.activeConversationId, 'c-view-1');
  await view.deleteConversation();
  assert.equal(view.activeConversationId, 'c-view-1');
  view.busy = false;
  view.session.appendMessage('user', 'next question');
  view.generating = true;
  const id = view.session.appendMessage('assistant', '');
  view.syncMessages();
  view.generating = false;
  view.session.updateMessage(id, '回答。');
  view.session.markGeneration(id, 'complete');
  await view.deleteConversation('c-view-1');
  assert.equal(view.activeConversationId, '');
  assert.equal(view.historyService.list().length, 0);
  assert.equal(view.loaded, true);
  await new Promise(resolve => setTimeout(resolve, 1100));
  assert.equal(view.historyService.list().length, 0);
  view.setStatus('加载失败：code=1 name=Error 原因', 'error');
  assert.equal(view.headerColor(), 'app.color.status_error_alt');
  if ('layaReady' in view) {
    view.loaded = false;
    view.layaReady = true;
    view.layaRuntimeState = 'loaded';
    assert.ok(view.headerStatus().startsWith('加载失败'));
    view.setStatus('模型未加载');
    assert.equal(view.headerStatus(), 'Laya 已加载');
    view.layaRuntimeState = 'idle';
    assert.equal(view.headerStatus(), '模型未加载');
    view.layaRuntimeState = 'running';
    assert.equal(view.headerStatus(), '正在使用 Laya 判定...');
    view.layaRuntimeState = 'idle';
    view.benchmarkRunning = true;
    view.benchmarkMessage = '轮次间冷却 10s';
    assert.equal(view.headerStatus(), '正在等待下一轮 Benchmark...');
  }
});
for (const name of ['ChatSession', 'Thinking', 'Markdown', 'GenerationWorkflow', 'GenerationMetrics', 'OpenAiApiServer', 'Knowledge', 'KnowledgeRelations']) {
  const test = path.join(project, 'entry/src/ohosTest/ets/test', name + '.test.ets');
  if (fs.existsSync(test)) load(test).default();
}
(async () => {
  let passed = 0;
  try {
    for (const test of tests) {
      await test.run();
      passed++;
      console.log('PASS', test.name);
    }
    console.log(`${passed} state/storage/context/regression checks passed.`);
  } finally {
    const resolved = fs.realpathSync(temporary);
    assert.ok(resolved.startsWith(fs.realpathSync(os.tmpdir()) + path.sep));
    assert.ok(path.basename(resolved).startsWith('turbo-chat-history-'));
    fs.rmSync(resolved, { recursive: true, force: true });
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
