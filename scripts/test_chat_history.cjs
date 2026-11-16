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
  write: async (fd, value) => fs.writeSync(fd, typeof value === 'string' ? value : Buffer.from(value)),
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
    if (name.startsWith('.')) {
      const relative = path.resolve(path.dirname(filename), name);
      return load(fs.existsSync(relative + '.ets') ? relative + '.ets' : relative + '.js');
    }
    if (name === '@ohos.file.fs') return fileIo;
    if (name === '@ohos.data.preferences') return { getPreferences: async (_context, name) => {
      if (!preferenceStores.has(name)) preferenceStores.set(name, new Map());
      const values = preferenceStores.get(name);
      return { get: async (key, fallback) => values.has(key) ? values.get(key) : fallback,
        put: async (key, value) => values.set(key, value), flush: async () => {} };
    } };
    if (name === '@ohos/hypium') return hypium;
    if (name === 'libentry.so') return { __esModule: true, default: new Proxy(sdkStub, {
      get: (_target, key) => key === 'prepareChatInput' ?
        async turns => ({ prompt: JSON.stringify(turns), inputTokens: 17, modelConfig: '{}' }) :
        key === 'then' ? undefined : sdkStub
    }) };
    if (name === '@kit.ArkTS') return { buffer: Buffer, util: { TextEncoder: class {
      encodeInto(value) { return new TextEncoder().encode(value); }
    } } };
    return sdkStub;
  };
  vm.runInNewContext(result.outputText, {
    module, exports: module.exports, require: requireSource, console, ArrayBuffer, Buffer,
    setTimeout, clearTimeout, setInterval, clearInterval,
    Observed: type => type, Scroller: class { isAtEnd() { return false; } }, ScrollAlign: { START: 0, END: 1 }, Edge: { Bottom: 1 }, $r: name => name
  }, { filename });
  return module.exports;
}
function add(name, run) { tests.push({ name, run }); }
const ets = path.join(project, 'entry/src/main/ets');
const { ChatSession } = load(path.join(ets, 'state/ChatSession.ets'));
const { ChatHistoryService } = load(path.join(ets, 'services/ChatHistoryService.ets'));
const { declaredContextTokens, prepareChatContext } = load(path.join(ets, 'utils/chatContext.ets'));
const { conversationTitle, historyGroup } = load(path.join(ets, 'models/ChatHistoryTypes.ets'));
function conversation(id = 'c-test-1') {
  const session = new ChatSession();
  session.prepareModel('model-a', '模型甲');
  session.appendMessage('user', '问题一', '', true);
  session.appendMessage('assistant', '<think>思考</think>回答一。', '', true);
  return { version: 1, id, title: '测试对话', createdAt: 1000, updatedAt: 2000, messages: session.messages };
}
add('context window comes from explicit model metadata and unknown values stay unknown', () => {
  assert.equal(declaredContextTokens('{"max_position_embeddings":8192}'), 8192);
  assert.equal(declaredContextTokens('{"context_length":4096}'), 4096);
  assert.equal(declaredContextTokens('{"max_position_embeddings":256,"text_config":{"max_position_embeddings":16384}}'), 16384);
  for (const text of ['{}', 'null', '{"max_all_tokens":2048}', '{"max_position_embeddings":"8192"}',
    '{"max_position_embeddings":0}', '{"max_position_embeddings":1.5}', '{"max_position_embeddings":1e30}', 'bad']) {
    assert.equal(declaredContextTokens(text), 0, text);
  }
});
add('context inspection reports the selected pairs, omitted causes and exact untrimmed body', () => {
  const session = new ChatSession();
  const q1 = session.appendMessage('user', '第一问');
  const a1 = session.appendMessage('assistant', '第一答。');
  const q2 = session.appendMessage('user', '第二问');
  const a2 = session.appendMessage('assistant', '失败。');
  session.markGeneration(a2, 'failed', 'internal_error');
  const q3 = session.appendMessage('user', '第三问');
  const a3 = session.appendMessage('assistant', '<think>推理</think>    code  \n');
  session.markGeneration(a3, 'stopped', 'user_stop');
  const plan = session.composeContext('system', '继续', 2);
  assert.deepEqual(Array.from(plan.turns, x => x.content), ['system', '第三问', '    code  \n', '继续']);
  assert.deepEqual(Array.from(plan.historyMessageIds), [q3, a3]);
  for (const id of [q1, a1]) assert.equal(plan.omitted.find(x => x.messageId === id).reason, '超过历史条数上限');
  for (const id of [q2, a2]) assert.equal(plan.omitted.find(x => x.messageId === id).reason, '生成失败');
  assert.ok(session.composeContext('', '问题', 0).omitted.some(x => x.reason === '当前采用单轮对话'));
});
add('token budgeting removes oldest whole pairs and measures the exact final template again', async () => {
  const session = new ChatSession();
  for (const text of ['甲', '乙', '丙']) {
    session.appendMessage('user', text);
    const id = session.appendMessage('assistant', text + '。');
    session.markGeneration(id, 'complete', 'eos');
  }
  const original = JSON.stringify(session.messages);
  const plan = session.composeContext('system', '本次问题', 6);
  const measured = [];
  const result = await prepareChatContext(plan, session.messages, 20, false, async turns => {
    measured.push(JSON.stringify(turns));
    return { prompt: 'templated:' + JSON.stringify(turns), inputTokens: turns.length * 10,
      modelConfig: '{"max_position_embeddings":60}' };
  });
  assert.equal(result.exceedsContext, false);
  assert.equal(result.input.inputTokens, 40);
  assert.equal(measured.length, 3);
  assert.equal(result.input.prompt, 'templated:' + measured.at(-1));
  assert.deepEqual(Array.from(result.selection.turns, x => x.content), ['system', '丙', '丙。', '本次问题']);
  assert.equal(result.selection.omitted.filter(x => x.reason === '为本次问题和输出预留空间').length, 4);
  assert.equal(JSON.stringify(session.messages), original);
});
add('oversized current questions are preserved and unknown or visual budgets are explicit', async () => {
  const session = new ChatSession();
  session.appendMessage('user', '历史问题');
  const id = session.appendMessage('assistant', '历史回答。');
  session.markGeneration(id, 'complete', 'eos');
  const original = JSON.stringify(session.messages);
  for (const [image, config] of [[false, '{}'], [false, '{"max_position_embeddings":5}'],
    [true, '{"max_position_embeddings":5}']]) {
    const plan = session.composeContext('system', '必须原样保留的本次问题', 6);
    const before = JSON.stringify(plan.turns);
    let calls = 0;
    const result = await prepareChatContext(plan, session.messages, 10, image, async turns => {
      calls++;
      return { prompt: JSON.stringify(turns), inputTokens: image ? -1 : 100, modelConfig: config };
    });
    assert.equal(result.exceedsContext, !image && config !== '{}');
    assert.equal(result.selection.turns.at(-1).content, '必须原样保留的本次问题');
    if (image || config === '{}') assert.equal(JSON.stringify(plan.turns), before);
    if (image) {
      assert.equal(result.input.inputTokens, -1);
      assert.equal(plan.historyMessageIds.length, 2);
      assert.equal(plan.omitted.length, 0);
    }
    assert.equal(calls, !image && config !== '{}' ? 2 : 1);
  }
  assert.equal(JSON.stringify(session.messages), original);
});
add('visual budgets count actual encoded input and remove whole image turns together', async () => {
  const session = new ChatSession();
  session.appendMessage('user', 'image question', 'file://image');
  const answer = session.appendMessage('assistant', 'image answer');
  session.markGeneration(answer, 'complete', 'eos');
  const selection = session.composeContext('system', 'follow-up', 6);
  let calls = 0;
  const prepared = await prepareChatContext(selection, session.messages, 10, true, async turns => {
    calls++;
    return { prompt: JSON.stringify(turns), inputTokens: turns.some(turn => turn.imageUri) ? 95 : 12,
      modelConfig: '{"max_position_embeddings":100}' };
  });
  assert.equal(calls, 2);
  assert.equal(prepared.exceedsContext, false);
  assert.equal(prepared.input.inputTokens, 12);
  assert.equal(prepared.selection.turns.some(turn => turn.imageUri), false);
  const oversized = await prepareChatContext({ turns: [{ role: 'user', content: 'large', imageUri: 'file://image' }],
    historyMessageIds: [], omitted: [] }, [], 10, true, async () => ({ prompt: 'actual', inputTokens: 101,
      modelConfig: '{"max_position_embeddings":100}' }));
  assert.equal(oversized.exceedsContext, true);
});
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
add('interrupted restoration keeps visible context and recovers IDs', () => {
  const session = new ChatSession();
  const messages = conversation().messages;
  messages[1].generationState = 'generating';
  session.restore(messages);
  assert.equal(session.messages[1].generationState, 'interrupted');
  assert.equal(session.messages[1].includeInContext, true);
  assert.equal(session.composeChatTurns('system', 'new', 6).length, 4);
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
  view.imageService = { buildImagePayload: async () => ({ pixels: new ArrayBuffer(4), width: 1, height: 1 }) };
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
    assert.equal(view.headerStatus(), 'Laya 决策模型已加载');
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
  view.imageService = { buildImagePayload: async () => ({ pixels: new ArrayBuffer(4), width: 1, height: 1 }) };
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
  view.imageService = { buildImagePayload: async () => ({ pixels: new ArrayBuffer(4), width: 1, height: 1 }) };
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
  view.imageService = { buildImagePayload: async () => ({ pixels: new ArrayBuffer(4), width: 1, height: 1 }) };
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
  view.currentModel = () => ({ id: 'new-model', name: '新模型', shortName: '新模型', supportsImage: true, systemPrompt: 'system' });
  view.currentContextMessageLimit = () => 6;
  return view;
}
function finished(answer = '新的回答。') {
  return { answer, includeInContext: true, status: '生成完成',
    result: { stopReason: 'eos', text: answer, generatedTokens: 3 },
    perfMetrics: { ttft: 1, tpot: 2, tokensPerSec: 3, tokens: 3 } };
}
add('context exclusion distinguishes thinking-only output from an empty reply', () => {
  const session = new ChatSession();
  session.prepareModel('model', '模型');
  session.appendMessage('user', '思考未完的问题');
  const thinking = session.appendMessage('assistant', '<think>只生成了一部分思考', '', true);
  session.markGeneration(thinking, 'complete', 'max_tokens');
  session.appendMessage('user', '空回答的问题');
  const empty = session.appendMessage('assistant', '', '', true);
  session.markGeneration(empty, 'stopped', 'user_stop');
  const selection = session.composeContext('', '下一问', 6);
  assert.equal(selection.omitted.find(item => item.messageId === thinking).reason, '只生成了思考过程，尚未给出回答');
  assert.equal(selection.omitted.find(item => item.messageId === empty).reason, '尚未生成回答');
});
add('empty native output remains empty and legacy placeholders never become model context', () => {
  const { finalAssistantAnswer, shouldIncludeAssistantInContext } = load(path.join(ets, 'utils/generationText.ets'));
  for (const reason of ['eos', 'user_stop', 'timeout', 'internal_error', 'max_tokens']) {
    const result = { text: '', generatedTokens: 0, stopReason: reason };
    assert.equal(finalAssistantAnswer(result), '');
    assert.equal(shouldIncludeAssistantInContext(finalAssistantAnswer(result), result), false);
  }
  const session = new ChatSession();
  session.restore([{ id: 1, role: 'user', content: '旧问题', imageUri: '', includeInContext: true },
    { id: 2, role: 'assistant', content: '（已停止生成）', imageUri: '', includeInContext: false,
      generationState: 'stopped', stopReason: 'user_stop' }]);
  assert.equal(session.composeChatTurns('', '新问题', 6).length, 1);
  assert.equal(session.lastAnswer().includeInContext, false);
  assert.equal(finalAssistantAnswer({ text: '  \n', generatedTokens: 1, stopReason: 'eos' }), '  \n');
});
add('context omission data source replaces entries and releases listeners correctly', () => {
  const source = fs.readFileSync(path.join(ets, 'components/ChatContextDialog.ets'), 'utf8');
  const body = source.slice(source.indexOf('class ContextEntries'), source.indexOf('function roleTitle'));
  const output = ts.transpileModule(body + '\nexports.ContextEntries = ContextEntries;', {
    compilerOptions: { target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.CommonJS }
  }).outputText;
  const sandbox = { exports: {} }; vm.runInNewContext(output, sandbox);
  const rows = new sandbox.exports.ContextEntries([{ key: 'included', content: '已带入' }]);
  let reloads = 0;
  const listener = { onDataReloaded: () => { reloads++; } };
  rows.registerDataChangeListener(listener);
  rows.replace([{ key: 'omitted', content: '未带入' }]);
  assert.equal(reloads, 1);
  assert.equal(rows.totalCount(), 1);
  assert.equal(rows.getData(0).content, '未带入');
  rows.replace([]);
  assert.equal(rows.totalCount(), 0);
  assert.equal(reloads, 2);
  rows.unregisterDataChangeListener(listener);
  rows.replace([{ key: 'formatted', content: '完整文本' }]);
  assert.equal(reloads, 2);
});
add('context cards group actual question-answer pairs and retain the current image question', () => {
  const source = fs.readFileSync(path.join(ets, 'components/ChatContextDialog.ets'), 'utf8');
  const turns = source.slice(source.indexOf('  private conversationTurns()'), source.indexOf('  private instructions()'));
  const roundStart = source.indexOf('  private conversationRounds()');
  const rounds = source.slice(roundStart, source.indexOf('  @Builder', roundStart));
  const output = ts.transpileModule(`class Cards { snapshot: any; ${turns} ${rounds} } exports.Cards = Cards;`, {
    compilerOptions: { target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.CommonJS }
  }).outputText;
  const sandbox = { exports: {} }; vm.runInNewContext(output, sandbox);
  const cards = new sandbox.exports.Cards();
  cards.snapshot = { turns: [{ role: 'system', content: '提示' }, { role: 'user', content: '第一问\n' },
    { role: 'assistant', content: '  第一答\n' }, { role: 'user', content: '本次问题' }] };
  assert.equal(JSON.stringify(cards.conversationRounds()), JSON.stringify([
    { question: '第一问\n', answer: '  第一答\n', current: false, hasImage: false },
    { question: '本次问题', answer: '', current: true, hasImage: false }
  ]));
  cards.snapshot.imageInput = true; cards.snapshot.questionText = '';
  cards.snapshot.turns[1].imageUri = 'saved-image';
  const visual = cards.conversationRounds();
  assert.equal(visual.length, 2);
  assert.equal(visual[0].hasImage, true);
  assert.equal(visual[0].question, '第一问\n');
  assert.equal(visual[1].question, '本次问题');
  assert.equal(visual[1].hasImage, false);
});
add('API status reflects the actual end reason and never calls a stopped request completed', async () => {
  for (const [stopReason, expected, tone] of [
    ['eos', 'API 生成完成', 'success'], ['max_tokens', 'API 输出已达到上限', 'warning'],
    ['user_stop', 'API 生成已停止', 'warning'], ['timeout', 'API 生成超时', 'error'],
    ['internal_error', 'API 生成失败', 'error'], ['unknown', 'API 生成失败', 'error']
  ]) {
    const view = await actionView('api-status-' + stopReason);
    view.nativeService = { generateText: async () => ({ text: '正文', generatedTokens: 3, stopReason }) };
    await view.runApiGeneration({ turns: [], maxNewTokens: 8, settings: {} }, () => {});
    assert.ok(view.status.startsWith(expected), view.status);
    assert.equal(view.statusTone, tone);
    assert.equal(view.busy, false);
    assert.equal(view.generating, false);
    assert.equal(view.generationStopping, false);
  }
  const failed = await actionView('api-status-rejected');
  failed.nativeService = { generateText: () => Promise.reject(new Error('native code=123 timeout')) };
  await assert.rejects(failed.runApiGeneration({ turns: [], maxNewTokens: 8, settings: {} }, () => {}));
  assert.equal(failed.status, 'API 生成失败，请查看服务日志');
  assert.equal(failed.busy, false);
});
add('ability background saves with a short delay and foreground resumes lifecycle work', async () => {
  const view = await actionView('ability-background');
  const events = [];
  view.titleService = { pause: () => events.push('pause-title'), resume: () => events.push('resume-title') };
  view.backgroundTasks = {
    setPerformanceState: () => {},
    saveBeforeSuspend: async save => { events.push('protect-save'); await save(); },
    refresh: () => events.push('refresh-background')
  };
  view.flushHistory = async () => { events.push('save-history'); };
  view.setAppForeground(false);
  await new Promise(resolve => setTimeout(resolve, 0));
  assert.deepEqual(events, ['pause-title', 'protect-save', 'save-history']);
  view.setAppForeground(true);
  assert.deepEqual(events.slice(-2), ['resume-title', 'refresh-background']);
});
add('background API chunks preserve output without rendering progress and late callbacks cannot revive it', async () => {
  const view = await actionView('api-background-chunks');
  view.appForeground = false;
  let callback, finish;
  view.nativeService = { generateText: (_turns, _limit, _settings, onChunk) => {
    callback = onChunk;
    return new Promise(resolve => { finish = resolve; });
  } };
  const received = [];
  const generation = view.runApiGeneration({ turns: [], maxNewTokens: 8, settings: {} }, chunk => received.push(chunk));
  callback('前半');
  assert.equal(view.status, '等待 API 首个输出片段...');
  assert.equal(view.streamingChars, 0);
  view.appForeground = true;
  callback('后半');
  assert.ok(view.status.includes('4 字符'));
  finish({ text: '前半后半', generatedTokens: 4, stopReason: 'eos' });
  await generation;
  const completed = view.status;
  callback('迟到片段');
  assert.equal(view.status, completed);
  assert.equal(view.streamingChars, 4);
  assert.deepEqual(received, ['前半', '后半']);
});
add('sending the first question consumes the empty-conversation draft before assigning its ID', async () => {
  const view = await actionView('first-send-draft');
  await view.beginNewConversation();
  view.conversationDrafts.set('c-other-draft', '其他对话的草稿');
  view.generationWorkflow = { run: () => Promise.resolve(finished()) };
  view.updateInputText('新对话的第一条问题');
  await view.sendMessage();
  await new Promise(done => setTimeout(done, 0));
  assert.ok(view.activeConversationId);
  await view.flushHistory();
  assert.equal(view.contextForCurrentConversation().conversationId, view.activeConversationId);
  assert.equal(view.contextForCurrentConversation().turns.at(-1).content, '新对话的第一条问题');
  await view.beginNewConversation();
  assert.equal(view.inputText, '');
  assert.equal(view.conversationDrafts.has(''), false);
  assert.equal(view.conversationDrafts.get('c-other-draft'), '其他对话的草稿');
});
add('failed or oversized preparation preserves original messages, versions, draft and attachments', async () => {
  for (const failure of ['native', 'budget']) {
    const view = await actionView('prepare-reject-' + failure);
    const question = view.session.lastQuestion();
    const original = JSON.stringify(view.session.messages);
    view.inputText = '未发送草稿';
    view.selectedImageUri = 'file://unsent-image';
    let generated = false;
    view.generationWorkflow = { run: () => { generated = true; return Promise.resolve(finished()); } };
    view.nativeService.prepareChatInput = async () => {
      if (failure === 'native') throw new Error('native internal detail');
      return { prompt: 'native template', inputTokens: 1000, modelConfig: '{"max_position_embeddings":32}' };
    };
    await view.generateChatMessage('修改后的问题', '', question.id, false, true);
    assert.equal(generated, false);
    assert.equal(JSON.stringify(view.session.messages), original);
    assert.equal(view.inputText, '未发送草稿');
    assert.equal(view.selectedImageUri, 'file://unsent-image');
    assert.equal(view.busy, false); assert.equal(view.generating, false);
    assert.ok(!view.status.includes('native internal detail'));
  }
});
add('cancelling preparation keeps the question in the composer and does not start generation', async () => {
  const view = await actionView('prepare-cancel');
  const original = JSON.stringify(view.session.messages);
  let release, generated = false;
  view.nativeService.prepareChatInput = () => new Promise(resolve => { release = resolve; });
  view.generationWorkflow = { run: () => { generated = true; return Promise.resolve(finished()); }, stop: () => {} };
  view.inputText = '取消准备后保留';
  const sending = view.sendMessage();
  assert.equal(view.generating, true);
  await new Promise(resolve => setImmediate(resolve));
  view.stopGeneration();
  release({ prompt: 'prepared', inputTokens: 10, modelConfig: '{}' });
  await sending;
  assert.equal(generated, false);
  assert.equal(JSON.stringify(view.session.messages), original);
  assert.equal(view.inputText, '取消准备后保留');
  assert.equal(view.busy, false); assert.equal(view.generating, false);
});
add('disposing during preparation prevents its late completion from starting a model job', async () => {
  const view = await actionView('prepare-dispose');
  const original = JSON.stringify(view.session.messages);
  let release, generated = false;
  view.nativeService.prepareChatInput = () => new Promise(resolve => { release = resolve; });
  view.generationWorkflow = { run: () => { generated = true; return Promise.resolve(finished()); }, stop: () => {} };
  view.inputText = '尚未提交的问题';
  const sending = view.sendMessage();
  await new Promise(resolve => setImmediate(resolve));
  view.dispose();
  release({ prompt: 'prepared', inputTokens: 10, modelConfig: '{}' });
  await sending;
  assert.equal(generated, false);
  assert.equal(JSON.stringify(view.session.messages), original);
});
add('typing continue is a normal new question with the preceding partial answer as context', async () => {
  for (const reason of ['user_stop', 'max_tokens', 'timeout']) {
    const view = await actionView('ordinary-followup-' + reason);
    view.session.lastQuestion().imageUri = '';
    const originalId = view.session.lastAnswer().id;
    const originalText = '<think>不发送思考过程</think>\n    已有回答';
    view.session.updateMessage(originalId, originalText, false);
    view.session.markGeneration(originalId, reason === 'user_stop' ? 'stopped' :
      (reason === 'timeout' ? 'failed' : 'complete'), reason);
    let request;
    view.generationWorkflow = { run: value => { request = value; return Promise.resolve(finished('接着回答。')); } };
    view.inputText = '继续';
    view.selectedImageUri = '';
    await view.sendMessage();
    await new Promise(resolve => setTimeout(resolve, 0));
    assert.equal(request.turns.at(-1).content, '继续');
    assert.equal(request.turns.at(-2).content, '\n    已有回答');
    assert.equal(request.turns.some(turn => turn.content.includes('不发送思考过程')), false);
    assert.equal(view.session.messages.find(message => message.id === originalId).content, originalText);
    assert.equal(view.session.lastQuestion().content, '继续');
    assert.notEqual(view.session.lastAnswer().id, originalId);
    assert.equal(view.session.lastAnswer().answerVersions, undefined);
    await view.flushHistory();
  }
});
add('regeneration retains answer versions and uses current model without duplicating context', async () => {
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
  assert.equal(view.session.lastAnswer().id, oldAnswer.id);
  assert.equal(view.session.lastAnswer().answerVersions[0].content, '最后的旧回答。');
  assert.equal(view.session.lastAnswer().answerVersions.length, 2);
  assert.equal(view.session.lastAnswer().answerVersionIndex, 1);
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
add('repeated regeneration rebuilds one model-switch notice for the replaced turn', async () => {
  const view = await actionView('regenerate-model-notice');
  const id = view.session.lastAnswer().id;
  const precedingAnswer = view.messages[1];
  view.generationWorkflow = { run: () => Promise.resolve(finished()) };
  for (let attempt = 0; attempt < 3; attempt++) {
    await view.regenerateAnswer(id);
    await new Promise(done => setTimeout(done, 0));
    assert.equal(view.messages.filter(item => item.role === 'notice').length, 1);
    assert.equal(view.messages.find(item => item.role === 'notice').modelId, 'new-model');
    assert.deepEqual(view.messages[1], precedingAnswer);
  }
  assert.equal(view.session.lastAnswer().answerVersions.length, 4);
  await view.flushHistory();
  const record = await view.historyService.load(view.activeConversationId);
  assert.equal(record.messages.filter(item => item.role === 'notice').length, 1);
});
add('editing and regenerating an existing turn replaces stale model-switch notices', async () => {
  const view = await actionView('edit-model-notice');
  const question = view.session.lastQuestion();
  view.generationWorkflow = { run: () => Promise.resolve(finished()) };
  await view.regenerateAnswer(view.session.lastAnswer().id);
  await new Promise(done => setTimeout(done, 0));
  const answer = view.session.lastAnswer();
  const questionIndex = view.session.messages.findIndex(item => item.id === question.id);
  const duplicate = { ...view.messages.find(item => item.role === 'notice'), id: 9000 };
  view.session.messages.splice(questionIndex, 0, duplicate, { ...duplicate, id: 9001 });
  assert.equal(await view.resendEditedQuestion(question.id, '修改后的问题'), true);
  await new Promise(done => setTimeout(done, 0));
  assert.equal(view.messages.filter(item => item.role === 'notice').length, 1);
  assert.equal(view.messages.some(item => item.id === answer.id), false);
  view.currentModel = () => ({ id: 'old-model', shortName: '旧模型', supportsImage: true, systemPrompt: 'system' });
  await view.regenerateAnswer(view.session.lastAnswer().id);
  await new Promise(done => setTimeout(done, 0));
  assert.equal(view.messages.filter(item => item.role === 'notice').length, 0);
  assert.equal(view.session.lastAnswer().modelId, 'old-model');
});
add('editing an earlier turn preserves preceding switch notices and rebuilds its own notice', async () => {
  const view = await actionView('edit-earlier-model-notice');
  view.generationWorkflow = { run: () => Promise.resolve(finished()) };
  await view.regenerateAnswer(view.session.lastAnswer().id);
  await new Promise(done => setTimeout(done, 0));
  const preceding = view.messages.slice();
  view.currentModel = () => ({ id: 'third-model', shortName: '第三模型', supportsImage: true, systemPrompt: 'system' });
  view.updateInputText('后续问题');
  await view.sendMessage();
  await new Promise(done => setTimeout(done, 0));
  const questionId = view.session.lastQuestion().id;
  view.updateInputText('再问一次');
  await view.sendMessage();
  await new Promise(done => setTimeout(done, 0));
  assert.equal(await view.resendEditedQuestion(questionId, '修改后续问题'), true);
  await new Promise(done => setTimeout(done, 0));
  assert.equal(JSON.stringify(view.messages.slice(0, preceding.length)), JSON.stringify(preceding));
  const notices = view.messages.filter(item => item.role === 'notice');
  assert.deepEqual(Array.from(notices, item => item.modelId), ['new-model', 'third-model']);
});
add('version selection restores metadata, thinking state and metrics across a restart', async () => {
  const view = await actionView('version-roundtrip');
  const first = view.session.lastAnswer();
  view.session.updateMessage(first.id, '<think>原思考</think>原回答。', true,
    { ttft: 10, tpot: 20, tokensPerSec: 30, tokens: 40, tokensEstimated: true,
      inputTokens: 17, nativeTiming: { prefillMs: 12.345, decodeMs: 23.456, visionMs: 0 } });
  view.session.toggleThinkingExpanded(first.id);
  const original = JSON.parse(JSON.stringify(view.session.lastAnswer()));
  view.generationWorkflow = { run: () => Promise.resolve(finished('第二版回答。')) };
  await view.regenerateAnswer(first.id);
  await new Promise(done => setTimeout(done, 0));
  view.selectAnswerVersion(first.id, 0);
  const selected = view.session.lastAnswer();
  for (const key of ['content', 'modelId', 'modelName', 'createdAt', 'completedAt', 'time',
    'generationState', 'includeInContext', 'thinkingExpanded']) assert.equal(selected[key], original[key], key);
  assert.equal(selected.perfMetrics.tokens, 40);
  assert.equal(selected.perfMetrics.tokensEstimated, true);
  assert.equal(JSON.stringify(selected.perfMetrics.nativeTiming), JSON.stringify(original.perfMetrics.nativeTiming));
  await view.flushHistory();
  const restarted = new ChatHistoryService();
  await restarted.initialize(path.join(temporary, 'version-roundtrip'));
  const record = await restarted.load(view.activeConversationId);
  const session = new ChatSession();
  session.restore(record.messages);
  assert.equal(session.lastAnswer().answerVersionIndex, 0);
  assert.equal(session.lastAnswer().content, original.content);
  assert.equal(session.lastAnswer().perfMetrics.tokensEstimated, true);
  assert.equal(session.lastAnswer().perfMetrics.inputTokens, 17);
  assert.equal(JSON.stringify(session.lastAnswer().perfMetrics.nativeTiming), JSON.stringify(original.perfMetrics.nativeTiming));
  assert.equal(session.selectAnswerVersion(first.id, 1), true);
  assert.equal(session.lastAnswer().content, '第二版回答。');
  assert.equal(session.lastAnswer().modelName, '新模型');
  assert.equal(session.lastAnswer().perfMetrics.tokens, 3);
  assert.equal(session.lastAnswer().perfMetrics.tokensEstimated, undefined);
  assert.equal(session.lastAnswer().perfMetrics.nativeTiming, undefined);
});
add('regenerating from an older selection appends a version rather than replacing alternatives', async () => {
  const view = await actionView('version-append');
  const id = view.session.lastAnswer().id;
  view.generationWorkflow = { run: () => Promise.resolve(finished('第二版。')) };
  await view.regenerateAnswer(id);
  await new Promise(done => setTimeout(done, 0));
  view.selectAnswerVersion(id, 0);
  view.generationWorkflow = { run: () => Promise.resolve(finished('第三版。')) };
  await view.regenerateAnswer(id);
  await new Promise(done => setTimeout(done, 0));
  const answer = view.session.lastAnswer();
  assert.deepEqual(Array.from(answer.answerVersions, x => x.content), ['最后的旧回答。', '第二版。', '第三版。']);
  assert.equal(answer.answerVersionIndex, 2);
  assert.equal(view.messages.filter(x => x.role === 'user').length, 2);
});
add('follow-up context uses the selected reply while keeping later messages and composer drafts', async () => {
  const view = await actionView('selected-context');
  const id = view.session.lastAnswer().id;
  view.generationWorkflow = { run: () => Promise.resolve(finished('不要进入上下文的另一版。')) };
  await view.regenerateAnswer(id);
  await new Promise(done => setTimeout(done, 0));
  view.updateInputText('后续问题');
  view.selectAnswerVersion(id, 0);
  assert.equal(view.inputText, '后续问题');
  let request;
  view.generationWorkflow = { run: value => { request = value; return Promise.resolve(finished('后续回答。')); } };
  await view.sendMessage();
  await new Promise(done => setTimeout(done, 0));
  assert.deepEqual(Array.from(request.turns, x => x.content),
    ['system', '更早的问题', '更早的回答。', '最后的问题', '最后的旧回答。', '后续问题']);
  const followingIds = Array.from(view.messages.slice(-2), x => x.id);
  view.selectAnswerVersion(id, 1);
  assert.deepEqual(Array.from(view.messages.slice(-2), x => x.id), followingIds);
  assert.ok(view.session.composeChatTurns('system', '再问', 6)
    .some(x => x.content === '不要进入上下文的另一版。'));
});
add('answer version switching follows the pre-switch bottom position rather than the auto-follow flag', async () => {
  const view = await actionView('version-scroll');
  const id = view.session.lastAnswer().id;
  view.generationWorkflow = { run: () => Promise.resolve(finished('另一版。')) };
  await view.regenerateAnswer(id);
  await new Promise(done => setTimeout(done, 0));
  let atBottom = true;
  let scrolls = 0;
  view.chatScroller = { isAtEnd: () => atBottom };
  view.notifyAndMaybeScroll = Object.getPrototypeOf(view).notifyAndMaybeScroll;
  view.scrollToBottom = () => { scrolls++; };
  view.pauseChatAutoScroll(); // A touch on the version button also pauses auto-follow.
  view.selectAnswerVersion(id, 0);
  assert.equal(scrolls, 1);
  assert.equal(view.chatAutoScrollEnabled, true);
  atBottom = false;
  view.selectAnswerVersion(id, 1);
  assert.equal(scrolls, 1);
  assert.equal(view.chatAutoScrollEnabled, false);
  atBottom = true;
  view.selectAnswerVersion(id, 1); // Selecting the active version must not change scroll state.
  assert.equal(scrolls, 1);
  assert.equal(view.chatAutoScrollEnabled, false);
  await view.flushHistory();
});
add('busy, generating, invalid and user-message version switches are ignored', async () => {
  const view = await actionView('version-guards');
  const id = view.session.lastAnswer().id;
  let resolve;
  view.generationWorkflow = { run: () => new Promise(done => { resolve = done; }) };
  await view.regenerateAnswer(id);
  const before = JSON.stringify(view.messages);
  view.selectAnswerVersion(id, 0);
  assert.equal(view.session.selectAnswerVersion(id, 0), false);
  assert.equal(JSON.stringify(view.messages), before);
  resolve(finished());
  await new Promise(done => setTimeout(done, 0));
  const after = JSON.stringify(view.messages);
  for (const index of [-1, 2, 0.5, NaN]) view.selectAnswerVersion(id, index);
  view.selectAnswerVersion(view.session.lastQuestion().id, 0);
  view.selectAnswerVersion(99999, 0);
  view.busy = true;
  view.selectAnswerVersion(id, 0);
  assert.equal(JSON.stringify(view.messages), after);
  view.busy = false;
});
add('failed and stopped alternatives preserve the original reply and its usable context', async () => {
  const view = await actionView('version-failure-stop');
  const id = view.session.lastAnswer().id;
  view.generationWorkflow = { run: (_request, callbacks) => {
    callbacks.onStream({ text: '失败前的内容', characterCount: 6 });
    return Promise.reject(new Error('故障'));
  } };
  await view.regenerateAnswer(id);
  await new Promise(done => setTimeout(done, 0));
  assert.equal(view.session.lastAnswer().generationState, 'failed');
  view.selectAnswerVersion(id, 0);
  assert.equal(view.session.lastAnswer().content, '最后的旧回答。');
  assert.ok(view.session.composeChatTurns('system', '继续', 6).some(x => x.content === '最后的旧回答。'));
  view.generationWorkflow = { run: () => Promise.resolve({ ...finished('停止前的内容'), includeInContext: false,
    result: { stopReason: 'user_stop', text: '停止前的内容', generatedTokens: 2 } }) };
  await view.regenerateAnswer(id);
  await new Promise(done => setTimeout(done, 0));
  assert.equal(view.session.lastAnswer().generationState, 'stopped');
  assert.equal(view.session.lastAnswer().answerVersions.length, 3);
  assert.equal(view.session.composeChatTurns('system', '继续', 6).length, 6);
  await view.flushHistory();
  const record = await view.historyService.load(view.activeConversationId);
  const restored = new ChatSession();
  restored.restore(record.messages);
  assert.equal(restored.selectAnswerVersion(id, 1), true);
  assert.equal(restored.lastAnswer().generationState, 'failed');
  assert.equal(restored.lastAnswer().content, '失败前的内容');
  assert.equal(restored.lastAnswer().includeInContext, false);
  assert.equal(restored.selectAnswerVersion(id, 0), true);
  assert.equal(restored.lastAnswer().content, '最后的旧回答。');
});
add('restart during a new version keeps the newest stream checkpoint and the original answer', () => {
  const session = new ChatSession();
  session.appendMessage('user', '问题');
  const id = session.appendMessage('assistant', '原回答。');
  session.startAnswerVersion(id);
  session.updateMessage(id, '<think>思考</think>最新片段', true);
  session.appendToMessage(id, '。');
  const restored = new ChatSession();
  restored.restore(JSON.parse(JSON.stringify(session.messages)));
  assert.equal(restored.lastAnswer().generationState, 'interrupted');
  assert.equal(restored.lastAnswer().content, '<think>思考</think>最新片段。');
  assert.equal(restored.lastAnswer().includeInContext, true);
  assert.equal(restored.selectAnswerVersion(id, 0), true);
  assert.equal(restored.lastAnswer().content, '原回答。');
  assert.equal(restored.selectAnswerVersion(id, 1), true);
  assert.equal(restored.lastAnswer().generationState, 'interrupted');
});
add('editing a question discards its answer alternatives and later turns', async () => {
  const view = await actionView('edit-versioned-question');
  const id = view.session.lastAnswer().id;
  const questionId = view.session.lastQuestion().id;
  view.generationWorkflow = { run: () => Promise.resolve(finished('第二版。')) };
  await view.regenerateAnswer(id);
  await new Promise(done => setTimeout(done, 0));
  view.session.appendMessage('user', '后续问题');
  view.session.appendMessage('assistant', '后续回答');
  view.messages = view.session.messages;
  assert.equal(await view.resendEditedQuestion(questionId, '改后的问题'), true);
  await new Promise(done => setTimeout(done, 0));
  assert.equal(view.messages.some(x => x.id === id), false);
  assert.equal(view.messages.some(x => x.content === '后续问题'), false);
  assert.equal(view.session.lastAnswer().answerVersions, undefined);
  await view.flushHistory();
  const saved = await view.historyService.load(view.activeConversationId);
  assert.equal(saved.messages.filter(x => x.answerVersions).length, 0);
});
add('history search covers inactive rendered answer versions without changing the saved selection', async () => {
  const service = new ChatHistoryService();
  await service.initialize(path.join(temporary, 'version-search'));
  const record = conversation('c-version-search');
  const session = new ChatSession();
  session.restore(record.messages);
  const id = session.lastAnswer().id;
  session.updateMessage(id, '<think>隐藏思考关键词</think>**旧版独有内容**与共同关键词。', true);
  session.startAnswerVersion(id);
  session.updateMessage(id, '新版独有内容与共同关键词。', true);
  session.markGeneration(id, 'complete', 'eos');
  record.messages = session.messages;
  await service.save(record);
  const before = JSON.stringify(await service.load(record.id));
  const old = await service.search('旧版独有内容');
  assert.equal(old.length, 1);
  assert.equal(old[0].messageId, id);
  assert.equal(old[0].answerVersionIndex, 0);
  assert.ok(old[0].excerpt.startsWith('第 1 版：'));
  assert.equal(old[0].excerpt.includes('**'), false);
  assert.equal((await service.search('隐藏思考关键词')).length, 0);
  const common = await service.search('共同关键词');
  assert.equal(common.length, 1);
  assert.equal(common[0].answerVersionIndex, 1);
  assert.equal(common[0].excerpt.startsWith('第 '), false);
  assert.equal(JSON.stringify(await service.load(record.id)), before);
  session.updateMessage(id, '可搜索的最新流式检查点。');
  record.messages = session.messages;
  await service.save(record);
  assert.equal((await service.search('最新流式检查点'))[0].answerVersionIndex, 1);
});
add('opening a version search result selects and focuses it in active and inactive conversations', async () => {
  const view = await actionView('version-search-navigation');
  const id = view.session.lastAnswer().id;
  view.generationWorkflow = { run: () => Promise.resolve(finished('新版独有回复。')) };
  await view.regenerateAnswer(id);
  await new Promise(done => setTimeout(done, 0));
  await view.flushHistory();
  const conversationId = view.activeConversationId;
  let result = (await view.historyService.search('最后的旧回答'))[0];
  assert.equal(await view.openConversation(result.id, result.messageId, result.answerVersionIndex), true);
  assert.equal(view.session.lastAnswer().answerVersionIndex, 0);
  assert.equal(view.chatScrollTargetId, id);
  assert.equal(view.highlightedMessageId, id);
  await view.flushHistory();
  assert.equal((await view.historyService.load(conversationId)).messages.at(-1).answerVersionIndex, 0);
  await view.beginNewConversation();
  assert.equal(view.activeConversationId, '');
  result = (await view.historyService.search('新版独有回复'))[0];
  const modelId = view.selectedModelId;
  assert.equal(await view.openConversation(result.id, result.messageId, result.answerVersionIndex), true);
  assert.equal(view.activeConversationId, conversationId);
  assert.equal(view.session.lastAnswer().answerVersionIndex, 1);
  assert.equal(view.session.lastAnswer().content, '新版独有回复。');
  assert.equal(view.chatScrollTargetId, id);
  assert.equal(view.loaded, true);
  assert.equal(view.selectedModelId, modelId);
  assert.equal((await view.historyService.load(conversationId)).messages.at(-1).answerVersionIndex, 1);
  view.busy = true;
  assert.equal(await view.openConversation(conversationId, id, 0), false);
  assert.equal(view.session.lastAnswer().answerVersionIndex, 1);
  view.busy = false;
  assert.equal(await view.openConversation(conversationId, id, 999), true);
  assert.equal(view.session.lastAnswer().answerVersionIndex, 1);
});
add('output limits and timeouts retain their exact stop reason through versions and storage', async () => {
  const view = await actionView('version-stop-reasons');
  const id = view.session.lastAnswer().id;
  for (const reason of ['max_tokens', 'timeout', 'eos']) {
    view.generationWorkflow = { run: () => Promise.resolve({ ...finished('结束原因为 ' + reason),
      includeInContext: reason === 'eos',
      result: { stopReason: reason, text: '结束原因为 ' + reason, generatedTokens: 10 } }) };
    await view.regenerateAnswer(id);
    await new Promise(done => setTimeout(done, 0));
    assert.equal(view.session.lastAnswer().stopReason, reason);
  }
  const answer = view.session.lastAnswer();
  assert.deepEqual(Array.from(answer.answerVersions, x => x.stopReason), [undefined, 'max_tokens', 'timeout', 'eos']);
  view.selectAnswerVersion(id, 1);
  view.session.toggleThinkingExpanded(id);
  view.session.updateMessage(id, '保留达到输出上限的回答。');
  view.session.appendToMessage(id, '尾部');
  view.syncMessages();
  await view.flushHistory();
  const record = await view.historyService.load(view.activeConversationId);
  const restored = new ChatSession();
  restored.restore(record.messages);
  assert.equal(restored.lastAnswer().stopReason, 'max_tokens');
  assert.equal(restored.lastAnswer().includeInContext, true);
  assert.equal(restored.lastAnswer().generationState, 'complete');
  assert.equal(restored.lastAnswer().thinkingExpanded, true);
  assert.equal(restored.selectAnswerVersion(id, 2), true);
  assert.equal(restored.lastAnswer().stopReason, 'timeout');
  assert.equal(restored.lastAnswer().generationState, 'failed');
  assert.equal(restored.selectAnswerVersion(id, 3), true);
  assert.equal(restored.lastAnswer().stopReason, 'eos');
  assert.equal(restored.lastAnswer().includeInContext, true);
  assert.equal(restored.selectAnswerVersion(id, 0), true);
  assert.equal(restored.lastAnswer().stopReason, undefined);
});
add('thrown generation errors and user stops persist distinct reasons', async () => {
  const view = await actionView('error-stop-reasons');
  const id = view.session.lastAnswer().id;
  view.generationWorkflow = { run: () => Promise.reject(new Error('测试故障')) };
  await view.regenerateAnswer(id);
  await new Promise(done => setTimeout(done, 0));
  assert.equal(view.session.lastAnswer().stopReason, 'internal_error');
  view.generationWorkflow = { run: () => Promise.resolve({ ...finished('已停止的内容'), includeInContext: false,
    result: { stopReason: 'user_stop', text: '已停止的内容', generatedTokens: 2 } }) };
  await view.regenerateAnswer(id);
  await new Promise(done => setTimeout(done, 0));
  assert.equal(view.session.lastAnswer().stopReason, 'user_stop');
  await view.flushHistory();
  const record = await view.historyService.load(view.activeConversationId);
  assert.equal(record.messages.at(-1).answerVersions[1].stopReason, 'internal_error');
  assert.equal(record.messages.at(-1).stopReason, 'user_stop');
});
add('invalid stored version records are rejected without changing the old-record format', () => {
  const service = new ChatHistoryService();
  const record = conversation('c-invalid-versions');
  assert.equal(service.parseRecord(JSON.stringify(record), record.id).messages.length, 2);
  const reply = record.messages[1];
  reply.answerVersions = [{ content: 'a' }, { content: 'b' }];
  reply.answerVersionIndex = 9;
  assert.throws(() => service.parseRecord(JSON.stringify(record), record.id), /版本格式/);
  reply.answerVersionIndex = 0;
  assert.throws(() => service.parseRecord(JSON.stringify(record), record.id), /版本格式/);
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
  const originalImage = question.imageUri;
  const oldAnswer = view.session.lastAnswer();
  let request;
  view.generationWorkflow = { run: value => { request = value; return Promise.resolve(finished()); } };
  view.updateInputText('底部草稿');
  view.selectedImageUri = 'file://draft';
  assert.equal(await view.resendEditedQuestion(question.id, ' 修改后的问题 '), true);
  await new Promise(done => setTimeout(done, 0));
  assert.deepEqual(Array.from(request.turns, item => item.content), ['system', '更早的问题', '更早的回答。', '修改后的问题']);
  assert.equal(request.imageUri, originalImage);
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
  let first, second, firstIsCurrent, secondIsCurrent;
  view.historyService = { search: (query, isCurrent) => new Promise(resolve => {
    if (query === '旧') { first = resolve; firstIsCurrent = isCurrent; }
    else { second = resolve; secondIsCurrent = isCurrent; }
  }) };
  view.updateHistorySearch('旧');
  await new Promise(done => setTimeout(done, 210));
  assert.equal(firstIsCurrent(), true);
  view.updateHistorySearch('新');
  assert.equal(firstIsCurrent(), false);
  await new Promise(done => setTimeout(done, 210));
  assert.equal(secondIsCurrent(), true);
  second([{ id: 'c-new', excerpt: 'new' }]);
  await new Promise(done => setTimeout(done, 0));
  first([{ id: 'c-old', excerpt: 'old' }]);
  await new Promise(done => setTimeout(done, 0));
  assert.equal(view.historySearchResults[0].id, 'c-new');
  view.updateHistorySearch('旧');
  await new Promise(done => setTimeout(done, 210));
  view.updateHistorySearch('');
  assert.equal(firstIsCurrent(), false);
  first([{ id: 'c-old', excerpt: 'old' }]);
  await new Promise(done => setTimeout(done, 0));
  assert.equal(view.historySearchResults.length, 0);
  assert.equal(view.historySearching, false);
});
add('obsolete searches stop reading and cannot delay a save behind the full corpus', async () => {
  const directory = path.join(temporary, 'search-cancel-storage');
  const service = new ChatHistoryService();
  await service.initialize(directory);
  for (let index = 0; index < 24; index++) {
    const record = conversation('c-cancel-' + index);
    record.updatedAt += index;
    await service.save(record);
  }
  const read = service.readRecord.bind(service);
  let releaseRead, readStarted;
  const started = new Promise(resolve => { readStarted = resolve; });
  const gate = new Promise(resolve => { releaseRead = resolve; });
  let reads = 0, current = true;
  service.readRecord = async id => {
    reads++;
    if (reads === 1) { readStarted(); await gate; }
    return read(id);
  };
  const search = service.search('不存在', () => current);
  await started;
  const pendingSave = conversation('c-cancel-save');
  const save = service.save(pendingSave);
  current = false;
  releaseRead();
  assert.equal((await search).length, 0);
  await save;
  assert.equal(reads, 1);
  assert.ok(fs.existsSync(path.join(directory, 'chat-history', pendingSave.id, 'conversation.json')));
  assert.equal((await service.search('问题一')).length, 25);
});
add('a current search yields storage to writes and deletion without reviving deleted results', async () => {
  const directory = path.join(temporary, 'search-storage-yield');
  const service = new ChatHistoryService();
  await service.initialize(directory);
  for (let index = 0; index < 24; index++) {
    const record = conversation('c-yield-' + index);
    record.updatedAt += index;
    await service.save(record);
  }
  const read = service.readRecord.bind(service);
  let releaseRead, readStarted;
  const started = new Promise(resolve => { readStarted = resolve; });
  const gate = new Promise(resolve => { releaseRead = resolve; });
  let reads = 0;
  service.readRecord = async id => {
    reads++;
    if (reads === 2) { readStarted(); await gate; }
    return read(id);
  };
  const search = service.search('问题一');
  await started;
  const saved = conversation('c-yield-new');
  const save = service.save(saved);
  const remove = service.remove('c-yield-23'); // Already searched before the gated read.
  releaseRead();
  await save; await remove;
  assert.ok(reads < 24, 'save and delete must finish before the entire search');
  const results = await search;
  assert.equal(results.length, 23);
  assert.ok(!results.some(result => result.id === 'c-yield-23'));
  assert.ok(!results.some(result => result.id === saved.id), 'new records join the next query snapshot');
});
add('rapid query changes cancel between batches before reading a thousand conversations', async () => {
  const service = new ChatHistoryService();
  service.summaries = Array.from({ length: 1000 }, (_, index) => ({
    id: 'c-batch-' + index, title: 'title', updatedAt: index, createdAt: 0
  }));
  let reads = 0, current = true;
  service.readRecord = async id => {
    reads++;
    const record = conversation(id);
    record.messages[1].content = '段落 **重点** '.repeat(500);
    return record;
  };
  const search = service.search('不存在', () => current);
  setTimeout(() => { current = false; }, 0);
  assert.equal((await search).length, 0);
  assert.ok(reads < 1000, 'input must run before scanning the entire corpus');
});
add('search backup recovery stays serialized with a save of the same conversation', async () => {
  const directory = path.join(temporary, 'search-recovery-save');
  const service = new ChatHistoryService();
  await service.initialize(directory);
  const record = conversation('c-search-recovery');
  await service.save(record);
  const filename = path.join(directory, 'chat-history', record.id, 'conversation.json');
  fs.writeFileSync(filename + '.bak', JSON.stringify(record));
  fs.writeFileSync(filename, '{broken');
  const actualRead = fileIo.readText;
  let entered, release;
  const started = new Promise(resolve => { entered = resolve; });
  const gate = new Promise(resolve => { release = resolve; });
  fileIo.readText = async name => {
    if (path.resolve(name) === filename + '.bak') {
      entered(); await gate;
    }
    return actualRead(name);
  };
  try {
    const search = service.search('问题一');
    await started;
    const updated = { ...record, title: '保存后的标题' };
    const save = service.save(updated);
    release();
    await search; await save;
    assert.equal(JSON.parse(fs.readFileSync(filename, 'utf8')).title, updated.title);
    assert.equal((await service.load(record.id)).title, updated.title);
  } finally {
    fileIo.readText = actualRead;
  }
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

add('short writes preserve UTF-8 messages and complete JSON before reporting success', async () => {
  for (const size of [1, 2, 7]) {
    const dir = path.join(temporary, `short-write-${size}`);
    const service = new ChatHistoryService(); await service.initialize(dir);
    const record = conversation(`c-short-${size}`);
    record.messages[1].content = '中文🙂𠮷与组合字符é'.repeat(8);
    const write = fileIo.write; let calls = 0;
    fileIo.write = async (fd, value) => {
      calls++;
      const bytes = Buffer.from(value);
      return fs.writeSync(fd, bytes.subarray(0, size));
    };
    try { await service.save(record); } finally { fileIo.write = write; }
    const restarted = new ChatHistoryService(); await restarted.initialize(dir);
    assert.equal((await restarted.load(record.id)).messages[1].content, record.messages[1].content);
    assert.ok(calls > 2);
  }
});
add('zero-progress and interrupted writes keep the previous record and allow retry', async () => {
  for (const fault of ['zero', 'throw']) {
    const dir = path.join(temporary, `write-failure-${fault}`);
    const service = new ChatHistoryService(); await service.initialize(dir);
    const record = conversation(`c-write-${fault}`); await service.save(record);
    const filename = path.join(dir, 'chat-history', record.id, 'conversation.json');
    const before = fs.readFileSync(filename, 'utf8'); record.messages[1].content = '修改后🙂';
    const write = fileIo.write; let calls = 0;
    fileIo.write = async (fd, value) => {
      if (++calls > 1) {
        if (fault === 'zero') return 0;
        throw new Error('injected write failure');
      }
      return fs.writeSync(fd, Buffer.from(value).subarray(0, 3));
    };
    try { await assert.rejects(service.save(record)); } finally { fileIo.write = write; }
    assert.equal(fs.readFileSync(filename, 'utf8'), before);
    await service.save(record);
    assert.equal((await service.load(record.id)).messages[1].content, '修改后🙂');
  }
});
add('missing or damaged primary index restores active selection from a valid backup', async () => {
  for (const damage of ['missing', 'json', 'version']) {
    const dir = path.join(temporary, `index-recovery-${damage}`);
    const service = new ChatHistoryService(); await service.initialize(dir);
    const record = conversation(`c-index-${damage}`); await service.save(record);
    const filename = path.join(dir, 'chat-history', 'index.json');
    fs.copyFileSync(filename, filename + '.tmp');
    fs.rmSync(filename + '.bak', { force: true }); fs.renameSync(filename, filename + '.bak');
    if (damage !== 'missing') fs.writeFileSync(filename, damage === 'json' ? '{broken' : JSON.stringify({ version: 99, activeId: '' }));
    const restarted = new ChatHistoryService(); const index = await restarted.initialize(dir);
    assert.equal(index.activeId, record.id); assert.equal(restarted.list().length, 1);
    assert.equal((await restarted.load(record.id)).messages[1].content, record.messages[1].content);
    const again = new ChatHistoryService(); assert.equal((await again.initialize(dir)).activeId, record.id);
  }
});
add('primary empty selection wins and backup cannot restore a deleted conversation', async () => {
  const dir = path.join(temporary, 'index-empty-selection');
  const service = new ChatHistoryService(); await service.initialize(dir);
  const record = conversation('c-empty-selection'); await service.save(record); await service.selectEmpty();
  const restarted = new ChatHistoryService(); assert.equal((await restarted.initialize(dir)).activeId, '');
  await restarted.load(record.id); await restarted.remove(record.id);
  const filename = path.join(dir, 'chat-history', 'index.json'); fs.unlinkSync(filename);
  const deleted = new ChatHistoryService(); const index = await deleted.initialize(dir);
  assert.equal(index.activeId, ''); assert.equal(deleted.list().length, 0);
});
add('unreadable indexes rebuild records while valid primary selection takes precedence', async () => {
  const dir = path.join(temporary, 'index-precedence');
  const service = new ChatHistoryService(); await service.initialize(dir);
  await service.save(conversation('c-first')); await service.save(conversation('c-second'));
  const normal = new ChatHistoryService(); assert.equal((await normal.initialize(dir)).activeId, 'c-second');
  const filename = path.join(dir, 'chat-history', 'index.json'); fs.writeFileSync(filename, '{bad'); fs.writeFileSync(filename + '.bak', '{bad');
  const rebuilt = new ChatHistoryService(); assert.equal((await rebuilt.initialize(dir)).activeId, ''); assert.equal(rebuilt.list().length, 2);
});


add('failed attachment copies never publish a partial image and retry copies complete bytes', async () => {
  const dir = path.join(temporary, 'image-partial-copy');
  const service = new ChatHistoryService(); await service.initialize(dir);
  const record = conversation('c-image-partial'); const source = path.join(temporary, 'source-partial.png');
  fs.writeFileSync(source, 'complete image bytes'); record.messages[0].imageUri = source;
  const copy = fileIo.copyFile;
  fileIo.copyFile = async (_fd, name) => { fs.writeFileSync(name, 'co'); throw new Error('injected image copy failure'); };
  try { await assert.rejects(service.save(record), /图片未能保存/); } finally { fileIo.copyFile = copy; }
  const destination = path.join(dir, 'chat-history', record.id, 'image-1');
  assert.equal(fs.existsSync(destination), false);
  await service.save(record); assert.equal(fs.readFileSync(destination, 'utf8'), 'complete image bytes');
});
add('saved attachment replaces the live picker URI without replacing newer message text', async () => {
  const view = await actionView('live-image-copy');
  const question = view.session.lastQuestion(); const source = question.imageUri;
  const copy = fileIo.copyFile;
  fileIo.copyFile = async (fd, name) => { await copy(fd, name); question.content = '保存期间更新的文字'; };
  try { await view.saveCurrentConversation(); } finally { fileIo.copyFile = copy; }
  const stored = await view.historyService.load(view.activeConversationId);
  assert.equal(question.imageUri, stored.messages.find(m => m.id === question.id).imageUri);
  assert.notEqual(question.imageUri, source); assert.equal(question.content, '保存期间更新的文字');
  fs.unlinkSync(source); assert.equal(fs.readFileSync(question.imageUri, 'utf8'), 'original image');
});
add('image cleanup retains current and backup references and leaves other conversations intact', async () => {
  const dir = path.join(temporary, 'image-pruning'); const service = new ChatHistoryService(); await service.initialize(dir);
  const source = path.join(temporary, 'pruning-source.png'); fs.writeFileSync(source, 'fixture');
  const record = conversation('c-images-prune'); record.messages[0].imageUri = source;
  const session = new ChatSession(); session.restore(record.messages); session.appendMessage('user', 'later image', source); session.appendMessage('assistant', 'later answer'); record.messages = session.messages;
  await service.save(record);
  const neighbor = conversation('c-images-neighbor'); neighbor.messages[0].imageUri = source; await service.save(neighbor);
  const folder = path.join(dir, 'chat-history', record.id); const later = path.join(folder, 'image-3');
  record.messages = record.messages.slice(0, 2); await service.save(record);
  assert.equal(fs.existsSync(later), true, 'previous committed backup still references this image');
  await service.save(record); assert.equal(fs.existsSync(later), false, 'unreferenced image must be removed after backup rotation');
  assert.equal(fs.existsSync(path.join(folder, 'image-1')), true);
  assert.equal(fs.existsSync(path.join(dir, 'chat-history', neighbor.id, 'image-1')), true);
  await service.remove(record.id); assert.equal(fs.existsSync(folder), false);
  assert.equal(fs.existsSync(path.join(dir, 'chat-history', neighbor.id, 'image-1')), true);
});


add('an attachment failure keeps question text and retries from the live source when it returns', async () => {
  const view = await actionView('image-copy-retry'); const question = view.session.lastQuestion(); const source = question.imageUri;
  fs.unlinkSync(source); await assert.rejects(view.saveCurrentConversation(), /图片未能保存/);
  const failed = await view.historyService.load(view.activeConversationId);
  assert.equal(failed.messages.find(m => m.id === question.id).imageUnavailable, true);
  assert.equal(question.content, '最后的问题');
  fs.writeFileSync(source, 'restored source'); await view.saveCurrentConversation(); fs.unlinkSync(source);
  assert.equal(fs.readFileSync(question.imageUri, 'utf8'), 'restored source'); assert.equal(question.imageUnavailable, false);
});
add('a late attachment save cannot overwrite a new attachment selection or newer streamed text', async () => {
  const view = await actionView('image-copy-race'); const question = view.session.lastQuestion(); const copy = fileIo.copyFile;
  fileIo.copyFile = async (fd, name) => { await copy(fd, name); question.imageUri = 'new-picker-uri'; question.content = 'new text'; };
  try { await view.saveCurrentConversation(); } finally { fileIo.copyFile = copy; }
  assert.equal(question.imageUri, 'new-picker-uri'); assert.equal(question.content, 'new text');
});
add('an unreadable backup defers attachment cleanup and preserves unrelated files', async () => {
  const dir = path.join(temporary, 'image-backup-guard'); const service = new ChatHistoryService(); await service.initialize(dir);
  const record = conversation('c-image-backup'); await service.save(record);
  const folder = path.join(dir, 'chat-history', record.id); fs.writeFileSync(path.join(folder, 'image-99'), 'backup image'); fs.writeFileSync(path.join(folder, 'user-notes'), 'leave alone');
  fs.writeFileSync(path.join(folder, 'conversation.json'), '{damaged');
  await service.save(record); assert.equal(fs.existsSync(path.join(folder, 'image-99')), true);
  await service.save(record); assert.equal(fs.existsSync(path.join(folder, 'image-99')), false);
  assert.equal(fs.readFileSync(path.join(folder, 'user-notes'), 'utf8'), 'leave alone');
});

add('generated Markdown survives finalization, storage and answer extraction', async () => {
  const { finalAssistantAnswer } = load(path.join(ets, 'utils/generationText.ets'));
  const { parseAssistantText } = load(path.join(ets, 'utils/thinking.ets'));
  const text = '```yaml\na: 1\n---\nb: 2\n```\n\n<s>旧价格</s>，字面量 <|im_end|>。\n第一行  \n第二行。\n本地';
  const service = new ChatHistoryService();
  await service.initialize(path.join(temporary, 'output-fidelity'));
  const record = conversation('c-output-fidelity');
  record.messages[1].content = finalAssistantAnswer({ text, generatedTokens: 20, stopReason: 'eos' });
  await service.save(record);
  const restored = await service.load(record.id);
  assert.equal(restored.messages[1].content, text);
  assert.equal(parseAssistantText(restored.messages[1].content).answer, text);
});

for (const name of ['ChatSession', 'Thinking', 'Markdown', 'GenerationWorkflow', 'GenerationMetrics', 'OpenAiApiServer', 'Knowledge', 'KnowledgeRelations']) {
  const test = path.join(project, 'entry/src/ohosTest/ets/test', name + '.test.ets');
  if (fs.existsSync(test)) load(test).default();
}
(async () => {
  let passed = 0;
  try {
    for (const test of tests) {
      let timeout;
      try {
        await Promise.race([
          Promise.resolve().then(() => test.run()),
          new Promise((_, reject) => {
            timeout = setTimeout(() => reject(new Error('Test timed out: ' + test.name)), 30000);
          })
        ]);
      } finally {
        clearTimeout(timeout);
      }
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
