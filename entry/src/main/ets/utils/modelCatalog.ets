import {
  BuiltinModelFileSpec,
  CatalogGenerationDefaults,
  CatalogRuntimeSpec,
  ModelCatalogItem
} from '../models/BuiltinModelDownloadTypes'
import {
  InstalledCatalogManifest,
  RemoteCatalogFile,
  RemoteCatalogItem,
  RemoteModelCatalogManifest
} from '../models/ModelCatalogTypes'
import {
  CHAT_FORMAT_MNN_AUTO,
  GenerationDefaults,
  ModelProfile
} from '../models/ModelProfile'

const CATALOG_SCHEMA_VERSION: number = 1
const INSTALLED_CATALOG_SCHEMA_VERSION: number = 1
const MODELSCOPE_BASE_URL: string = 'https://modelscope.cn/models'
const ID_PATTERN: RegExp = /^[a-z0-9][a-z0-9._-]*$/
const DIRECTORY_PATTERN: RegExp = /^[A-Za-z0-9._-]+$/
const FILE_PATH_PATTERN: RegExp = /^[A-Za-z0-9._\/-]+$/
const REPO_PATTERN: RegExp = /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/
const REVISION_PATTERN: RegExp = /^[A-Za-z0-9._-]+$/

export function parseRemoteModelCatalog(text: string): RemoteModelCatalogManifest {
  const parsed = JSON.parse(text.replace(/^\uFEFF/, '')) as RemoteModelCatalogManifest
  requireCondition(parsed.schemaVersion === CATALOG_SCHEMA_VERSION, '模型广场清单版本不受支持')
  requireCondition(Number.isInteger(parsed.catalogVersion) && parsed.catalogVersion >= 1, '模型广场版本无效')
  requireCondition(typeof parsed.publishedAt === 'string', '模型广场发布时间无效')
  requireCondition(Array.isArray(parsed.hiddenIds), '模型广场下架列表无效')
  requireCondition(Array.isArray(parsed.items), '模型广场条目列表无效')

  const hiddenIds: string[] = []
  for (let index = 0; index < parsed.hiddenIds.length; index++) {
    const id = parsed.hiddenIds[index]
    requireCondition(isValidId(id), '模型广场下架 ID 无效')
    requireCondition(hiddenIds.indexOf(id) < 0, `模型广场下架 ID 重复：${id}`)
    hiddenIds.push(id)
  }

  const itemIds: string[] = []
  const directoryNames: string[] = []
  for (let index = 0; index < parsed.items.length; index++) {
    validateRemoteItem(parsed.items[index])
    requireCondition(itemIds.indexOf(parsed.items[index].id) < 0, `模型广场条目 ID 重复：${parsed.items[index].id}`)
    requireCondition(directoryNames.indexOf(parsed.items[index].directoryName) < 0,
      `模型广场目录名称重复：${parsed.items[index].directoryName}`)
    itemIds.push(parsed.items[index].id)
    directoryNames.push(parsed.items[index].directoryName)
  }
  for (let index = 0; index < hiddenIds.length; index++) {
    requireCondition(itemIds.indexOf(hiddenIds[index]) < 0, `模型广场条目不能同时上架和下架：${hiddenIds[index]}`)
  }
  return parsed
}

export function mergeRemoteModelCatalog(
  bundledItems: ModelCatalogItem[],
  manifest: RemoteModelCatalogManifest
): ModelCatalogItem[] {
  const merged = bundledItems.slice()
  for (let hiddenIndex = 0; hiddenIndex < manifest.hiddenIds.length; hiddenIndex++) {
    const id = manifest.hiddenIds[hiddenIndex]
    const existingIndex = findCatalogItemIndex(merged, id)
    if (existingIndex >= 0 && !merged[existingIndex].recommended) {
      merged.splice(existingIndex, 1)
    }
  }

  for (let itemIndex = 0; itemIndex < manifest.items.length; itemIndex++) {
    const remote = manifest.items[itemIndex]
    const existingIndex = findCatalogItemIndex(bundledItems, remote.id)
    const bundled = existingIndex >= 0 ? bundledItems[existingIndex] : undefined
    requireCondition(bundled !== undefined || remote.runtime !== undefined,
      `新市场模型缺少运行配置：${remote.id}`)
    if (bundled !== undefined) {
      requireCondition(remote.directoryName === bundled.directoryName,
        `预置市场模型不能在线修改安装目录：${remote.id}`)
      requireCondition(remote.supportsImage === bundled.supportsImage,
        `预置市场模型不能在线修改模态：${remote.id}`)
    } else {
      requireCondition(findCatalogDirectoryIndex(bundledItems, remote.directoryName) < 0,
        `新市场模型目录与预置模型冲突：${remote.id}`)
    }
    const item = toCatalogItem(remote, bundled)
    const mergedIndex = findCatalogItemIndex(merged, remote.id)
    if (mergedIndex >= 0) {
      merged[mergedIndex] = item
    } else {
      merged.push(item)
    }
  }
  return merged
}

export function catalogItemToProfile(item: ModelCatalogItem): ModelProfile | undefined {
  if (item.runtime === undefined) {
    return undefined
  }
  const runtime = item.runtime
  const generationDefaults = copyGenerationDefaults(runtime.generationDefaults)
  return {
    id: item.modelId,
    name: item.displayName,
    shortName: item.shortName,
    directoryName: item.directoryName,
    description: item.description,
    supportsImage: item.supportsImage,
    systemPrompt: runtime.systemPrompt,
    source: 'catalog',
    chatFormat: CHAT_FORMAT_MNN_AUTO,
    contextMessageLimit: runtime.contextMessageLimit,
    catalogItemId: item.id,
    downloadId: item.id,
    editable: false,
    removable: true,
    generationDefaults
  }
}

export function parseInstalledCatalog(text: string): ModelCatalogItem[] {
  const parsed = JSON.parse(text.replace(/^\uFEFF/, '')) as InstalledCatalogManifest
  requireCondition(parsed.schemaVersion === INSTALLED_CATALOG_SCHEMA_VERSION, '已安装市场模型清单版本不受支持')
  requireCondition(Array.isArray(parsed.items), '已安装市场模型清单无效')
  const result: ModelCatalogItem[] = []
  for (let index = 0; index < parsed.items.length; index++) {
    const item = parsed.items[index]
    validateInstalledItem(item)
    requireCondition(findCatalogItemIndex(result, item.id) < 0, `已安装市场模型 ID 重复：${item.id}`)
    result.push(item)
  }
  return result
}

export function serializeInstalledCatalog(items: ModelCatalogItem[]): string {
  const manifest: InstalledCatalogManifest = {
    schemaVersion: INSTALLED_CATALOG_SCHEMA_VERSION,
    items
  }
  return JSON.stringify(manifest, undefined, 2)
}

export function mergeCatalogItems(primary: ModelCatalogItem[], fallback: ModelCatalogItem[]): ModelCatalogItem[] {
  const merged = primary.slice()
  for (let index = 0; index < fallback.length; index++) {
    if (findCatalogItemIndex(merged, fallback[index].id) < 0) {
      merged.push(fallback[index])
    }
  }
  return merged
}

function validateRemoteItem(item: RemoteCatalogItem): void {
  requireCondition(isValidId(item.id), '模型广场条目 ID 无效')
  requireCondition(isSafeDirectoryName(item.directoryName), `模型目录名称无效：${item.id}`)
  requireCondition(isNonEmptyString(item.displayName), `模型显示名称无效：${item.id}`)
  requireCondition(isNonEmptyString(item.shortName), `模型短名称无效：${item.id}`)
  requireCondition(typeof item.description === 'string', `模型描述无效：${item.id}`)
  requireCondition(isNonEmptyString(item.provider), `模型提供方无效：${item.id}`)
  requireCondition(typeof item.supportsImage === 'boolean', `模型能力声明无效：${item.id}`)
  requireCondition(Array.isArray(item.capabilities) && item.capabilities.length > 0, `模型能力标签无效：${item.id}`)
  for (let index = 0; index < item.capabilities.length; index++) {
    requireCondition(isNonEmptyString(item.capabilities[index]), `模型能力标签无效：${item.id}`)
  }
  requireCondition(item.source !== undefined && item.source.type === 'modelscope', `模型来源不受支持：${item.id}`)
  requireCondition(REPO_PATTERN.test(item.source.repo), `ModelScope 仓库名称无效：${item.id}`)
  requireCondition(REVISION_PATTERN.test(item.source.revision), `ModelScope revision 无效：${item.id}`)
  requireCondition(Array.isArray(item.files) && item.files.length > 0, `模型文件列表为空：${item.id}`)
  validateRemoteFiles(item)
  if (item.runtime !== undefined) {
    validateRuntime(item.id, item.runtime)
  }
}

function validateRemoteFiles(item: RemoteCatalogItem): void {
  const paths: string[] = []
  let hasConfig = false
  let hasLlmConfig = false
  for (let index = 0; index < item.files.length; index++) {
    const file = item.files[index]
    requireCondition(isSafeRelativePath(file.relativePath), `模型文件路径无效：${item.id}`)
    requireCondition(Number.isInteger(file.sizeBytes) && file.sizeBytes > 0, `模型文件大小无效：${item.id}`)
    requireCondition(paths.indexOf(file.relativePath) < 0, `模型文件路径重复：${item.id}`)
    paths.push(file.relativePath)
    hasConfig = hasConfig || file.relativePath === 'config.json'
    hasLlmConfig = hasLlmConfig || file.relativePath === 'llm_config.json'
  }
  requireCondition(hasConfig && hasLlmConfig, `模型缺少基础配置文件：${item.id}`)
}

function validateRuntime(id: string, runtime: CatalogRuntimeSpec): void {
  requireCondition(isNonEmptyString(runtime.systemPrompt), `模型系统提示词无效：${id}`)
  requireCondition(Number.isInteger(runtime.contextMessageLimit) && runtime.contextMessageLimit >= 0,
    `模型上下文轮数无效：${id}`)
  if (runtime.generationDefaults !== undefined) {
    const defaults = runtime.generationDefaults
    validateOptionalNumber(defaults.maxNewTokens, `模型最大输出无效：${id}`, 1)
    validateOptionalNumber(defaults.temperature, `模型温度无效：${id}`, 0)
    validateOptionalNumber(defaults.topP, `模型 Top-P 无效：${id}`, 0)
    validateOptionalNumber(defaults.topK, `模型 Top-K 无效：${id}`, 1)
    validateOptionalNumber(defaults.repetitionPenalty, `模型重复惩罚无效：${id}`, 0)
    validateOptionalNumber(defaults.frequencyPenalty, `模型频率惩罚无效：${id}`, 0)
    validateOptionalNumber(defaults.presencePenalty, `模型存在惩罚无效：${id}`, 0)
    validateOptionalNumber(defaults.penaltyWindow, `模型惩罚窗口无效：${id}`, 0)
  }
}

function validateOptionalNumber(value: number | undefined, message: string, minimum: number): void {
  if (value === undefined) {
    return
  }
  requireCondition(Number.isFinite(value) && value >= minimum, message)
}

function validateInstalledItem(item: ModelCatalogItem): void {
  requireCondition(isValidId(item.id), '已安装市场模型 ID 无效')
  requireCondition(isSafeDirectoryName(item.directoryName), `已安装模型目录无效：${item.id}`)
  requireCondition(isNonEmptyString(item.displayName), `已安装模型名称无效：${item.id}`)
  requireCondition(Array.isArray(item.files) && item.files.length > 0, `已安装模型文件列表无效：${item.id}`)
  for (let index = 0; index < item.files.length; index++) {
    const file = item.files[index]
    requireCondition(isSafeRelativePath(file.relativePath), `已安装模型文件路径无效：${item.id}`)
    requireCondition(Number.isInteger(file.sizeBytes) && file.sizeBytes > 0, `已安装模型文件大小无效：${item.id}`)
    requireCondition(file.url.startsWith(`${MODELSCOPE_BASE_URL}/`), `已安装模型文件来源无效：${item.id}`)
  }
  if (item.runtime !== undefined) {
    validateRuntime(item.id, item.runtime)
  }
}

function toCatalogItem(remote: RemoteCatalogItem, bundled?: ModelCatalogItem): ModelCatalogItem {
  const files: BuiltinModelFileSpec[] = remote.files.map((file: RemoteCatalogFile): BuiltinModelFileSpec => {
    return {
      relativePath: file.relativePath,
      sizeBytes: file.sizeBytes,
      url: `${MODELSCOPE_BASE_URL}/${remote.source.repo}/resolve/${remote.source.revision}/${file.relativePath}`
    }
  })
  let totalBytes = 0
  files.forEach((file) => {
    totalBytes += file.sizeBytes
  })
  return {
    id: remote.id,
    modelId: bundled?.modelId ?? remote.id,
    directoryName: remote.directoryName,
    displayName: remote.displayName,
    shortName: remote.shortName,
    description: remote.description,
    provider: remote.provider,
    sourceName: 'ModelScope',
    sourceUrl: `${MODELSCOPE_BASE_URL}/${remote.source.repo}`,
    supportsImage: remote.supportsImage,
    capabilities: remote.capabilities,
    recommended: bundled?.recommended ?? false,
    files,
    totalBytes,
    runtime: remote.runtime ?? bundled?.runtime
  }
}

function copyGenerationDefaults(source?: CatalogGenerationDefaults): GenerationDefaults | undefined {
  if (source === undefined) {
    return undefined
  }
  return {
    maxNewTokens: source.maxNewTokens,
    temperature: source.temperature,
    topP: source.topP,
    topK: source.topK,
    repetitionPenalty: source.repetitionPenalty,
    frequencyPenalty: source.frequencyPenalty,
    presencePenalty: source.presencePenalty,
    penaltyWindow: source.penaltyWindow
  }
}

function findCatalogItemIndex(items: ModelCatalogItem[], id: string): number {
  for (let index = 0; index < items.length; index++) {
    if (items[index].id === id) {
      return index
    }
  }
  return -1
}

function isValidId(value: string): boolean {
  return typeof value === 'string' && ID_PATTERN.test(value) && !value.startsWith('imported-')
}

function isNonEmptyString(value: string): boolean {
  return typeof value === 'string' && value.trim().length > 0
}

function isSafeDirectoryName(value: string): boolean {
  return isNonEmptyString(value) && DIRECTORY_PATTERN.test(value) && value !== '.' && value !== '..'
}

function isSafeRelativePath(value: string): boolean {
  if (!isNonEmptyString(value) || !FILE_PATH_PATTERN.test(value) || value.startsWith('/') || value.indexOf('\\') >= 0) {
    return false
  }
  const segments = value.split('/')
  for (let index = 0; index < segments.length; index++) {
    if (segments[index].length <= 0 || segments[index] === '.' || segments[index] === '..') {
      return false
    }
  }
  return true
}

function findCatalogDirectoryIndex(items: ModelCatalogItem[], directoryName: string): number {
  for (let index = 0; index < items.length; index++) {
    if (items[index].directoryName === directoryName) {
      return index
    }
  }
  return -1
}

function requireCondition(condition: boolean, message: string): void {
  if (!condition) {
    throw new Error(message)
  }
}
