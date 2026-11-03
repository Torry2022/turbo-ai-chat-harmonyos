// Run with Node and the TypeScript compiler bundled with DevEco:
// node scripts/test_catalog_storage.cjs <path/to/typescript.js>
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(process.argv[2] || 'typescript');
const sourceRoot = path.resolve(__dirname, '../entry/src/main/ets');
const modules = new Map();
const files = new Map();
let remote;
let requestedUrl;
let replies = [];
let requests = [];
let destroyed = 0;
let officialResponse;
let rerankerResponse;
let descriptionResponse;
let urlResponses = new Map();
const mockFs = {
  OpenMode: { WRITE_ONLY: 1, CREATE: 2, TRUNC: 4 },
  access: async (name) => files.has(name),
  readText: async (name) => {
    assert(files.has(name), `Missing file: ${name}`);
    return files.get(name);
  },
  openSync: (name) => { files.set(name, ''); return { fd: name }; },
  writeSync: (name, text) => files.set(name, text),
  closeSync: () => {},
  unlink: async (name) => files.delete(name),
  rename: async (from, to) => {
    assert(files.has(from));
    files.set(to, files.get(from));
    files.delete(from);
  }
};
function load(name) {
  if (modules.has(name)) return modules.get(name).exports;
  const module = { exports: {} };
  modules.set(name, module);
  const source = fs.readFileSync(name, 'utf8');
  const code = ts.transpileModule(source, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText;
  const localRequire = (id) => {
    if (id === '@kit.PerformanceAnalysisKit') return { hilog: { warn: () => {}, info: () => {} } };
    if (id === '@ohos.file.fs') return { default: mockFs };
    if (id === '@ohos.net.http') return { default: {
      RequestMethod: { GET: 'GET', PUT: 'PUT' }, HttpDataType: { STRING: 'string' },
      createHttp: () => ({
        request: async (url, options) => {
          requestedUrl = url;
          requests.push({ url, options });
          if (urlResponses.has(url)) {
            const reply = urlResponses.get(url);
            if (reply instanceof Error) throw reply;
            return reply;
          }
          if (url.includes('model_descriptions_zh.json')) {
            if (descriptionResponse instanceof Error) throw descriptionResponse;
            return descriptionResponse || { responseCode: 503, result: '' };
          }
          if (url === 'https://modelscope.cn/api/v1/models') return rerankerResponse || { responseCode: 503, result: '' };
          if (url.includes('meta.alicdn.com')) {
            if (officialResponse instanceof Error) throw officialResponse;
            return officialResponse || { responseCode: 503, result: '' };
          }
          if (replies.length) {
            const reply = replies.shift();
            if (reply instanceof Error) throw reply;
            return reply;
          }
          return { responseCode: 200, result: JSON.stringify(remote) };
        },
        destroy: () => { destroyed++; }
      })
    } };
    assert(id.startsWith('.'), `Unexpected import ${id}`);
    return load(path.resolve(path.dirname(name), id + '.ets'));
  };
  vm.runInThisContext(`(function(require,module,exports){${code}\n})`, { filename: name })(localRequire, module, module.exports);
  return module.exports;
}
const { ModelCatalogService } = load(path.join(sourceRoot, 'services/ModelCatalogService.ets'));
const { MODEL_CATALOG_ITEMS } = load(path.join(sourceRoot, 'models/BuiltinModelDownloadTypes.ets'));
const { serializeInstalledCatalog } = load(path.join(sourceRoot, 'utils/modelCatalog.ets'));
const { catalogCompatibilityMessage, parseRemoteModelCatalog, parseInstalledCatalog } =
  load(path.join(sourceRoot, 'utils/modelCatalog.ets'));
const legacy = '/test/model-catalog-installs.json';
const current = '/test/model-catalog-installs-v2.json';
const oldCache = '/test/model-catalog-cache.json';
const newCache = '/test/model-catalog-cache-v2.json';
const snapshot = serializeInstalledCatalog([MODEL_CATALOG_ITEMS[0]]);
async function check(name, test) {
  files.clear();
  replies = []; requests = []; destroyed = 0; officialResponse = undefined; rerankerResponse = undefined;
  descriptionResponse = undefined; urlResponses = new Map();
  await test();
  console.log('PASS', name);
}
async function main() {
  await check('download and model-load entry points reject incompatible models', async () => {
    const source = fs.readFileSync(path.join(sourceRoot, 'state/ChatViewModel.ets'), 'utf8');
    const ast = ts.createSourceFile('ChatViewModel.ts', source, ts.ScriptTarget.Latest, true);
    const declaration = ast.statements.find((node) => ts.isClassDeclaration(node) && node.name.text === 'ChatViewModel');
    const names = ['setStatus', 'rejectWhileModelScanning', 'catalogCompatibilityMessage', 'rejectIncompatibleCatalogItem', 'installCatalogItem',
      'prepareAndStartBuiltinModelInstall', 'ensureCurrentModelInstalled', 'startModelLoad'];
    const methods = declaration.members.filter((node) => node.name && names.includes(node.name.getText(ast)));
    assert.equal(methods.length, names.length);
    const code = ts.transpileModule(`class Subject { ${methods.map((node) => node.getText(ast)).join('\n')} }`, {
      compilerOptions: { target: ts.ScriptTarget.ES2020 }
    }).outputText;
    const Subject = vm.runInNewContext(code + '\nSubject', { catalogCompatibilityMessage });
    const item = { ...MODEL_CATALOG_ITEMS[0], minAppVersionCode: 1100100 };
    for (const method of ['installCatalogItem', 'prepareAndStartBuiltinModelInstall', 'ensureCurrentModelInstalled', 'startModelLoad']) {
      const subject = new Subject();
      Object.assign(subject, {
        appVersionCode: 1100000, apiServerStartAfterModelLoad: true, context: {}, notify: () => {}, toastCallback: () => {},
        currentModel: () => ({ catalogItemId: item.id }),
        modelCatalogService: { findMarketItem: () => item, findInstallItem: () => item }
      });
      // Deliberately omit downloader/native services: reaching either is a failure.
      if (method === 'prepareAndStartBuiltinModelInstall') await subject[method]({}, item);
      else await subject[method](item.id);
      assert(subject.status.endsWith('需升级 App'), method);
      assert.equal(subject.apiServerStartAfterModelLoad, false);
    }
  });
  await check('version gates handle old, equal, newer and unknown app versions', async () => {
    const item = { ...MODEL_CATALOG_ITEMS[0], minAppVersionCode: 1100100 };
    assert.equal(catalogCompatibilityMessage(item, 1100000), '需升级 App');
    assert.equal(catalogCompatibilityMessage(item, 1100100), '');
    assert.equal(catalogCompatibilityMessage(item, 1110000), '');
    assert.equal(catalogCompatibilityMessage(item, 0), '无法确认 App 版本');
    delete item.minAppVersionCode;
    assert.equal(catalogCompatibilityMessage(item, 0), '');
  });
  await check('remote refresh, cache and installed snapshot preserve version gates', async () => {
    remote = JSON.parse(fs.readFileSync(path.resolve(__dirname, '../model-catalog/catalog-v2.json'), 'utf8'));
    const service = new ModelCatalogService();
    await service.load('/test');
    await service.refresh('/test');
    const item = service.findMarketItem('minicpm5-2b');
    assert.equal(item.minAppVersionCode, 1100100);
    await service.recordInstalled('/test', item);
    const reloaded = new ModelCatalogService();
    await reloaded.load('/test');
    assert.equal(reloaded.findMarketItem(item.id).minAppVersionCode, 1100100);
    assert.equal(reloaded.findInstallItem(item.id).minAppVersionCode, 1100100);
    assert.equal(catalogCompatibilityMessage(reloaded.findInstallItem(item.id), 1100000), '需升级 App');
  });
  await check('malformed minimum versions reject remote manifests and snapshots', async () => {
    const manifest = JSON.parse(fs.readFileSync(path.resolve(__dirname, '../model-catalog/catalog-v2.json'), 'utf8'));
    for (const value of [null, true, '1100100', -1, 0, 1.2, 2147483648]) {
      manifest.items[0].minAppVersionCode = value;
      assert.throws(() => parseRemoteModelCatalog(JSON.stringify(manifest)));
      assert.throws(() => parseInstalledCatalog(serializeInstalledCatalog([
        { ...MODEL_CATALOG_ITEMS[0], minAppVersionCode: value }
      ])));
    }
    delete manifest.items[0].minAppVersionCode;
    assert.doesNotThrow(() => parseRemoteModelCatalog(JSON.stringify(manifest)));
  });
  await check('migrate old snapshot without changing old files', async () => {
    files.set(legacy, snapshot);
    const service = new ModelCatalogService();
    await service.load('/test');
    assert(service.hasInstalledSnapshot(MODEL_CATALOG_ITEMS[0].id));
    assert.equal(files.get(legacy), snapshot);
    assert.equal(files.get(current), snapshot);
    await service.removeInstalled('/test', MODEL_CATALOG_ITEMS[0].id);
    assert.equal(files.get(legacy), snapshot);
    const reloaded = new ModelCatalogService();
    await reloaded.load('/test');
    assert(!reloaded.hasInstalledSnapshot(MODEL_CATALOG_ITEMS[0].id), 'Do not resurrect removed entries');
  });
  await check('migrate legacy backup after interrupted old write', async () => {
    files.set(legacy + '.bak', snapshot);
    await new ModelCatalogService().load('/test');
    assert.equal(files.get(current), snapshot);
    assert.equal(files.get(legacy + '.bak'), snapshot);
    assert(!files.has(legacy));
  });
  await check('recover current backup before considering legacy', async () => {
    files.set(legacy, snapshot);
    files.set(current + '.bak', serializeInstalledCatalog([]));
    files.set(current + '.tmp', 'partial');
    const service = new ModelCatalogService();
    await service.load('/test');
    assert(!service.hasInstalledSnapshot(MODEL_CATALOG_ITEMS[0].id));
    assert(!files.has(current + '.tmp'));
    assert(!files.has(current + '.bak'));
    assert.equal(files.get(legacy), snapshot);
  });
  await check('invalid legacy snapshot is not migrated', async () => {
    files.set(legacy, 'invalid');
    await new ModelCatalogService().load('/test');
    assert(!files.has(current));
    assert.equal(files.get(legacy), 'invalid');
  });
  await check('catalog URL and cache are isolated', async () => {
    const manifest = { schemaVersion: 1, catalogVersion: 999, publishedAt: '2026-09-18T00:00:00Z', items: [], hiddenIds: [] };
    const oldText = JSON.stringify(manifest);
    files.set(oldCache, oldText);
    const service = new ModelCatalogService();
    assert.equal((await service.load('/test')).catalogVersion, 0);
    remote = { ...manifest, catalogVersion: 2 };
    assert((await service.refresh('/test')).updated);
    assert(requests.some(request => request.url.endsWith('/model-catalog/catalog-v2.json')));
    assert.equal(files.get(oldCache), oldText);
    assert.equal(JSON.parse(files.get(newCache)).catalogVersion, 2);
    assert.equal((await new ModelCatalogService().load('/test')).catalogVersion, 2);
  });
  await check('raw timeout falls back to official API and destroys both requests', async () => {
    remote = JSON.parse(fs.readFileSync(path.resolve(__dirname, '../model-catalog/catalog-v2.json'), 'utf8'));
    replies.push(Object.assign(new Error('Operation timeout'), { code: 2300028 }));
    const service = new ModelCatalogService();
    assert((await service.refresh('/test')).updated);
    const supplemental = requests.filter(request => !request.url.includes('meta.alicdn.com') && request.url !== 'https://modelscope.cn/api/v1/models' && !request.url.includes('model_descriptions_zh.json'));
    assert.equal(supplemental.length, 2);
    assert(supplemental[0].url.startsWith('https://raw.githubusercontent.com/'));
    assert.equal(supplemental[1].url, 'https://api.github.com/repos/Torry2022/turbo-ai-chat-harmonyos/contents/model-catalog/catalog-v2.json?ref=main');
    assert.equal(supplemental[1].options.header.Accept, 'application/vnd.github.raw+json');
    assert.equal(destroyed, requests.length);
    assert.equal((await new ModelCatalogService().load('/test')).catalogVersion, remote.catalogVersion);
  });
  await check('both endpoints failing preserves valid cached catalog', async () => {
    const service = new ModelCatalogService();
    await service.refresh('/test');
    const cached = files.get(newCache);
    const items = JSON.stringify(service.items());
    replies.push({ responseCode: 503, result: '' }, Object.assign(new Error('Operation timeout'), { code: 2300028 }));
    await assert.rejects(service.refresh('/test'), /HTTP 503/);
    assert.equal(files.get(newCache), cached);
    assert.equal(JSON.stringify(service.items()), items);
    assert.equal(destroyed, requests.length);
  });
  await check('invalid catalog content is rejected without another network request or cache mutation', async () => {
    const service = new ModelCatalogService();
    await service.refresh('/test');
    const cached = files.get(newCache);
    replies.push({ responseCode: 200, result: '<html>error</html>' });
    await assert.rejects(service.refresh('/test'));
    assert.equal(requests.filter(request => !request.url.includes('meta.alicdn.com') && request.url !== 'https://modelscope.cn/api/v1/models' && !request.url.includes('model_descriptions_zh.json')).length, 2);
    assert.equal(destroyed, requests.length);
    assert.equal(files.get(newCache), cached);
  });
  await check('reopening gallery retries failed refresh, clears failure after success, and avoids concurrent refresh', async () => {
    const source = fs.readFileSync(path.join(sourceRoot, 'state/ChatViewModel.ets'), 'utf8');
    const ast = ts.createSourceFile('ChatViewModel.ts', source, ts.ScriptTarget.Latest, true);
    const declaration = ast.statements.find((node) => ts.isClassDeclaration(node) && node.name.text === 'ChatViewModel');
    const names = ['openModelMarketDialog', 'updateModelMarketCategory', 'refreshModelCatalog'];
    const methods = declaration.members.filter((node) => node.name && names.includes(node.name.getText(ast)));
    const code = ts.transpileModule(`class Subject { ${methods.map((node) => node.getText(ast)).join('\n')} }`, {
      compilerOptions: { target: ts.ScriptTarget.ES2020 }
    }).outputText;
    const { formatError } = load(path.join(sourceRoot, 'utils/formatters.ets'));
    const Subject = vm.runInNewContext(code + '\nSubject', { formatError, MODEL_CATALOG_FILTER_ALL: '全部' });
    const subject = new Subject();
    let count = 0;
    Object.assign(subject, { filesDir: '/test', modelPageCategory: 'chat', modelMarketCategory: 'chat', notify: () => {}, refreshModelMarketInstallStates: () => {},
      applyCatalogResult: () => {}, toastCallback: () => {},
      modelCatalogService: { refresh: async () => { count++; throw { code: 2300028, message: 'Operation timeout' }; } }
    });
    subject.refreshModelCatalog(false);
    await new Promise(setImmediate);
    assert.equal(subject.modelCatalogStatus, '目录更新超时，当前目录仍可使用');
    assert.equal(subject.modelCatalogRefreshFailed, true);
    subject.openModelMarketDialog();
    subject.openModelMarketDialog();
    assert.equal(count, 2);
    await new Promise(setImmediate);
    subject.modelCatalogService.refresh = async () => { count++; return {}; };
    subject.openModelMarketDialog();
    await new Promise(setImmediate);
    assert.equal(subject.modelCatalogRefreshFailed, false);
    subject.openModelMarketDialog();
    assert.equal(count, 3);
  });
  const { parseOfficialModelCatalog, parseOfficialRepoFiles, resolveOfficialCatalogItem } =
    load(path.join(sourceRoot, 'utils/officialModelCatalog.ets'));
  const officialUrl = 'https://meta.alicdn.com/data/mnn/apis/model_market.json';
  const official = (version = '21', models) => ({ version, models: models || [{ modelName: 'Example-MNN', vendor: 'Example',
    file_size: 1234, sources: { ModelScope: 'MNN/Example-MNN' }, tags: ['Think', 'Code'] }] });
  const response = value => ({ responseCode: 200, result: JSON.stringify(value) });
  const revision = '0123456789abcdef0123456789abcdef01234567';
  const blobs = ['config.json', 'llm_config.json', 'tokenizer.txt', 'llm.mnn', 'llm.mnn.weight'].map(Path =>
    ({ Type: 'blob', Path, Size: 12, Revision: revision }));
  const listing = (Files = blobs) => ({ Success: true, Data: { Files, LatestCommitter: { ShortId: revision.slice(0, 8) } } });
  const config = { llm_model: 'llm.mnn', llm_weight: 'llm.mnn.weight', temperature: 0.7, topP: 0.8, topK: 20, penalty: 1.1 };
  const llm = { jinja: { chat_template: 'a valid template' }, is_visual: false };
  const raw = JSON.stringify;
  await check('official parser deduplicates curated repositories, ignores Android versions, and filters unsupported tasks', async () => {
    const entry = official().models[0];
    const models = [entry, entry, { ...entry, min_app_version: '999.0', sources: { ModelScope: 'MNN/Other-MNN' } },
      { ...entry, sources: { ModelScope: 'MNN/../bad' } },
      ...['ImageGen', 'Audio', 'AudioGen', 'Video', 'NPU'].map(tag =>
        ({ ...entry, tags: [tag], sources: { ModelScope: `MNN/${tag}-MNN` } })),
      { ...entry, sources: { ModelScope: MODEL_CATALOG_ITEMS[0].sourceUrl.split('/models/')[1] } }];
    const items = parseOfficialModelCatalog(raw(official('21', models)), MODEL_CATALOG_ITEMS).items;
    assert.equal(items.length, 2);
    assert.equal(items[1].minAppVersionCode, undefined);
    assert.equal(items[0].files.length, 0);
    assert.equal(items[0].runtime, undefined);
    assert.deepEqual(items[0].capabilities, ['对话', '深度思考', '代码']);
    const { catalogCapabilityLabels } = load(path.join(sourceRoot, 'utils/modelCatalog.ets'));
    assert.deepEqual(catalogCapabilityLabels(['文本', '对话', '通用', '轻量', '超轻量', '低内存', '大内存', '图片', '思考']), ['对话', '图像理解', '深度思考']);
    const translated = { ...official(), tagTranslations: { Chat: '对话', Think: '深度思考', Code: '代码' } };
    assert.deepEqual(parseOfficialModelCatalog(raw(translated), []).items[0].capabilities, ['对话', '深度思考', '代码']);
    for (const value of [null, {}, { version: true, models }, official('21', [null]), official('21', [])]) {
      assert.throws(() => parseOfficialModelCatalog(raw(value), []));
    }
  });
  await check('official refresh needs no per-model HTTP calls and survives a supplemental outage and restart', async () => {
    officialResponse = response(official());
    replies.push(new Error('raw unavailable'), new Error('API unavailable'));
    const service = new ModelCatalogService();
    const result = await service.refresh('/test');
    assert.equal(result.source, 'MNN 官方目录');
    assert.equal(result.catalogVersion, 21);
    assert.equal(result.publishedAt, '');
    assert.equal(requests.filter(request => !request.url.includes('model_descriptions_zh.json')).length, 4);
    assert(!requests.some(request => request.url.includes('/repo/files')));
    const restored = new ModelCatalogService();
    assert.equal((await restored.load('/test')).catalogVersion, 21);
    assert(restored.findMarketItem('official-example-mnn'));
    assert(restored.findMarketItem(MODEL_CATALOG_ITEMS[0].id));
  });
  await check('invalid official refresh retains its cache and reports fallback rather than claiming it is current', async () => {
    officialResponse = response(official());
    remote = JSON.parse(fs.readFileSync(path.resolve(__dirname, '../model-catalog/catalog-v2.json'), 'utf8'));
    const service = new ModelCatalogService(); await service.refresh('/test');
    const cached = files.get('/test/model-catalog-official.json');
    officialResponse = response(official('22', [null]));
    const result = await service.refresh('/test');
    assert.equal(result.message, '官方目录更新失败，已保留缓存');
    assert.equal(files.get('/test/model-catalog-official.json'), cached);
    assert(service.findMarketItem('official-example-mnn'));
  });
  await check('official file resolution pins the full commit and rejects traversal, duplicates, and missing configs', async () => {
    const selected = parseOfficialRepoFiles(raw(listing([...blobs, { Type: 'blob', Path: 'README.md', Size: 5 }])), 'MNN/Example-MNN');
    assert.equal(selected.revision, revision);
    assert.equal(selected.files.length, 5);
    assert(selected.files.every(file => file.url.includes(`/resolve/${revision}/`)));
    for (const Files of [blobs.slice(1), [...blobs, blobs[0]], [...blobs, { Type: 'blob', Path: '../evil.mnn', Size: 1 }]]) {
      assert.throws(() => parseOfficialRepoFiles(raw(listing(Files)), 'MNN/Example-MNN'));
    }
    assert.throws(() => parseOfficialRepoFiles(raw({ Success: true, Data: { Files: blobs } }), 'MNN/Example-MNN'));
    const item = parseOfficialModelCatalog(raw(official()), []).items[0];
    const resolved = resolveOfficialCatalogItem(item, selected.files, raw(config), raw(llm));
    assert.equal(resolved.totalBytes, 60);
    assert.equal(resolved.runtime.generationDefaults.topP, 0.8);
    assert.equal(resolved.runtime.generationDefaults.repetitionPenalty, 1.1);
    assert.throws(() => resolveOfficialCatalogItem(item, selected.files, raw({ ...config, llm_model: 'missing.mnn' }), raw(llm)));
    assert.throws(() => resolveOfficialCatalogItem(item, selected.files, raw(config), raw({})));
  });
  await check('resolved official downloads keep their pinned manifest across refreshes and restarts', async () => {
    officialResponse = response(official());
    const service = new ModelCatalogService(); await service.refresh('/test');
    const id = 'official-example-mnn';
    await assert.rejects(service.recordInstalled('/test', service.findMarketItem(id)), /尚未解析/);
    const repoRoot = `https://modelscope.cn/models/MNN/Example-MNN/resolve/${revision}`;
    urlResponses.set('https://modelscope.cn/api/v1/models/MNN/Example-MNN/repo/files?Revision=master&Recursive=true', response(listing()));
    urlResponses.set(repoRoot + '/config.json', response(config));
    urlResponses.set(repoRoot + '/llm_config.json', response(llm));
    const resolved = await service.resolveInstallItem('/test', id);
    assert.equal(resolved.files.length, 5);
    const before = requests.length;
    const reloaded = new ModelCatalogService(); await reloaded.load('/test');
    await reloaded.resolveInstallItem('/test', id);
    assert.equal(requests.length, before, 'resume uses the saved pinned manifest');
    officialResponse = response(official('22')); await reloaded.refresh('/test');
    assert.equal(raw(reloaded.findMarketItem(id)), raw(resolved));
    await reloaded.recordInstalled('/test', resolved);
    assert(reloaded.profiles().some(profile => profile.id === id));
    assert.equal(parseInstalledCatalog(files.get(current)).find(item => item.id === id).files[0].url, resolved.files[0].url);
  });
  await check('metadata errors and cancellation cannot start downloads or leave the app busy', async () => {
    const source = fs.readFileSync(path.join(sourceRoot, 'state/ChatViewModel.ets'), 'utf8');
    const ast = ts.createSourceFile('ChatViewModel.ts', source, ts.ScriptTarget.Latest, true);
    const declaration = ast.statements.find(node => ts.isClassDeclaration(node) && node.name.text === 'ChatViewModel');
    const names = ['prepareAndStartBuiltinModelInstall', 'cancelBuiltinModelInstall'];
    const methods = declaration.members.filter(node => node.name && names.includes(node.name.getText(ast)));
    const code = ts.transpileModule(`class Subject { ${methods.map(node => node.getText(ast)).join('\n')} }`, {
      compilerOptions: { target: ts.ScriptTarget.ES2020 }
    }).outputText;
    const { formatDownloadError } = load(path.join(sourceRoot, 'utils/formatters.ets'));
    const { calculateDownloadProgress } = load(path.join(sourceRoot, 'utils/downloadProgress.ets'));
    const Subject = vm.runInNewContext(code + '\nSubject', { formatDownloadError, calculateDownloadProgress, setTimeout: () => 0 });
    const item = parseOfficialModelCatalog(raw(official()), []).items[0];
    let downloads = 0;
    const subject = new Subject();
    Object.assign(subject, { filesDir: '/test', notify: () => {}, setStatus: value => { subject.status = value; },
      rejectIncompatibleCatalogItem: () => false,
      builtinModelInstallService: { cancelInstall: () => {}, existingPartialDownloadBytes: async () => 0 },
      modelLifecycleService: { installCatalogItem: async () => { downloads++; } },
      modelCatalogService: { resolveInstallItem: async () => { throw new Error('metadata unavailable'); } }
    });
    await subject.prepareAndStartBuiltinModelInstall({}, item); await new Promise(setImmediate);
    assert.equal(downloads, 0); assert.equal(subject.busy, false); assert.equal(subject.builtinModelInstalling, false);
    assert(subject.builtinModelInstallError.includes('metadata unavailable'));
    let resolve;
    subject.modelCatalogService.resolveInstallItem = () => new Promise(done => { resolve = done; });
    await subject.prepareAndStartBuiltinModelInstall({}, item);
    subject.cancelBuiltinModelInstall();
    resolve({ ...item, files: blobs }); await new Promise(setImmediate);
    assert.equal(downloads, 0); assert.equal(subject.busy, false); assert.equal(subject.builtinModelInstalling, false);
    assert.equal(subject.builtinModelInstallCanceled, true);
  });
  await check('specialized catalogs stay out of conversation profiles and resolve rerankers without chat templates', async () => {
    const { parseOfficialRerankerCatalog } = load(path.join(sourceRoot, 'utils/officialModelCatalog.ets'));
    const { modelInstallDirectory, catalogItemToProfile } = load(path.join(sourceRoot, 'utils/modelCatalog.ets'));
    const page = { Data: { TotalCount: 3, Models: [
      { Path: 'MNN', Name: 'Qwen3-Reranker-4B-MNN', StorageSize: 200 },
      { Path: 'MNN', Name: 'Qwen3-Reranker-0.6B-MNN', StorageSize: 100 },
      { Path: 'MNN', Name: 'bge-large-MNN', StorageSize: 100 }] } };
    const items = parseOfficialRerankerCatalog(raw(page));
    assert.equal(items.length, 2);
    assert(items[0].displayName.includes('0.6B'));
    assert.equal(items[0].modelType, 'rerank');
    assert.equal(catalogItemToProfile(items[0]), undefined);
    assert.equal(modelInstallDirectory('/test', items[0]), '/test/rerank-models/Qwen3-Reranker-0.6B-MNN');
    const resolved = resolveOfficialCatalogItem(items[0], parseOfficialRepoFiles(raw(listing()), 'MNN/Example-MNN').files, raw(config), '{}');
    assert.equal(resolved.modelType, 'rerank');
    assert.equal(resolved.runtime, undefined);
    assert.equal(resolved.capabilities.length, 0);
    rerankerResponse = response(page); officialResponse = response(official());
    const service = new ModelCatalogService(); await service.refresh('/test');
    const laya = service.findMarketItem('laya-multilingual-mnn-fp16');
    assert.equal(laya.modelType, 'decision');
    assert.equal(modelInstallDirectory('/test', laya), '/test/laya-probe');
    assert.equal(catalogItemToProfile(laya), undefined);
    assert(service.items().some(item => item.modelType === 'rerank'));
    const reloaded = new ModelCatalogService(); await reloaded.load('/test');
    assert(reloaded.items().some(item => item.modelType === 'rerank'));
    assert.throws(() => parseOfficialRerankerCatalog(raw({ Data: { TotalCount: 10, Models: [] } })), /不完整/);
  });
  await check('gallery categories follow the model page and keep tag filters scoped to their category', async () => {
    const source = fs.readFileSync(path.join(sourceRoot, 'state/ChatViewModel.ets'), 'utf8');
    const ast = ts.createSourceFile('ChatViewModel.ts', source, ts.ScriptTarget.Latest, true);
    const declaration = ast.statements.find(node => ts.isClassDeclaration(node) && node.name.text === 'ChatViewModel');
    const names = ['modelCatalogItems', 'modelCategoryItems', 'catalogCapabilities', 'modelCatalogFilterTags',
      'openModelMarketDialog', 'updateModelMarketCategory'];
    const methods = declaration.members.filter(node => node.name && names.includes(node.name.getText(ast)));
    const code = ts.transpileModule(`class Subject { ${methods.map(node => node.getText(ast)).join('\n')} }`, {
      compilerOptions: { target: ts.ScriptTarget.ES2020 }
    }).outputText;
    const { catalogCapabilityLabels } = load(path.join(sourceRoot, 'utils/modelCatalog.ets'));
    const Subject = vm.runInNewContext(code + '\nSubject', { MODEL_CATALOG_FILTER_ALL: '全部', catalogCapabilityLabels });
    const subject = new Subject();
    const item = parseOfficialModelCatalog(raw(official()), []).items[0];
    Object.assign(subject, { modelPageCategory: 'rerank', modelMarketCategory: 'chat', modelMarketSearchText: 'old',
      modelMarketCapabilityFilter: '代码', notify: () => {}, refreshModelMarketInstallStates: () => {},
      modelCatalogService: { items: () => [item, { ...item, id: 'rank', modelType: 'rerank', capabilities: [] }] }
    });
    subject.openModelMarketDialog();
    assert.equal(subject.modelMarketCategory, 'rerank');
    assert.equal(subject.modelMarketSearchText, '');
    assert.deepEqual(Array.from(subject.modelCatalogFilterTags()), ['全部']);
    assert.equal(subject.modelCatalogItems()[0].id, 'rank');
    subject.updateModelMarketCategory('chat');
    assert(subject.modelCatalogFilterTags().includes('深度思考'));
    assert.equal(subject.modelCatalogItems()[0].id, item.id);
    assert.equal(subject.modelPageCategory, 'rerank', 'gallery selection must not change model-page selection');
  });
  const descriptionCache = '/test/model-descriptions-zh-v1.json';
  const describedItem = MODEL_CATALOG_ITEMS[0];
  const describedRepo = describedItem.sourceUrl.split('/models/')[1];
  const descriptions = (version, text = '经核实的模型用途描述', entries) => JSON.stringify({
    schemaVersion: 1, descriptionVersion: version, publishedAt: '2026-11-03T06:00:00Z',
    entries: entries ?? [{repo: describedRepo, description: text, sources: ['https://example.com/model-card']}]
  });
  await check('bundled descriptions are immediate and only exact repositories receive them', async () => {
    const service = new ModelCatalogService(); await service.load('/test', descriptions(1));
    const described = service.findMarketItem(describedItem.id);
    assert.equal(described.description, '经核实的模型用途描述');
    assert.equal(MODEL_CATALOG_ITEMS[0].description, describedItem.description, 'do not mutate the bundled model item');
    const untouched = MODEL_CATALOG_ITEMS.find(item => item.sourceUrl !== describedItem.sourceUrl);
    assert.equal(service.findMarketItem(untouched.id).description, untouched.description);
    assert.deepEqual(described.files, describedItem.files);
    assert.deepEqual(described.runtime, describedItem.runtime);
    assert(!files.has(descriptionCache), 'bundled descriptions do not masquerade as downloaded cache');
  });
  await check('new official variants without an exact description keep the catalog fallback', async () => {
    remote = JSON.parse(fs.readFileSync(path.resolve(__dirname, '../model-catalog/catalog-v2.json'), 'utf8'));
    officialResponse = response(official('22', [{...official().models[0],
      sources: {ModelScope: describedRepo + '-New'}, tags: ['Vision']} ]));
    const service = new ModelCatalogService(); await service.load('/test', descriptions(1)); await service.refresh('/test');
    const fresh = service.items().find(item => item.sourceUrl.endsWith(describedRepo + '-New'));
    assert(fresh); assert.equal(fresh.description, '支持文本与图片输入的多模态对话模型。');
  });
  await check('description cache recovery failures cannot prevent the normal catalog from loading', async () => {
    files.set(descriptionCache + '.bak', descriptions(2));
    const rename = mockFs.rename;
    mockFs.rename = async (from, to) => {
      if (to === descriptionCache) throw Error('cache permission error');
      return rename(from, to);
    };
    try {
      const service = new ModelCatalogService(); await service.load('/test', descriptions(1, '包内可用描述'));
      assert.equal(service.findMarketItem(describedItem.id).description, '包内可用描述');
      assert(service.items().length > 0);
    } finally { mockFs.rename = rename; }
  });
  await check('newer cached descriptions override the bundle, older or malformed caches do not', async () => {
    files.set(descriptionCache, descriptions(2, '较新的描述'));
    const cached = new ModelCatalogService(); await cached.load('/test', descriptions(1));
    assert.equal(cached.findMarketItem(describedItem.id).description, '较新的描述');
    files.set(descriptionCache, descriptions(1, '过期缓存'));
    const bundled = new ModelCatalogService(); await bundled.load('/test', descriptions(2, '包内较新描述'));
    assert.equal(bundled.findMarketItem(describedItem.id).description, '包内较新描述');
    files.set(descriptionCache, '{broken');
    const recovered = new ModelCatalogService(); await recovered.load('/test', descriptions(2, '包内较新描述'));
    assert.equal(recovered.findMarketItem(describedItem.id).description, '包内较新描述');
    const defaults = new ModelCatalogService(); await defaults.load('/test', '{broken');
    assert.equal(defaults.findMarketItem(describedItem.id).description, describedItem.description);
  });
  await check('description-only update persists without changing installation snapshots or runtime settings', async () => {
    remote = JSON.parse(fs.readFileSync(path.resolve(__dirname, '../model-catalog/catalog-v2.json'), 'utf8'));
    const service = new ModelCatalogService(); await service.load('/test', descriptions(1));
    await service.refresh('/test');
    await service.recordInstalled('/test', service.findMarketItem(describedItem.id));
    const saved = files.get(current), catalog = files.get(newCache);
    descriptionResponse = {responseCode: 200, result: descriptions(2, '在线修订后的描述')};
    assert((await service.refresh('/test')).updated);
    assert.equal(service.findMarketItem(describedItem.id).description, '在线修订后的描述');
    assert.equal(files.get(current), saved); assert.equal(files.get(newCache), catalog);
    const restart = new ModelCatalogService(); await restart.load('/test', descriptions(1));
    assert.equal(restart.findMarketItem(describedItem.id).description, '在线修订后的描述');
    descriptionResponse = {responseCode: 200, result: descriptions(1, '远程旧版本')};
    await restart.refresh('/test');
    assert.equal(restart.findMarketItem(describedItem.id).description, '在线修订后的描述');
    descriptionResponse = new Error('offline'); await restart.refresh('/test');
    assert.equal(restart.findMarketItem(describedItem.id).description, '在线修订后的描述');
    descriptionResponse = {responseCode: 200, result: '{broken'}; await restart.refresh('/test');
    assert.equal(JSON.parse(files.get(descriptionCache)).descriptionVersion, 2);
    descriptionResponse = {responseCode: 200, result: descriptions(3, '', [])}; await restart.refresh('/test');
    assert.equal(restart.findMarketItem(describedItem.id).description, describedItem.description,
      'a newer complete manifest can remove an override and restore the normal fallback');
  });
  await check('description Raw failures use the Contents API and retain atomic cache recovery', async () => {
    remote = JSON.parse(fs.readFileSync(path.resolve(__dirname, '../model-catalog/catalog-v2.json'), 'utf8'));
    const raw = 'https://raw.githubusercontent.com/Torry2022/turbo-ai-chat-harmonyos/main/entry/src/main/resources/rawfile/model_descriptions_zh.json';
    const api = 'https://api.github.com/repos/Torry2022/turbo-ai-chat-harmonyos/contents/entry/src/main/resources/rawfile/model_descriptions_zh.json?ref=main';
    urlResponses.set(raw, new Error('timeout'));
    urlResponses.set(api, {responseCode: 200, result: descriptions(2, '备用接口的描述')});
    const service = new ModelCatalogService(); await service.load('/test', descriptions(1)); await service.refresh('/test');
    assert.equal(service.findMarketItem(describedItem.id).description, '备用接口的描述');
    assert(requests.some(request => request.url === api && request.options.header.Accept === 'application/vnd.github.raw+json'));
    files.set(descriptionCache + '.bak', files.get(descriptionCache)); files.delete(descriptionCache);
    files.set(descriptionCache + '.tmp', 'interrupted');
    const recovered = new ModelCatalogService(); await recovered.load('/test', descriptions(1));
    assert.equal(recovered.findMarketItem(describedItem.id).description, '备用接口的描述');
    assert(!files.has(descriptionCache + '.tmp')); assert(!files.has(descriptionCache + '.bak'));
    assert.equal(destroyed, requests.length);
  });
  await check('new installations never write the legacy snapshot', async () => {
    const service = new ModelCatalogService();
    await service.load('/test');
    await service.recordInstalled('/test', MODEL_CATALOG_ITEMS[0]);
    assert(files.has(current));
    assert(!files.has(legacy));
  });
  await check('current manifest loads MiniCPM5-2B without adding it to legacy', async () => {
    remote = JSON.parse(fs.readFileSync(path.resolve(__dirname, '../model-catalog/catalog-v2.json'), 'utf8'));
    const legacyManifest = JSON.parse(fs.readFileSync(path.resolve(__dirname, '../model-catalog/catalog.json'), 'utf8'));
    assert(!legacyManifest.items.some((item) => item.id === 'minicpm5-2b'));
    const service = new ModelCatalogService();
    await service.load('/test');
    await service.refresh('/test');
    const profile = service.profiles().find((item) => item.id === 'minicpm5-2b');
    assert(profile);
    assert.equal(profile.generationDefaults.repetitionPenalty, 1);
    assert.equal(profile.generationDefaults.temperature, 1);
    assert.equal(profile.generationDefaults.topP, 0.95);
    assert.equal(profile.contextMessageLimit, 6);
    for (const item of legacyManifest.items) {
      assert(service.findMarketItem(item.id), `Existing model disappeared: ${item.id}`);
    }
  });
}
main().catch((error) => { console.error(error); process.exitCode = 1; });
