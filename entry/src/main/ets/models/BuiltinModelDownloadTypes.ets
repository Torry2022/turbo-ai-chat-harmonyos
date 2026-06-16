export interface BuiltinModelFileSpec {
  relativePath: string
  sizeBytes: number
  url: string
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
): BuiltinModelDownloadSpec {
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
    sourceName: 'ModelScope',
    sourceUrl: `${MODELSCOPE_BASE_URL}/${repo}`,
    files: resolvedFiles,
    totalBytes
  }
}

export const BUILTIN_MODEL_DOWNLOADS: BuiltinModelDownloadSpec[] = [
  createSpec(
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
  ),
  createSpec(
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
  )
]

export function findBuiltinModelDownloadSpec(downloadId: string | undefined): BuiltinModelDownloadSpec | undefined {
  if (downloadId === undefined || downloadId.length <= 0) {
    return undefined
  }
  for (let index = 0; index < BUILTIN_MODEL_DOWNLOADS.length; index++) {
    if (BUILTIN_MODEL_DOWNLOADS[index].id === downloadId) {
      return BUILTIN_MODEL_DOWNLOADS[index]
    }
  }
  return undefined
}

export function formatBytes(bytes: number): string {
  if (bytes >= 1024 * 1024 * 1024) {
    return `${Math.round(bytes / 1024 / 1024 / 1024 * 10) / 10} GB`
  }
  if (bytes >= 1024 * 1024) {
    return `${Math.round(bytes / 1024 / 1024 * 10) / 10} MB`
  }
  return `${Math.round(bytes / 1024 * 10) / 10} KB`
}
