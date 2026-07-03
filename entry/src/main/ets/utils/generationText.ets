import { GenerationResult, PerfMetrics } from '../models/ChatTypes'
import { isLikelyIncompleteAssistantText, stripModelSpecialTokens, trimLikelyIncompleteTrailingFragment } from './thinking'

export function sanitizeAssistantText(text: string, stripLeadingSeparator: boolean = false): string {
  const normalizedText = stripModelSpecialTokens(text)
  const lines = normalizedText
    .split('\n')
    .map((line: string) => line.trimEnd())
    .filter((line: string) => {
      const trimmed = line.trim()
      return trimmed.length > 0 && !/^[*\-•]+\s*$/.test(trimmed)
    })
  const cleanedText = lines.join('\n').trim()
  return stripLeadingSeparator ? stripLeadingAssistantSeparator(cleanedText) : cleanedText
}

export function sanitizeStreamingAssistantText(text: string, stripLeadingSeparator: boolean = false): string {
  return sanitizeAssistantText(text, stripLeadingSeparator).replace(/^\uFFFD+/, '').trimStart()
}

export function applyAssistantOutputPrefix(text: string, prefix: string): string {
  if (prefix.length <= 0 || text.length <= 0) {
    return text
  }
  const trimmedStart = text.trimStart()
  if (trimmedStart.startsWith('<think>') || '<think>'.startsWith(trimmedStart)) {
    return text
  }
  return `${prefix}${text}`
}

export function finalAssistantAnswer(
  result: GenerationResult,
  assistantOutputPrefix: string = '',
  stripLeadingSeparator: boolean = false
): string {
  const cleanedText = trimLikelyIncompleteTrailingFragment(sanitizeAssistantText(
    applyAssistantOutputPrefix(result.text, assistantOutputPrefix),
    stripLeadingSeparator
  ))
  if (cleanedText.length > 0) {
    return cleanedText
  }
  return result.stopReason === 'user_stop' ? '（已停止生成）' : '（原生层返回空内容）'
}

export function shouldIncludeAssistantInContext(answer: string, result: GenerationResult): boolean {
  if (answer.trim().length <= 0) {
    return false
  }
  if (result.stopReason === 'eos') {
    return true
  }
  if (result.stopReason === 'max_tokens' ||
    result.stopReason === 'user_stop' ||
    result.stopReason === 'timeout' ||
    result.stopReason === 'internal_error') {
    return false
  }
  return !isLikelyIncompleteAssistantText(answer)
}

export function formatGenerationStatus(
  answer: string,
  includeInContext: boolean,
  result: GenerationResult
): string {
  const tokenText = result.generatedTokens > 0 ? `，${result.generatedTokens} tokens` : ''
  if (result.stopReason === 'max_tokens') {
    return `生成完成（${answer.length} 字符${tokenText}，达到最大输出）`
  }
  if (result.stopReason === 'user_stop') {
    return `已停止生成（${answer.length} 字符${tokenText}）`
  }
  if (result.stopReason === 'timeout') {
    return `生成超时（${answer.length} 字符${tokenText}，回答可能不完整）`
  }
  if (result.stopReason === 'internal_error') {
    return `生成异常（${answer.length} 字符${tokenText}，回答可能不完整）`
  }
  if (!includeInContext) {
    return `生成完成（${answer.length} 字符${tokenText}，可能被截断）`
  }
  return `生成完成（${answer.length} 字符${tokenText}）`
}

export function calculatePerfMetrics(
  generationStartedAt: number,
  firstChunkAt: number,
  generationFinishedAt: number,
  generatedTokens: number
): PerfMetrics {
  const generationTime = Math.max(1, generationFinishedAt - generationStartedAt)
  const safeGeneratedTokens = Math.max(1, generatedTokens)
  return {
    ttft: firstChunkAt > 0 ? firstChunkAt - generationStartedAt : 0,
    tpot: Math.round(generationTime / safeGeneratedTokens * 100) / 100,
    tokensPerSec: Math.round(safeGeneratedTokens / (generationTime / 1000) * 10) / 10,
    tokens: Math.max(0, generatedTokens)
  }
}

function stripLeadingAssistantSeparator(text: string): string {
  return text.replace(/^(assistant|助手)?\s*[:：]\s*/, '').trim()
}
