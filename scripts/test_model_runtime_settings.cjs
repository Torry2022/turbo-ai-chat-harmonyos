const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(process.argv[2] || 'typescript');
const source = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/state/ChatViewModel.ets'), 'utf8');
const ast = ts.createSourceFile('ChatViewModel.ts', source, ts.ScriptTarget.Latest, true);
const cls = ast.statements.find(n => ts.isClassDeclaration(n) && n.name.text === 'ChatViewModel');
const names = [
  'releaseRerankModel', 'reloadDecisionModel', 'reloadRerankModel',
  'decisionRuntimeChanged', 'decisionRuntimeHint', 'rerankRuntimeChanged',
  'rerankRuntimeHint', 'applyRuntimeConfigAndLoad', 'threadConfigHint'
];
const methods = cls.members.filter(n => n.name && names.includes(n.name.getText(ast))).map(n=>n.getText(ast)).join('\n');
let decision = {id:'loaded-decision'}, failRelease = false;
const events = [];
const Host = vm.runInNewContext(ts.transpileModule('class Host { '+methods+' }', {compilerOptions:{target:ts.ScriptTarget.ES2020}}).outputText+'\nHost', {
  loadedDecisionModel:()=>decision, isDecisionLoaded:()=>!!decision,
  releaseDecision:async()=>{events.push('release-decision');if(failRelease)throw Error('release failed');
 decision=undefined;},
  formatError:e=>e.message
});
function host() {
 const h = new Host();
 Object.assign(h,{busy:false,modelLoading:false,decisionImporting:false,decisionRuntimeState:'loaded',
   rerankImporting:false,reranker:{busy:false,loadedId:'loaded-rerank',release:async()=>events.push('release-rerank')},
   nativeService:{cancelTitleGeneration:async()=>events.push('cancel-title'),modelThreadInfo:()=>({chat:{actual:6}})},
   notify:()=>{}, settingFeedback:msg=>events.push(msg),loadedReranker:()=>({id:'loaded-rerank'}),
   loadDecisionModel:async model=>events.push('load-'+model.id),loadRerankModel:async model=>events.push('load-'+model.id)});
 return h;
}
(async()=>{
 let h=host();
 await h.reloadDecisionModel();
 assert.deepEqual(events.splice(0),['cancel-title','release-decision','load-loaded-decision']);
 assert.equal(h.busy,false);
 h=host();
 await h.reloadRerankModel();
 assert.deepEqual(events.splice(0),['cancel-title','release-rerank','load-loaded-rerank']);
 h=host();
 h.busy=true;
 decision={id:'loaded-decision'};
 await h.reloadDecisionModel();
 await h.reloadRerankModel();
 assert.deepEqual(events,[]);
 h=host();
 failRelease=true;
 await h.reloadDecisionModel();
 assert.equal(events.includes('load-loaded-decision'),false);
 assert.equal(h.busy,false);
 events.length=0;
 failRelease=false;
 h=host();
 h.decisionThreads=12;
 h.decisionLoadedThreads=6;
 assert.equal(h.decisionRuntimeChanged(),true);
 h.decisionThreads=6;
 assert.equal(h.decisionRuntimeChanged(),false);
 h.rerankThreads=6;
 h.rerankLoadedThreads=6;
 h.rerankMaxTokens=4096;
 h.rerankLoadedTokens=2048;
 assert.equal(h.rerankRuntimeChanged(),true);
 h.rerankMaxTokens=2048;
 assert.equal(h.rerankRuntimeChanged(),false);
 h=host();Object.assign(h,{decisionRuntimeState:'idle',loaded:true,apiServerRunning:false,apiServerStarting:false,
   rejectWhileModelScanning:()=>false,ensureCurrentModelInstalled:async()=>false,modelLifecycleService:{reset:()=>events.push('reset')},
   setStatus:()=>{},startModelLoad:()=>events.push('load-chat')});
 h.applyRuntimeConfigAndLoad();
 assert.equal(h.busy,true);
 await new Promise(resolve=>setImmediate(resolve));
 assert.equal(h.loaded,true);
 assert.deepEqual(events,[]);
 assert.equal(h.busy,false);
 h.ensureCurrentModelInstalled=async()=>true;
 h.stopApiServerForModelChange=()=>{};
 h.startModelLoad=(dialog,announce)=>{assert.equal(dialog,true);
 assert.equal(announce,false);
 events.push('load-chat');};
 h.applyRuntimeConfigAndLoad();
 await new Promise(resolve=>setImmediate(resolve));
 assert.deepEqual(events,['reset','load-chat']);
 events.length=0;
 h=host();
 h.setStatus=message=>events.push(message);
 await h.releaseRerankModel();
 assert.deepEqual(events,['release-rerank','重排模型已释放']);
 console.log('PASS reload targeting, busy guards, release failures, draft reversion, preflight and quiet chat reload');
})().catch(e=>{console.error(e);process.exitCode=1});
