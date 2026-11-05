import { hilog } from '@kit.PerformanceAnalysisKit'
import fs from '@ohos.file.fs'
import { formatError } from '../utils/formatters'
import http from '@ohos.net.http'
import {
  MODEL_CATALOG_ITEMS,
  ModelCatalogItem
} from '../models/BuiltinModelDownloadTypes'
import {
  ModelCatalogLoadResult,
  ModelCatalogRefreshResult,
  RemoteModelCatalogManifest
} from '../models/ModelCatalogTypes'
import { LAYA_DOWNLOAD_SPEC } from '../models/LayaModelConfig'
import { ModelProfile } from '../models/ModelProfile'
import { ModelDescriptionManifest, descriptionRepo, parseModelDescriptions } from '../utils/modelDescriptions'
import { OfficialCatalog, officialModelRepo, officialPackageCompatibilityMessage, parseOfficialModelCatalog, parseOfficialRerankerCatalog, parseOfficialRepoFiles, resolveOfficialCatalogItem } from '../utils/officialModelCatalog'
import {
  catalogItemToProfile,
  mergeCatalogItems,
  mergeRemoteModelCatalog,
  parseInstalledCatalog,
  parseRemoteModelCatalog,
  serializeInstalledCatalog
} from '../utils/modelCatalog'

export const REMOTE_MODEL_CATALOG_URL: string =
  'https://raw.githubusercontent.com/Torry2022/turbo-ai-chat-harmonyos/main/model-catalog/catalog-v2.json'

const REMOTE_MODEL_CATALOG_API_URL: string =
  'https://api.github.com/repos/Torry2022/turbo-ai-chat-harmonyos/contents/model-catalog/catalog-v2.json?ref=main'

export const OFFICIAL_MODEL_CATALOG_URL: string = 'https://meta.alicdn.com/data/mnn/apis/model_market.json'
const OFFICIAL_CATALOG_CACHE_FILE: string = 'model-catalog-official.json'
const RERANKER_CATALOG_CACHE_FILE: string = 'model-catalog-rerank.json'

const OFFICIAL_RESOLVED_CACHE_FILE: string = 'model-catalog-official-files.json'
const DESCRIPTION_CACHE_FILE: string = 'model-descriptions-zh-v1.json'
const DESCRIPTION_URL: string =
  'https://raw.githubusercontent.com/Torry2022/turbo-ai-chat-harmonyos/main/entry/src/main/resources/rawfile/model_descriptions_zh.json'
const DESCRIPTION_API_URL: string =
  'https://api.github.com/repos/Torry2022/turbo-ai-chat-harmonyos/contents/entry/src/main/resources/rawfile/model_descriptions_zh.json?ref=main'

const CATALOG_CACHE_FILE: string = 'model-catalog-cache-v2.json'
const INSTALLED_CATALOG_FILE: string = 'model-catalog-installs-v2.json'
const LEGACY_INSTALLED_CATALOG_FILE: string = 'model-catalog-installs.json'

export class ModelCatalogService {
  private descriptionVersion: number = 0
  private descriptions: Record<string, string> = {}
  private rerankerItems: ModelCatalogItem[] = []
  private rerankerCatalogStatus: string = '正在读取重排模型目录...'
  private officialItems: ModelCatalogItem[] = []
  private resolvedItems: ModelCatalogItem[] = []
  private officialVersion: number = 0
  private marketItems: ModelCatalogItem[] = MODEL_CATALOG_ITEMS.slice()
  private installedItems: ModelCatalogItem[] = []
  private catalogVersion: number = 0
  private publishedAt: string = ''
  private source: string = '内置目录'

  items(): ModelCatalogItem[] {
    const official = this.officialItems.concat(this.rerankerItems).map((item: ModelCatalogItem) =>
      this.findItem(this.resolvedItems, item.id) ?? item)
    return mergeCatalogItems(mergeCatalogItems(official, this.marketItems), [LAYA_DOWNLOAD_SPEC])
      .map((item: ModelCatalogItem): ModelCatalogItem => {
        const description = this.descriptions[descriptionRepo(item.sourceUrl)]
        if (description === undefined) return item
        return { id: item.id, modelId: item.modelId, modelType: item.modelType,
          minAppVersionCode: item.minAppVersionCode, directoryName: item.directoryName,
          displayName: item.displayName, shortName: item.shortName, description,
          provider: item.provider, sourceName: item.sourceName, sourceUrl: item.sourceUrl,
          files: item.files, totalBytes: item.totalBytes, supportsImage: item.supportsImage,
          capabilities: item.capabilities, recommended: item.recommended, runtime: item.runtime }
      })
  }

  knownItems(): ModelCatalogItem[] {
    return mergeCatalogItems(mergeCatalogItems(this.installedItems, this.items()), MODEL_CATALOG_ITEMS)
  }

  bundledItems(): ModelCatalogItem[] {
    return MODEL_CATALOG_ITEMS
  }

  profiles(): ModelProfile[] {
    const profiles: ModelProfile[] = []
    const items = this.knownItems()
    for (let index = 0; index < items.length; index++) {
      const profile = catalogItemToProfile(items[index])
      if (profile !== undefined) {
        profiles.push(profile)
      }
    }
    return profiles
  }

  findMarketItem(id: string | undefined): ModelCatalogItem | undefined {
    return this.findItem(this.items(), id)
  }

  findInstallItem(id: string | undefined): ModelCatalogItem | undefined {
    const installed = this.findItem(this.installedItems, id)
    if (installed !== undefined) {
      return installed
    }
    const market = this.findMarketItem(id)
    if (market !== undefined) {
      return market
    }
    return this.findItem(MODEL_CATALOG_ITEMS, id)
  }

  hasInstalledSnapshot(id: string): boolean {
    return this.findItem(this.installedItems, id) !== undefined
  }

  async load(filesDir: string, bundledDescriptions: string = ''): Promise<ModelCatalogLoadResult> {
    if (bundledDescriptions.length > 0) {
      try { this.applyDescriptions(parseModelDescriptions(bundledDescriptions)) } catch (_) {
        hilog.warn(0, 'TurboAIChat', 'Ignoring invalid bundled model descriptions')
      }
    }
    const descriptionPath = `${filesDir}/${DESCRIPTION_CACHE_FILE}`
    try {
      await this.recoverAtomicFile(descriptionPath)
      if (await this.exists(descriptionPath)) {
        this.applyDescriptions(parseModelDescriptions(await fs.readText(descriptionPath)))
      }
    } catch (_) {
      hilog.warn(0, 'TurboAIChat', 'Ignoring unreadable or invalid model description cache')
    }
    await this.loadInstalledItems(filesDir)
    const cachePath = `${filesDir}/${CATALOG_CACHE_FILE}`
    await this.recoverAtomicFile(cachePath)
    if (await this.exists(cachePath)) {
      try {
        this.applyManifest(parseRemoteModelCatalog(await fs.readText(cachePath)), '本地缓存')
      } catch (_) {
        hilog.warn(0, 'TurboAIChat', 'Ignoring invalid supplemental catalog cache')
      }
    }
    const resolvedPath = `${filesDir}/${OFFICIAL_RESOLVED_CACHE_FILE}`
    await this.recoverAtomicFile(resolvedPath)
    if (await this.exists(resolvedPath)) {
      try { this.resolvedItems = parseInstalledCatalog(await fs.readText(resolvedPath)) } catch (_) {
        this.resolvedItems = []
      }
    }
    const officialPath = `${filesDir}/${OFFICIAL_CATALOG_CACHE_FILE}`
    await this.recoverAtomicFile(officialPath)
    if (await this.exists(officialPath)) {
      try { this.applyOfficialCatalog(parseOfficialModelCatalog(await fs.readText(officialPath), this.marketItems)) } catch (_) {
        hilog.warn(0, 'TurboAIChat', 'Ignoring invalid official catalog cache')
      }
    }
    const rerankerPath = `${filesDir}/${RERANKER_CATALOG_CACHE_FILE}`
    await this.recoverAtomicFile(rerankerPath)
    if (await this.exists(rerankerPath)) {
      try {
        this.rerankerItems = parseOfficialRerankerCatalog(await fs.readText(rerankerPath))
        this.rerankerCatalogStatus = '已载入缓存的重排模型目录'
      } catch (_) { this.rerankerCatalogStatus = '重排模型目录缓存无效，请刷新重试' }
    } else { this.rerankerCatalogStatus = '尚未获取重排模型目录，请刷新' }
    return this.result(this.source, this.officialVersion > 0 ? '已载入缓存的官方模型目录' :
      this.catalogVersion > 0 ? '已载入上次更新的模型目录' : '正在使用安装包内置模型目录')
  }

  async refresh(filesDir: string): Promise<ModelCatalogRefreshResult> {
    let officialError: Error | undefined = undefined
    let supplementalError: Error | undefined = undefined
    let rerankerError: Error | undefined = undefined
    let updated = false
    await Promise.all([
      this.refreshOfficial(filesDir).then((changed: boolean) => { updated = updated || changed })
        .catch((err: Error) => {
          officialError = err
          hilog.warn(0, 'TurboAIChat', 'Official catalog refresh failed: %{public}s', formatError(err))
        }),
      this.refreshSupplemental(filesDir).then((changed: boolean) => { updated = updated || changed })
        .catch((err: Error) => {
          supplementalError = err
          hilog.warn(0, 'TurboAIChat', 'Supplemental catalog refresh failed: %{public}s', formatError(err))
        }),
      this.refreshRerankers(filesDir).then((changed: boolean) => { updated = updated || changed })
        .catch((err: Error) => {
          rerankerError = err
          this.rerankerCatalogStatus = this.rerankerItems.length > 0 ? '重排目录更新失败，已保留缓存' : '重排目录更新失败，请重试'
          hilog.warn(0, 'TurboAIChat', 'Reranker catalog refresh failed: %{public}s', formatError(err))
        }),
      this.refreshDescriptions(filesDir).then((changed: boolean) => { updated = updated || changed })
        .catch((err: Error) => {
          hilog.warn(0, 'TurboAIChat', 'Model description refresh failed: %{public}s', formatError(err))
        })
    ])
    if (officialError !== undefined && supplementalError !== undefined && rerankerError !== undefined) throw officialError as Error
    const result = this.result(this.source, officialError !== undefined ?
      (this.officialVersion > 0 ? '官方目录更新失败，已保留缓存' : '官方目录暂不可用，已使用补充目录') :
      updated ? '模型广场已更新' : '模型广场已是最新')
    return { source: result.source, catalogVersion: result.catalogVersion,
      publishedAt: result.publishedAt, message: result.message, updated }
  }

  rerankerStatus(): string { return this.rerankerCatalogStatus }

  private applyDescriptions(manifest: ModelDescriptionManifest): void {
    if (manifest.descriptionVersion < this.descriptionVersion) return
    const descriptions: Record<string, string> = {}
    for (const entry of manifest.entries) descriptions[entry.repo.toLowerCase()] = entry.description.trim()
    this.descriptions = descriptions
    this.descriptionVersion = manifest.descriptionVersion
  }

  private async refreshDescriptions(filesDir: string): Promise<boolean> {
    let text: string
    try {
      text = await this.requestCatalog(DESCRIPTION_URL, 'application/json', 5000)
    } catch (_) {
      text = await this.requestCatalog(DESCRIPTION_API_URL, 'application/vnd.github.raw+json', 5000)
    }
    const manifest = parseModelDescriptions(text)
    if (manifest.descriptionVersion <= this.descriptionVersion) return false
    await this.writeTextAtomically(`${filesDir}/${DESCRIPTION_CACHE_FILE}`, text)
    this.applyDescriptions(manifest)
    return true
  }

  private async refreshRerankers(filesDir: string): Promise<boolean> {
    const text = await this.requestCatalog('https://modelscope.cn/api/v1/models', 'application/json', 15000,
      http.RequestMethod.PUT, JSON.stringify({ Path: 'MNN', Name: 'Qwen3-Reranker', PageNumber: 1, PageSize: 100 }))
    const items = parseOfficialRerankerCatalog(text)
    const changed = JSON.stringify(items) !== JSON.stringify(this.rerankerItems)
    await this.writeTextAtomically(`${filesDir}/${RERANKER_CATALOG_CACHE_FILE}`, text)
    this.rerankerItems = items
    this.rerankerCatalogStatus = '重排模型目录已更新'
    return changed
  }

  private async refreshOfficial(filesDir: string): Promise<boolean> {
    const text = await this.requestCatalog(OFFICIAL_MODEL_CATALOG_URL, 'application/json')
    const catalog = parseOfficialModelCatalog(text, this.marketItems)
    if (catalog.version < this.officialVersion) throw new Error('官方目录版本较旧，已保留当前目录')
    const changed = catalog.version !== this.officialVersion
    await this.writeTextAtomically(`${filesDir}/${OFFICIAL_CATALOG_CACHE_FILE}`, text)
    this.applyOfficialCatalog(catalog)
    return changed
  }

  private async refreshSupplemental(filesDir: string): Promise<boolean> {
    let text: string
    try {
      text = await this.requestCatalog(REMOTE_MODEL_CATALOG_URL, 'application/json', 5000)
    } catch (_) {
      text = await this.requestCatalog(REMOTE_MODEL_CATALOG_API_URL, 'application/vnd.github.raw+json', 5000)
    }
    const manifest = parseRemoteModelCatalog(text)
    if (manifest.catalogVersion <= this.catalogVersion) return false
    const nextItems = mergeRemoteModelCatalog(MODEL_CATALOG_ITEMS, manifest)
    await this.writeTextAtomically(`${filesDir}/${CATALOG_CACHE_FILE}`, JSON.stringify(manifest, undefined, 2))
    this.marketItems = nextItems
    this.catalogVersion = manifest.catalogVersion
    this.publishedAt = manifest.publishedAt
    this.source = '在线目录'
    // A supplemental update may claim a repository that was discovered earlier.
    this.officialItems = this.officialItems.filter((item: ModelCatalogItem) =>
      !this.marketItems.some((known: ModelCatalogItem) =>
        known.sourceUrl.toLowerCase() === item.sourceUrl.toLowerCase() ||
        known.directoryName.toLowerCase() === item.directoryName.toLowerCase()))
    return true
  }

  private applyOfficialCatalog(catalog: OfficialCatalog): void {
    this.officialVersion = catalog.version
    this.officialItems = catalog.items.filter((item: ModelCatalogItem) =>
      !this.marketItems.some((known: ModelCatalogItem) =>
        known.sourceUrl.toLowerCase() === item.sourceUrl.toLowerCase() ||
        known.directoryName.toLowerCase() === item.directoryName.toLowerCase()))
  }

  async resolveInstallItem(filesDir: string, id: string): Promise<ModelCatalogItem> {
    const item = this.findMarketItem(id) ?? this.findInstallItem(id)
    if (item === undefined) throw new Error('模型广场条目不存在')
    if (item.files.length > 0 && officialPackageCompatibilityMessage(item, item.files).length <= 0) return item
    const repo = officialModelRepo(item)
    const text = await this.requestCatalog(
      `https://modelscope.cn/api/v1/models/${repo}/repo/files?Revision=master&Recursive=true`, 'application/json')
    const listing = parseOfficialRepoFiles(text, repo)
    const root = `https://modelscope.cn/models/${repo}/resolve/${listing.revision}`
    const config = await this.requestCatalog(`${root}/config.json`, 'application/json')
    const llmConfig = await this.requestCatalog(`${root}/llm_config.json`, 'application/json')
    const resolved = resolveOfficialCatalogItem(item, listing.files, config, llmConfig)
    const next = this.resolvedItems.filter((value: ModelCatalogItem) => value.id !== id)
    next.push(resolved)
    await this.writeTextAtomically(`${filesDir}/${OFFICIAL_RESOLVED_CACHE_FILE}`, serializeInstalledCatalog(next))
    this.resolvedItems = next
    return resolved
  }

  private async requestCatalog(url: string, accept: string, timeout: number = 15000,
    method: http.RequestMethod = http.RequestMethod.GET, extraData?: string): Promise<string> {
    const request = http.createHttp()
    try {
      const response = await request.request(url, {
        method, extraData,
        expectDataType: http.HttpDataType.STRING,
        usingCache: false,
        connectTimeout: Math.min(10000, timeout),
        readTimeout: timeout,
        header: {
          'Accept': accept,
          'Content-Type': 'application/json',
          'User-Agent': 'Turbo-AI-Chat-HarmonyOS'
        }
      })
      if (response.responseCode < 200 || response.responseCode >= 300) {
        if (response.responseCode === 404) {
          throw new Error('模型目录或配置已不可用（HTTP 404），请刷新模型广场后重试。')
        }
        throw new Error(`HTTP ${response.responseCode}`)
      }
      if (typeof response.result !== 'string') {
        throw new Error('服务器未返回文本目录')
      }
      hilog.info(0, 'TurboAIChat', 'Model catalog received from %{public}s', url)
      return response.result
    } finally {
      request.destroy()
    }
  }

  async recordInstalled(filesDir: string, item: ModelCatalogItem): Promise<void> {
    if (item.files.length === 0) throw new Error('模型文件信息尚未解析，不能记录为已安装')
    const next = this.installedItems.slice()
    const existingIndex = this.findItemIndex(next, item.id)
    if (existingIndex >= 0) {
      next[existingIndex] = item
    } else {
      next.push(item)
    }
    await this.writeTextAtomically(`${filesDir}/${INSTALLED_CATALOG_FILE}`, serializeInstalledCatalog(next))
    this.installedItems = next
  }

  async removeInstalled(filesDir: string, id: string): Promise<void> {
    const next = this.installedItems.filter((item: ModelCatalogItem) => item.id !== id)
    await this.writeTextAtomically(`${filesDir}/${INSTALLED_CATALOG_FILE}`, serializeInstalledCatalog(next))
    this.installedItems = next
  }

  private async loadInstalledItems(filesDir: string): Promise<void> {
    const path = `${filesDir}/${INSTALLED_CATALOG_FILE}`
    await this.recoverAtomicFile(path)
    let readPath = path
    if (!await this.exists(path)) {
      // Read the old snapshot once, without modifying files used by older apps.
      readPath = `${filesDir}/${LEGACY_INSTALLED_CATALOG_FILE}`
      if (!await this.exists(readPath)) {
        readPath = `${readPath}.bak`
      }
      if (!await this.exists(readPath)) {
        this.installedItems = []
        return
      }
    }
    try {
      this.installedItems = parseInstalledCatalog(await fs.readText(readPath))
    } catch (_) {
      this.installedItems = []
      return
    }
    if (readPath !== path) {
      await this.writeTextAtomically(path, serializeInstalledCatalog(this.installedItems))
    }
  }

  private applyManifest(manifest: RemoteModelCatalogManifest, source: string): void {
    this.marketItems = mergeRemoteModelCatalog(MODEL_CATALOG_ITEMS, manifest)
    this.catalogVersion = manifest.catalogVersion
    this.publishedAt = manifest.publishedAt
    this.source = source
  }

  private result(source: string, message: string): ModelCatalogLoadResult {
    return {
      source: this.officialVersion > 0 ? 'MNN 官方目录' : source,
      catalogVersion: this.officialVersion > 0 ? this.officialVersion : this.catalogVersion,
      publishedAt: this.officialVersion > 0 ? '' : this.publishedAt,
      message
    }
  }

  private findItem(items: ModelCatalogItem[], id: string | undefined): ModelCatalogItem | undefined {
    if (id === undefined || id.length <= 0) {
      return undefined
    }
    const index = this.findItemIndex(items, id)
    return index >= 0 ? items[index] : undefined
  }

  private findItemIndex(items: ModelCatalogItem[], id: string): number {
    for (let index = 0; index < items.length; index++) {
      if (items[index].id === id) {
        return index
      }
    }
    return -1
  }

  private async writeTextAtomically(path: string, text: string): Promise<void> {
    const tempPath = `${path}.tmp`
    const backupPath = `${path}.bak`
    const file = fs.openSync(tempPath, fs.OpenMode.WRITE_ONLY | fs.OpenMode.CREATE | fs.OpenMode.TRUNC)
    try {
      fs.writeSync(file.fd, text)
    } finally {
      fs.closeSync(file)
    }
    if (await this.exists(backupPath)) {
      await fs.unlink(backupPath)
    }
    if (await this.exists(path)) {
      await fs.rename(path, backupPath)
    }
    try {
      await fs.rename(tempPath, path)
      if (await this.exists(backupPath)) {
        await fs.unlink(backupPath)
      }
    } catch (err) {
      if (await this.exists(backupPath) && !await this.exists(path)) {
        await fs.rename(backupPath, path)
      }
      throw new Error(`${err}`)
    }
  }

  private async recoverAtomicFile(path: string): Promise<void> {
    const tempPath = `${path}.tmp`
    const backupPath = `${path}.bak`
    if (!await this.exists(path) && await this.exists(backupPath)) {
      await fs.rename(backupPath, path)
    }
    if (await this.exists(tempPath)) {
      await fs.unlink(tempPath)
    }
    if (await this.exists(path) && await this.exists(backupPath)) {
      await fs.unlink(backupPath)
    }
  }

  private async exists(path: string): Promise<boolean> {
    try {
      return await fs.access(path)
    } catch (_) {
      return false
    }
  }
}
