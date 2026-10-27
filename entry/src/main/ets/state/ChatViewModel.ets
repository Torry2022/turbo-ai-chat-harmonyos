import { ConversationTitleService, ConversationTitleRequest, conversationTitleSignature } from '../services/ConversationTitleService'
import { decideLaya, isLayaReady, LayaRuntimeState, observeLayaRuntime, releaseLaya } from '../services/LayaDecisionService'
import { ChatConversation, ChatConversationSummary, ChatHistorySearchResult, conversationTitle } from '../models/ChatHistoryTypes'
import { ChatHistoryService } from '../services/ChatHistoryService'
import { bundleManager, common } from '@kit.AbilityKit'
import preferences from '@ohos.data.preferences'
import cryptoFramework from '@ohos.security.cryptoFramework'
import { ChatMessage, ChatTurn, GenerationResult, GenerationSettings, PerfMetrics } from '../models/ChatTypes'
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
import { catalogCompatibilityMessage } from '../utils/modelCatalog'
import { NativeInferenceService } from '../services/NativeInferenceService'
import {
  ApiGenerationRequest,
  PreparedApiDecision,
  ApiServerModel,
  OpenAiApiServer
} from '../services/OpenAiApiServer'
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

export interface ApiServerLogEntry {
  id: number
  time: string
  level: string
  message: string
}

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
  private statusTone: 'neutral' | 'success' | 'warning' | 'error' = 'neutral'
  conversations: ChatConversationSummary[] = []
  activeConversationId: string = ''
  historyReady: boolean = false
  historyBusy: boolean = false
  historyError: string = ''
  private skipEditConfirmation: boolean = false
  historySearchText: string = ''
  historySearchResults: ChatHistorySearchResult[] = []
  historySearching: boolean = false
  historySearchError: string = ''
  highlightedMessageId: number = 0
  private historySearchTimer: number = -1
  private historySearchSerial: number = 0
  private activeConversation?: ChatConversation
  private historyService: ChatHistoryService = new ChatHistoryService()
  private conversationDrafts: Map<string, string> = new Map()
  private historyTimer: number = -1
  private historyCloseHandler: () => boolean = () => false
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
  startupAutoLoadEnabled: boolean = false
  startupModelId: string = ''
  showModelLoadDialog: boolean = false
  modelLoading: boolean = false
  modelLoadElapsedSeconds: number = 0
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
  modelScanning: boolean = false
  modelImportMessage: string = '可导入完整的 MNN 模型目录或 zip 包'
  editingImportedModelId: string = ''
  importedModelNameInput: string = ''
  importedModelShortNameInput: string = ''
  importedModelDescriptionInput: string = ''
  importedModelSystemPromptInput: string = ''
  showDeleteModelDialog: boolean = false
  pendingDeleteModelId: string = ''
  layaReady: boolean = false
  layaRuntimeState: LayaRuntimeState = 'idle'
  apiServiceTarget: 'chat' | 'decision' = 'chat'
  apiServerRunning: boolean = false
  apiServerStarting: boolean = false
  apiServerPortInput: string = '8080'
  apiServerRequireKey: boolean = true
  apiServerKey: string = ''
  apiServerAddress: string = 'http://设备局域网 IP:8080'
  apiServerStatus: string = 'API 服务未启动'
  apiServerRequestCount: number = 0
  apiServerLogs: ApiServerLogEntry[] = []
  stats: RuntimeStats = EMPTY_RUNTIME_STATS
  storageStats: StorageStats = EMPTY_STORAGE_STATS
  streamingChars: number = 0
  latestPerfMetrics?: PerfMetrics
  appVersion: string = ''
  appVersionCode: number = 0
  chatScroller: Scroller = new Scroller()

  private filesDir: string = ''
  private context?: common.UIAbilityContext
  private modelLoadTimer: number = -1
  private modelLoadStartedAt: number = 0
  private autoScrollPending: boolean = false
  private chatScrollTargetId: number = 0
  private chatAutoScrollEnabled: boolean = true
  private notifyCallback: () => void = () => {}
  private toastCallback: (message: string) => void = (_message: string) => {}
  private session: ChatSession = new ChatSession()
  private modelManager: ModelManager = new ModelManager()
  private nativeService: NativeInferenceService = new NativeInferenceService()
  private titleForeground: boolean = true
  private titleService: ConversationTitleService = new ConversationTitleService(
    () => this.canGenerateConversationTitle(),
    (turns: ChatTurn[]) => this.nativeService.generateTitle(turns),
    () => this.nativeService.cancelTitleGeneration(),
    (request: ConversationTitleRequest, title: string) => this.applyConversationTitle(request, title)
  )

  private imageService: ImagePayloadService = new ImagePayloadService()
  private modelCatalogService: ModelCatalogService = new ModelCatalogService()
  private builtinModelInstallService: BuiltinModelInstallService =
    new BuiltinModelInstallService(this.modelCatalogService)
  private modelImportService: ModelImportService = new ModelImportService()
  private statsService: RuntimeStatsService = new RuntimeStatsService()
  private speechRecognitionService: SpeechRecognitionService = new SpeechRecognitionService()
  private apiServer: OpenAiApiServer = new OpenAiApiServer({
    isModelLoaded: () => this.apiServiceTarget === 'chat' && this.loaded,
    isLayaReady: () => this.apiServiceTarget === 'decision' && isLayaReady(this.filesDir),
    isGenerationReady: () => this.apiServiceTarget === 'chat' && this.loaded && !this.modelScanning && !this.busy && !this.modelLoading,
    currentModel: () => this.apiServerModel(),
    currentSettings: () => this.currentGenerationSettings(),
    currentMaxNewTokens: () => this.maxNewTokens,
    generate: (request: ApiGenerationRequest, onChunk: (chunk: string) => void) => {
      return this.runApiGeneration(request, onChunk)
    },
    decide: (request: PreparedApiDecision) => decideLaya(this.filesDir, request.state, request.type,
      request.instruction, request.options),
    stopGeneration: () => this.stopGeneration(),
    onStatus: (status: string) => {
      if (status.startsWith('API 请求：')) {
        this.apiServerRequestCount++
      }
      this.apiServerStatus = status
      this.notify()
    },
    onLog: (level: string, message: string) => {
      this.appendApiServerLog(level, message)
    }
  })
  private modelStorageStats: Map<string, string> = new Map()
  private generationWorkflow: GenerationWorkflow = new GenerationWorkflow(this.nativeService, this.imageService)
  private modelLifecycleService: ModelLifecycleService = new ModelLifecycleService(
    this.nativeService,
    this.builtinModelInstallService,
    this.modelImportService
  )
  private pendingInstallCatalogItemId: string = ''
  private autoLoadAfterInstall: boolean = false
  private apiServerStartAfterModelLoad: boolean = false
  private builtinModelInstallCancelRequested: boolean = false
  private readonly modelOrderPreferenceName: string = 'model-settings'
  private readonly modelOrderPreferenceKey: string = 'model-order'
  private readonly startupAutoLoadPreferenceKey: string = 'startup-auto-load'
  private readonly startupModelPreferenceKey: string = 'startup-model-id'
  private startupSettingsReady: boolean = false
  private startupLoadStarted: boolean = false
  private readonly apiServerPreferenceName: string = 'api-server-settings'
  private readonly apiServerPortPreferenceKey: string = 'port'
  private readonly apiServerRequireKeyPreferenceKey: string = 'require-key'
  private readonly apiServerKeyPreferenceKey: string = 'api-key'
  private readonly apiServerLogLimit: number = 100
  private nextApiServerLogId: number = 1

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
    observeLayaRuntime((state: LayaRuntimeState) => {
      this.layaRuntimeState = state
      this.refreshLayaReady()
      this.notify()
    })
    this.layaReady = isLayaReady(this.filesDir)
    try {
      const bundleInfo = bundleManager.getBundleInfoForSelfSync(
        bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT
      )
      this.appVersion = bundleInfo.versionName
      this.appVersionCode = bundleInfo.versionCode
    } catch (_) {
      this.appVersion = ''
      this.appVersionCode = 0
    }
    this.modelManager.initialize(this.filesDir)
    this.loadModelOrder()
    this.loadStartupModelSettings()
    this.loadChatActionSettings()
    this.loadApiServerSettings()
    this.resetGenerationSettings(false)
    this.historyService.onAttachmentError = () => {
      this.historyError = '对话文字已保存，但有图片未能保存。请重试。'
      this.notify()
    }
    this.initializeHistory()
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
      this.tryStartStartupModelLoad()
      this.notify()
    }).catch((err: Error) => {
      this.modelImportMessage = `读取导入模型失败：${formatError(err as Object)}`
      this.notify()
    })
  }

  dispose(): void {
    this.titleService.dispose()
    clearTimeout(this.historySearchTimer)
    this.historySearchSerial++
    this.flushHistory().catch((error: Error) => console.error(`保存对话失败：${formatError(error as Object)}`))
    this.stopModelLoadTimer()
    this.speechRecognitionService.shutdown()
    this.resetSpeechRecognitionState()
    this.apiServer.stop().catch((_err: Error) => {
    })
    this.apiServerRunning = false
  }

  modelProfiles(): ModelProfile[] {
    return this.modelManager.profiles().filter((profile: ModelProfile) => this.shouldShowModelProfile(profile))
  }

  currentModel(): ModelProfile {
    return this.modelManager.currentModel()
  }

  startupModelName(): string {
    const profile = this.modelManager.profiles().find((item: ModelProfile) => item.id === this.startupModelId)
    return profile?.shortName ?? this.startupModelId
  }

  setStartupAutoLoad(enabled: boolean): void {
    if (!enabled && this.startupModelId !== this.selectedModelId) {
      return
    }
    this.startupAutoLoadEnabled = enabled
    if (enabled) {
      this.startupModelId = this.selectedModelId
    }
    this.saveStartupModelSettings()
    this.notify()
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

  catalogCompatibilityMessage(item: BuiltinModelDownloadSpec): string {
    return catalogCompatibilityMessage(item, this.appVersionCode)
  }

  private rejectIncompatibleCatalogItem(item: BuiltinModelDownloadSpec): boolean {
    const message = this.catalogCompatibilityMessage(item)
    if (message.length === 0) {
      return false
    }
    this.apiServerStartAfterModelLoad = false
    this.setStatus(`${item.displayName}：${message}`, 'neutral')
    this.toastCallback?.(this.status)
    this.notify()
    return true
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

  refreshApiServerAddress(): void {
    const port = this.apiServerPort()
    this.apiServer.refreshLanAddress(port).then((address: string) => {
      this.apiServerAddress = address
      this.notify()
    }).catch((_err: Error) => {
    })
  }

  clearApiServerLogs(): void {
    this.apiServerLogs = []
    this.notify()
  }

  updateApiServerPort(value: string): void {
    if (this.apiServerRunning || this.apiServerStarting) {
      return
    }
    this.apiServerPortInput = value.replace(/[^0-9]/g, '').substring(0, 5)
    this.apiServerAddress = `http://设备局域网 IP:${this.apiServerPortInput.length > 0 ? this.apiServerPortInput : '8080'}`
    this.saveApiServerSettings()
    this.notify()
  }

  updateApiServerRequireKey(value: boolean): void {
    if (this.apiServerRunning || this.apiServerStarting) {
      return
    }
    this.apiServerRequireKey = value
    this.saveApiServerSettings()
    this.notify()
  }

  regenerateApiServerKey(): void {
    if (this.apiServerRunning || this.apiServerStarting) {
      return
    }
    this.createApiServerKey(true)
  }

  setApiServerEnabled(enabled: boolean): void {
    if (enabled && this.rejectWhileModelScanning()) {
      return
    }
    if (this.apiServerStarting || enabled === this.apiServerRunning) {
      return
    }
    if (!enabled) {
      this.apiServerStartAfterModelLoad = false
      this.apiServerStarting = true
      this.apiServer.stop().then(() => {
        this.apiServerRunning = false
        this.apiServerStarting = false
        this.notify()
      }).catch((err: Error) => {
        this.apiServerStarting = false
        this.apiServerStatus = `停止 API 服务失败：${formatError(err as Object)}`
        this.appendApiServerLog('ERROR', `停止服务失败：${formatError(err as Object)}`)
        this.notify()
      })
      this.notify()
      return
    }
    this.layaReady = isLayaReady(this.filesDir)
    if (this.apiServiceTarget === 'decision' && !this.layaReady) {
      this.toastCallback('请先在模型页安装 Laya')
      return
    }
    if (this.apiServiceTarget === 'chat' && !this.loaded) {
      this.apiServerStartAfterModelLoad = true
      this.toastCallback('请先加载模型')
      this.openModelLoadDialog(false)
      this.notify()
      return
    }
    this.apiServerStartAfterModelLoad = false
    if (this.busy || this.modelLoading) {
      this.apiServerStatus = '当前任务结束后才能启动 API 服务。'
      this.notify()
      return
    }
    const port = this.apiServerPort()
    if (port < 1024 || port > 65535) {
      this.apiServerStatus = '端口应为 1024 至 65535。'
      this.notify()
      return
    }
    if (this.apiServerRequireKey && this.apiServerKey.length <= 0) {
      this.apiServerStatus = '请先生成 API Key。'
      this.notify()
      return
    }
    this.apiServerStarting = true
    this.saveApiServerSettings()
    this.apiServer.start({
      port,
      target: this.apiServiceTarget,
      requireApiKey: this.apiServerRequireKey,
      apiKey: this.apiServerKey
    }).then((address: string) => {
      this.apiServerAddress = address
      this.apiServerRunning = true
      this.apiServerStarting = false
      this.notify()
    }).catch((err: Error) => {
      this.apiServerRunning = false
      this.apiServerStarting = false
      this.apiServerStatus = `启动 API 服务失败：${formatError(err as Object)}`
      this.appendApiServerLog('ERROR', `启动服务失败：${formatError(err as Object)}`)
      this.notify()
    })
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
    if (this.rejectWhileModelScanning()) {
      return
    }
    if (this.busy || this.modelLoading || this.modelImporting || this.builtinModelInstalling ||
      this.modelCatalogRefreshing || this.context === undefined) {
      return
    }
    const item = this.modelCatalogService.findMarketItem(catalogItemId)
    if (item === undefined) {
      this.setStatus('安装失败：模型广场条目不存在', 'error')
      this.notify()
      return
    }
    if (this.rejectIncompatibleCatalogItem(item)) {
      return
    }
    this.pendingInstallCatalogItemId = item.id
    this.autoLoadAfterInstall = item.modelId === this.selectedModelId
    this.showModelMarketDialog = false
    this.openBuiltinModelInstallDialog(item, this.autoLoadAfterInstall)
    this.startBuiltinModelInstall()
  }

  switchModel(modelId: string): void {
    if (this.rejectWhileModelScanning()) {
      return
    }
    if (this.busy || this.modelLoading || this.apiServerStarting || modelId === this.selectedModelId) {
      return
    }

    this.cancelSpeechRecognition(false)
    const model = this.modelManager.switchModel(modelId, this.filesDir)
    this.applyCurrentModelStorageStats()
    this.prepareImportedModelEditor(model.id)
    if (!model.supportsImage) {
      this.selectedImageUri = ''
    }
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
    this.setStatus(this.loaded ? '运行配置已修改，应用并重新加载后生效。' : '运行配置已修改，应用并加载后生效。', 'neutral')
    this.notify()
  }

  updateInputText(value: string): void {
    if (value.trim()) this.titleService.pause()
    this.inputText = value
    this.storeDraft(this.activeConversationId, value)
    this.notify()
  }

  private storeDraft(id: string, text: string): void {
    if (text.length > 0) this.conversationDrafts.set(id, text)
    else this.conversationDrafts.delete(id)
  }

  private restoreDraft(id: string): void {
    this.inputText = this.conversationDrafts.get(id) ?? ''
  }

  async startSpeechRecognition(): Promise<void> {
    if (this.rejectWhileModelScanning()) {
      return
    }
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
    this.setStatus('正在准备语音识别...', 'neutral')
    this.notify()
    const callbacks: SpeechRecognitionCallbacks = {
      onStarted: () => {
        this.speechRecognitionStarting = false
        this.speechRecognizing = true
        this.setStatus('正在聆听...', 'neutral')
        this.notify()
      },
      onSpeechActivity: (active: boolean) => {
        this.speechDetected = active
        this.setStatus(active ? '正在识别语音...' : '正在等待继续说话...', 'neutral')
        this.notify()
      },
      onTranscript: (text: string) => {
        this.updateInputText(text)
      },
      onCompleted: () => {
        this.resetSpeechRecognitionState()
        this.setStatus(this.inputText.trim().length > 0 ? '语音识别完成，可编辑后发送' : '未识别到语音', 'success')
        this.notify()
      },
      onError: (message: string) => {
        this.resetSpeechRecognitionState()
        this.setStatus(`语音识别失败：${message}`, 'error')
        this.toastCallback('语音识别失败，请重试')
        this.notify()
      }
    }
    try {
      await this.speechRecognitionService.start(this.context, callbacks)
      if (this.speechRecognitionStarting) {
        this.speechRecognitionStarting = false
        this.speechRecognizing = true
        this.setStatus('正在聆听...', 'neutral')
        this.notify()
      }
    } catch (err) {
      this.resetSpeechRecognitionState()
      console.error(`启动语音识别失败：${formatError(err as Object)}`)
      const message = (err as Error).message
      this.setStatus(message && message.trim().length > 0 ? message : '无法启动语音输入，请重试', 'error')
      this.toastCallback(this.status)
      this.notify()
    }
  }

  stopSpeechRecognition(): void {
    if (!this.speechRecognizing || this.speechRecognitionStopping) {
      return
    }
    this.speechRecognitionStopping = true
    this.setStatus('正在完成语音识别...', 'success')
    try {
      this.speechRecognitionService.finish()
    } catch (err) {
      this.resetSpeechRecognitionState()
      this.setStatus(`停止语音识别失败：${formatError(err as Object)}`, 'error')
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
    this.setStatus(this.loaded ? '运行配置已修改，应用并重新加载后生效。' : '运行配置已修改，应用并加载后生效。', 'neutral')
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

  importModelPackage(folder: boolean = false): void {
    if (this.rejectWhileModelScanning()) {
      return
    }
    if (this.busy || this.modelLoading || this.modelImporting || this.builtinModelInstalling ||
      this.apiServerStarting) {
      return
    }
    if (!this.context) {
      this.modelImportMessage = '导入失败：上下文不可用'
      this.notify()
      return
    }

    this.busy = true
    this.modelImporting = true
    this.modelImportMessage = folder ? '请选择包含完整 MNN 模型文件的文件夹' : '请选择 MNN 模型 zip 包；解压需要额外空间'
    this.setStatus('正在导入模型...', 'neutral')
    this.notify()

    this.modelLifecycleService.importPickedModel(this.context, this.modelProfiles(), folder).then((result) => {
      if (result === undefined) {
        this.modelImportMessage = '已取消导入模型'
        this.setStatus(this.loaded ? `${this.currentModel().shortName} 已加载` : '模型未加载', this.loaded ? 'success' : 'neutral')
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
      const message = `导入失败：${err.message || formatError(err as Object)}`
      this.modelImportMessage = message
      this.setStatus(message, 'error')
      this.busy = false
      this.modelImporting = false
      this.refreshStats()
      this.notify()
    })
  }

  async scanPushedModelDirectories(): Promise<void> {
    if (this.modelScanning || this.busy || this.modelLoading || this.modelImporting || this.builtinModelInstalling ||
      this.apiServerStarting) {
      return
    }

    this.modelScanning = true
    this.modelImportMessage = '正在扫描已推送目录...'
    this.notify()

    try {
      const result = await this.modelLifecycleService.scanPushedModels(this.filesDir, this.modelProfiles())
      const addedProfile = result.addedProfiles.length > 0 ? result.addedProfiles[result.addedProfiles.length - 1] : undefined
      if (addedProfile !== undefined) {
        this.modelManager.updateImportedProfiles(result.profiles, this.filesDir)
        const model = this.modelManager.switchModel(addedProfile.id, this.filesDir)
        this.prepareImportedModelEditor(model.id)
        this.selectedImageUri = ''
        this.resetGenerationSettings(false)
        this.session.resetForModelSwitch(model.shortName)
        this.syncMessages()
        this.resetLoadedModel(`已添加 ${result.addedProfiles.length} 个模型，请加载 ${model.shortName}。`)
        this.modelImportMessage = `已添加 ${result.addedProfiles.length} 个模型，请加载 ${model.shortName}。`
        if (result.errors.length > 0) {
          this.modelImportMessage += ` 部分目录未导入：${result.errors[0]}`
        }
      } else {
        this.modelImportMessage = result.errors.length > 0 ?
          `未导入模型：${result.errors[0]}` :
          (result.skippedCount > 0 ?
            '未发现新的可导入 MNN 目录，请检查目录完整性与对话模板。' :
            '未发现新的已推送模型目录。')
        if (result.errors.length === 0) {
          this.toastCallback('未发现新模型，请用电脑 hdc 将完整模型目录推入应用沙箱 files/model-imports 后重试')
        }
      }
    } catch (err) {
      const message = `扫描失败：${formatError(err as Object)}`
      this.modelImportMessage = message
    } finally {
      this.modelScanning = false
      this.notify()
    }
  }

  private rejectWhileModelScanning(): boolean {
    if (!this.modelScanning) {
      return false
    }
    this.toastCallback('正在扫描模型目录，请稍候')
    return true
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
    if (this.rejectWhileModelScanning()) {
      return Promise.resolve(false)
    }
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
      this.setStatus(this.loaded ? `${this.currentModel().shortName} 已加载` : this.status, this.loaded ? 'success' : 'neutral')
      this.notify()
      return true
    }).catch((err: Error) => {
      this.modelImportMessage = `保存失败：${formatError(err as Object)}`
      this.notify()
      return false
    })
  }

  requestDeleteModel(modelId: string): void {
    if (this.rejectWhileModelScanning()) {
      return
    }
    if (this.busy || this.modelLoading || this.modelImporting || this.builtinModelInstalling ||
      this.apiServerStarting) {
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
    if (this.rejectWhileModelScanning()) {
      return
    }
    if (this.pendingDeleteModelId.length <= 0 || this.busy || this.modelLoading || this.modelImporting ||
      this.builtinModelInstalling || this.apiServerStarting) {
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
    this.setStatus(`正在删除 ${profile.shortName}...`, 'neutral')
    this.notify()

    const deletingCurrent = this.selectedModelId === modelId
    if (deletingCurrent) {
      this.stopApiServerForModelChange(false)
    }
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
        if (this.startupModelId === modelId) {
          this.startupAutoLoadEnabled = false
          this.startupModelId = ''
          this.saveStartupModelSettings()
        }
        this.prepareImportedModelEditor(this.selectedModelId)
        this.pendingDeleteModelId = ''
        this.setStatus(deletingCurrent ? `${profile.shortName} 已删除，请重新安装或选择其他模型。` : `${profile.shortName} 已删除`, 'success')
        this.busy = false
        this.modelImporting = false
        this.refreshModelMarketInstallStates()
        this.notify()
      }).catch((err: Error) => {
        this.pendingDeleteModelId = ''
        this.setStatus(`删除失败：${formatError(err as Object)}`, 'error')
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
    if (this.rejectWhileModelScanning()) {
      return
    }
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
      this.apiServerStarting ||
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
      this.tryStartStartupModelLoad()
    }
  }

  private applyCatalogResult(result: ModelCatalogLoadResult): void {
    this.modelCatalogSource = result.source
    this.modelCatalogVersion = result.catalogVersion
    this.modelCatalogPublishedAt = result.publishedAt
    this.modelCatalogStatus = result.message
    this.modelManager.updateCatalogProfiles(this.modelCatalogService.profiles(), this.filesDir)
    this.tryStartStartupModelLoad()
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

  async unloadModel(): Promise<void> {
    if (this.rejectWhileModelScanning()) {
      return
    }
    if (this.busy || this.modelLoading || this.apiServerStarting) {
      return
    }
    this.cancelSpeechRecognition(false)
    this.stopApiServerForModelChange(false)
    this.titleService.pause()
    this.loaded = false
    this.busy = true
    this.setStatus('正在释放模型...', 'neutral')
    this.notify()
    try {
      await this.modelLifecycleService.reset()
    } catch (error) {
      this.busy = false
      this.setStatus(`释放模型失败：${formatError(error as Object)}`, 'error')
      this.notify()
      return
    }
    this.busy = false
    this.setStatus('模型已释放', 'neutral')
    this.modelLoadMessage = '模型已从内存中释放，可重新加载。'
    this.session.appendMessage('assistant',
      `${this.currentModel().shortName} 已从内存中释放。当前不会继续占用推理内存；如需继续对话，请在模型页重新加载该模型，或切换并加载其他模型。`, '', false)
    this.syncMessages()
    this.refreshStats()
    this.notify()
  }

  newChat(): void {
    if (!this.canManageConversations()) return
    this.beginNewConversation()
  }

  bindHistoryClose(handler: () => boolean): void {
    this.historyCloseHandler = handler
  }

  closeHistoryDrawer(): boolean {
    return this.historyCloseHandler()
  }

  currentConversationTitle(_renderVersion: number = 0): string {
    return this.activeConversation?.title ?? '新对话'
  }

  canManageConversations(): boolean {
    return this.historyReady && !this.historyBusy && !this.busy && !this.generating && !this.modelLoading &&
      !this.modelScanning && !this.apiServerStarting
  }

  canEditQuestion(messageId: number): boolean {
    return this.canManageConversations() && this.loaded && !this.speechRecognitionStarting &&
      !this.speechRecognizing && this.session.messages.some((message: ChatMessage) =>
        message.id === messageId && message.role === 'user' && message.kind !== 'notice')
  }

  needsEditQuestionConfirmation(messageId: number): boolean {
    const index = this.session.messages.findIndex((message: ChatMessage) =>
      message.id === messageId && message.role === 'user' && message.kind !== 'notice')
    return !this.skipEditConfirmation && index >= 0 && this.session.messages.slice(index + 1)
      .some((message: ChatMessage) => message.role === 'user' && message.kind !== 'notice')
  }

  async resendEditedQuestion(messageId: number, content: string, skipConfirmation: boolean = false): Promise<boolean> {
    const text = content.trim()
    if (!this.canEditQuestion(messageId) || text.length === 0) return false
    const question = this.session.messages.find((message: ChatMessage) => message.id === messageId)
    if (question === undefined) return false
    if (question.imageUnavailable) {
      this.toastCallback('原问题的图片无法读取，暂不能重发')
      return false
    }
    if (question.imageUri.length > 0 && !this.currentModel().supportsImage) {
      this.toastCallback('当前模型不支持原问题的图片，请先切换模型')
      return false
    }
    if (skipConfirmation) this.rememberEditConfirmationChoice()
    await this.generateChatMessage(text, question.imageUri, question.id, false, true)
    return true
  }

  canRegenerateAnswer(messageId: number): boolean {
    return this.canManageConversations() && this.loaded && !this.speechRecognitionStarting &&
      !this.speechRecognizing && this.session.lastAnswer()?.id === messageId
  }

  async regenerateAnswer(messageId: number): Promise<void> {
    if (!this.canRegenerateAnswer(messageId)) return
    const question = this.session.lastQuestion()
    if (question === undefined) return
    if (question.imageUnavailable) {
      this.toastCallback('原问题的图片无法读取，暂不能重新生成')
      return
    }
    await this.generateChatMessage(question.content, question.imageUri, question.id, false)
  }

  selectAnswerVersion(messageId: number, index: number): void {
    if (!this.canManageConversations()) return
    const keepAtBottom = this.chatScroller.isAtEnd()
    if (!this.session.selectAnswerVersion(messageId, index)) return
    if (keepAtBottom) this.resumeChatAutoScroll()
    else this.pauseChatAutoScroll()
    this.syncMessages()
    this.notifyAndMaybeScroll()
  }

  updateHistorySearch(value: string): void {
    this.historySearchText = value
    clearTimeout(this.historySearchTimer)
    const serial = ++this.historySearchSerial
    this.historySearchResults = []
    this.historySearchError = ''
    this.historySearching = value.trim().length > 0
    this.notify()
    if (!this.historySearching) return
    this.historySearchTimer = setTimeout(async () => {
      try {
        const results = await this.historyService.search(value)
        if (serial === this.historySearchSerial) this.historySearchResults = results
      } catch (_) {
        if (serial === this.historySearchSerial) this.historySearchError = '搜索失败，请重试'
      } finally {
        if (serial === this.historySearchSerial) {
          this.historySearching = false
          this.notify()
        }
      }
    }, 180)
  }

  private historyFailure(action: string, error: Object): string {
    console.error(`${action}：${formatError(error)}`)
    const message = (error as Error).message ?? ''
    if (message === '对话文字已保存，但有图片未能保存。请重试。' ||
      message === '该对话暂时无法读取，记录仍保留在本机。') return message
    return `${action}，请重试。`
  }

  setConversationTitleActive(active: boolean): void {
    this.titleForeground = active
    if (!active) this.titleService.pause()
    else this.titleService.resume()
  }

  private canGenerateConversationTitle(): boolean {
    return this.titleForeground && this.historyReady && !this.historyBusy && this.loaded &&
      !this.busy && !this.generating && !this.modelLoading && !this.modelScanning &&
      !this.apiServerRunning && !this.apiServerStarting && !this.modelImporting && !this.builtinModelInstalling &&
      !this.speechRecognitionStarting && !this.speechRecognizing && !this.inputText.trim() && !this.selectedImageUri
  }

  private async applyConversationTitle(request: ConversationTitleRequest, title: string): Promise<void> {
    const applied = await this.historyService.applyGeneratedTitle(request.id, request.signature, title,
      () => !request.cancelled && !request.discarded)
    if (!applied) return
    if (this.activeConversation?.id === request.id && this.activeConversation.titleSource === 'temporary' &&
      conversationTitleSignature(this.activeConversation) === request.signature) {
      const current = this.activeConversation
      this.activeConversation = {
        version: current.version, id: current.id, title, titleSource: 'generated',
        createdAt: current.createdAt, updatedAt: current.updatedAt, messages: current.messages
      }
    }
    this.conversations = this.historyService.list()
    this.notify()
  }

  private async initializeHistory(): Promise<void> {
    this.historyBusy = true
    try {
      const index = await this.historyService.initialize(this.filesDir)
      this.conversations = this.historyService.list()
      this.historyError = this.historyService.warning
      if (index.activeId.length > 0) {
        this.activeConversation = await this.historyService.load(index.activeId)
        this.activeConversationId = this.activeConversation.id
        this.session.restore(this.activeConversation.messages)
        this.messages = this.session.messages
        await this.saveCurrentConversation()
      }
    } catch (error) {
      this.conversations = this.historyService.list()
      this.historyError = this.historyFailure('读取历史对话失败', error as Object)
    } finally {
      this.historyReady = true
      this.historyBusy = false
      this.notifyAndMaybeScroll()
    }
  }

  async openConversation(id: string, messageId: number = 0, answerVersionIndex?: number): Promise<boolean> {
    if (!this.canManageConversations()) return false
    this.titleService.pause()
    if (id === this.activeConversationId) {
      if (answerVersionIndex !== undefined) this.selectAnswerVersion(messageId, answerVersionIndex)
      if (messageId > 0) this.focusChatMessage(messageId)
      return true
    }
    this.historyBusy = true
    this.cancelSpeechRecognition(false)
    try {
      await this.flushHistory()
      const conversation = await this.historyService.load(id)
      this.activeConversation = conversation
      this.activeConversationId = id
      this.session.restore(conversation.messages)
      if (answerVersionIndex !== undefined) this.session.selectAnswerVersion(messageId, answerVersionIndex)
      this.messages = this.session.messages
      this.restoreDraft(id)
      this.selectedImageUri = ''
      this.historyError = ''
      await this.saveCurrentConversation()
      this.resumeChatAutoScroll()
      if (messageId > 0) this.focusChatMessage(messageId)
      else this.notifyAndScroll()
      return true
    } catch (error) {
      this.historyError = this.historyFailure('打开对话失败', error as Object)
      return false
    } finally {
      this.historyBusy = false
      this.notify()
    }
  }

  async renameConversation(id: string, title: string): Promise<void> {
    if (!this.canManageConversations() || title.trim().length === 0) return
    this.titleService.forget(id)
    this.historyBusy = true
    try {
      await this.flushHistory()
      this.titleService.forget(id)
      await this.historyService.rename(id, title)
      if (this.activeConversation?.id === id) {
        this.activeConversation.title = title.trim()
        this.activeConversation.titleSource = 'manual'
      }
      this.conversations = this.historyService.list()
      this.historyError = ''
      if (this.historySearchText.trim()) this.updateHistorySearch(this.historySearchText)
    } catch (error) {
      this.historyError = this.historyFailure('重命名对话失败', error as Object)
    } finally {
      this.historyBusy = false
      this.notify()
    }
  }

  async deleteConversation(id?: string): Promise<void> {
    if (!this.canManageConversations()) return
    this.titleService.forget(id)
    this.historyBusy = true
    try {
      await this.flushHistory()
      this.titleService.forget(id)
      if (id === undefined) {
        await this.historyService.clear()
        this.conversationDrafts.clear()
      } else {
        await this.historyService.remove(id)
        this.conversationDrafts.delete(id)
      }
      if (id === undefined || id === this.activeConversationId) this.startEmptyConversation(id !== undefined)
      this.conversations = this.historyService.list()
      this.historyError = ''
      if (this.historySearchText.trim()) this.updateHistorySearch(this.historySearchText)
    } catch (error) {
      this.conversations = this.historyService.list()
      if (!this.conversations.some((item: ChatConversationSummary) => item.id === this.activeConversationId)) {
        this.startEmptyConversation(true)
      }
      this.historyError = this.historyFailure('删除对话失败', error as Object)
    } finally {
      this.historyBusy = false
      this.notify()
    }
  }

  async retryHistorySave(): Promise<void> {
    if (this.historyBusy) return
    if (!this.activeConversation && !this.session.messages.some((message: ChatMessage) => message.role === 'user')) {
      await this.initializeHistory()
      return
    }
    this.historyBusy = true
    try {
      await this.flushHistory()
      this.historyError = ''
    } catch (error) {
      this.historyError = this.historyFailure('保存对话失败', error as Object)
    } finally {
      this.historyBusy = false
      this.notify()
    }
  }

  private async beginNewConversation(): Promise<void> {
    this.titleService.pause()
    this.historyBusy = true
    try {
      await this.flushHistory()
      await this.historyService.selectEmpty()
      this.startEmptyConversation(this.activeConversationId.length > 0)
      this.historyError = ''
      this.notifyAndScroll()
    } catch (error) {
      this.historyError = this.historyFailure('保存对话失败', error as Object)
    } finally {
      this.historyBusy = false
      this.notify()
    }
  }

  private startEmptyConversation(restorePendingDraft: boolean = false): void {
    this.resumeChatAutoScroll()
    this.cancelSpeechRecognition(false)
    this.activeConversation = undefined
    this.activeConversationId = ''
    this.session.newChat(this.loaded, this.currentModel().shortName)
    this.messages = this.session.messages
    if (restorePendingDraft) this.restoreDraft('')
    else {
      this.conversationDrafts.delete('')
      this.inputText = ''
    }
    this.selectedImageUri = ''
    this.setStatus(this.loaded ? `${this.currentModel().shortName} 已加载` : '模型未加载', this.loaded ? 'success' : 'neutral')
  }

  private async flushHistory(): Promise<void> {
    clearTimeout(this.historyTimer)
    this.historyTimer = -1
    await this.saveCurrentConversation()
  }

  private async saveCurrentConversation(): Promise<void> {
    const userMessages = this.session.messages.filter((message: ChatMessage) => message.role === 'user')
    if (userMessages.length === 0) return
    if (!this.activeConversation) {
      const now = Date.now()
      this.activeConversation = {
        version: 1, id: `c-${now.toString(36)}-${Math.random().toString(36).substring(2, 10)}`,
        title: conversationTitle(userMessages[0].content), titleSource: 'temporary', createdAt: userMessages[0].createdAt ?? now,
        updatedAt: now, messages: []
      }
      this.activeConversationId = this.activeConversation.id
    }
    const conversation = this.activeConversation
    conversation.messages = this.session.messages
    conversation.updatedAt = this.session.messages.reduce((latest: number, message: ChatMessage) =>
      Math.max(latest, message.completedAt ?? message.createdAt ?? 0), conversation.updatedAt)
    try {
      await this.historyService.save(conversation)
      this.titleService.enqueue(conversation)
    } finally {
      this.conversations = this.historyService.list()
      if (!this.generating && this.historySearchText.trim()) this.updateHistorySearch(this.historySearchText)
      this.notify()
    }
  }

  private scheduleHistorySave(): void {
    if (!this.historyReady || this.historyBusy) return
    if (this.generating && this.session.messages.some((message: ChatMessage) => message.generationState === 'generating')) {
      if (this.historyTimer >= 0) return
      this.historyTimer = setTimeout(() => {
        this.historyTimer = -1
        this.saveCurrentConversation().catch((error: Error) => {
          this.historyError = this.historyFailure('保存对话失败', error as Object)
          this.notify()
        })
      }, 1000)
    } else {
      clearTimeout(this.historyTimer)
      this.historyTimer = -1
      this.saveCurrentConversation().catch((error: Error) => {
        this.historyError = this.historyFailure('保存对话失败', error as Object)
        this.notify()
      })
    }
  }

  private setStatus(text: string, tone: 'neutral' | 'success' | 'warning' | 'error' = 'neutral'): void {
    this.status = text
    this.statusTone = tone
  }

  selectApiServiceTarget(target: 'chat' | 'decision'): void {
    if (this.apiServerRunning || this.apiServerStarting) return
    this.apiServerStartAfterModelLoad = false
    this.apiServiceTarget = target
    this.notify()
  }

  layaStatusText(): string {
    if (this.layaRuntimeState === 'loading') return '正在加载决策模型'
    if (this.layaRuntimeState === 'running') return '正在执行决策'
    if (this.layaRuntimeState === 'releasing') return '正在释放'
    if (this.layaRuntimeState === 'loaded') return '已加载'
    return this.layaReady ? '已安装' : '未安装'
  }

  async releaseDecisionModel(): Promise<void> {
    if ((this.apiServerRunning || this.apiServerStarting) && this.apiServiceTarget === 'decision') {
      this.toastCallback('请先关闭决策 API 服务')
      return
    }
    try {
      await releaseLaya()
    } catch (error) {
      this.toastCallback(formatError(error as Object))
    }
  }

  refreshLayaReady(): void {
    const ready = isLayaReady(this.filesDir)
    if (ready === this.layaReady) return
    this.layaReady = ready
    this.notify()
  }

  headerStatus(): string {
    if (this.layaRuntimeState === 'loading') return '正在加载决策模型...'
    if (this.layaRuntimeState === 'running') return '正在执行决策...'
    if (this.layaRuntimeState === 'releasing') return '正在释放 Laya...'
    if (!this.loaded && !this.busy && !this.modelLoading && this.status === '模型未加载' &&
      this.layaRuntimeState === 'loaded') return 'Laya 已加载'
    return this.headerText()
  }

  headerColor(): ResourceColor {
    if (this.layaRuntimeState === 'loading' || this.layaRuntimeState === 'running' ||
      this.layaRuntimeState === 'releasing') return $r('app.color.status_warning')
    if (this.statusTone === 'error') return $r('app.color.status_error_alt')
    if (this.busy || this.modelLoading || this.speechRecognitionStarting || this.speechRecognizing ||
      this.speechRecognitionStopping) return $r('app.color.status_warning')
    if (this.statusTone === 'warning') return $r('app.color.status_warning')
    return this.loaded || this.layaRuntimeState === 'loaded' || this.statusTone === 'success' ? $r('app.color.status_good') : $r('app.color.text_muted')
  }

  private headerText(): string {
    if (this.status === '等待首个输出片段...') return '正在准备回答...'
    if (this.status === '等待视觉模型...') return '正在处理图片...'
    if (this.statusTone === 'error' && (this.status.includes('code=') || this.status.includes('name='))) {
      return `${this.status.split('：')[0]}，请重试。`
    }
    return this.status
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
    if (this.rejectWhileModelScanning()) {
      return
    }
    this.ensureCurrentModelInstalled().then((installed: boolean) => {
      if (!installed) {
        return
      }
      this.showModelLoadDialog = true
      this.modelLoadElapsedSeconds = 0
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
      this.apiServerStartAfterModelLoad = false
      this.setStatus(`检查模型失败：${formatError(err as Object)}`, 'error')
      this.notify()
    })
  }

  closeModelLoadDialog(): void {
    this.apiServerStartAfterModelLoad = false
    this.showModelLoadDialog = false
    this.notify()
  }

  loadModel(): void {
    if (this.rejectWhileModelScanning()) {
      return
    }
    this.ensureCurrentModelInstalled().then((installed: boolean) => {
      if (!installed) {
        return
      }
      this.resetGenerationSettings(false)
      this.startModelLoad()
    }).catch((err: Error) => {
      this.apiServerStartAfterModelLoad = false
      this.setStatus(`检查模型失败：${formatError(err as Object)}`, 'error')
      this.notify()
    })
  }

  applyRuntimeConfigAndLoad(): void {
    if (this.rejectWhileModelScanning()) {
      return
    }
    if (this.busy || this.modelLoading || this.modelImporting || this.builtinModelInstalling ||
      this.apiServerStarting) {
      return
    }
    if (this.loaded) {
      const restartApiServer = this.apiServerRunning
      this.stopApiServerForModelChange(restartApiServer)
      this.modelLifecycleService.reset()
      this.loaded = false
    }
    this.ensureCurrentModelInstalled().then((installed: boolean) => {
      if (!installed) {
        return
      }
      this.startModelLoad()
    }).catch((err: Error) => {
      this.apiServerStartAfterModelLoad = false
      this.setStatus(`检查模型失败：${formatError(err as Object)}`, 'error')
      this.notify()
    })
  }

  startModelLoad(showProgressDialog: boolean = true, announceReady: boolean = true): void {
    if (this.rejectWhileModelScanning()) {
      return
    }
    const catalogItem = this.modelCatalogService.findInstallItem(this.currentModel().catalogItemId ??
      this.currentModel().downloadId)
    if (catalogItem !== undefined && this.rejectIncompatibleCatalogItem(catalogItem)) {
      return
    }
    if (this.modelLoading) {
      return
    }
    if (this.showBuiltinModelInstallDialog) {
      return
    }
    this.busy = true
    this.modelLoading = true
    this.showModelLoadDialog = showProgressDialog
    this.setStatus(`正在加载 ${this.currentModel().shortName}...`, 'neutral')
    this.modelLoadMessage = '正在加载模型权重，请保持应用在前台。'
    this.startModelLoadTimer()
    this.notify()

    this.modelLifecycleService.loadModel(
      this.filesDir,
      this.currentModel(),
      this.modelPath,
      this.threadNum,
      this.maxNewTokens,
      this.currentGenerationSettings()
    ).then((loaded: boolean) => {
      if (!loaded) {
        throw new Error('模型加载未完成。')
      }
      this.loaded = loaded
      this.runtimeConfigDirty = false
      this.setStatus(`${this.currentModel().shortName} 已加载`, 'success')
      this.modelLoadMessage = `${this.currentModel().shortName} 加载完成，可以开始聊天。`
      this.stopModelLoadTimer()
      this.modelLoadElapsedSeconds = Math.floor((Date.now() - this.modelLoadStartedAt) / 1000)
      if (announceReady) {
        this.session.appendMessage('assistant', `${this.currentModel().shortName} 加载完成，现在可以开始提问。`, '', false)
        this.syncMessages()
      }
      this.busy = false
      this.modelLoading = false
      this.refreshStats()
      if (announceReady) {
        this.notifyAndScroll()
      } else {
        this.notify()
      }
      this.startPendingApiServerIfReady()
      if (showProgressDialog) {
        setTimeout(() => {
          this.showModelLoadDialog = false
          this.notifyAndScroll()
        }, 450)
      }
    }).catch((err: Error) => {
      this.apiServerStartAfterModelLoad = false
      this.loaded = false
      this.setStatus(`加载失败：${formatError(err as Object)}`, 'error')
      const loadErrorMessage = `${this.currentModel().shortName} 加载失败，可能是设备可用内存不足。请关闭后台应用、释放其他模型或重启 App 后重试。\n\n${this.status}`
      this.stopModelLoadTimer()
      this.modelLoadElapsedSeconds = 0
      this.modelLoadMessage = loadErrorMessage
      this.busy = false
      this.modelLoading = false
      this.refreshStats()
      if (showProgressDialog) {
        this.notifyAndScroll()
      } else {
        this.notify()
      }
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
    this.apiServerStartAfterModelLoad = false
    this.pendingInstallCatalogItemId = ''
    this.autoLoadAfterInstall = false
    this.builtinModelInstallCanceled = false
    this.notify()
  }

  startBuiltinModelInstall(): void {
    if (this.rejectWhileModelScanning()) {
      return
    }
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
    if (this.rejectIncompatibleCatalogItem(spec)) {
      return
    }
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
    this.setStatus(`正在安装 ${spec.displayName}...`, 'neutral')
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
      this.setStatus(`正在安装 ${progress.modelName}...`, 'neutral')
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
      this.setStatus(`${spec.displayName} 安装完成`, 'success')
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
        this.setStatus(`${spec.displayName} 下载已停止`, 'warning')
      } else {
        this.builtinModelInstallCanceled = false
        this.builtinModelInstallError = `安装失败：${formatDownloadError(err as Object)}`
        this.builtinModelInstallMessage = `${spec.displayName} 未安装完成，可以重试。`
        this.setStatus(this.builtinModelInstallError, 'neutral')
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
    this.setStatus('正在停止模型下载...', 'neutral')
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
      this.setStatus(`${this.currentModel().shortName} 不支持图片输入。`, 'warning')
      this.notify()
      return
    }
    if (!this.context) {
      this.setStatus('选择图片失败：上下文不可用', 'error')
      this.notify()
      return
    }

    this.imageService.pickImage().then((uri: string | undefined) => {
      if (uri !== undefined && uri.length > 0) {
        this.selectedImageUri = uri
        this.notify()
      }
    }).catch((err: Error) => {
      this.setStatus(`选择图片失败：${formatError(err as Object)}`, 'error')
      this.notify()
    })
  }

  async sendMessage(): Promise<void> {
    await this.generateChatMessage(this.inputText.trim(), this.selectedImageUri, 0, true)
  }

  private async generateChatMessage(text: string, attachedImage: string, replacingQuestionId: number,
    consumeInput: boolean, editQuestion: boolean = false): Promise<void> {
    if (!this.historyReady || this.historyBusy) return
    if (this.rejectWhileModelScanning()) {
      return
    }
    if (!this.loaded || this.busy || this.generating || this.modelLoading || this.apiServerStarting ||
      this.speechRecognitionStarting || this.speechRecognizing || text.length === 0) {
      return
    }
    const question = editQuestion ? this.session.messages.find((message: ChatMessage) =>
      message.id === replacingQuestionId && message.role === 'user' && message.kind !== 'notice') : this.session.lastQuestion()
    if (replacingQuestionId > 0 && question?.id !== replacingQuestionId) return
    if (attachedImage.length > 0 && !this.currentModel().supportsImage) {
      this.setStatus(`${this.currentModel().shortName} 不支持图片输入，请清除图片后发送。`, 'warning')
      this.notify()
      return
    }

    const previousAnswer = replacingQuestionId > 0 && !editQuestion ? this.session.lastAnswer() : undefined
    if (replacingQuestionId > 0) this.session.removeFromQuestion(replacingQuestionId)
    const chatTurns = this.composeChatTurns(text)
    this.session.prepareModel(this.currentModel().id, this.currentModel().shortName)
    if (replacingQuestionId > 0 && !consumeInput && question !== undefined) {
      if (editQuestion) question.content = text
      this.session.messages = [...this.session.messages, question]
    } else {
      this.session.appendMessage('user', text, attachedImage)
    }
    let assistantId: number
    if (previousAnswer !== undefined) {
      this.session.messages = [...this.session.messages, previousAnswer]
      this.session.startAnswerVersion(previousAnswer.id)
      assistantId = previousAnswer.id
    } else {
      assistantId = this.session.appendMessage('assistant', '', '')
    }
    this.syncMessages()
    this.resumeChatAutoScroll()
    if (consumeInput) {
      this.conversationDrafts.delete(this.activeConversationId)
      this.inputText = ''
      this.selectedImageUri = ''
    }
    this.busy = true
    this.generating = true
    this.generationStopping = false
    this.streamingChars = 0
    this.latestPerfMetrics = undefined
    this.setStatus('等待首个输出片段...', 'neutral')
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
        this.setStatus(status, 'neutral')
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
      this.session.markGeneration(assistantId, outcome.result.stopReason === 'user_stop' ? 'stopped' :
        (outcome.result.stopReason === 'timeout' || outcome.result.stopReason === 'internal_error' ? 'failed' : 'complete'),
        outcome.result.stopReason)
      this.syncMessages()
      this.setStatus(outcome.status, outcome.includeInContext ? 'success' : 'warning')
      this.busy = false
      this.generating = false
      this.generationStopping = false
      this.refreshStats()
      this.notifyAndMaybeScroll()
    }).catch((err: Error) => {
      const message = `生成失败：${formatError(err as Object)}`
      const partialAnswer = this.session.messages.find((item: ChatMessage) => item.id === assistantId)?.content ?? ''
      this.session.updateMessage(assistantId, partialAnswer, false)
      this.session.markGeneration(assistantId, 'failed', 'internal_error')
      this.syncMessages()
      this.setStatus(message, 'error')
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
    this.setStatus('正在停止生成...', 'neutral')
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
      const lastIndex = this.chatScrollTargetId > 0 ?
        this.messages.findIndex((message: ChatMessage) => message.id === this.chatScrollTargetId) : this.messages.length - 1
      if (lastIndex < 0) {
        return
      }
      try {
        this.chatScroller.scrollToIndex(lastIndex, false, this.chatScrollTargetId > 0 ? ScrollAlign.START : ScrollAlign.END)
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
    this.chatScrollTargetId = 0
    if (this.highlightedMessageId > 0) {
      this.highlightedMessageId = 0
      this.notify()
    }
  }

  resumeChatAutoScroll(): void {
    this.chatAutoScrollEnabled = true
    this.chatScrollTargetId = 0
    this.highlightedMessageId = 0
  }

  private focusChatMessage(messageId: number): void {
    if (!this.messages.some((message: ChatMessage) => message.id === messageId)) return
    this.pauseChatAutoScroll()
    this.chatScrollTargetId = messageId
    this.highlightedMessageId = messageId
    this.notifyAndScroll()
  }

  private resetLoadedModel(status: string): void {
    this.stopApiServerForModelChange(false)
    if (this.loaded) {
      this.modelLifecycleService.reset()
    }
    this.loaded = false
    this.setStatus(status, 'neutral')
    this.modelLoadElapsedSeconds = 0
    this.modelLoadMessage = status
  }

  private stopApiServerForModelChange(restartAfterLoad: boolean): void {
    if (this.apiServerRunning && this.apiServiceTarget === 'decision' && isLayaReady(this.filesDir)) {
      this.apiServerStartAfterModelLoad = false
      return
    }
    this.apiServerStartAfterModelLoad = restartAfterLoad
    if (!this.apiServerRunning) {
      return
    }
    this.apiServerRunning = false
    this.apiServerStarting = true
    this.apiServer.stop().then(() => {
      this.apiServerStarting = false
      this.notify()
      this.startPendingApiServerIfReady()
    }).catch((err: Error) => {
      this.apiServerStarting = false
      this.apiServerStartAfterModelLoad = false
      this.apiServerStatus = `停止 API 服务失败：${formatError(err as Object)}`
      this.appendApiServerLog('ERROR', `停止服务失败：${formatError(err as Object)}`)
      this.notify()
    })
    this.notify()
  }

  private startPendingApiServerIfReady(): void {
    if (!this.apiServerStartAfterModelLoad || !this.loaded || this.busy || this.modelLoading ||
      this.apiServerStarting || this.apiServerRunning) {
      return
    }
    this.apiServerStartAfterModelLoad = false
    this.setApiServerEnabled(true)
  }

  private ensureCurrentModelInstalled(): Promise<boolean> {
    const catalogItem = this.modelCatalogService.findInstallItem(this.currentModel().catalogItemId ??
      this.currentModel().downloadId)
    if (catalogItem !== undefined && this.rejectIncompatibleCatalogItem(catalogItem)) {
      return Promise.resolve(false)
    }
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
    this.stopModelLoadTimer()
    this.modelLoadElapsedSeconds = 0
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
    this.setStatus(`${spec.displayName} 未安装`, 'neutral')
    this.notify()
    this.syncBuiltinModelInstallPartialProgress(spec)
  }

  private composeChatTurns(text: string): ChatTurn[] {
    return this.session.composeChatTurns(this.currentModel().systemPrompt, text, this.currentContextMessageLimit())
  }

  private apiServerModel(): ApiServerModel {
    const model = this.currentModel()
    return { id: model.id, name: model.name }
  }

  private appendApiServerLog(level: string, message: string): void {
    const now = new Date()
    const time = `${now.getHours().toString().padStart(2, '0')}:` +
      `${now.getMinutes().toString().padStart(2, '0')}:` +
      now.getSeconds().toString().padStart(2, '0')
    const entry: ApiServerLogEntry = {
      id: this.nextApiServerLogId++,
      time,
      level,
      message
    }
    const logs = this.apiServerLogs.concat(entry)
    this.apiServerLogs = logs.length > this.apiServerLogLimit ?
      logs.slice(logs.length - this.apiServerLogLimit) : logs
    this.notify()
  }

  private runApiGeneration(
    request: ApiGenerationRequest,
    onChunk: (chunk: string) => void
  ): Promise<GenerationResult> {
    if (this.modelScanning) {
      return Promise.reject(new Error('正在扫描模型目录，请稍候'))
    }
    if (!this.loaded || this.busy || this.modelLoading) {
      return Promise.reject(new Error('模型未就绪或当前已有任务。'))
    }
    this.busy = true
    this.generating = true
    this.generationStopping = false
    this.streamingChars = 0
    this.latestPerfMetrics = undefined
    this.setStatus('等待 API 首个输出片段...', 'neutral')
    this.refreshStats()
    this.notify()
    return this.nativeService.generateText(
      request.turns,
      request.maxNewTokens,
      request.settings,
      (chunk: string) => {
        this.streamingChars += chunk.length
        this.setStatus(`正在处理 API 请求... ${this.streamingChars} 字符`, 'neutral')
        onChunk(chunk)
        this.notify()
      }
    ).then((result: GenerationResult) => {
      this.busy = false
      this.generating = false
      this.generationStopping = false
      this.setStatus(`API 生成完成（${result.generatedTokens} tokens）`, 'success')
      this.refreshStats()
      this.notify()
      return result
    }).catch((err: Error) => {
      this.busy = false
      this.generating = false
      this.generationStopping = false
      this.setStatus(`API 生成失败：${formatError(err as Object)}`, 'error')
      this.refreshStats()
      this.notify()
      throw err
    })
  }

  currentContextMessageLimit(): number {
    const model = this.currentModel()
    if (model.contextMessageLimit !== undefined) {
      const rounded = Math.max(0, Math.round(model.contextMessageLimit))
      return rounded - rounded % 2
    }
    if (model.source === 'imported') {
      return 0
    }
    return 6
  }

  private syncMessages(): void {
    this.messages = this.session.messages
    this.scheduleHistorySave()
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

  private loadChatActionSettings(): void {
    if (this.context === undefined) return
    preferences.getPreferences(this.context, 'chat-actions').then((store: preferences.Preferences) => {
      return store.get('skip-edit-confirmation', false)
    }).then((value: preferences.ValueType) => {
      this.skipEditConfirmation = value === true
      this.notify()
    }).catch(() => {})
  }

  private rememberEditConfirmationChoice(): void {
    this.skipEditConfirmation = true
    if (this.context === undefined) return
    preferences.getPreferences(this.context, 'chat-actions').then((store: preferences.Preferences) => {
      return store.put('skip-edit-confirmation', true).then(() => store.flush())
    }).catch(() => {})
  }

  private loadStartupModelSettings(): void {
    if (this.context === undefined) {
      return
    }
    preferences.getPreferences(this.context, this.modelOrderPreferenceName).then(async (store: preferences.Preferences) => {
      const enabled = await store.get(this.startupAutoLoadPreferenceKey, false)
      const modelId = await store.get(this.startupModelPreferenceKey, '')
      this.startupAutoLoadEnabled = typeof enabled === 'boolean' ? enabled : false
      this.startupModelId = typeof modelId === 'string' ? modelId : ''
      this.startupSettingsReady = true
      this.tryStartStartupModelLoad()
      this.notify()
    }).catch((_err: Error) => {
      this.startupSettingsReady = true
    })
  }

  private saveStartupModelSettings(): void {
    if (this.context === undefined) {
      return
    }
    preferences.getPreferences(this.context, this.modelOrderPreferenceName).then((store: preferences.Preferences) => {
      return store.put(this.startupAutoLoadPreferenceKey, this.startupAutoLoadEnabled)
        .then(() => store.put(this.startupModelPreferenceKey, this.startupModelId))
        .then(() => store.flush())
    }).catch((_err: Error) => {
    })
  }

  private tryStartStartupModelLoad(): void {
    if (!this.startupSettingsReady || !this.startupAutoLoadEnabled || this.startupLoadStarted ||
      this.startupModelId.length <= 0) {
      return
    }
    const profile = this.modelManager.profiles().find((item: ModelProfile) => item.id === this.startupModelId)
    if (profile === undefined) {
      return
    }
    this.startupLoadStarted = true
    if (this.selectedModelId !== profile.id) {
      this.modelManager.switchModel(profile.id, this.filesDir)
      this.prepareImportedModelEditor(profile.id)
      this.selectedImageUri = ''
      this.resetGenerationSettings(false)
      this.runtimeConfigDirty = false
    }
    this.modelLifecycleService.isInstalled(this.filesDir, profile, this.modelPath).then((installed: boolean) => {
      if (!installed) {
        this.setStatus(`${profile.shortName} 未安装，已跳过启动加载`, 'warning')
        this.notify()
        return
      }
      this.startModelLoad(false, false)
    }).catch((err: Error) => {
      this.setStatus(`启动加载失败：${formatError(err as Object)}`, 'error')
      this.notify()
    })
  }

  private apiServerPort(): number {
    const parsed = Number.parseInt(this.apiServerPortInput, 10)
    return Number.isFinite(parsed) ? parsed : 8080
  }

  private loadApiServerSettings(): void {
    if (this.context === undefined) {
      return
    }
    preferences.getPreferences(this.context, this.apiServerPreferenceName).then(async (store: preferences.Preferences) => {
      const portValue = await store.get(this.apiServerPortPreferenceKey, 8080)
      const requireKeyValue = await store.get(this.apiServerRequireKeyPreferenceKey, true)
      const keyValue = await store.get(this.apiServerKeyPreferenceKey, '')
      if (typeof portValue === 'number') {
        this.apiServerPortInput = `${Math.round(portValue)}`
      }
      if (typeof requireKeyValue === 'boolean') {
        this.apiServerRequireKey = requireKeyValue
      }
      if (typeof keyValue === 'string') {
        this.apiServerKey = keyValue
      }
      if (this.apiServerKey.length <= 0) {
        this.createApiServerKey(false)
      }
      this.apiServerAddress = `http://设备局域网 IP:${this.apiServerPortInput}`
      this.notify()
    }).catch((_err: Error) => {
      if (this.apiServerKey.length <= 0) {
        this.createApiServerKey(false)
      }
    })
  }

  private saveApiServerSettings(): void {
    if (this.context === undefined) {
      return
    }
    preferences.getPreferences(this.context, this.apiServerPreferenceName).then((store: preferences.Preferences) => {
      return store.put(this.apiServerPortPreferenceKey, this.apiServerPort())
        .then(() => store.put(this.apiServerRequireKeyPreferenceKey, this.apiServerRequireKey))
        .then(() => store.put(this.apiServerKeyPreferenceKey, this.apiServerKey))
        .then(() => store.flush())
    }).catch((_err: Error) => {
    })
  }

  private createApiServerKey(showResult: boolean): void {
    cryptoFramework.createRandom().generateRandom(16).then((blob: cryptoFramework.DataBlob) => {
      let key = ''
      for (let index = 0; index < blob.data.length; index++) {
        key += blob.data[index].toString(16).padStart(2, '0')
      }
      this.apiServerKey = key
      this.saveApiServerSettings()
      if (showResult) {
        this.toastCallback('已重新生成 API Key')
      }
      this.notify()
    }).catch((err: Error) => {
      this.apiServerStatus = `生成 API Key 失败：${formatError(err as Object)}`
      this.notify()
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
    this.setStatus(`正在生成... ${update.characterCount} 字符`, 'neutral')
    this.session.updateMessage(assistantId, update.text)
    this.syncMessages()
    this.notify()
    if (this.chatAutoScrollEnabled) {
      this.scrollToBottom()
    }
  }

  private startModelLoadTimer(): void {
    this.stopModelLoadTimer()
    this.modelLoadStartedAt = Date.now()
    this.modelLoadElapsedSeconds = 0
    this.modelLoadTimer = setInterval(() => {
      this.modelLoadElapsedSeconds = Math.floor((Date.now() - this.modelLoadStartedAt) / 1000)
      this.notify()
    }, 1000)
  }

  private stopModelLoadTimer(): void {
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
    this.titleService.resume()
    this.notifyCallback()
  }
}
