import {
  ChatTurn,
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
import { NativeInferenceService } from './NativeInferenceService'

export interface GenerationWorkflowRequest {
  turns: ChatTurn[]
  imageUri: string
  maxNewTokens: number
  settings: GenerationSettings
  assistantOutputPrefix: string
  stripLeadingAssistantSeparator: boolean
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
    const generationStartedAt = Date.now()
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
        const payload: ImagePayload = await this.imageService.buildImagePayload(request.imageUri)
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
            request.maxNewTokens,
            request.settings,
            onChunk
          )
        }
      } else {
        result = await this.nativeService.generateText(
          request.turns,
          request.maxNewTokens,
          request.settings,
          onChunk
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
      result.generatedTokens
    )
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
