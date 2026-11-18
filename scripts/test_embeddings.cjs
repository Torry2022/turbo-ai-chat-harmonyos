// node scripts/test_embeddings.cjs <path/to/typescript.js>
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const ts = require(process.argv[2] || 'typescript');
function compile(file, imports = () => ({})) {
  const context = { exports: {}, require: imports, console, setTimeout, clearTimeout, TextDecoder };
  vm.runInNewContext(ts.transpileModule(fs.readFileSync(path.join(__dirname, '..', file), 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText, context);
  return context.exports;
}
const utils = compile('entry/src/main/ets/utils/embeddings.ets');
for (const input of [null, [], {}, {input:''}, {input:['a', ' ']}, {input:[1]},
  {input:Array(65).fill('a')}, {input:'a', model:''}, {input:'a', encoding_format:'base64'},
  {input:'a', dimensions:0}, {input:'a', dimensions:1.5}]) assert.throws(() => utils.embeddingInputs(input));
assert.deepEqual(Array.from(utils.embeddingInputs({input:'你好'})), ['你好']);
assert.deepEqual(Array.from(utils.embeddingInputs({input:['a','b'],dimensions:512})), ['a','b']);
const execution = compile('entry/src/main/ets/services/ModelExecutionService.ets');
let finishEncode;
const native = {embeddingAsync:async operation => operation === 'encode' ? new Promise(resolve => {finishEncode=resolve}) :
  {vectors:[],inputTokens:0,dimension:512,threads:3}};
const { EmbeddingService } = compile('entry/src/main/ets/services/EmbeddingService.ets', name =>
  name === 'libentry.so' ? {default:native} : name.includes('ModelExecutionService') ? execution :
  name.includes('NativeInferenceService') ? {NativeInferenceService:class {async cancelTitleGeneration(){}}} :
  {ModelDirectoryPreflightService:class {async requireCompatible(){}}});
const { OpenAiApiServer } = compile('entry/src/main/ets/services/OpenAiApiServer.ets', name =>
  name.includes('/embeddings') ? utils : name === '@ohos.util' ? {default:{TextDecoder:{create:()=>new TextDecoder()}}} : {});
const tick = () => new Promise(resolve => setImmediate(resolve));
(async () => {
  const service = new EmbeddingService();
  const release = execution.ModelExecutionService.acquire('chat');
  await assert.rejects(service.load({id:'model',configPath:'/model/config.json'},3),/当前模型任务/);
  assert.equal(service.busy,false); release();
  await service.load({id:'model',configPath:'/model/config.json'},3);
  assert.equal(service.loadedId,'model'); assert.equal(service.threads,3);
  const encoding = service.encode(['a']); await tick();
  await assert.rejects(service.release());
  assert.equal(execution.ModelExecutionService.current(),'embedding');
  finishEncode({vectors:[[1,0]],inputTokens:3,dimension:2,threads:3}); await encoding;
  assert.equal(service.busy,false); assert.equal(execution.ModelExecutionService.current(),undefined);
  await service.release(); assert.equal(service.loadedId,'');
  let finish, available=true, busy=false;
  const activity=[], responses=[];
  const server = new OpenAiApiServer({embeddingModel:()=>available?{id:'model',name:'Model'}:undefined,
    embeddings:()=>new Promise(resolve=>{finish=resolve}),isEmbeddingBusy:()=>busy,
    onRequestState:(kind,active)=>activity.push([kind,active]),onLog:()=>{}});
  server.sendError=(_state,status,code)=>responses.push({status,code});
  server.sendJson=(_state,status,body)=>responses.push({status,body});
  const state={closed:false}, request=JSON.stringify({input:['a','b'],model:'model'});
  server.handleEmbeddings(state,'null');assert.equal(responses.pop().status,400);
  available=false;server.handleEmbeddings(state,request);assert.equal(responses.pop().status,503);available=true;
  server.handleEmbeddings(state,request.replace('"model":"model"','"model":"other"'));assert.equal(responses.pop().status,400);
  busy=true;server.handleEmbeddings(state,request);assert.equal(responses.pop().status,409);busy=false;
  server.rerankConnection={};server.handleEmbeddings(state,request);assert.equal(responses.pop().status,409);server.rerankConnection=undefined;
  server.handleEmbeddings(state,request);server.handleEmbeddings({},request);assert.equal(responses.pop().status,409);
  finish({vectors:[[1,0],[0,1]],inputTokens:6,dimension:2,threads:3});await tick();
  const result=responses.pop();assert.equal(result.status,200);
  assert.deepEqual(JSON.parse(JSON.stringify(result.body)),{object:'list',model:'model',data:[
    {object:'embedding',index:0,embedding:[1,0]},{object:'embedding',index:1,embedding:[0,1]}],usage:{prompt_tokens:6,total_tokens:6}});
  assert.equal(server.embeddingConnection,undefined);
  server.handleEmbeddings(state,request);state.closed=true;
  finish({vectors:[[1,0],[0,1]],inputTokens:6,dimension:2});await tick();
  assert.equal(responses.length,0);assert.equal(server.embeddingConnection,undefined);
  assert.deepEqual(activity,[['embedding',true],['embedding',false],['embedding',true],['embedding',false]]);
  console.log('PASS embeddings validation, thread forwarding, shared execution, release protection, ordered API output and disconnect cleanup');
})().catch(error=>{console.error(error);process.exitCode=1});
