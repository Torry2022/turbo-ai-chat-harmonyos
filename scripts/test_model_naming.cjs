// node scripts/test_model_naming.cjs <path/to/typescript.js>
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(process.argv[2] || 'typescript');
const root = path.resolve(__dirname, '..');
const source = fs.readFileSync(path.join(root, 'entry/src/main/ets/utils/modelNaming.ets'), 'utf8');
const code = ts.transpileModule(source, {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
}).outputText;
const context = { exports: {} };
vm.runInNewContext(code, context);
const { importedModelShortName: short, resolveImportedShortName: resolve, uniqueModelShortName } = context.exports;
const cases = [
  ['Qwen3-0.6B-MNN', 'Qwen3-0.6B'],
  ['Qwen3-VL-8B-Instruct-MNN', 'Qwen3-VL-8B-Instruct'],
  ['Qwen3-4B-Instruct-2507-MNN', 'Qwen3-4B-Instruct'],
  ['Qwen_1_8B_Chat_MNN', 'Qwen-1.8B-Chat'],
  ['Qwen3 0.6B Instruct MNN', 'Qwen3-0.6B-Instruct'],
  ['Gemma-4-E2B-it-MNN', 'Gemma-4-E2B'],
  ['MiniCPM5-1B-MNN-INT8', 'MiniCPM5-1B-INT8'],
  ['MiniCPM-V-4.5-MNN', 'MiniCPM-V-4.5'],
  ['MiniMind2-MNN', 'MiniMind2'],
  ['Qwen3-30B-A3B-Instruct-MNN', 'Qwen3-30B-A3B-Instruct'],
  ['Model-Family-Instruct-MNN', 'Model-Family-Instruct'],
  ['Very-Long-Model-Family-Name-1.5B-Instruct-MNN', 'Very-Long-Model-Family-Name-1.5B'],
  ['ImportRegression-Qwen3-0.6B-20260921', 'ImportRegression-Qwen3-0.6B'],
  ['Model-2B-v2', 'Model-2B-v2'],
  ['', ''], ['  ', '']
];
for (const [input, expected] of cases) {
  assert.equal(short(input), expected, input);
}
for (const input of [
  'VeryLongGemmaFamilyNameWithExtraLetters-4-E2B-it-MNN',
  'VeryLongQwenFamilyNameWithExtraLetters-VL-8B-Instruct-MNN-INT8'
]) {
  const output = short(input);
  assert(output.length <= 32);
  for (const token of input.includes('Gemma') ? ['4', 'E2B'] : ['VL', '8B', 'INT8']) {
    assert(output.split('-').includes(token), `${input} => ${output} lost ${token}`);
  }
}
for (const saved of ['Qwen3', 'Qwen3-0.6B-MNN', '我的模型', 'Qwen3-0.6B 2']) {
  assert.equal(resolve('Qwen3-0.6B-MNN', saved), saved);
}
assert.equal(resolve('Qwen3-0.6B-MNN', ''), 'Qwen3-0.6B');
assert.equal(uniqueModelShortName('Qwen3-0.6B', [{ id: 'one', shortName: 'Qwen3-0.6B' }]), 'Qwen3-0.6B 2');
const catalog = JSON.parse(fs.readFileSync(path.join(root, 'model-catalog/catalog.json'), 'utf8'));
const items = catalog.models || catalog.items;
assert(Array.isArray(items));
for (const item of items) {
  const result = short(item.displayName);
  assert(result.length > 0 && result.length <= 32, item.displayName);
  console.log(`${item.displayName} => ${result}`);
}
console.log(`PASS ${cases.length} exact cases, identity retention, saved names, collisions, and ${items.length} catalog entries`);
