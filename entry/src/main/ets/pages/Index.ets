import { common } from '@kit.AbilityKit';
import picker from '@ohos.file.picker';
import fs from '@ohos.file.fs';
import hidebug from '@ohos.hidebug';
import image from '@ohos.multimedia.image';
import entry from 'libentry.so';

interface ChatMessage {
  id: number;
  role: string;
  content: string;
  imageUri: string;
  time: string;
  includeInContext: boolean;
}

interface RuntimeStats {
  appCpu: string;
  systemCpu: string;
  appPss: string;
  nativeHeap: string;
  systemMem: string;
}

interface ChatTurn {
  role: string;
  content: string;
}

interface ImagePayload {
  pixels: ArrayBuffer;
  width: number;
  height: number;
}

interface ModelProfile {
  id: string;
  name: string;
  shortName: string;
  directoryName: string;
  description: string;
  supportsImage: boolean;
  systemPrompt: string;
}

const MAX_GENERATION_TOKENS: number = 512;
const CONTEXT_MESSAGE_LIMIT: number = 6;
const VISION_MAX_PIXELS: number = 640000;
const DEFAULT_MODEL_ID: string = 'gemma4';
const MODEL_PROFILES: ModelProfile[] = [
  {
    id: 'gemma4',
    name: 'Gemma 4 E2B',
    shortName: 'Gemma 4',
    directoryName: 'gemma-4-E2B-it-MNN',
    description: '多模态 MNN 模型，支持文本和图片输入。',
    supportsImage: true,
    systemPrompt: '你是运行在鸿蒙 NEXT 本地设备上的 Gemma 4。请始终使用简体中文回答，表达简洁清楚。用户提供图片时，请结合图片内容回答；如果用户要求提取文字，请尽量逐行转写图片中的可见文字。'
  },
  {
    id: 'minicpm5-1b',
    name: 'MiniCPM5-1B',
    shortName: 'MiniCPM5',
    directoryName: 'MiniCPM5-1B-MNN',
    description: '轻量文本 MNN 模型，适合快速本地对话。',
    supportsImage: false,
    systemPrompt: '你是运行在鸿蒙 NEXT 本地设备上的 MiniCPM5-1B。请始终使用简体中文回答，表达简洁清楚。'
  }
];

@Entry
@Component
struct Index {
  @State private modelPath: string = '';
  @State private selectedModelId: string = DEFAULT_MODEL_ID;
  @State private inputText: string = '用一段话介绍鸿蒙 NEXT。';
  @State private selectedImageUri: string = '';
  @State private messages: ChatMessage[] = [];
  @State private busy: boolean = false;
  @State private loaded: boolean = false;
  @State private status: string = '模型未加载';
  @State private maxNewTokens: number = 32;
  @State private threadNum: number = 6;
  @State private showLaunch: boolean = true;
  @State private activeTab: number = 0;
  @State private showModelLoadDialog: boolean = false;
  @State private modelLoading: boolean = false;
  @State private modelLoadProgress: number = 0;
  @State private modelLoadMessage: string = '准备加载本地模型';
  @State private stats: RuntimeStats = {
    appCpu: '--',
    systemCpu: '--',
    appPss: '--',
    nativeHeap: '--',
    systemMem: '--'
  };

  private nextMessageId: number = 1;
  private monitorTimer: number = -1;
  private modelLoadTimer: number = -1;
  private chatScroller: Scroller = new Scroller();
  private autoScrollPending: boolean = false;

  aboutToAppear(): void {
    const context = getContext(this) as common.UIAbilityContext;
    this.modelPath = this.defaultConfigPath(context.filesDir, this.currentModel());
    this.messages = [{
      id: this.nextMessageId++,
      role: 'assistant',
      content: `请先加载 ${this.currentModel().shortName}，然后发送一条简短问题。想要更快响应，可以降低最大输出。`,
      imageUri: '',
      time: this.nowTime(),
      includeInContext: false
    }];
    setTimeout(() => {
      this.showLaunch = false;
      if (!this.loaded) {
        this.openModelLoadDialog(true);
      }
    }, 1200);
    this.refreshStats();
    this.monitorTimer = setInterval(() => {
      this.refreshStats();
    }, 1500);
  }

  aboutToDisappear(): void {
    if (this.monitorTimer >= 0) {
      clearInterval(this.monitorTimer);
      this.monitorTimer = -1;
    }
    this.stopModelLoadProgress();
  }

  private currentModel(): ModelProfile {
    const fallback = MODEL_PROFILES[0];
    for (let index = 0; index < MODEL_PROFILES.length; index++) {
      if (MODEL_PROFILES[index].id === this.selectedModelId) {
        return MODEL_PROFILES[index];
      }
    }
    return fallback;
  }

  private defaultConfigPath(filesDir: string, model: ModelProfile): string {
    return `${filesDir}/${model.directoryName}/config.json`;
  }

  private resetLoadedModel(status: string): void {
    if (this.loaded) {
      entry.reset();
    }
    this.loaded = false;
    this.status = status;
    this.modelLoadProgress = 0;
    this.modelLoadMessage = status;
  }

  private switchModel(modelId: string): void {
    if (this.busy || this.modelLoading || modelId === this.selectedModelId) {
      return;
    }

    this.selectedModelId = modelId;
    const context = getContext(this) as common.UIAbilityContext;
    const model = this.currentModel();
    this.modelPath = this.defaultConfigPath(context.filesDir, model);
    if (!model.supportsImage) {
      this.selectedImageUri = '';
    }
    this.resetLoadedModel(`已切换至 ${model.shortName}，请加载模型。`);
  }

  private updateModelPath(value: string): void {
    if (this.modelPath === value) {
      return;
    }
    this.modelPath = value;
    if (!this.modelLoading) {
      this.resetLoadedModel('模型路径已修改，请重新加载。');
    }
  }

  private nowTime(): string {
    const date = new Date();
    const hour = date.getHours().toString().padStart(2, '0');
    const minute = date.getMinutes().toString().padStart(2, '0');
    return `${hour}:${minute}`;
  }

  private kbToMb(value: bigint): string {
    return `${(Number(value.toString()) / 1024).toFixed(1)} MB`;
  }

  private bytesToMb(value: bigint): string {
    return `${(Number(value.toString()) / 1024 / 1024).toFixed(1)} MB`;
  }

  private formatError(err: Object): string {
    if (err === undefined || err === null) {
      return '未知错误';
    }
    if (typeof err === 'string') {
      return err;
    }

    const record = err as Record<string, Object>;
    const parts: string[] = [];
    if (record.code !== undefined) {
      parts.push(`code=${record.code}`);
    }
    if (record.name !== undefined) {
      parts.push(`name=${record.name}`);
    }
    if (record.message !== undefined) {
      parts.push(`${record.message}`);
    }
    if (parts.length > 0) {
      return parts.join(' ');
    }
    return `${err}`;
  }

  private refreshStats(): void {
    try {
      const systemMem = hidebug.getSystemMemInfo();
      const appMem = hidebug.getAppNativeMemInfo();
      this.stats = {
        appCpu: `${(hidebug.getCpuUsage() * 100).toFixed(1)}%`,
        systemCpu: `${(hidebug.getSystemCpuUsage() * 100).toFixed(1)}%`,
        appPss: this.kbToMb(appMem.pss),
        nativeHeap: this.bytesToMb(hidebug.getNativeHeapAllocatedSize()),
        systemMem: `${this.kbToMb(systemMem.availableMem)} 可用`
      };
    } catch (err) {
      this.stats = {
        appCpu: '--',
        systemCpu: '--',
        appPss: '--',
        nativeHeap: '--',
        systemMem: `不可用：${this.formatError(err as Object)}`
      };
    }
  }

  private scrollToBottom(): void {
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

  private appendMessage(role: string, content: string, imageUri: string = '', includeInContext: boolean = true): number {
    const message: ChatMessage = {
      id: this.nextMessageId++,
      role,
      content,
      imageUri,
      time: this.nowTime(),
      includeInContext
    };
    this.messages = [...this.messages, message];
    this.scrollToBottom();
    return message.id;
  }

  private updateMessage(id: number, content: string, includeInContext?: boolean): void {
    this.messages = this.messages.map((message: ChatMessage) => {
      if (message.id === id) {
        return {
          id: message.id,
          role: message.role,
          content,
          imageUri: message.imageUri,
          time: message.time,
          includeInContext: includeInContext === undefined ? message.includeInContext : includeInContext
        };
      }
      return message;
    });
    this.scrollToBottom();
  }

  private appendToMessage(id: number, chunk: string): void {
    this.messages = this.messages.map((message: ChatMessage) => {
      if (message.id === id) {
        return {
          id: message.id,
          role: message.role,
          content: message.content + chunk,
          imageUri: message.imageUri,
          time: message.time,
          includeInContext: message.includeInContext
        };
      }
      return message;
    });
    this.scrollToBottom();
  }

  private sanitizeAssistantText(text: string): string {
    const lines = text
      .split('\n')
      .map((line: string) => line.trimEnd())
      .filter((line: string) => {
        const trimmed = line.trim();
        return trimmed.length > 0 && !/^[*\-•]+\s*$/.test(trimmed);
      });
    return lines.join('\n').trim();
  }

  private newChat(): void {
    this.messages = [{
      id: this.nextMessageId++,
      role: 'assistant',
      content: `新对话已开始。${this.loaded ? `已加载的 ${this.currentModel().shortName} 会继续保留在内存中。` : '请先加载模型。'}`,
      imageUri: '',
      time: this.nowTime(),
      includeInContext: false
    }];
    this.inputText = '';
    this.selectedImageUri = '';
    this.status = this.loaded ? `${this.currentModel().shortName} 已加载` : '模型未加载';
    this.scrollToBottom();
  }

  private stopModelLoadProgress(): void {
    if (this.modelLoadTimer >= 0) {
      clearInterval(this.modelLoadTimer);
      this.modelLoadTimer = -1;
    }
  }

  private startModelLoadProgress(): void {
    this.stopModelLoadProgress();
    this.modelLoadProgress = 8;
    this.modelLoadTimer = setInterval(() => {
      if (this.modelLoadProgress < 88) {
        this.modelLoadProgress = Math.min(88, this.modelLoadProgress + 4);
      }
    }, 160);
  }

  private openModelLoadDialog(autoStart: boolean = false): void {
    this.showModelLoadDialog = true;
    this.activeTab = 0;
    this.modelLoadProgress = this.loaded ? 100 : 0;
    this.modelLoadMessage = this.loaded ? `${this.currentModel().shortName} 已加载，可以开始聊天。` : `正在准备加载 ${this.currentModel().shortName} 本地模型...`;
    if (autoStart) {
      setTimeout(() => {
        if (this.showModelLoadDialog && !this.loaded && !this.modelLoading) {
          this.startModelLoad();
        }
      }, 350);
    }
  }

  private loadModel(): void {
    this.openModelLoadDialog(false);
    this.startModelLoad();
  }

  private startModelLoad(): void {
    if (this.modelLoading) {
      return;
    }
    this.busy = true;
    this.modelLoading = true;
    this.showModelLoadDialog = true;
    this.status = `正在加载 ${this.currentModel().shortName}...`;
    this.modelLoadMessage = '正在加载模型权重，请保持应用在前台。';
    this.startModelLoadProgress();

    entry.loadModelAsync(this.modelPath, this.threadNum, this.maxNewTokens).then((_result: string) => {
      this.loaded = entry.isLoaded() as boolean;
      this.status = `${this.currentModel().shortName} 已加载`;
      this.modelLoadMessage = `${this.currentModel().shortName} 加载完成，已进入聊天。`;
      this.stopModelLoadProgress();
      this.modelLoadProgress = 100;
      this.appendMessage('assistant', `${this.currentModel().shortName} 加载完成，现在可以开始提问。`, '', false);
      this.busy = false;
      this.modelLoading = false;
      this.refreshStats();
      setTimeout(() => {
        this.showModelLoadDialog = false;
        this.scrollToBottom();
      }, 450);
    }).catch((err: Error) => {
      this.status = `加载失败：${this.formatError(err as Object)}`;
      this.modelLoadMessage = this.status;
      this.stopModelLoadProgress();
      this.modelLoadProgress = 0;
      this.appendMessage('assistant', this.status, '', false);
      this.loaded = false;
      this.busy = false;
      this.modelLoading = false;
      this.refreshStats();
    });
  }

  private composeChatTurns(text: string): ChatTurn[] {
    const turns: ChatTurn[] = [{
      role: 'system',
      content: this.currentModel().systemPrompt
    }];
    const contextMessages = this.messages
      .filter((message: ChatMessage) => message.includeInContext && message.content.trim().length > 0)
      .slice(-CONTEXT_MESSAGE_LIMIT);

    contextMessages.forEach((message: ChatMessage) => {
      turns.push({
        role: message.role === 'assistant' ? 'assistant' : 'user',
        content: message.content
      });
    });
    turns.push({
      role: 'user',
      content: text
    });
    return turns;
  }

  private async buildImagePayload(uri: string): Promise<ImagePayload> {
    const file = fs.openSync(uri, fs.OpenMode.READ_ONLY);
    const source = image.createImageSource(file.fd);
    let pixelMap: image.PixelMap | undefined = undefined;
    try {
      const sourceInfo = await source.getImageInfo();
      const sourceWidth = sourceInfo.size.width;
      const sourceHeight = sourceInfo.size.height;
        const sourcePixels = sourceWidth * sourceHeight;
        const scale = sourcePixels > VISION_MAX_PIXELS ? Math.sqrt(VISION_MAX_PIXELS / sourcePixels) : 1;
      const targetWidth = Math.max(1, Math.round(sourceWidth * scale));
      const targetHeight = Math.max(1, Math.round(sourceHeight * scale));

      pixelMap = await source.createPixelMap({
        desiredPixelFormat: image.PixelMapFormat.RGBA_8888,
        desiredSize: {
          width: targetWidth,
          height: targetHeight
        }
      });
      if (!pixelMap) {
        pixelMap = await source.createPixelMap({
          desiredPixelFormat: image.PixelMapFormat.RGBA_8888
        });
      }
      if (!pixelMap) {
        throw new Error('createPixelMap returned undefined');
      }
      const info = await pixelMap.getImageInfo();
      const width = info.size.width;
      const height = info.size.height;
      const pixels = new ArrayBuffer(width * height * 4);
      await pixelMap.readPixelsToBuffer(pixels);
      return { pixels, width, height };
    } finally {
      if (pixelMap) {
        await pixelMap.release();
      }
      fs.closeSync(file);
    }
  }

  private async sendMessage(): Promise<void> {
    const text = this.inputText.trim();
    if (!this.loaded || this.busy || text.length === 0) {
      return;
    }

    const chatTurns = this.composeChatTurns(text);
    const attachedImage = this.selectedImageUri;
    if (attachedImage.length > 0 && !this.currentModel().supportsImage) {
      this.status = `${this.currentModel().shortName} 不支持图片输入，请清除图片后发送。`;
      return;
    }

    this.appendMessage('user', text, attachedImage);
    const assistantId = this.appendMessage('assistant', '', '');
    this.inputText = '';
    this.selectedImageUri = '';
    this.busy = true;
    this.status = '等待首个字元...';
    this.refreshStats();

    let streamedChars = 0;
    let generation: Promise<string>;
    if (attachedImage.length > 0) {
      this.status = '正在读取图片...';
      generation = this.buildImagePayload(attachedImage).then((payload: ImagePayload): Promise<string> => {
        this.status = '等待视觉模型...';
        return entry.generateImageChatStream(
          chatTurns,
          payload.pixels,
          payload.width,
          payload.height,
          this.maxNewTokens,
          (chunk: string) => {
            if (chunk.length > 0) {
              streamedChars += chunk.length;
              this.status = `正在生成... ${streamedChars} 字符`;
              this.appendToMessage(assistantId, chunk);
            }
          });
      });
    } else {
      generation = entry.generateChatStream(chatTurns, this.maxNewTokens, (chunk: string) => {
        if (chunk.length > 0) {
          streamedChars += chunk.length;
          this.status = `正在生成... ${streamedChars} 字符`;
          this.appendToMessage(assistantId, chunk);
        }
      });
    }

    generation.then((finalText: string) => {
      const cleanedText = this.sanitizeAssistantText(finalText);
      const answer = cleanedText.length > 0 ? cleanedText : '（原生层返回空内容）';
      this.updateMessage(assistantId, answer);
      this.status = `生成完成（${answer.length} 字符）`;
      this.busy = false;
      this.refreshStats();
    }).catch((err: Error) => {
      const message = `生成失败：${this.formatError(err as Object)}`;
      this.updateMessage(assistantId, message, false);
      this.status = message;
      this.busy = false;
      this.refreshStats();
    });
  }

  private chooseImage(): void {
    if (!this.currentModel().supportsImage) {
      this.status = `${this.currentModel().shortName} 不支持图片输入。`;
      return;
    }

    const context = getContext(this) as common.UIAbilityContext;
    const photoPicker = new picker.PhotoViewPicker(context);
    const options = new picker.PhotoSelectOptions();
    options.MIMEType = picker.PhotoViewMIMETypes.IMAGE_TYPE;
    options.maxSelectNumber = 1;
    photoPicker.select(options).then((result: picker.PhotoSelectResult) => {
      if (result.photoUris.length > 0) {
        this.selectedImageUri = result.photoUris[0];
      }
    }).catch((err: Error) => {
      this.status = `选择图片失败：${this.formatError(err as Object)}`;
    });
  }

  @Builder
  private StatItem(label: string, value: string) {
    Column({ space: 2 }) {
      Text(label)
        .fontSize(11)
        .fontColor('#8CA2B8');
      Text(value)
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor('#F2F8FF')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis });
    }
    .alignItems(HorizontalAlign.Start)
    .padding(8)
    .backgroundColor('#101D2B')
    .borderRadius(8)
    .width('32%');
  }

  @Builder
  private TabButton(index: number, title: string, desc: string) {
    Column({ space: 2 }) {
      Text(title)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.activeTab === index ? '#F4FBFF' : '#8CA2B8');
      Text(desc)
        .fontSize(10)
        .fontColor(this.activeTab === index ? '#8DE4C3' : '#5F748A')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis });
    }
    .height(54)
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .backgroundColor(this.activeTab === index ? '#14344A' : '#091522')
    .borderRadius(8)
    .onClick(() => {
      this.activeTab = index;
      if (index === 0) {
        this.scrollToBottom();
      }
    });
  }

  @Builder
  private ModelOption(profile: ModelProfile) {
    Column({ space: 4 }) {
      Row() {
        Text(profile.name)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.selectedModelId === profile.id ? '#F4FBFF' : '#B7CDE1')
          .layoutWeight(1);
        Text(profile.supportsImage ? '文本 + 图片' : '仅文本')
          .fontSize(11)
          .fontColor(profile.supportsImage ? '#8DE4C3' : '#F2B35D');
      }
      .width('100%');

      Text(profile.description)
        .fontSize(12)
        .lineHeight(18)
        .fontColor(this.selectedModelId === profile.id ? '#9FBDD5' : '#64788D')
        .width('100%');
    }
    .width('100%')
    .padding(10)
    .backgroundColor(this.selectedModelId === profile.id ? '#14344A' : '#091522')
    .borderRadius(8)
    .onClick(() => {
      this.switchModel(profile.id);
    });
  }

  @Builder
  private MessageBubble(message: ChatMessage) {
    Row() {
      if (message.role === 'user') {
        Blank();
      }
      Column({ space: 6 }) {
        Row() {
          Text(message.role === 'user' ? '你' : '助手')
            .fontSize(11)
            .fontColor(message.role === 'user' ? '#DFF7FF' : '#8FA9C3');
          Text(message.time)
            .fontSize(11)
            .fontColor(message.role === 'user' ? '#B8DAE8' : '#64788D')
            .margin({ left: 8 });
        }
        if (message.imageUri.length > 0) {
          Image(message.imageUri)
            .width(132)
            .height(88)
            .objectFit(ImageFit.Cover)
            .borderRadius(8);
        }
        Text(message.content.length > 0 ? message.content : '...')
          .fontSize(15)
          .lineHeight(22)
          .fontColor(message.role === 'user' ? Color.White : '#EAF4FF');
      }
      .padding({ left: 12, right: 12, top: 10, bottom: 10 })
      .backgroundColor(message.role === 'user' ? '#1267A8' : '#111E2C')
      .borderRadius(8)
      .width(message.role === 'user' ? '84%' : '94%');
      if (message.role !== 'user') {
        Blank();
      }
    }
    .width('100%');
  }

  @Builder
  private AppHeader() {
    Row({ space: 10 }) {
      Image($r('app.media.startIcon'))
        .width(38)
        .height(38)
        .borderRadius(10);
      Column({ space: 2 }) {
        Text('Turbo AI Chat')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor('#F4FBFF');
        Text(this.status)
          .fontSize(12)
          .fontColor(this.loaded ? '#45D6A4' : '#F2B35D')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis });
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start);

      Button('新对话')
        .enabled(!this.busy)
        .height(34)
        .onClick(() => {
          this.newChat();
          this.activeTab = 0;
        });
    }
    .width('100%')
    .height(50);
  }

  @Builder
  private ChatTab() {
    Column({ space: 8 }) {
      List({ space: 10, scroller: this.chatScroller }) {
        ForEach(this.messages, (message: ChatMessage) => {
          ListItem() {
            this.MessageBubble(message);
          }
        }, (message: ChatMessage) => `${message.id}-${message.content.length}`);
      }
      .layoutWeight(1)
      .width('100%')
      .divider({ strokeWidth: 0 });

      if (this.selectedImageUri.length > 0) {
        Row({ space: 8 }) {
          Image(this.selectedImageUri)
            .width(72)
            .height(48)
            .objectFit(ImageFit.Cover)
            .borderRadius(8);
          Text(this.selectedImageUri)
            .fontSize(12)
            .fontColor('#8CA2B8')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1);
          Button('清除')
            .height(34)
            .onClick(() => {
              this.selectedImageUri = '';
            });
        }
        .width('100%')
        .padding(8)
        .backgroundColor('#101D2B')
        .borderRadius(8);
      }

      Row({ space: 8 }) {
        Button(this.currentModel().supportsImage ? '图片' : '仅文本')
          .enabled(!this.busy && this.currentModel().supportsImage)
          .height(44)
          .onClick(() => {
            this.chooseImage();
          });

        TextArea({ text: this.inputText, placeholder: '输入消息' })
          .height(58)
          .layoutWeight(1)
          .fontSize(14)
          .fontColor('#EAF4FF')
          .backgroundColor('#101D2B')
          .maxLines(3)
          .onChange((value: string) => {
            this.inputText = value;
          });

        Button(this.busy ? '生成中' : '发送')
          .enabled(this.loaded && !this.busy && this.inputText.trim().length > 0 && (this.selectedImageUri.length === 0 || this.currentModel().supportsImage))
          .height(44)
          .onClick(() => {
            this.sendMessage();
          });
      }
      .width('100%');
    }
    .layoutWeight(1)
    .width('100%');
  }

  @Builder
  private ModelTab() {
    Scroll() {
      Column({ space: 12 }) {
        Image($r('app.media.home_hero'))
          .width('100%')
          .height(150)
          .objectFit(ImageFit.Cover)
          .borderRadius(8);

        Column({ space: 10 }) {
          Text('模型')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor('#F4FBFF');

          Column({ space: 8 }) {
            ForEach(MODEL_PROFILES, (profile: ModelProfile) => {
              this.ModelOption(profile);
            }, (profile: ModelProfile) => profile.id);
          }
          .width('100%');

          TextInput({ text: this.modelPath, placeholder: '模型配置路径' })
            .onChange((value: string) => {
              this.updateModelPath(value);
            })
            .enabled(!this.busy)
            .height(42)
            .fontSize(12)
            .fontColor('#EAF4FF')
            .backgroundColor('#0A1623')
            .width('100%');

          Text(`当前模型：${this.currentModel().name} · ${this.currentModel().supportsImage ? '支持图片输入' : '仅支持文本输入'}`)
            .fontSize(12)
            .fontColor('#8CA2B8')
            .width('100%');

          Row({ space: 8 }) {
            Button(this.loaded ? '重新加载模型' : '加载模型')
              .enabled(!this.busy)
              .height(40)
              .layoutWeight(1)
              .onClick(() => {
                this.loadModel();
              });

            Button(`输出 ${this.maxNewTokens}/${MAX_GENERATION_TOKENS}`)
              .enabled(false)
              .height(40);
          }

          Column({ space: 4 }) {
            Text(`最大输出 ${this.maxNewTokens}`)
              .fontSize(12)
              .fontColor('#8CA2B8');
            Slider({ value: this.maxNewTokens, min: 16, max: MAX_GENERATION_TOKENS, step: 16 })
              .onChange((value: number) => {
                this.maxNewTokens = Math.round(value);
              });
          }
          .width('100%');

          Column({ space: 4 }) {
            Text(`推理线程 ${this.threadNum}`)
              .fontSize(12)
              .fontColor('#8CA2B8');
            Slider({ value: this.threadNum, min: 2, max: 8, step: 1 })
              .onChange((value: number) => {
                this.threadNum = Math.round(value);
              });
          }
          .width('100%');
        }
        .width('100%')
        .padding(12)
        .backgroundColor('#0D1A28')
        .borderRadius(8);

        Column({ space: 6 }) {
          Text('上下文')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor('#F4FBFF');
          Text(`每轮会带上最近 ${CONTEXT_MESSAGE_LIMIT} 条可记忆消息，系统提示会按当前模型生成，并固定要求使用中文简洁回答。`)
            .fontSize(13)
            .lineHeight(20)
            .fontColor('#8CA2B8');
        }
        .width('100%')
        .padding(12)
        .backgroundColor('#101D2B')
        .borderRadius(8);
      }
      .width('100%');
    }
    .layoutWeight(1)
    .width('100%')
    .scrollBar(BarState.Off);
  }

  @Builder
  private MonitorTab() {
    Column({ space: 12 }) {
      Column({ space: 8 }) {
        Row() {
          Text('设备监控')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor('#F4FBFF')
            .layoutWeight(1);
          Button('刷新')
            .height(34)
            .onClick(() => {
              this.refreshStats();
            });
        }
        .width('100%');

        Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
          this.StatItem('应用 CPU', this.stats.appCpu);
          this.StatItem('系统 CPU', this.stats.systemCpu);
          this.StatItem('应用内存', this.stats.appPss);
          this.StatItem('原生堆', this.stats.nativeHeap);
          this.StatItem('系统内存', this.stats.systemMem);
        }
        .width('100%');
      }
      .width('100%')
      .padding(12)
      .backgroundColor('#0D1A28')
      .borderRadius(8);

      Column({ space: 6 }) {
        Text('运行状态')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor('#F4FBFF');
        Text(this.status)
          .fontSize(13)
          .lineHeight(20)
          .fontColor('#9FBDD5');
      }
      .width('100%')
      .padding(12)
      .backgroundColor('#101D2B')
      .borderRadius(8);

      Blank();
    }
    .layoutWeight(1)
    .width('100%');
  }

  @Builder
  private BottomTabs() {
    Row({ space: 8 }) {
      this.TabButton(0, '聊天', '全屏对话');
      this.TabButton(1, '模型', '加载参数');
      this.TabButton(2, '监控', 'CPU 内存');
    }
    .width('100%')
    .padding(4)
    .backgroundColor('#07111D')
    .borderRadius(10);
  }

  @Builder
  private ModelLoadDialog() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#00000099');

      Column({ space: 14 }) {
        Row({ space: 10 }) {
          Image($r('app.media.startIcon'))
            .width(42)
            .height(42)
            .borderRadius(12);
          Column({ space: 2 }) {
            Text('加载本地模型')
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .fontColor('#F4FBFF');
            Text(`${this.currentModel().shortName} · MNN`)
              .fontSize(12)
              .fontColor('#8DE4C3');
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start);
        }
        .width('100%');

        Text(this.modelLoadMessage)
          .fontSize(14)
          .lineHeight(21)
          .fontColor('#B7CDE1')
          .width('100%');

        Progress({ value: this.modelLoadProgress, total: 100, type: ProgressType.Linear })
          .width('100%')
          .height(8)
          .color('#45D6A4')
          .style({ strokeWidth: 8, strokeRadius: 4, enableScanEffect: this.modelLoading });

        Row() {
          Text(`${Math.round(this.modelLoadProgress)}%`)
            .fontSize(12)
            .fontColor('#8CA2B8')
            .layoutWeight(1);
          Text(this.modelLoading ? '加载中' : (this.loaded ? '已完成' : '等待操作'))
            .fontSize(12)
            .fontColor(this.loaded ? '#45D6A4' : '#F2B35D');
        }
        .width('100%');

        Row({ space: 10 }) {
          if (!this.modelLoading && !this.loaded) {
            Button('稍后')
              .height(38)
              .layoutWeight(1)
              .onClick(() => {
                this.showModelLoadDialog = false;
              });
            Button('立即加载')
              .height(38)
              .layoutWeight(1)
              .onClick(() => {
                this.startModelLoad();
              });
          } else if (this.loaded) {
            Button('开始聊天')
              .height(38)
              .layoutWeight(1)
              .onClick(() => {
                this.showModelLoadDialog = false;
                this.scrollToBottom();
              });
          } else {
            Button('正在加载')
              .enabled(false)
              .height(38)
              .layoutWeight(1);
          }
        }
        .width('100%');
      }
      .width('86%')
      .padding(18)
      .backgroundColor('#0D1A28')
      .borderRadius(10);
    }
    .width('100%')
    .height('100%');
  }

  @Builder
  private LaunchScreen() {
    Stack() {
      Image($r('app.media.launch_art'))
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Cover);
      Column({ space: 12 }) {
        Image($r('app.media.startIcon'))
          .width(92)
          .height(92)
          .borderRadius(24);
        Text('Turbo AI Chat')
          .fontSize(28)
          .fontWeight(FontWeight.Bold)
          .fontColor('#F4FBFF');
        Text('本地智能对话')
          .fontSize(15)
          .fontColor('#9FBDD5');
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center);
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#06121F')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM]);
  }

  @Builder
  private MainScreen() {
    Stack() {
      Column({ space: 10 }) {
        this.AppHeader();
        if (this.activeTab === 0) {
          this.ChatTab();
        } else if (this.activeTab === 1) {
          this.ModelTab();
        } else {
          this.MonitorTab();
        }
        this.BottomTabs();
      }
      .width('100%')
      .height('100%')
      .padding({ left: 14, right: 14, top: 42, bottom: 12 });

      if (this.showModelLoadDialog) {
        this.ModelLoadDialog();
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#06121F')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM]);
  }

  build() {
    if (this.showLaunch) {
      this.LaunchScreen();
    } else {
      this.MainScreen();
    }
  }
}
