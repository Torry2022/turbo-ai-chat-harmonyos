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
    if (id === '@ohos.file.fs') return { default: mockFs };
    if (id === '@ohos.net.http') return { default: {
      RequestMethod: { GET: 'GET' }, HttpDataType: { STRING: 'string' },
      createHttp: () => ({
        request: async (url) => { requestedUrl = url; return { responseCode: 200, result: JSON.stringify(remote) }; },
        destroy: () => {}
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
  await test();
  console.log('PASS', name);
}
async function main() {
  await check('download and model-load entry points reject incompatible models', async () => {
    const source = fs.readFileSync(path.join(sourceRoot, 'state/ChatViewModel.ets'), 'utf8');
    const ast = ts.createSourceFile('ChatViewModel.ts', source, ts.ScriptTarget.Latest, true);
    const declaration = ast.statements.find((node) => ts.isClassDeclaration(node) && node.name.text === 'ChatViewModel');
    const names = ['catalogCompatibilityMessage', 'rejectIncompatibleCatalogItem', 'installCatalogItem',
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
        appVersionCode: 1100000, context: {}, notify: () => {}, toastCallback: () => {},
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
    assert(requestedUrl.endsWith('/model-catalog/catalog-v2.json'));
    assert.equal(files.get(oldCache), oldText);
    assert.equal(JSON.parse(files.get(newCache)).catalogVersion, 2);
    assert.equal((await new ModelCatalogService().load('/test')).catalogVersion, 2);
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
