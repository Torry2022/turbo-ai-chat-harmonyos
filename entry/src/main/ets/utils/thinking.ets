export interface AssistantTextParts {
  hasThinking: boolean
  thinking: string
  answer: string
  thinkingClosed: boolean
}

const ASSISTANT_TEXT_CACHE_LIMIT: number = 240
const assistantTextCache: Map<string, AssistantTextParts> = new Map()

function rememberAssistantText(content: string, parts: AssistantTextParts): AssistantTextParts {
  if (assistantTextCache.size >= ASSISTANT_TEXT_CACHE_LIMIT) {
    const oldest = assistantTextCache.keys().next()
    if (!oldest.done) assistantTextCache.delete(oldest.value)
  }
  assistantTextCache.set(content, parts)
  return parts
}

export function parseAssistantText(content: string): AssistantTextParts {
  const cached = assistantTextCache.get(content)
  if (cached !== undefined) {
    return cached
  }
  return rememberAssistantText(content, parseAssistantTextUncached(content))
}

function parseAssistantTextUncached(content: string): AssistantTextParts {
  const normalizedContent = content
  const openTag = '<think>'
  const closeTag = '</think>'
  // A thinking block is a response prefix. Tags in prose and code are literal text.
  const prefixLength = normalizedContent.length - normalizedContent.trimStart().length
  const openIndex = normalizedContent.startsWith(openTag, prefixLength) ? prefixLength : -1
  if (openIndex < 0) {
    return {
      hasThinking: false,
      thinking: '',
      answer: normalizedContent,
      thinkingClosed: false
    }
  }

  const before = normalizedContent.substring(0, openIndex).trim()
  const afterOpen = normalizedContent.substring(openIndex + openTag.length)
  const closeIndex = afterOpen.indexOf(closeTag)
  if (closeIndex < 0) {
    return {
      hasThinking: true,
      thinking: afterOpen.trim(),
      answer: before,
      thinkingClosed: false
    }
  }

  const thinking = afterOpen.substring(0, closeIndex).trim()
  const answer = afterOpen.substring(closeIndex + closeTag.length)
  if (thinking.length <= 0) {
    return {
      hasThinking: false,
      thinking: '',
      answer,
      thinkingClosed: false
    }
  }

  return {
    hasThinking: true,
    thinking,
    answer,
    thinkingClosed: true
  }
}

export function answerTextForContext(content: string): string {
  const parts = parseAssistantText(content)
  if (!parts.hasThinking) {
    return content
  }
  return parts.answer
}

export function isLikelyIncompleteAssistantText(content: string): boolean {
  const parts = parseAssistantText(content)
  if (parts.hasThinking && !parts.thinkingClosed) {
    return true
  }

  const answer = parts.answer.trim()
  if (answer.length === 0) {
    return false
  }
  if (/[。！？!?\.…」』”'")）】》]$/.test(answer)) {
    return false
  }
  if (/[，、；：,;:]$/.test(answer)) {
    return true
  }
  return answer.length >= 12
}
