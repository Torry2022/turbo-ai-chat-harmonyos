import { describe, expect, it } from '@ohos/hypium'
import {
  ApiReasoningStreamFilter,
  splitApiOutput,
  visibleAnswer
} from '../../../main/ets/services/OpenAiApiServer'

export default function openAiApiServerTest(): void {
  describe('OpenAiApiServer', () => {
    it('streamsNormalAnswerWithoutChangingText', 0, () => {
      const filter = new ApiReasoningStreamFilter()
      expect(filter.append('你好').answer).assertEqual('你好')
      expect(filter.append('，世界').answer).assertEqual('，世界')
      expect(filter.complete('你好，世界。').answer).assertEqual('。')
      expect(filter.output().reasoning).assertEqual('')
      expect(filter.output().answer).assertEqual('你好，世界。')
    })

    it('streamsThinkingSeparatelyFromAnswer', 0, () => {
      const filter = new ApiReasoningStreamFilter()
      expect(filter.append('<thi').reasoning).assertEqual('')
      expect(filter.append('nk>分析过程').reasoning).assertEqual('分析过程')
      expect(filter.append('</thi').reasoning).assertEqual('')
      const answerDelta = filter.append('nk>最终')
      expect(answerDelta.reasoning).assertEqual('')
      expect(answerDelta.answer).assertEqual('最终')
      expect(filter.complete('<think>分析过程</think>最终答案。').answer).assertEqual('答案。')
      expect(filter.output().reasoning).assertEqual('分析过程')
      expect(filter.output().answer).assertEqual('最终答案。')
    })

    it('splitsThinkingFromNonStreamingAnswer', 0, () => {
      const output = splitApiOutput('<think>内部分析</think>对外回答。', true)
      expect(output.reasoning).assertEqual('内部分析')
      expect(output.answer).assertEqual('对外回答。')
      expect(visibleAnswer('<think>内部分析</think>对外回答。', true)).assertEqual('对外回答。')
    })
  })
}
