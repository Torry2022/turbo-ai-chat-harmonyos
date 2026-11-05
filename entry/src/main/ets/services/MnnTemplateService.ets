import fs from '@ohos.file.fs'
import { isLegacyChatMlConfig, MnnChatTemplateConfig, resolveMnnChatTemplate } from '../utils/modelCompatibility'

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
    const llmConfig = JSON.parse(text.replace(/^\uFEFF/, '')) as MnnChatTemplateConfig
    const configText = await fs.readText(configPath)
    const config = JSON.parse(configText.replace(/^\uFEFF/, '')) as MnnChatTemplateConfig
    const existingJinjaTemplate = resolveMnnChatTemplate(config, llmConfig)
    if (existingJinjaTemplate.trim().length > 0) {
      return
    }
    if (!isLegacyChatMlConfig(config, llmConfig)) {
      throw new Error('模型包未提供本应用可用的对话模板，请使用含 jinja.chat_template 的模型包或完整的 ChatML 角色模板。')
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
    const existingEos = llmConfig.jinja?.eos ?? config.jinja?.eos ?? ''
    llmConfig.jinja = llmConfig.jinja ?? {}
    llmConfig.jinja.chat_template = CHATML_JINJA_TEMPLATE
    llmConfig.jinja.eos = existingEos.length > 0 ? existingEos : '<|im_end|>'
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
