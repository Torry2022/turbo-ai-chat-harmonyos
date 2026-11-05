// node scripts/test_mnn_templates.cjs <path/to/typescript.js>
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(process.argv[2] || 'typescript');
const root = path.resolve(__dirname, '../entry/src/main/ets');
const files = new Map();
const writes = [];
const mockFs = {
  OpenMode: { WRITE_ONLY: 1, CREATE: 2, TRUNC: 4 },
  access: async name => files.has(name),
  readText: async name => { assert(files.has(name)); return files.get(name); },
  openSync: name => ({ fd: name }),
  writeSync: (name, text) => { files.set(name, text); writes.push(name); },
  closeSync: () => {}
};
const modules = new Map();
function load(file) {
  if (modules.has(file)) return modules.get(file);
  const module = { exports: {} };
  const code = ts.transpileModule(fs.readFileSync(file, 'utf8'), { compilerOptions: {
    module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020
  }}).outputText;
  vm.runInNewContext(code, { module, exports: module.exports, require: id => {
    if (id === '@ohos.file.fs') return { default: mockFs };
    assert(id.startsWith('.'));
    return load(path.resolve(path.dirname(file), id + '.ets'));
  }});
  modules.set(file, module.exports);
  return module.exports;
}
const { validateModelDirectorySnapshot } = load(path.join(root, 'utils/modelCompatibility.ets'));
const { MnnTemplateService } = load(path.join(root, 'services/MnnTemplateService.ets'));
const config = { llm_model: 'llm.mnn', llm_weight: 'llm.mnn.weight' };
const roles = {
  system_prompt_template: '<|im_start|>system\n%s<|im_end|>\n',
  user_prompt_template: '<|im_start|>user\n%s<|im_end|>\n',
  assistant_prompt_template: '<|im_start|>assistant\n%s<|im_end|>\n'
};
const legacyPrompt = '<|im_start|>user\n%s<|im_end|>\n<|im_start|>assistant\n';
function reset(llm, base = config) {
  files.clear(); writes.length = 0;
  files.set('/model/config.json', JSON.stringify(base));
  files.set('/model/llm_config.json', JSON.stringify(llm));
}
function preflight(llm, base = config, extra = {}) {
  return validateModelDirectorySnapshot({
    configText: JSON.stringify(base), llmConfigText: JSON.stringify(llm),
    files: ['config.json', 'llm_config.json', 'llm.mnn', 'llm.mnn.weight', 'tokenizer.txt'].map(
      relativePath => ({ relativePath, sizeBytes: 100 })),
    expectedFiles: [], supportsImage: false, ...extra
  });
}
async function main() {
  assert.equal(preflight(roles).compatible, true);
  assert.equal(preflight(roles).legacyTemplate, true);
  reset({ ...roles, hidden_size: 4096, jinja: { eos: '<custom-stop>', context: { custom: true } } });
  await MnnTemplateService.ensureChatMessagesTemplate('/model/config.json');
  const converted = JSON.parse(files.get('/model/llm_config.json'));
  assert.equal(converted.hidden_size, 4096);
  assert.equal(converted.jinja.eos, '<custom-stop>');
  assert.equal(converted.jinja.context.custom, true);
  assert.equal(converted.user_prompt_template, roles.user_prompt_template);
  assert.equal(files.get('/model/config.json'), JSON.stringify(config));
  assert.equal(preflight(converted).legacyTemplate, false);
  const firstWrite = files.get('/model/llm_config.json');
  await MnnTemplateService.ensureChatMessagesTemplate('/model/config.json');
  assert.equal(files.get('/model/llm_config.json'), firstWrite);
  assert.equal(writes.length, 1);
  console.log('PASS complete ChatML roles convert once, preserving model settings, EOS and Jinja context');

  for (const llm of [
    { prompt_template: legacyPrompt }, roles, { ...roles, jinja: null },
    { user_prompt_template: roles.user_prompt_template }
  ]) {
    const base = { ...config, ...roles };
    reset(llm, base);
    assert.equal(preflight(llm, base).compatible, true);
    await MnnTemplateService.ensureChatMessagesTemplate('/model/config.json');
    assert.equal(preflight(JSON.parse(files.get('/model/llm_config.json')), base).compatible, true);
  }
  console.log('PASS combined prompt and split config/llm_config role templates share the same compatibility rules');

  for (const llm of [{}, { jinja: { chat_template: 'llm-template' } }]) {
    const base = { ...config, jinja: { chat_template: 'config-template' } };
    reset(llm, base);
    assert.equal(preflight(llm, base).compatible, true);
    assert.equal(preflight(llm, base).legacyTemplate, false);
    await MnnTemplateService.ensureChatMessagesTemplate('/model/config.json');
    assert.equal(writes.length, 0, 'native Jinja templates must never be replaced');
  }
  const { resolveMnnChatTemplate } = load(path.join(root, 'utils/modelCompatibility.ets'));
  assert.equal(resolveMnnChatTemplate({ jinja: { chat_template: 'base' } },
    { jinja: { chat_template: 'model' } }), 'model');
  assert.equal(preflight({ jinja: { chat_template: '' } },
    { ...config, jinja: { chat_template: 'base' } }).compatible, false);
  console.log('PASS Jinja in config.json is accepted and llm_config.json overrides it as in MNN');

  for (const llm of [
    {}, { prompt_template: '%s' }, { prompt_template: '[INST]%s[/INST]' },
    { ...roles, assistant_prompt_template: undefined },
    { ...roles, user_prompt_template: 'User: %s' },
    { ...roles, bos: '<special-bos>' },
    { prompt_template: legacyPrompt, system_prompt_template: 'Custom: %s' }
  ]) {
    reset(llm);
    assert.equal(preflight(llm).compatible, false);
    await assert.rejects(MnnTemplateService.ensureChatMessagesTemplate('/model/config.json'), /对话模板/);
    assert.equal(writes.length, 0);
  }
  assert.equal(preflight({}, config, { requireChatTemplate: false }).compatible, true);
  assert.equal(preflight(roles, config, { files: [
    { relativePath: 'config.json', sizeBytes: 100 }, { relativePath: 'llm_config.json', sizeBytes: 100 }
  ] }).compatible, false, 'a recognized template cannot bypass missing weights');
  console.log('PASS incomplete/custom templates remain unchanged, rerankers bypass only chat checks, weights stay required');
}
main().catch(error => { console.error(error); process.exitCode = 1; });
