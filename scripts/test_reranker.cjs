// node scripts/test_reranker.cjs <path/to/typescript.js>
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const ts = require(process.argv[2] || 'typescript');
function compile(file, imports) {
  const context = { exports: {}, require: imports, console, setTimeout, clearTimeout, TextDecoder };
  vm.runInNewContext(ts.transpileModule(fs.readFileSync(path.join(__dirname, '..', file), 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText, context);
  return context.exports;
}
const utils = compile('entry/src/main/ets/utils/rerank.ets', () => ({}));
for (const body of [null, [], {}, {query:' ',documents:['a']}, {query:'q',documents:[]},
  {query:'q',documents:[null]}, {query:'q',documents:['a'],top_n:0}, {query:'q',documents:['a'],top_n:1.5},
  {query:'q',documents:Array(65).fill('x')}]) assert.notEqual(utils.validateRerankRequest(body), '');
assert.equal(utils.validateRerankRequest({query:'q',documents:['a','b'],top_n:1}), '');
assert.deepEqual(JSON.parse(JSON.stringify(utils.rankScores([0.2,0.8,0.8],3))), [
  {index:1,relevance_score:0.8},{index:2,relevance_score:0.8},{index:0,relevance_score:0.2}]);
for (const score of [NaN,Infinity,-0.1,1.1]) assert.throws(() => utils.rankScores([score],1));

const native = { rerankerAsync: async () => [], rerankerCancel: () => {} };
const {RerankerService} = compile('entry/src/main/ets/services/RerankerService.ets', name =>
  name === 'libentry.so' ? {default:native} : {});
const {OpenAiApiServer} = compile('entry/src/main/ets/services/OpenAiApiServer.ets', name => {
  if (name.includes('/rerank')) return utils;
  if (name === '@ohos.util') return {default:{TextDecoder:{create:()=>new TextDecoder()}}};
  return {};
});
const tick = () => new Promise(resolve => setImmediate(resolve));
(async () => {
  const service = new RerankerService(); service.loadedId = 'model';
  let resume; const preparing = new Promise(resolve => {resume=resolve});
  let nativeCalls=0; native.rerankerAsync=async()=>{nativeCalls++;return [0.8]};
  const pending = service.score('q',['doc'],()=>preparing);
  assert.equal(service.busy,true);
  await assert.rejects(service.release());
  await assert.rejects(service.score('q',['doc'],async()=>{}));
  service.cancel(); resume(); await assert.rejects(pending);
  assert.equal(nativeCalls,0); assert.equal(service.busy,false);
  assert.deepEqual(await service.score('q',['doc'],async()=>{}),[0.8]);
  let resolveScore, cancels=0, available=true;
  const server = new OpenAiApiServer({
    rerankModel:()=>available?{id:'model',name:'Model'}:undefined,
    isRerankBusy:()=>false, rerank:()=>new Promise(resolve=>{resolveScore=resolve}),
    cancelRerank:()=>{cancels++},onStatus:()=>{},onLog:()=>{}
  });
  const responses=[]; server.sendError=(_state,status,code)=>responses.push({status,code});
  server.sendJson=(_state,status,body)=>responses.push({status,body});
  const state={closed:false}; const request=JSON.stringify({model:'model',query:'q',documents:['a','b','c'],top_n:2});
  server.handleRerank(state,'{}'); assert.equal(responses.pop().status,400);
  available=false; server.handleRerank(state,request);assert.equal(responses.pop().status,503);available=true;
  server.handleRerank(state,request.replace('"model":"model"','"model":"wrong"'));assert.equal(responses.pop().status,400);
  server.handleRerank(state,request);server.handleRerank({},request);assert.equal(responses.pop().status,409);
  server.running=true; await server.stop();assert.equal(cancels,1);
  server.handleRerank({},request);assert.equal(responses.pop().status,409);
  resolveScore([0.3,0.9,0.9]);await tick();
  const response=responses.pop();assert.equal(response.status,200);
  assert.deepEqual(JSON.parse(JSON.stringify(response.body.results)),[{index:1,relevance_score:0.9},{index:2,relevance_score:0.9}]);
  server.handleRerank(state,request);resolveScore([0.1]);await tick();assert.equal(responses.pop().status,500);
  assert.equal(server.rerankConnection,undefined);
  console.log('PASS rerank validation, stable ordering, input mapping, pending cancellation, release protection and HTTP stop/restart ownership');
})().catch(error=>{console.error(error);process.exitCode=1});
