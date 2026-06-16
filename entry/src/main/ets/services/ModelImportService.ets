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
  LEGACY_IMPORTED_MODEL_PROMPT,
  ModelImportResult
} from '../models/ImportedModelTypes'
import {
  CHAT_FORMAT_GEMMA_TURN,
  CHAT_FORMAT_MINICPM_THINKING,
  CHAT_FORMAT_MNN_AUTO,
  CHAT_FORMAT_QWEN_IM,
  CHAT_FORMAT_RAW_TEMPLATE,
  ModelProfile
} from '../models/ModelProfile'
import { formatError } from '../utils/formatters'

interface MnnLlmConfig {
  prompt_template?: string
  jinja?: MnnJinjaConfig
}

interface MnnJinjaConfig {
  chat_template?: string
  eos?: string
}

interface PromptTemplateProfile {
  chatFormat: string
  promptTemplate: string
  stopSequence: string
}

export class ModelImportService {
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

      const allFiles = await this.listFilesRecursive(targetDir)
      if (!this.containsMnnFile(allFiles)) {
        throw new Error('模型包中未找到 .mnn 模型文件')
      }

      const inferredName = this.uniqueProfileName(this.inferName(zipUri, configPath, targetDir), existingProfiles)
      const inferredShortName = this.uniqueProfileShortName(this.toShortName(inferredName), existingProfiles)
      const promptConfig = await this.readPromptTemplateProfile(configPath, inferredName)
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
        chatFormat: promptConfig.chatFormat,
        promptTemplate: promptConfig.promptTemplate,
        stopSequence: promptConfig.stopSequence,
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

  async updateImportedProfile(filesDir: string, updated: ModelProfile, existingProfiles: ModelProfile[]): Promise<ModelProfile[]> {
    const profiles = await this.loadImportedProfiles(filesDir)
    const uniqueName = this.uniqueProfileName(updated.name, existingProfiles, updated.id)
    const uniqueShortName = this.uniqueProfileShortName(updated.shortName, existingProfiles, updated.id)
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
        chatFormat: updated.chatFormat,
        promptTemplate: updated.promptTemplate,
        stopSequence: updated.stopSequence,
        templateOverride: updated.chatFormat !== CHAT_FORMAT_MNN_AUTO,
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
      supportsImage: profile.supportsImage,
      systemPrompt: profile.systemPrompt,
      chatFormat: profile.chatFormat ?? CHAT_FORMAT_MNN_AUTO,
      promptTemplate: profile.promptTemplate ?? '',
      stopSequence: profile.stopSequence ?? ''
    }
  }

  applyDraft(profile: ModelProfile, draft: ImportedModelDraft): ModelProfile {
    const name = draft.name.trim().length > 0 ? draft.name.trim() : profile.name
    const shortName = draft.shortName.trim().length > 0 ? draft.shortName.trim() : this.toShortName(name)
    return {
      id: profile.id,
      name,
      shortName,
      directoryName: profile.directoryName,
      description: profile.description,
      supportsImage: draft.supportsImage,
      systemPrompt: draft.systemPrompt.trim().length > 0 ? draft.systemPrompt.trim() : DEFAULT_IMPORTED_MODEL_PROMPT,
      source: IMPORTED_MODEL_SOURCE,
      configPath: profile.configPath,
      chatFormat: draft.chatFormat,
      promptTemplate: draft.promptTemplate,
      stopSequence: draft.stopSequence,
      templateOverride: draft.chatFormat !== CHAT_FORMAT_MNN_AUTO,
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

  private containsMnnFile(files: string[]): boolean {
    for (let index = 0; index < files.length; index++) {
      if (files[index].toLowerCase().endsWith('.mnn')) {
        return true
      }
    }
    return false
  }

  private inferName(zipUri: string, configPath: string, targetDir: string): string {
    const fromDirectory = this.nameFromConfigDirectory(configPath, targetDir)
    if (fromDirectory.length > 0) {
      return fromDirectory
    }
    const fromZip = this.stripMnnSuffix(this.cleanFileName(zipUri))
    return fromZip.length > 0 ? fromZip : 'Imported MNN Model'
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
    return this.stripMnnSuffix(parts[parts.length - 2])
  }

  private uniqueProfileName(baseName: string, profiles: ModelProfile[], selfId: string = ''): string {
    const name = baseName.length > 0 ? baseName : 'Imported MNN Model'
    let candidate = name
    let suffix = 2
    while (profiles.some((profile: ModelProfile) => profile.id !== selfId && profile.name === candidate)) {
      candidate = `${name} ${suffix}`
      suffix++
    }
    return candidate
  }

  private uniqueProfileShortName(baseName: string, profiles: ModelProfile[], selfId: string = ''): string {
    const name = baseName.length > 0 ? baseName : 'Imported'
    let candidate = name
    let suffix = 2
    while (profiles.some((profile: ModelProfile) => profile.id !== selfId && profile.shortName === candidate)) {
      candidate = `${name} ${suffix}`
      suffix++
    }
    return candidate
  }

  private toShortName(name: string): string {
    const normalized = this.stripMnnSuffix(name)
    const familyAndSize = this.extractFamilyAndSize(normalized)
    return familyAndSize.length > 24 ? familyAndSize.substring(0, 24) : familyAndSize
  }

  private stripMnnSuffix(name: string): string {
    let normalized = name.trim()
    const lowerName = normalized.toLowerCase()
    if (lowerName.endsWith('-mnn') || lowerName.endsWith('_mnn')) {
      normalized = normalized.substring(0, normalized.length - 4)
    } else if (lowerName.endsWith(' mnn')) {
      normalized = normalized.substring(0, normalized.length - 4)
    }
    return normalized.trim()
  }

  private extractFamilyAndSize(name: string): string {
    const normalized = name.trim()
    const tokens = normalized.split('-')
    if (tokens.length <= 1) {
      return normalized
    }

    for (let index = 1; index < tokens.length; index++) {
      if (this.isParameterToken(tokens[index])) {
        return `${tokens[0]}-${tokens[index]}`
      }
    }
    return tokens[0]
  }

  private isParameterToken(token: string): boolean {
    return /^[0-9]+(\.[0-9]+)?[BMbK]?$/.test(token) || /^E[0-9]+B$/i.test(token)
  }

  private async normalizeImportedProfile(profile: ModelProfile): Promise<ModelProfile> {
    const normalizedName = this.stripMnnSuffix(profile.name)
    const normalizedSystemPrompt = profile.systemPrompt === LEGACY_IMPORTED_MODEL_PROMPT ?
      DEFAULT_IMPORTED_MODEL_PROMPT :
      profile.systemPrompt
    const shouldRefreshShortName =
      profile.shortName.length === 12 && profile.name.length > 12 && profile.shortName === profile.name.substring(0, 12) ||
      profile.shortName === normalizedName ||
      profile.shortName === profile.name
    const hasTemplateOverride = profile.templateOverride === true
    const inferredPromptConfig = profile.configPath === undefined || profile.configPath.length <= 0 ?
      this.defaultPromptTemplateProfile(profile.name) :
      await this.readPromptTemplateProfile(profile.configPath, profile.name)
    const normalizedChatFormat = hasTemplateOverride ? profile.chatFormat ?? inferredPromptConfig.chatFormat : inferredPromptConfig.chatFormat
    const normalizedPromptTemplate = hasTemplateOverride ? profile.promptTemplate ?? inferredPromptConfig.promptTemplate : inferredPromptConfig.promptTemplate
    const normalizedStopSequence = hasTemplateOverride ? profile.stopSequence ?? inferredPromptConfig.stopSequence : inferredPromptConfig.stopSequence
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
        shortName: shouldRefreshShortName ? this.toShortName(normalizedName) : profile.shortName,
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

  private async readPromptTemplateProfile(configPath: string, modelName: string): Promise<PromptTemplateProfile> {
    const llmConfigPath = this.llmConfigPath(configPath)
    if (llmConfigPath.length <= 0 || !await this.exists(llmConfigPath)) {
      return this.defaultPromptTemplateProfile(modelName)
    }
    try {
      const text = await fs.readText(llmConfigPath)
      const llmConfig = JSON.parse(text.replace(/^\uFEFF/, '')) as MnnLlmConfig
      return this.inferPromptTemplateProfile(
        llmConfig.prompt_template ?? llmConfig.jinja?.chat_template ?? '',
        modelName,
        llmConfig.jinja?.eos ?? ''
      )
    } catch (_) {
      return this.defaultPromptTemplateProfile(modelName)
    }
  }

  private llmConfigPath(configPath: string): string {
    const lowerPath = configPath.toLowerCase()
    if (!lowerPath.endsWith('/config.json')) {
      return ''
    }
    return `${configPath.substring(0, configPath.length - '/config.json'.length)}/llm_config.json`
  }

  private defaultPromptTemplateProfile(modelName: string): PromptTemplateProfile {
    return this.inferPromptTemplateProfile('', modelName, '')
  }

  private inferPromptTemplateProfile(promptTemplate: string, modelName: string, eos: string): PromptTemplateProfile {
    const template = promptTemplate.trim()
    const lowerTemplate = template.toLowerCase()
    const lowerName = modelName.toLowerCase()
    if (lowerTemplate.indexOf('<|im_start|>') >= 0 && lowerTemplate.indexOf('<|im_end|>') >= 0) {
      if (lowerName.indexOf('minicpm') >= 0) {
        return {
          chatFormat: CHAT_FORMAT_MINICPM_THINKING,
          promptTemplate: template,
          stopSequence: eos.length > 0 ? eos : '</s>'
        }
      }
      return {
        chatFormat: CHAT_FORMAT_QWEN_IM,
        promptTemplate: template,
        stopSequence: '<|im_end|>'
      }
    }
    if (lowerTemplate.indexOf('<|turn>') >= 0 && lowerTemplate.indexOf('<turn|>') >= 0) {
      return {
        chatFormat: CHAT_FORMAT_GEMMA_TURN,
        promptTemplate: template,
        stopSequence: '<turn|>'
      }
    }
    if (template.indexOf('%s') >= 0) {
      return {
        chatFormat: CHAT_FORMAT_RAW_TEMPLATE,
        promptTemplate: template,
        stopSequence: this.inferStopSequence(template, lowerName, eos)
      }
    }
    return {
      chatFormat: CHAT_FORMAT_MNN_AUTO,
      promptTemplate: template,
      stopSequence: this.inferStopSequence(template, lowerName, eos)
    }
  }

  private inferStopSequence(promptTemplate: string, lowerName: string, eos: string): string {
    if (promptTemplate.indexOf('<|im_end|>') >= 0) {
      return '<|im_end|>'
    }
    if (promptTemplate.indexOf('<|end_of_sentence|>') >= 0) {
      return '<|end_of_sentence|>'
    }
    if (promptTemplate.indexOf('<|end_of_text|>') >= 0) {
      return '<|end_of_text|>'
    }
    if (eos.length > 0) {
      return eos
    }
    if (lowerName.indexOf('deepseek') >= 0) {
      return '<|end_of_sentence|>'
    }
    if (lowerName.indexOf('qwen') >= 0 && lowerName.indexOf('deepseek') < 0) {
      return '<|im_end|>'
    }
    return ''
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
