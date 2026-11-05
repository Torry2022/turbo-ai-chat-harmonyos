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
  const template = llm.jinja?.chat_template ?? config.jinja?.chat_template ?? ''
  const explicit = llm.jinja?.context?.enable_thinking ?? config.jinja?.context?.enable_thinking
  // Qwen/MiniCPM/Hunyuan templates leave thinking enabled when the optional flag is absent.
  const optionalFlag = typeof template === 'string' && /enable_thinking\s+is\s+defined/.test(template) &&
    /(?:enable_thinking\s+is\s+false|\bnot\s+enable_thinking\b)/.test(template) && template.includes('</think>')
  const templateDefault = typeof template === 'string' ? template.match(
    /{%-?\s*if\s+enable_thinking\s+is\s+not\s+defined\s*-?%}\s*{%-?\s*set\s+enable_thinking\s*=\s*(true|false)\s*-?%}\s*{%-?\s*endif\s*-?%}/
  ) : null
  const conditional = typeof template === 'string' && /{%-?\s*(?:if|elif)[^%]*\benable_thinking\b/.test(
    templateDefault !== null ? template.replace(templateDefault[0], '') : template
  )
  const supported = config.use_template !== false && conditional &&
    (typeof explicit === 'boolean' || optionalFlag || templateDefault !== null)
  return { supported, defaultEnabled: typeof explicit === 'boolean' ? explicit :
    templateDefault !== null ? templateDefault[1] === 'true' : true }
}
