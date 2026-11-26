import { ModelCatalogItem } from './BuiltinModelDownloadTypes'

const REPO = 'TorryJi/H2O-Lightning-4B-MNN-INT8'
const REVISION = 'f626be5d7680deae28eaf292d22b902ac54c2772'
const BASE_URL = `https://modelscope.cn/models/${REPO}/resolve/${REVISION}`
const INT4_REPO = 'TorryJi/H2O-Lightning-4B-MNN-INT4'
const INT4_BASE_URL = `https://modelscope.cn/models/${INT4_REPO}/resolve/3ccbc58ebd822c6415c3bdfa78d63a3ce14a0c41`
const H2O_DESCRIPTION = 'H2O.ai 多模态决策模型，支持候选选择、评分与是非判断，可结合图片作出决策。'

export const H2O_DOWNLOAD_SPEC: ModelCatalogItem = {
  id: 'h2o-lightning-4b-mnn-int8',
  variantGroup: 'H2O-Lightning-4B',
  variantLabel: 'INT8',
  modelType: 'decision',
  modelId: REPO,
  directoryName: 'H2O-Lightning-4B-MNN-INT8',
  displayName: 'H2O-Lightning-4B-MNN-INT8',
  shortName: 'H2O-Lightning-4B',
  description: H2O_DESCRIPTION,
  provider: 'H2O.ai',
  supportsImage: true,
  capabilities: ['图像理解'],
  recommended: false,
  sourceName: 'ModelScope',
  sourceUrl: `https://modelscope.cn/models/${REPO}`,
  files: [
    { relativePath: 'config.json', sizeBytes: 724,
      url: `${BASE_URL}/config.json`, sha256: 'b8d84806af7f8f182d3e2b7c4b86a989f35b10aa1259345ccc50783d64f8dc47' },
    { relativePath: 'llm_config.json', sizeBytes: 9045,
      url: `${BASE_URL}/llm_config.json`, sha256: 'eaf49848491e26158cbb8ad9b0d1bbe1a8a127b262c895170fdc4d6f7e728da5' },
    { relativePath: 'llm.mnn', sizeBytes: 5340552,
      url: `${BASE_URL}/llm.mnn`, sha256: '016d80de5422186208aaa36bebd131575e0f3e758bec87298f984ba45d91946e' },
    { relativePath: 'llm.mnn.weight', sizeBytes: 3793581568,
      url: `${BASE_URL}/llm.mnn.weight`, sha256: '686e932417715a46d5a55554709bb737ece9124449d5750be182425ac9d47520' },
    { relativePath: 'embeddings_bf16.bin', sizeBytes: 1271398400,
      url: `${BASE_URL}/embeddings_bf16.bin`, sha256: '2a68153b498532801ab605bb03fe617c57b3e6a3ba019301fb70ada0c864a2f7' },
    { relativePath: 'tokenizer.mtok', sizeBytes: 7334464,
      url: `${BASE_URL}/tokenizer.mtok`, sha256: 'a3a67a5f90a39d61caa36682742661fdc924bd888942221506802a4599f9d63d' },
    { relativePath: 'visual.mnn', sizeBytes: 5271136,
      url: `${BASE_URL}/visual.mnn`, sha256: 'a7d4ccc6ad806b15beabc6223692808d6692fb86ef17ed5f55c18d5e27279747' },
    { relativePath: 'visual.mnn.weight', sizeBytes: 662968320,
      url: `${BASE_URL}/visual.mnn.weight`, sha256: '16058d2191d7a85f4d84093d8a7615a9345a63a0edc770a5d124e816c1ef7a02' },
    { relativePath: 'LICENSE', sizeBytes: 11343,
      url: `${BASE_URL}/LICENSE`, sha256: '50cbab8a892c5f2993b8c7351a99182507472def3b1374558308605d99b86b32' },
    { relativePath: 'NOTICE', sizeBytes: 482,
      url: `${BASE_URL}/NOTICE`, sha256: '853ff2555df6c8b9cd15d2910b3a94429655a05834657af0496453c1709ccc2f' }
  ],
  totalBytes: 5745916034
}

export const H2O_INT4_DOWNLOAD_SPEC: ModelCatalogItem = {
  id: 'h2o-lightning-4b-mnn-int4',
  variantGroup: 'H2O-Lightning-4B',
  variantLabel: 'INT4',
  modelType: 'decision',
  modelId: INT4_REPO,
  directoryName: 'H2O-Lightning-4B-MNN-INT4',
  displayName: 'H2O-Lightning-4B-MNN-INT4',
  shortName: 'H2O-Lightning-4B INT4',
  description: H2O_DESCRIPTION,
  provider: 'H2O.ai',
  supportsImage: true,
  capabilities: ['图像理解'],
  recommended: false,
  sourceName: 'ModelScope',
  sourceUrl: `https://modelscope.cn/models/${INT4_REPO}`,
  files: [
    { relativePath: 'config.json', sizeBytes: 724,
      url: `${INT4_BASE_URL}/config.json`, sha256: 'b8d84806af7f8f182d3e2b7c4b86a989f35b10aa1259345ccc50783d64f8dc47' },
    { relativePath: 'llm_config.json', sizeBytes: 9045,
      url: `${INT4_BASE_URL}/llm_config.json`, sha256: 'eaf49848491e26158cbb8ad9b0d1bbe1a8a127b262c895170fdc4d6f7e728da5' },
    { relativePath: 'llm.mnn', sizeBytes: 4037784,
      url: `${INT4_BASE_URL}/llm.mnn`, sha256: '8a780106f32ac85277b9afc7d7435fe4e2b3ed6907d2afa59900b7accdf9f0e4' },
    { relativePath: 'llm.mnn.weight', sizeBytes: 2010280448,
      url: `${INT4_BASE_URL}/llm.mnn.weight`, sha256: 'fe8b263aa84034b707fd613077bcbf42876f86b758e825160f616de69c76ab2b' },
    { relativePath: 'embeddings_bf16.bin', sizeBytes: 1271398400,
      url: `${INT4_BASE_URL}/embeddings_bf16.bin`, sha256: '2a68153b498532801ab605bb03fe617c57b3e6a3ba019301fb70ada0c864a2f7' },
    { relativePath: 'tokenizer.mtok', sizeBytes: 7334464,
      url: `${INT4_BASE_URL}/tokenizer.mtok`, sha256: 'a3a67a5f90a39d61caa36682742661fdc924bd888942221506802a4599f9d63d' },
    { relativePath: 'visual.mnn', sizeBytes: 5271136,
      url: `${INT4_BASE_URL}/visual.mnn`, sha256: 'a7d4ccc6ad806b15beabc6223692808d6692fb86ef17ed5f55c18d5e27279747' },
    { relativePath: 'visual.mnn.weight', sizeBytes: 662968320,
      url: `${INT4_BASE_URL}/visual.mnn.weight`, sha256: '16058d2191d7a85f4d84093d8a7615a9345a63a0edc770a5d124e816c1ef7a02' },
    { relativePath: 'LICENSE', sizeBytes: 11343,
      url: `${INT4_BASE_URL}/LICENSE`, sha256: '50cbab8a892c5f2993b8c7351a99182507472def3b1374558308605d99b86b32' },
    { relativePath: 'NOTICE', sizeBytes: 696,
      url: `${INT4_BASE_URL}/NOTICE`, sha256: '36d78887a756edc1a8f4c2cdf2748f6fd8770971db652bf4ecbef3dc015ae01e' }
  ],
  totalBytes: 3961312360
}
