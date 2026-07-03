import { common } from '@kit.AbilityKit'
import picker from '@ohos.file.picker'
import fs from '@ohos.file.fs'
import zlib from '@ohos.zlib'
import {
  DEFAULT_IMPORTED_MODEL_PROMPT,
  IMPORTED_MODEL_SOURCE,
  IMPORTED_MODELS_DIR,
  IMPORTED_MODELS_STORE_FILE,
  ImportedModelDraft,
  ImportedModelManifest,
  ModelImportScanResult,
  LEGACY_IMPORTED_MODEL_PROMPT,
  ModelImportResult
} from '../models/ImportedModelTypes'
import {
  CHAT_FORMAT_MNN_AUTO,
  ModelProfile
} from '../models/ModelProfile'
import { formatError } from '../utils/formatters'
import {
  importedModelShortName,
  legacyImportedModelShortName,
  safeModelId,
  stripMnnSuffix,
  uniqueModelId,
  uniqueModelName,
  uniqueModelShortName
} from '../utils/modelNaming'
import { ModelDirectoryPreflightService } from './ModelDirectoryPreflightService'

export class ModelImportService {
  private preflightService: ModelDirectoryPreflightService = new ModelDirectoryPreflightService()

  async pickAndImport(context: common.UIAbilityContext, existingProfiles: ModelProfile[]): Promise<ModelImportResult | undefined> {
    const zipUri = await this.pickZip(context)
    if (zipUri === undefined || zipUri.length <= 0) {
      return undefined
    }

    const filesDir = context.filesDir
    const importRoot = this.importRoot(filesDir)
    const tempDir = `${importRoot}/tmp`
    await this.ensureDir(tempDir)

    const timestamp = new Date().getTime()
    const modelId = `imported-${timestamp}`
    const targetDir = `${importRoot}/${modelId}`
    const tempZip = `${tempDir}/${modelId}.zip`
    try {
      await this.ensureDir(targetDir)
      await this.copyPickedFile(zipUri, tempZip)
      await zlib.decompressFile(tempZip, targetDir)
      if (await this.exists(tempZip)) {
        await fs.unlink(tempZip)
      }

      const configPath = await this.findConfigPath(targetDir)
      if (configPath.length <= 0) {
        throw new Error('模型包中未找到 config.json')
      }

      await this.preflightService.requireCompatible(configPath, false)

      const inferredName = uniqueModelName(this.inferName(zipUri, configPath, targetDir), existingProfiles)
      const inferredShortName = uniqueModelShortName(importedModelShortName(inferredName), existingProfiles)
      const profile: ModelProfile = {
        id: modelId,
        name: inferredName,
        shortName: inferredShortName,
        directoryName: modelId,
        description: '用户导入的 MNN 模型。',
        supportsImage: false,
        systemPrompt: DEFAULT_IMPORTED_MODEL_PROMPT,
        source: IMPORTED_MODEL_SOURCE,
        configPath,
        chatFormat: CHAT_FORMAT_MNN_AUTO,
        promptTemplate: '',
        stopSequence: '',
        templateOverride: false,
        editable: true,
        removable: true
      }

      const imported = await this.loadImportedProfiles(filesDir)
      imported.push(profile)
      await this.saveImportedProfiles(filesDir, imported)
      return {
        profile,
        message: `${profile.shortName} 导入完成，请加载模型。`
      }
    } catch (err) {
      if (await this.exists(tempZip)) {
        await fs.unlink(tempZip)
      }
      if (await this.exists(targetDir)) {
        await this.deletePathRecursive(targetDir)
      }
      throw new Error(formatError(err as Object))
    }
  }

  async scanPushedModelDirectories(filesDir: string, existingProfiles: ModelProfile[]): Promise<ModelImportScanResult> {
    const importRoot = this.importRoot(filesDir)
    await this.ensureDir(importRoot)

    const importedProfiles = await this.loadImportedProfiles(filesDir)
    const nextProfiles = importedProfiles.slice()
    const addedProfiles: ModelProfile[] = []
    const errors: string[] = []
    let skippedCount = 0

    const names = await fs.listFile(importRoot)
    for (let index = 0; index < names.length; index++) {
      const directoryName = names[index]
      if (!this.isSafeImportedDirectoryName(directoryName) || directoryName === 'tmp') {
        skippedCount++
        continue
      }

      const targetDir = `${importRoot}/${directoryName}`
      const stat = await fs.stat(targetDir)
      if (!stat.isDirectory()) {
        continue
      }
      if (this.hasImportedDirectory(nextProfiles, directoryName)) {
        continue
      }

      const configPath = await this.findConfigPath(targetDir)
      if (configPath.length <= 0 || this.hasImportedConfigPath(nextProfiles, configPath)) {
        skippedCount++
        if (configPath.length <= 0) {
          errors.push(`${directoryName}：模型目录缺少 config.json。`)
        }
        continue
      }

      const preflight = await this.preflightService.validate(configPath, false)
      if (!preflight.compatible) {
        skippedCount++
        errors.push(`${directoryName}：${preflight.message}`)
        continue
      }

      const profilePool = existingProfiles.concat(nextProfiles)
      const inferredName = uniqueModelName(this.inferNameFromDirectory(configPath, targetDir, directoryName), profilePool)
      const inferredShortName = uniqueModelShortName(importedModelShortName(inferredName), profilePool)
      const profile: ModelProfile = {
        id: uniqueModelId(`imported-${safeModelId(directoryName)}`, profilePool),
        name: inferredName,
        shortName: inferredShortName,
        directoryName,
        description: '用户导入的 MNN 模型。',
        supportsImage: false,
        systemPrompt: DEFAULT_IMPORTED_MODEL_PROMPT,
        source: IMPORTED_MODEL_SOURCE,
        configPath,
        chatFormat: CHAT_FORMAT_MNN_AUTO,
        promptTemplate: '',
        stopSequence: '',
        templateOverride: false,
        editable: true,
        removable: true
      }

      nextProfiles.push(profile)
      addedProfiles.push(profile)
    }

    if (addedProfiles.length > 0) {
      await this.saveImportedProfiles(filesDir, nextProfiles)
    }
    return {
      profiles: nextProfiles,
      addedProfiles,
      skippedCount,
      errors
    }
  }

  async loadImportedProfiles(filesDir: string): Promise<ModelProfile[]> {
    const storePath = this.storePath(filesDir)
    if (!await this.exists(storePath)) {
      return []
    }

    const text = await fs.readText(storePath)
    if (text.trim().length <= 0) {
      return []
    }

    const manifest = JSON.parse(text.replace(/^\uFEFF/, '')) as ImportedModelManifest
    if (!manifest.models) {
      return []
    }
    const importRoot = this.importRoot(filesDir)
    const normalized: ModelProfile[] = []
    for (let index = 0; index < manifest.models.length; index++) {
      const profile = manifest.models[index]
      if (this.isSafeImportedProfile(profile, importRoot)) {
        normalized.push(await this.normalizeImportedProfile(profile))
      }
    }
    return normalized
  }

  async saveImportedProfiles(filesDir: string, profiles: ModelProfile[]): Promise<void> {
    const importRoot = this.importRoot(filesDir)
    await this.ensureDir(importRoot)
    const manifest: ImportedModelManifest = { models: profiles }
    await this.writeText(this.storePath(filesDir), JSON.stringify(manifest, undefined, 2))
  }

  async updateImportedProfile(filesDir: string, updated: ModelProfile): Promise<ModelProfile[]> {
    const profiles = await this.loadImportedProfiles(filesDir)
    const uniqueName = uniqueModelName(updated.name, profiles, updated.id)
    const uniqueShortName = uniqueModelShortName(updated.shortName, profiles, updated.id)
    const next = profiles.map((profile: ModelProfile) => {
      if (profile.id !== updated.id) {
        return profile
      }
      return {
        id: profile.id,
        name: uniqueName,
        shortName: uniqueShortName,
        directoryName: profile.directoryName,
        description: updated.description,
        supportsImage: updated.supportsImage,
        systemPrompt: updated.systemPrompt,
        source: IMPORTED_MODEL_SOURCE,
        configPath: profile.configPath,
        chatFormat: CHAT_FORMAT_MNN_AUTO,
        promptTemplate: '',
        stopSequence: '',
        templateOverride: false,
        editable: true,
        removable: true
      } as ModelProfile
    })
    await this.saveImportedProfiles(filesDir, next)
    return next
  }

  async deleteImportedProfile(filesDir: string, modelId: string): Promise<ModelProfile[]> {
    const profiles = await this.loadImportedProfiles(filesDir)
    const target = profiles.find((profile: ModelProfile) => profile.id === modelId)
    const next = profiles.filter((profile: ModelProfile) => profile.id !== modelId)
    if (target !== undefined) {
      const targetDir = `${this.importRoot(filesDir)}/${target.directoryName}`
      if (await this.exists(targetDir)) {
        await this.deletePathRecursive(targetDir)
      }
    }
    await this.saveImportedProfiles(filesDir, next)
    return next
  }

  createDraft(profile: ModelProfile): ImportedModelDraft {
    return {
      name: profile.name,
      shortName: profile.shortName,
      description: profile.description,
      supportsImage: profile.supportsImage,
      systemPrompt: profile.systemPrompt
    }
  }

  applyDraft(profile: ModelProfile, draft: ImportedModelDraft): ModelProfile {
    const name = draft.name.trim().length > 0 ? draft.name.trim() : profile.name
    const shortName = draft.shortName.trim().length > 0 ? draft.shortName.trim() : importedModelShortName(name)
    return {
      id: profile.id,
      name,
      shortName,
      directoryName: profile.directoryName,
      description: draft.description.trim().length > 0 ? draft.description.trim() : profile.description,
      supportsImage: draft.supportsImage,
      systemPrompt: draft.systemPrompt.trim().length > 0 ? draft.systemPrompt.trim() : DEFAULT_IMPORTED_MODEL_PROMPT,
      source: IMPORTED_MODEL_SOURCE,
      configPath: profile.configPath,
      chatFormat: CHAT_FORMAT_MNN_AUTO,
      promptTemplate: '',
      stopSequence: '',
      templateOverride: false,
      editable: true,
      removable: true
    }
  }

  private async pickZip(context: common.UIAbilityContext): Promise<string | undefined> {
    const documentPicker = new picker.DocumentViewPicker(context)
    const options = new picker.DocumentSelectOptions()
    options.fileSuffixFilters = ['MNN 模型包|.zip']
    options.maxSelectNumber = 1
    const result = await documentPicker.select(options)
    return result.length > 0 ? result[0] : undefined
  }

  private importRoot(filesDir: string): string {
    return `${filesDir}/${IMPORTED_MODELS_DIR}`
  }

  private storePath(filesDir: string): string {
    return `${this.importRoot(filesDir)}/${IMPORTED_MODELS_STORE_FILE}`
  }

  private async ensureDir(path: string): Promise<void> {
    if (await this.exists(path)) {
      return
    }
    await fs.mkdir(path, true)
  }

  private async exists(path: string): Promise<boolean> {
    try {
      return await fs.access(path)
    } catch (_) {
      return false
    }
  }

  private async writeText(path: string, text: string): Promise<void> {
    const file = fs.openSync(path, fs.OpenMode.WRITE_ONLY | fs.OpenMode.CREATE | fs.OpenMode.TRUNC)
    try {
      fs.writeSync(file.fd, text)
    } finally {
      fs.closeSync(file)
    }
  }

  private async copyPickedFile(uri: string, targetPath: string): Promise<void> {
    const file = fs.openSync(uri, fs.OpenMode.READ_ONLY)
    try {
      await fs.copyFile(file.fd, targetPath)
    } finally {
      fs.closeSync(file)
    }
  }

  private async findConfigPath(root: string): Promise<string> {
    const files = await this.listFilesRecursive(root)
    for (let index = 0; index < files.length; index++) {
      if (files[index].toLowerCase().endsWith('/config.json')) {
        return files[index]
      }
    }
    return ''
  }

  private async listFilesRecursive(root: string): Promise<string[]> {
    const result: string[] = []
    const names = await fs.listFile(root)
    for (let index = 0; index < names.length; index++) {
      const path = `${root}/${names[index]}`
      const stat = await fs.stat(path)
      if (stat.isDirectory()) {
        const childFiles = await this.listFilesRecursive(path)
        childFiles.forEach((child: string) => result.push(child))
      } else if (stat.isFile()) {
        result.push(path)
      }
    }
    return result
  }

  private inferName(zipUri: string, configPath: string, targetDir: string): string {
    const fromDirectory = this.nameFromConfigDirectory(configPath, targetDir)
    if (fromDirectory.length > 0) {
      return fromDirectory
    }
    const fromZip = stripMnnSuffix(this.cleanFileName(zipUri))
    return fromZip.length > 0 ? fromZip : 'Imported MNN Model'
  }

  private inferNameFromDirectory(configPath: string, targetDir: string, directoryName: string): string {
    const fromDirectory = this.nameFromConfigDirectory(configPath, targetDir)
    if (fromDirectory.length > 0) {
      return fromDirectory
    }
    const fromDirectoryName = stripMnnSuffix(directoryName)
    return fromDirectoryName.length > 0 ? fromDirectoryName : 'Imported MNN Model'
  }

  private cleanFileName(path: string): string {
    const normalized = decodeURIComponent(path)
    const segments = normalized.split('/')
    let fileName = segments.length > 0 ? segments[segments.length - 1] : ''
    const queryIndex = fileName.indexOf('?')
    if (queryIndex >= 0) {
      fileName = fileName.substring(0, queryIndex)
    }
    if (fileName.toLowerCase().endsWith('.zip')) {
      fileName = fileName.substring(0, fileName.length - 4)
    }
    return fileName.trim()
  }

  private nameFromConfigDirectory(configPath: string, targetDir: string): string {
    const normalizedTargetDir = `${targetDir}/`
    if (!configPath.startsWith(normalizedTargetDir)) {
      return ''
    }
    const relativeConfigPath = configPath.substring(normalizedTargetDir.length)
    const parts = relativeConfigPath.split('/')
    if (parts.length < 2) {
      return ''
    }
    return stripMnnSuffix(parts[parts.length - 2])
  }

  private async normalizeImportedProfile(profile: ModelProfile): Promise<ModelProfile> {
    if (profile.configPath !== undefined && profile.configPath.length > 0) {
      try {
        await this.preflightService.validate(profile.configPath, profile.supportsImage)
      } catch (_) {}
    }
    const normalizedName = stripMnnSuffix(profile.name)
    const normalizedSystemPrompt = profile.systemPrompt === LEGACY_IMPORTED_MODEL_PROMPT ?
      DEFAULT_IMPORTED_MODEL_PROMPT :
      profile.systemPrompt
    const shouldRefreshShortName =
      profile.shortName.length === 12 && profile.name.length > 12 && profile.shortName === profile.name.substring(0, 12) ||
      profile.shortName === legacyImportedModelShortName(normalizedName) ||
      profile.shortName === normalizedName ||
      profile.shortName === profile.name
    const normalizedChatFormat = CHAT_FORMAT_MNN_AUTO
    const normalizedPromptTemplate = ''
    const normalizedStopSequence = ''
    const hasTemplateOverride = false
    if (
      normalizedName !== profile.name ||
      normalizedSystemPrompt !== profile.systemPrompt ||
      profile.chatFormat !== normalizedChatFormat ||
      (profile.promptTemplate ?? '') !== normalizedPromptTemplate ||
      (profile.stopSequence ?? '') !== normalizedStopSequence ||
      profile.templateOverride !== hasTemplateOverride ||
      shouldRefreshShortName
    ) {
      return {
        id: profile.id,
        name: normalizedName,
        shortName: shouldRefreshShortName ? importedModelShortName(normalizedName) : profile.shortName,
        directoryName: profile.directoryName,
        description: profile.description,
        supportsImage: profile.supportsImage,
        systemPrompt: normalizedSystemPrompt,
        source: profile.source,
        configPath: profile.configPath,
        chatFormat: normalizedChatFormat,
        promptTemplate: normalizedPromptTemplate,
        stopSequence: normalizedStopSequence,
        templateOverride: hasTemplateOverride,
        editable: profile.editable,
        removable: profile.removable
      }
    }
    return profile
  }

  private isSafeImportedProfile(profile: ModelProfile, importRoot: string): boolean {
    if (profile.source !== IMPORTED_MODEL_SOURCE || profile.configPath === undefined || profile.configPath.length <= 0) {
      return false
    }
    if (profile.directoryName.length <= 0 || profile.directoryName.indexOf('/') >= 0 || profile.directoryName.indexOf('\\') >= 0) {
      return false
    }
    if (profile.directoryName.indexOf('..') >= 0) {
      return false
    }
    return profile.configPath.startsWith(`${importRoot}/`)
  }

  private isSafeImportedDirectoryName(name: string): boolean {
    if (name.length <= 0 || name.indexOf('/') >= 0 || name.indexOf('\\') >= 0) {
      return false
    }
    return name.indexOf('..') < 0
  }

  private hasImportedDirectory(profiles: ModelProfile[], directoryName: string): boolean {
    return profiles.some((profile: ModelProfile) => profile.directoryName === directoryName)
  }

  private hasImportedConfigPath(profiles: ModelProfile[], configPath: string): boolean {
    return profiles.some((profile: ModelProfile) => profile.configPath === configPath)
  }

  private async deletePathRecursive(path: string): Promise<void> {
    const stat = await fs.stat(path)
    if (stat.isFile()) {
      await fs.unlink(path)
      return
    }
    if (!stat.isDirectory()) {
      return
    }
    const names = await fs.listFile(path)
    for (let index = 0; index < names.length; index++) {
      await this.deletePathRecursive(`${path}/${names[index]}`)
    }
    await fs.rmdir(path)
  }
}
