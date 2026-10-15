const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const ts = require(process.argv[2] || 'typescript');
const file = path.join(__dirname, '../entry/src/main/ets/utils/messageSelection.ets');
const code = ts.transpileModule(fs.readFileSync(file, 'utf8'), {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }
}).outputText;
const exportsObject = {};
vm.runInNewContext(code, { exports: exportsObject });
const { joinMessageSelection } = exportsObject;
const part = (block, row, column, kind, text) => ({ block, row, column, kind, text });
const check = (parts, expected, native = parts.map(p => p.text).join('\n')) =>
  assert.equal(joinMessageSelection(parts, native), expected);
check([], '');
check([part(0, 0, 0, 'text', '部分文字')], '部分文字');
check([part(0, 0, 0, 'text', '段落末尾'), part(1, 0, 0, 'text', '下一段开头')], '段落末尾\n\n下一段开头');
check([part(0, 0, 0, 'list', '1.'), part(0, 0, 1, 'list', '第一项'),
  part(0, 1, 0, 'list', '2.'), part(0, 1, 1, 'list', '第二项')], '1. 第一项\n2. 第二项');
check([part(0, 0, 1, 'list', '项的末尾'), part(0, 1, 0, 'list', '•'),
  part(0, 1, 1, 'list', '下一项')], '项的末尾\n• 下一项');
check([part(0, 0, 0, 'table', '名称'), part(0, 0, 1, 'table', '数量'),
  part(0, 1, 0, 'table', '苹果'), part(0, 1, 1, 'table', '2')], '名称\t数量\n苹果\t2');
check([part(0, 0, 1, 'table', '2'), part(0, 1, 0, 'table', '2'),
  part(0, 1, 1, 'table', '2')], '2\n2\t2');
check([part(0, 0, 0, 'text', '正文'), part(1, 0, 0, 'text', 'const x = 1;\n  log(x);')],
  '正文\n\nconst x = 1;\n  log(x);');
// Callback order must not change visual copy order; stale nodes must not change native contents.
check([part(1, 0, 0, 'text', '后'), part(0, 0, 0, 'text', '前')], '前\n\n后', '前\n后');
check([part(0, 0, 0, 'text', '旧选区')], '当前选区', '当前选区');
check([part(0, 0, 0, 'text', 'A😀'), part(1, 0, 0, 'text', '中文')], 'A😀\n\n中文');
check([part(0, 0, 0, 'table', 'A'), part(0, 0, 2, 'table', 'C'),
  part(0, 1, 1, 'table', 'B')], 'A\t\tC\n\tB');
console.log('message selection: 12 cases passed');
