import { GenerationResult, PerfMetrics } from '../models/ChatTypes'
import { answerTextForContext, isLikelyIncompleteAssistantText } from './thinking'

export function sanitizeAssistantText(text: string, stripLeadingSeparator: boolean = false): string {
  return stripLeadingSeparator ? stripLeadingAssistantSeparator(text) : text
}

export function sanitizeStreamingAssistantText(text: string, stripLeadingSeparator: boolean = false): string {
  return sanitizeAssistantText(text, stripLeadingSeparator)
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
  return sanitizeAssistantText(
    applyAssistantOutputPrefix(result.text, assistantOutputPrefix),
    stripLeadingSeparator
  )
}

export function shouldIncludeAssistantInContext(answer: string, result: GenerationResult): boolean {
  if (result.text.trim().length <= 0 || answerTextForContext(answer).trim().length <= 0) {
    return false
  }
  if (result.stopReason === 'internal_error') return false
  return result.stopReason === 'eos' || result.stopReason === 'max_tokens' ||
    result.stopReason === 'user_stop' || result.stopReason === 'timeout' || !isLikelyIncompleteAssistantText(answer)
}

export function formatGenerationStatus(
  answer: string,
  includeInContext: boolean,
  result: GenerationResult
): string {
  const tokenText = result.generatedTokens > 0 ?
    `，${result.generatedTokensEstimated ? '约 ' : ''}${result.generatedTokens} tokens` : ''
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
  generatedTokens: number,
  tokensEstimated: boolean = false
): PerfMetrics {
  const safeTokens = Math.max(0, generatedTokens)
  const decodedTokenIntervals = Math.max(0, safeTokens - 1)
  const decodeDuration = firstChunkAt > 0 ? Math.max(0, generationFinishedAt - firstChunkAt) : 0
  return {
    ttft: firstChunkAt > 0 ? Math.max(0, firstChunkAt - generationStartedAt) : 0,
    tpot: decodedTokenIntervals > 0 ? Math.round(decodeDuration / decodedTokenIntervals * 100) / 100 : 0,
    tokensPerSec: decodedTokenIntervals > 0 && decodeDuration > 0 ?
      Math.round(decodedTokenIntervals / (decodeDuration / 1000) * 10) / 10 : 0,
    tokens: safeTokens,
    tokensEstimated
  }
}

export function formatPerfMetrics(metrics: PerfMetrics): string {
  const approximate = metrics.tokensEstimated ? '约 ' : ''
  return `TTFT ${metrics.ttft}ms · ${approximate}${metrics.tpot}ms/tok · ` +
    `${approximate}${metrics.tokensPerSec} tok/s · ${approximate}${metrics.tokens} tokens`
}

function stripLeadingAssistantSeparator(text: string): string {
  return text.replace(/^(assistant|助手)?\s*[:：]\s*/, '').trim()
}
