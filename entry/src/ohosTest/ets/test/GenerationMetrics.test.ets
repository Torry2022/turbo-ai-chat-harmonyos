import { describe, expect, it } from '@ohos/hypium'
import { calculatePerfMetrics } from '../../../main/ets/utils/generationText'

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
  })
}
