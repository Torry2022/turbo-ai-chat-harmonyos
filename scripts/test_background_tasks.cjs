// node scripts/test_background_tasks.cjs <path/to/typescript.js>
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(process.argv[2] || 'typescript');
const root = path.resolve(__dirname, '../entry/src/main/ets');
const active = new Map(), listeners = new Set(), notices = [], stopped = [], cancelledDelays = [];
let nextId = 1, nextFailure = false, stopFailure = false, startGate;
const deviceInfo = { deviceType: '2in1' };
const powerCalls = [];
let powerGate, powerFailure = false, powerResult = 0;
const backgroundProcessManager = {
  PowerSaveMode: { EFFICIENCY_MODE: 1, DEFAULT_MODE: 2 },
  setPowerSaveMode: (pid, mode) => {
    powerCalls.push([pid, mode]);
    if (powerFailure) throw new Error('power mode unavailable');
    return powerGate || powerResult;
  }
};
const manager = {
  ContinuousTaskRequest: class {},
  BackgroundTaskMode: { MODE_TASK_KEEPING: 9, MODE_DATA_TRANSFER: 1 },
  BackgroundTaskSubmode: { SUBMODE_NORMAL_NOTIFICATION: 1, SUBMODE_LIVE_VIEW_NOTIFICATION: 2 },
  on: (_name, callback) => listeners.add(callback), off: (_name, callback) => listeners.delete(callback),
  startBackgroundRunning: async (_context, request) => {
    if (startGate) await startGate;
    if (nextFailure) { nextFailure = false; throw new Error('denied'); }
    const id = nextId++;
    active.set(id, request);
    return { continuousTaskId: id, notificationId: id + 100 };
  },
  stopBackgroundRunning: async (_context, id) => {
    if (stopFailure) { stopFailure = false; throw new Error('temporary stop failure'); }
    stopped.push(id); active.delete(id);
  },
  requestSuspendDelay: () => ({ requestId: nextId++ }),
  cancelSuspendDelay: id => cancelledDelays.push(id)
};
const ability = { wantAgent: {
  getWantAgent: async info => info, OperationType: { START_ABILITY: 0 },
  WantAgentFlags: { UPDATE_PRESENT_FLAG: 0 }
} };
const notification = { notificationManager: {
  ContentType: { NOTIFICATION_CONTENT_SYSTEM_LIVE_VIEW: 3 }, SlotType: { LIVE_VIEW: 4 },
  publish: async info => notices.push(info)
} };
const cache = new Map();
function load(filename) {
  if (cache.has(filename)) return cache.get(filename).exports;
  const module = { exports: {} }; cache.set(filename, module);
  const code = ts.transpileModule(fs.readFileSync(filename, 'utf8'), { compilerOptions: {
    module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020
  }}).outputText;
  const requireSource = name => {
    if (name.startsWith('.')) return load(path.resolve(path.dirname(filename), name + '.ets'));
    if (name === '@kit.BackgroundTasksKit') return { backgroundTaskManager: manager, backgroundProcessManager };
    if (name === '@kit.ArkTS') return { process: { pid: 1234 } };
    if (name === '@kit.AbilityKit') return ability;
    if (name === '@kit.BasicServicesKit') return { deviceInfo };
    if (name === '@kit.NotificationKit') return notification;
    return {};
  };
  vm.runInNewContext(code, { module, exports: module.exports, require: requireSource, console, Date }, { filename });
  return module.exports;
}
const { BackgroundTaskService } = load(path.join(root, 'services/BackgroundTaskService.ets'));
const context = { abilityInfo: { name: 'EntryAbility', bundleName: 'test.bundle' } };
const tick = () => new Promise(resolve => setImmediate(resolve));
const settle = async service => { await Promise.all([service.compute.queue, service.download.queue]); await tick(); };
const create = () => { const service = new BackgroundTaskService(); service.initialize(context); return service; };
const timeout = setTimeout(() => { console.error('Background task tests timed out'); process.exitCode = 1; }, 30000);
(async () => {
  const service = create();
  service.setComputeActive(true); service.setComputeActive(true);
  await settle(service);
  const computeId = service.compute.id;
  assert.equal(active.size, 1);
  assert.equal(active.get(computeId).backgroundTaskModes[0], 9);
  service.setDownloadActive(true, 10, 'test model');
  await settle(service);
  assert.equal(active.size, 2);
  assert.equal(active.get(service.download.id).backgroundTaskModes[0], 1);
  assert.equal(notices.at(-1).id, service.download.notificationId);
  assert.equal(notices.at(-1).template.data.progressValue, 10);
  service.lastPublishedAt = 0;
  service.setDownloadActive(true, 25, 'test model');
  await settle(service);
  assert.equal(notices.at(-1).template.data.progressValue, 25);
  service.setDownloadActive(false, 25, 'test model');
  await settle(service);
  assert.equal(active.size, 1);
  assert.ok(active.has(computeId));
  service.setComputeActive(false);
  await settle(service);
  assert.equal(active.size, 0);
  service.dispose(); await settle(service);
  assert.equal(listeners.size, 0);
  console.log('PASS independent computation/download tasks, deduplication, progress and release');

  const pending = create();
  let release;
  startGate = new Promise(resolve => { release = resolve; });
  pending.setComputeActive(true);
  await tick();
  pending.dispose(); release(); startGate = undefined;
  await settle(pending);
  assert.equal(active.size, 0);
  assert.ok(stopped.includes(pending.compute.id) || pending.compute.id === -1);

  const cancelled = create();
  cancelled.setComputeActive(true); cancelled.setComputeActive(false);
  await settle(cancelled);
  assert.equal(active.size, 0);
  cancelled.dispose(); await settle(cancelled);
  console.log('PASS cancel before registration and dispose while registration is pending');

  const failed = create();
  let warnings = 0;
  failed.onUnavailable = () => warnings++;
  nextFailure = true;
  failed.setComputeActive(true); await settle(failed);
  assert.equal(warnings, 1); assert.equal(active.size, 0);
  failed.setComputeActive(true); await settle(failed);
  assert.equal(warnings, 1);
  failed.setComputeActive(false); failed.setComputeActive(true); await settle(failed);
  assert.equal(active.size, 1);
  const id = failed.compute.id;
  active.delete(id);
  for (const callback of listeners) callback({ id, reason: 0 });
  failed.refresh(); await settle(failed);
  assert.equal(active.size, 0); assert.equal(warnings, 2);
  failed.setComputeActive(false); failed.setComputeActive(true); await settle(failed);
  assert.equal(active.size, 1);
  stopFailure = true;
  failed.setComputeActive(false); await settle(failed);
  assert.equal(active.size, 1);
  failed.refresh(); await settle(failed);
  assert.equal(active.size, 0);
  failed.dispose(); await settle(failed);
  console.log('PASS registration failure, explicit retry, user cancellation and release retry on foreground');

  const performance = create();
  performance.setPerformanceState(true, true); await performance.performanceQueue;
  assert.equal(powerCalls.length, 0);
  performance.setPerformanceState(false, true); await performance.performanceQueue;
  assert.deepEqual(powerCalls.at(-1), [1234, 1]);
  performance.setPerformanceState(false, true); await performance.performanceQueue;
  assert.equal(powerCalls.length, 1);
  performance.setPerformanceState(false, false); await performance.performanceQueue;
  assert.deepEqual(powerCalls.at(-1), [1234, 2]);
  let finishPower;
  powerGate = new Promise(resolve => { finishPower = resolve; });
  performance.setPerformanceState(false, true); await tick();
  performance.setPerformanceState(true, true);
  powerGate = undefined; finishPower(); await performance.performanceQueue;
  assert.deepEqual(powerCalls.slice(-2), [[1234, 1], [1234, 2]]);
  powerFailure = true;
  performance.setPerformanceState(false, true); await performance.performanceQueue;
  assert.equal(performance.performanceApplied, false);
  powerFailure = false;
  performance.setPerformanceState(true, false); await performance.performanceQueue;
  powerResult = 7;
  performance.setPerformanceState(false, true); await performance.performanceQueue;
  assert.equal(performance.performanceApplied, false);
  powerResult = 0;
  performance.dispose(); await performance.performanceQueue;
  console.log('PASS PC background inference mode, synchronous return, race and failure handling');

  deviceInfo.deviceType = 'phone';
  const phone = create();
  const callsBeforePhone = powerCalls.length;
  phone.setPerformanceState(false, true); await phone.performanceQueue;
  assert.equal(powerCalls.length, callsBeforePhone);
  phone.setComputeActive(true); await settle(phone);
  assert.equal(phone.computeSupported, false); assert.equal(active.size, 0);
  phone.setDownloadActive(true, 0, 'phone model'); await settle(phone);
  assert.equal(active.size, 1);
  let saved = false;
  await phone.saveBeforeSuspend(async () => { saved = true; });
  assert.equal(saved, true);
  const before = cancelledDelays.length;
  await assert.rejects(phone.saveBeforeSuspend(async () => { throw new Error('save failed'); }));
  assert.equal(cancelledDelays.length, before + 1);
  phone.dispose(); await settle(phone);
  assert.equal(active.size, 0); assert.equal(listeners.size, 0);
  console.log('PASS phone capability boundary and short-save cleanup on success or failure');
})().catch(error => { console.error(error); process.exitCode = 1; }).finally(() => clearTimeout(timeout));
