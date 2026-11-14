export interface DecisionOutput {
  logits: number[]
  probabilities?: number[]
  cpu_threads?: number
  input_tokens?: number
  elapsed_ms: number
}

export function decisionProbabilities(result: DecisionOutput, count: number): number[] {
  if (!Array.isArray(result.logits) || result.logits.length !== count || count === 0 ||
    !result.logits.every((value: number) => Number.isFinite(value))) throw new Error('模型输出与候选项不符')
  if (result.probabilities !== undefined) {
    const values = result.probabilities
    if (!Array.isArray(values) || values.length !== count ||
      !values.every((value: number) => Number.isFinite(value) && value >= 0 && value <= 1) ||
      Math.abs(values.reduce((sum: number, value: number) => sum + value, 0) - 1) > 0.00001)
      throw new Error('模型返回的候选概率无效')
    return values
  }
  const peak = Math.max(...result.logits)
  const weights = result.logits.map((value: number) => Math.exp(value - peak))
  const total = weights.reduce((sum: number, value: number) => sum + value, 0)
  return weights.map((value: number) => value / total)
}
