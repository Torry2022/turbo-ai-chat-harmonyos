export interface ChatMessage {
  id: number
  role: string
  content: string
  imageUri: string
  time: string
  includeInContext: boolean
  thinkingExpanded: boolean
  perfMetrics?: PerfMetrics
}

export interface PerfMetrics {
  ttft: number
  tpot: number
  tokensPerSec: number
  tokens: number
}

export interface ChatTurn {
  role: string
  content: string
}

export interface ImagePayload {
  pixels: ArrayBuffer
  width: number
  height: number
}

export type GenerationStopReason = 'eos' | 'max_tokens' | 'user_stop' | 'timeout' | 'internal_error' | 'unknown'

export interface GenerationResult {
  text: string
  generatedTokens: number
  stopReason: GenerationStopReason
}

export interface GenerationSettings {
  temperature: number
  topP: number
  topK: number
  repetitionPenalty: number
  frequencyPenalty: number
  presencePenalty: number
  penaltyWindow: number
}

export const CONTEXT_MESSAGE_LIMIT: number = 6
export const VISION_MAX_PIXELS: number = 640000
