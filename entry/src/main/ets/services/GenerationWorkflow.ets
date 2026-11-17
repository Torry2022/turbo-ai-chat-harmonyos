import { captureGenerationConfiguration } from '../utils/generationSnapshot'
import {
  ChatTurn,
  GenerationModelIdentity,
  GenerationEnvironment,
  GenerationResult,
  GenerationSettings,
  ImagePayload,
  PerfMetrics
} from '../models/ChatTypes'
import {
  applyAssistantOutputPrefix,
  calculatePerfMetrics,
  finalAssistantAnswer,
  formatGenerationStatus,
  sanitizeStreamingAssistantText,
  shouldIncludeAssistantInContext
} from '../utils/generationText'
import { ImagePayloadService } from './ImagePayloadService'
import { NativeInferenceService, ChatRequestExecution } from './NativeInferenceService'

export interface GenerationWorkflowRequest {
  execution?: ChatRequestExecution
  environment?: GenerationEnvironment
  modelIdentity?: GenerationModelIdentity
  turns: ChatTurn[]
  imageUri: string
  imagePayload?: ImagePayload
  maxNewTokens: number
  settings: GenerationSettings
  assistantOutputPrefix: string
  stripLeadingAssistantSeparator: boolean
  preparedPrompt?: string
  requestedAt?: number
}

export interface GenerationStreamUpdate {
  text: string
  characterCount: number
}

export interface GenerationWorkflowCallbacks {
  onStatus: (status: string) => void
  onStream: (update: GenerationStreamUpdate) => void
  isStopRequested: () => boolean
}

export interface GenerationWorkflowResult {
  answer: string
  includeInContext: boolean
  perfMetrics: PerfMetrics
  result: GenerationResult
  status: string
}

export class GenerationWorkflow {
  private nativeService: NativeInferenceService
  private imageService: ImagePayloadService

  constructor(nativeService: NativeInferenceService, imageService: ImagePayloadService) {
    this.nativeService = nativeService
    this.imageService = imageService
  }

  async run(
    request: GenerationWorkflowRequest,
    callbacks: GenerationWorkflowCallbacks
  ): Promise<GenerationWorkflowResult> {
    const settings: GenerationSettings = {
      temperature: request.settings.temperature, topP: request.settings.topP, topK: request.settings.topK,
      repetitionPenalty: request.settings.repetitionPenalty, frequencyPenalty: request.settings.frequencyPenalty,
      presencePenalty: request.settings.presencePenalty, penaltyWindow: request.settings.penaltyWindow,
      thinkingEnabled: request.settings.thinkingEnabled, kvCacheScope: request.settings.kvCacheScope
    }
    const maxNewTokens = request.maxNewTokens
    const configuration = captureGenerationConfiguration(maxNewTokens, settings, request.modelIdentity,
      request.environment, request.requestedAt ?? Date.now())
    const generationStartedAt = configuration.startedAt ?? Date.now()
    let firstChunkAt = 0
    let streamedText = ''
    let streamFinished = false
    const onChunk = (chunk: string): void => {
      if (streamFinished) {
        return
      }
      if (firstChunkAt <= 0) {
        firstChunkAt = Date.now()
      }
      streamedText += chunk
      const displayText = sanitizeStreamingAssistantText(
        applyAssistantOutputPrefix(streamedText, request.assistantOutputPrefix),
        request.stripLeadingAssistantSeparator
      )
      callbacks.onStream({
        text: displayText,
        characterCount: displayText.length
      })
    }

    let result: GenerationResult
    try {
      if (request.imageUri.length > 0) {
        callbacks.onStatus('正在读取图片...')
        const payload: ImagePayload = request.imagePayload ?? await this.imageService.buildImagePayload(request.imageUri)
        if (callbacks.isStopRequested()) {
          result = {
            text: streamedText,
            generatedTokens: 0,
            stopReason: 'user_stop'
          }
        } else {
          callbacks.onStatus('等待视觉模型...')
          result = await this.nativeService.generateImage(
            request.turns,
            payload,
            maxNewTokens,
            settings,
            onChunk,
            request.execution
          )
        }
      } else if (request.preparedPrompt !== undefined) {
        result = await this.nativeService.generateRawPrompt(request.preparedPrompt, maxNewTokens,
          '', settings, onChunk, request.execution)
      } else {
        result = await this.nativeService.generateText(
          request.turns,
          maxNewTokens,
          settings,
          onChunk,
          request.execution
        )
      }

    } finally {
      streamFinished = true
    }

    const answer = finalAssistantAnswer(
      result,
      request.assistantOutputPrefix,
      request.stripLeadingAssistantSeparator
    )
    const includeInContext = shouldIncludeAssistantInContext(answer, result)
    const perfMetrics = calculatePerfMetrics(
      generationStartedAt,
      firstChunkAt,
      Date.now(),
      result.generatedTokens,
      result.generatedTokensEstimated ?? false
    )
    configuration.finishedAt = Date.now()
    perfMetrics.configuration = configuration
    perfMetrics.inputTokens = result.inputTokens
    perfMetrics.reusedInputTokens = result.reusedInputTokens
    perfMetrics.nativeTiming = result.nativeTiming
    return {
      answer,
      includeInContext,
      perfMetrics,
      result,
      status: formatGenerationStatus(answer, includeInContext, result)
    }
  }

  stop(): void {
    this.nativeService.stopGeneration()
  }
}
