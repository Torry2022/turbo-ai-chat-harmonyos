import { common } from '@kit.AbilityKit'
import {
  BuiltinModelDownloadSpec,
  BuiltinModelFileSpec,
  BuiltinModelInstallProgress
} from '../models/BuiltinModelDownloadTypes'
import { GenerationSettings } from '../models/ChatTypes'
import { ModelImportResult, ModelImportScanResult } from '../models/ImportedModelTypes'
import { ModelProfile } from '../models/ModelProfile'
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
    const expectedFiles = this.expectedFiles(filesDir, profile, configPath)
    const preflight = await this.preflightService.validate(configPath, profile.supportsImage, expectedFiles)
    if (!preflight.compatible) {
      throw new Error(`模型目录预检失败（${preflight.code}）：${preflight.message}`)
    }
    try {
      const loaded = await this.nativeService.loadModel(configPath, threadNum, maxNewTokens, settings)
      if (!loaded) {
        throw new Error('原生推理层未返回已加载状态。')
      }
      return true
    } catch (err) {
      this.nativeService.reset()
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
    await this.preflightService.requireCompatible(
      `${context.filesDir}/${spec.directoryName}/config.json`,
      supportsImage,
      spec.files
    )
  }

  async deleteModel(
    filesDir: string,
    profile: ModelProfile,
    resetLoadedModel: boolean
  ): Promise<ModelDeleteResult> {
    if (resetLoadedModel) {
      this.nativeService.reset()
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

  loadImportedProfiles(filesDir: string): Promise<ModelProfile[]> {
    return this.importService.loadImportedProfiles(filesDir)
  }

  importPickedModel(
    context: common.UIAbilityContext,
    existingProfiles: ModelProfile[]
  ): Promise<ModelImportResult | undefined> {
    return this.importService.pickAndImport(context, existingProfiles)
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

  reset(): void {
    this.nativeService.reset()
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
