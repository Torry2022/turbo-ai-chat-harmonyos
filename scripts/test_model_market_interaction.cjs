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
