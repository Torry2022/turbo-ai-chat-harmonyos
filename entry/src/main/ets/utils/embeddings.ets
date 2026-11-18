export interface EmbeddingRequest {
  input: string | string[]
  model?: string
  encoding_format?: string
  dimensions?: number
}

export interface EmbeddingObject {
  object: string
  index: number
  embedding: number[]
}

export interface EmbeddingUsage { prompt_tokens: number; total_tokens: number }
export interface EmbeddingResponse {
  object: string
  data: EmbeddingObject[]
  model: string
  usage: EmbeddingUsage
}

export function embeddingInputs(request: EmbeddingRequest): string[] {
  if (!request || typeof request !== 'object' || Array.isArray(request)) {
    throw new Error('请提供包含 input 的 JSON 对象。')
  }
  const texts: string[] = typeof request.input === 'string' ? [request.input] : request.input
  if (!Array.isArray(texts) || texts.length === 0 || texts.length > 64 ||
    texts.some((text: string) => typeof text !== 'string' || text.trim().length === 0)) {
    throw new Error('input 需为非空文本，或包含 1 至 64 条非空文本的数组。')
  }
  if (request.model !== undefined && (typeof request.model !== 'string' || !request.model.trim())) {
    throw new Error('model 需为已加载向量模型的 ID。')
  }
  if (request.encoding_format !== undefined && request.encoding_format !== 'float') {
    throw new Error('encoding_format 当前支持 float。')
  }
  if (request.dimensions !== undefined && (!Number.isInteger(request.dimensions) || request.dimensions < 1)) {
    throw new Error('dimensions 需为模型的原始向量维度。')
  }
  return texts
}
