const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const ts = require(process.argv[2]);
let replies = [], dns = [], calls = [], closed = 0, cancelled = 0;
const rcp = {
  Request: class { constructor(url) { this.url = url; } },
  createSession(options) {
    const reply = replies.shift();
    const session = { cancel() { cancelled++; }, close() { closed++; }, async fetch(request) {
      calls.push({ request, options });
      for (const chunk of reply.chunks || []) options.requestConfiguration.tracing.httpEventsHandler.onDataReceive(chunk);
      return { statusCode: reply.status || 200, headers: reply.headers || { 'content-type': 'image/png' } };
    }};
    return session;
  }
};
const exportsObject = {};
const modules = {
  '@kit.RemoteCommunicationKit': { rcp },
  '@ohos.net.connection': { getAddressesByName: async host => { dns.push(host); return [{ address: host === 'private.test' ? '127.0.0.1' : '93.184.216.34' }]; } },
  '@ohos.url': { URL },
  '@ohos.util': { Base64Helper: class { encodeToStringSync(bytes) { return Buffer.from(bytes).toString('base64'); } } }
};
const code = ts.transpileModule(fs.readFileSync('entry/src/main/ets/services/ApiImageDownload.ets', 'utf8'), {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020, esModuleInterop: true }
}).outputText;
vm.runInNewContext(code, { exports: exportsObject, require: name => modules[name], setInterval, clearInterval, Date, URL, Uint8Array });
const { publicImageAddress, downloadApiImage } = exportsObject;
async function main() {
  for (const ip of ['127.0.0.1', '10.0.0.1', '172.16.0.2', '192.168.0.1', '169.254.1.1', '100.64.0.1', '::1', '::ffff:127.0.0.1', 'fc00::1', 'fe80::1']) assert.equal(publicImageAddress(ip), false, ip);
  assert.equal(publicImageAddress('93.184.216.34'), true);
  assert.equal(publicImageAddress('2606:4700:4700::1111'), true);
  replies = [{ chunks: [new Uint8Array([1, 2, 3]).buffer] }];
  assert.equal(await downloadApiImage('https://public.test/a', () => false), 'data:image/png;base64,AQID');
  assert.equal(calls[0].options.requestConfiguration.transfer.autoRedirect, false);
  assert.deepEqual(Array.from(calls[0].options.requestConfiguration.dns.dnsRules[0].ipAddresses), ['93.184.216.34']);
  assert.equal(calls[0].options.requestConfiguration.proxy, 'no-proxy');
  replies = [{ status: 302, headers: { location: 'http://private.test/a' } }];
  const before = calls.length;
  await assert.rejects(downloadApiImage('https://public.test/a', () => false), error => error.name === 'InvalidImageError');
  assert.equal(calls.length, before + 1);
  replies = [{ chunks: [new ArrayBuffer(10 * 1024 * 1024 + 1)] }];
  await assert.rejects(downloadApiImage('https://public.test/a', () => false), /10 MB/);
  assert(cancelled > 0);
  await assert.rejects(downloadApiImage('https://public.test/a', () => true), /取消/);
  replies = [{ headers: { 'content-type': 'text/html' }, chunks: [new ArrayBuffer(2)] }];
  await assert.rejects(downloadApiImage('https://public.test/a', () => false), error => error.name === 'InvalidImageError');
  replies = [{ status: 404 }];
  await assert.rejects(downloadApiImage('https://public.test/a', () => false), error => error.name === 'InvalidImageError');
  await assert.rejects(downloadApiImage('https://user:password@public.test/a', () => false), error => error.name === 'InvalidImageError');
  assert(closed >= 5);
  console.log('PASS remote image DNS pinning, redirects, limits, cancellation and cleanup');
}
main().catch(error => { console.error(error); process.exitCode = 1; });
