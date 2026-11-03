interface ThinkingContext {
  enable_thinking?: boolean
}

interface ThinkingJinja {
  chat_template?: string
  context?: ThinkingContext
}

interface ThinkingConfig {
  use_template?: boolean
  jinja?: ThinkingJinja
}

export interface ThinkingSupport {
  supported: boolean
  defaultEnabled: boolean
}

export function modelThinkingSupport(configText: string, llmConfigText: string): ThinkingSupport {
  const config = JSON.parse(configText) as ThinkingConfig
  const llm = JSON.parse(llmConfigText) as ThinkingConfig
  const template = config.jinja?.chat_template ?? llm.jinja?.chat_template ?? ''
  const explicit = config.jinja?.context?.enable_thinking ?? llm.jinja?.context?.enable_thinking
  const conditional = typeof template === 'string' && /{%-?\s*(?:if|elif)[^%]*\benable_thinking\b/.test(template)
  // Qwen/MiniCPM templates leave thinking enabled when the optional flag is absent.
  const optionalFlag = typeof template === 'string' && /enable_thinking\s+is\s+defined/.test(template) &&
    /enable_thinking\s+is\s+false/.test(template) && template.includes('</think>')
  const supported = config.use_template !== false && conditional && (typeof explicit === 'boolean' || optionalFlag)
  return { supported, defaultEnabled: typeof explicit === 'boolean' ? explicit : true }
}
