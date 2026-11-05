export const MODEL_PREFLIGHT_OK: string = 'ok'
export const MODEL_PREFLIGHT_CONFIG_MISSING: string = 'config_missing'
export const MODEL_PREFLIGHT_CONFIG_INVALID: string = 'config_invalid'
export const MODEL_PREFLIGHT_LLM_CONFIG_MISSING: string = 'llm_config_missing'
export const MODEL_PREFLIGHT_LLM_CONFIG_INVALID: string = 'llm_config_invalid'
export const MODEL_PREFLIGHT_TEMPLATE_INCOMPATIBLE: string = 'template_incompatible'
export const MODEL_PREFLIGHT_FILE_MISSING: string = 'file_missing'
export const MODEL_PREFLIGHT_FILE_SIZE_MISMATCH: string = 'file_size_mismatch'
export const MODEL_PREFLIGHT_CONFIG_REFERENCE_MISSING: string = 'config_reference_missing'
export const MODEL_PREFLIGHT_VISUAL_FILES_MISSING: string = 'visual_files_missing'

export interface ModelFileSnapshot {
  relativePath: string
  sizeBytes: number
}

export interface ExpectedModelFile {
  relativePath: string
  sizeBytes: number
}

export interface ModelDirectorySnapshot {
  requireChatTemplate?: boolean
  configText: string
  llmConfigText: string
  files: ModelFileSnapshot[]
  expectedFiles: ExpectedModelFile[]
  supportsImage: boolean
}

export interface ModelPreflightResult {
  compatible: boolean
  code: string
  message: string
  legacyTemplate: boolean
}

interface MnnConfig extends MnnChatTemplateConfig {
  llm_model?: string
  llm_weight?: string
  visual_model?: string
  visual_weight?: string
  audio_model?: string
  audio_weight?: string
  embedding_file?: string
  embeddings?: string
  tokenizer_file?: string
}

interface MnnLlmConfig extends MnnChatTemplateConfig {
  is_visual?: boolean
  tie_embeddings?: number[]
}

export interface MnnChatTemplateConfig {
  bos?: string
  prompt_template?: string
  system_prompt_template?: string
  user_prompt_template?: string
  assistant_prompt_template?: string
  jinja?: MnnJinjaConfig
}

interface MnnJinjaConfig {
  chat_template?: string
  eos?: string
}

export function inferSupportsImageFromLlmConfig(llmConfigText: string): boolean {
  try {
    const config = JSON.parse(stripBom(llmConfigText)) as MnnLlmConfig
    return config.is_visual === true
  } catch (_) {
    return false
  }
}

export function validateModelDirectorySnapshot(snapshot: ModelDirectorySnapshot): ModelPreflightResult {
  if (!hasFile(snapshot.files, 'config.json')) {
    return failure(MODEL_PREFLIGHT_CONFIG_MISSING, '模型目录缺少 config.json。')
  }
  if (!hasFile(snapshot.files, 'llm_config.json')) {
    return failure(MODEL_PREFLIGHT_LLM_CONFIG_MISSING, '模型目录缺少 llm_config.json。')
  }

  let config: MnnConfig
  try {
    config = JSON.parse(stripBom(snapshot.configText)) as MnnConfig
  } catch (_) {
    return failure(MODEL_PREFLIGHT_CONFIG_INVALID, 'config.json 不是有效的 JSON。')
  }
  let llmConfig: MnnLlmConfig
  try {
    llmConfig = JSON.parse(stripBom(snapshot.llmConfigText)) as MnnLlmConfig
  } catch (_) {
    return failure(MODEL_PREFLIGHT_LLM_CONFIG_INVALID, 'llm_config.json 不是有效的 JSON。')
  }

  const template = resolveMnnChatTemplate(config, llmConfig)
  const legacyTemplate = template.trim().length <= 0 && isLegacyChatMlConfig(config, llmConfig)
  if (snapshot.requireChatTemplate !== false && template.trim().length <= 0 && !legacyTemplate) {
    return failure(
      MODEL_PREFLIGHT_TEMPLATE_INCOMPATIBLE,
      '模型包未提供本应用可用的对话模板，请使用含 jinja.chat_template 的模型包或完整的 ChatML 角色模板。'
    )
  }

  if ((config.llm_model ?? '').trim().length <= 0) {
    return failure(MODEL_PREFLIGHT_CONFIG_INVALID, 'config.json 缺少 llm_model 配置。')
  }

  if (!hasPositiveFileWithSuffix(snapshot.files, '.mnn')) {
    return failure(MODEL_PREFLIGHT_FILE_MISSING, '模型目录缺少有效的 .mnn 模型文件。')
  }
  if (!hasTokenizer(snapshot.files)) {
    return failure(MODEL_PREFLIGHT_FILE_MISSING, '模型目录缺少有效的 tokenizer 文件。')
  }

  const referencedFiles = configFileReferences(config, hasTiedEmbeddings(llmConfig))
  for (let index = 0; index < referencedFiles.length; index++) {
    if (!hasPositiveFile(snapshot.files, referencedFiles[index])) {
      return failure(
        MODEL_PREFLIGHT_CONFIG_REFERENCE_MISSING,
        `config.json 引用的文件不存在或为空：${referencedFiles[index]}`
      )
    }
  }

  if (snapshot.supportsImage && !hasVisualModelFiles(snapshot.files)) {
    return failure(MODEL_PREFLIGHT_VISUAL_FILES_MISSING, '多模态模型目录缺少有效的 visual.mnn 或视觉权重文件。')
  }

  for (let index = 0; index < snapshot.expectedFiles.length; index++) {
    const expected = snapshot.expectedFiles[index]
    const actual = findFile(snapshot.files, expected.relativePath)
    if (actual === undefined) {
      return failure(MODEL_PREFLIGHT_FILE_MISSING, `模型目录缺少文件：${expected.relativePath}`)
    }
    if (expected.sizeBytes > 0 && actual.sizeBytes !== expected.sizeBytes) {
      return failure(
        MODEL_PREFLIGHT_FILE_SIZE_MISMATCH,
        `模型文件大小不匹配：${expected.relativePath}`
      )
    }
  }

  return {
    compatible: true,
    code: MODEL_PREFLIGHT_OK,
    message: legacyTemplate ? '模型目录兼容，将自动补全 ChatML 对话模板。' : '模型目录预检通过。',
    legacyTemplate
  }
}

export function isLegacyChatMlPromptTemplate(promptTemplate: string): boolean {
  return promptTemplate.indexOf('%s') >= 0 &&
    promptTemplate.indexOf('<|im_start|>user') >= 0 &&
    promptTemplate.indexOf('<|im_start|>assistant') >= 0 &&
    promptTemplate.indexOf('<|im_end|>') >= 0
}

export function resolveMnnChatTemplate(config: MnnChatTemplateConfig, llmConfig: MnnChatTemplateConfig): string {
  // MNN merges llm_config.json into config.json; fields in llm_config.json take precedence.
  return llmConfig.jinja?.chat_template ?? config.jinja?.chat_template ?? ''
}

export function isLegacyChatMlConfig(config: MnnChatTemplateConfig, llmConfig: MnnChatTemplateConfig): boolean {
  const system = llmConfig.system_prompt_template ?? config.system_prompt_template
  const user = llmConfig.user_prompt_template ?? config.user_prompt_template
  const assistant = llmConfig.assistant_prompt_template ?? config.assistant_prompt_template
  const systemMatches = system === '<|im_start|>system\n%s<|im_end|>\n'
  const userMatches = user === '<|im_start|>user\n%s<|im_end|>\n'
  const assistantMatches = assistant === '<|im_start|>assistant\n%s<|im_end|>\n'
  if ((system !== undefined && !systemMatches) || (user !== undefined && !userMatches) ||
    (assistant !== undefined && !assistantMatches) || (llmConfig.bos ?? config.bos ?? '').length > 0) {
    return false
  }
  return (systemMatches && userMatches && assistantMatches) ||
    isLegacyChatMlPromptTemplate(llmConfig.prompt_template ?? config.prompt_template ?? '')
}

function configFileReferences(config: MnnConfig, tiedEmbeddings: boolean): string[] {
  const candidates: string[] = [
    config.llm_model ?? '',
    config.llm_weight ?? '',
    config.visual_model ?? '',
    config.visual_weight ?? '',
    config.audio_model ?? '',
    config.audio_weight ?? '',
    tiedEmbeddings ? '' : config.embedding_file ?? '',
    config.embeddings ?? '',
    config.tokenizer_file ?? ''
  ]
  return candidates.filter((value: string) => value.trim().length > 0)
}

function hasTiedEmbeddings(config: MnnLlmConfig): boolean {
  return Array.isArray(config.tie_embeddings) && config.tie_embeddings.length > 0
}

function hasVisualModelFiles(files: ModelFileSnapshot[]): boolean {
  let hasVisualModel = false
  let hasVisualWeight = false
  files.forEach((file: ModelFileSnapshot) => {
    const path = normalizedPath(file.relativePath)
    if (file.sizeBytes <= 0) {
      return
    }
    if (path.endsWith('visual.mnn')) {
      hasVisualModel = true
    }
    if (path.indexOf('visual') >= 0 && (path.endsWith('.weight') || path.endsWith('.bin'))) {
      hasVisualWeight = true
    }
  })
  return hasVisualModel && hasVisualWeight
}

function hasTokenizer(files: ModelFileSnapshot[]): boolean {
  for (let index = 0; index < files.length; index++) {
    const fileName = normalizedPath(files[index].relativePath).split('/').pop() ?? ''
    if (files[index].sizeBytes > 0 && fileName.startsWith('tokenizer.')) {
      return true
    }
  }
  return false
}

function hasPositiveFileWithSuffix(files: ModelFileSnapshot[], suffix: string): boolean {
  for (let index = 0; index < files.length; index++) {
    if (files[index].sizeBytes > 0 && normalizedPath(files[index].relativePath).endsWith(suffix)) {
      return true
    }
  }
  return false
}

function hasPositiveFile(files: ModelFileSnapshot[], relativePath: string): boolean {
  const file = findFile(files, relativePath)
  return file !== undefined && file.sizeBytes > 0
}

function hasFile(files: ModelFileSnapshot[], relativePath: string): boolean {
  return findFile(files, relativePath) !== undefined
}

function findFile(files: ModelFileSnapshot[], relativePath: string): ModelFileSnapshot | undefined {
  const expected = normalizedPath(relativePath)
  for (let index = 0; index < files.length; index++) {
    if (normalizedPath(files[index].relativePath) === expected) {
      return files[index]
    }
  }
  return undefined
}

function normalizedPath(path: string): string {
  return path.replace(/\\/g, '/').replace(/^\.\//, '').toLowerCase()
}

function stripBom(text: string): string {
  return text.replace(/^\uFEFF/, '')
}

function failure(code: string, message: string): ModelPreflightResult {
  return {
    compatible: false,
    code,
    message,
    legacyTemplate: false
  }
}
