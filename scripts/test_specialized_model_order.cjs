const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const ts = require(process.argv[2] || 'typescript');
const source = fs.readFileSync('entry/src/main/ets/state/ChatViewModel.ets', 'utf8');
const ast = ts.createSourceFile('view.ts', source, ts.ScriptTarget.Latest, true);
const declaration = ast.statements.find(node => ts.isClassDeclaration(node) && node.name.text === 'ChatViewModel');
const names = ['orderedSpecializedModels', 'moveSpecializedModel', 'loadSpecializedModelOrder'];
const methods = declaration.members.filter(node => node.name && names.includes(node.name.getText(ast)));
const drag = fs.readFileSync('entry/src/main/ets/utils/modelDrag.ets', 'utf8').replace(/export /g, '');
const code = ts.transpileModule(`${drag}\nclass Subject { ${methods.map(node => node.getText(ast)).join('\n')} }`, {
  compilerOptions: { target: ts.ScriptTarget.ES2020 }
}).outputText;
let saved = '';
const store = { get: async () => saved, put: async (_key, value) => { saved = value; }, flush: async () => {} };
const Subject = vm.runInNewContext(code + '\nSubject', {
  preferences: { getPreferences: async () => store }
});
function subject() {
  const result = new Subject();
  Object.assign(result, { specializedModelOrder: [], specializedOrderRevision: 0,
    specializedOrderSave: Promise.resolve(), context: {}, modelOrderPreferenceName: 'models',
    decisionModels: () => result.orderedSpecializedModels([{ id: 'laya' }, { id: 'h2o' }]),
    embeddingProfiles: [{ id: 'bge' }, { id: 'gte' }], rerankProfiles: [{ id: 'r1' }, { id: 'r2' }],
    notify() {}, toastCallback(message) { throw new Error(message); } });
  return result;
}
(async () => {
  const first = subject();
  first.moveSpecializedModel('decision', 'h2o', 0);
  first.moveSpecializedModel('embedding', 'gte', 0);
  first.moveSpecializedModel('rerank', 'r2', 0);
  await first.specializedOrderSave;
  const restored = subject();
  await restored.loadSpecializedModelOrder();
  assert.deepEqual(Array.from(restored.decisionModels(), p => p.id), ['h2o', 'laya']);
  assert.deepEqual(Array.from(restored.orderedSpecializedModels(restored.embeddingProfiles), p => p.id), ['gte', 'bge']);
  assert.deepEqual(Array.from(restored.orderedSpecializedModels(restored.rerankProfiles), p => p.id), ['r2', 'r1']);
  assert.deepEqual(Array.from(restored.orderedSpecializedModels([{ id: 'bge' }, { id: 'new' }]), p => p.id), ['bge', 'new']);
  const before = saved;
  restored.moveSpecializedModel('chat', 'bge', 0);
  restored.moveSpecializedModel('embedding', 'missing', 0);
  restored.busy = true;
  restored.moveSpecializedModel('embedding', 'bge', 0);
  await restored.specializedOrderSave;
  assert.equal(saved, before);
  console.log('PASS specialized model order survives reload, appends new models and isolates categories');
})().catch(error => { console.error(error); process.exitCode = 1; });
