// node scripts/test_model_download.cjs <path/to/typescript.js>
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(process.argv[2] || 'typescript');
const root = path.resolve(__dirname, '../entry/src/main/ets');
const temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'turbo-download-'));
let reply;
let shortWrites = false;
let zeroWrite = false;
let failAppend = false;
let failCheckpoint = false;
const requests = [];
const { createHash } = require('node:crypto');
const fileIo = {
  OpenMode: { READ_ONLY: 1, WRITE_ONLY: 2, CREATE: 4, TRUNC: 8, APPEND: 16 },
  access: async name => fs.existsSync(name),
  readText: async name => fs.readFileSync(name, 'utf8'),
  stat: async name => fs.statSync(name),
  openSync: (name, flags) => ({ fd: fs.openSync(name, flags === 1 ? 'r' : flags & 16 ? 'a' : 'w') }),
  closeSync: file => fs.closeSync(file.fd),
  fsyncSync: fd => fs.fsyncSync(fd),
  truncateSync: (name, size) => fs.truncateSync(name, size),
  readSync: (fd, bytes) => fs.readSync(fd, new Uint8Array(bytes), 0, bytes.byteLength, null),
  writeSync: (fd, bytes) => {
    if (zeroWrite) return 0;
    if (failAppend && fs.fstatSync(fd).size >= 4) {
      failAppend = false;
      fs.writeSync(fd, Buffer.from(bytes).subarray(0, 1));
      throw new Error('injected interrupted append');
    }
    const buffer = Buffer.from(bytes);
    return fs.writeSync(fd, shortWrites ? buffer.subarray(0, 1) : buffer);
  },
  rename: async (from, to) => {
    if (failCheckpoint && to.endsWith('.meta')) { failCheckpoint = false; throw new Error('injected checkpoint failure'); }
    fs.renameSync(from, to);
  },
  unlink: async name => fs.unlinkSync(name)
};
const http = {
  RequestMethod: { GET: 'GET' },
  createHttp: () => {
    const handlers = {};
    return {
      on: (name, callback) => { handlers[name] = callback; },
      off: name => { delete handlers[name]; },
      destroy: () => {},
      requestInStream: async (url, options) => {
        requests.push({ url, options });
        const response = typeof reply === 'function' ? reply(options) : reply;
        handlers.headersReceive(response.headers || {});
        for (const chunk of response.chunks || [response.body || '']) {
          handlers.dataReceive(Uint8Array.from(Buffer.from(chunk)).buffer);
          if (response.cancel) response.cancel();
        }
        if (response.error) throw new Error(response.error);
        return response.code;
      }
    };
  }
};
const modules = new Map();
const sdkStub = new Proxy(function () {}, { get: (_, key) => key === 'then' ? undefined : sdkStub, construct: () => sdkStub });
function load(filename) {
  if (modules.has(filename)) return modules.get(filename).exports;
  const module = { exports: {} }; modules.set(filename, module);
  const code = ts.transpileModule(fs.readFileSync(filename, 'utf8'), { compilerOptions: {
    module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020, esModuleInterop: true
  }}).outputText;
  const requireSource = name => {
    if (name === '@ohos.file.fs') return fileIo;
    if (name === '@ohos.net.http') return http;
    if (name === '@ohos.security.cryptoFramework') return { createMd: () => {
      const hash = createHash('sha256');
      return { update: async blob => { hash.update(blob.data); }, digest: async () => ({data: hash.digest()}) };
    } };
    if (name === '@ohos.util') return { TextEncoder: class { encodeInto(text) { return new TextEncoder().encode(text); } } };
    if (name.startsWith('.')) return load(path.resolve(path.dirname(filename), name + '.ets'));
    return sdkStub;
  };
  vm.runInNewContext(code, { module, exports: module.exports, require: requireSource, console, ArrayBuffer,
    setTimeout, clearTimeout }, { filename });
  return module.exports;
}
const { BuiltinModelInstallService } = load(path.join(root, 'services/BuiltinModelInstallService.ets'));
const pinned = 'https://example.invalid/resolve/' + 'a'.repeat(40) + '/weight.bin';
const spec = { displayName: 'Synthetic', totalBytes: 8 };
let cases = 0;
async function check(name, run) {
  const target = path.join(temporary, String(cases++) + '.part');
  const installer = new BuiltinModelInstallService({});
  const file = { relativePath: 'weight.bin', sizeBytes: 8, url: pinned };
  shortWrites = false; zeroWrite = false; failAppend = false; failCheckpoint = false;
  requests.length = 0;
  await run({ target, installer, file, download: () => installer.downloadFile(spec, file, target, 0, () => {}) });
  console.log('PASS', name);
}
function checkpoint(target, file, bytes = 4, validator = '"v1"') {
  fs.writeFileSync(target, 'ABCDEFGH'.slice(0, bytes));
  fs.writeFileSync(target + '.meta', JSON.stringify({ url: file.url, size: file.sizeBytes, bytes, validator, sha256: file.sha256 }));
}
(async () => {
  await check('installed decision package accepts a pinned config with equivalent Windows line endings', async ({ installer }) => {
    const filesDir = path.join(temporary, 'decision-models-test');
    const modelDir = path.join(filesDir, 'decision-models', 'H2O-fixture');
    fs.mkdirSync(modelDir, { recursive: true });
    const config = '{\n  "memory": "low"\n}\n';
    const item = { modelType: 'decision', directoryName: 'H2O-fixture',
      files: [{ relativePath: 'config.json', sizeBytes: Buffer.byteLength(config),
        sha256: createHash('sha256').update(config).digest('hex') }] };
    const installedConfig = path.join(modelDir, 'config.json');
    fs.writeFileSync(installedConfig, config.replace(/\n/g, '\r\n'));
    assert.equal(await installer.isCatalogItemInstalled(filesDir, item), true);
    fs.writeFileSync(installedConfig, config.replace('low', 'new').replace(/\n/g, '\r\n'));
    assert.equal(await installer.isCatalogItemInstalled(filesDir, item), false);
  });
  await check('trusted SHA-256 is verified after download', async ({ target, file, download }) => {
    file.sha256 = createHash('sha256').update('ABCDEFGH').digest('hex');
    reply = { code: 200, body: 'ABCDEFGH' };
    await download(); assert.equal(fs.readFileSync(target, 'utf8'), 'ABCDEFGH');
  });
  await check('same-length corrupted body fails trusted SHA-256', async ({ target, file, download }) => {
    file.sha256 = createHash('sha256').update('ABCDEFGH').digest('hex');
    reply = { code: 200, body: 'ABCDABCD' };
    await assert.rejects(download, /SHA-256/);
    assert.equal(fs.statSync(target).size, 0);
    assert.equal(fs.existsSync(target + '.meta'), false);
    reply = { code: 200, body: 'ABCDEFGH' }; await download();
    assert.equal(fs.readFileSync(target, 'utf8'), 'ABCDEFGH');
  });
  await check('valid 206 uses exact range and resumes verified bytes', async ({ target, file, download }) => {
    checkpoint(target, file);
    reply = { code: 206, headers: { 'Content-Range': 'bytes 4-7/8', ETag: '"v1"' }, body: 'EFGH' };
    await download();
    assert.equal(fs.readFileSync(target, 'utf8'), 'ABCDEFGH');
    assert.equal(requests[0].options.header.Range, 'bytes=4-7');
    assert.equal(requests[0].options.header['If-Range'], '"v1"');
  });
  for (const range of ['bytes 0-3/8', 'bytes 4-7/9', 'bytes 4-6/8', '']) {
    await check('rejects wrong or absent Content-Range ' + range, async ({ target, file, download }) => {
      checkpoint(target, file);
      reply = { code: 206, headers: { 'content-range': range, etag: '"v1"' }, body: 'ABCD' };
      await assert.rejects(download, /范围或长度/);
      assert.equal(fs.readFileSync(target, 'utf8'), 'ABCD');
      assert.equal(fs.existsSync(target + '.range'), false);
    });
  }
  await check('valid shorter server ranges advance by received bytes', async ({ target, file, download }) => {
    checkpoint(target, file);
    reply = options => options.header.Range === 'bytes=4-7'
      ? { code: 206, headers: { 'content-range': 'bytes 4-5/8', etag: '"v1"' }, body: 'EF' }
      : { code: 206, headers: { 'content-range': 'bytes 6-7/8', etag: '"v1"' }, body: 'GH' };
    await download(); assert.equal(fs.readFileSync(target, 'utf8'), 'ABCDEFGH');
  });
  await check('full 200 replaces an existing partial', async ({ target, file, download }) => {
    checkpoint(target, file);
    reply = { code: 200, headers: { etag: '"v2"' }, body: '12345678' };
    await download(); assert.equal(fs.readFileSync(target, 'utf8'), '12345678');
  });
  await check('interrupted 200 never merges unconfirmed bytes after restart', async ({ target, file, download }) => {
    checkpoint(target, file);
    reply = { code: 200, body: 'ABCD', error: 'interrupted' };
    await assert.rejects(download, /interrupted/);
    assert.equal(fs.readFileSync(target, 'utf8'), 'ABCD');
    fs.writeFileSync(target + '.range', 'ABCD'); // Legacy orphan from an older build.
    reply = { code: 206, headers: { 'content-range': 'bytes 4-7/8', etag: '"v1"' }, body: 'EFGH' };
    await download(); assert.equal(fs.readFileSync(target, 'utf8'), 'ABCDEFGH');
  });
  await check('legacy partial without checkpoint restarts safely', async ({ target, download }) => {
    fs.writeFileSync(target, 'WRONGOLD');
    reply = { code: 206, headers: { 'content-range': 'bytes 0-7/8' }, body: 'ABCDEFGH' };
    await download(); assert.equal(fs.readFileSync(target, 'utf8'), 'ABCDEFGH');
  });
  await check('changed URL or total size invalidates checkpoint', async ({ target, file, download }) => {
    checkpoint(target, { ...file, url: pinned + '?old' });
    reply = { code: 200, body: 'ABCDEFGH' };
    await download(); assert.equal(requests[0].options.header.Range, 'bytes=0-7');
  });
  await check('validator mismatch preserves old checkpoint', async ({ target, file, download }) => {
    checkpoint(target, file);
    reply = { code: 206, headers: { 'content-range': 'bytes 4-7/8', etag: '"v2"' }, body: 'EFGH' };
    await assert.rejects(download, /远端文件已变化/);
    assert.equal(fs.readFileSync(target, 'utf8'), 'ABCD');
  });
  await check('short writes are completed', async ({ target, download }) => {
    shortWrites = true;
    reply = { code: 200, body: 'ABCDEFGH' };
    await download(); assert.equal(fs.readFileSync(target, 'utf8'), 'ABCDEFGH');
  });
  await check('zero write cannot publish a complete file', async ({ target, download }) => {
    zeroWrite = true; reply = { code: 200, body: 'ABCDEFGH' };
    await assert.rejects(download, /写入失败/);
    assert.equal(fs.existsSync(target), false);
  });
  for (const code of [416, 404, 500]) {
    await check('HTTP ' + code + ' leaves verified data unchanged', async ({ target, file, download }) => {
      checkpoint(target, file); reply = { code, body: 'no' };
      await assert.rejects(download, /下载响应无效/);
      assert.equal(fs.readFileSync(target, 'utf8'), 'ABCD');
    });
  }
  await check('cancel keeps verified data and permits retry', async ({ target, file, installer, download }) => {
    checkpoint(target, file);
    reply = { code: 206, headers: { 'content-range': 'bytes 4-7/8' }, body: 'EFGH', cancel: () => installer.cancelInstall() };
    await assert.rejects(download, /取消/);
    assert.equal(fs.readFileSync(target, 'utf8'), 'ABCD');
  });
  await check('failed append is rolled back to its last checkpoint', async ({ target, file, download }) => {
    checkpoint(target, file); failAppend = true;
    reply = { code: 206, headers: { 'content-range': 'bytes 4-7/8', etag: '"v1"' }, body: 'EFGH' };
    await assert.rejects(download, /interrupted append/);
    assert.equal(fs.statSync(target).size, 5);
    await download(); assert.equal(fs.readFileSync(target, 'utf8'), 'ABCDEFGH');
  });
  await check('multi-block download resumes only its completed block', async ({ target, file, download }) => {
    const block = 16 * 1024 * 1024;
    file.sizeBytes = block + 4;
    let interrupted = true;
    reply = options => {
      if (options.header.Range === `bytes=0-${block - 1}`) {
        return { code: 206, headers: { 'content-range': `bytes 0-${block - 1}/${file.sizeBytes}` }, body: 'A'.repeat(block) };
      }
      assert.equal(options.header.Range, `bytes=${block}-${block + 3}`);
      if (interrupted) { interrupted = false; return { code: 206, body: 'EF', error: 'network interrupted' }; }
      return { code: 206, headers: { 'content-range': `bytes ${block}-${block + 3}/${file.sizeBytes}` }, body: 'EFGH' };
    };
    await assert.rejects(download, /network interrupted/);
    assert.equal(JSON.parse(fs.readFileSync(target + '.meta', 'utf8')).bytes, block);
    await download();
    assert.equal(requests.length, 3);
    assert.equal(fs.statSync(target).size, file.sizeBytes);
    assert.equal(fs.readFileSync(target).subarray(block).toString(), 'EFGH');
  });
  await check('checkpoint failure rolls appended bytes back before retry', async ({ target, file, download }) => {
    checkpoint(target, file); failCheckpoint = true;
    reply = { code: 206, headers: { 'content-range': 'bytes 4-7/8', etag: '"v1"' }, body: 'EFGH' };
    await assert.rejects(download, /checkpoint failure/);
    await download(); assert.equal(fs.readFileSync(target, 'utf8'), 'ABCDEFGH');
  });
})().catch(error => { console.error(error); process.exitCode = 1; }).finally(() => {
  fs.rmSync(temporary, { recursive: true, force: true });
});
