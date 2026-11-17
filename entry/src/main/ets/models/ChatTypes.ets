export interface ChatMessage {
  id: number
  role: string
  content: string
  imageUri: string
  time: string
  includeInContext: boolean
  thinkingExpanded: boolean
  createdAt?: number
  completedAt?: number
  modelId?: string
  modelName?: string
  kind?: 'message' | 'notice'
  generationState?: 'generating' | 'complete' | 'interrupted' | 'stopped' | 'failed'
  stopReason?: GenerationStopReason
  imageUnavailable?: boolean
  perfMetrics?: PerfMetrics
  answerVersions?: ChatAnswerVersion[]
  answerVersionIndex?: number
}

// A reply version keeps its own text, model, timestamps and generation outcome.
export interface ChatAnswerVersion {
  content: string
  time: string
  createdAt?: number
  completedAt?: number
  modelId?: string
  modelName?: string
  generationState?: 'generating' | 'complete' | 'interrupted' | 'stopped' | 'failed'
  stopReason?: GenerationStopReason
  includeInContext: boolean
  thinkingExpanded: boolean
  perfMetrics?: PerfMetrics
}

export interface PerfMetrics {
  ttft: number
  tpot: number
  tokensPerSec: number
  tokens: number
  tokensEstimated?: boolean
  inputTokens?: number
  reusedInputTokens?: number
  nativeTiming?: NativeGenerationTiming
  configuration?: GenerationConfiguration
}

// Configuration captured before asynchronous input preparation; no prompt or cache identity.
export interface GenerationEnvironment {
  appVersion: string
  appVersionCode: number
  deviceModel: string
  osVersion: string
}

export interface GenerationConfiguration {
  environment?: GenerationEnvironment
  maxNewTokens: number
  settings: GenerationSettings
  model?: GenerationModelIdentity
  startedAt?: number
  finishedAt?: number
}

export interface GenerationModelIdentity {
  sourceRepository?: string
  sourceRevision?: string
  runtimeLibrarySha256?: string
  configurationSha256?: string
  fileManifestSha256?: string
  id: string
  name: string
  requestedThreads: number
  actualThreads: number
}

export interface NativeGenerationTiming {
  prefillMs: number
  decodeMs: number
  visionMs: number
}

export interface ChatTurn {
  role: string
  content: string
  imageUri?: string
}

export interface ChatContextOmission {
  messageId: number
  role: string
  content: string
  reason: string
}

export interface ChatContextSelection {
  turns: ChatTurn[]
  omitted: ChatContextOmission[]
  historyMessageIds: number[]
}

export interface ChatContextSnapshot extends ChatContextSelection {
  conversationId: string
  modelName: string
  requestedOutputTokens: number
  inputTokens?: number
  imageInput: boolean
  contextTokens: number
  formattedPrompt: string
  questionText?: string
}

export interface PreparedChatInput {
  prompt: string
  inputTokens: number
  modelConfig: string
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
  inputTokens?: number
  reusedInputTokens?: number
  generatedTokensEstimated?: boolean
  nativeTiming?: NativeGenerationTiming
  stopReason: GenerationStopReason
}

export interface GenerationSettings {
  kvCacheScope?: string
  thinkingEnabled?: boolean
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
