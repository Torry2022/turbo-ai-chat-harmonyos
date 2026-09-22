// node scripts/test_model_import.cjs <path/to/typescript.js>
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(process.argv[2] || 'typescript');
const namingContext = { exports: {} };
vm.runInNewContext(ts.transpileModule(
  fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/utils/modelNaming.ets'), 'utf8'),
  { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 } }
).outputText, namingContext);
const source = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/services/ModelImportService.ets'), 'utf8');
const ast = ts.createSourceFile('ModelImportService.ts', source, ts.ScriptTarget.Latest, true);
const declaration = ast.statements.find(n => ts.isClassDeclaration(n));
const code = ts.transpileModule(declaration.getText(ast).replace('export class', 'class'), {
  compilerOptions: { target: ts.ScriptTarget.ES2020 }
}).outputText;

async function check(name, run) {
  let available = 1e12;
  let unzipError = false;
  let link = false;
  const copied = [];
  let pickerResult = ['/selected'];
  let pickerError;
  let pickerOptions;
  const deleted = [];
  let saved;
  const mockFs = {
    OpenMode: { READ_ONLY: 0 },
    open: async name => ({ fd: name }), close: async () => {},
    stat: async () => ({ size: 100 }),
    copyFile: async (from, to) => copied.push([from, to]),
    unlink: async name => deleted.push(name),
    listFile: async () => ['weights.bin'],
    lstat: async () => ({ isDirectory: () => false, isFile: () => !link })
  };
  const Service = vm.runInNewContext(code + '\nModelImportService', {
    fs: mockFs,
    canIUse: () => false,
    picker: {
      DocumentSelectMode: { FOLDER: 1 },
      DocumentSelectOptions: class {},
      DocumentViewPicker: class {
        async select(options) {
          pickerOptions = options;
          if (pickerError) throw pickerError;
          return pickerResult;
        }
      }
    },
    fileUri: { FileUri: class { constructor(uri) { this.path = uri; } } },
    statvfs: { getFreeSize: async () => available },
    zlib: { decompressFile: async () => { if (unzipError) throw new Error('bad archive'); } },
    ModelDirectoryPreflightService: class { async requireCompatible() {} },
    formatError: err => err.message,
    ...namingContext.exports,
    IMPORTED_MODELS_DIR: 'model-imports', IMPORTED_MODEL_SOURCE: 'imported',
    DEFAULT_IMPORTED_MODEL_PROMPT: '', CHAT_FORMAT_MNN_AUTO: 'mnn'
  });
  const service = new Service();
  Object.assign(service, {
    pickSource: async () => '/selected', ensureDir: async () => {},
    exists: async () => true,
    findConfigPath: async root => root + '/config.json',
    detectSupportsImage: async () => false,
    inferName: () => 'Test-2B',
    loadImportedProfiles: async () => [],
    saveImportedProfiles: async (_, profiles) => { saved = profiles; },
    deletePathRecursive: async name => deleted.push(name),
    copyPickedFile: async (from, to) => copied.push([from, to])
  });
  await run({ service, fs: mockFs, copied, deleted, saved: () => saved,
    useRealPicker: () => { delete service.pickSource; },
    pickerOptions: () => pickerOptions,
    cancelPicker: () => { pickerResult = []; },
    failPicker: () => { pickerError = new Error('unsupported'); },
    lowSpace: () => { available = 10; },
    corruptZip: () => { unzipError = true; },
    symlink: () => { link = true; } });
  console.log('PASS', name);
}

(async () => {
  await check('folder picker works even when capability reporting is false', async t => {
    t.useRealPicker();
    assert.equal(await t.service.pickSource({}, true), '/selected');
    assert.equal(t.pickerOptions().selectMode, 1);
    assert.equal(t.pickerOptions().maxSelectNumber, 1);
    t.cancelPicker();
    assert.equal(await t.service.pickSource({}, true), undefined);
    t.failPicker();
    await assert.rejects(t.service.pickSource({}, true), /无法打开文件夹选择器.*压缩包导入/);
  });
  await check('ZIP picker retains its filter and original errors', async t => {
    t.useRealPicker();
    await t.service.pickSource({}, false);
    assert.equal(t.pickerOptions().fileSuffixFilters[0], 'MNN 模型包|.zip');
    assert.equal(t.pickerOptions().selectMode, undefined);
    t.failPicker();
    await assert.rejects(t.service.pickSource({}, false), /unsupported/);
  });
  for (const folder of [false, true]) {
    await check('duplicate ' + (folder ? 'folder' : 'ZIP') + ' preserves model family', async t => {
      const name = 'ImportRegression-Qwen3-0.6B-20260921';
      const profiles = [1, 2].map(n => ({
        id: 'existing-' + n,
        name: name + (n === 1 ? '' : ' ' + n),
        shortName: 'ImportRegression-Qwen3-0.6B' + (n === 1 ? '' : ' ' + n)
      }));
      t.service.inferName = () => name;
      t.service.loadImportedProfiles = async () => profiles;
      const result = await t.service.pickAndImport({ filesDir: '/app' }, profiles, folder);
      assert.equal(result.profile.name, name + ' 3');
      assert.equal(result.profile.shortName, 'ImportRegression-Qwen3-0.6B 3');
      assert.equal(t.saved()[0].shortName, profiles[0].shortName);
    });
  }
  await check('scanned duplicate preserves model family', async t => {
    const name = 'ImportRegression-Qwen3-0.6B-20260921';
    const profiles = [{ id: 'existing', name, shortName: 'ImportRegression-Qwen3-0.6B' }];
    t.service.inferNameFromDirectory = () => name;
    t.service.preflightService.validate = async () => ({ compatible: true });
    t.fs.stat = async () => ({ isDirectory: () => true });
    const result = await t.service.scanPushedModelDirectories('/app', profiles);
    assert.equal(result.addedProfiles[0].name, name + ' 2');
    assert.equal(result.addedProfiles[0].shortName, 'ImportRegression-Qwen3-0.6B 2');
  });
  await check('cancel leaves files and manifest untouched', async t => {
    t.service.pickSource = async () => undefined;
    assert.equal(await t.service.pickAndImport({ filesDir: '/app' }, [], true), undefined);
    assert.equal(t.copied.length, 0);
    assert.equal(t.deleted.length, 0);
    assert.equal(t.saved(), undefined);
  });
  await check('folder copies nested paths and registers only after validation', async t => {
    t.service.listImportFiles = async () => ['/selected/config.json', '/selected/sub/weights.bin'];
    const result = await t.service.pickAndImport({ filesDir: '/app' }, [], true);
    assert.equal(t.copied.length, 2);
    assert(t.copied[1][1].endsWith('/sub/weights.bin'));
    assert.equal(t.saved()[0], result.profile);
    assert(t.deleted.every(p => p.startsWith('/app/')));
  });
  await check('low space rejects before copying and does not save manifest', async t => {
    t.lowSpace();
    await assert.rejects(t.service.pickAndImport({ filesDir: '/app' }, [], true), /读取文件夹失败.*空间不足/);
    assert.equal(t.copied.length, 0);
    assert.equal(t.saved(), undefined);
  });
  await check('symlinks are rejected before copying', async t => {
    t.symlink();
    await assert.rejects(t.service.pickAndImport({ filesDir: '/app' }, [], true), /符号链接/);
    assert.equal(t.copied.length, 0);
  });
  await check('ZIP errors identify extraction and clean staging files', async t => {
    t.corruptZip();
    await assert.rejects(t.service.pickAndImport({ filesDir: '/app' }, []), /解压模型包失败.*bad archive/);
    assert(t.deleted.some(p => p.endsWith('.zip')));
    assert.equal(t.saved(), undefined);
  });
  await check('validation failure never registers an imported model', async t => {
    t.service.findConfigPath = async () => '';
    await assert.rejects(t.service.pickAndImport({ filesDir: '/app' }, [], true), /校验模型目录失败/);
    assert.equal(t.saved(), undefined);
  });
})().catch(err => { console.error(err); process.exitCode = 1; });
