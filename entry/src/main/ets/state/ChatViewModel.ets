import { bundleManager, common } from '@kit.AbilityKit'
import preferences from '@ohos.data.preferences'
import { ChatMessage, ChatTurn, GenerationSettings, PerfMetrics } from '../models/ChatTypes'
import { ImportedModelDraft } from '../models/ImportedModelTypes'
import {
  BuiltinModelDownloadSpec,
  BuiltinModelInstallProgress,
  MODEL_CATALOG_FILTER_ALL,
  ModelCatalogItem,
  isBundledPresetCatalogItem
} from '../models/BuiltinModelDownloadTypes'
import {
  ModelCatalogLoadResult,
  ModelCatalogRefreshResult
} from '../models/ModelCatalogTypes'
import {
  DEFAULT_FREQUENCY_PENALTY,
  DEFAULT_MAX_NEW_TOKENS,
  DEFAULT_PENALTY_WINDOW,
  DEFAULT_PRESENCE_PENALTY,
  DEFAULT_REPETITION_PENALTY,
  DEFAULT_TEMPERATURE,
  DEFAULT_THREAD_NUM,
  DEFAULT_TOP_K,
  DEFAULT_TOP_P,
  GenerationDefaults,
  MAX_GENERATION_TOKENS,
  ModelProfile
} from '../models/ModelProfile'
import { EMPTY_RUNTIME_STATS, EMPTY_STORAGE_STATS, RuntimeStats, StorageStats } from '../models/RuntimeStats'
import { ImagePayloadService } from '../services/ImagePayloadService'
import { BuiltinModelInstallService } from '../services/BuiltinModelInstallService'
import { ModelImportService } from '../services/ModelImportService'
import { ModelCatalogService } from '../services/ModelCatalogService'
import { NativeInferenceService } from '../services/NativeInferenceService'
import { RuntimeStatsService } from '../services/RuntimeStatsService'
import {
  SpeechRecognitionCallbacks,
  SpeechRecognitionService
} from '../services/SpeechRecognitionService'
import {
  GenerationStreamUpdate,
  GenerationWorkflow,
  GenerationWorkflowResult
} from '../services/GenerationWorkflow'
import { ModelDeleteResult, ModelLifecycleService } from '../services/ModelLifecycleService'
import { calculateDownloadProgress } from '../utils/downloadProgress'
import { formatDownloadError, formatError } from '../utils/formatters'
import { reorderVisibleModelIds } from '../utils/modelDrag'
import { ChatSession } from './ChatSession'
import { ModelManager } from './ModelManager'

@Observed
export class ChatViewModel {
  messages: ChatMessage[] = []
  inputText: string = ''
  selectedImageUri: string = ''
  busy: boolean = false
  generating: boolean = false
  generationStopping: boolean = false
  speechRecognitionStarting: boolean = false
  speechRecognizing: boolean = false
  speechRecognitionStopping: boolean = false
  speechDetected: boolean = false
  loaded: boolean = false
  status: string = '模型未加载'
  maxNewTokens: number = DEFAULT_MAX_NEW_TOKENS
  threadNum: number = DEFAULT_THREAD_NUM
  temperature: number = DEFAULT_TEMPERATURE
  topP: number = DEFAULT_TOP_P
  topK: number = DEFAULT_TOP_K
  repetitionPenalty: number = DEFAULT_REPETITION_PENALTY
  frequencyPenalty: number = DEFAULT_FREQUENCY_PENALTY
  presencePenalty: number = DEFAULT_PRESENCE_PENALTY
  penaltyWindow: number = DEFAULT_PENALTY_WINDOW
  runtimeConfigDirty: boolean = false
  showModelLoadDialog: boolean = false
  modelLoading: boolean = false
  modelLoadProgress: number = 0
  modelLoadMessage: string = '准备加载本地模型'
  showBuiltinModelInstallDialog: boolean = false
  builtinModelInstalling: boolean = false
  builtinModelInstallProgress: number = 0
  builtinModelInstallMessage: string = '内置模型目录缺失，请先下载模型文件。'
  builtinModelInstallFileName: string = ''
  builtinModelInstallModelName: string = ''
  builtinModelInstallSourceName: string = 'ModelScope'
  builtinModelInstallDownloadedBytes: number = 0
  builtinModelInstallTotalBytes: number = 0
  builtinModelInstallError: string = ''
  builtinModelInstallCanceled: boolean = false
  showModelMarketDialog: boolean = false
  modelMarketSearchText: string = ''
  modelMarketCapabilityFilter: string = MODEL_CATALOG_FILTER_ALL
  modelMarketInstalledIds: string[] = []
  modelCatalogRefreshing: boolean = false
  modelCatalogStatus: string = '正在读取模型目录...'
  modelCatalogSource: string = '内置目录'
  modelCatalogVersion: number = 0
  modelCatalogPublishedAt: string = ''
  modelImporting: boolean = false
  modelImportMessage: string = '可导入 MNN 模型 zip 包'
  editingImportedModelId: string = ''
  importedModelNameInput: string = ''
  importedModelShortNameInput: string = ''
  importedModelDescriptionInput: string = ''
  importedModelSystemPromptInput: string = ''
  showDeleteModelDialog: boolean = false
  pendingDeleteModelId: string = ''
  stats: RuntimeStats = EMPTY_RUNTIME_STATS
  storageStats: StorageStats = EMPTY_STORAGE_STATS
  streamingChars: number = 0
  latestPerfMetrics?: PerfMetrics
  appVersion: string = ''
  chatScroller: Scroller = new Scroller()

  private filesDir: string = ''
  private context?: common.UIAbilityContext
  private modelLoadTimer: number = -1
  private autoScrollPending: boolean = false
  private chatAutoScrollEnabled: boolean = true
  private notifyCallback: () => void = () => {}
  private toastCallback: (message: string) => void = (_message: string) => {}
  private session: ChatSession = new ChatSession()
  private modelManager: ModelManager = new ModelManager()
  private nativeService: NativeInferenceService = new NativeInferenceService()
  private imageService: ImagePayloadService = new ImagePayloadService()
  private modelCatalogService: ModelCatalogService = new ModelCatalogService()
  private builtinModelInstallService: BuiltinModelInstallService =
    new BuiltinModelInstallService(this.modelCatalogService)
  private modelImportService: ModelImportService = new ModelImportService()
  private statsService: RuntimeStatsService = new RuntimeStatsService()
  private speechRecognitionService: SpeechRecognitionService = new SpeechRecognitionService()
  private modelStorageStats: Map<string, string> = new Map()
  private generationWorkflow: GenerationWorkflow = new GenerationWorkflow(this.nativeService, this.imageService)
  private modelLifecycleService: ModelLifecycleService = new ModelLifecycleService(
    this.nativeService,
    this.builtinModelInstallService,
    this.modelImportService
  )
  private pendingInstallCatalogItemId: string = ''
  private autoLoadAfterInstall: boolean = false
  private builtinModelInstallCancelRequested: boolean = false
  private readonly modelOrderPreferenceName: string = 'model-settings'
  private readonly modelOrderPreferenceKey: string = 'model-order'

  get modelPath(): string {
    return this.modelManager.modelPath
  }

  get selectedModelId(): string {
    return this.modelManager.selectedModelId
  }

  get maxGenerationTokens(): number {
    return MAX_GENERATION_TOKENS
  }

  get appFilesDir(): string {
    return this.filesDir
  }

  bindNotify(callback: () => void): void {
    this.notifyCallback = callback
  }

  bindToast(callback: (message: string) => void): void {
    this.toastCallback = callback
  }

  initialize(context: common.UIAbilityContext): void {
    this.context = context
    this.filesDir = context.filesDir
    try {
      this.appVersion = bundleManager.getBundleInfoForSelfSync(
        bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT
      ).versionName
    } catch (_) {
      this.appVersion = ''
    }
    this.modelManager.initialize(this.filesDir)
    this.loadModelOrder()
    this.resetGenerationSettings(false)
    this.session.initializeWelcome(this.currentModel().shortName)
    this.syncMessages()
    this.refreshStats()
    this.refreshStorageStats()
    this.preloadModelStorageStats()
    this.notify()
    this.modelCatalogService.load(this.filesDir).then(async (result: ModelCatalogLoadResult) => {
      this.applyCatalogResult(result)
      await this.migrateBundledCatalogInstalls()
      this.refreshModelMarketInstallStates()
      this.refreshModelCatalog(false)
    }).catch((err: Error) => {
      this.modelCatalogStatus = `读取模型目录失败：${formatError(err as Object)}`
      this.notify()
    })
    this.modelLifecycleService.loadImportedProfiles(this.filesDir).then((profiles: ModelProfile[]) => {
      this.modelManager.updateImportedProfiles(profiles, this.filesDir)
      this.prepareImportedModelEditor(this.selectedModelId)
      this.preloadModelStorageStats()
      this.notify()
    }).catch((err: Error) => {
      this.modelImportMessage = `读取导入模型失败：${formatError(err as Object)}`
      this.notify()
    })
  }

  dispose(): void {
    this.stopModelLoadProgress()
    this.speechRecognitionService.shutdown()
    this.resetSpeechRecognitionState()
  }

  modelProfiles(): ModelProfile[] {
    return this.modelManager.profiles().filter((profile: ModelProfile) => this.shouldShowModelProfile(profile))
  }

  currentModel(): ModelProfile {
    return this.modelManager.currentModel()
  }

  modelCatalogItems(): ModelCatalogItem[] {
    const searchText = this.modelMarketSearchText.trim().toLowerCase()
    const filter = this.modelMarketCapabilityFilter
    const visibleItems = this.modelCatalogService.items().filter((item: ModelCatalogItem) => {
      if (filter !== MODEL_CATALOG_FILTER_ALL && item.capabilities.indexOf(filter) < 0) {
        return false
      }
      if (searchText.length <= 0) {
        return true
      }
      return item.displayName.toLowerCase().indexOf(searchText) >= 0 ||
        item.shortName.toLowerCase().indexOf(searchText) >= 0 ||
        item.provider.toLowerCase().indexOf(searchText) >= 0
    })
    const regularItems = visibleItems.filter((item: ModelCatalogItem) => !item.recommended)
    const presetItems = visibleItems.filter((item: ModelCatalogItem) => item.recommended)
    return regularItems.concat(presetItems)
  }

  modelCatalogFilterTags(): string[] {
    const tags: string[] = [MODEL_CATALOG_FILTER_ALL]
    this.modelCatalogService.items().forEach((item: ModelCatalogItem) => {
      item.capabilities.forEach((capability: string) => {
        if (tags.indexOf(capability) < 0) {
          tags.push(capability)
        }
      })
    })
    return tags
  }

  isCatalogItemInstalled(catalogItemId: string): boolean {
    return this.modelMarketInstalledIds.indexOf(catalogItemId) >= 0
  }

  openModelMarketDialog(): void {
    if (this.modelLoading || this.modelImporting || this.builtinModelInstalling) {
      return
    }
    this.showModelMarketDialog = true
    this.refreshModelMarketInstallStates()
    this.notify()
  }

  closeModelMarketDialog(): void {
    if (this.builtinModelInstalling) {
      return
    }
    this.showModelMarketDialog = false
    this.notify()
  }

  updateModelMarketSearchText(value: string): void {
    this.modelMarketSearchText = value
    this.notify()
  }

  updateModelMarketCapabilityFilter(value: string): void {
    this.modelMarketCapabilityFilter = value
    this.notify()
  }

  refreshModelCatalog(showResultToast: boolean = true): void {
    if (this.modelCatalogRefreshing || this.builtinModelInstalling || this.filesDir.length <= 0) {
      return
    }
    this.modelCatalogRefreshing = true
    this.modelCatalogStatus = '正在更新模型广场...'
    this.notify()
    this.modelCatalogService.refresh(this.filesDir).then((result: ModelCatalogRefreshResult) => {
      this.modelCatalogRefreshing = false
      this.applyCatalogResult(result)
      this.refreshModelMarketInstallStates()
      if (showResultToast) {
        this.toastCallback(result.message)
      }
    }).catch((err: Error) => {
      this.modelCatalogRefreshing = false
      const errorText = formatError(err as Object)
      const httpIndex = errorText.indexOf('HTTP ')
      const httpStatus = httpIndex >= 0 ?
        errorText.substring(httpIndex, Math.min(errorText.length, httpIndex + 8)) : ''
      this.modelCatalogStatus = httpStatus.length > 0 ?
        `在线更新失败（${httpStatus}），已保留当前目录` : '在线更新失败，已保留当前目录'
      if (showResultToast) {
        this.toastCallback('模型广场更新失败，已保留当前目录')
      }
      this.notify()
    })
  }

  installCatalogItem(catalogItemId: string): void {
    if (this.busy || this.modelLoading || this.modelImporting || this.builtinModelInstalling ||
      this.modelCatalogRefreshing || this.context === undefined) {
      return
    }
    const item = this.modelCatalogService.findMarketItem(catalogItemId)
    if (item === undefined) {
      this.status = '安装失败：模型广场条目不存在'
      this.notify()
      return
    }
    this.pendingInstallCatalogItemId = item.id
    this.autoLoadAfterInstall = item.modelId === this.selectedModelId
    this.showModelMarketDialog = false
    this.openBuiltinModelInstallDialog(item, this.autoLoadAfterInstall)
    this.startBuiltinModelInstall()
  }

  switchModel(modelId: string): void {
    if (this.busy || this.modelLoading || modelId === this.selectedModelId) {
      return
    }

    this.cancelSpeechRecognition(false)
    const model = this.modelManager.switchModel(modelId, this.filesDir)
    this.applyCurrentModelStorageStats()
    this.prepareImportedModelEditor(model.id)
    if (!model.supportsImage) {
      this.selectedImageUri = ''
    }
    this.inputText = ''
    this.selectedImageUri = ''
    this.resetGenerationSettings(false)
    this.session.resetForModelSwitch(model.shortName)
    this.syncMessages()
    this.runtimeConfigDirty = false
    this.resetLoadedModel(`已切换至 ${model.shortName}，请加载模型。`)
    this.notify()
  }

  updateModelPath(value: string): void {
    if (!this.modelManager.updateModelPath(value)) {
      return
    }
    this.runtimeConfigDirty = true
    this.status = this.loaded ? '运行配置已修改，应用并重新加载后生效。' : '运行配置已修改，应用并加载后生效。'
    this.notify()
  }

  updateInputText(value: string): void {
    this.inputText = value
    this.notify()
  }

  async startSpeechRecognition(): Promise<void> {
    if (
      !this.loaded ||
      this.busy ||
      this.context === undefined ||
      this.inputText.trim().length > 0 ||
      this.speechRecognitionStarting ||
      this.speechRecognizing
    ) {
      return
    }

    this.speechRecognitionStarting = true
    this.speechRecognitionStopping = false
    this.speechDetected = false
    this.status = '正在准备语音识别...'
    this.notify()
    const callbacks: SpeechRecognitionCallbacks = {
      onStarted: () => {
        this.speechRecognitionStarting = false
        this.speechRecognizing = true
        this.status = '正在聆听...'
        this.notify()
      },
      onSpeechActivity: (active: boolean) => {
        this.speechDetected = active
        this.status = active ? '正在识别语音...' : '正在等待继续说话...'
        this.notify()
      },
      onTranscript: (text: string) => {
        this.inputText = text
        this.notify()
      },
      onCompleted: () => {
        this.resetSpeechRecognitionState()
        this.status = this.inputText.trim().length > 0 ? '语音识别完成，可编辑后发送' : '未识别到语音'
        this.notify()
      },
      onError: (message: string) => {
        this.resetSpeechRecognitionState()
        this.status = `语音识别失败：${message}`
        this.toastCallback('语音识别失败，请重试')
        this.notify()
      }
    }
    try {
      await this.speechRecognitionService.start(this.context, callbacks)
      if (this.speechRecognitionStarting) {
        this.speechRecognitionStarting = false
        this.speechRecognizing = true
        this.status = '正在聆听...'
        this.notify()
      }
    } catch (err) {
      this.resetSpeechRecognitionState()
      this.status = formatError(err as Object)
      this.toastCallback(this.status)
      this.notify()
    }
  }

  stopSpeechRecognition(): void {
    if (!this.speechRecognizing || this.speechRecognitionStopping) {
      return
    }
    this.speechRecognitionStopping = true
    this.status = '正在完成语音识别...'
    try {
      this.speechRecognitionService.finish()
    } catch (err) {
      this.resetSpeechRecognitionState()
      this.status = `停止语音识别失败：${formatError(err as Object)}`
    }
    this.notify()
  }

  cancelSpeechRecognition(notify: boolean = true): void {
    if (!this.speechRecognitionStarting && !this.speechRecognizing) {
      return
    }
    this.speechRecognitionService.cancel()
    this.resetSpeechRecognitionState()
    if (notify) {
      this.notify()
    }
  }

  updateMaxNewTokens(value: number, notify: boolean = true): void {
    this.maxNewTokens = Math.round(value)
    if (notify) {
      this.notify()
    }
  }

  updateThreadNum(value: number): void {
    const nextThreadNum = Math.round(value)
    if (this.threadNum === nextThreadNum) {
      return
    }
    this.threadNum = nextThreadNum
    this.runtimeConfigDirty = true
    this.status = this.loaded ? '运行配置已修改，应用并重新加载后生效。' : '运行配置已修改，应用并加载后生效。'
    this.notify()
  }

  updateTemperature(value: number, notify: boolean = true): void {
    this.temperature = Math.round(value * 100) / 100
    if (notify) {
      this.notify()
    }
  }

  updateTopP(value: number, notify: boolean = true): void {
    this.topP = Math.round(value * 100) / 100
    if (notify) {
      this.notify()
    }
  }

  updateTopK(value: number, notify: boolean = true): void {
    this.topK = Math.round(value)
    if (notify) {
      this.notify()
    }
  }

  updateRepetitionPenalty(value: number, notify: boolean = true): void {
    this.repetitionPenalty = Math.round(value * 100) / 100
    if (notify) {
      this.notify()
    }
  }

  updateFrequencyPenalty(value: number, notify: boolean = true): void {
    this.frequencyPenalty = Math.round(value * 100) / 100
    if (notify) {
      this.notify()
    }
  }

  updatePresencePenalty(value: number, notify: boolean = true): void {
    this.presencePenalty = Math.round(value * 100) / 100
    if (notify) {
      this.notify()
    }
  }

  updatePenaltyWindow(value: number, notify: boolean = true): void {
    this.penaltyWindow = Math.round(value)
    if (notify) {
      this.notify()
    }
  }

  resetGenerationSettings(notify: boolean = true): void {
    const defaults = this.generationDefaultsForCurrentModel()
    this.maxNewTokens = defaults.maxNewTokens ?? DEFAULT_MAX_NEW_TOKENS
    this.temperature = defaults.temperature ?? DEFAULT_TEMPERATURE
    this.topP = defaults.topP ?? DEFAULT_TOP_P
    this.topK = defaults.topK ?? DEFAULT_TOP_K
    this.repetitionPenalty = defaults.repetitionPenalty ?? DEFAULT_REPETITION_PENALTY
    this.frequencyPenalty = defaults.frequencyPenalty ?? DEFAULT_FREQUENCY_PENALTY
    this.presencePenalty = defaults.presencePenalty ?? DEFAULT_PRESENCE_PENALTY
    this.penaltyWindow = defaults.penaltyWindow ?? DEFAULT_PENALTY_WINDOW
    if (notify) {
      this.notify()
    }
  }

  generationDefaultsForCurrentModel(): GenerationDefaults {
    return this.currentModel().generationDefaults ?? {}
  }

  importModelPackage(): void {
    if (this.busy || this.modelLoading || this.modelImporting || this.builtinModelInstalling) {
      return
    }
    if (!this.context) {
      this.modelImportMessage = '导入失败：上下文不可用'
      this.notify()
      return
    }

    this.busy = true
    this.modelImporting = true
    this.modelImportMessage = '可导入 MNN 模型 zip 包'
    this.status = '正在导入模型包...'
    this.notify()

    this.modelLifecycleService.importPickedModel(this.context, this.modelProfiles()).then((result) => {
      if (result === undefined) {
        this.modelImportMessage = '已取消导入模型包'
        this.status = this.loaded ? `${this.currentModel().shortName} 已加载` : '模型未加载'
        this.busy = false
        this.modelImporting = false
        this.notify()
        return
      }

      this.modelManager.addImportedProfile(result.profile, this.filesDir)
      this.prepareImportedModelEditor(result.profile.id)
      if (!result.profile.supportsImage) {
        this.selectedImageUri = ''
      }
      this.resetLoadedModel(result.message)
      this.modelImportMessage = result.message
      this.busy = false
      this.modelImporting = false
      this.notify()
    }).catch((err: Error) => {
      const message = `导入失败：${formatError(err as Object)}`
      this.modelImportMessage = message
      this.status = message
      this.busy = false
      this.modelImporting = false
      this.refreshStats()
      this.notify()
    })
  }

  scanPushedModelDirectories(): void {
    if (this.busy || this.modelLoading || this.modelImporting || this.builtinModelInstalling) {
      return
    }

    this.busy = true
    this.modelImporting = true

    this.modelLifecycleService.scanPushedModels(this.filesDir, this.modelProfiles()).then((result) => {
      this.modelManager.updateImportedProfiles(result.profiles, this.filesDir)
      const addedProfile = result.addedProfiles.length > 0 ? result.addedProfiles[result.addedProfiles.length - 1] : undefined
      if (addedProfile !== undefined) {
        const model = this.modelManager.switchModel(addedProfile.id, this.filesDir)
        this.prepareImportedModelEditor(model.id)
        this.selectedImageUri = ''
        this.inputText = ''
        this.resetGenerationSettings(false)
        this.session.resetForModelSwitch(model.shortName)
        this.syncMessages()
        this.resetLoadedModel(`已添加 ${result.addedProfiles.length} 个模型，请加载 ${model.shortName}。`)
        this.modelImportMessage = `已添加 ${result.addedProfiles.length} 个模型，请加载 ${model.shortName}。`
      } else {
        this.prepareImportedModelEditor(this.selectedModelId)
        this.modelImportMessage = result.errors.length > 0 ?
          `未导入模型：${result.errors[0]}` :
          (result.skippedCount > 0 ?
            '未发现新的可导入 MNN 目录，请检查目录完整性与对话模板。' :
            '未发现新的已推送模型目录。')
        this.status = this.loaded ? `${this.currentModel().shortName} 已加载` : this.status
      }
      this.busy = false
      this.modelImporting = false
      this.notify()
    }).catch((err: Error) => {
      const message = `扫描失败：${formatError(err as Object)}`
      this.modelImportMessage = message
      this.status = message
      this.busy = false
      this.modelImporting = false
      this.notify()
    })
  }

  prepareImportedModelEditor(modelId: string): void {
    const profile = this.findProfile(modelId)
    if (profile === undefined || profile.source !== 'imported') {
      this.editingImportedModelId = ''
      this.importedModelNameInput = ''
      this.importedModelShortNameInput = ''
      this.importedModelDescriptionInput = ''
      this.importedModelSystemPromptInput = ''
      return
    }
    const draft = this.modelImportService.createDraft(profile)
    this.editingImportedModelId = profile.id
    this.importedModelNameInput = draft.name
    this.importedModelShortNameInput = draft.shortName
    this.importedModelDescriptionInput = draft.description
    this.importedModelSystemPromptInput = draft.systemPrompt
  }

  updateImportedModelName(value: string): void {
    this.importedModelNameInput = value
    this.notify()
  }

  updateImportedModelShortName(value: string): void {
    this.importedModelShortNameInput = value
    this.notify()
  }

  updateImportedModelDescription(value: string): void {
    this.importedModelDescriptionInput = value
    this.notify()
  }

  updateImportedModelSystemPrompt(value: string): void {
    this.importedModelSystemPromptInput = value
    this.notify()
  }

  saveImportedModelProfile(): Promise<boolean> {
    if (this.busy || this.modelLoading || this.modelImporting || this.editingImportedModelId.length <= 0) {
      return Promise.resolve(false)
    }
    const profile = this.findProfile(this.editingImportedModelId)
    if (profile === undefined) {
      this.modelImportMessage = '保存失败：导入模型不存在'
      this.notify()
      return Promise.resolve(false)
    }
    const draft: ImportedModelDraft = {
      name: this.importedModelNameInput,
      shortName: this.importedModelShortNameInput,
      description: this.importedModelDescriptionInput,
      supportsImage: profile.supportsImage,
      systemPrompt: this.importedModelSystemPromptInput
    }
    const updated = this.modelImportService.applyDraft(profile, draft)
    return this.modelLifecycleService.updateImportedProfile(this.filesDir, updated).then((profiles: ModelProfile[]) => {
      this.modelManager.updateImportedProfiles(profiles, this.filesDir)
      this.prepareImportedModelEditor(updated.id)
      if (!updated.supportsImage) {
        this.selectedImageUri = ''
      }
      this.modelImportMessage = `${updated.shortName} 配置已保存`
      this.status = this.loaded ? `${this.currentModel().shortName} 已加载` : this.status
      this.notify()
      return true
    }).catch((err: Error) => {
      this.modelImportMessage = `保存失败：${formatError(err as Object)}`
      this.notify()
      return false
    })
  }

  requestDeleteModel(modelId: string): void {
    if (this.busy || this.modelLoading || this.modelImporting || this.builtinModelInstalling) {
      return
    }
    const profile = this.findProfile(modelId)
    if (profile === undefined || !this.canDeleteModel(modelId)) {
      return
    }
    this.pendingDeleteModelId = modelId
    this.showDeleteModelDialog = true
    this.notify()
  }

  cancelDeleteModel(): void {
    this.pendingDeleteModelId = ''
    this.showDeleteModelDialog = false
    this.notify()
  }

  confirmDeleteModel(): void {
    if (this.pendingDeleteModelId.length <= 0 || this.busy || this.modelLoading || this.modelImporting || this.builtinModelInstalling) {
      return
    }
    const modelId = this.pendingDeleteModelId
    const profile = this.findProfile(modelId)
    if (profile === undefined) {
      this.cancelDeleteModel()
      return
    }

    this.busy = true
    this.showDeleteModelDialog = false
    this.status = `正在删除 ${profile.shortName}...`
    this.notify()

    const deletingCurrent = this.selectedModelId === modelId
    this.modelLifecycleService.deleteModel(this.filesDir, profile, deletingCurrent && this.loaded)
      .then(async (result: ModelDeleteResult) => {
        if (deletingCurrent) {
          this.loaded = false
        }
        if (result.importedProfiles !== undefined) {
          this.modelManager.updateImportedProfiles(result.importedProfiles, this.filesDir)
        } else {
          await this.removeInstalledCatalogState(profile)
        }
        this.prepareImportedModelEditor(this.selectedModelId)
        this.pendingDeleteModelId = ''
        this.status = deletingCurrent ? `${profile.shortName} 已删除，请重新安装或选择其他模型。` : this.status
        this.busy = false
        this.modelImporting = false
        this.refreshModelMarketInstallStates()
        this.notify()
      }).catch((err: Error) => {
        this.pendingDeleteModelId = ''
        this.status = `删除失败：${formatError(err as Object)}`
        this.busy = false
        this.modelImporting = false
        this.notify()
      })
  }

  refreshModelMarketInstallStates(): void {
    const installedIds: string[] = []
    const checks = this.modelCatalogService.knownItems().map((item: ModelCatalogItem) => {
      return this.builtinModelInstallService.isCatalogItemInstalled(this.filesDir, item).then((installed: boolean) => {
        if (installed) {
          installedIds.push(item.id)
        }
      }).catch((_err: Error) => {
      })
    })
    Promise.all(checks).then(() => {
      this.modelMarketInstalledIds = installedIds
      this.notify()
    }).catch((_err: Error) => {
    })
  }

  moveModelToIndex(modelId: string, targetIndex: number): void {
    if (this.busy || this.modelLoading || this.modelImporting || this.builtinModelInstalling) {
      return
    }
    const visibleIds = this.modelProfiles().map((profile: ModelProfile) => profile.id)
    const currentIndex = visibleIds.indexOf(modelId)
    const nextIndex = Math.max(0, Math.min(visibleIds.length - 1, Math.round(targetIndex)))
    if (currentIndex < 0 || currentIndex === nextIndex) {
      return
    }
    const allIds = this.modelManager.modelOrderIds()
    const nextOrder = reorderVisibleModelIds(allIds, visibleIds, modelId, nextIndex)
    this.modelManager.setModelOrder(nextOrder, this.filesDir)
    this.saveModelOrder()
    this.notify()
  }

  canDeleteModel(modelId: string): boolean {
    const profile = this.findProfile(modelId)
    if (profile === undefined) {
      return false
    }
    if (profile.source === 'imported') {
      return true
    }
    const catalogItemId = this.catalogItemIdForProfile(profile)
    return catalogItemId.length > 0 && this.modelMarketInstalledIds.indexOf(catalogItemId) >= 0
  }

  pendingDeleteModel(): ModelProfile | undefined {
    if (this.pendingDeleteModelId.length <= 0) {
      return undefined
    }
    return this.findProfile(this.pendingDeleteModelId)
  }

  dismissTopDialogIfIdle(): boolean {
    if (!this.hasVisibleDialog()) {
      return false
    }
    if (this.isDialogDismissBlocked()) {
      return true
    }
    if (this.showDeleteModelDialog) {
      this.cancelDeleteModel()
      return true
    }
    if (this.showModelMarketDialog) {
      this.closeModelMarketDialog()
      return true
    }
    if (this.showBuiltinModelInstallDialog) {
      this.closeBuiltinModelInstallDialog()
      return true
    }
    if (this.showModelLoadDialog) {
      this.closeModelLoadDialog()
      return true
    }
    return true
  }

  private hasVisibleDialog(): boolean {
    return this.showDeleteModelDialog ||
      this.showModelMarketDialog ||
      this.showBuiltinModelInstallDialog ||
      this.showModelLoadDialog
  }

  private isDialogDismissBlocked(): boolean {
    return this.busy ||
      this.generating ||
      this.generationStopping ||
      this.modelLoading ||
      this.modelImporting ||
      this.builtinModelInstalling
  }

  private async removeInstalledCatalogState(profile: ModelProfile): Promise<void> {
    const catalogItemId = this.catalogItemIdForProfile(profile)
    if (catalogItemId.length <= 0) {
      return
    }
    await this.modelCatalogService.removeInstalled(this.filesDir, catalogItemId)
    this.modelManager.updateCatalogProfiles(this.modelCatalogService.profiles(), this.filesDir)
    this.modelMarketInstalledIds = this.modelMarketInstalledIds.filter((itemId: string) => itemId !== catalogItemId)
  }

  private async migrateBundledCatalogInstalls(): Promise<void> {
    const bundledItems = this.modelCatalogService.bundledItems()
    let changed = false
    for (let index = 0; index < bundledItems.length; index++) {
      const item = bundledItems[index]
      if (this.modelCatalogService.hasInstalledSnapshot(item.id)) {
        continue
      }
      try {
        if (await this.builtinModelInstallService.isCatalogItemInstalled(this.filesDir, item)) {
          await this.modelCatalogService.recordInstalled(this.filesDir, item)
          changed = true
        }
      } catch (_) {
      }
    }
    if (changed) {
      this.modelManager.updateCatalogProfiles(this.modelCatalogService.profiles(), this.filesDir)
    }
  }

  private applyCatalogResult(result: ModelCatalogLoadResult): void {
    this.modelCatalogSource = result.source
    this.modelCatalogVersion = result.catalogVersion
    this.modelCatalogPublishedAt = result.publishedAt
    this.modelCatalogStatus = result.message
    this.modelManager.updateCatalogProfiles(this.modelCatalogService.profiles(), this.filesDir)
    this.notify()
  }

  private shouldShowModelProfile(profile: ModelProfile): boolean {
    if (profile.source === 'imported') {
      return true
    }
    const catalogItemId = this.catalogItemIdForProfile(profile)
    if (catalogItemId.length <= 0) {
      return true
    }
    if (profile.source === 'builtin' && isBundledPresetCatalogItem(catalogItemId)) {
      return true
    }
    return this.modelMarketInstalledIds.indexOf(catalogItemId) >= 0
  }

  private catalogItemIdForProfile(profile: ModelProfile): string {
    if (profile.catalogItemId !== undefined && profile.catalogItemId.length > 0) {
      return profile.catalogItemId
    }
    if (profile.downloadId !== undefined && profile.downloadId.length > 0) {
      return profile.downloadId
    }
    return ''
  }

  clearSelectedImage(): void {
    this.selectedImageUri = ''
    this.notify()
  }

  toggleMessageThinking(messageId: number): void {
    this.session.toggleThinkingExpanded(messageId)
    this.syncMessages()
    this.notify()
  }

  unloadModel(): void {
    if (this.busy || this.modelLoading) {
      return
    }
    this.cancelSpeechRecognition(false)
    this.modelLifecycleService.reset()
    this.loaded = false
    this.status = '模型已释放'
    this.modelLoadMessage = '模型已从内存中释放，可重新加载。'
    this.session.appendMessage('assistant',
      `${this.currentModel().shortName} 已从内存中释放。当前不会继续占用推理内存；如需继续对话，请在模型页重新加载该模型，或切换并加载其他模型。`, '', false)
    this.syncMessages()
    this.refreshStats()
    this.notify()
  }

  newChat(): void {
    this.cancelSpeechRecognition(false)
    this.session.newChat(this.loaded, this.currentModel().shortName)
    this.syncMessages()
    this.inputText = ''
    this.selectedImageUri = ''
    this.status = this.loaded ? `${this.currentModel().shortName} 已加载` : '模型未加载'
    this.notifyAndScroll()
  }

  refreshStats(): void {
    this.stats = this.statsService.readStats()
    this.notify()
  }

  private refreshStorageStats(): void {
    const modelConfig = this.modelPath
    this.readStorageStatsForModel(this.currentModel(), modelConfig).then((storageStats: StorageStats) => {
      this.cacheStorageStats(modelConfig, storageStats)
    }).catch((_err: Error) => {
    })
  }

  readStorageStatsForCurrentModel(): Promise<StorageStats> {
    return this.readStorageStatsForModel(this.currentModel(), this.modelPath)
  }

  storageStatsForCurrentModel(): StorageStats {
    const currentModelStorage = this.modelStorageStats.get(this.modelPath)
    if (currentModelStorage === undefined) {
      return this.storageStats
    }
    return {
      appFiles: this.storageStats.appFiles,
      currentModel: currentModelStorage
    }
  }

  cacheStorageStats(modelConfig: string, storageStats: StorageStats): void {
    this.modelStorageStats.set(modelConfig, storageStats.currentModel)
    if (modelConfig === this.modelPath) {
      this.storageStats = storageStats
    }
  }

  private applyCurrentModelStorageStats(): void {
    this.storageStats = this.storageStatsForCurrentModel()
  }

  private preloadModelStorageStats(): void {
    const profiles = this.modelManager.profiles()
    for (let index = 0; index < profiles.length; index++) {
      const profile = profiles[index]
      const modelConfig = this.modelManager.defaultConfigPath(this.filesDir, profile)
      this.readModelStorage(profile, modelConfig).then((currentModelStorage: string) => {
        this.modelStorageStats.set(modelConfig, currentModelStorage)
      }).catch((_err: Error) => {
      })
    }
  }

  private readStorageStatsForModel(model: ModelProfile, modelConfig: string): Promise<StorageStats> {
    const modelDir = modelConfig.length > 0 ? modelConfig.substring(0, modelConfig.lastIndexOf('/')) : ''
    return this.modelLifecycleService.isInstalled(this.filesDir, model, modelConfig).then((installed: boolean) => {
      return this.statsService.readStorageStats(this.filesDir, installed ? modelDir : '')
    })
  }

  private readModelStorage(model: ModelProfile, modelConfig: string): Promise<string> {
    const modelDir = modelConfig.length > 0 ? modelConfig.substring(0, modelConfig.lastIndexOf('/')) : ''
    return this.modelLifecycleService.isInstalled(this.filesDir, model, modelConfig).then((installed: boolean) => {
      return installed ? this.statsService.readCurrentModelStorage(modelDir) : '未安装'
    })
  }

  openModelLoadDialog(autoStart: boolean = false): void {
    this.ensureCurrentModelInstalled().then((installed: boolean) => {
      if (!installed) {
        return
      }
      this.showModelLoadDialog = true
      this.modelLoadProgress = this.loaded ? 100 : 0
      this.modelLoadMessage = this.loaded ? `${this.currentModel().shortName} 已加载，可以开始聊天。` : `${this.currentModel().shortName} 尚未加载，点击加载模型开始。`
      this.notify()
      if (autoStart) {
        setTimeout(() => {
          if (this.showModelLoadDialog && !this.loaded && !this.modelLoading) {
            this.startModelLoad()
          }
        }, 350)
      }
    }).catch((err: Error) => {
      this.status = `检查模型失败：${formatError(err as Object)}`
      this.notify()
    })
  }

  closeModelLoadDialog(): void {
    this.showModelLoadDialog = false
    this.notifyAndScroll()
  }

  loadModel(): void {
    this.ensureCurrentModelInstalled().then((installed: boolean) => {
      if (!installed) {
        return
      }
      this.resetGenerationSettings(false)
      this.startModelLoad()
    }).catch((err: Error) => {
      this.status = `检查模型失败：${formatError(err as Object)}`
      this.notify()
    })
  }

  applyRuntimeConfigAndLoad(): void {
    if (this.busy || this.modelLoading || this.modelImporting || this.builtinModelInstalling) {
      return
    }
    if (this.loaded) {
      this.modelLifecycleService.reset()
      this.loaded = false
    }
    this.ensureCurrentModelInstalled().then((installed: boolean) => {
      if (!installed) {
        return
      }
      this.startModelLoad()
    }).catch((err: Error) => {
      this.status = `检查模型失败：${formatError(err as Object)}`
      this.notify()
    })
  }

  startModelLoad(): void {
    if (this.modelLoading) {
      return
    }
    if (this.showBuiltinModelInstallDialog) {
      return
    }
    this.busy = true
    this.modelLoading = true
    this.showModelLoadDialog = true
    this.status = `正在加载 ${this.currentModel().shortName}...`
    this.modelLoadMessage = '正在加载模型权重，请保持应用在前台。'
    this.startModelLoadProgress()
    this.notify()

    this.modelLifecycleService.loadModel(
      this.filesDir,
      this.currentModel(),
      this.modelPath,
      this.threadNum,
      this.maxNewTokens,
      this.currentGenerationSettings()
    ).then((loaded: boolean) => {
      this.loaded = loaded
      this.runtimeConfigDirty = false
      this.status = `${this.currentModel().shortName} 已加载`
      this.modelLoadMessage = `${this.currentModel().shortName} 加载完成，可以开始聊天。`
      this.stopModelLoadProgress()
      this.modelLoadProgress = 100
      this.session.appendMessage('assistant', `${this.currentModel().shortName} 加载完成，现在可以开始提问。`, '', false)
      this.syncMessages()
      this.busy = false
      this.modelLoading = false
      this.refreshStats()
      this.notifyAndScroll()
      setTimeout(() => {
        this.showModelLoadDialog = false
        this.notifyAndScroll()
      }, 450)
    }).catch((err: Error) => {
      this.loaded = false
      this.status = `加载失败：${formatError(err as Object)}`
      const loadErrorMessage = `${this.currentModel().shortName} 加载失败，可能是设备可用内存不足。请关闭后台应用、释放其他模型或重启 App 后重试。\n\n${this.status}`
      this.stopModelLoadProgress()
      this.modelLoadProgress = 0
      this.modelLoadMessage = loadErrorMessage
      this.busy = false
      this.modelLoading = false
      this.refreshStats()
      this.notifyAndScroll()
    })
  }

  closeBuiltinModelInstallDialog(): void {
    if (this.builtinModelInstalling) {
      return
    }
    if (this.builtinModelInstallCanceled) {
      const spec = this.currentBuiltinModelInstallSpec()
      if (spec !== undefined) {
        this.builtinModelInstallService.clearPartialDownload(this.filesDir, spec)
          .then((_removedBytes: number) => undefined)
          .catch((_err: Error) => undefined)
      }
    }
    this.showBuiltinModelInstallDialog = false
    this.pendingInstallCatalogItemId = ''
    this.autoLoadAfterInstall = false
    this.builtinModelInstallCanceled = false
    this.notify()
  }

  startBuiltinModelInstall(): void {
    if (this.builtinModelInstalling || this.context === undefined) {
      return
    }
    const spec = this.currentBuiltinModelInstallSpec()
    if (spec === undefined) {
      this.showBuiltinModelInstallDialog = false
      this.loadModel()
      return
    }
    this.prepareAndStartBuiltinModelInstall(this.context, spec)
  }

  private async prepareAndStartBuiltinModelInstall(
    context: common.UIAbilityContext,
    spec: BuiltinModelDownloadSpec
  ): Promise<void> {
    this.busy = true
    this.builtinModelInstalling = true
    this.builtinModelInstallCancelRequested = false
    this.builtinModelInstallCanceled = false
    this.showBuiltinModelInstallDialog = true
    this.builtinModelInstallError = ''
    this.builtinModelInstallTotalBytes = spec.totalBytes
    this.builtinModelInstallModelName = spec.displayName
    this.builtinModelInstallSourceName = spec.sourceName
    let existingBytes = 0
    try {
      existingBytes = await this.builtinModelInstallService.existingPartialDownloadBytes(this.filesDir, spec)
    } catch (_err) {
      existingBytes = 0
    }
    this.builtinModelInstallDownloadedBytes = existingBytes
    this.builtinModelInstallProgress = calculateDownloadProgress(existingBytes, spec.totalBytes)
    this.builtinModelInstallMessage = existingBytes > 0 ?
      `正在继续下载 ${spec.displayName}。请保持 App 在前台。` :
      `正在从 ${spec.sourceName} 下载 ${spec.displayName}。请保持 App 在前台。`
    this.status = `正在安装 ${spec.displayName}...`
    this.notify()

    const supportsImage = this.modelCatalogService.findInstallItem(spec.id)?.supportsImage ?? false
    this.modelLifecycleService.installCatalogItem(context, spec, supportsImage, (progress: BuiltinModelInstallProgress) => {
      if (this.builtinModelInstallCancelRequested) {
        return
      }
      if (progress.downloadedBytes < this.builtinModelInstallDownloadedBytes) {
        return
      }
      this.builtinModelInstallProgress = progress.progress
      this.builtinModelInstallDownloadedBytes = progress.downloadedBytes
      this.builtinModelInstallTotalBytes = progress.totalBytes
      this.builtinModelInstallFileName = progress.fileName
      this.builtinModelInstallMessage = `${progress.message}：${progress.fileName}`
      this.status = `正在安装 ${progress.modelName}...`
      this.notify()
    }).then(async () => {
      const installedItem = this.modelCatalogService.findMarketItem(spec.id) ??
        this.modelCatalogService.findInstallItem(spec.id)
      if (installedItem !== undefined) {
        await this.modelCatalogService.recordInstalled(this.filesDir, installedItem)
        this.modelManager.updateCatalogProfiles(this.modelCatalogService.profiles(), this.filesDir)
      }
      this.builtinModelInstalling = false
      this.busy = false
      this.builtinModelInstallProgress = 100
      this.builtinModelInstallMessage = this.autoLoadAfterInstall ?
        `${spec.displayName} 安装完成，正在加载模型。` :
        `${spec.displayName} 安装完成，可在模型列表中选择并加载。`
      this.status = `${spec.displayName} 安装完成`
      this.refreshModelMarketInstallStates()
      this.notify()
      setTimeout(() => {
        this.showBuiltinModelInstallDialog = false
        this.pendingInstallCatalogItemId = ''
        if (this.autoLoadAfterInstall) {
          this.autoLoadAfterInstall = false
          this.openModelLoadDialog(false)
          this.startModelLoad()
        } else {
          this.autoLoadAfterInstall = false
          this.notify()
        }
      }, 350)
    }).catch((err: Error) => {
      const canceled = this.builtinModelInstallCancelRequested
      this.builtinModelInstalling = false
      this.busy = false
      this.builtinModelInstallCancelRequested = false
      if (canceled) {
        this.builtinModelInstallError = ''
        this.builtinModelInstallCanceled = true
        this.builtinModelInstallMessage = `${spec.displayName} 下载已停止；继续下载会断点续传，关闭弹窗会清理未完成文件。`
        this.status = `${spec.displayName} 下载已停止`
      } else {
        this.builtinModelInstallCanceled = false
        this.builtinModelInstallError = `安装失败：${formatDownloadError(err as Object)}`
        this.builtinModelInstallMessage = `${spec.displayName} 未安装完成，可以重试。`
        this.status = this.builtinModelInstallError
      }
      this.notify()
    })
  }

  cancelBuiltinModelInstall(): void {
    if (!this.builtinModelInstalling) {
      return
    }
    this.builtinModelInstallCancelRequested = true
    this.builtinModelInstallMessage = '正在停止下载，请稍候...'
    this.status = '正在停止模型下载...'
    this.builtinModelInstallService.cancelInstall()
    this.notify()
  }

  private syncBuiltinModelInstallPartialProgress(spec: BuiltinModelDownloadSpec): void {
    this.builtinModelInstallService.existingPartialDownloadBytes(this.filesDir, spec).then((downloadedBytes: number) => {
      if (this.builtinModelInstalling) {
        return
      }
      this.builtinModelInstallDownloadedBytes = downloadedBytes
      this.builtinModelInstallProgress = calculateDownloadProgress(downloadedBytes, spec.totalBytes)
      if (downloadedBytes > 0 && this.builtinModelInstallFileName.length <= 0) {
        this.builtinModelInstallMessage = `${spec.displayName} 检测到未完成下载，可继续下载或关闭弹窗清理。`
      }
      this.notify()
    }).catch((_err: Error) => undefined)
  }

  private currentBuiltinModelInstallSpec(): BuiltinModelDownloadSpec | undefined {
    if (this.pendingInstallCatalogItemId.length > 0) {
      return this.modelCatalogService.findMarketItem(this.pendingInstallCatalogItemId)
    }
    return this.builtinModelInstallService.getDownloadSpec(this.currentModel())
  }

  chooseImage(): void {
    if (!this.currentModel().supportsImage) {
      this.status = `${this.currentModel().shortName} 不支持图片输入。`
      this.notify()
      return
    }
    if (!this.context) {
      this.status = '选择图片失败：上下文不可用'
      this.notify()
      return
    }

    this.imageService.pickImage().then((uri: string | undefined) => {
      if (uri !== undefined && uri.length > 0) {
        this.selectedImageUri = uri
        this.notify()
      }
    }).catch((err: Error) => {
      this.status = `选择图片失败：${formatError(err as Object)}`
      this.notify()
    })
  }

  async sendMessage(): Promise<void> {
    const text = this.inputText.trim()
    if (!this.loaded || this.busy || text.length === 0) {
      return
    }

    const chatTurns = this.composeChatTurns(text)
    const attachedImage = this.selectedImageUri
    if (attachedImage.length > 0 && !this.currentModel().supportsImage) {
      this.status = `${this.currentModel().shortName} 不支持图片输入，请清除图片后发送。`
      this.notify()
      return
    }

    this.session.appendMessage('user', text, attachedImage)
    const assistantId = this.session.appendMessage('assistant', '', '')
    this.syncMessages()
    this.resumeChatAutoScroll()
    this.inputText = ''
    this.selectedImageUri = ''
    this.busy = true
    this.generating = true
    this.generationStopping = false
    this.streamingChars = 0
    this.latestPerfMetrics = undefined
    this.status = '等待首个输出片段...'
    this.refreshStats()
    this.notifyAndScroll()

    const assistantOutputPrefix = this.expectedAssistantOutputPrefixForCurrentModel()
    const generation = this.generationWorkflow.run({
      turns: chatTurns,
      imageUri: attachedImage,
      maxNewTokens: this.maxNewTokens,
      settings: this.currentGenerationSettings(),
      assistantOutputPrefix,
      stripLeadingAssistantSeparator: this.shouldStripLeadingAssistantSeparator()
    }, {
      onStatus: (status: string) => {
        this.status = status
        this.notify()
      },
      onStream: (update: GenerationStreamUpdate) => {
        this.handleStreamUpdate(assistantId, update)
      },
      isStopRequested: () => this.generationStopping
    })

    generation.then((outcome: GenerationWorkflowResult) => {
      this.latestPerfMetrics = outcome.perfMetrics
      this.streamingChars = outcome.answer.length
      this.session.updateMessage(
        assistantId,
        outcome.answer,
        outcome.includeInContext,
        outcome.result.stopReason === 'user_stop' ? undefined : outcome.perfMetrics
      )
      this.syncMessages()
      this.status = outcome.status
      this.busy = false
      this.generating = false
      this.generationStopping = false
      this.refreshStats()
      this.notifyAndMaybeScroll()
    }).catch((err: Error) => {
      const message = `生成失败：${formatError(err as Object)}`
      this.session.updateMessage(assistantId, message, false)
      this.syncMessages()
      this.status = message
      this.latestPerfMetrics = undefined
      this.busy = false
      this.generating = false
      this.generationStopping = false
      this.refreshStats()
      this.notifyAndScroll()
    })
  }

  stopGeneration(): void {
    if (!this.generating || this.generationStopping) {
      return
    }
    this.generationStopping = true
    this.status = '正在停止生成...'
    this.generationWorkflow.stop()
    this.notify()
  }

  scrollToBottom(): void {
    if (this.autoScrollPending) {
      return
    }
    this.autoScrollPending = true
    setTimeout(() => {
      this.autoScrollPending = false
      const lastIndex = this.messages.length - 1
      if (lastIndex < 0) {
        return
      }
      try {
        this.chatScroller.scrollToIndex(lastIndex, false, ScrollAlign.END)
      } catch (err) {
        try {
          this.chatScroller.scrollEdge(Edge.Bottom)
        } catch (_) {
        }
      }
    }, 30)
  }

  pauseChatAutoScroll(): void {
    this.chatAutoScrollEnabled = false
  }

  resumeChatAutoScroll(): void {
    this.chatAutoScrollEnabled = true
  }

  private resetLoadedModel(status: string): void {
    if (this.loaded) {
      this.modelLifecycleService.reset()
    }
    this.loaded = false
    this.status = status
    this.modelLoadProgress = 0
    this.modelLoadMessage = status
  }

  private ensureCurrentModelInstalled(): Promise<boolean> {
    const model = this.currentModel()
    const spec = this.builtinModelInstallService.getDownloadSpec(model)
    if (spec === undefined) {
      return Promise.resolve(true)
    }
    const defaultConfigPath = `${this.filesDir}/${model.directoryName}/config.json`
    if (this.modelPath !== defaultConfigPath) {
      return Promise.resolve(true)
    }
    return this.modelLifecycleService.isInstalled(this.filesDir, model, this.modelPath).then((installed: boolean) => {
      if (installed) {
        return true
      }
      this.pendingInstallCatalogItemId = spec.id
      this.autoLoadAfterInstall = true
      this.openBuiltinModelInstallDialog(spec, true)
      return false
    })
  }

  private openBuiltinModelInstallDialog(spec: BuiltinModelDownloadSpec, autoLoadAfterInstall: boolean = false): void {
    this.showModelLoadDialog = false
    this.stopModelLoadProgress()
    this.modelLoadProgress = 0
    this.showBuiltinModelInstallDialog = true
    this.builtinModelInstalling = false
    this.builtinModelInstallCanceled = false
    this.builtinModelInstallProgress = 0
    this.builtinModelInstallDownloadedBytes = 0
    this.builtinModelInstallTotalBytes = spec.totalBytes
    this.builtinModelInstallFileName = ''
    this.builtinModelInstallModelName = spec.displayName
    this.builtinModelInstallSourceName = spec.sourceName
    this.builtinModelInstallError = ''
    this.builtinModelInstallMessage = autoLoadAfterInstall ?
      `${spec.displayName} 模型目录缺失或不完整，请先下载模型文件。` :
      `准备从 ${spec.sourceName} 安装 ${spec.displayName}。`
    this.status = `${spec.displayName} 未安装`
    this.notify()
    this.syncBuiltinModelInstallPartialProgress(spec)
  }

  private composeChatTurns(text: string): ChatTurn[] {
    return this.session.composeChatTurns(this.currentModel().systemPrompt, text, this.currentContextMessageLimit())
  }

  currentContextMessageLimit(): number {
    const model = this.currentModel()
    if (model.contextMessageLimit !== undefined) {
      return Math.max(0, Math.round(model.contextMessageLimit))
    }
    if (model.source === 'imported') {
      return 0
    }
    return 6
  }

  private syncMessages(): void {
    this.messages = this.session.messages
  }

  private shouldStripLeadingAssistantSeparator(): boolean {
    return false
  }

  private expectedAssistantOutputPrefixForCurrentModel(): string {
    return ''
  }

  private currentGenerationSettings(): GenerationSettings {
    return {
      temperature: this.temperature,
      topP: this.topP,
      topK: this.topK,
      repetitionPenalty: this.repetitionPenalty,
      frequencyPenalty: this.frequencyPenalty,
      presencePenalty: this.presencePenalty,
      penaltyWindow: this.penaltyWindow
    }
  }

  private findProfile(modelId: string): ModelProfile | undefined {
    const profiles = this.modelProfiles()
    for (let index = 0; index < profiles.length; index++) {
      if (profiles[index].id === modelId) {
        return profiles[index]
      }
    }
    return undefined
  }

  private loadModelOrder(): void {
    if (this.context === undefined) {
      return
    }
    preferences.getPreferences(this.context, this.modelOrderPreferenceName).then((store: preferences.Preferences) => {
      return store.get(this.modelOrderPreferenceKey, '')
    }).then((value: preferences.ValueType) => {
      if (typeof value !== 'string' || value.length <= 0) {
        return
      }
      const order = JSON.parse(value.replace(/^\uFEFF/, '')) as string[]
      this.modelManager.setModelOrder(order, this.filesDir)
      this.notify()
    }).catch((_err: Error) => {
    })
  }

  private saveModelOrder(): void {
    if (this.context === undefined) {
      return
    }
    preferences.getPreferences(this.context, this.modelOrderPreferenceName).then((store: preferences.Preferences) => {
      return store.put(this.modelOrderPreferenceKey, JSON.stringify(this.modelManager.modelOrderIds()))
        .then(() => store.flush())
    }).catch((_err: Error) => {
    })
  }

  private handleStreamUpdate(assistantId: number, update: GenerationStreamUpdate): void {
    this.streamingChars = update.characterCount
    this.status = `正在生成... ${update.characterCount} 字符`
    this.session.updateMessage(assistantId, update.text)
    this.syncMessages()
    this.notify()
    if (this.chatAutoScrollEnabled) {
      this.scrollToBottom()
    }
  }

  private startModelLoadProgress(): void {
    this.stopModelLoadProgress()
    this.modelLoadProgress = 8
    this.modelLoadTimer = setInterval(() => {
      if (this.modelLoadProgress < 88) {
        this.modelLoadProgress = Math.min(88, this.modelLoadProgress + 4)
        this.notify()
      }
    }, 160)
  }

  private stopModelLoadProgress(): void {
    if (this.modelLoadTimer >= 0) {
      clearInterval(this.modelLoadTimer)
      this.modelLoadTimer = -1
    }
  }

  private notifyAndScroll(): void {
    this.notify()
    this.scrollToBottom()
  }

  private notifyAndMaybeScroll(): void {
    this.notify()
    if (this.chatAutoScrollEnabled) {
      this.scrollToBottom()
    }
  }

  private resetSpeechRecognitionState(): void {
    this.speechRecognitionStarting = false
    this.speechRecognizing = false
    this.speechRecognitionStopping = false
    this.speechDetected = false
  }

  private notify(): void {
    this.notifyCallback()
  }
}
