// node scripts/test_download_errors.cjs <path/to/typescript.js>
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(process.argv[2] || 'typescript');
const source = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/utils/formatters.ets'), 'utf8');
const context = { exports: {} };
vm.runInNewContext(ts.transpileModule(source, { compilerOptions: {
  module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020
}}).outputText, context);
const { formatDownloadError, formatError } = context.exports;
const cases = [
  [{ code: 2300028, message: 'Operation timeout' }, '连接下载服务超时，请检查网络或代理设置后重试。'],
  [new Error('Operation timeout'), '连接下载服务超时，请检查网络或代理设置后重试。'],
  ['BusinessError: code=2300028 Operation timeout', '连接下载服务超时，请检查网络或代理设置后重试。'],
  [{ code: 2300005, message: 'Could not resolve proxy' }, '无法连接代理服务器，请检查代理设置后重试。'],
  [{ code: 2300006, message: 'Could not resolve host' }, '无法解析下载地址，请检查网络后重试。'],
  [{ code: 2300007, message: 'Failed to connect' }, '无法连接下载服务，请检查网络或代理设置后重试。'],
  [{ code: 2300060, message: 'SSL certificate validation failed' }, '下载连接验证失败，请检查设备时间或更换网络后重试。'],
  [new Error('llm.mnn.weight 写入失败：Error: ENOSPC'), '存储空间不足，请清理空间后重试。'],
  [{ code: 13900028, message: 'No space left on device' }, '存储空间不足，请清理空间后重试。'],
  [new Error('模型配置已不可用（HTTP 404）'), '下载地址已失效，请刷新模型广场后重试。'],
  [new Error('下载响应无效：HTTP 403'), '下载源拒绝访问，请确认模型可公开下载后重试。'],
  [new Error('下载响应无效：HTTP 416'), '续传信息已失效，请关闭安装窗口后重新下载。'],
  [new Error('下载响应无效：HTTP 503'), '下载服务暂时不可用，请稍后重试。'],
  [{ code: 2300056, message: 'Connection reset' }, '下载连接已中断，请检查网络后继续下载。'],
  [new Error('模型文件 SHA-256 校验失败，请重新下载'), '模型文件 SHA-256 校验失败，请重新下载'],
  [new Error('下载已取消'), '下载已取消'],
  [new Error('续传范围或长度不匹配'), '续传范围或长度不匹配']
];
for (const [input, expected] of cases) assert.equal(formatDownloadError(input), expected);
for (const input of [null, undefined, {}, new Error('unexpected transport failure'), new Error('写入失败：Error: unknown failure')]) {
  assert.equal(formatDownloadError(input), '下载未完成，请检查网络和可用存储空间后重试。');
}
const diagnostic = { code: 2300028, name: 'BusinessError', message: 'Operation timeout' };
assert.ok(formatError(diagnostic).includes('2300028'));
assert.ok(formatError(diagnostic).includes('Operation timeout'));
assert.ok(!formatDownloadError(diagnostic).includes('2300028'));
assert.ok(!formatDownloadError(diagnostic).includes('Operation timeout'));
console.log('PASS 22 download error presentations and preserved diagnostic details');
