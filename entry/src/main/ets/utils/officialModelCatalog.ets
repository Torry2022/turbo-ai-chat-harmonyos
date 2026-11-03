import { BuiltinModelFileSpec, CatalogGenerationDefaults, ModelCatalogItem } from '../models/BuiltinModelDownloadTypes'
import { catalogCapabilityLabels } from './modelCatalog'
import { ModelFileSnapshot, inferSupportsImageFromLlmConfig, validateModelDirectorySnapshot } from './modelCompatibility'

interface OfficialModelSource {
  ModelScope?: string
}

interface OfficialModelEntry {
  modelName: string
  vendor?: string
  tags?: string[]
  sources: OfficialModelSource
  file_size: number
}

interface OfficialMarket {
  version: string
  models: OfficialModelEntry[]
  tagTranslations?: Record<string, string>
}

export interface OfficialCatalog {
  version: number
  items: ModelCatalogItem[]
}

interface ModelScopeFile {
  Type: string
  Path: string
  Size: number
  Revision?: string
}

interface ModelScopeCommit {
  Id?: string
  ShortId?: string
}

interface ModelScopeFilesData {
  Files: ModelScopeFile[]
  LatestCommitter: ModelScopeCommit
}

interface ModelScopeFilesResponse {
  Success: boolean
  Data: ModelScopeFilesData
}

export interface OfficialRepoFiles {
  revision: string
  files: BuiltinModelFileSpec[]
}

const MODEL_SCOPE_ROOT: string = 'https://modelscope.cn/models/'
const REPO_PATTERN: RegExp = /^MNN\/[A-Za-z0-9_.-]+$/
const COMMIT_PATTERN: RegExp = /^[a-f0-9]{8,64}$/

// These exports previously failed generation in this app; retain other official models.
const EXCLUDED_REPOS: string[] = ['mnn/qwen1.5-1.8b-chat-mnn', 'mnn/hunyuan-0.5b-instruct-mnn']

function translatedTag(translations: Record<string, string> | undefined, key: string, fallback: string): string {
  const value = translations?.[key]
  return typeof value === 'string' && value.trim().length > 0 ? value : fallback
}

export function parseOfficialModelCatalog(text: string, existing: ModelCatalogItem[]): OfficialCatalog {
  const parsed = JSON.parse(text) as OfficialMarket
  const version = Number(parsed.version)
  if ((typeof parsed.version !== 'string' && typeof parsed.version !== 'number') || !Number.isSafeInteger(version) || version < 1 || !Array.isArray(parsed.models) || parsed.models.length === 0) {
    throw new Error('MNN 官方模型目录格式无效')
  }
  let validEntries = 0
  const items: ModelCatalogItem[] = []
  const knownSources = existing.map((item: ModelCatalogItem) => item.sourceUrl.toLowerCase())
  const directories = existing.map((item: ModelCatalogItem) => item.directoryName.toLowerCase())
  for (const entry of parsed.models) {
    const repo = entry?.sources?.ModelScope ?? ''
    if (!REPO_PATTERN.test(repo) || !Number.isSafeInteger(entry.file_size) || entry.file_size <= 0) continue
    validEntries++
    if (EXCLUDED_REPOS.includes(repo.toLowerCase())) continue
    const directoryName = repo.split('/')[1]
    if (directoryName === '.' || directoryName === '..') continue
    const sourceUrl = `${MODEL_SCOPE_ROOT}${repo}`
    if (knownSources.includes(sourceUrl.toLowerCase()) || directories.includes(directoryName.toLowerCase())) continue
    const tags: string[] = Array.isArray(entry.tags) ? entry.tags.filter((tag: string) => typeof tag === 'string') : []
    if (tags.includes('ImageGen') || tags.includes('AudioGen') || tags.includes('NPU') ||
      (tags.includes('Audio') && !tags.includes('Vision')) || (tags.includes('Video') && !tags.includes('Vision')) ||
      /(?:embedding|rerank|guard|omni|diffusion|qnn|eagle|dflash|(?:^|-)base(?:-|$))/i.test(directoryName)) continue
    const displayName = directoryName.replace(/-mnn$/i, '')
    const id = `official-${directoryName.toLowerCase()}`
    if (existing.some((item: ModelCatalogItem) => item.id === id)) continue
    const supportsImage = tags.includes('Vision')
    const translations = parsed.tagTranslations
    const capabilities: string[] = [translatedTag(translations, 'Chat', '对话')]
    if (supportsImage) capabilities.push(translatedTag(translations, 'Vision', '图像理解'))
    if (tags.includes('Think')) capabilities.push(translatedTag(translations, 'Think', '深度思考'))
    if (tags.includes('Code')) capabilities.push(translatedTag(translations, 'Code', '代码'))
    if (tags.includes('Math')) capabilities.push(translatedTag(translations, 'Math', '数学'))
    items.push({
      id, modelId: id, directoryName, displayName, shortName: displayName,
      description: supportsImage ? '支持文本与图片输入的多模态对话模型。' : '文本对话模型。',
      provider: typeof entry.vendor === 'string' && entry.vendor.trim() ? entry.vendor : 'MNN',
      sourceName: 'ModelScope', sourceUrl, supportsImage, capabilities, recommended: false,
      files: [], totalBytes: entry.file_size
    })
    knownSources.push(sourceUrl.toLowerCase())
    directories.push(directoryName.toLowerCase())
  }
  if (validEntries === 0) throw new Error('官方目录没有有效的模型条目')
  return { version, items }
}

export function officialModelRepo(item: ModelCatalogItem): string {
  const repo = item.sourceUrl.startsWith(MODEL_SCOPE_ROOT) ? item.sourceUrl.substring(MODEL_SCOPE_ROOT.length) : ''
  if (!REPO_PATTERN.test(repo)) throw new Error('官方模型的魔搭仓库地址无效')
  return repo
}

function safePath(path: string): boolean {
  return typeof path === 'string' && /^[A-Za-z0-9._/-]+$/.test(path) &&
    path.split('/').every((part: string) => part.length > 0 && part !== '.' && part !== '..')
}

export function parseOfficialRepoFiles(text: string, repo: string): OfficialRepoFiles {
  if (!REPO_PATTERN.test(repo)) throw new Error('官方模型仓库名称无效')
  const response = JSON.parse(text) as ModelScopeFilesResponse
  const data = response.Data
  if (response.Success !== true || !Array.isArray(data?.Files)) throw new Error('无法读取魔搭模型文件清单')
  let revision = (data.LatestCommitter?.Id || data.LatestCommitter?.ShortId || '').toLowerCase()
  if (!COMMIT_PATTERN.test(revision)) throw new Error('魔搭未返回有效的模型提交版本')
  const commits: string[] = []
  for (const file of data.Files) {
    if (file.Type === 'blob' && typeof file.Revision === 'string' &&
      COMMIT_PATTERN.test(file.Revision.toLowerCase()) && file.Revision.toLowerCase().startsWith(revision) &&
      !commits.includes(file.Revision.toLowerCase())) commits.push(file.Revision.toLowerCase())
  }
  if (commits.length === 1) revision = commits[0]
  const files: BuiltinModelFileSpec[] = []
  for (const file of data.Files) {
    if (file.Type !== 'blob' || typeof file.Path !== 'string') continue
    const name = file.Path.split('/').pop() ?? ''
    if (!/^(?:config\.json|llm_config\.json|merges\.txt|vocab\.json|sentencepiece\.bpe\.model|tokenizer.*)$/.test(name) &&
      !/\.(?:mnn|mnn\.weight|bin|mtok)$/.test(name)) continue
    if (!safePath(file.Path) || !Number.isSafeInteger(file.Size) || file.Size <= 0 ||
      files.some((item: BuiltinModelFileSpec) => item.relativePath === file.Path)) {
      throw new Error('魔搭模型文件路径或大小无效')
    }
    files.push({ relativePath: file.Path, sizeBytes: file.Size,
      url: `${MODEL_SCOPE_ROOT}${repo}/resolve/${revision}/${file.Path}` })
  }
  if (!files.some((file: BuiltinModelFileSpec) => file.relativePath === 'config.json') ||
    !files.some((file: BuiltinModelFileSpec) => file.relativePath === 'llm_config.json')) {
    throw new Error('模型仓库缺少 config.json 或 llm_config.json')
  }
  files.sort((a: BuiltinModelFileSpec, b: BuiltinModelFileSpec) => a.relativePath.localeCompare(b.relativePath))
  return { revision, files }
}

export function resolveOfficialCatalogItem(
  item: ModelCatalogItem, files: BuiltinModelFileSpec[], configText: string, llmConfigText: string
): ModelCatalogItem {
  const supportsImage = inferSupportsImageFromLlmConfig(llmConfigText)
  const snapshots: ModelFileSnapshot[] = files.map((file: BuiltinModelFileSpec): ModelFileSnapshot => {
    return { relativePath: file.relativePath, sizeBytes: file.sizeBytes }
  })
  const result = validateModelDirectorySnapshot({ configText, llmConfigText, files: snapshots,
    expectedFiles: [], supportsImage, requireChatTemplate: item.modelType !== 'rerank' })
  if (!result.compatible) throw new Error(`模型目录预检失败：${result.message}`)
  const config = JSON.parse(configText) as Record<string, Object>
  const defaults: CatalogGenerationDefaults = {}
  if (typeof config['temperature'] === 'number' && Number.isFinite(config['temperature']) &&
    (config['temperature'] as number) > 0) defaults.temperature = config['temperature'] as number
  if (config['top_p'] === undefined) config['top_p'] = config['topP']
  if (config['top_k'] === undefined) config['top_k'] = config['topK']
  if (config['repetition_penalty'] === undefined) config['repetition_penalty'] = config['penalty']
  if (typeof config['top_p'] === 'number' && Number.isFinite(config['top_p']) &&
    (config['top_p'] as number) > 0 && (config['top_p'] as number) <= 1) defaults.topP = config['top_p'] as number
  if (typeof config['top_k'] === 'number' && Number.isInteger(config['top_k']) &&
    (config['top_k'] as number) > 0) defaults.topK = config['top_k'] as number
  if (typeof config['repetition_penalty'] === 'number' && Number.isFinite(config['repetition_penalty']) &&
    (config['repetition_penalty'] as number) > 0) defaults.repetitionPenalty = config['repetition_penalty'] as number
  let totalBytes = 0
  files.forEach((file: BuiltinModelFileSpec) => { totalBytes += file.sizeBytes })
  return { id: item.id, modelId: item.modelId, modelType: item.modelType, directoryName: item.directoryName,
    displayName: item.displayName, shortName: item.shortName, description: item.description,
    provider: item.provider, sourceName: item.sourceName, sourceUrl: item.sourceUrl,
    recommended: item.recommended, minAppVersionCode: item.minAppVersionCode, files, totalBytes, supportsImage,
    capabilities: supportsImage ? ['对话', '图像理解', ...catalogCapabilityLabels(item.capabilities).filter((value: string) => value !== '对话' && value !== '图像理解')] :
      catalogCapabilityLabels(item.capabilities).filter((value: string) => value !== '图像理解'),
    runtime: item.modelType === 'rerank' ? undefined :
      { systemPrompt: '你是一个有帮助的助手。请使用简体中文回答。', contextMessageLimit: 6, generationDefaults: defaults } }
}

interface OfficialRerankerEntry {
  Name: string
  Path: string
  StorageSize: number
  IsAccessible?: number
  IsPublished?: number
}

interface OfficialRerankerData {
  Models: OfficialRerankerEntry[]
  TotalCount: number
}

interface OfficialRerankerResponse {
  Data: OfficialRerankerData
}

export function parseOfficialRerankerCatalog(text: string): ModelCatalogItem[] {
  const response = JSON.parse(text) as OfficialRerankerResponse
  const data = response.Data
  if (!Array.isArray(data?.Models) || !Number.isSafeInteger(data.TotalCount) ||
    data.TotalCount < 0 || data.TotalCount > data.Models.length) throw new Error('重排模型目录格式无效或不完整')
  const items: ModelCatalogItem[] = []
  for (const model of data.Models) {
    if (model?.Path !== 'MNN' || typeof model.Name !== 'string' ||
      !/^Qwen3-Reranker-[A-Za-z0-9._-]+$/.test(model.Name) || model.Name.includes('..') ||
      model.IsAccessible === 0 || model.IsPublished === 0 ||
      !Number.isSafeInteger(model.StorageSize) || model.StorageSize <= 0) continue
    const id = `official-${model.Name.toLowerCase()}`
    if (items.some((item: ModelCatalogItem) => item.id === id)) continue
    const name = model.Name.replace(/-mnn$/i, '')
    items.push({ id, modelId: id, modelType: 'rerank', directoryName: model.Name,
      displayName: name, shortName: name, description: '对查询与候选文本的相关性评分并排序。',
      provider: 'Qwen', sourceName: 'ModelScope', sourceUrl: `${MODEL_SCOPE_ROOT}MNN/${model.Name}`,
      supportsImage: false, capabilities: [], recommended: false, files: [], totalBytes: model.StorageSize })
  }
  items.sort((a: ModelCatalogItem, b: ModelCatalogItem) => a.totalBytes - b.totalBytes)
  return items
}
