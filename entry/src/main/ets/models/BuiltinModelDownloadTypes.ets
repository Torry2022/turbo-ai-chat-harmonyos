export interface BuiltinModelFileSpec {
  relativePath: string
  sizeBytes: number
  url: string
}

export interface CatalogGenerationDefaults {
  maxNewTokens?: number
  temperature?: number
  topP?: number
  topK?: number
  repetitionPenalty?: number
  frequencyPenalty?: number
  presencePenalty?: number
  penaltyWindow?: number
}

export interface CatalogRuntimeSpec {
  systemPrompt: string
  contextMessageLimit: number
  generationDefaults?: CatalogGenerationDefaults
}

export interface BuiltinModelDownloadSpec {
  id: string
  modelId: string
  directoryName: string
  displayName: string
  sourceName: string
  sourceUrl: string
  files: BuiltinModelFileSpec[]
  totalBytes: number
}

export interface ModelCatalogItem extends BuiltinModelDownloadSpec {
  shortName: string
  description: string
  provider: string
  supportsImage: boolean
  capabilities: string[]
  recommended: boolean
  runtime?: CatalogRuntimeSpec
}

export interface BuiltinModelInstallProgress {
  modelName: string
  fileName: string
  downloadedBytes: number
  totalBytes: number
  progress: number
  message: string
}

interface BuiltinModelFileInput {
  relativePath: string
  sizeBytes: number
}

export const MODEL_CATALOG_FILTER_ALL: string = '全部'

const MODELSCOPE_BASE_URL: string = 'https://modelscope.cn/models'

function modelScopeFileUrl(repo: string, relativePath: string): string {
  return `${MODELSCOPE_BASE_URL}/${repo}/resolve/master/${relativePath}`
}

function createSpec(
  id: string,
  modelId: string,
  directoryName: string,
  displayName: string,
  repo: string,
  files: BuiltinModelFileInput[]
): ModelCatalogItem {
  const resolvedFiles = files.map((file: BuiltinModelFileInput): BuiltinModelFileSpec => {
    return {
      relativePath: file.relativePath,
      sizeBytes: file.sizeBytes,
      url: modelScopeFileUrl(repo, file.relativePath)
    }
  })
  let totalBytes = 0
  resolvedFiles.forEach((file: BuiltinModelFileSpec) => {
    totalBytes += file.sizeBytes
  })
  return {
    id,
    modelId,
    directoryName,
    displayName,
    shortName: displayName,
    description: '',
    provider: '',
    sourceName: 'ModelScope',
    sourceUrl: `${MODELSCOPE_BASE_URL}/${repo}`,
    supportsImage: false,
    capabilities: ['文本'],
    recommended: true,
    files: resolvedFiles,
    totalBytes
  }
}

function withCatalogMeta(
  spec: ModelCatalogItem,
  shortName: string,
  description: string,
  provider: string,
  supportsImage: boolean,
  capabilities: string[],
  recommended: boolean = true
): ModelCatalogItem {
  return {
    id: spec.id,
    modelId: spec.modelId,
    directoryName: spec.directoryName,
    displayName: spec.displayName,
    shortName,
    description,
    provider,
    sourceName: spec.sourceName,
    sourceUrl: spec.sourceUrl,
    supportsImage,
    capabilities,
    recommended,
    files: spec.files,
    totalBytes: spec.totalBytes
  }
}

export const MODEL_CATALOG_ITEMS: ModelCatalogItem[] = [
  withCatalogMeta(createSpec(
    'qwen3-4b-instruct',
    'qwen3-4b-instruct',
    'Qwen3-4B-Instruct-2507-MNN',
    'Qwen3-4B-Instruct',
    'MNN/Qwen3-4B-Instruct-2507-MNN',
    [
      { relativePath: 'config.json', sizeBytes: 403 },
      { relativePath: 'llm_config.json', sizeBytes: 4803 },
      { relativePath: 'tokenizer.txt', sizeBytes: 3193555 },
      { relativePath: 'llm.mnn', sizeBytes: 592336 },
      { relativePath: 'llm.mnn.weight', sizeBytes: 2709972658 }
    ]
  ), 'Qwen3-4B-Instruct', '通用中文文本模型，适合作为默认本地对话。', 'MNN', false, ['文本', '通用']),
  withCatalogMeta(createSpec(
    'gemma4',
    'gemma4',
    'gemma-4-E2B-it-MNN',
    'Gemma 4 E2B',
    'MNN/gemma-4-E2B-it-MNN',
    [
      { relativePath: 'config.json', sizeBytes: 678 },
      { relativePath: 'llm_config.json', sizeBytes: 1415 },
      { relativePath: 'tokenizer.mtok', sizeBytes: 10068633 },
      { relativePath: 'llm.mnn', sizeBytes: 2276992 },
      { relativePath: 'llm.mnn.weight', sizeBytes: 1436474178 },
      { relativePath: 'ple_embeddings_int4.bin', sizeBytes: 1468006400 },
      { relativePath: 'visual.mnn', sizeBytes: 1060528 },
      { relativePath: 'visual.mnn.weight', sizeBytes: 225904812 },
      { relativePath: 'audio.mnn', sizeBytes: 1428288 },
      { relativePath: 'audio.mnn.weight', sizeBytes: 589877376 }
    ]
  ), 'Gemma-4-E2B', '图片理解实验模型，支持文本和图片输入。', 'MNN', true, ['文本', '图片']),
  withCatalogMeta(createSpec(
    'qwen3-vl-4b-instruct',
    'qwen3-vl-4b-instruct',
    'Qwen3-VL-4B-Instruct-MNN',
    'Qwen3-VL-4B-Instruct',
    'MNN/Qwen3-VL-4B-Instruct-MNN',
    [
      { relativePath: 'config.json', sizeBytes: 605 },
      { relativePath: 'llm_config.json', sizeBytes: 6446 },
      { relativePath: 'tokenizer.txt', sizeBytes: 3193555 },
      { relativePath: 'llm.mnn', sizeBytes: 591728 },
      { relativePath: 'llm.mnn.weight', sizeBytes: 2709972658 },
      { relativePath: 'visual.mnn', sizeBytes: 502512 },
      { relativePath: 'visual.mnn.weight', sizeBytes: 242953564 }
    ]
  ), 'Qwen3-VL-4B', '中文图像理解模型，支持文本、图片和视觉问答。', 'MNN', true, ['文本', '图片'], false),
  withCatalogMeta(createSpec(
    'minicpm5-1b',
    'minicpm5-1b',
    'MiniCPM5-1B-MNN',
    'MiniCPM5-1B',
    'TorryJi/MiniCPM5-1B-MNN-BF16',
    [
      { relativePath: 'config.json', sizeBytes: 547 },
      { relativePath: 'llm_config.json', sizeBytes: 9617 },
      { relativePath: 'tokenizer.mtok', sizeBytes: 3536395 },
      { relativePath: 'llm.mnn', sizeBytes: 419568 },
      { relativePath: 'llm.mnn.weight', sizeBytes: 1760636928 },
      { relativePath: 'embeddings_bf16.bin', sizeBytes: 401080320 }
    ]
  ), 'MiniCPM5-1B', '超小参数文本模型，适合轻量本地对话与快速验证。', 'TorryJi', false, ['文本', '轻量']),
  withCatalogMeta(createSpec(
    'qwen3-0.6b',
    'qwen3-0.6b',
    'Qwen3-0.6B-MNN',
    'Qwen3-0.6B',
    'MNN/Qwen3-0.6B-MNN',
    [
      { relativePath: 'config.json', sizeBytes: 403 },
      { relativePath: 'llm_config.json', sizeBytes: 4880 },
      { relativePath: 'tokenizer.txt', sizeBytes: 3193569 },
      { relativePath: 'llm.mnn', sizeBytes: 461520 },
      { relativePath: 'llm.mnn.weight', sizeBytes: 450810338 }
    ]
  ), 'Qwen3-0.6B', '超轻量 Qwen3 文本模型，适合快速响应和低存储占用。', 'MNN', false, ['文本', '超轻量'], false),
  withCatalogMeta(createSpec(
    'qwen3-1.7b',
    'qwen3-1.7b',
    'Qwen3-1.7B-MNN',
    'Qwen3-1.7B',
    'MNN/Qwen3-1.7B-MNN',
    [
      { relativePath: 'config.json', sizeBytes: 403 },
      { relativePath: 'llm_config.json', sizeBytes: 4881 },
      { relativePath: 'tokenizer.txt', sizeBytes: 3193569 },
      { relativePath: 'llm.mnn', sizeBytes: 461520 },
      { relativePath: 'llm.mnn.weight', sizeBytes: 1231860194 }
    ]
  ), 'Qwen3-1.7B', '轻量 Qwen3 文本模型，兼顾速度、效果和占用。', 'MNN', false, ['文本', '轻量'], false),
  withCatalogMeta(createSpec(
    'qwen2.5-1.5b-instruct',
    'qwen2.5-1.5b-instruct',
    'Qwen2.5-1.5B-Instruct-MNN',
    'Qwen2.5-1.5B-Instruct',
    'MNN/Qwen2.5-1.5B-Instruct-MNN',
    [
      { relativePath: 'config.json', sizeBytes: 159 },
      { relativePath: 'llm_config.json', sizeBytes: 384 },
      { relativePath: 'tokenizer.txt', sizeBytes: 3193477 },
      { relativePath: 'llm.mnn', sizeBytes: 1145128 },
      { relativePath: 'llm.mnn.weight', sizeBytes: 868491506 }
    ]
  ), 'Qwen2.5-1.5B', '低内存 Qwen2.5 指令模型，适合常规文本对话。', 'MNN', false, ['文本', '低内存'], false),
  withCatalogMeta(createSpec(
    'qwen2.5-3b-instruct',
    'qwen2.5-3b-instruct',
    'Qwen2.5-3B-Instruct-MNN',
    'Qwen2.5-3B-Instruct',
    'MNN/Qwen2.5-3B-Instruct-MNN',
    [
      { relativePath: 'config.json', sizeBytes: 159 },
      { relativePath: 'llm_config.json', sizeBytes: 274 },
      { relativePath: 'tokenizer.txt', sizeBytes: 3193477 },
      { relativePath: 'llm.mnn', sizeBytes: 1180432 },
      { relativePath: 'llm.mnn.weight', sizeBytes: 1736078786 },
      { relativePath: 'embeddings_bf16.bin', sizeBytes: 622329856 }
    ]
  ), 'Qwen2.5-3B', '中档 Qwen2.5 指令模型，适合对话、摘要和轻量写作。', 'MNN', false, ['文本', '中档'], false),
  withCatalogMeta(createSpec(
    'qwen3-8b',
    'qwen3-8b',
    'Qwen3-8B-MNN',
    'Qwen3-8B',
    'MNN/Qwen3-8B-MNN',
    [
      { relativePath: 'config.json', sizeBytes: 417 },
      { relativePath: 'llm_config.json', sizeBytes: 413 },
      { relativePath: 'tokenizer.txt', sizeBytes: 3193569 },
      { relativePath: 'llm.mnn', sizeBytes: 592328 },
      { relativePath: 'llm.mnn.weight', sizeBytes: 4259526082 },
      { relativePath: 'embeddings_bf16.bin', sizeBytes: 1244659712 }
    ]
  ), 'Qwen3-8B', '较大参数 Qwen3 文本模型，适合大内存设备尝试。', 'MNN', false, ['文本', '大内存'], false)
]

export const BUILTIN_MODEL_DOWNLOADS: BuiltinModelDownloadSpec[] = MODEL_CATALOG_ITEMS

export function findModelCatalogItem(catalogItemId: string | undefined): ModelCatalogItem | undefined {
  if (catalogItemId === undefined || catalogItemId.length <= 0) {
    return undefined
  }
  for (let index = 0; index < MODEL_CATALOG_ITEMS.length; index++) {
    if (MODEL_CATALOG_ITEMS[index].id === catalogItemId) {
      return MODEL_CATALOG_ITEMS[index]
    }
  }
  return undefined
}

export function findBuiltinModelDownloadSpec(downloadId: string | undefined): BuiltinModelDownloadSpec | undefined {
  return findModelCatalogItem(downloadId)
}

export function isBundledPresetCatalogItem(catalogItemId: string): boolean {
  const item = findModelCatalogItem(catalogItemId)
  return item?.recommended ?? false
}

export function formatBytes(bytes: number): string {
  if (bytes >= 1024 * 1024 * 1024) {
    return `${(bytes / 1024 / 1024 / 1024).toFixed(2)} GB`
  }
  if (bytes >= 1024 * 1024) {
    return `${(bytes / 1024 / 1024).toFixed(2)} MB`
  }
  return `${(bytes / 1024).toFixed(2)} KB`
}
