import { common } from '@kit.AbilityKit';
import { ChatMessage, ChatTurn, GenerationResult } from '../models/ChatTypes';
import { ImportedModelDraft } from '../models/ImportedModelTypes';
import {
  CHAT_FORMAT_MNN_AUTO,
  CHAT_FORMAT_QWEN_IM,
  CHAT_FORMAT_RAW_TEMPLATE,
  DEFAULT_MAX_NEW_TOKENS,
  DEFAULT_THREAD_NUM,
  MAX_GENERATION_TOKENS,
  ModelProfile
} from '../models/ModelProfile';
import { EMPTY_RUNTIME_STATS, RuntimeStats } from '../models/RuntimeStats';
import { ImagePayloadService } from '../services/ImagePayloadService';
import { ModelImportService } from '../services/ModelImportService';
import { NativeInferenceService } from '../services/NativeInferenceService';
import { RuntimeStatsService } from '../services/RuntimeStatsService';
import { formatError } from '../utils/formatters';
import { isLikelyIncompleteAssistantText } from '../utils/thinking';
import { ChatSession } from './ChatSession';
import { ModelManager } from './ModelManager';

@Observed
export class ChatViewModel {
  inputText: string = '用一段话介绍鸿蒙 NEXT。';
  selectedImageUri: string = '';
  busy: boolean = false;
  loaded: boolean = false;
  status: string = '模型未加载';
  maxNewTokens: number = DEFAULT_MAX_NEW_TOKENS;
  threadNum: number = DEFAULT_THREAD_NUM;
  showModelLoadDialog: boolean = false;
  modelLoading: boolean = false;
  modelLoadProgress: number = 0;
  modelLoadMessage: string = '准备加载本地模型';
  modelImporting: boolean = false;
  modelImportMessage: string = '可导入 MNN 模型 zip 包';
  editingImportedModelId: string = '';
  importedModelNameInput: string = '';
  importedModelShortNameInput: string = '';
  importedModelSystemPromptInput: string = '';
  importedModelChatFormatInput: string = CHAT_FORMAT_MNN_AUTO;
  importedModelPromptTemplateInput: string = '';
  importedModelStopSequenceInput: string = '';
  importedModelSupportsImage: boolean = false;
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
  private modelImportService: ModelImportService = new ModelImportService();
  private statsService: RuntimeStatsService = new RuntimeStatsService();

  get messages(): ChatMessage[] {
    return this.session.messages;
  }

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
    this.resetLoadedModel(`已切换至 ${model.shortName}，请加载模型。`);
    this.notify();
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

  updateMaxNewTokens(value: number): void {
    this.maxNewTokens = Math.round(value);
    this.notify();
  }

  updateThreadNum(value: number): void {
    this.threadNum = Math.round(value);
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
      this.importedModelSupportsImage = false;
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
    this.importedModelSupportsImage = draft.supportsImage;
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
    } else {
      this.importedModelChatFormatInput = CHAT_FORMAT_MNN_AUTO;
    }
    this.notify();
  }

  updateImportedModelPromptTemplate(value: string): void {
    this.importedModelPromptTemplateInput = value;
    this.notify();
  }

  updateImportedModelStopSequence(value: string): void {
    this.importedModelStopSequenceInput = value;
    this.notify();
  }

  updateImportedModelSupportsImage(value: boolean): void {
    this.importedModelSupportsImage = value;
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
      supportsImage: this.importedModelSupportsImage,
      systemPrompt: this.importedModelSystemPromptInput,
      chatFormat: this.importedModelChatFormatInput,
      promptTemplate: this.importedModelPromptTemplateInput,
      stopSequence: this.importedModelStopSequenceInput
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
    this.notify();
  }

  newChat(): void {
    this.session.newChat(this.loaded, this.currentModel().shortName);
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
  }

  closeModelLoadDialog(): void {
    this.showModelLoadDialog = false;
    this.notifyAndScroll();
  }

  loadModel(): void {
    this.openModelLoadDialog(false);
    this.startModelLoad();
  }

  startModelLoad(): void {
    if (this.modelLoading) {
      return;
    }
    this.busy = true;
    this.modelLoading = true;
    this.showModelLoadDialog = true;
    this.status = `正在加载 ${this.currentModel().shortName}...`;
    this.modelLoadMessage = '正在加载模型权重，请保持应用在前台。';
    this.startModelLoadProgress();
    this.notify();

    this.nativeService.loadModel(this.modelPath, this.threadNum, this.maxNewTokens).then((loaded: boolean) => {
      this.loaded = loaded;
      this.status = `${this.currentModel().shortName} 已加载`;
      this.modelLoadMessage = `${this.currentModel().shortName} 加载完成，可以开始聊天。`;
      this.stopModelLoadProgress();
      this.modelLoadProgress = 100;
      this.session.appendMessage('assistant', `${this.currentModel().shortName} 加载完成，现在可以开始提问。`, '', false);
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
      this.loaded = false;
      this.busy = false;
      this.modelLoading = false;
      this.refreshStats();
      this.notifyAndScroll();
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
    this.inputText = '';
    this.selectedImageUri = '';
    this.busy = true;
    this.status = '等待首个字元...';
    this.refreshStats();
    this.notifyAndScroll();

    let streamedChars = 0;
    let generation: Promise<GenerationResult>;
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
          (chunk: string) => {
            streamedChars = this.handleStreamChunk(assistantId, chunk, streamedChars);
          }
        );
      });
    } else {
      generation = this.generateTextForCurrentModel(chatTurns, (chunk: string) => {
        streamedChars = this.handleStreamChunk(assistantId, chunk, streamedChars);
      });
    }

    generation.then((result: GenerationResult) => {
      const cleanedText = this.session.sanitizeAssistantText(result.text);
      const answer = cleanedText.length > 0 ? cleanedText : '（原生层返回空内容）';
      const includeInContext = this.shouldIncludeAssistantInContext(answer, result);
      this.session.updateMessage(assistantId, answer, includeInContext);
      this.status = this.formatGenerationStatus(answer, includeInContext, result);
      this.busy = false;
      this.refreshStats();
      this.notifyAndScroll();
    }).catch((err: Error) => {
      const message = `生成失败：${formatError(err as Object)}`;
      this.session.updateMessage(assistantId, message, false);
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

  private composeChatTurns(text: string): ChatTurn[] {
    return this.session.composeChatTurns(this.currentModel().systemPrompt, text);
  }

  private generateTextForCurrentModel(turns: ChatTurn[], onChunk: (chunk: string) => void): Promise<GenerationResult> {
    const model = this.currentModel();
    const chatFormat = model.chatFormat ?? CHAT_FORMAT_MNN_AUTO;
    if (chatFormat === CHAT_FORMAT_QWEN_IM) {
      return this.nativeService.generateRawPrompt(
        this.composeQwenPrompt(turns),
        this.maxNewTokens,
        model.stopSequence ?? '<|im_end|>',
        onChunk
      );
    }
    if (chatFormat === CHAT_FORMAT_RAW_TEMPLATE && model.promptTemplate !== undefined && model.promptTemplate.length > 0) {
      return this.nativeService.generateRawPrompt(
        this.composeRawTemplatePrompt(turns, model.promptTemplate),
        this.maxNewTokens,
        model.stopSequence ?? '',
        onChunk
      );
    }
    return this.nativeService.generateText(turns, this.maxNewTokens, onChunk);
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

  private composeRawTemplatePrompt(turns: ChatTurn[], promptTemplate: string): string {
    const conversation = this.composeSingleUserPromptText(turns);
    if (promptTemplate.indexOf('%s') >= 0) {
      return promptTemplate.replace('%s', conversation);
    }
    return `${promptTemplate}\n${conversation}`;
  }

  private composeSingleUserPromptText(turns: ChatTurn[]): string {
    let systemPrompt = '';
    const historyParts: string[] = [];
    let currentUserText = '';
    turns.forEach((turn: ChatTurn) => {
      const content = turn.content.trim();
      if (content.length <= 0) {
        return;
      }
      if (turn.role === 'system') {
        systemPrompt = content;
      } else if (turn.role === 'assistant') {
        historyParts.push(`助手：${content}`);
      } else {
        currentUserText = content;
      }
    });

    const sections: string[] = [];
    const constraints = '请只回答“当前用户问题”。如果当前问题涉及具体产品、版本、年份、型号、厂商路线或外部事实，而你没有可靠把握，请明确说不确定，不要猜测或编造。专有名词保持原样，不要按英文或字面含义拆解。';
    if (systemPrompt.length > 0) {
      sections.push(`系统要求：\n${systemPrompt}\n${constraints}`);
    } else {
      sections.push(`系统要求：\n${constraints}`);
    }
    if (historyParts.length > 0) {
      sections.push(`历史对话：\n${historyParts.join('\n')}`);
    }
    sections.push(`当前用户问题：\n${currentUserText}`);
    return sections.join('\n\n');
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

  private handleStreamChunk(assistantId: number, chunk: string, streamedChars: number): number {
    if (chunk.length <= 0) {
      return streamedChars;
    }
    const nextStreamedChars = streamedChars + chunk.length;
    this.status = `正在生成... ${nextStreamedChars} 字符`;
    this.session.appendToMessage(assistantId, chunk);
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
