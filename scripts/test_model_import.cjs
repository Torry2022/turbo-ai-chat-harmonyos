// node scripts/test_model_import.cjs <path/to/typescript.js>
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(process.argv[2] || 'typescript');
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
    fileUri: { FileUri: class { constructor(uri) { this.path = uri; } } },
    statvfs: { getFreeSize: async () => available },
    zlib: { decompressFile: async () => { if (unzipError) throw new Error('bad archive'); } },
    ModelDirectoryPreflightService: class { async requireCompatible() {} },
    formatError: err => err.message,
    uniqueModelName: name => name, uniqueModelShortName: name => name,
    importedModelShortName: name => name,
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
  await run({ service, copied, deleted, saved: () => saved,
    lowSpace: () => { available = 10; },
    corruptZip: () => { unzipError = true; },
    symlink: () => { link = true; } });
  console.log('PASS', name);
}

(async () => {
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
