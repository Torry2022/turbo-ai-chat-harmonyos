import { describe, expect, it } from '@ohos/hypium'
import { GenerationResult } from '../../../main/ets/models/ChatTypes'
import {
  finalAssistantAnswer,
  sanitizeStreamingAssistantText,
  formatGenerationStatus,
  shouldIncludeAssistantInContext
} from '../../../main/ets/utils/generationText'
import { answerTextForContext, parseAssistantText } from '../../../main/ets/utils/thinking'

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

    it('preservesModelOutputContent', 0, () => {
      const samples: string[] = [
        '```yaml\na: 1\n---\nb: 2\n```',
        'HTML 示例：<s>旧价格</s>。',
        '请保留字面量 <|im_end|>。',
        '第一段。\n\n第二段。',
        '第一行  \n第二行。',
        '请选择保存位置。\n本地',
        '  缩进文本\n尾部空格  ',
        '示例：`<think>分析</think>`'
      ]
      samples.forEach((text: string) => {
        expect(sanitizeStreamingAssistantText(text)).assertEqual(text)
        expect(parseAssistantText(text).answer).assertEqual(text)
        const stopReasons: string[] = ['eos', 'max_tokens', 'user_stop']
        stopReasons.forEach((stopReason: string) => {
          expect(finalAssistantAnswer({ text, generatedTokens: 8, stopReason })).assertEqual(text)
        })
      })
    })

    it('keepsVisibleStoppedAndTruncatedAnswersInContext', 0, () => {
      const stopped: GenerationResult = { text: '部分回答', generatedTokens: 4, stopReason: 'user_stop' }
      const truncated: GenerationResult = { text: '部分回答', generatedTokens: 4, stopReason: 'max_tokens' }
      expect(shouldIncludeAssistantInContext('部分回答', stopped)).assertTrue()
      expect(shouldIncludeAssistantInContext('部分回答', truncated)).assertTrue()
      expect(finalAssistantAnswer({ text: '', generatedTokens: 0, stopReason: 'user_stop' })).assertEqual('')
      expect(shouldIncludeAssistantInContext('（已停止生成）', {
        text: '', generatedTokens: 0, stopReason: 'user_stop'
      })).assertFalse()
      expect(shouldIncludeAssistantInContext('<think>尚未完成', {
        text: '<think>尚未完成', generatedTokens: 3, stopReason: 'max_tokens'
      })).assertFalse()
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

      expect(shouldIncludeAssistantInContext(timeout.text, timeout)).assertTrue()
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
