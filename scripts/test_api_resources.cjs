// node scripts/test_api_resources.cjs <path/to/typescript.js>
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(process.argv[2] || 'typescript');
const root = path.resolve(__dirname, '../entry/src/main/ets');
const modules = new Map();
const timers = new Map();
let timerId = 0;
function load(filename) {
  if (modules.has(filename)) return modules.get(filename).exports;
  const module = { exports: {} }; modules.set(filename, module);
  const code = ts.transpileModule(fs.readFileSync(filename, 'utf8'), { compilerOptions: {
    module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020, esModuleInterop: true
  }}).outputText;
  const requireSource = name => {
    if (name.startsWith('.')) return load(path.resolve(path.dirname(filename), name + '.ets'));
    if (name === '@ohos.util') return { TextDecoder: { create: () => {
      const decoder = new TextDecoder();
      return { decodeToString: (data, options) => decoder.decode(data, options) };
    } } };
    return {};
  };
  vm.runInNewContext(code, { module, exports: module.exports, require: requireSource, console,
    setTimeout: (callback, delay) => { const id = ++timerId; timers.set(id, { callback, delay }); return id; },
    clearTimeout: id => timers.delete(id) }, { filename });
  return module.exports;
}
const { OpenAiApiServer } = load(path.join(root, 'services/OpenAiApiServer.ets'));
const tick = () => new Promise(resolve => setImmediate(resolve));
class Client {
  constructor(id) { this.clientId = id; this.handlers = {}; this.sent = []; this.closes = 0; }
  on(name, callback) { this.handlers[name] = callback; }
  close() { this.closes++; this.handlers.close?.(); return Promise.resolve(); }
  send({ data }) { this.sent.push(data); return Promise.resolve(); }
  emit(data) { this.handlers.message({ message: new TextEncoder().encode(data).buffer }); }
}
let stops = 0, rerankStops = 0;
const callbacks = { stopGeneration: () => stops++, cancelRerank: () => rerankStops++,
  onStatus: () => {}, onLog: () => {}, onRequestState: () => {} };
function accept(server, client) { server.acceptClient(client); return server.connections.get(client.clientId); }
function expire(delay) {
  for (const [id, timer] of [...timers]) {
    if (timer.delay === delay && timers.delete(id)) timer.callback();
  }
}
(async () => {
  const server = new OpenAiApiServer(callbacks);
  const clients = Array.from({ length: 20 }, (_, id) => new Client(id));
  clients.forEach(client => accept(server, client));
  assert.equal(server.connections.size, 16);
  assert.ok(clients.slice(16).every(client => client.closes === 1));
  clients[0].emit('POST /v1/responses HTTP/1.1\r\nContent-Length: 100\r\n');
  expire(15000);
  assert.equal(server.connections.size, 0);
  assert.equal(timers.size, 0);
  console.log('PASS connection cap and absolute receive deadline, including partial headers');

  const client = new Client(30);
  const state = accept(server, client);
  server.route = (_state, request) => { assert.equal(request.body, '好'); };
  const request = new TextEncoder().encode('POST /v1/responses HTTP/1.1\r\nContent-Length: 3\r\n\r\n好');
  for (const byte of request) server.handleClientData(state, new Uint8Array([byte]).buffer);
  assert.equal(state.handled, true);
  assert.equal(state.buffer, '');
  assert.equal(timers.size, 0);
  state.send('one'); state.send('二'); state.closeAfterSend();
  await tick();
  assert.deepEqual(client.sent, ['one', '二']);
  assert.equal(client.closes, 1);
  assert.equal(server.connections.size, 0);
  console.log('PASS split UTF-8 input, ordered sends and drained close');

  const oversized = new Client(31);
  const oversizedState = accept(server, oversized);
  server.handleClientData(oversizedState, new ArrayBuffer(1024 * 1024 + 1));
  await tick();
  assert.ok(oversized.sent.join('').startsWith('HTTP/1.1 413'));
  assert.equal(oversizedState.buffer, '');
  assert.equal(server.connections.size, 0);

  for (const failure of ['rejected', 'timeout', 'queue', 'manual']) {
    const slow = new Client(40);
    slow.send = () => failure === 'rejected' ? Promise.reject(new Error('send rejected')) : new Promise(() => {});
    const pending = accept(server, slow);
    pending.finishRequest();
    server.activeClientId = 40; server.activeRequestKind = 'chat';
    server.activeConnection = pending;
    const previousStops = stops;
    pending.send('first');
    if (failure === 'queue') pending.send('中'.repeat(Math.ceil(4 * 1024 * 1024 / 3)));
    if (failure === 'timeout') expire(30000);
    if (failure === 'manual') pending.close();
    await tick();
    assert.equal(pending.closed, true, failure);
    assert.equal(pending.sending, false, failure);
    assert.equal(pending.pendingBytes, 0);
    assert.equal(pending.pending.length, 0);
    assert.equal(server.connections.size, 0);
    assert.equal(stops, previousStops + 1);
    assert.equal(timers.size, 0);
    assert.equal(slow.closes, 1);
    server.activeClientId = -1; server.activeRequestKind = '';
    server.activeConnection = undefined;
  }
  console.log('PASS send rejection, timeout, UTF-8 queue limit and close during stalled send');

  const old = new Client(50);
  const oldState = accept(server, old);
  server.rerankConnection = oldState;
  old.handlers.error(new Error('lost connection'));
  assert.equal(rerankStops, 1);
  server.rerankConnection = undefined;
  const replacement = new Client(50);
  const replacementState = accept(server, replacement);
  old.handlers.close(); old.handlers.error(new Error('late event'));
  assert.equal(server.connections.get(50), replacementState);
  server.running = true;
  await server.stop();
  assert.equal(server.connections.size, 0);
  assert.equal(timers.size, 0);
  assert.equal(replacement.closes, 1);
  const alreadyClosed = new Client(60);
  const closing = accept(server, alreadyClosed);
  alreadyClosed.close = () => { throw new Error('socket already closed'); };
  closing.close();
  assert.equal(server.connections.size, 0);
  assert.equal(timers.size, 0);
  console.log('PASS rerank cancellation, late old-client events and stop cleanup');
})().catch(error => { console.error(error); process.exitCode = 1; });
