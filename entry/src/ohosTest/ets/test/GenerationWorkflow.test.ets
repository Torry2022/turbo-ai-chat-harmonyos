import { describe, expect, it } from '@ohos/hypium'
import { ChatTurn, GenerationResult, GenerationSettings } from '../../../main/ets/models/ChatTypes'
import { GenerationWorkflow, GenerationWorkflowRequest } from '../../../main/ets/services/GenerationWorkflow'
import { ImagePayloadService } from '../../../main/ets/services/ImagePayloadService'
import { NativeInferenceService } from '../../../main/ets/services/NativeInferenceService'

class DeferredChunkService extends NativeInferenceService {
  fail: boolean = false
  estimated: boolean = false
  rawPrompt: string = ''
  chunk: (text: string) => void = (_text: string) => {}

  generateText(_turns: ChatTurn[], _limit: number, _settings: GenerationSettings,
    onChunk: (chunk: string) => void): Promise<GenerationResult> {
    this.chunk = onChunk
    onChunk('par')
    if (this.fail) {
      return Promise.reject(new Error('test failure'))
    }
    return Promise.resolve<GenerationResult>({ text: 'partial answer', generatedTokens: 2,
      inputTokens: 17, reusedInputTokens: 12, nativeTiming: { prefillMs: 12.345, decodeMs: 23.456, visionMs: 0 },
      generatedTokensEstimated: this.estimated, stopReason: 'eos' })
  }

  generateRawPrompt(prompt: string, limit: number, _endWith: string, settings: GenerationSettings,
    onChunk: (chunk: string) => void): Promise<GenerationResult> {
    this.rawPrompt = prompt
    return this.generateText([], limit, settings, onChunk)
  }
}

function request(): GenerationWorkflowRequest {
  return {
    turns: [{ role: 'user', content: 'test' }],
    imageUri: '',
    maxNewTokens: 16,
    settings: { temperature: 0.7, topP: 0.8, topK: 20, repetitionPenalty: 1.05,
      frequencyPenalty: 0, presencePenalty: 0, penaltyWindow: 64 },
    assistantOutputPrefix: '',
    stripLeadingAssistantSeparator: false
  }
}

export default function generationWorkflowTest(): void {
  describe('GenerationWorkflow', () => {
    it('usesThePreparedNativeTemplateVerbatimAndIncludesPreparationInWaitTime', 0, async () => {
      const native = new DeferredChunkService()
      const workflow = new GenerationWorkflow(native, new ImagePayloadService())
      const input = request()
      input.preparedPrompt = '  模型自己的模板\n<think>\n'
      input.requestedAt = Date.now() - 50
      const outcome = await workflow.run(input, {
        onStatus: (_status: string) => {}, onStream: () => {}, isStopRequested: () => false
      })
      expect(native.rawPrompt).assertEqual(input.preparedPrompt)
      expect(outcome.perfMetrics.ttft >= 50).assertTrue()
      expect(outcome.perfMetrics.inputTokens).assertEqual(17)
      expect(outcome.perfMetrics.reusedInputTokens).assertEqual(12)
      expect(outcome.perfMetrics.nativeTiming?.prefillMs).assertEqual(12.345)
      expect(outcome.perfMetrics.nativeTiming?.decodeMs).assertEqual(23.456)
      expect(outcome.perfMetrics.nativeTiming?.visionMs).assertEqual(0)
    })
    it('keepsRequestConfigurationIndependentOfLaterChangesAndCacheIdentity', 0, async () => {
      const input = request()
      input.modelIdentity = { id: 'loaded-id', name: 'loaded-name', requestedThreads: 8, actualThreads: 6, runtimeLibrarySha256: 'runtime-hash', fileManifestSha256: 'file-metadata-hash', sourceRepository: 'MNN/Test', sourceRevision: 'test-revision' }
      input.environment = { appVersion: '2.0.0', appVersionCode: 2000000, deviceModel: 'test-device', osVersion: 'test-os' }
      input.settings.kvCacheScope = 'private-conversation-id'
      input.settings.thinkingEnabled = false
      const workflow = new GenerationWorkflow(new DeferredChunkService(), new ImagePayloadService())
      const outcome = await workflow.run(input, {
        onStatus: () => {}, isStopRequested: () => false,
        onStream: () => { input.settings.temperature = 1.5; input.maxNewTokens = 128 }
      })
      expect(outcome.perfMetrics.configuration?.maxNewTokens).assertEqual(16)
      expect(outcome.perfMetrics.configuration?.settings.temperature).assertEqual(0.7)
      expect(outcome.perfMetrics.configuration?.settings.thinkingEnabled).assertFalse()
      expect(outcome.perfMetrics.configuration?.settings.kvCacheScope).assertUndefined()
      input.environment.appVersion = 'changed-version'
      expect(outcome.perfMetrics.configuration?.environment?.appVersion).assertEqual('2.0.0')
      expect(outcome.perfMetrics.configuration?.environment?.deviceModel).assertEqual('test-device')
      input.modelIdentity.name = 'changed-model'
      expect(outcome.perfMetrics.configuration?.model?.name).assertEqual('loaded-name')
      expect(outcome.perfMetrics.configuration?.model?.actualThreads).assertEqual(6)
      expect(outcome.perfMetrics.configuration?.model?.runtimeLibrarySha256).assertEqual('runtime-hash')
      expect(outcome.perfMetrics.configuration?.model?.fileManifestSha256).assertEqual('file-metadata-hash')
      expect(outcome.perfMetrics.configuration?.model?.sourceRepository).assertEqual('MNN/Test')
      expect(outcome.perfMetrics.configuration?.model?.sourceRevision).assertEqual('test-revision')
      expect((outcome.perfMetrics.configuration?.finishedAt ?? 0) >=
        (outcome.perfMetrics.configuration?.startedAt ?? 1)).assertTrue()
      input.settings.topK = 99
      expect(outcome.perfMetrics.configuration?.settings.topK).assertEqual(20)
    })
    it('carriesNativeEstimateIntoSavedPerformanceMetrics', 0, async () => {
      const native = new DeferredChunkService()
      native.estimated = true
      const workflow = new GenerationWorkflow(native, new ImagePayloadService())
      const outcome = await workflow.run(request(), {
        onStatus: (_status: string) => {}, onStream: () => {}, isStopRequested: () => false
      })
      expect(outcome.perfMetrics.tokensEstimated).assertTrue()
      expect(outcome.status).assertContain('约 2 tokens')
    })
    it('ignoresQueuedChunksAfterCompletion', 0, async () => {
      const native = new DeferredChunkService()
      const workflow = new GenerationWorkflow(native, new ImagePayloadService())
      let updates = 0
      const outcome = await workflow.run(request(), {
        onStatus: (_status: string) => {},
        onStream: () => { updates++ },
        isStopRequested: () => false
      })
      expect(updates).assertEqual(1)
      native.chunk('tial answer')
      expect(updates).assertEqual(1)
      expect(outcome.answer).assertEqual('partial answer')
      expect(outcome.result.generatedTokens).assertEqual(2)
    })

    it('ignoresQueuedChunksAfterFailure', 0, async () => {
      const native = new DeferredChunkService()
      native.fail = true
      const workflow = new GenerationWorkflow(native, new ImagePayloadService())
      let updates = 0
      let failed = false
      try {
        await workflow.run(request(), {
          onStatus: (_status: string) => {},
          onStream: () => { updates++ },
          isStopRequested: () => false
        })
      } catch (_) {
        failed = true
      }
      native.chunk('late chunk')
      expect(failed).assertTrue()
      expect(updates).assertEqual(1)
    })
  })
}
