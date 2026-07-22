import fs from '@ohos.file.fs'
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
import { ModelProfile } from '../models/ModelProfile'
import {
  catalogItemToProfile,
  mergeCatalogItems,
  mergeRemoteModelCatalog,
  parseInstalledCatalog,
  parseRemoteModelCatalog,
  serializeInstalledCatalog
} from '../utils/modelCatalog'

export const REMOTE_MODEL_CATALOG_URL: string =
  'https://raw.githubusercontent.com/Torry2022/turbo-ai-chat-harmonyos/main/model-catalog/catalog.json'

const CATALOG_CACHE_FILE: string = 'model-catalog-cache.json'
const INSTALLED_CATALOG_FILE: string = 'model-catalog-installs.json'

export class ModelCatalogService {
  private marketItems: ModelCatalogItem[] = MODEL_CATALOG_ITEMS.slice()
  private installedItems: ModelCatalogItem[] = []
  private catalogVersion: number = 0
  private publishedAt: string = ''
  private source: string = '内置目录'

  items(): ModelCatalogItem[] {
    return this.marketItems
  }

  knownItems(): ModelCatalogItem[] {
    return mergeCatalogItems(mergeCatalogItems(this.installedItems, this.marketItems), MODEL_CATALOG_ITEMS)
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
    return this.findItem(this.marketItems, id)
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

  async load(filesDir: string): Promise<ModelCatalogLoadResult> {
    await this.loadInstalledItems(filesDir)
    const cachePath = `${filesDir}/${CATALOG_CACHE_FILE}`
    await this.recoverAtomicFile(cachePath)
    if (!await this.exists(cachePath)) {
      return this.result('内置目录', '正在使用安装包内置模型目录')
    }
    try {
      const text = await fs.readText(cachePath)
      const manifest = parseRemoteModelCatalog(text)
      this.applyManifest(manifest, '本地缓存')
      return this.result('本地缓存', '已载入上次更新的模型目录')
    } catch (_) {
      this.marketItems = MODEL_CATALOG_ITEMS.slice()
      this.catalogVersion = 0
      this.publishedAt = ''
      this.source = '内置目录'
      return this.result('内置目录', '模型目录缓存无效，已使用安装包内置目录')
    }
  }

  async refresh(filesDir: string): Promise<ModelCatalogRefreshResult> {
    const request = http.createHttp()
    try {
      const response = await request.request(REMOTE_MODEL_CATALOG_URL, {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.STRING,
        usingCache: false,
        connectTimeout: 15000,
        readTimeout: 30000,
        header: {
          'Accept': 'application/json',
          'User-Agent': 'Turbo-AI-Chat-HarmonyOS'
        }
      })
      if (response.responseCode < 200 || response.responseCode >= 300) {
        throw new Error(`HTTP ${response.responseCode}`)
      }
      if (typeof response.result !== 'string') {
        throw new Error('服务器未返回文本目录')
      }
      const manifest = parseRemoteModelCatalog(response.result)
      if (manifest.catalogVersion <= this.catalogVersion) {
        return {
          updated: false,
          source: this.source,
          catalogVersion: this.catalogVersion,
          publishedAt: this.publishedAt,
          message: manifest.catalogVersion === this.catalogVersion ?
            '模型广场已是最新' : '在线目录版本较旧，已保留当前目录'
        }
      }
      const nextItems = mergeRemoteModelCatalog(MODEL_CATALOG_ITEMS, manifest)
      await this.writeTextAtomically(`${filesDir}/${CATALOG_CACHE_FILE}`, JSON.stringify(manifest, undefined, 2))
      this.marketItems = nextItems
      this.catalogVersion = manifest.catalogVersion
      this.publishedAt = manifest.publishedAt
      this.source = '在线目录'
      return {
        updated: true,
        source: this.source,
        catalogVersion: this.catalogVersion,
        publishedAt: this.publishedAt,
        message: '模型广场已更新'
      }
    } finally {
      request.destroy()
    }
  }

  async recordInstalled(filesDir: string, item: ModelCatalogItem): Promise<void> {
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
    if (!await this.exists(path)) {
      this.installedItems = []
      return
    }
    try {
      this.installedItems = parseInstalledCatalog(await fs.readText(path))
    } catch (_) {
      this.installedItems = []
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
      source,
      catalogVersion: this.catalogVersion,
      publishedAt: this.publishedAt,
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
