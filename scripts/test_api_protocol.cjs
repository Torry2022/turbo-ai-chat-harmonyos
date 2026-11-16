// node scripts/test_api_protocol.cjs <path/to/typescript.js>
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(process.argv[2] || 'typescript');
const root = path.resolve(__dirname, '../entry/src/main/ets');
const modules = new Map();
function load(filename) {
  if (modules.has(filename)) return modules.get(filename).exports;
  const module = { exports: {} }; modules.set(filename, module);
  const code = ts.transpileModule(fs.readFileSync(filename, 'utf8'), { compilerOptions: {
    module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020, esModuleInterop: true
  }}).outputText;
  const requireSource = name => {
    if (name.startsWith('.')) return load(path.resolve(path.dirname(filename), name + '.ets'));
    if (name === '@ohos.util') return { TextDecoder: { create: () => new TextDecoder() } };
    return {};
  };
  vm.runInNewContext(code, { module, exports: module.exports, require: requireSource, console,
    setTimeout, clearTimeout }, { filename });
  return module.exports;
}
const { OpenAiApiServer } = load(path.join(root, 'services/OpenAiApiServer.ets'));
const tick = () => new Promise(resolve => setImmediate(resolve));
async function request(responses, stream, stopReason, options = {}, extraResult = {}) {
  const server = new OpenAiApiServer();
  const output = [];
  const logs = [];
  let response, captured, generated = false;
  const state = { connection: { clientId: 1 }, closed: false,
    send: data => output.push(data), closeAfterSend: () => {} };
  server.callbacks = {
    isModelLoaded: () => true, isGenerationReady: () => true,
    currentModel: () => ({ id: 'test', name: 'Test' }),
    currentSettings: () => ({ temperature: 0.7, topP: 0.8, topK: 20, repetitionPenalty: 1.05 }),
    currentMaxNewTokens: () => 128,
    generate: async (_request, onChunk) => {
      captured = _request;
      if (stopReason === 'image_error') { const error = new Error('invalid image'); error.name = 'InvalidImageError'; throw error; }
      const result = { text: '部分回答', generatedTokens: 3, stopReason, ...extraResult };
      generated = true; onChunk(result.text.substring(0, 2));
      return result;
    },
    onRequestState: () => {}, onLog: (_level, message) => logs.push(message)
  };
  server.sendJson = (_state, status, body) => { response = { status, body }; };
  server.sendError = (_state, status, code, message) => { response = { status, code, message }; };
  const body = responses ? { input: '问题', stream, ...options } :
    { messages: [{ role: 'user', content: '问题' }], stream, ...options };
  if (responses) server.handleResponses(state, JSON.stringify(body));
  else server.handleChatCompletions(state, JSON.stringify(body));
  await tick();
  const events = output.flatMap(data => data.split('\n').filter(line => line.startsWith('data: {'))
    .map(line => JSON.parse(line.slice(6))));
  return { response, events, output: output.join(''), generated, captured, logs };
}
(async () => {
  for (const reason of ['eos', 'max_tokens', 'user_stop', 'timeout', 'internal_error', 'unknown']) {
    for (const stream of [false, true]) {
      const actual = await request(true, stream, reason);
      const expected = reason === 'eos' ? 'completed' : reason === 'max_tokens' ? 'incomplete' : 'failed';
      let result;
      if (stream) {
        const terminal = actual.events.filter(event => /^response\.(completed|incomplete|failed)$/.test(event.type));
        assert.equal(terminal.length, 1);
        assert.equal(terminal[0].type, 'response.' + expected);
        result = terminal[0].response;
        const messageDone = actual.events.find(event => event.type === 'response.output_item.done' && event.item.type === 'message');
        assert.equal(messageDone.item.status, expected === 'completed' ? 'completed' : 'incomplete');
      } else { assert.equal(actual.response.status, 200); result = actual.response.body; }
      assert.equal(result.status, expected);
      if (reason === 'max_tokens') assert.equal(result.incomplete_details.reason, 'max_output_tokens');
      if (expected === 'failed') assert.equal(result.error.code, 'server_error');
      assert.equal(result.usage, null);
      const chat = await request(false, stream, reason);
      if (reason === 'eos' || reason === 'max_tokens') {
        const finish = stream ? chat.events.find(event => event.choices?.[0]?.finish_reason)?.choices[0].finish_reason :
          chat.response.body.choices[0].finish_reason;
        assert.equal(finish, reason === 'eos' ? 'stop' : 'length');
      } else if (stream) {
        assert.ok(chat.events.some(event => event.error?.type === 'error'));
        assert.ok(!chat.events.some(event => event.choices?.[0]?.finish_reason));
      } else { assert.equal(chat.response.status, 500); }
    }
  }
  console.log('PASS six stop reasons across both endpoints and streaming modes');
  for (const responses of [false, true]) {
    for (const stream of [false, true]) {
      for (const address of ['data:image/png;base64,AA==', 'https://example.com/picture.png']) {
        const turns = [
          { role: 'system', content: 'system instruction' },
          { role: 'user', content: [{ type: responses ? 'input_image' : 'image_url',
            image_url: responses ? address : { url: address } }, { type: responses ? 'input_text' : 'text', text: 'first question' }] },
          { role: 'assistant', content: 'first answer' }, { role: 'user', content: 'follow-up' }
        ];
        const options = responses ? { input: turns } : { messages: turns };
        const actual = await request(responses, stream, 'eos', options, { inputTokens: 321 });
        assert.equal(actual.captured.turns.length, 4);
        assert.equal(actual.captured.turns[0].content, 'system instruction');
        assert.equal(actual.captured.turns[1].imageUri, address);
        assert.equal(actual.captured.turns[3].imageUri, '');
        const invalid = await request(responses, stream, 'image_error', options);
        assert(invalid.logs.some(message => message.startsWith('400 POST ')));
        if (stream) assert(invalid.output.includes('invalid_request_error'));
        else assert.equal(invalid.response.status, 400);
      }
    }
    const part = { type: responses ? 'input_image' : 'image_url', image_url: 'data:image/png;base64,AA==' };
    for (const messages of [
      [{ role: 'user', content: [part, part] }],
      [{ role: 'assistant', content: [part] }],
      [{ role: 'user', content: [{ ...part, image_url: 'file:///private/image' }] }]
    ]) {
      const actual = await request(responses, false, 'eos', responses ? { input: messages } : { messages });
      assert.equal(actual.response.status, 400);
      assert.equal(actual.generated, false);
    }
  }
  console.log('PASS image parts retain their original turn across both APIs and image errors return 400');

  for (const responses of [false, true]) {
    const unknown = await request(responses, false, 'eos');
    if (!responses) assert.equal(unknown.response.body.usage, undefined);
    const estimated = await request(responses, false, 'eos', {}, { inputTokens: 17, generatedTokensEstimated: true });
    assert.equal(estimated.response.body.usage, responses ? null : undefined);
    const counted = await request(responses, false, 'eos', {}, { inputTokens: 17 });
    const usage = counted.response.body.usage;
    assert.equal(responses ? usage.input_tokens : usage.prompt_tokens, 17);
    assert.equal(usage.total_tokens, 20);
    for (const inputTokens of [-1, 1.2, Infinity]) {
      const missing = await request(responses, false, 'eos', {}, { inputTokens });
      assert.equal(missing.response.body.usage, responses ? null : undefined);
    }
  }
  for (const closed of [false, true]) {
    const text = closed ? '<think>分析</think>答案' : '<think>未结束的分析';
    const actual = await request(true, true, 'max_tokens', {}, { text, inputTokens: 17 });
    const final = actual.events.find(event => event.type === 'response.incomplete').response;
    const reasoning = final.output.find(item => item.type === 'reasoning');
    assert.equal(reasoning.status, closed ? 'completed' : 'incomplete');
    assert.equal(final.usage, null);
    const reasoningDone = actual.events.find(event => event.type === 'response.output_item.done' && event.item.type === 'reasoning');
    assert.equal(reasoningDone.item.status, reasoning.status);
  }
  console.log('PASS measured usage and unknown input counts');
  for (const reason of ['eos', 'max_tokens', 'user_stop']) {
    const actual = await request(false, true, reason, { stream_options: { include_usage: true } }, { inputTokens: 17 });
    const counts = actual.events.filter(event => event.choices?.length === 0);
    if (reason === 'user_stop') {
      assert.equal(counts.length, 0);
    } else {
      assert.equal(counts.length, 1);
      assert.deepEqual(JSON.parse(JSON.stringify(counts[0].usage)), { prompt_tokens: 17, completion_tokens: 3, total_tokens: 20 });
      assert.equal(actual.events.at(-1), counts[0]);
      assert.ok(actual.output.indexOf('"choices":[]') < actual.output.indexOf('[DONE]'));
    }
    for (const event of actual.events.filter(event => event.choices?.length)) assert.equal(event.usage, null);
  }
  const unknownStream = await request(false, true, 'eos', { stream_options: { include_usage: true } });
  assert.equal(unknownStream.events.at(-1).usage, null);
  const ordinaryStream = await request(false, true, 'eos', {}, { inputTokens: 17 });
  assert.ok(ordinaryStream.events.every(event => event.usage === undefined));
  console.log('PASS opt-in streaming usage is final, measured and absent after failure');
  for (const responses of [false, true]) {
    const common = [{ tools: [{ type: 'function' }] }, { tool_choice: 'required' }, { response_format: { type: 'json_object' } },
      { response_format: 'text' }, { response_format: [] },
      { parallel_tool_calls: true }, { n: 2 }, { store: true }, { background: true }];
    const specific = responses ? [{ previous_response_id: 'resp_old' }, { text: { format: { type: 'json_schema' } } },
      { conversation: 'conv_old' }, { reasoning: { effort: 'high' } }, { text: 'text' }, { text: [] },
      { text: { format: 'text' } },
      { response_format: { type: 'json_object' }, text: { format: { type: 'text' } } },
      { response_format: { type: 'json_object' }, text: {} }] : [{ stop: ['END'] }, { seed: 1 },
        { stream_options: 'usage' }, { stream_options: { include_usage: 'true' } }, { stream_options: { include_usage: true } }];
    for (const option of [...common, ...specific]) {
      const rejected = await request(responses, false, 'eos', option);
      assert.equal(rejected.response.status, 400, JSON.stringify(option));
      assert.equal(rejected.generated, false);
    }
    const accepted = await request(responses, false, 'eos', {
      tools: [], tool_choice: 'none', n: 1, store: false, metadata: { label: 'test' },
      ...(responses ? { text: { format: { type: 'text' } } } : { response_format: { type: 'text' } })
    });
    assert.equal(accepted.response.status, 200);
    assert.equal(accepted.generated, true);
  }
  console.log('PASS unsupported semantic options are rejected before generation and harmless defaults remain valid');
  for (const stopReason of ['eos', 'user_stop']) {
    const jobs = [], busy = [];
    const server = new OpenAiApiServer({
      isModelLoaded: () => true, isGenerationReady: () => true,
      currentModel: () => ({ id: 'test', name: 'Test' }),
      generate: () => new Promise(resolve => jobs.push(resolve)), stopGeneration: () => {},
      onRequestState: (_kind, active) => busy.push(active), onLog: () => {}, onStatus: () => {}
    });
    const state = () => ({ connection: { clientId: 7 }, closed: false, send: () => {}, closeAfterSend: () => {} });
    const old = state(), current = state();
    server.sendJson = () => {}; server.sendError = () => {};
    const input = { turns: [{ role: 'user', content: 'test' }], maxNewTokens: 8, settings: {} };
    server.running = true;
    server.runGeneration(old, '', false, false, input);
    await server.stop();
    server.runGeneration(current, '', false, false, input);
    const before = busy.length;
    jobs[0]({ text: 'old', generatedTokens: 1, stopReason });
    await tick();
    assert.equal(server.activeConnection, current);
    assert.equal(server.activeClientId, 7);
    assert.equal(busy.length, before);
    jobs[1]({ text: 'new', generatedTokens: 1, stopReason: 'eos' });
    await tick();
    assert.equal(server.activeClientId, -1);
    assert.equal(busy.at(-1), false);
  }
  console.log('PASS old generation completion cannot clear a restarted request with a reused client ID');
  for (const responses of [false, true]) {
    let emit;
    const output = [];
    const server = new OpenAiApiServer({
      isModelLoaded: () => true, isGenerationReady: () => true,
      currentModel: () => ({ id: 'test', name: 'Test' }),
      generate: async (_request, onChunk) => {
        emit = onChunk;
        onChunk('回答');
        return { text: '回答', generatedTokens: 1, stopReason: 'eos' };
      },
      stopGeneration: () => {}, onRequestState: () => {}, onLog: () => {}, onStatus: () => {}
    });
    const state = { connection: { clientId: 1 }, closed: false,
      send: data => output.push(data), closeAfterSend: () => {} };
    server.runGeneration(state, '', true, responses,
      { turns: [{ role: 'user', content: 'test' }], maxNewTokens: 8, settings: {} });
    await tick();
    const terminalOutput = output.join('');
    emit('迟到片段');
    await tick();
    assert.equal(output.join(''), terminalOutput);
  }
  console.log('PASS late native chunks cannot append events after either streaming endpoint terminates');
})().catch(error => { console.error(error); process.exitCode = 1; });
