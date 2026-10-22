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
const preferenceStores = new Map();
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
    if (name === '@ohos.data.preferences') return { getPreferences: async (_context, name) => {
      if (!preferenceStores.has(name)) preferenceStores.set(name, new Map());
      const values = preferenceStores.get(name);
      return { get: async (key, fallback) => values.has(key) ? values.get(key) : fallback,
        put: async (key, value) => values.set(key, value), flush: async () => {} };
    } };
    if (name === '@ohos/hypium') return hypium;
    if (name === '@kit.ArkTS') return { buffer: Buffer };
    return sdkStub;
  };
  vm.runInNewContext(result.outputText, {
    module, exports: module.exports, require: requireSource, console, ArrayBuffer, Buffer,
    setTimeout, clearTimeout, setInterval, clearInterval,
    Observed: type => type, Scroller: class {}, ScrollAlign: { START: 0, END: 1 }, Edge: { Bottom: 1 }, $r: name => name
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
    assert.equal(view.headerStatus(), '正在执行决策...');
    view.layaRuntimeState = 'idle';
  }
  if ('benchmarkRunning' in view) {
    view.benchmarkRunning = true;
    view.benchmarkMessage = '轮次间冷却 10s';
    assert.equal(view.headerStatus(), '正在等待下一轮 Benchmark...');
  }
});
add('conversation drafts survive navigation and model switches', async () => {
  const { ChatViewModel } = load(path.join(ets, 'state/ChatViewModel.ets'));
  const view = new ChatViewModel();
  view.notify = view.notifyAndScroll = view.notifyAndMaybeScroll = () => {};
  view.historyReady = true;
  await view.historyService.initialize(path.join(temporary, 'drafts'));
  await view.historyService.save(conversation('c-draft-1'));
  await view.historyService.save(conversation('c-draft-2'));
  view.updateInputText('尚未发送的新对话草稿');
  assert.equal(await view.openConversation('c-draft-1'), true);
  view.updateInputText('对话一草稿');
  assert.equal(await view.openConversation('c-draft-2'), true);
  view.updateInputText('对话二草稿');
  assert.equal(await view.openConversation('c-draft-1'), true);
  assert.equal(view.inputText, '对话一草稿');
  const alternate = view.modelProfiles().find(profile => profile.id !== view.selectedModelId);
  assert.ok(alternate);
  view.switchModel(alternate.id);
  assert.equal(view.inputText, '对话一草稿');
  await view.beginNewConversation();
  assert.equal(view.inputText, '尚未发送的新对话草稿');
});
add('generation failures retain streamed text and failed state', async () => {
  const { ChatViewModel } = load(path.join(ets, 'state/ChatViewModel.ets'));
  const view = new ChatViewModel();
  view.notify = view.notifyAndScroll = view.notifyAndMaybeScroll = () => {};
  view.historyReady = true;
  view.loaded = true;
  await view.historyService.initialize(path.join(temporary, 'generation-failure'));
  view.generationWorkflow = {
    run: (_request, callbacks) => {
      callbacks.onStream({ text: '已经生成的部分回答', characterCount: 9 });
      return Promise.reject(new Error('测试故障'));
    },
    stop: () => {}
  };
  view.updateInputText('测试问题');
  await view.sendMessage();
  await new Promise(resolve => setTimeout(resolve, 0));
  const answer = view.messages[view.messages.length - 1];
  assert.equal(answer.content, '已经生成的部分回答');
  assert.equal(answer.includeInContext, false);
  assert.equal(answer.generationState, 'failed');
  await view.flushHistory();
  const saved = await view.historyService.load(view.activeConversationId);
  const savedAnswer = saved.messages[saved.messages.length - 1];
  assert.equal(savedAnswer.content, '已经生成的部分回答');
  assert.equal(savedAnswer.generationState, 'failed');
});

async function actionView(name) {
  const { ChatViewModel } = load(path.join(ets, 'state/ChatViewModel.ets'));
  const view = new ChatViewModel();
  view.notify = view.notifyAndScroll = view.notifyAndMaybeScroll = view.refreshStats = () => {};
  view.historyReady = view.loaded = true;
  await view.historyService.initialize(path.join(temporary, name));
  view.session.prepareModel('old-model', '旧模型');
  view.session.appendMessage('user', '更早的问题');
  view.session.appendMessage('assistant', '更早的回答。');
  const image = path.join(temporary, name + '-image');
  fs.writeFileSync(image, 'original image');
  view.session.appendMessage('user', '最后的问题', image);
  const answer = view.session.appendMessage('assistant', '最后的旧回答。');
  view.session.markGeneration(answer, 'complete');
  view.messages = view.session.messages;
  view.currentModel = () => ({ id: 'new-model', shortName: '新模型', supportsImage: true, systemPrompt: 'system' });
  view.currentContextMessageLimit = () => 6;
  return view;
}
function finished(answer = '新的回答。') {
  return { answer, includeInContext: true, status: '生成完成',
    result: { stopReason: 'eos', text: answer, generatedTokens: 3 },
    perfMetrics: { ttft: 1, tpot: 2, tokensPerSec: 3, tokens: 3 } };
}
add('regeneration replaces only the last answer and uses current model without duplicating context', async () => {
  const view = await actionView('regenerate');
  const originalQuestion = view.session.lastQuestion();
  const oldAnswer = view.session.lastAnswer();
  let request, resolve;
  view.generationWorkflow = { run: value => { request = value; return new Promise(done => { resolve = done; }); } };
  view.updateInputText('保留未发送草稿');
  view.selectedImageUri = 'file://draft-image';
  await view.regenerateAnswer(oldAnswer.id);
  assert.equal(view.busy, true);
  assert.equal(request.imageUri, originalQuestion.imageUri);
  assert.equal(request.turns.length, 4);
  assert.deepEqual(Array.from(request.turns, item => item.content), ['system', '更早的问题', '更早的回答。', '最后的问题']);
  assert.equal(view.session.lastQuestion().id, originalQuestion.id);
  assert.equal(view.session.lastQuestion().createdAt, originalQuestion.createdAt);
  assert.equal(view.session.lastAnswer().modelId, 'new-model');
  assert.equal(view.messages.some(item => item.id === oldAnswer.id), false);
  assert.equal(view.inputText, '保留未发送草稿');
  assert.equal(view.selectedImageUri, 'file://draft-image');
  await view.regenerateAnswer(view.session.lastAnswer().id);
  assert.equal(view.messages.filter(item => item.role === 'user').length, 2);
  resolve(finished());
  await new Promise(done => setTimeout(done, 0));
  await view.flushHistory();
  const record = await view.historyService.load(view.activeConversationId);
  assert.equal(record.messages.at(-1).content, '新的回答。');
  assert.equal(record.messages.at(-1).modelName, '新模型');
  assert.equal(record.messages.at(-1).generationState, 'complete');
});
add('missing attachments, unavailable model and stale action IDs cannot replace a turn', async () => {
  const view = await actionView('action-guards');
  const before = JSON.stringify(view.messages);
  view.generationWorkflow = { run: () => { throw Error('Must not generate'); } };
  await view.regenerateAnswer(99999);
  view.loaded = false;
  await view.regenerateAnswer(view.session.lastAnswer().id);
  view.loaded = true;
  view.session.lastQuestion().imageUnavailable = true;
  const missing = JSON.stringify(view.messages);
  await view.regenerateAnswer(view.session.lastAnswer().id);
  assert.equal(JSON.stringify(view.messages), missing);
  assert.ok(before.length > 0);
});
add('inline edit replaces the last turn, retains its attachment and leaves composer drafts intact', async () => {
  const view = await actionView('inline-edit');
  const question = view.session.lastQuestion();
  const oldAnswer = view.session.lastAnswer();
  let request;
  view.generationWorkflow = { run: value => { request = value; return Promise.resolve(finished()); } };
  view.updateInputText('底部草稿');
  view.selectedImageUri = 'file://draft';
  assert.equal(await view.resendEditedQuestion(question.id, ' 修改后的问题 '), true);
  await new Promise(done => setTimeout(done, 0));
  assert.deepEqual(Array.from(request.turns, item => item.content), ['system', '更早的问题', '更早的回答。', '修改后的问题']);
  assert.equal(request.imageUri, question.imageUri);
  assert.equal(view.session.lastQuestion().id, question.id);
  assert.equal(view.session.lastQuestion().content, '修改后的问题');
  assert.equal(view.messages.some(item => item.id === oldAnswer.id), false);
  assert.equal(view.inputText, '底部草稿');
  assert.equal(view.selectedImageUri, 'file://draft');
  await view.flushHistory();
  const saved = await view.historyService.load(view.activeConversationId);
  assert.equal(saved.messages.filter(item => item.role === 'user').length, 2);
  assert.equal(saved.messages.at(-2).content, '修改后的问题');
});
add('editing an earlier question keeps only preceding messages and persists the replacement without later turns', async () => {
  const view = await actionView('edit-earlier-question');
  const firstPair = view.messages.slice(0, 2);
  const question = view.session.lastQuestion();
  const originalTime = question.createdAt;
  const originalImage = question.imageUri;
  const oldAnswer = view.session.lastAnswer().id;
  const laterQuestion = view.session.appendMessage('user', '后续问题');
  const laterAnswer = view.session.appendMessage('assistant', '后续回答');
  view.session.appendMessage('notice', '后续模型切换提示', '', false);
  view.messages = view.session.messages;
  let request;
  view.generationWorkflow = { run: value => { request = value; return Promise.resolve(finished()); } };
  assert.equal(view.canEditQuestion(question.id), true);
  assert.equal(view.canEditQuestion(oldAnswer), false);
  assert.equal(await view.resendEditedQuestion(question.id, '修改中间的问题'), true);
  await new Promise(done => setTimeout(done, 0));
  assert.deepEqual(view.session.messages.slice(0, 2), firstPair);
  assert.deepEqual(Array.from(request.turns, item => item.content), ['system', '更早的问题', '更早的回答。', '修改中间的问题']);
  assert.equal(request.imageUri, originalImage);
  assert.equal(view.session.lastQuestion().createdAt, originalTime);
  assert.equal(view.messages.some(item => [oldAnswer, laterQuestion, laterAnswer].includes(item.id)), false);
  assert.equal(view.messages.some(item => item.content === '后续模型切换提示'), false);
  assert.equal(view.session.lastAnswer().modelId, 'new-model');
  await view.flushHistory();
  const saved = await view.historyService.load(view.activeConversationId);
  assert.equal(saved.messages.some(item => item.content === '后续问题'), false);
  assert.equal(saved.messages.at(-2).content, '修改中间的问题');
  assert.equal(await view.resendEditedQuestion(laterQuestion, '过期提交'), false);
});
add('editing the first question removes all later turns and sends no discarded context', async () => {
  const view = await actionView('edit-first-question');
  const first = view.messages.find(item => item.role === 'user');
  let request;
  view.generationWorkflow = { run: value => { request = value; return Promise.resolve(finished()); } };
  assert.equal(await view.resendEditedQuestion(first.id, '新的开场问题'), true);
  await new Promise(done => setTimeout(done, 0));
  assert.deepEqual(Array.from(request.turns, item => item.content), ['system', '新的开场问题']);
  assert.equal(view.messages.filter(item => item.role === 'user').length, 1);
  assert.equal(view.messages.filter(item => item.role === 'assistant').length, 1);
  assert.equal(view.session.lastQuestion().id, first.id);
});
add('confirmation is limited to earlier questions and opting out persists only after a valid resend', async () => {
  const view = await actionView('edit-confirmation');
  const first = view.messages.find(item => item.role === 'user');
  const last = view.session.lastQuestion();
  assert.equal(view.needsEditQuestionConfirmation(first.id), true);
  assert.equal(view.needsEditQuestionConfirmation(last.id), false);
  assert.equal(view.needsEditQuestionConfirmation(99999), false);
  const before = JSON.stringify(view.messages);
  assert.equal(await view.resendEditedQuestion(first.id, ' ', true), false);
  assert.equal(view.needsEditQuestionConfirmation(first.id), true);
  assert.equal(JSON.stringify(view.messages), before);
  view.context = {};
  view.generationWorkflow = { run: () => Promise.resolve(finished()) };
  await view.resendEditedQuestion(last.id, '修改后问题', true);
  await new Promise(done => setTimeout(done, 0));
  assert.equal(view.needsEditQuestionConfirmation(first.id), false);
  const restored = await actionView('edit-confirmation-restored');
  restored.context = {};
  restored.loadChatActionSettings();
  await new Promise(done => setTimeout(done, 0));
  assert.equal(restored.needsEditQuestionConfirmation(restored.messages[0].id), false);
  assert.equal(preferenceStores.get('chat-actions').get('skip-edit-confirmation'), true);
  preferenceStores.clear();
});
add('inline edit rejects blank, stale, busy and incompatible-image submissions without changing history', async () => {
  const view = await actionView('inline-edit-guards');
  const id = view.session.lastQuestion().id;
  const before = JSON.stringify(view.messages);
  view.generationWorkflow = { run: () => { throw Error('Must not generate'); } };
  assert.equal(await view.resendEditedQuestion(id, '  '), false);
  assert.equal(await view.resendEditedQuestion(99999, '修改'), false);
  view.busy = true;
  assert.equal(await view.resendEditedQuestion(id, '修改'), false);
  view.busy = false;
  view.currentModel = () => ({ supportsImage: false });
  assert.equal(await view.resendEditedQuestion(id, '修改'), false);
  assert.equal(JSON.stringify(view.messages), before);
});
add('history search finds message excerpts without changing the active conversation or exposing notices and thinking', async () => {
  const directory = path.join(temporary, 'search');
  const service = new ChatHistoryService();
  await service.initialize(directory);
  const first = conversation('c-search-1');
  first.title = '设备记录';
  first.messages[1].content = '<think>隐藏的推理词</think>电池温度\n保持正常。';
  first.messages.push({ ...first.messages[1], id: 3, kind: 'notice', content: '系统通知专有词' });
  const second = conversation('c-search-2');
  second.title = 'HarmonyOS Tips';
  second.updatedAt = 3000;
  second.messages[0].content = 'API 调用示例';
  await service.save(first); await service.save(second);
  const indexPath = path.join(directory, 'chat-history/index.json');
  const indexBefore = fs.readFileSync(indexPath, 'utf8');
  const body = await service.search('温度 保持');
  assert.equal(body.length, 1);
  assert.equal(body[0].messageId, first.messages[1].id);
  assert.equal(body[0].excerpt, '电池温度 保持正常。');
  assert.equal((await service.search('harmonyos'))[0].id, second.id);
  assert.equal((await service.search('api'))[0].messageId, second.messages[0].id);
  assert.equal((await service.search('隐藏的推理词')).length, 0);
  assert.equal((await service.search('系统通知专有词')).length, 0);
  assert.equal((await service.search('   ')).length, 0);
  assert.equal((await service.search('不存在')).length, 0);
  assert.equal(fs.readFileSync(indexPath, 'utf8'), indexBefore);
  fs.writeFileSync(path.join(directory, 'chat-history', first.id, 'conversation.json'), '{broken');
  assert.equal((await service.search('api'))[0].id, second.id);
});
add('history search uses rendered Markdown text in paragraphs, tables and code', async () => {
  const service = new ChatHistoryService();
  await service.initialize(path.join(temporary, 'search-markdown'));
  const record = conversation('c-markdown');
  record.title = 'Markdown example';
  record.messages[1].content = '## 检索示例\n\n本地**隐私**保护与[离线运行](https://example.com)。\n\n| 名称 | 用途 |\n| --- | --- |\n| 索引 | 查询资料 |\n\n```cpp\nint count = 3;\n```';
  await service.save(record);
  const prose = await service.search('本地隐私保护');
  assert.equal(prose.length, 1);
  assert.ok(!prose[0].excerpt.includes('**'));
  assert.ok(!prose[0].excerpt.includes('example.com'));
  assert.ok(!prose[0].excerpt.includes('##'));
  assert.ok((await service.search('索引 查询资料'))[0].excerpt.includes('索引 查询资料'));
  assert.ok((await service.search('int count'))[0].excerpt.includes('int count = 3;'));
  assert.equal((await service.search('Markdown example'))[0].excerpt, '');
});

add('a stale search completion cannot replace newer results or revive a cleared query', async () => {
  const view = await actionView('search-race');
  let first, second;
  view.historyService = { search: query => new Promise(resolve => { if (query === '旧') first = resolve; else second = resolve; }) };
  view.updateHistorySearch('旧');
  await new Promise(done => setTimeout(done, 210));
  view.updateHistorySearch('新');
  await new Promise(done => setTimeout(done, 210));
  second([{ id: 'c-new', excerpt: 'new' }]);
  await new Promise(done => setTimeout(done, 0));
  first([{ id: 'c-old', excerpt: 'old' }]);
  await new Promise(done => setTimeout(done, 0));
  assert.equal(view.historySearchResults[0].id, 'c-new');
  view.updateHistorySearch('旧');
  await new Promise(done => setTimeout(done, 210));
  view.updateHistorySearch('');
  first([{ id: 'c-old', excerpt: 'old' }]);
  await new Promise(done => setTimeout(done, 0));
  assert.equal(view.historySearchResults.length, 0);
  assert.equal(view.historySearching, false);
});
add('search navigation targets a matching message even when a bottom scroll is pending', async () => {
  const view = await actionView('search-focus');
  const record = conversation('c-focus');
  await view.historyService.save(record);
  let target;
  view.chatScroller = { scrollToIndex: index => { target = index; } };
  const originalScroll = Object.getPrototypeOf(view).scrollToBottom;
  view.notifyAndScroll = () => originalScroll.call(view);
  originalScroll.call(view); // Queue a bottom scroll before opening the search result.
  await view.openConversation(record.id, record.messages[0].id);
  assert.equal(view.highlightedMessageId, record.messages[0].id);
  assert.equal(view.chatScrollTargetId, record.messages[0].id);
  assert.equal(view.chatAutoScrollEnabled, false);
  await new Promise(done => setTimeout(done, 40));
  assert.equal(target, 0);
  await view.openConversation(record.id, record.messages[1].id);
  await new Promise(done => setTimeout(done, 40));
  assert.equal(target, 1);
  view.pauseChatAutoScroll();
  assert.equal(view.highlightedMessageId, 0);
});


const { conversationTitleSignature } = load(path.join(ets, 'services/ConversationTitleService.ets'));
function pendingTitleRecord(id) {
  const record = conversation(id);
  record.titleSource = 'temporary';
  record.messages[1].generationState = 'complete';
  record.messages[1].completedAt = 2000;
  return record;
}
add('background title persists without selecting or reordering its conversation', async () => {
  const service = new ChatHistoryService();
  await service.initialize(path.join(temporary, 'title-active'));
  const old = pendingTitleRecord('c-title-old');
  const current = pendingTitleRecord('c-title-current');
  await service.save(old);
  await service.save(current);
  assert.equal(await service.applyGeneratedTitle(old.id, conversationTitleSignature(old), '概括标题', () => true), true);
  const index = JSON.parse(fs.readFileSync(path.join(temporary, 'title-active/chat-history/index.json'), 'utf8'));
  assert.equal(index.activeId, current.id);
  const saved = await service.load(old.id);
  assert.equal(saved.title, '概括标题');
  assert.equal(saved.titleSource, 'generated');
  assert.equal(saved.updatedAt, old.updatedAt);
});
add('title completion refreshes the active snapshot without adding messages or changing chat status', async () => {
  const { ChatViewModel } = load(path.join(ets, 'state/ChatViewModel.ets'));
  const view = new ChatViewModel();
  await view.historyService.initialize(path.join(temporary, 'title-view'));
  const record = pendingTitleRecord('c-title-view');
  await view.historyService.save(record);
  view.activeConversation = record;
  view.activeConversationId = record.id;
  view.messages = record.messages;
  view.status = '原回答生成完成';
  const messages = view.messages;
  await view.applyConversationTitle({id:record.id, signature:conversationTitleSignature(record), cancelled:false}, '新标题');
  assert.notEqual(view.activeConversation, record);
  assert.equal(view.currentConversationTitle(), '新标题');
  assert.equal(view.messages, messages);
  assert.equal(view.status, '原回答生成完成');
  view.titleService.dispose();
});
add('manual title survives stale autosave and automatic completion', async () => {
  const service = new ChatHistoryService();
  await service.initialize(path.join(temporary, 'title-manual'));
  const record = pendingTitleRecord('c-title-manual');
  await service.save(record);
  await service.rename(record.id, '用户命名');
  await service.save(record);
  assert.equal(await service.applyGeneratedTitle(record.id, conversationTitleSignature(record), '不应覆盖', () => true), false);
  const saved = await service.load(record.id);
  assert.equal(saved.title, '用户命名');
  assert.equal(saved.titleSource, 'manual');
});
add('manual renames survive stale generated, manual and legacy autosave snapshots', async () => {
  const service = new ChatHistoryService();
  await service.initialize(path.join(temporary, 'title-manual-stale'));
  for (const source of [undefined, 'generated', 'manual']) {
    const record = pendingTitleRecord('c-title-stale-' + (source || 'legacy'));
    record.titleSource = source;
    record.title = '旧名称';
    await service.save(record);
    await service.rename(record.id, '手动新名称');
    await service.save(record);
    const saved = await service.load(record.id);
    assert.equal(saved.title, '手动新名称');
    assert.equal(saved.titleSource, 'manual');
  }
});
add('title completion rejects changed content, cancelled work and legacy titles', async () => {
  const service = new ChatHistoryService();
  await service.initialize(path.join(temporary, 'title-stale'));
  const record = pendingTitleRecord('c-title-stale');
  const signature = conversationTitleSignature(record);
  record.messages[0].content += ' 已编辑';
  await service.save(record);
  assert.equal(await service.applyGeneratedTitle(record.id, signature, '旧结果', () => true), false);
  assert.equal(await service.applyGeneratedTitle(record.id, conversationTitleSignature(record), '已取消', () => false), false);
  const legacy = conversation('c-title-legacy');
  await service.save(legacy);
  assert.equal(await service.applyGeneratedTitle(legacy.id, conversationTitleSignature(legacy), '旧对话不覆盖', () => true), false);
});
add('late title cannot resurrect deleted conversation or clear operation', async () => {
  const service = new ChatHistoryService();
  await service.initialize(path.join(temporary, 'title-delete'));
  const record = pendingTitleRecord('c-title-delete');
  await service.save(record);
  await service.remove(record.id);
  assert.equal(await service.applyGeneratedTitle(record.id, conversationTitleSignature(record), '已删除', () => true), false);
  assert.equal(service.list().length, 0);
});
add('stale autosave retains generated title only for the same first-turn version', async () => {
  const service = new ChatHistoryService();
  await service.initialize(path.join(temporary, 'title-snapshot'));
  const record = pendingTitleRecord('c-title-snapshot');
  await service.save(record);
  await service.applyGeneratedTitle(record.id, conversationTitleSignature(record), '自动标题', () => true);
  await service.save(record);
  assert.equal((await service.load(record.id)).title, '自动标题');
  record.messages[0].content = '完全不同的问题';
  await service.save(record);
  assert.equal((await service.load(record.id)).titleSource, 'temporary');
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
