import { ModelCatalogItem } from './BuiltinModelDownloadTypes'

const REPO: string = 'TorryJi/bge-small-zh-v1.5-MNN'
const REVISION: string = '76a422bc'

export const BGE_EMBEDDING_DOWNLOAD: ModelCatalogItem = {
  id: 'bge-small-zh-v1.5-embedding', modelId: 'bge-small-zh-v1.5-embedding', modelType: 'embedding',
  directoryName: 'bge-small-zh-v1.5-MNN', displayName: 'bge-small-zh-v1.5', shortName: 'bge-small-zh-v1.5',
  description: '中文文本向量模型，用于语义检索和相似度计算。', provider: 'BGE',
  sourceName: 'ModelScope', sourceUrl: `https://modelscope.cn/models/${REPO}`,
  supportsImage: false, capabilities: ['向量'], recommended: false, totalBytes: 63996034,
  files: [
    { relativePath: 'config.json', sizeBytes: 547, url: `https://modelscope.cn/models/${REPO}/resolve/${REVISION}/config.json` },
    { relativePath: 'llm_config.json', sizeBytes: 422, url: `https://modelscope.cn/models/${REPO}/resolve/${REVISION}/llm_config.json` },
    { relativePath: 'llm.mnn', sizeBytes: 119192, url: `https://modelscope.cn/models/${REPO}/resolve/${REVISION}/llm.mnn` },
    { relativePath: 'llm.mnn.weight', sizeBytes: 51490816, url: `https://modelscope.cn/models/${REPO}/resolve/${REVISION}/llm.mnn.weight` },
    { relativePath: 'embeddings_int8.bin', sizeBytes: 12169728, url: `https://modelscope.cn/models/${REPO}/resolve/${REVISION}/embeddings_int8.bin` },
    { relativePath: 'tokenizer.mtok', sizeBytes: 215329, url: `https://modelscope.cn/models/${REPO}/resolve/${REVISION}/tokenizer.mtok` }
  ]
}
