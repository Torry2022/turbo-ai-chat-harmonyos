// Run: node scripts/test_runtime_stats.cjs <path/to/typescript.js>
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(process.argv[2] || 'typescript');
const root = path.resolve(__dirname, '..');
let now = 10000, reads = 0, storageReads = 0, fail = false;
const device = { sdkApiVersion: 24 };
const memory = { pss: 2048n, rss: 1024n };
const debug = {
  getAppNativeMemInfo: () => { reads++; return memory; },
  getAppNativeMemInfoAsync: async () => { reads++; if (fail) throw new Error('unavailable'); return memory; },
  getRssInfo: () => ({ swapRss: 512n }),
  getSystemMemInfo: () => ({ totalMem: 32768n, availableMem: 8192n }),
  getCpuUsage: () => 0.125, getSystemCpuUsage: () => 0.25,
  getNativeHeapAllocatedSize: () => 1048576n, getNativeHeapSize: () => 2097152n,
  getAppThreadCpuUsage: () => [{}, {}, {}]
};
function compile(relative, requireModule = () => ({}), extras = {}) {
  const source = fs.readFileSync(path.join(root, relative), 'utf8');
  const context = { exports: {}, require: requireModule, Date: { now: () => now }, console, ...extras };
  vm.runInNewContext(ts.transpileModule(source, { compilerOptions: {
    module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020
  } }).outputText, context);
  return context.exports;
}
const models = compile('entry/src/main/ets/models/RuntimeStats.ets');
const formatters = compile('entry/src/main/ets/utils/formatters.ets');
const { RuntimeStatsService } = compile('entry/src/main/ets/services/RuntimeStatsService.ets', name => {
  if (name === '@ohos.hidebug') return { default: debug };
  if (name === '@ohos.deviceInfo') return { default: device };
  if (name === '@ohos.batteryInfo') return { default: { batteryTemperature: 325 } };
  if (name === '@kit.CoreFileKit') return { storageStatistics: { getCurrentBundleStats: async () => {
    storageReads++; return { appSize: 10, dataSize: 20, cacheSize: 30 };
  } } };
  if (name.includes('RuntimeStats')) return models;
  if (name.includes('formatters')) return formatters;
  return { default: {} };
});
(async () => {
  const service = new RuntimeStatsService();
  const [first, second] = await Promise.all([service.readSample(), service.readSample()]);
  assert.equal(reads, 1);
  assert.equal(first, second);
  assert.equal(first.pssWithSwapBytes, 2048 * 1024);
  assert.equal(first.rssBytes, 1024 * 1024);
  assert.equal(first.swapBytes, 512 * 1024);
  assert.equal(first.nativeHeapAllocatedBytes, 1048576);
  assert.equal(first.appCpuPercent, 12.5);
  assert.equal(first.batteryTemperatureC, 32.5);
  assert.equal(service.readStats().appRss, '1.0 MB');
  assert.equal(reads, 1, 'UI and API share the same fresh sample');
  assert.doesNotThrow(() => JSON.stringify(first), 'No bigint in the public JSON');
  now += 1001; device.sdkApiVersion = 19;
  assert.equal((await service.readSample()).swapBytes, null);
  now += 1001; device.sdkApiVersion = 24; fail = true;
  await assert.rejects(service.readSample(), /unavailable/);
  fail = false;
  assert.equal((await service.readSample()).sampledAt, now);
  service.exists = async () => true;
  service.pathSize = async name => name === '/model-a' ? 100 : 200;
  const a = await service.readStorageSample('/app', '/model-a');
  const cached = await service.readStorageSample('/app', '/model-a');
  assert.equal(a.appBytes, 60); assert.equal(cached.currentModelBytes, 100);
  assert.equal(storageReads, 1, 'Polling does not rescan storage');
  const b = await service.readStorageSample('/app', '/model-b');
  assert.equal(b.currentModelBytes, 200, 'Changing model invalidates storage cache');
  now += 30001;
  await service.readStorageSample('/app', '/model-b');
  assert.equal(storageReads, 3);
  console.log('PASS numeric units, shared samples, old SDK fallback, errors and storage freshness');

  const source = fs.readFileSync(path.join(root, 'entry/src/main/ets/services/OpenAiApiServer.ets'), 'utf8');
  const ast = ts.createSourceFile('server.ts', source, ts.ScriptTarget.Latest, true);
  const node = ast.statements.find(n => ts.isClassDeclaration(n) && n.name.text === 'OpenAiApiServer');
  const context = { exports: {}, errorMessage: error => error.message };
  vm.runInNewContext(ts.transpileModule(node.getText(ast), { compilerOptions: {
    module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020
  } }).outputText, context);
  let snapshots = 0, payload, status, unavailable = false;
  const server = new context.exports.OpenAiApiServer({
    onLog: () => {}, runtimeSnapshot: async () => {
      snapshots++; if (unavailable) throw new Error('failed');
      return { chatModel: { id: 'test', name: 'Test', loaded: false, loading: false, generating: false }, metrics: first, storage: a };
    }
  });
  server.config = { port: 8080, target: 'chat', requireApiKey: true, apiKey: 'secret' };
  server.sendJson = (_state, code, body) => { status = code; payload = body; };
  server.sendError = (_state, code) => { status = code; };
  const state = { closed: false };
  const request = (method = 'GET', key = 'secret') => ({ method, path: '/turbo/runtime', body: '', headers: new Map([['authorization', `Bearer ${key}`]]) });
  const tick = () => new Promise(resolve => setImmediate(resolve));
  server.route(state, request('GET', 'wrong')); await tick();
  assert.equal(status, 401); assert.equal(snapshots, 0);
  server.activeClientId = 42;
  server.route(state, request()); await tick();
  assert.equal(status, 200); assert.equal(payload.service.inferenceBusy, true);
  assert.equal(payload.chatModel.loaded, false, 'Metrics route does not require a loaded model');
  assert.equal(payload.metrics.appCpuPercent, 12.5);
  assert.ok(!JSON.stringify(payload).includes('secret'));
  server.route(state, request('POST')); await tick(); assert.equal(status, 404);
  unavailable = true;
  server.route(state, request()); await tick(); assert.equal(status, 503);
  status = undefined; state.closed = true;
  server.route(state, request()); await tick(); assert.equal(status, undefined);
  console.log('PASS authenticated read-only runtime route, active generation, failure and disconnected clients');
})().catch(error => { console.error(error); process.exitCode = 1; });
