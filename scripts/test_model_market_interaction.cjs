const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const ts = require(process.argv[2] || 'typescript');

const source = fs.readFileSync('entry/src/main/ets/components/ModelMarketDialog.ets', 'utf8');
const callback = source.match(/onChange:\s*\(type: ModelType\): void => \{([\s\S]*?)\n\s*\}/);
assert(callback, 'Model market category callback must exist');
const code = ts.transpileModule(`(type: string) => { ${callback[1]} }`, {
  compilerOptions: { target: ts.ScriptTarget.ES2020 }
}).outputText;
const selected = [];
const handler = vm.runInNewContext(code, {
  searchController: { stopEditing() {} },
  viewModel: { updateModelMarketCategory: type => selected.push(type) }
});
for (const type of ['chat', 'decision', 'embedding', 'rerank']) handler(type);
assert.deepEqual(selected, ['chat', 'decision', 'embedding', 'rerank']);
handler('unknown');
assert.equal(selected.length, 4);
console.log('PASS model market routes all four category clicks');

const filterCondition = source.match(/if \((this\.viewModel\.modelMarketCategory[^\n]*modelCatalogFilterTags\(\)\.length > 1)\) \{/);
assert(filterCondition, 'Capability filter visibility condition must exist');
const filterState = { modelMarketCategory: 'chat', modelCatalogFilterTags: () => ['全部', '图像理解'] };
const showFilters = vm.runInNewContext(`() => ${filterCondition[1]}`, { viewModel: filterState });
for (const category of ['chat', 'decision', 'embedding', 'rerank']) {
  filterState.modelMarketCategory = category;
  assert.equal(showFilters(), category === 'chat');
}
filterState.modelMarketCategory = 'chat';
filterState.modelCatalogFilterTags = () => ['全部'];
assert.equal(showFilters(), false);
console.log('PASS only conversation models display capability filters');

const viewSource = fs.readFileSync('entry/src/main/ets/state/ChatViewModel.ets', 'utf8');
const viewAst = ts.createSourceFile('view.ts', viewSource, ts.ScriptTarget.Latest, true);
const viewClass = viewAst.statements.find(node => ts.isClassDeclaration(node) && node.name.text === 'ChatViewModel');
const statusMethod = viewClass.members.find(node => node.name && node.name.getText(viewAst) === 'modelMarketStatus');
const statusCode = ts.transpileModule(`class Subject { ${statusMethod.getText(viewAst)} }`, {
  compilerOptions: { target: ts.ScriptTarget.ES2020 }
}).outputText;
const Subject = vm.runInNewContext(statusCode + '\nSubject');
const subject = new Subject();
Object.assign(subject, { modelCatalogRefreshFailed: true, modelCatalogRefreshing: false,
  modelCatalogStatus: '暂时无法更新目录，当前目录仍可使用',
  modelCatalogService: { rerankerStatus: () => '尚未获取模型目录，请刷新' } });
for (const type of ['chat', 'decision', 'embedding', 'rerank']) {
  subject.modelMarketCategory = type;
  assert.equal(subject.modelMarketStatus(), subject.modelCatalogStatus);
}
subject.modelCatalogRefreshFailed = false;
assert.equal(subject.modelMarketStatus(), '尚未获取模型目录，请刷新');
console.log('PASS offline gallery status is consistent while retaining source-specific availability');

async function checkDownloadTaskRecovery() {
  const methods = ['restoreModelDownloadTask', 'saveModelDownloadTask', 'syncBuiltinModelInstallPartialProgress',
    'openModelDownloadTask', 'discardModelDownloadTask', 'clearModelDownloadTask'];
  const code = ts.transpileModule('class DownloadTask {\n' + viewClass.members
    .filter(node => methods.includes(node.name?.getText(viewAst)))
    .map(node => node.getText(viewAst)).join('\n') + '\n}', {
    compilerOptions: { target: ts.ScriptTarget.ES2020 }
  }).outputText;
  let pendingId = '';
  let storedId = '';
  const store = {
    getSync: () => storedId,
    put: async (_key, value) => { pendingId = value; },
    flush: async () => { storedId = pendingId; }
  };
  const DownloadTask = vm.runInNewContext(code + '\nDownloadTask', {
    preferences: { getPreferencesSync: () => store },
    calculateDownloadProgress: (bytes, total) => bytes / total * 100
  });
  const spec = { id: 'fixture', displayName: 'Fixture', totalBytes: 100 };
  let savedBytes = 37;
  const makeView = () => Object.assign(new DownloadTask(), {
    context: {}, builtinModelInstallDownloadedBytes: 0, builtinModelInstallFileName: '',
    modelCatalogService: { findMarketItem: id => id === spec.id ? spec : undefined, findInstallItem: () => undefined },
    builtinModelInstallService: {
      existingPartialDownloadBytes: async () => savedBytes,
      clearPartialDownload: async () => { savedBytes = 0; }
    },
    notify() {}, toastCallback() {}
  });
  await makeView().saveModelDownloadTask(spec.id);
  const reopened = makeView();
  reopened.restoreModelDownloadTask(reopened.context);
  await Promise.resolve();
  assert.equal(reopened.modelDownloadTaskActive, true);
  assert.equal(reopened.builtinModelInstallCanceled, true);
  assert.ok(!reopened.builtinModelInstalling && !reopened.showBuiltinModelInstallDialog);
  assert.equal(reopened.builtinModelInstallDownloadedBytes, 37);
  assert.equal(reopened.builtinModelInstallProgress, 37);
  reopened.openModelDownloadTask();
  assert.equal(reopened.showBuiltinModelInstallDialog, true);
  await reopened.discardModelDownloadTask();
  assert.equal(savedBytes, 0);
  const nextLaunch = makeView();
  nextLaunch.restoreModelDownloadTask(nextLaunch.context);
  assert.ok(!nextLaunch.modelDownloadTaskActive);
  console.log('PASS interrupted download is restored at the saved progress and explicit cancellation clears it');
}
checkDownloadTaskRecovery().catch(error => { console.error(error); process.exitCode = 1; });

{
  const methods = ['modelDownloadCompleted', 'openCompletedModelDownload',
    'showModelDownloadCompletion', 'clearModelDownloadCompletion', 'presentModelDownloadCompletion',
    'showModelDownloadFailure', 'setAppForeground'];
  const code = ts.transpileModule('class Completion {\n' + viewClass.members
    .filter(node => methods.includes(node.name?.getText(viewAst)))
    .map(node => node.getText(viewAst)).join('\n') + '\n}', {
    compilerOptions: { target: ts.ScriptTarget.ES2020 }
  }).outputText;
  const timers = new Map();
  let timerId = 0;
  let notifications = 0;
  let loads = 0;
  const toasts = [];
  const Completion = vm.runInNewContext(code + '\nCompletion', {
    setTimeout: (callback, delay) => {
      assert.equal(delay, 1250);
      timers.set(++timerId, callback);
      return timerId;
    },
    clearTimeout: id => timers.delete(id)
  });
  const completion = Object.assign(new Completion(), {
    modelDownloadCompletionTimer: -1,
    updateModelPageCategory(category) { this.category = category; },
    notify() { notifications++; },
    currentModel: () => ({ id: 'qwen-test' }),
    openModelLoadDialog() { assert.fail('Automatic load initializes its own progress dialog'); },
    startModelLoad() { loads++; },
    toastCallback(message) { toasts.push({ message, checkmark: this.modelDownloadCompleted }); },
    reranker: { busy: false },
    backgroundTasks: { setPerformanceState() {}, refresh() {} },
    setConversationTitleActive() {}
  });
  assert.equal(completion.openCompletedModelDownload(), false);
  completion.showModelDownloadCompletion('embedding');
  assert.equal(completion.modelDownloadCompleted, true);
  assert.equal(completion.openCompletedModelDownload(), true);
  assert.equal(completion.category, 'embedding');
  assert.equal(completion.modelDownloadCompleted, false);
  assert.equal(timers.size, 0);
  completion.showModelDownloadCompletion('chat');
  [...timers.values()][0]();
  assert.equal(completion.modelDownloadCompleted, false);
  assert.equal(notifications, 1);
  assert.equal(timers.size, 0);
  const collapsed = { modelName: 'Qwen Test', category: 'chat', autoLoadModelId: '', startApi: false };
  completion.presentModelDownloadCompletion(collapsed);
  assert.deepEqual(toasts.splice(0), [{ message: 'Qwen Test 下载完成', checkmark: true }]);
  assert.equal(completion.openCompletedModelDownload(), true);
  assert.equal(loads, 0);
  completion.pendingModelDownloadCompletion = collapsed;
  completion.setAppForeground(true);
  completion.setAppForeground(true);
  assert.deepEqual(toasts.splice(0), [{ message: 'Qwen Test 下载完成', checkmark: true }]);
  completion.clearModelDownloadCompletion();
  completion.pendingModelDownloadCompletion = {
    modelName: 'Qwen Test', autoLoadModelId: 'qwen-test', startApi: true
  };
  completion.setAppForeground(true);
  assert.equal(loads, 1);
  assert.equal(completion.apiServerStartAfterModelLoad, true);
  assert.equal(toasts.length, 0);
  completion.pendingModelDownloadFailure = true;
  completion.builtinModelInstallModelName = 'Qwen Test';
  completion.setAppForeground(true);
  assert.deepEqual(toasts.splice(0), [{ message: 'Qwen Test 安装未完成，请打开下载任务重试', checkmark: false }]);
  console.log('PASS completion feedback follows the panel, floating button and foreground return');
}
