import { common } from '@kit.AbilityKit';
import fs from '@ohos.file.fs';
import { ChatMessage, ChatTurn, GenerationResult, GenerationSettings } from '../models/ChatTypes';
import { ImportedModelDraft } from '../models/ImportedModelTypes';
import { BuiltinModelDownloadSpec, BuiltinModelInstallProgress } from '../models/BuiltinModelDownloadTypes';
import {
  CHAT_FORMAT_GEMMA_TURN,
  CHAT_FORMAT_MINICPM_THINKING,
  CHAT_FORMAT_MNN_AUTO,
  CHAT_FORMAT_QWEN_IM,
  CHAT_FORMAT_RAW_TEMPLATE,
  DEFAULT_MAX_NEW_TOKENS,
  DEFAULT_REPETITION_PENALTY,
  DEFAULT_TEMPERATURE,
  DEFAULT_THREAD_NUM,
  DEFAULT_TOP_K,
  DEFAULT_TOP_P,
  MAX_GENERATION_TOKENS,
  ModelProfile
} from '../models/ModelProfile';
import { EMPTY_RUNTIME_STATS, RuntimeStats } from '../models/RuntimeStats';
import { ImagePayloadService } from '../services/ImagePayloadService';
import { BuiltinModelInstallService } from '../services/BuiltinModelInstallService';
import { ModelImportService } from '../services/ModelImportService';
import { NativeInferenceService } from '../services/NativeInferenceService';
import { RuntimeStatsService } from '../services/RuntimeStatsService';
import { formatError } from '../utils/formatters';
import { isLikelyIncompleteAssistantText, trimLikelyIncompleteTrailingFragment } from '../utils/thinking';
import { ChatSession } from './ChatSession';
import { ModelManager } from './ModelManager';

@Observed
export class ChatViewModel {
  messages: ChatMessage[] = [];
  inputText: string = '请用一段话介绍鸿蒙系统。';
  selectedImageUri: string = '';
  busy: boolean = false;
  loaded: boolean = false;
  status: string = '模型未加载';
  maxNewTokens: number = DEFAULT_MAX_NEW_TOKENS;
  threadNum: number = DEFAULT_THREAD_NUM;
  temperature: number = DEFAULT_TEMPERATURE;
  topP: number = DEFAULT_TOP_P;
  topK: number = DEFAULT_TOP_K;
  repetitionPenalty: number = DEFAULT_REPETITION_PENALTY;
  showAdvancedModelSettings: boolean = false;
  showModelLoadDialog: boolean = false;
  modelLoading: boolean = false;
  modelLoadProgress: number = 0;
  modelLoadMessage: string = '准备加载本地模型';
  showBuiltinModelInstallDialog: boolean = false;
  builtinModelInstalling: boolean = false;
  builtinModelInstallProgress: number = 0;
  builtinModelInstallMessage: string = '内置模型目录缺失，请先下载模型文件。';
  builtinModelInstallFileName: string = '';
  builtinModelInstallModelName: string = '';
  builtinModelInstallSourceName: string = 'ModelScope';
  builtinModelInstallDownloadedBytes: number = 0;
  builtinModelInstallTotalBytes: number = 0;
  builtinModelInstallError: string = '';
  modelImporting: boolean = false;
  modelImportMessage: string = '可导入 MNN 模型 zip 包';
  editingImportedModelId: string = '';
  importedModelNameInput: string = '';
  importedModelShortNameInput: string = '';
  importedModelSystemPromptInput: string = '';
  importedModelChatFormatInput: string = CHAT_FORMAT_MNN_AUTO;
  importedModelPromptTemplateInput: string = '';
  importedModelStopSequenceInput: string = '';
  showDeleteImportedModelDialog: boolean = false;
  pendingDeleteImportedModelId: string = '';
  stats: RuntimeStats = EMPTY_RUNTIME_STATS;
  chatScroller: Scroller = new Scroller();

  private filesDir: string = '';
  private context?: common.UIAbilityContext;
  private modelLoadTimer: number = -1;
  private autoScrollPending: boolean = false;
  private notifyCallback: () => void = () => {};
  private session: ChatSession = new ChatSession();
  private modelManager: ModelManager = new ModelManager();
  private nativeService: NativeInferenceService = new NativeInferenceService();
  private imageService: ImagePayloadService = new ImagePayloadService();
  private builtinModelInstallService: BuiltinModelInstallService = new BuiltinModelInstallService();
  private modelImportService: ModelImportService = new ModelImportService();
  private statsService: RuntimeStatsService = new RuntimeStatsService();

  get modelPath(): string {
    return this.modelManager.modelPath;
  }

  get selectedModelId(): string {
    return this.modelManager.selectedModelId;
  }

  get maxGenerationTokens(): number {
    return MAX_GENERATION_TOKENS;
  }

  bindNotify(callback: () => void): void {
    this.notifyCallback = callback;
  }

  initialize(context: common.UIAbilityContext): void {
    this.context = context;
    this.filesDir = context.filesDir;
    this.modelManager.initialize(this.filesDir);
    this.session.initializeWelcome(this.currentModel().shortName);
    this.syncMessages();
    this.refreshStats();
    this.notify();
    this.modelImportService.loadImportedProfiles(this.filesDir).then((profiles: ModelProfile[]) => {
      this.modelManager.updateImportedProfiles(profiles, this.filesDir);
      this.prepareImportedModelEditor(this.selectedModelId);
      this.notify();
    }).catch((err: Error) => {
      this.modelImportMessage = `读取导入模型失败：${formatError(err as Object)}`;
      this.notify();
    });
  }

  dispose(): void {
    this.stopModelLoadProgress();
  }

  modelProfiles(): ModelProfile[] {
    return this.modelManager.profiles();
  }

  currentModel(): ModelProfile {
    return this.modelManager.currentModel();
  }

  switchModel(modelId: string): void {
    if (this.busy || this.modelLoading || modelId === this.selectedModelId) {
      return;
    }

    const model = this.modelManager.switchModel(modelId, this.filesDir);
    this.prepareImportedModelEditor(model.id);
    if (!model.supportsImage) {
      this.selectedImageUri = '';
    }
    this.inputText = '';
    this.selectedImageUri = '';
    this.session.resetForModelSwitch(model.shortName);
    this.syncMessages();
    this.resetLoadedModel(`已切换至 ${model.shortName}，请加载模型。`);
    this.notifyAndScroll();
  }

  updateModelPath(value: string): void {
    if (!this.modelManager.updateModelPath(value)) {
      return;
    }
    if (!this.modelLoading) {
      this.resetLoadedModel('模型路径已修改，请重新加载。');
    }
    this.notify();
  }

  updateInputText(value: string): void {
    this.inputText = value;
    this.notify();
  }

  updateMaxNewTokens(value: number, notify: boolean = true): void {
    this.maxNewTokens = Math.round(value);
    if (notify) {
      this.notify();
    }
  }

  updateThreadNum(value: number): void {
    this.threadNum = Math.round(value);
    this.notify();
  }

  updateTemperature(value: number, notify: boolean = true): void {
    this.temperature = Math.round(value * 100) / 100;
    if (notify) {
      this.notify();
    }
  }

  updateTopP(value: number, notify: boolean = true): void {
    this.topP = Math.round(value * 100) / 100;
    if (notify) {
      this.notify();
    }
  }

  updateTopK(value: number, notify: boolean = true): void {
    this.topK = Math.round(value);
    if (notify) {
      this.notify();
    }
  }

  updateRepetitionPenalty(value: number, notify: boolean = true): void {
    this.repetitionPenalty = Math.round(value * 100) / 100;
    if (notify) {
      this.notify();
    }
  }

  resetGenerationSettings(notify: boolean = true): void {
    this.maxNewTokens = DEFAULT_MAX_NEW_TOKENS;
    this.temperature = DEFAULT_TEMPERATURE;
    this.topP = DEFAULT_TOP_P;
    this.topK = DEFAULT_TOP_K;
    this.repetitionPenalty = DEFAULT_REPETITION_PENALTY;
    if (notify) {
      this.notify();
    }
  }

  toggleAdvancedModelSettings(): void {
    this.showAdvancedModelSettings = !this.showAdvancedModelSettings;
    this.notify();
  }

  importModelPackage(): void {
    if (this.busy || this.modelLoading || this.modelImporting) {
      return;
    }
    if (!this.context) {
      this.modelImportMessage = '导入失败：上下文不可用';
      this.notify();
      return;
    }

    this.busy = true;
    this.modelImporting = true;
    this.modelImportMessage = '请选择 MNN 模型 zip 包...';
    this.status = '正在导入模型包...';
    this.notify();

    this.modelImportService.pickAndImport(this.context, this.modelProfiles()).then((result) => {
      if (result === undefined) {
        this.modelImportMessage = '已取消导入模型包';
        this.status = this.loaded ? `${this.currentModel().shortName} 已加载` : '模型未加载';
        this.busy = false;
        this.modelImporting = false;
        this.notify();
        return;
      }

      this.modelManager.addImportedProfile(result.profile, this.filesDir);
      this.prepareImportedModelEditor(result.profile.id);
      if (!result.profile.supportsImage) {
        this.selectedImageUri = '';
      }
      this.resetLoadedModel(result.message);
      this.modelImportMessage = result.message;
      this.busy = false;
      this.modelImporting = false;
      this.notify();
    }).catch((err: Error) => {
      const message = `导入失败：${formatError(err as Object)}`;
      this.modelImportMessage = message;
      this.status = message;
      this.busy = false;
      this.modelImporting = false;
      this.refreshStats();
      this.notify();
    });
  }

  prepareImportedModelEditor(modelId: string): void {
    const profile = this.findProfile(modelId);
    if (profile === undefined || profile.source !== 'imported') {
      this.editingImportedModelId = '';
      this.importedModelNameInput = '';
      this.importedModelShortNameInput = '';
      this.importedModelSystemPromptInput = '';
      this.importedModelChatFormatInput = CHAT_FORMAT_MNN_AUTO;
      this.importedModelPromptTemplateInput = '';
      this.importedModelStopSequenceInput = '';
      return;
    }
    const draft = this.modelImportService.createDraft(profile);
    this.editingImportedModelId = profile.id;
    this.importedModelNameInput = draft.name;
    this.importedModelShortNameInput = draft.shortName;
    this.importedModelSystemPromptInput = draft.systemPrompt;
    this.importedModelChatFormatInput = draft.chatFormat;
    this.importedModelPromptTemplateInput = draft.promptTemplate;
    this.importedModelStopSequenceInput = draft.stopSequence;
  }

  updateImportedModelName(value: string): void {
    this.importedModelNameInput = value;
    this.notify();
  }

  updateImportedModelShortName(value: string): void {
    this.importedModelShortNameInput = value;
    this.notify();
  }

  updateImportedModelSystemPrompt(value: string): void {
    this.importedModelSystemPromptInput = value;
    this.notify();
  }

  updateImportedModelChatFormat(value: string): void {
    this.importedModelChatFormatInput = value;
    this.notify();
  }

  cycleImportedModelChatFormat(): void {
    if (this.importedModelChatFormatInput === CHAT_FORMAT_MNN_AUTO) {
      this.importedModelChatFormatInput = CHAT_FORMAT_RAW_TEMPLATE;
    } else if (this.importedModelChatFormatInput === CHAT_FORMAT_RAW_TEMPLATE) {
      this.importedModelChatFormatInput = CHAT_FORMAT_QWEN_IM;
    } else if (this.importedModelChatFormatInput === CHAT_FORMAT_QWEN_IM) {
      this.importedModelChatFormatInput = CHAT_FORMAT_MINICPM_THINKING;
    } else if (this.importedModelChatFormatInput === CHAT_FORMAT_MINICPM_THINKING) {
      this.importedModelChatFormatInput = CHAT_FORMAT_GEMMA_TURN;
    } else if (this.importedModelChatFormatInput === CHAT_FORMAT_GEMMA_TURN) {
      this.importedModelChatFormatInput = CHAT_FORMAT_MNN_AUTO;
    } else {
      this.importedModelChatFormatInput = CHAT_FORMAT_MNN_AUTO;
    }
    this.syncImportedTemplateFieldsForFormat();
    this.notify();
  }

  saveImportedModelProfile(): void {
    if (this.busy || this.modelLoading || this.modelImporting || this.editingImportedModelId.length <= 0) {
      return;
    }
    const profile = this.findProfile(this.editingImportedModelId);
    if (profile === undefined) {
      this.modelImportMessage = '保存失败：导入模型不存在';
      this.notify();
      return;
    }
    const draft: ImportedModelDraft = {
      name: this.importedModelNameInput,
      shortName: this.importedModelShortNameInput,
      supportsImage: profile.supportsImage,
      systemPrompt: this.importedModelSystemPromptInput,
      chatFormat: this.importedModelChatFormatInput,
      promptTemplate: this.promptTemplateForImportedProfile(profile),
      stopSequence: this.stopSequenceForImportedProfile(profile)
    };
    const updated = this.modelImportService.applyDraft(profile, draft);
    this.modelImportService.updateImportedProfile(this.filesDir, updated, this.modelProfiles()).then((profiles: ModelProfile[]) => {
      this.modelManager.updateImportedProfiles(profiles, this.filesDir);
      this.prepareImportedModelEditor(updated.id);
      if (!updated.supportsImage) {
        this.selectedImageUri = '';
      }
      this.modelImportMessage = `${updated.shortName} 配置已保存`;
      this.status = this.loaded ? `${this.currentModel().shortName} 已加载` : this.status;
      this.notify();
    }).catch((err: Error) => {
      this.modelImportMessage = `保存失败：${formatError(err as Object)}`;
      this.notify();
    });
  }

  requestDeleteImportedModel(modelId: string): void {
    if (this.busy || this.modelLoading || this.modelImporting) {
      return;
    }
    const profile = this.findProfile(modelId);
    if (profile === undefined || profile.source !== 'imported') {
      return;
    }
    this.pendingDeleteImportedModelId = modelId;
    this.showDeleteImportedModelDialog = true;
    this.notify();
  }

  cancelDeleteImportedModel(): void {
    this.pendingDeleteImportedModelId = '';
    this.showDeleteImportedModelDialog = false;
    this.notify();
  }

  confirmDeleteImportedModel(): void {
    if (this.pendingDeleteImportedModelId.length <= 0 || this.busy || this.modelLoading || this.modelImporting) {
      return;
    }
    const modelId = this.pendingDeleteImportedModelId;
    const profile = this.findProfile(modelId);
    if (profile === undefined) {
      this.cancelDeleteImportedModel();
      return;
    }

    this.busy = true;
    this.modelImporting = true;
    this.showDeleteImportedModelDialog = false;
    this.modelImportMessage = `正在删除 ${profile.shortName}...`;
    this.notify();

    this.modelImportService.deleteImportedProfile(this.filesDir, modelId).then((profiles: ModelProfile[]) => {
      const deletingCurrent = this.selectedModelId === modelId;
      if (deletingCurrent && this.loaded) {
        this.nativeService.reset();
        this.loaded = false;
      }
      this.modelManager.updateImportedProfiles(profiles, this.filesDir);
      this.prepareImportedModelEditor(this.selectedModelId);
      this.pendingDeleteImportedModelId = '';
      this.modelImportMessage = `${profile.shortName} 已删除`;
      this.status = deletingCurrent ? '导入模型已删除，请重新选择并加载模型。' : this.status;
      this.busy = false;
      this.modelImporting = false;
      this.notify();
    }).catch((err: Error) => {
      this.pendingDeleteImportedModelId = '';
      this.modelImportMessage = `删除失败：${formatError(err as Object)}`;
      this.busy = false;
      this.modelImporting = false;
      this.notify();
    });
  }

  clearSelectedImage(): void {
    this.selectedImageUri = '';
    this.notify();
  }

  toggleMessageThinking(messageId: number): void {
    this.session.toggleThinkingExpanded(messageId);
    this.syncMessages();
    this.notify();
  }

  newChat(): void {
    this.session.newChat(this.loaded, this.currentModel().shortName);
    this.syncMessages();
    this.inputText = '';
    this.selectedImageUri = '';
    this.status = this.loaded ? `${this.currentModel().shortName} 已加载` : '模型未加载';
    this.notifyAndScroll();
  }

  refreshStats(): void {
    this.stats = this.statsService.readStats();
    this.notify();
  }

  openModelLoadDialog(autoStart: boolean = false): void {
    this.ensureCurrentModelInstalled().then((installed: boolean) => {
      if (!installed) {
        return;
      }
      this.showModelLoadDialog = true;
      this.modelLoadProgress = this.loaded ? 100 : 0;
      this.modelLoadMessage = this.loaded ? `${this.currentModel().shortName} 已加载，可以开始聊天。` : `正在准备加载 ${this.currentModel().shortName} 本地模型...`;
      this.notify();
      if (autoStart) {
        setTimeout(() => {
          if (this.showModelLoadDialog && !this.loaded && !this.modelLoading) {
            this.startModelLoad();
          }
        }, 350);
      }
    }).catch((err: Error) => {
      this.status = `检查模型失败：${formatError(err as Object)}`;
      this.notify();
    });
  }

  closeModelLoadDialog(): void {
    this.showModelLoadDialog = false;
    this.notifyAndScroll();
  }

  loadModel(): void {
    this.ensureCurrentModelInstalled().then((installed: boolean) => {
      if (!installed) {
        return;
      }
      this.openModelLoadDialog(false);
      this.startModelLoad();
    }).catch((err: Error) => {
      this.status = `检查模型失败：${formatError(err as Object)}`;
      this.notify();
    });
  }

  startModelLoad(): void {
    if (this.modelLoading) {
      return;
    }
    if (this.showBuiltinModelInstallDialog) {
      return;
    }
    this.busy = true;
    this.modelLoading = true;
    this.showModelLoadDialog = true;
    this.status = `正在加载 ${this.currentModel().shortName}...`;
    this.modelLoadMessage = '正在加载模型权重，请保持应用在前台。';
    this.startModelLoadProgress();
    this.notify();

    this.nativeService.loadModel(
      this.modelPath,
      this.threadNum,
      this.maxNewTokens,
      this.currentGenerationSettings()
    ).then((loaded: boolean) => {
      this.loaded = loaded;
      this.status = `${this.currentModel().shortName} 已加载`;
      this.modelLoadMessage = `${this.currentModel().shortName} 加载完成，可以开始聊天。`;
      this.stopModelLoadProgress();
      this.modelLoadProgress = 100;
      this.session.appendMessage('assistant', `${this.currentModel().shortName} 加载完成，现在可以开始提问。`, '', false);
      this.syncMessages();
      this.busy = false;
      this.modelLoading = false;
      this.refreshStats();
      this.notifyAndScroll();
      setTimeout(() => {
        this.showModelLoadDialog = false;
        this.notifyAndScroll();
      }, 450);
    }).catch((err: Error) => {
      this.status = `加载失败：${formatError(err as Object)}`;
      this.modelLoadMessage = this.status;
      this.stopModelLoadProgress();
      this.modelLoadProgress = 0;
      this.session.appendMessage('assistant', this.status, '', false);
      this.syncMessages();
      this.loaded = false;
      this.busy = false;
      this.modelLoading = false;
      this.refreshStats();
      this.notifyAndScroll();
    });
  }

  closeBuiltinModelInstallDialog(): void {
    if (this.builtinModelInstalling) {
      return;
    }
    this.showBuiltinModelInstallDialog = false;
    this.notify();
  }

  startBuiltinModelInstall(): void {
    if (this.builtinModelInstalling || this.context === undefined) {
      return;
    }
    const model = this.currentModel();
    const spec = this.builtinModelInstallService.getDownloadSpec(model);
    if (spec === undefined) {
      this.showBuiltinModelInstallDialog = false;
      this.loadModel();
      return;
    }

    this.busy = true;
    this.builtinModelInstalling = true;
    this.showBuiltinModelInstallDialog = true;
    this.builtinModelInstallError = '';
    this.builtinModelInstallProgress = 0;
    this.builtinModelInstallDownloadedBytes = 0;
    this.builtinModelInstallTotalBytes = spec.totalBytes;
    this.builtinModelInstallFileName = '';
    this.builtinModelInstallModelName = spec.displayName;
    this.builtinModelInstallSourceName = spec.sourceName;
    this.builtinModelInstallMessage = `正在从 ${spec.sourceName} 下载 ${spec.displayName}。请保持 App 在前台。`;
    this.status = `正在安装 ${spec.displayName}...`;
    this.notify();

    this.builtinModelInstallService.install(this.context, model, (progress: BuiltinModelInstallProgress) => {
      this.builtinModelInstallProgress = progress.progress;
      this.builtinModelInstallDownloadedBytes = progress.downloadedBytes;
      this.builtinModelInstallTotalBytes = progress.totalBytes;
      this.builtinModelInstallFileName = progress.fileName;
      this.builtinModelInstallMessage = `${progress.message}：${progress.fileName}`;
      this.status = `正在安装 ${progress.modelName}... ${Math.round(progress.progress)}%`;
      this.notify();
    }).then(() => {
      this.builtinModelInstalling = false;
      this.busy = false;
      this.builtinModelInstallProgress = 100;
      this.builtinModelInstallMessage = `${spec.displayName} 安装完成，正在加载模型。`;
      this.status = `${spec.displayName} 安装完成`;
      this.notify();
      setTimeout(() => {
        this.showBuiltinModelInstallDialog = false;
        this.openModelLoadDialog(false);
        this.startModelLoad();
      }, 350);
    }).catch((err: Error) => {
      this.builtinModelInstalling = false;
      this.busy = false;
      this.builtinModelInstallError = `安装失败：${formatError(err as Object)}`;
      this.builtinModelInstallMessage = `${spec.displayName} 未安装完成，可以重试。`;
      this.status = this.builtinModelInstallError;
      this.notify();
    });
  }

  chooseImage(): void {
    if (!this.currentModel().supportsImage) {
      this.status = `${this.currentModel().shortName} 不支持图片输入。`;
      this.notify();
      return;
    }
    if (!this.context) {
      this.status = '选择图片失败：上下文不可用';
      this.notify();
      return;
    }

    this.imageService.pickImage(this.context).then((uri: string | undefined) => {
      if (uri !== undefined && uri.length > 0) {
        this.selectedImageUri = uri;
        this.notify();
      }
    }).catch((err: Error) => {
      this.status = `选择图片失败：${formatError(err as Object)}`;
      this.notify();
    });
  }

  async sendMessage(): Promise<void> {
    const text = this.inputText.trim();
    if (!this.loaded || this.busy || text.length === 0) {
      return;
    }

    const chatTurns = this.composeChatTurns(text);
    const attachedImage = this.selectedImageUri;
    if (attachedImage.length > 0 && !this.currentModel().supportsImage) {
      this.status = `${this.currentModel().shortName} 不支持图片输入，请清除图片后发送。`;
      this.notify();
      return;
    }

    this.session.appendMessage('user', text, attachedImage);
    const assistantId = this.session.appendMessage('assistant', '', '');
    this.syncMessages();
    this.inputText = '';
    this.selectedImageUri = '';
    this.busy = true;
    this.status = '等待首个字元...';
    this.refreshStats();
    this.notifyAndScroll();

    let streamedChars = 0;
    let streamedText = '';
    let generation: Promise<GenerationResult>;
    const assistantOutputPrefix = this.expectedAssistantOutputPrefixForCurrentModel();
    if (attachedImage.length > 0) {
      this.status = '正在读取图片...';
      this.notify();
      generation = this.imageService.buildImagePayload(attachedImage).then((payload) => {
        this.status = '等待视觉模型...';
        this.notify();
        return this.nativeService.generateImage(
          chatTurns,
          payload,
          this.maxNewTokens,
          this.currentGenerationSettings(),
          (chunk: string) => {
            streamedText += chunk;
            streamedChars = this.handleStreamText(assistantId, streamedText, assistantOutputPrefix);
          }
        );
      });
    } else {
      generation = this.generateTextForCurrentModel(chatTurns, (chunk: string) => {
        streamedText += chunk;
        streamedChars = this.handleStreamText(assistantId, streamedText, assistantOutputPrefix);
      });
    }

    generation.then((result: GenerationResult) => {
      const cleanedText = trimLikelyIncompleteTrailingFragment(this.session.sanitizeAssistantText(
        this.applyExpectedAssistantOutputPrefix(result.text, assistantOutputPrefix),
        this.shouldStripLeadingAssistantSeparator()
      ));
      const answer = cleanedText.length > 0 ? cleanedText : '（原生层返回空内容）';
      const includeInContext = this.shouldIncludeAssistantInContext(answer, result);
      this.session.updateMessage(assistantId, answer, includeInContext);
      this.syncMessages();
      this.status = this.formatGenerationStatus(answer, includeInContext, result);
      this.busy = false;
      this.refreshStats();
      this.notifyAndScroll();
    }).catch((err: Error) => {
      const message = `生成失败：${formatError(err as Object)}`;
      this.session.updateMessage(assistantId, message, false);
      this.syncMessages();
      this.status = message;
      this.busy = false;
      this.refreshStats();
      this.notifyAndScroll();
    });
  }

  scrollToBottom(): void {
    if (this.autoScrollPending) {
      return;
    }
    this.autoScrollPending = true;
    setTimeout(() => {
      this.autoScrollPending = false;
      const lastIndex = this.messages.length - 1;
      if (lastIndex < 0) {
        return;
      }
      try {
        this.chatScroller.scrollToIndex(lastIndex, false, ScrollAlign.END);
      } catch (err) {
        try {
          this.chatScroller.scrollEdge(Edge.Bottom);
        } catch (_) {
        }
      }
    }, 30);
  }

  private resetLoadedModel(status: string): void {
    if (this.loaded) {
      this.nativeService.reset();
    }
    this.loaded = false;
    this.status = status;
    this.modelLoadProgress = 0;
    this.modelLoadMessage = status;
  }

  private ensureCurrentModelInstalled(): Promise<boolean> {
    const model = this.currentModel();
    const spec = this.builtinModelInstallService.getDownloadSpec(model);
    if (spec === undefined) {
      return Promise.resolve(true);
    }
    return this.currentModelConfigExists().then((customPathExists: boolean) => {
      if (customPathExists && this.modelPath !== `${this.filesDir}/${model.directoryName}/config.json`) {
        return true;
      }
      return this.builtinModelInstallService.isInstalled(this.filesDir, model);
    }).then((installed: boolean) => {
      if (installed) {
        return true;
      }
      this.openBuiltinModelInstallDialog(spec);
      return false;
    });
  }

  private openBuiltinModelInstallDialog(spec: BuiltinModelDownloadSpec): void {
    this.showModelLoadDialog = false;
    this.stopModelLoadProgress();
    this.modelLoadProgress = 0;
    this.showBuiltinModelInstallDialog = true;
    this.builtinModelInstalling = false;
    this.builtinModelInstallProgress = 0;
    this.builtinModelInstallDownloadedBytes = 0;
    this.builtinModelInstallTotalBytes = spec.totalBytes;
    this.builtinModelInstallFileName = '';
    this.builtinModelInstallModelName = spec.displayName;
    this.builtinModelInstallSourceName = spec.sourceName;
    this.builtinModelInstallError = '';
    this.builtinModelInstallMessage = `${spec.displayName} 内置模型目录缺失或不完整，请先下载模型文件。`;
    this.status = `${spec.displayName} 未安装`;
    this.notify();
  }

  private async currentModelConfigExists(): Promise<boolean> {
    if (this.modelPath.length <= 0) {
      return false;
    }
    try {
      const stat = await fs.stat(this.modelPath);
      return stat.isFile();
    } catch (_) {
      return false;
    }
  }

  private composeChatTurns(text: string): ChatTurn[] {
    return this.session.composeChatTurns(this.currentModel().systemPrompt, text, this.currentContextMessageLimit());
  }

  currentContextMessageLimit(): number {
    const model = this.currentModel();
    if (model.contextMessageLimit !== undefined) {
      return Math.max(0, Math.round(model.contextMessageLimit));
    }
    if (model.source === 'imported') {
      return 0;
    }
    return 6;
  }

  private syncMessages(): void {
    this.messages = this.session.messages;
  }

  private shouldStripLeadingAssistantSeparator(): boolean {
    const model = this.currentModel();
    return model.source === 'imported' && (model.chatFormat ?? CHAT_FORMAT_MNN_AUTO) === CHAT_FORMAT_RAW_TEMPLATE;
  }

  private generateTextForCurrentModel(turns: ChatTurn[], onChunk: (chunk: string) => void): Promise<GenerationResult> {
    const model = this.currentModel();
    const chatFormat = model.chatFormat ?? CHAT_FORMAT_MNN_AUTO;
    if (chatFormat === CHAT_FORMAT_MINICPM_THINKING) {
      return this.nativeService.generateRawPrompt(
        this.composeMiniCpmThinkingPrompt(turns),
        this.maxNewTokens,
        model.stopSequence ?? '</s>',
        this.currentGenerationSettings(),
        onChunk
      );
    }
    if (chatFormat === CHAT_FORMAT_GEMMA_TURN) {
      return this.nativeService.generateRawPrompt(
        this.composeGemmaTurnPrompt(turns),
        this.maxNewTokens,
        model.stopSequence ?? '<turn|>',
        this.currentGenerationSettings(),
        onChunk
      );
    }
    if (chatFormat === CHAT_FORMAT_QWEN_IM) {
      return this.nativeService.generateRawPrompt(
        this.composeQwenPrompt(turns),
        this.maxNewTokens,
        model.stopSequence ?? '<|im_end|>',
        this.currentGenerationSettings(),
        onChunk
      );
    }
    if (chatFormat === CHAT_FORMAT_RAW_TEMPLATE && model.promptTemplate !== undefined && model.promptTemplate.length > 0) {
      return this.nativeService.generateRawPrompt(
        this.composeRawTemplatePrompt(turns, model.promptTemplate, model),
        this.maxNewTokens,
        model.stopSequence ?? '',
        this.currentGenerationSettings(),
        onChunk
      );
    }
    return this.nativeService.generateText(turns, this.maxNewTokens, this.currentGenerationSettings(), onChunk);
  }

  private expectedAssistantOutputPrefixForCurrentModel(): string {
    const model = this.currentModel();
    if ((model.chatFormat ?? CHAT_FORMAT_MNN_AUTO) === CHAT_FORMAT_MINICPM_THINKING) {
      return '<think>\n';
    }
    return '';
  }

  private applyExpectedAssistantOutputPrefix(text: string, prefix: string): string {
    if (prefix.length <= 0 || text.length <= 0) {
      return text;
    }
    const trimmedStart = text.trimStart();
    if (trimmedStart.startsWith('<think>') || '<think>'.startsWith(trimmedStart)) {
      return text;
    }
    return `${prefix}${text}`;
  }

  private currentGenerationSettings(): GenerationSettings {
    return {
      temperature: this.temperature,
      topP: this.topP,
      topK: this.topK,
      repetitionPenalty: this.repetitionPenalty
    };
  }

  private syncImportedTemplateFieldsForFormat(): void {
    const profile = this.findProfile(this.editingImportedModelId);
    const originalTemplate = profile?.promptTemplate ?? '';
    if (this.importedModelChatFormatInput === CHAT_FORMAT_MNN_AUTO) {
      this.importedModelPromptTemplateInput = '';
      this.importedModelStopSequenceInput = '';
      return;
    }
    if (this.importedModelChatFormatInput === CHAT_FORMAT_QWEN_IM) {
      this.importedModelPromptTemplateInput = '';
      this.importedModelStopSequenceInput = '<|im_end|>';
      return;
    }
    if (this.importedModelChatFormatInput === CHAT_FORMAT_MINICPM_THINKING) {
      this.importedModelPromptTemplateInput = '';
      this.importedModelStopSequenceInput = '</s>';
      return;
    }
    if (this.importedModelChatFormatInput === CHAT_FORMAT_GEMMA_TURN) {
      this.importedModelPromptTemplateInput = '';
      this.importedModelStopSequenceInput = '<turn|>';
      return;
    }
    this.importedModelPromptTemplateInput = originalTemplate;
    this.importedModelStopSequenceInput = this.inferStopSequenceForTemplate(originalTemplate, profile?.name ?? '');
  }

  private promptTemplateForImportedProfile(profile: ModelProfile): string {
    if (this.importedModelChatFormatInput === CHAT_FORMAT_RAW_TEMPLATE) {
      const currentTemplate = this.importedModelPromptTemplateInput.trim();
      if (currentTemplate.length > 0) {
        return currentTemplate;
      }
      return profile.promptTemplate ?? '';
    }
    if (this.importedModelChatFormatInput === CHAT_FORMAT_QWEN_IM) {
      return '';
    }
    if (this.importedModelChatFormatInput === CHAT_FORMAT_MINICPM_THINKING) {
      return '';
    }
    return '';
  }

  private stopSequenceForImportedProfile(profile: ModelProfile): string {
    if (this.importedModelChatFormatInput === CHAT_FORMAT_QWEN_IM) {
      return '<|im_end|>';
    }
    if (this.importedModelChatFormatInput === CHAT_FORMAT_MINICPM_THINKING) {
      return '</s>';
    }
    if (this.importedModelChatFormatInput === CHAT_FORMAT_GEMMA_TURN) {
      return '<turn|>';
    }
    if (this.importedModelChatFormatInput === CHAT_FORMAT_RAW_TEMPLATE) {
      const template = this.promptTemplateForImportedProfile(profile);
      const currentStopSequence = this.importedModelStopSequenceInput.trim();
      if (currentStopSequence.length > 0) {
        return currentStopSequence;
      }
      return this.inferStopSequenceForTemplate(template, profile.name);
    }
    return '';
  }

  private inferStopSequenceForTemplate(promptTemplate: string, modelName: string): string {
    if (promptTemplate.indexOf('<|im_end|>') >= 0) {
      return '<|im_end|>';
    }
    if (promptTemplate.indexOf('<|end_of_sentence|>') >= 0) {
      return '<|end_of_sentence|>';
    }
    if (promptTemplate.indexOf('<|end_of_text|>') >= 0) {
      return '<|end_of_text|>';
    }
    const lowerName = modelName.toLowerCase();
    if (lowerName.indexOf('deepseek') >= 0) {
      return '<|end_of_sentence|>';
    }
    if (lowerName.indexOf('qwen') >= 0 && lowerName.indexOf('deepseek') < 0) {
      return '<|im_end|>';
    }
    return '';
  }

  private composeQwenPrompt(turns: ChatTurn[]): string {
    let prompt = '';
    turns.forEach((turn: ChatTurn) => {
      const role = turn.role === 'assistant' ? 'assistant' : turn.role === 'system' ? 'system' : 'user';
      const content = turn.content.trim();
      if (content.length <= 0) {
        return;
      }
      prompt += `<|im_start|>${role}\n${content}<|im_end|>\n`;
    });
    prompt += '<|im_start|>assistant\n';
    return prompt;
  }

  private composeGemmaTurnPrompt(turns: ChatTurn[]): string {
    let prompt = '<bos>';
    turns.forEach((turn: ChatTurn) => {
      const role = turn.role === 'assistant' ? 'model' : turn.role === 'system' ? 'system' : 'user';
      const content = turn.content.trim();
      if (content.length <= 0) {
        return;
      }
      prompt += `<|turn>${role}\n${content}<turn|>\n`;
    });
    prompt += '<|turn>model\n';
    return prompt;
  }

  private composeMiniCpmThinkingPrompt(turns: ChatTurn[]): string {
    let prompt = '<s>';
    turns.forEach((turn: ChatTurn) => {
      const role = turn.role === 'assistant' ? 'assistant' : turn.role === 'system' ? 'system' : 'user';
      const content = turn.content.trim();
      if (content.length <= 0) {
        return;
      }
      prompt += `<|im_start|>${role}\n${content}<|im_end|>\n`;
    });
    prompt += '<|im_start|>assistant\n<think>\n';
    return prompt;
  }

  private composeRawTemplatePrompt(turns: ChatTurn[], promptTemplate: string, model: ModelProfile): string {
    const conversation = this.composeRawTemplateUserText(turns, model);
    if (promptTemplate.indexOf('%s') >= 0) {
      return promptTemplate.replace('%s', conversation);
    }
    return `${promptTemplate}\n${conversation}`;
  }

  private composeRawTemplateUserText(turns: ChatTurn[], model: ModelProfile): string {
    let currentUserText = '';
    turns.forEach((turn: ChatTurn) => {
      const content = turn.content.trim();
      if (content.length <= 0) {
        return;
      }
      if (turn.role === 'user') {
        currentUserText = content;
      }
    });
    if (this.isDeepSeekModel(model)) {
      return `请用简体中文回答用户问题。最终答案必须直接回答问题，不要在已经可以回答时说“我还没有学会回答这个问题”。\n\n用户问题：${currentUserText}`;
    }
    return currentUserText;
  }

  private isDeepSeekModel(model: ModelProfile): boolean {
    return `${model.id} ${model.name} ${model.shortName}`.toLowerCase().indexOf('deepseek') >= 0;
  }

  private shouldIncludeAssistantInContext(answer: string, result: GenerationResult): boolean {
    if (result.stopReason === 'max_tokens') {
      return false;
    }
    if (result.stopReason === 'eos' || result.stopReason === 'user_stop') {
      return true;
    }
    return !isLikelyIncompleteAssistantText(answer);
  }

  private formatGenerationStatus(answer: string, includeInContext: boolean, result: GenerationResult): string {
    const tokenText = result.generatedTokens > 0 ? `，${result.generatedTokens} tokens` : '';
    if (result.stopReason === 'max_tokens') {
      return `生成完成（${answer.length} 字符${tokenText}，达到最大输出）`;
    }
    if (!includeInContext) {
      return `生成完成（${answer.length} 字符${tokenText}，可能被截断）`;
    }
    return `生成完成（${answer.length} 字符${tokenText}）`;
  }

  private findProfile(modelId: string): ModelProfile | undefined {
    const profiles = this.modelProfiles();
    for (let index = 0; index < profiles.length; index++) {
      if (profiles[index].id === modelId) {
        return profiles[index];
      }
    }
    return undefined;
  }

  private handleStreamText(assistantId: number, streamedText: string, assistantOutputPrefix: string = ''): number {
    if (streamedText.length <= 0) {
      return 0;
    }
    const displayText = this.session.sanitizeStreamingAssistantText(
      this.applyExpectedAssistantOutputPrefix(streamedText, assistantOutputPrefix),
      this.shouldStripLeadingAssistantSeparator()
    );
    const nextStreamedChars = displayText.length;
    this.status = `正在生成... ${nextStreamedChars} 字符`;
    this.session.updateMessage(assistantId, displayText);
    this.syncMessages();
    this.notifyAndScroll();
    return nextStreamedChars;
  }

  private startModelLoadProgress(): void {
    this.stopModelLoadProgress();
    this.modelLoadProgress = 8;
    this.modelLoadTimer = setInterval(() => {
      if (this.modelLoadProgress < 88) {
        this.modelLoadProgress = Math.min(88, this.modelLoadProgress + 4);
        this.notify();
      }
    }, 160);
  }

  private stopModelLoadProgress(): void {
    if (this.modelLoadTimer >= 0) {
      clearInterval(this.modelLoadTimer);
      this.modelLoadTimer = -1;
    }
  }

  private notifyAndScroll(): void {
    this.notify();
    this.scrollToBottom();
  }

  private notify(): void {
    this.notifyCallback();
  }
}
