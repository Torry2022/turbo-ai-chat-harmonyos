import { ModelCatalogItem } from './BuiltinModelDownloadTypes'

const REPO = 'TorryJi/H2O-Lightning-4B-MNN-INT8'
const REVISION = 'f626be5d7680deae28eaf292d22b902ac54c2772'
const BASE_URL = `https://modelscope.cn/models/${REPO}/resolve/${REVISION}`

export const H2O_DOWNLOAD_SPEC: ModelCatalogItem = {
  id: 'h2o-lightning-4b-mnn-int8',
  modelType: 'decision',
  modelId: REPO,
  directoryName: 'H2O-Lightning-4B-MNN-INT8',
  displayName: 'H2O-Lightning-4B-MNN-INT8',
  shortName: 'H2O-Lightning-4B',
  description: 'H2O.ai 多模态决策模型，支持候选选择、评分与是非判断，可结合图片作出决策。',
  provider: 'H2O.ai',
  supportsImage: true,
  capabilities: ['图像理解'],
  recommended: false,
  sourceName: 'ModelScope',
  sourceUrl: `https://modelscope.cn/models/${REPO}`,
  files: [
    { relativePath: 'config.json', sizeBytes: 724, url: `${BASE_URL}/config.json` },
    { relativePath: 'llm_config.json', sizeBytes: 9045, url: `${BASE_URL}/llm_config.json` },
    { relativePath: 'llm.mnn', sizeBytes: 5340552, url: `${BASE_URL}/llm.mnn` },
    { relativePath: 'llm.mnn.weight', sizeBytes: 3793581568, url: `${BASE_URL}/llm.mnn.weight` },
    { relativePath: 'embeddings_bf16.bin', sizeBytes: 1271398400, url: `${BASE_URL}/embeddings_bf16.bin` },
    { relativePath: 'tokenizer.mtok', sizeBytes: 7334464, url: `${BASE_URL}/tokenizer.mtok` },
    { relativePath: 'visual.mnn', sizeBytes: 5271136, url: `${BASE_URL}/visual.mnn` },
    { relativePath: 'visual.mnn.weight', sizeBytes: 662968320, url: `${BASE_URL}/visual.mnn.weight` },
    { relativePath: 'LICENSE', sizeBytes: 11343, url: `${BASE_URL}/LICENSE` },
    { relativePath: 'NOTICE', sizeBytes: 482, url: `${BASE_URL}/NOTICE` }
  ],
  totalBytes: 5745916034
}
