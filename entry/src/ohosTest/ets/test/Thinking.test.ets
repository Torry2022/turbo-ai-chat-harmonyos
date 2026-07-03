import { describe, expect, it } from '@ohos/hypium'
import { GenerationResult } from '../../../main/ets/models/ChatTypes'
import {
  finalAssistantAnswer,
  formatGenerationStatus,
  shouldIncludeAssistantInContext
} from '../../../main/ets/utils/generationText'
import { answerTextForContext, parseAssistantText, stripModelSpecialTokens } from '../../../main/ets/utils/thinking'

export default function thinkingTest(): void {
  describe('AssistantText', () => {
    it('separatesThinkingFromAnswer', 0, () => {
      const parts = parseAssistantText('<think>分析过程</think>最终答案。')
      expect(parts.hasThinking).assertTrue()
      expect(parts.thinkingClosed).assertTrue()
      expect(parts.thinking).assertEqual('分析过程')
      expect(parts.answer).assertEqual('最终答案。')
      expect(answerTextForContext('<think>分析过程</think>最终答案。')).assertEqual('最终答案。')
    })

    it('removesKnownModelSpecialTokens', 0, () => {
      expect(stripModelSpecialTokens('<s><|im_start|>assistant\n你好<|im_end|></s>').trim()).assertEqual('assistant\n你好')
    })

    it('keepsStoppedAndTruncatedAnswersOutOfContext', 0, () => {
      const stopped: GenerationResult = { text: '部分回答', generatedTokens: 4, stopReason: 'user_stop' }
      const truncated: GenerationResult = { text: '部分回答', generatedTokens: 4, stopReason: 'max_tokens' }
      expect(shouldIncludeAssistantInContext('部分回答', stopped)).assertFalse()
      expect(shouldIncludeAssistantInContext('部分回答', truncated)).assertFalse()
      expect(finalAssistantAnswer({ text: '', generatedTokens: 0, stopReason: 'user_stop' })).assertEqual('（已停止生成）')
    })

    it('classifiesExplicitAndUnknownStopReasons', 0, () => {
      const timeout: GenerationResult = { text: '部分回答', generatedTokens: 4, stopReason: 'timeout' }
      const internalError: GenerationResult = { text: '部分回答', generatedTokens: 4, stopReason: 'internal_error' }
      const eos: GenerationResult = { text: '完整回答。', generatedTokens: 4, stopReason: 'eos' }
      const unknownComplete: GenerationResult = { text: '完整回答。', generatedTokens: 4, stopReason: 'unknown' }
      const unknownIncomplete: GenerationResult = {
        text: '这是一段尚未结束并且没有句末标点的回答',
        generatedTokens: 12,
        stopReason: 'unknown'
      }

      expect(shouldIncludeAssistantInContext(timeout.text, timeout)).assertFalse()
      expect(shouldIncludeAssistantInContext(internalError.text, internalError)).assertFalse()
      expect(shouldIncludeAssistantInContext(eos.text, eos)).assertTrue()
      expect(shouldIncludeAssistantInContext(unknownComplete.text, unknownComplete)).assertTrue()
      expect(shouldIncludeAssistantInContext(unknownIncomplete.text, unknownIncomplete)).assertFalse()
      expect(formatGenerationStatus(timeout.text, false, timeout))
        .assertEqual('生成超时（4 字符，4 tokens，回答可能不完整）')
      expect(formatGenerationStatus(internalError.text, false, internalError))
        .assertEqual('生成异常（4 字符，4 tokens，回答可能不完整）')
    })
  })
}
