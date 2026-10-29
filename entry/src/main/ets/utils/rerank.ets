export interface RerankRequest {
  model?: string
  query: string
  documents: string[]
  top_n?: number
}

export interface RerankResult {
  index: number
  relevance_score: number
}

export function validateRerankRequest(body: RerankRequest): string {
  if (body === null || typeof body !== 'object') return '请求必须为 JSON 对象。'
  if (typeof body.query !== 'string' || body.query.trim().length === 0) return 'query 不能为空。'
  if (body.model !== undefined && (typeof body.model !== 'string' || body.model.length === 0)) return 'model 必须为模型 ID。'
  if (!Array.isArray(body.documents) || body.documents.length < 1 || body.documents.length > 64) return 'documents 需要包含 1–64 段文本。'
  for (const text of body.documents) {
    if (typeof text !== 'string' || text.trim().length === 0) return '候选文本不能为空。'
  }
  if (body.top_n !== undefined && (!Number.isInteger(body.top_n) || body.top_n < 1 || body.top_n > body.documents.length)) return 'top_n 必须为候选数量范围内的正整数。'
  return ''
}

export function rankScores(scores: number[], topN: number): RerankResult[] {
  if (scores.some((score: number) => !Number.isFinite(score) || score < 0 || score > 1)) throw new Error('重排模型返回无效分数')
  return scores.map((score: number, index: number): RerankResult => ({ index, relevance_score: score }))
    .sort((a: RerankResult, b: RerankResult): number => b.relevance_score - a.relevance_score || a.index - b.index)
    .slice(0, topN)
}

export interface RerankResponse {
  model: string
  results: RerankResult[]
}
