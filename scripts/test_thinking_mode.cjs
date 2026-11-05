// node scripts/test_thinking_mode.cjs <path/to/typescript.js>
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(process.argv[2] || 'typescript');
const root = path.resolve(__dirname, '../entry/src/main/ets');
function compile(source) { return ts.transpileModule(source, { compilerOptions: {
  module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020
} }).outputText; }
function moduleFrom(file, require) {
  const module = { exports: {} };
  vm.runInNewContext(compile(fs.readFileSync(path.join(root,file),'utf8')), {module,exports:module.exports,require});
  return module.exports;
}
const { modelThinkingSupport } = moduleFrom('utils/modelThinking.ets', () => {});
const template = "{% if enable_thinking is defined and enable_thinking is false %}{{ '<think>\\n\\n</think>' }}{% endif %}";
const llm = JSON.stringify({ jinja: { chat_template: template } });
assert.equal(modelThinkingSupport('{}',llm).supported, true);
assert.equal(modelThinkingSupport('{}',llm).defaultEnabled, true);
assert.equal(modelThinkingSupport('{"jinja":{"context":{"enable_thinking":false}}}',llm).defaultEnabled,false);
assert.equal(modelThinkingSupport('{"use_template":false}',llm).supported,false);
assert.equal(modelThinkingSupport('{}','{"jinja":{"chat_template":"{% if add_generation_prompt %}answer{% endif %}"}}').supported,false);
assert.equal(modelThinkingSupport('{}','{"tags":["Think"]}').supported,false);
assert.equal(modelThinkingSupport(JSON.stringify({jinja: {chat_template: template}}),
  '{"jinja":{"chat_template":"fixed output"}}').supported, false,
  'llm_config template overrides config.json as in the native MNN merge');
assert.equal(modelThinkingSupport('{"jinja":{"context":{"enable_thinking":false}}}',
  JSON.stringify({jinja: {chat_template: template, context: {enable_thinking: true}}})).defaultEnabled, true);
assert.equal(modelThinkingSupport('{}','{"jinja":{"chat_template":"enable_thinking in documentation"}}').supported,false);
// Hunyuan and SmolLM3 use these forms in their published MNN templates.
const hunyuan = "{% if enable_thinking is defined and not enable_thinking %}</think>{% endif %}";
assert.equal(modelThinkingSupport('{}', JSON.stringify({jinja: {chat_template: hunyuan}})).supported, true);
const smol = "{%- if enable_thinking is not defined -%}\n{%- set enable_thinking = true -%}\n{%- endif -%}\n{%- if enable_thinking -%}<think>{%- endif -%}";
assert.equal(modelThinkingSupport('{}', JSON.stringify({jinja: {chat_template: smol}})).supported, true);
assert.equal(modelThinkingSupport('{}', JSON.stringify({jinja: {chat_template: smol}})).defaultEnabled, true);
const defaultOff = smol.replace('= true', '= false');
assert.equal(modelThinkingSupport('{}', JSON.stringify({jinja: {chat_template: defaultOff}})).defaultEnabled, false);
assert.equal(modelThinkingSupport('{"jinja":{"context":{"enable_thinking":false}}}', JSON.stringify({jinja: {chat_template: smol}})).defaultEnabled, false);
assert.equal(modelThinkingSupport('{"use_template":false}', JSON.stringify({jinja: {chat_template: smol}})).supported, false);
assert.equal(modelThinkingSupport('{}', JSON.stringify({jinja: {chat_template: '{% set enable_thinking = true %}{% if enable_thinking %}text{% endif %}'}})).supported, false);
assert.equal(modelThinkingSupport('{}', JSON.stringify({jinja: {chat_template: smol.split('{%- if enable_thinking -%}')[0] + 'fixed output'}})).supported, false,
  'a default assignment without a generation branch must not expose a switch');
assert.throws(() => modelThinkingSupport('{}','bad json'));
console.log('PASS thinking controls follow actual template branches and model defaults, not catalog tags');
const source = fs.readFileSync(path.join(root,'state/ChatViewModel.ets'),'utf8');
const ast = ts.createSourceFile('view.ts',source,ts.ScriptTarget.Latest,true);
const declaration = ast.statements.find(node => ts.isClassDeclaration(node) && node.name.text==='ChatViewModel');
const names=['loadThinkingSettings','refreshThinkingMode','setThinkingEnabled','resetThinkingMode','saveThinkingSettings','currentGenerationSettings'];
const members=declaration.members.filter(node=>node.name && (names.includes(node.name.getText(ast)) || node.name.getText(ast).startsWith('thinking')));
let read = async name => name.endsWith('llm_config.json') ? llm : '{}';
const store = new Map();
const Subject = vm.runInNewContext(compile(`class Subject { ${members.map(node=>node.getText(ast)).join('\n')} }`)+'\nSubject', {
  fs:{readText:name=>read(name)},modelThinkingSupport,
  preferences:{getPreferences:async()=>({get:async(key,fallback)=>store.get(key)??fallback,put:async(key,value)=>store.set(key,value),flush:async()=>{}})}
});
const flush=async()=>{for(let i=0;i<20;i++) await Promise.resolve();};
(async()=>{
  const view=new Subject();Object.assign(view,{context:{},selectedModelId:'model-a',modelPath:'/a/config.json',notify:()=>{},toastCallback:message=>{throw Error(message);}});
  await view.loadThinkingSettings();await flush();assert.equal(view.thinkingSupported,true);assert.equal(view.thinkingEnabled,true);
  assert.equal(view.currentGenerationSettings().thinkingEnabled,undefined,'untouched settings preserve the native model default');
  view.setThinkingEnabled(false);await flush();assert.equal(view.currentGenerationSettings().thinkingEnabled,false);
  assert.equal(JSON.parse(store.get('models'))['model-a'],false);
  view.selectedModelId='model-b';view.modelPath='/b/config.json';view.refreshThinkingMode();await flush();
  assert.equal(view.thinkingEnabled,true);assert.equal(view.currentGenerationSettings().thinkingEnabled,undefined);
  view.setThinkingEnabled(true);await flush();view.selectedModelId='model-a';view.modelPath='/a/config.json';view.refreshThinkingMode();await flush();assert.equal(view.thinkingEnabled,false);
  const reloaded=new Subject();Object.assign(reloaded,{context:{},selectedModelId:'model-a',modelPath:'/a/config.json',notify:()=>{}});
  reloaded.loadThinkingSettings();await flush();assert.equal(reloaded.thinkingEnabled,false);
  reloaded.resetThinkingMode();await flush();assert.equal(reloaded.thinkingEnabled,true);assert.equal(reloaded.currentGenerationSettings().thinkingEnabled,undefined);assert(!Object.hasOwn(JSON.parse(store.get('models')),'model-a'));
  view.busy=true;view.setThinkingEnabled(true);assert.equal(view.thinkingEnabled,false);view.busy=false;
  console.log('PASS per-model persistence, restart, restore defaults, busy guard and request settings');
  const waits=new Map();read=name=>new Promise(resolve=>waits.set(name,resolve));
  view.modelPath='/slow/config.json';view.refreshThinkingMode();view.modelPath='/new/config.json';view.refreshThinkingMode();
  waits.get('/new/config.json')('{}');waits.get('/new/llm_config.json')(llm);await flush();assert.equal(view.thinkingSupported,true);
  waits.get('/slow/config.json')('{}');waits.get('/slow/llm_config.json')('{}');await flush();assert.equal(view.thinkingSupported,true,'stale reads cannot hide the current switch');
  read=async()=>{throw Error('missing config');};view.refreshThinkingMode();await flush();assert.equal(view.thinkingSupported,false);assert.equal(view.currentGenerationSettings().thinkingEnabled,undefined);
  console.log('PASS model/path changes reject stale reads and missing templates hide the control');
  const received=[];
  const native={generateChatStream:async(_turns,_limit,settings,_chunk,title)=>{received.push({settings,title});return {};},generateImageChatStream:async(_turns,_pixels,_w,_h,_limit,settings)=>{received.push({settings});return {};}};
  const {NativeInferenceService}=moduleFrom('services/NativeInferenceService.ets',id=>{assert.equal(id,'libentry.so');return {default:native};});
  const bridge=new NativeInferenceService();await bridge.generateText([],128,{thinkingEnabled:false},()=>{});await bridge.generateImage([],{pixels:new ArrayBuffer(3),width:1,height:1},128,{thinkingEnabled:true},()=>{});await bridge.generateTitle([]);
  assert.equal(received[0].settings.thinkingEnabled,false);assert.equal(received[1].settings.thinkingEnabled,true);assert.equal(received[2].title,true);
  assert.equal(received[2].settings.thinkingEnabled,undefined,'native title scope independently disables thinking');
  console.log('PASS native bridge forwards text and image choices without changing title requests');
})().catch(error=>{console.error(error);process.exitCode=1;});
