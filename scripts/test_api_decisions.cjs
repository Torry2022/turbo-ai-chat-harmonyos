// node scripts/test_api_decisions.cjs <path/to/typescript.js>
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(process.argv[2] || 'typescript');

const source = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/services/OpenAiApiServer.ets'), 'utf8');
const ast = ts.createSourceFile('OpenAiApiServer.ts', source, ts.ScriptTarget.Latest, true);
const selected = ast.statements.filter(node =>
  (ts.isVariableStatement(node) && node.declarationList.declarations.some(declaration =>
    declaration.name.getText(ast) === 'DECISION_MODEL_ID')) ||
  (ts.isFunctionDeclaration(node) && ['prepareApiDecision', 'formatApiDecision'].includes(node.name?.text)));
const configContext = { exports: {} };
vm.runInNewContext(ts.transpileModule(fs.readFileSync(path.join(__dirname,
  '../entry/src/main/ets/models/LayaModelConfig.ets'), 'utf8'), {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
}).outputText, configContext);
const probabilityContext = {exports:{}};
vm.runInNewContext(ts.transpileModule(fs.readFileSync(path.join(__dirname,
  '../entry/src/main/ets/utils/decisionOutput.ets'),'utf8'), {
  compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2020}
}).outputText, probabilityContext);
const context = { exports: {}, LAYA_MODEL_ID: configContext.exports.LAYA_MODEL_ID,
  decisionProbabilities: probabilityContext.exports.decisionProbabilities };
vm.runInNewContext(ts.transpileModule(selected.map(node => node.getText(ast)).join('\n'), {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
}).outputText, context);
const { prepareApiDecision, formatApiDecision } = context.exports;
const request = body => prepareApiDecision(JSON.stringify(body));
const native = logits => JSON.stringify({ logits, elapsed_ms: 12 });

const choice = request({
  input: 'Keyboard moves the bottom tabs.',
  task: { type: 'choice', instruction: 'Classify the issue.', options: { ui: 'Layout', other: 'Other' } }
});
assert.equal(choice.type, 'choice');
assert.deepEqual(Array.from(choice.options), ['ui: Layout', 'other: Other']);
assert.equal(formatApiDecision(choice, native([3, 1])).result.choice, 'ui');

const score = request({
  input: 'App is slow.',
  task: { type: 'score', instruction: 'How urgent?', levels: ['Low', 'Medium', 'High'] }
});
assert.equal(score.type, 'score');
assert.equal(formatApiDecision(score, native([0, 0, 0])).result.score, 1);

const boolean = request({
  input: 'Crash after launch.',
  task: { type: 'boolean', instruction: 'Is this a defect?' }
});
assert.equal(boolean.type, 'noul');
const booleanResult = formatApiDecision(boolean, native([0, 2])).result;
assert.equal(booleanResult.type, 'boolean');
assert.equal(booleanResult.value, true);
assert.ok(booleanResult.probabilities.true > booleanResult.probabilities.false);

assert.throws(() => request({ input: 'x', task: { type: 'choice', instruction: 'Classify', options: { only: 'One' } } }), /至少需要两个候选项/);
assert.throws(() => request({ input: 'x', task: { type: 'choice', instruction: 'Classify',
  options: Object.fromEntries(Array.from({ length: 21 }, (_, index) => [`item${index}`, `Option ${index}`])) } }), /最多支持 20 个候选项/);
assert.throws(() => request({ input: 'x', task: { type: 'score', instruction: 'Score',
  levels: Array.from({ length: 21 }, (_, index) => `Level ${index}`) } }), /最多支持 20 个等级/);
assert.throws(() => request({ model: 'unknown', input: 'x', task: { type: 'boolean', instruction: 'Check' } }), /当前已加载的决策模型/);
assert.throws(() => request({ input: 'x', task: { type: 'noul', instruction: 'Check' } }), /只支持 choice、score 或 boolean/);
console.log('PASS decision request mapping and response formatting');

// All endpoint families remain routable regardless of which models are ready.
context.SERVER_OWNER = 'test';
vm.runInNewContext(ts.transpileModule(ast.statements.find(node =>
  ts.isClassDeclaration(node) && node.name.text === 'OpenAiApiServer').getText(ast), {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
}).outputText, context);
const server = new context.exports.OpenAiApiServer({
  rerankModel: () => undefined,
  isModelLoaded: () => true, isDecisionLoaded: () => true, isDecisionBusy: () => false,
  currentModel: () => ({ id: 'chat-model', name: 'Chat' }), onLog: () => {}
});
let routed, status, payload;
server.authorized = () => true;
server.sendError = (_state, code) => { status = code; };
server.sendJson = (_state, code, body) => { status = code; payload = body; };
server.handleDecision = () => { routed = 'decision'; };
server.handleChatCompletions = server.handleResponses = () => { routed = 'chat'; };
for (const endpoint of ['/v1/chat/completions', '/v1/responses', '/v1/decisions']) {
  routed = undefined; status = undefined;
  server.route({}, { method: 'POST', path: endpoint, body: '{}' });
  assert.equal(routed, endpoint === '/v1/decisions' ? 'decision' : 'chat');
  assert.equal(status, undefined);
}
for (const chatLoaded of [false, true]) {
  for (const decisionReady of [false, true]) {
    for (const rerankLoaded of [false, true]) {
      server.callbacks.isModelLoaded = () => chatLoaded;
      server.callbacks.isDecisionLoaded = () => decisionReady;
      server.callbacks.rerankModel = () => rerankLoaded ? { id: 'reranker' } : undefined;
      server.sendModels({});
      const expected = [
        ...(rerankLoaded ? ['reranker'] : []),
        ...(chatLoaded ? ['chat-model'] : []),
        ...(decisionReady ? ['Laya-Multilingual-MNN-FP16'] : []),
      ];
      assert.deepEqual(Array.from(payload.data, item => item.id), expected);
    }
  }
}
server.callbacks.isDecisionLoaded = () => false;
status = undefined;
const decisionBody = JSON.stringify({ input: 'x', task: { type: 'boolean', instruction: 'Check' } });
context.exports.OpenAiApiServer.prototype.handleDecision.call(server, {}, decisionBody);
assert.equal(status, 503);
server.callbacks.isDecisionLoaded = () => true;
server.callbacks.isDecisionBusy = () => true;
context.exports.OpenAiApiServer.prototype.handleDecision.call(server, {}, decisionBody);
assert.equal(status, 409);
console.log('PASS unified routing, loaded-only model listing, unloaded decisions and busy guards');

server.callbacks.isModelLoaded = () => false;
server.callbacks.isGenerationReady = () => false;
server.runGeneration({}, '', false, false, {});
assert.equal(status, 503);
server.callbacks.isModelLoaded = () => true;
for (const responsesApi of [false, true]) {
  server.runGeneration({}, '', false, responsesApi, {});
  assert.equal(status, 409);
}
console.log('PASS unloaded chat returns 503 while busy chat returns 409 for both API formats');

const h2oId = 'H2O-Lightning-4B-MNN-INT8';
const h2o = prepareApiDecision(JSON.stringify({model:h2oId,input:'',image:'data:image/png;base64,YQ==',
  task:{type:'choice',instruction:'Color?',options:{blue:'Blue',red:'Red'}}}),h2oId);
assert.deepEqual(Array.from(h2o.descriptions),['Blue','Red']);
const h2oResult = formatApiDecision(h2o,JSON.stringify({logits:[1,9],probabilities:[0.8,0.2],elapsed_ms:4}),h2oId);
assert.equal(h2oResult.model,h2oId);
assert.equal(h2oResult.result.choice,'blue');
assert.equal(h2oResult.result.probabilities.blue,0.8);
assert.throws(()=>formatApiDecision(h2o,JSON.stringify({logits:[1,2],probabilities:[0.8,0.8]})),/概率无效/);
assert.throws(()=>prepareApiDecision(JSON.stringify({input:'x',image:'file://private',task:{type:'boolean',instruction:'x'}}),h2oId),/数据 URI/);
const nearTie = formatApiDecision(boolean,JSON.stringify({logits:[0,0],probabilities:[0.50001,0.49999],elapsed_ms:1}),h2oId);
assert.equal(nearTie.result.value,false);
console.log('PASS H2O model identity, image validation, calibrated probabilities and boolean rounding');

async function verifyDecisionFailureStatus() {
  context.errorMessage = error => error.message;
  server.callbacks.isDecisionBusy = () => false;
  server.callbacks.onRequestState = () => {};
  for (const [name, expectedStatus] of [['InvalidImageError', 400], ['Error', 500]]) {
    server.callbacks.decide = async () => {
      const error = new Error('Invalid image data');
      error.name = name;
      throw error;
    };
    status = undefined;
    context.exports.OpenAiApiServer.prototype.handleDecision.call(server,
      { connection: { clientId: 7 }, closed: false }, decisionBody);
    await new Promise(resolve => setImmediate(resolve));
    assert.equal(status, expectedStatus);
    assert.equal(server.activeClientId, -1);
  }
  console.log('PASS invalid image returns 400, inference failure returns 500 and request state is released');
}
verifyDecisionFailureStatus().catch(error => { console.error(error); process.exitCode = 1; });

const preciseProbabilities = [0.5000100123456789, 0.4999899876543211];
const preciseRaw = {logits: [0, 0], probabilities: preciseProbabilities, elapsed_ms: 6, input_tokens: 1984};
const preciseResult = formatApiDecision(h2o, JSON.stringify(preciseRaw), h2oId);
assert.equal(preciseResult.result.probabilities.blue, preciseProbabilities[0]);
assert.equal(preciseResult.result.probabilities.red, preciseProbabilities[1]);
assert.notEqual(preciseResult.result.probabilities.blue, preciseResult.result.probabilities.red);
assert.equal(preciseResult.metadata.input_tokens, 1984);
assert.equal(preciseResult.metadata.elapsed_ms, 6);
assert.equal(preciseResult.metadata.task_calibrated, false);
const legacyMetadata = formatApiDecision(boolean, native([0, 2])).metadata;
assert.equal(Object.hasOwn(legacyMetadata, 'input_tokens'), false);
assert.equal(formatApiDecision(h2o, JSON.stringify({...preciseRaw, input_tokens: 0}), h2oId).metadata.input_tokens, 0);
for (const invalid of [-1, 1.5, '1984']) {
  assert.throws(() => formatApiDecision(h2o, JSON.stringify({...preciseRaw, input_tokens: invalid}), h2oId), /输入词元数无效/);
}
console.log('PASS unrounded native probabilities, actual input tokens and legacy metadata compatibility');

assert.equal(formatApiDecision(h2o, JSON.stringify({...preciseRaw, cpu_threads: 8}), h2oId).metadata.cpu_threads, 8);
assert.equal(Object.hasOwn(legacyMetadata, 'cpu_threads'), false);
for (const invalid of [0, 17, 4.5, '8']) {
  assert.throws(() => formatApiDecision(h2o, JSON.stringify({...preciseRaw, cpu_threads: invalid}), h2oId), /实际线程数无效/);
}
console.log('PASS verified CPU thread receipt and legacy compatibility');
