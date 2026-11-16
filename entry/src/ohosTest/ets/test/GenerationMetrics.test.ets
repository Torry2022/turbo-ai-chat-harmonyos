import { describe, expect, it } from '@ohos/hypium'
import { calculatePerfMetrics, formatPerfMetrics, formatGenerationStatus } from '../../../main/ets/utils/generationText'

export default function generationMetricsTest(): void {
  describe('GenerationMetrics', () => {
    it('usesDecodeOnlyTimeForTpotAndTps', 0, () => {
      const metrics = calculatePerfMetrics(1000, 1500, 2500, 6)
      expect(metrics.ttft).assertEqual(500)
      expect(metrics.tpot).assertEqual(200)
      expect(metrics.tokensPerSec).assertEqual(5)
      expect(metrics.tokens).assertEqual(6)
    })

    it('avoidsInventedRatesForZeroOrOneToken', 0, () => {
      const metrics = calculatePerfMetrics(1000, 1200, 1500, 1)
      expect(metrics.tpot).assertEqual(0)
      expect(metrics.tokensPerSec).assertEqual(0)
    })

    it('labelsEstimatedCountsAndDerivedRatesWithoutChangingMeasuredWait', 0, () => {
      const metrics = calculatePerfMetrics(1000, 1500, 2500, 6, true)
      expect(metrics.tokensEstimated).assertTrue()
      expect(formatPerfMetrics(metrics)).assertEqual('TTFT 500ms · 约 200ms/tok · 约 5 tok/s · 约 6 tokens')
      expect(formatGenerationStatus('正文', true, {
        text: '正文', generatedTokens: 6, generatedTokensEstimated: true, stopReason: 'eos'
      })).assertContain('约 6 tokens')
    })

    it('preservesFormattingForMeasuredCountsAndExistingHistory', 0, () => {
      expect(formatPerfMetrics(calculatePerfMetrics(1000, 1500, 2500, 6)))
        .assertEqual('TTFT 500ms · 200ms/tok · 5 tok/s · 6 tokens')
      expect(formatPerfMetrics({ ttft: 500, tpot: 200, tokensPerSec: 5, tokens: 6 }))
        .assertEqual('TTFT 500ms · 200ms/tok · 5 tok/s · 6 tokens')
    })
  })
}
