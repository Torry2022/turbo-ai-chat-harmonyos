// node scripts/test_model_descriptions.cjs <path/to/typescript.js>
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(process.argv[2] || 'typescript');
const root = path.resolve(__dirname, '../entry/src/main/ets');
const compile = source => ts.transpileModule(source, {compilerOptions: {
  module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020
}}).outputText;
function load(file) {
  const module = {exports: {}};
  vm.runInNewContext(compile(fs.readFileSync(file, 'utf8')), {module, exports: module.exports,
    require: id => load(path.resolve(path.dirname(file), id + '.ets'))});
  return module.exports;
}
const {parseModelDescriptions, descriptionRepo} = load(path.join(root, 'utils/modelDescriptions.ets'));
const text = fs.readFileSync(path.resolve(root, '../resources/rawfile/model_descriptions_zh.json'), 'utf8');
const manifest = parseModelDescriptions(text);
const fixture = {schemaVersion: 1, descriptionVersion: 1, publishedAt: '2026-11-03T06:00:00Z',
  entries: [{repo: 'MNN/Example-MNN', description: '已核实的模型用途', sources: ['https://example.com/card']}]};
for (const patch of [{schemaVersion: 2}, {descriptionVersion: 0}, {descriptionVersion: 1.2},
  {descriptionVersion: '2'}, {publishedAt: 'invalid'}, {entries: null}]) {
  assert.throws(() => parseModelDescriptions(JSON.stringify({...fixture, ...patch})));
}
for (const patch of [{repo: '../Example'}, {repo: 'https://example.com/repo'}, {description: ''},
  {description: 'a'.repeat(81)}, {description: 'first\nsecond'}, {sources: []}, {sources: ['http://example.com/card']}]) {
  assert.throws(() => parseModelDescriptions(JSON.stringify({...fixture, entries: [{...fixture.entries[0], ...patch}]})));
}
assert.throws(() => parseModelDescriptions(JSON.stringify({...fixture,
  entries: [fixture.entries[0], {...fixture.entries[0], repo: 'mnn/example-mnn'}]})));
assert.doesNotThrow(() => parseModelDescriptions(JSON.stringify({...fixture, entries: []})));
assert.equal(descriptionRepo('https://modelscope.cn/models/MNN/Example-MNN'), 'mnn/example-mnn');
assert.equal(descriptionRepo('https://example.com/models/MNN/Example-MNN'), '');
assert.notEqual(descriptionRepo('https://modelscope.cn/models/MNN/Example-2B-MNN'),
  descriptionRepo('https://modelscope.cn/models/MNN/Example-4B-MNN'));
const {MODEL_CATALOG_ITEMS} = load(path.join(root, 'models/BuiltinModelDownloadTypes.ets'));
const supplemental = JSON.parse(fs.readFileSync(path.resolve(__dirname, '../model-catalog/catalog-v2.json'), 'utf8'));
const repos = new Set(manifest.entries.map(entry => entry.repo.toLowerCase()));
for (const item of MODEL_CATALOG_ITEMS) assert(repos.has(descriptionRepo(item.sourceUrl)), item.id);
for (const item of supplemental.items) assert(repos.has(item.source.repo.toLowerCase()), item.id);
for (const entry of manifest.entries) assert(entry.description.length <= 50, entry.repo + ': card summary is too long');
console.log('PASS description schema, exact repository matching, summary length, sources and bundled catalog coverage');
const source = fs.readFileSync(path.join(root, 'state/ChatViewModel.ets'), 'utf8');
const ast = ts.createSourceFile('view.ts', source, ts.ScriptTarget.Latest, true);
const cls = ast.statements.find(node => ts.isClassDeclaration(node) && node.name.text === 'ChatViewModel');
const method = cls.members.find(node => node.name?.getText(ast) === 'loadModelCatalog');
const Subject = vm.runInNewContext(compile(`class Subject {${method.getText(ast)}}`) + '\nSubject', {
  util: {TextDecoder: {create: () => ({decodeToString: bytes => Buffer.from(bytes).toString('utf8')})}},
  console: {warn() {}}
});
(async () => {
  const view = new Subject(); let received;
  Object.assign(view, {filesDir: '/sandbox', modelCatalogService: {load: async (dir, contents) => {
    received = {dir, contents}; return 'loaded';
  }}});
  assert.equal(await view.loadModelCatalog({resourceManager: {getRawFileContent: async name => {
    assert.equal(name, 'model_descriptions_zh.json'); return Buffer.from(text, 'utf8');
  }}}), 'loaded');
  assert.equal(received.contents, text); assert.equal(received.dir, '/sandbox');
  await view.loadModelCatalog({resourceManager: {getRawFileContent: async () => {throw Error('missing resource');}}});
  assert.equal(received.contents, '', 'missing resources leave cached/default descriptions usable');
  console.log('PASS bundled UTF-8 descriptions reach the catalog service and resource failures retain fallbacks');
})().catch(error => {console.error(error); process.exitCode = 1;});
