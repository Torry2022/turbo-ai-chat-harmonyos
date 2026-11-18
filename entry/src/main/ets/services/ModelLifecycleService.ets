import { ModelIdentityService, ModelIdentity } from './ModelIdentityService'
import { ModelUsageService, ModelLoadRecord } from './ModelUsageService'
import fs from '@ohos.file.fs'
import { common } from '@kit.AbilityKit'
import {
  BuiltinModelDownloadSpec,
  BuiltinModelFileSpec,
  BuiltinModelInstallProgress
} from '../models/BuiltinModelDownloadTypes'
import { GenerationSettings } from '../models/ChatTypes'
import { ModelImportResult, ModelImportScanResult } from '../models/ImportedModelTypes'
import { ModelProfile } from '../models/ModelProfile'
import { modelInstallDirectory, isPinnedModelDownload } from '../utils/modelCatalog'
import { formatError } from '../utils/formatters'
import { BuiltinModelInstallService } from './BuiltinModelInstallService'
import { ModelDirectoryPreflightService } from './ModelDirectoryPreflightService'
import { ModelImportService } from './ModelImportService'
import { NativeInferenceService } from './NativeInferenceService'

export interface ModelDeleteResult {
  deleted: boolean
  importedProfiles?: ModelProfile[]
}

export class ModelLifecycleService {
  private usage: ModelUsageService = new ModelUsageService()
  private filesDir: string = ''
  private identities: Map<string, ModelIdentity> = new Map()
  private identityReads: Map<string, number> = new Map()

  async refreshUsageIdentity(profile: ModelProfile, configPath?: string): Promise<void> {
    const serial = (this.identityReads.get(profile.id) ?? 0) + 1
    this.identityReads.set(profile.id, serial)
    const identity = await new ModelIdentityService().read(configPath ?? profile.configPath ??
      `${this.filesDir}/${profile.directoryName}/config.json`)
    if (this.identityReads.get(profile.id) === serial) this.identities.set(profile.id, identity)
  }

  modelFilesChanged(modelId: string): boolean {
    const previous = this.usage.latest(modelId)?.fileManifestSha256
    const current = this.identities.get(modelId)?.fileManifestSha256
    return previous !== undefined && current !== undefined && previous !== current
  }

  recentLoad(modelId: string): ModelLoadRecord | undefined { return this.usage.latestAttempt(modelId) }

  async recordSuccessfulLoad(profile: ModelProfile, startedAt: number, finishedAt: number,
    requestedThreads: number, type: 'chat' | 'decision' | 'rerank' | 'embedding', actualThreads?: number,
    configurationSha256?: string, fileManifestSha256?: string): Promise<void> {
    try {
      const runtime = this.nativeService.modelThreadInfo()
      if (configurationSha256 === undefined && fileManifestSha256 === undefined) {
        const identity = await new ModelIdentityService().read(profile.configPath ??
          `${this.filesDir}/${profile.directoryName}/config.json`)
        configurationSha256 = identity.configurationSha256
        fileManifestSha256 = identity.fileManifestSha256
      }
      this.identities.set(profile.id, { configurationSha256, fileManifestSha256 })
      const actual = type === 'chat' ? runtime.chat.actual : type === 'rerank' ? runtime.rerank.actual : actualThreads
      await this.usage.recordLoad({ outcome: 'loaded', modelId: profile.id, modelName: profile.name, loadedAt: finishedAt,
        loadDurationMs: finishedAt - startedAt, requestedThreads, actualThreads: actual, configurationSha256, fileManifestSha256,
        runtimeLibrarySha256: runtime.runtimeLibrarySha256 })
    } catch (_) { console.warn('本次模型加载记录未能保存') }
  }

  async recordFailedLoad(profile: ModelProfile, startedAt: number, requestedThreads: number): Promise<void> {
    const finishedAt = Date.now()
    try {
      await this.usage.recordLoad({ outcome: 'failed', modelId: profile.id, modelName: profile.name,
        loadedAt: finishedAt, loadDurationMs: finishedAt - startedAt, requestedThreads })
    } catch (_) { console.warn('本次模型加载记录未能保存') }
  }

  private loadedSourceRepository?: string
  private loadedSourceRevision?: string

  sourceRepository(): string | undefined { return this.loadedSourceRepository }
  sourceRevision(): string | undefined { return this.loadedSourceRevision }

  private loadedConfigurationSha256?: string
  private loadedFileManifestSha256?: string

  fileManifestSha256(): string | undefined { return this.loadedFileManifestSha256 }

  configurationSha256(): string | undefined { return this.loadedConfigurationSha256 }

  private nativeService: NativeInferenceService
  private installService: BuiltinModelInstallService
  private importService: ModelImportService
  private preflightService: ModelDirectoryPreflightService

  constructor(
    nativeService: NativeInferenceService,
    installService: BuiltinModelInstallService,
    importService: ModelImportService
  ) {
    this.nativeService = nativeService
    this.installService = installService
    this.importService = importService
    this.preflightService = new ModelDirectoryPreflightService()
  }

  async loadModel(
    filesDir: string,
    profile: ModelProfile,
    configPath: string,
    threadNum: number,
    maxNewTokens: number,
    settings: GenerationSettings
  ): Promise<boolean> {
    const loadStartedAt = Date.now()
    const expectedFiles = this.expectedFiles(filesDir, profile, configPath)
    const preflight = await this.preflightService.validate(configPath, profile.supportsImage, expectedFiles)
    if (!preflight.compatible) {
      await this.recordFailedLoad(profile, loadStartedAt, threadNum)
      throw new Error(`模型目录预检失败（${preflight.code}）：${preflight.message}`)
    }
    const identity = await new ModelIdentityService().read(configPath)
    let sourceRepository: string | undefined
    let sourceRevision: string | undefined
    const installed = profile.source === 'imported' ? undefined : this.installService.getInstalledDownloadSpec(profile)
    if (installed !== undefined && isPinnedModelDownload(installed) &&
      this.normalizedPath(configPath) === this.normalizedPath(`${filesDir}/${installed.directoryName}/config.json`)) {
      const repository = /^https:\/\/modelscope\.cn\/models\/([^/?#]+\/[^/?#]+)$/.exec(installed.sourceUrl)
      if (repository !== null) {
        sourceRepository = repository[1]
        sourceRevision = installed.files[0].url.substring(`${installed.sourceUrl}/resolve/`.length).split('/')[0]
      }
    }
    const configurationSha256 = identity.configurationSha256
    try {
      const loaded = await this.nativeService.loadModel(configPath, threadNum, maxNewTokens, settings)
      if (!loaded) {
        throw new Error('原生推理层未返回已加载状态。')
      }
      this.loadedSourceRepository = sourceRepository
      this.loadedSourceRevision = sourceRevision
      this.loadedConfigurationSha256 = configurationSha256
      this.loadedFileManifestSha256 = identity.fileManifestSha256
      const finishedAt = Date.now()
      await this.recordSuccessfulLoad(profile, loadStartedAt, finishedAt, threadNum, 'chat',
        undefined, configurationSha256, identity.fileManifestSha256)
      return true
    } catch (err) {
      await this.recordFailedLoad(profile, loadStartedAt, threadNum)
      this.loadedSourceRepository = undefined
      this.loadedSourceRevision = undefined
      this.loadedConfigurationSha256 = undefined
      this.loadedFileManifestSha256 = undefined
      await this.nativeService.reset()
      throw new Error(formatError(err as Object))
    }
  }

  async isInstalled(filesDir: string, profile: ModelProfile, configPath: string): Promise<boolean> {
    const expectedFiles = this.expectedFiles(filesDir, profile, configPath)
    const preflight = await this.preflightService.validate(configPath, profile.supportsImage, expectedFiles)
    return preflight.compatible
  }

  async installCatalogItem(
    context: common.UIAbilityContext,
    spec: BuiltinModelDownloadSpec,
    supportsImage: boolean,
    onProgress: (progress: BuiltinModelInstallProgress) => void
  ): Promise<void> {
    await this.installService.installCatalogItem(context, spec, onProgress)
    if (spec.modelType === 'decision') {
      const item = this.installService.getCatalogItem(spec.id)
      if (item === undefined || !await this.installService.isCatalogItemInstalled(context.filesDir, item)) {
        throw new Error('决策模型文件不完整')
      }
      return
    }
    await this.preflightService.requireCompatible(
      `${modelInstallDirectory(context.filesDir, spec)}/config.json`,
      supportsImage,
      spec.files, spec.modelType !== 'rerank' && spec.modelType !== 'embedding', spec.modelType === 'embedding'
    )
  }

  async deleteModel(
    filesDir: string,
    profile: ModelProfile,
    resetLoadedModel: boolean
  ): Promise<ModelDeleteResult> {
    if (resetLoadedModel) {
      await this.nativeService.reset()
    }
    if (profile.source === 'imported') {
      return {
        deleted: true,
        importedProfiles: await this.importService.deleteImportedProfile(filesDir, profile.id)
      }
    }
    return {
      deleted: await this.installService.deleteInstalled(filesDir, profile)
    }
  }

  async loadImportedProfiles(filesDir: string): Promise<ModelProfile[]> {
    this.filesDir = filesDir
    await this.usage.initialize(filesDir)
    return this.importService.loadImportedProfiles(filesDir)
  }

  importPickedModel(
    context: common.UIAbilityContext,
    existingProfiles: ModelProfile[],
    folder: boolean = false
  ): Promise<ModelImportResult | undefined> {
    return this.importService.pickAndImport(context, existingProfiles, folder)
  }

  scanPushedModels(filesDir: string, existingProfiles: ModelProfile[]): Promise<ModelImportScanResult> {
    return this.importService.scanPushedModelDirectories(filesDir, existingProfiles)
  }

  updateImportedProfile(
    filesDir: string,
    updated: ModelProfile
  ): Promise<ModelProfile[]> {
    return this.importService.updateImportedProfile(filesDir, updated)
  }

  reset(): Promise<void> {
    this.loadedSourceRepository = undefined
    this.loadedSourceRevision = undefined
    this.loadedConfigurationSha256 = undefined
    this.loadedFileManifestSha256 = undefined
    return this.nativeService.reset()
  }

  isLoaded(): boolean {
    return this.nativeService.isLoaded()
  }

  private expectedFiles(filesDir: string, profile: ModelProfile, configPath: string): BuiltinModelFileSpec[] {
    const catalogItem = this.installService.getDownloadSpec(profile)
    if (catalogItem === undefined) {
      return []
    }
    const expectedConfigPath = `${filesDir}/${catalogItem.directoryName}/config.json`
    return this.normalizedPath(expectedConfigPath) === this.normalizedPath(configPath) ? catalogItem.files : []
  }

  private normalizedPath(path: string): string {
    return path.replace(/\\/g, '/').toLowerCase()
  }
}
