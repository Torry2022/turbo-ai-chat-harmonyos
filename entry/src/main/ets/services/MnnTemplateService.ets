import fs from '@ohos.file.fs'

interface MnnLlmConfig {
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

const CHATML_JINJA_TEMPLATE: string = `{%- for message in messages %}
{{- '<|im_start|>' + message.role + '\\n' + message.content + '<|im_end|>\\n' }}
{%- endfor %}
{%- if add_generation_prompt %}
{{- '<|im_start|>assistant\\n' }}
{%- endif %}`

export class MnnTemplateService {
  static async ensureChatMessagesTemplate(configPath: string): Promise<void> {
    const llmConfigPath = MnnTemplateService.llmConfigPath(configPath)
    if (llmConfigPath.length <= 0 || !await MnnTemplateService.exists(llmConfigPath)) {
      throw new Error('该 MNN 模型目录缺少 llm_config.json，无法确认对话模板。')
    }
    const text = await fs.readText(llmConfigPath)
    const llmConfig = JSON.parse(text.replace(/^\uFEFF/, '')) as MnnLlmConfig
    const existingJinjaTemplate = llmConfig.jinja?.chat_template ?? ''
    if (existingJinjaTemplate.trim().length > 0) {
      return
    }
    const promptTemplate = llmConfig.prompt_template ?? ''
    if (!MnnTemplateService.isLegacyChatMlPromptTemplate(promptTemplate)) {
      throw new Error('该 MNN 模型目录缺少 jinja.chat_template，且不是可自动兼容的 ChatML 旧模板。请使用新版 MNN 导出模型或补全 llm_config.json。')
    }

    llmConfig.system_prompt_template = MnnTemplateService.valueOrDefault(
      llmConfig.system_prompt_template,
      '<|im_start|>system\n%s<|im_end|>\n'
    )
    llmConfig.user_prompt_template = MnnTemplateService.valueOrDefault(
      llmConfig.user_prompt_template,
      '<|im_start|>user\n%s<|im_end|>\n'
    )
    llmConfig.assistant_prompt_template = MnnTemplateService.valueOrDefault(
      llmConfig.assistant_prompt_template,
      '<|im_start|>assistant\n%s<|im_end|>\n'
    )
    const existingEos = llmConfig.jinja?.eos ?? ''
    llmConfig.jinja = {
      chat_template: CHATML_JINJA_TEMPLATE,
      eos: existingEos.length > 0 ? existingEos : '<|im_end|>'
    }
    MnnTemplateService.writeText(llmConfigPath, JSON.stringify(llmConfig, undefined, 2))
  }

  static async isCompatibleChatMessagesTemplate(configPath: string): Promise<boolean> {
    try {
      await MnnTemplateService.ensureChatMessagesTemplate(configPath)
      return true
    } catch (_) {
      return false
    }
  }

  private static llmConfigPath(configPath: string): string {
    const lowerPath = configPath.toLowerCase()
    if (!lowerPath.endsWith('/config.json')) {
      return ''
    }
    return `${configPath.substring(0, configPath.length - '/config.json'.length)}/llm_config.json`
  }

  private static isLegacyChatMlPromptTemplate(promptTemplate: string): boolean {
    return promptTemplate.indexOf('%s') >= 0 &&
      promptTemplate.indexOf('<|im_start|>user') >= 0 &&
      promptTemplate.indexOf('<|im_start|>assistant') >= 0 &&
      promptTemplate.indexOf('<|im_end|>') >= 0
  }

  private static valueOrDefault(value: string | undefined, defaultValue: string): string {
    if (value !== undefined && value.length > 0) {
      return value
    }
    return defaultValue
  }

  private static writeText(path: string, text: string): void {
    const file = fs.openSync(path, fs.OpenMode.WRITE_ONLY | fs.OpenMode.CREATE | fs.OpenMode.TRUNC)
    try {
      fs.writeSync(file.fd, text)
    } finally {
      fs.closeSync(file)
    }
  }

  private static async exists(path: string): Promise<boolean> {
    try {
      return await fs.access(path)
    } catch (_) {
      return false
    }
  }
}
