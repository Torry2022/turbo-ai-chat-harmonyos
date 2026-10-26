// Runs the real scheduler and inference bridge with deferred native jobs and a deterministic clock.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(process.argv[2] || 'typescript');
const root = path.resolve(__dirname, '..');
const timers = new Map();
let time = 0, nextTimer = 1;
function later(fn, delay) { const id = nextTimer++; timers.set(id, { at: time + delay, fn }); return id; }
function advance(ms) {
  time += ms;
  for (const [id, task] of [...timers]) if (task.at <= time) { timers.delete(id); task.fn(); }
}
async function flush() { for (let i = 0; i < 16; i++) await Promise.resolve(); }
function deferred() { let resolve, reject; const promise = new Promise((a,b) => { resolve=a; reject=b; }); return { promise, resolve, reject }; }
let nativeLog = [], titleNative;
const stopped = { text: '', generatedTokens: 0, stopReason: 'user_stop' };
const finished = { text: '合适的标题', generatedTokens: 5, stopReason: 'eos' };
const native = {
  generateChatStream: (_turns, _limit, _settings, _chunk, title) => {
    nativeLog.push(title ? 'title' : 'chat');
    if (title) { titleNative=deferred(); return titleNative.promise; }
    return Promise.resolve(finished);
  },
  generateRawPromptStream: () => { nativeLog.push('raw'); return Promise.resolve(finished); },
  generateImageChatStream: () => { nativeLog.push('image'); return Promise.resolve(finished); },
  cancelTitleGeneration: () => { nativeLog.push('cancel-title'); },
  stopGeneration: () => { nativeLog.push('stop-chat'); },
  reset: () => { nativeLog.push('reset'); },
  loadModelAsync: () => { nativeLog.push('load'); return Promise.resolve('loaded'); },
  isLoaded: () => true
};
const cache = new Map();
function load(file) {
  file=path.resolve(root,'entry/src/main/ets',file);
  if (cache.has(file)) return cache.get(file);
  const module={ exports:{} }; cache.set(file,module.exports);
  const code=ts.transpileModule(fs.readFileSync(file,'utf8'), {compilerOptions:{
    module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2020,esModuleInterop:true
  }}).outputText;
  vm.runInNewContext(code, {
    module,exports:module.exports,console,Promise,
    require:name => name === 'libentry.so' ? native : load(path.resolve(path.dirname(file),name+'.ets')),
    setTimeout:later,clearTimeout:id=>timers.delete(id)
  },{filename:file});
  return module.exports;
}
const { ConversationTitleService, prepareConversationTitle, cleanConversationTitle }=load('services/ConversationTitleService.ets');
const { NativeInferenceService }=load('services/NativeInferenceService.ets');
function record(id='c-title-1') {
  return {id,title:'临时标题',titleSource:'temporary',messages:[
    {id:1,role:'user',kind:'message',content:'如何给会话命名？',includeInContext:true},
    {id:2,role:'assistant',kind:'message',content:'可以概括首轮问答。',includeInContext:true,generationState:'complete',completedAt:20}
  ]};
}
const tests=[];
function test(name,run) { tests.push({name,run}); }
function scheduler() {
  let ready=true, cancel=0;
  const jobs=[], writes=[];
  const service=new ConversationTitleService(
    ()=>ready,
    turns=>{const job=deferred();jobs.push({...job,turns});return job.promise;},
    ()=>{cancel++;return Promise.resolve();},
    async (request,title)=>{writes.push({id:request.id,title});}
  );
  return {service,jobs,writes,setReady:x=>{ready=x;},get cancel(){return cancel;}};
}
test('only complete first turns qualify; legacy and manual names stay untouched',()=>{
  assert.ok(prepareConversationTitle(record()));
  for (const state of ['generating','stopped','failed','interrupted']) {
    const r=record();r.messages[1].generationState=state;assert.equal(prepareConversationTitle(r),undefined);
  }
  for (const source of [undefined,'manual','generated']) {
    const r=record();r.titleSource=source;assert.equal(prepareConversationTitle(r),undefined);
  }
  assert.equal(cleanConversationTitle({...finished,text:'<think>内部思考</think>简洁标题'}),'简洁标题');
  assert.equal(cleanConversationTitle({...finished,stopReason:'max_tokens'}),'');
  assert.equal(cleanConversationTitle({...finished,text:'第一行\n解释'}),'');
  const englishTitle='Reduce Android Battery Drain Without Disabling Notifications';
  assert.equal(cleanConversationTitle({...finished,text:englishTitle}),englishTitle);
  const modelTitle='bge-small-zh-v1.5、bge-large-zh-v1.5 和 bge-m3 区别';
  assert.equal(cleanConversationTitle({...finished,text:modelTitle}),modelTitle);
  assert.equal(cleanConversationTitle({...finished,text:'中'.repeat(33)}),'');
  assert.equal(cleanConversationTitle({...finished,text:'a'.repeat(101)}),'');
});
test('long questions retain both the opening and final request within a bounded excerpt',()=>{
  const r=record();
  r.messages[0].content='问题开头：'+ '😀背景材料'.repeat(180)+'最后请求：比较两款手机的续航。';
  r.messages[1].content='<think>不应进入标题材料</think>'+'回答开头：'+'详细说明'.repeat(100)+'最后结论：优先选择续航更长的一款。';
  const prompt=prepareConversationTitle(r).turns[1].content;
  const question=prompt.split('<用户问题>\n')[1].split('\n</用户问题>')[0];
  const answer=prompt.split('<助手回答>\n')[1].split('\n</助手回答>')[0];
  for(const [value,limit,opening,ending] of [
    [question,512,'问题开头：','最后请求：比较两款手机的续航。'],
    [answer,256,'回答开头：','最后结论：优先选择续航更长的一款。']
  ]) {
    assert.ok(value.startsWith(opening)&&value.endsWith(ending));
    assert.equal(Array.from(value.replace('\n[中间内容省略]\n','')).length,limit);
    assert.ok(!/[\uD800-\uDBFF](?![\uDC00-\uDFFF])|(?<![\uD800-\uDBFF])[\uDC00-\uDFFF]/u.test(value));
  }
  assert.ok(!prompt.includes('不应进入标题材料'));
});
test('short first turns are complete and unrelated later turns are excluded',()=>{
  const r=record();r.messages.push({id:3,role:'user',kind:'message',content:'不相关的第二个问题'});
  const prompt=prepareConversationTitle(r).turns[1].content;
  assert.ok(prompt.includes(r.messages[0].content)&&prompt.includes(r.messages[1].content));
  assert.ok(!prompt.includes('[中间内容省略]')&&!prompt.includes('不相关的第二个问题'));
});
test('idle delay and repeated notifications never create duplicate jobs',async()=>{
  const h=scheduler();h.service.enqueue(record());advance(900);h.service.resume();advance(899);assert.equal(h.jobs.length,0);
  advance(1);assert.equal(h.jobs.length,1);
  for(let i=0;i<50;i++)h.service.enqueue(record());
  h.jobs[0].resolve(finished);await flush();advance(2000);assert.equal(h.jobs.length,1);assert.equal(h.writes.length,1);
  h.service.dispose();
});
test('a hundred new conversations are bounded and do not queue native inference while busy',async()=>{
  const h=scheduler();h.setReady(false);
  for(let i=0;i<100;i++)h.service.enqueue(record('c-'+i));
  assert.equal(h.service.pending.size,8);advance(10000);assert.equal(h.jobs.length,0);
  h.setReady(true);h.service.resume();advance(1800);assert.equal(h.jobs.length,1);assert.equal(h.service.active.id,'c-99');
  h.service.dispose();h.jobs[0].resolve(stopped);await flush();assert.equal(h.writes.length,0);
});
test('preempted naming waits for completion, retries only when idle, and never applies cancelled text',async()=>{
  const h=scheduler();h.service.enqueue(record());advance(1800);
  h.setReady(false);h.service.pause();h.service.pause();assert.equal(h.cancel,1);
  h.service.resume();advance(10000);assert.equal(h.jobs.length,1);
  h.jobs[0].resolve(finished);await flush();assert.equal(h.writes.length,0);
  h.setReady(true);h.service.resume();advance(1800);assert.equal(h.jobs.length,2);
  h.jobs[1].resolve(finished);await flush();assert.equal(h.writes.length,1);h.service.dispose();
});
test('rename, deletion and dispose discard active requests instead of reviving them',async()=>{
  for(const mode of ['rename','clear','dispose']) {
    const h=scheduler();h.service.enqueue(record());advance(1800);
    if(mode==='rename')h.service.forget('c-title-1');
    else if(mode==='clear')h.service.forget();
    else h.service.dispose();
    h.jobs[0].resolve(finished);await flush();advance(4000);
    assert.equal(h.writes.length,0);assert.equal(h.jobs.length,1);assert.equal(h.service.pending.size,0);
    h.service.dispose();
  }
});
test('failure leaves the fallback title and does not spin or retry on each notification',async()=>{
  const h=scheduler();h.service.enqueue(record());advance(1800);h.jobs[0].reject(Error('failure'));await flush();
  for(let i=0;i<100;i++){h.service.enqueue(record());h.service.resume();advance(2000);}
  assert.equal(h.jobs.length,1);assert.equal(h.writes.length,0);h.service.dispose();
});
const settings={temperature:.7,topP:.8,topK:20,repetitionPenalty:1.05,frequencyPenalty:0,presencePenalty:0,penaltyWindow:256};
test('chat preempts title across service instances and waits until its native job has exited',async()=>{
  nativeLog=[];const a=new NativeInferenceService(),b=new NativeInferenceService();
  const title=a.generateTitle([]);const chat=b.generateText([],20,settings,()=>{});await flush();
  assert.deepEqual(nativeLog,['title','cancel-title']);
  titleNative.resolve(stopped);await title;await chat;assert.equal(nativeLog.at(-1),'chat');
});
test('a foreground job blocks new title work until it has actually completed',async()=>{
  const original=native.generateChatStream, job=deferred(), a=new NativeInferenceService();
  native.generateChatStream=()=>job.promise;
  try {
    const chat=a.generateText([],20,settings,()=>{});await flush();
    await assert.rejects(a.generateTitle([]));
    job.resolve(finished);await chat;
  } finally {native.generateChatStream=original;}
  const title=a.generateTitle([]);titleNative.resolve(finished);await title;
});
test('release cancels first, never blocks JS, and finishes before a following model load',async()=>{
  nativeLog=[];const a=new NativeInferenceService();const title=a.generateTitle([]);
  const release=a.reset();const loading=a.loadModel('config.json',4,20,settings);await flush();
  assert.ok(!nativeLog.includes('reset')&&!nativeLog.includes('load'));
  titleNative.resolve(stopped);await title;await release;await loading;
  assert.deepEqual(nativeLog.filter(x=>x==='reset'||x==='load'),['reset','load']);
});
test('stopping a chat while it waits for title cancellation cannot launch that chat later',async()=>{
  nativeLog=[];const a=new NativeInferenceService();const title=a.generateTitle([]);
  const chat=a.generateText([],20,settings,()=>{});a.stopGeneration();titleNative.resolve(stopped);
  await title;assert.equal((await chat).stopReason,'user_stop');assert.ok(!nativeLog.includes('chat'));
});
test('API/raw and image paths also preempt titles without firing the generic chat stop flag',async()=>{
  for(const mode of ['raw','image']){
    nativeLog=[];const a=new NativeInferenceService();const title=a.generateTitle([]);
    const foreground=mode==='raw'?a.generateRawPrompt('',20,'',settings,()=>{}):a.generateImage([],{pixels:new ArrayBuffer(4),width:1,height:1},20,settings,()=>{});
    await flush();assert.ok(!nativeLog.includes(mode));titleNative.resolve(stopped);await title;await foreground;
    assert.equal(nativeLog.at(-1),mode);assert.ok(!nativeLog.includes('stop-chat'));
  }
});
(async()=>{for(const t of tests){timers.clear();await t.run();console.log('PASS',t.name);}console.log(tests.length+' title scheduler/preemption checks passed.');})()
  .catch(error=>{console.error(error);process.exitCode=1;});
