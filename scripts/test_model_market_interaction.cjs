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

const filterCondition = source.match(/if \((this\.viewModel\.modelMarketCategory[^\n]*modelCatalogFilterTags\(\)\.length > 1)\) \{/);
assert(filterCondition, 'Capability filter visibility condition must exist');
const filterState = { modelMarketCategory: 'chat', modelCatalogFilterTags: () => ['全部', '图像理解'] };
const showFilters = vm.runInNewContext(`() => ${filterCondition[1]}`, { viewModel: filterState });
for (const category of ['chat', 'decision', 'embedding', 'rerank']) {
  filterState.modelMarketCategory = category;
  assert.equal(showFilters(), category === 'chat');
}
filterState.modelMarketCategory = 'chat';
filterState.modelCatalogFilterTags = () => ['全部'];
assert.equal(showFilters(), false);
console.log('PASS only conversation models display capability filters');

const viewSource = fs.readFileSync('entry/src/main/ets/state/ChatViewModel.ets', 'utf8');
const viewAst = ts.createSourceFile('view.ts', viewSource, ts.ScriptTarget.Latest, true);
const viewClass = viewAst.statements.find(node => ts.isClassDeclaration(node) && node.name.text === 'ChatViewModel');
const statusMethod = viewClass.members.find(node => node.name && node.name.getText(viewAst) === 'modelMarketStatus');
const statusCode = ts.transpileModule(`class Subject { ${statusMethod.getText(viewAst)} }`, {
  compilerOptions: { target: ts.ScriptTarget.ES2020 }
}).outputText;
const Subject = vm.runInNewContext(statusCode + '\nSubject');
const subject = new Subject();
Object.assign(subject, { modelCatalogRefreshFailed: true, modelCatalogRefreshing: false,
  modelCatalogStatus: '暂时无法更新目录，当前目录仍可使用',
  modelCatalogService: { rerankerStatus: () => '尚未获取模型目录，请刷新' } });
for (const type of ['chat', 'decision', 'embedding', 'rerank']) {
  subject.modelMarketCategory = type;
  assert.equal(subject.modelMarketStatus(), subject.modelCatalogStatus);
}
subject.modelCatalogRefreshFailed = false;
assert.equal(subject.modelMarketStatus(), '尚未获取模型目录，请刷新');
console.log('PASS offline gallery status is consistent while retaining source-specific availability');
