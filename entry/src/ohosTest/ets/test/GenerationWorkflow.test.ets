import { describe, expect, it } from '@ohos/hypium'
import { ChatTurn, GenerationResult, GenerationSettings } from '../../../main/ets/models/ChatTypes'
import { GenerationWorkflow, GenerationWorkflowRequest } from '../../../main/ets/services/GenerationWorkflow'
import { ImagePayloadService } from '../../../main/ets/services/ImagePayloadService'
import { NativeInferenceService } from '../../../main/ets/services/NativeInferenceService'

class DeferredChunkService extends NativeInferenceService {
  fail: boolean = false
  chunk: (text: string) => void = (_text: string) => {}

  generateText(_turns: ChatTurn[], _limit: number, _settings: GenerationSettings,
    onChunk: (chunk: string) => void): Promise<GenerationResult> {
    this.chunk = onChunk
    onChunk('par')
    if (this.fail) {
      return Promise.reject(new Error('test failure'))
    }
    return Promise.resolve<GenerationResult>({ text: 'partial answer', generatedTokens: 2, stopReason: 'eos' })
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
