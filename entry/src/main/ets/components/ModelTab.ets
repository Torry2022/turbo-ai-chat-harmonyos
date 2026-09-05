import {
  DEFAULT_FREQUENCY_PENALTY,
  DEFAULT_MAX_NEW_TOKENS,
  DEFAULT_PENALTY_WINDOW,
  DEFAULT_PRESENCE_PENALTY,
  DEFAULT_REPETITION_PENALTY,
  DEFAULT_TEMPERATURE,
  DEFAULT_TOP_K,
  DEFAULT_TOP_P,
  ModelProfile
} from '../models/ModelProfile'
import { ChatViewModel } from '../state/ChatViewModel'
import { ModelDragFrame, resolveModelDragPreview } from '../utils/modelDrag'

@Component
export struct ModelTab {
  @ObjectLink viewModel: ChatViewModel
  @Prop @Watch('onRenderVersionChange') renderVersion: number = 0
  onDragStateChange: (dragging: boolean) => void = (_dragging: boolean) => {}
  @State sliderMaxNewTokens: number = DEFAULT_MAX_NEW_TOKENS
  @State sliderTemperature: number = DEFAULT_TEMPERATURE
  @State sliderTopP: number = DEFAULT_TOP_P
  @State sliderTopK: number = DEFAULT_TOP_K
  @State sliderRepetitionPenalty: number = DEFAULT_REPETITION_PENALTY
  @State sliderFrequencyPenalty: number = DEFAULT_FREQUENCY_PENALTY
  @State sliderPresencePenalty: number = DEFAULT_PRESENCE_PENALTY
  @State sliderPenaltyWindow: number = DEFAULT_PENALTY_WINDOW
  @State generationExpanded: boolean = false
  @State runtimeExpanded: boolean = false
  @State importedConfigExpanded: boolean = false
  @State visibleModelProfiles: ModelProfile[] = []
  @State draggingModelId: string = ''
  @State dragOffsetY: number = 0
  @State dragTargetIndex: number = -1
  @State private contentWidth: number = 0
  private modelScroller: Scroller = new Scroller()
  private readonly modelCardGap: number = 8
  private dragStartIndex: number = -1
  private modelCardFrames: Map<string, ModelDragFrame> = new Map()

  aboutToAppear(): void {
    this.syncGenerationSlidersFromViewModel()
    this.onRenderVersionChange()
  }

  private onRenderVersionChange(): void {
    this.refreshModelProfiles()
  }

  private refreshModelProfiles(): void {
    this.visibleModelProfiles = this.viewModel.modelProfiles()
  }

  private syncGenerationSlidersFromViewModel(): void {
    this.sliderMaxNewTokens = this.viewModel.maxNewTokens
    this.sliderTemperature = this.viewModel.temperature
    this.sliderTopP = this.viewModel.topP
    this.sliderTopK = this.viewModel.topK
    this.sliderRepetitionPenalty = this.viewModel.repetitionPenalty
    this.sliderFrequencyPenalty = this.viewModel.frequencyPenalty
    this.sliderPresencePenalty = this.viewModel.presencePenalty
    this.sliderPenaltyWindow = this.viewModel.penaltyWindow
  }

  private resetGenerationSliders(): void {
    this.viewModel.resetGenerationSettings(false)
    this.syncGenerationSlidersFromViewModel()
  }

  private controlsEnabled(): boolean {
    return !this.viewModel.busy &&
      !this.viewModel.modelLoading &&
      !this.viewModel.modelImporting &&
      !this.viewModel.builtinModelInstalling &&
      !this.viewModel.apiServerStarting
  }

  private showToast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message, duration: 1600, bottom: 80 })
    } catch (_) {
    }
  }

  private beginModelDrag(profile: ModelProfile): void {
    if (!this.controlsEnabled()) {
      return
    }
    const index = this.visibleModelProfiles.findIndex((item: ModelProfile) => item.id === profile.id)
    if (index < 0) {
      return
    }
    this.draggingModelId = profile.id
    this.dragStartIndex = index
    this.dragTargetIndex = index
    this.dragOffsetY = 0
    this.onDragStateChange(true)
  }

  private updateModelDrag(offsetY: number): void {
    if (this.draggingModelId.length <= 0 || this.dragStartIndex < 0) {
      return
    }
    const frames = this.currentModelCardFrames()
    if (frames === undefined) {
      this.dragOffsetY = offsetY
      return
    }
    const preview = resolveModelDragPreview(frames, this.dragStartIndex, offsetY)
    this.dragTargetIndex = preview.targetIndex
    this.dragOffsetY = preview.offsetY
  }

  private endModelDrag(): void {
    const modelId = this.draggingModelId
    const startIndex = this.dragStartIndex
    const targetIndex = this.dragTargetIndex
    if (modelId.length > 0) {
      this.onDragStateChange(false)
    }
    this.draggingModelId = ''
    this.dragStartIndex = -1
    this.dragTargetIndex = -1
    this.dragOffsetY = 0
    if (modelId.length > 0 && targetIndex >= 0 && targetIndex !== startIndex) {
      this.viewModel.moveModelToIndex(modelId, targetIndex)
    }
    this.refreshModelProfiles()
  }

  private modelCardOffset(modelId: string): number {
    if (this.draggingModelId.length <= 0 || this.dragStartIndex < 0 || this.dragTargetIndex < 0) {
      return 0
    }
    if (modelId === this.draggingModelId) {
      return this.dragOffsetY
    }
    const index = this.visibleModelProfiles.findIndex((profile: ModelProfile) => profile.id === modelId)
    const draggedFrame = this.modelCardFrames.get(this.draggingModelId)
    if (index < 0 || draggedFrame === undefined) {
      return 0
    }
    const placeholderOffset = draggedFrame.height + this.modelCardGap
    if (this.dragTargetIndex > this.dragStartIndex &&
      index > this.dragStartIndex && index <= this.dragTargetIndex) {
      return -placeholderOffset
    }
    if (this.dragTargetIndex < this.dragStartIndex &&
      index >= this.dragTargetIndex && index < this.dragStartIndex) {
      return placeholderOffset
    }
    return 0
  }

  private currentModelCardFrames(): ModelDragFrame[] | undefined {
    const frames: ModelDragFrame[] = []
    for (let index = 0; index < this.visibleModelProfiles.length; index++) {
      const frame = this.modelCardFrames.get(this.visibleModelProfiles[index].id)
      if (frame === undefined) {
        return undefined
      }
      frames.push(frame)
    }
    return frames
  }

  private lengthValue(value: Length | undefined): number {
    if (value === undefined) {
      return 0
    }
    const numericValue = typeof value === 'number' ? value : Number.parseFloat(`${value}`)
    return Number.isFinite(numericValue) ? numericValue : 0
  }

  private rememberModelCardFrame(modelId: string, area: Area): void {
    const top = this.lengthValue(area.position.y)
    const height = this.lengthValue(area.height)
    if (height > 0) {
      this.modelCardFrames.set(modelId, { top, height })
    }
  }

  @Builder
  private SectionTitle(title: string, subtitle: string = '') {
    Column({ space: 2 }) {
      Text(title)
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor('#F4FBFF')
        .width('100%')
      if (subtitle.length > 0) {
        Text(subtitle)
          .fontSize(12)
          .lineHeight(18)
          .fontColor('#8CA2B8')
          .width('100%')
      }
    }
    .width('100%')
  }

  @Builder
  private CapabilityTag(text: string, color: string, background: string) {
    Text(text)
      .fontSize(11)
      .fontColor(color)
      .padding({ left: 7, right: 7, top: 3, bottom: 3 })
      .backgroundColor(background)
      .borderRadius(4)
  }

  @Builder
  private ModelOption(profile: ModelProfile) {
    Stack({ alignContent: Alignment.BottomEnd }) {
      Column({ space: 4 }) {
        Row({ space: 6 }) {
          Text(profile.name)
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.viewModel.selectedModelId === profile.id ? '#F4FBFF' : '#B7CDE1')
            .layoutWeight(1)
          if (profile.source === 'imported') {
            this.CapabilityTag('导入', '#45D6A4', '#12372E')
          }
          this.CapabilityTag(
            profile.supportsImage ? '文本 + 图片' : '仅文本',
            profile.supportsImage ? '#8DE4C3' : '#F2B35D',
            profile.supportsImage ? '#12372E' : '#3A2A14'
          )
        }
        .width('100%')

        Text(profile.description)
          .fontSize(12)
          .lineHeight(18)
          .fontColor(this.viewModel.selectedModelId === profile.id ? '#9FBDD5' : '#64788D')
          .width('100%')
          .padding({ right: 22 })
      }
      .width('100%')

      Image($r('app.media.model_drag_handle_icon'))
        .width(18)
        .height(18)
        .opacity(this.draggingModelId === profile.id ? 0.9 : 0.5)
        .gesture(
          GestureGroup(GestureMode.Parallel,
            LongPressGesture({ duration: 350 })
              .onAction(() => {
                this.beginModelDrag(profile)
              })
              .onActionEnd(() => {
                this.endModelDrag()
              })
              .onActionCancel(() => {
                this.endModelDrag()
              }),
            PanGesture({ direction: PanDirection.Vertical, distance: 1 })
              .onActionUpdate((event: GestureEvent) => {
                this.updateModelDrag(event.offsetY)
              })
              .onActionEnd(() => {
                this.endModelDrag()
              })
              .onActionCancel(() => {
                this.endModelDrag()
              })
          )
        )
    }
    .width('100%')
    .padding(10)
    .backgroundColor(this.viewModel.selectedModelId === profile.id ? '#14344A' : '#091522')
    .borderRadius(8)
    .shadow(this.draggingModelId === profile.id ? {
      radius: 16,
      color: '#00000066',
      offsetX: 0,
      offsetY: 8
    } : {
      radius: 0,
      color: '#00000000',
      offsetX: 0,
      offsetY: 0
    })
    .scale(this.draggingModelId === profile.id ? { x: 1.02, y: 1.02 } : { x: 1, y: 1 })
    .translate({ x: 0, y: this.modelCardOffset(profile.id) })
    .zIndex(this.draggingModelId === profile.id ? 10 : 0)
    .onAreaChange((_oldValue: Area, newValue: Area) => {
      this.rememberModelCardFrame(profile.id, newValue)
    })
    .onClick(() => {
      if (!this.controlsEnabled() || this.draggingModelId.length > 0) {
        return
      }
      this.viewModel.switchModel(profile.id)
      this.syncGenerationSlidersFromViewModel()
      this.importedConfigExpanded = profile.source === 'imported'
    })
  }

  private contextDescription(): string {
    const limit = this.viewModel.currentContextMessageLimit()
    if (limit <= 0) {
      return '当前模型默认使用单轮对话，不会把上一轮问答继续带入推理。'
    }
    return `当前模型每轮会带上最近 ${limit} 条可记忆消息。`
  }

  @Builder
  private ModelListCard() {
    Column({ space: 10 }) {
      this.SectionTitle('模型列表')
      Column({ space: 8 }) {
        ForEach(this.visibleModelProfiles, (profile: ModelProfile) => {
          this.ModelOption(profile)
        }, (profile: ModelProfile) =>
          `${profile.id}-${profile.name}-${profile.shortName}-${profile.description}`)
      }
      .width('100%')
      .zIndex(this.draggingModelId.length > 0 ? 10 : 0)
      Button(this.viewModel.loaded ? '释放模型' : '加载模型')
        .enabled(this.controlsEnabled())
        .height(38)
        .width('100%')
        .fontColor('#F4FBFF')
        .backgroundColor(this.viewModel.loaded ? '#26384D' : '#0F62FE')
        .onClick(() => {
          if (this.viewModel.loaded) {
            this.viewModel.unloadModel()
            return
          }
            this.viewModel.loadModel()
          })
      if (this.viewModel.canDeleteModel(this.viewModel.selectedModelId)) {
        Button('删除当前模型')
          .enabled(this.controlsEnabled())
          .height(38)
          .width('100%')
          .fontColor('#F4FBFF')
          .backgroundColor('#B43B3B')
          .onClick(() => {
            this.viewModel.requestDeleteModel(this.viewModel.selectedModelId)
          })
      }
    }
    .width('100%')
    .padding(12)
    .backgroundColor('#0D1A28')
    .borderRadius(8)
    .zIndex(this.draggingModelId.length > 0 ? 10 : 0)
  }

  @Builder
  private GenerationSliders() {
    Column({ space: 4 }) {
      Row() {
        Text('最大输出')
          .fontSize(12)
          .fontColor('#8CA2B8')
          .layoutWeight(1)
        Text(`${this.sliderMaxNewTokens} tokens`)
          .fontSize(12)
          .fontColor('#EAF4FF')
      }
      .width('100%')
      Slider({ value: this.sliderMaxNewTokens, min: 128, max: this.viewModel.maxGenerationTokens, step: 128 })
        .enabled(this.controlsEnabled())
        .onChange((value: number, _mode: SliderChangeMode) => {
          this.sliderMaxNewTokens = Math.round(value)
          this.viewModel.updateMaxNewTokens(this.sliderMaxNewTokens, false)
        })
    }
    .width('100%')

    Column({ space: 4 }) {
      Row() {
        Text('温度')
          .fontSize(12)
          .fontColor('#8CA2B8')
          .layoutWeight(1)
        Text(`${this.sliderTemperature}`)
          .fontSize(12)
          .fontColor('#EAF4FF')
      }
      .width('100%')
      Slider({ value: this.sliderTemperature, min: 0, max: 2, step: 0.05 })
        .enabled(this.controlsEnabled())
        .onChange((value: number, _mode: SliderChangeMode) => {
          this.sliderTemperature = Math.round(value * 100) / 100
          this.viewModel.updateTemperature(this.sliderTemperature, false)
        })
    }
    .width('100%')

    Column({ space: 4 }) {
      Row() {
        Text('Top-P')
          .fontSize(12)
          .fontColor('#8CA2B8')
          .layoutWeight(1)
        Text(`${this.sliderTopP}`)
          .fontSize(12)
          .fontColor('#EAF4FF')
      }
      .width('100%')
      Slider({ value: this.sliderTopP, min: 0.05, max: 1, step: 0.05 })
        .enabled(this.controlsEnabled())
        .onChange((value: number, _mode: SliderChangeMode) => {
          this.sliderTopP = Math.round(value * 100) / 100
          this.viewModel.updateTopP(this.sliderTopP, false)
        })
    }
    .width('100%')

    Column({ space: 4 }) {
      Row() {
        Text('Top K')
          .fontSize(12)
          .fontColor('#8CA2B8')
          .layoutWeight(1)
        Text(`${this.sliderTopK}`)
          .fontSize(12)
          .fontColor('#EAF4FF')
      }
      .width('100%')
      Slider({ value: this.sliderTopK, min: 1, max: 128, step: 1 })
        .enabled(this.controlsEnabled())
        .onChange((value: number, _mode: SliderChangeMode) => {
          this.sliderTopK = Math.round(value)
          this.viewModel.updateTopK(this.sliderTopK, false)
        })
    }
    .width('100%')

    Column({ space: 4 }) {
      Row() {
        Text('重复惩罚')
          .fontSize(12)
          .fontColor('#8CA2B8')
          .layoutWeight(1)
        Text(`${this.sliderRepetitionPenalty}`)
          .fontSize(12)
          .fontColor('#EAF4FF')
      }
      .width('100%')
      Slider({ value: this.sliderRepetitionPenalty, min: 0.8, max: 1.5, step: 0.05 })
        .enabled(this.controlsEnabled())
        .onChange((value: number, _mode: SliderChangeMode) => {
          this.sliderRepetitionPenalty = Math.round(value * 100) / 100
          this.viewModel.updateRepetitionPenalty(this.sliderRepetitionPenalty, false)
        })
    }
    .width('100%')

    Column({ space: 4 }) {
      Row() {
        Text('频率惩罚')
          .fontSize(12)
          .fontColor('#8CA2B8')
          .layoutWeight(1)
        Text(`${this.sliderFrequencyPenalty}`)
          .fontSize(12)
          .fontColor('#EAF4FF')
      }
      .width('100%')
      Slider({ value: this.sliderFrequencyPenalty, min: 0, max: 1, step: 0.05 })
        .enabled(this.controlsEnabled())
        .onChange((value: number, _mode: SliderChangeMode) => {
          this.sliderFrequencyPenalty = Math.round(value * 100) / 100
          this.viewModel.updateFrequencyPenalty(this.sliderFrequencyPenalty, false)
        })
    }
    .width('100%')

    Column({ space: 4 }) {
      Row() {
        Text('存在惩罚')
          .fontSize(12)
          .fontColor('#8CA2B8')
          .layoutWeight(1)
        Text(`${this.sliderPresencePenalty}`)
          .fontSize(12)
          .fontColor('#EAF4FF')
      }
      .width('100%')
      Slider({ value: this.sliderPresencePenalty, min: 0, max: 1, step: 0.05 })
        .enabled(this.controlsEnabled())
        .onChange((value: number, _mode: SliderChangeMode) => {
          this.sliderPresencePenalty = Math.round(value * 100) / 100
          this.viewModel.updatePresencePenalty(this.sliderPresencePenalty, false)
        })
    }
    .width('100%')

    Column({ space: 4 }) {
      Row() {
        Text('惩罚窗口')
          .fontSize(12)
          .fontColor('#8CA2B8')
          .layoutWeight(1)
        Text(`${this.sliderPenaltyWindow} tokens`)
          .fontSize(12)
          .fontColor('#EAF4FF')
      }
      .width('100%')
      Slider({ value: this.sliderPenaltyWindow, min: 0, max: 2048, step: 64 })
        .enabled(this.controlsEnabled())
        .onChange((value: number, _mode: SliderChangeMode) => {
          this.sliderPenaltyWindow = Math.round(value)
          this.viewModel.updatePenaltyWindow(this.sliderPenaltyWindow, false)
        })
    }
    .width('100%')
  }

  @Builder
  private GenerationSettingsCard() {
    Column({ space: 10 }) {
      Row() {
        Text('生成参数')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor('#F4FBFF')
          .layoutWeight(1)
        Row({ space: 4 }) {
          Text(this.generationExpanded ? '收起 ▲' : '展开 ▼')
            .fontSize(12)
            .fontColor('#5A7A9A')
        }
      }
      .width('100%')
      .onClick(() => {
        this.generationExpanded = !this.generationExpanded
      })
      if (!this.generationExpanded) {
        Text() {
          Span('当前参数：Temp ')
            .fontSize(11)
            .fontColor('#5A7A9A')
          Span(`${this.sliderTemperature}`)
            .fontSize(11)
            .fontColor('#5A7A9A')
          Span('  |  Top-P ')
            .fontSize(11)
            .fontColor('#5A7A9A')
          Span(`${this.sliderTopP}`)
            .fontSize(11)
            .fontColor('#5A7A9A')
          Span('  |  Top-K ')
            .fontSize(11)
            .fontColor('#5A7A9A')
          Span(`${this.sliderTopK}`)
            .fontSize(11)
            .fontColor('#5A7A9A')
          Span('  |  RepPen ')
            .fontSize(11)
            .fontColor('#5A7A9A')
          Span(`${this.sliderRepetitionPenalty}`)
            .fontSize(11)
            .fontColor('#5A7A9A')
        }
        .width('100%')
      }
      if (this.generationExpanded) {
        this.GenerationSliders()
        Button('恢复默认')
          .enabled(this.controlsEnabled())
          .height(36)
          .width('100%')
          .fontColor('#F4FBFF')
          .onClick(() => {
            this.resetGenerationSliders()
          })
      }
    }
    .width('100%')
    .padding(12)
    .backgroundColor('#101D2B')
    .borderRadius(8)
  }

  @Builder
  private RuntimeSettingsCard() {
    Column({ space: 10 }) {
      Row() {
        Text('运行配置')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor('#F4FBFF')
          .layoutWeight(1)
        Row({ space: 4 }) {
          Text(this.runtimeExpanded ? '收起 ▲' : '展开 ▼')
            .fontSize(12)
            .fontColor('#5A7A9A')
        }
      }
      .width('100%')
      .onClick(() => {
        this.runtimeExpanded = !this.runtimeExpanded
      })
      Text('可修改模型文件路径和 CPU 推理线程数，修改后需重新加载模型')
        .fontSize(11)
        .fontColor('#5A7A9A')
        .width('100%')
      if (this.runtimeExpanded) {
      Column({ space: 4 }) {
        Text('模型配置路径')
          .fontSize(12)
          .fontColor('#8CA2B8')
          .width('100%')
        TextInput({ text: this.viewModel.modelPath, placeholder: '模型配置路径' })
          .onChange((value: string) => {
            this.viewModel.updateModelPath(value)
          })
          .enabled(this.controlsEnabled())
          .height(42)
          .fontSize(12)
          .fontColor('#EAF4FF')
          .backgroundColor('#0A1623')
          .width('100%')
      }
      .width('100%')
      Column({ space: 4 }) {
        Row() {
          Text('推理线程')
            .fontSize(12)
            .fontColor('#8CA2B8')
            .layoutWeight(1)
          Text(`${this.viewModel.threadNum}`)
            .fontSize(12)
            .fontColor('#EAF4FF')
        }
        .width('100%')
        Slider({ value: this.viewModel.threadNum, min: 2, max: 8, step: 1 })
          .enabled(this.controlsEnabled())
          .onChange((value: number, _mode: SliderChangeMode) => {
            this.viewModel.updateThreadNum(value)
          })
        Text('更改后需重新加载模型生效')
          .fontSize(11)
          .fontColor('#5A7A9A')
          .width('100%')
      }
      .width('100%')
        Button(this.viewModel.loaded ? '应用并重新加载' : '应用并加载')
          .enabled(this.controlsEnabled())
          .height(38)
          .width('100%')
          .fontColor('#F4FBFF')
          .backgroundColor('#0F62FE')
          .onClick(() => {
            this.viewModel.applyRuntimeConfigAndLoad()
          })
      }
    }
    .width('100%')
    .padding(12)
    .backgroundColor('#101D2B')
    .borderRadius(8)
  }

  @Builder
  private ImportedModelConfigCard() {
    if (this.viewModel.currentModel().source === 'imported') {
      Column({ space: 10 }) {
        Row() {
          Text('导入模型配置')
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor('#F4FBFF')
            .layoutWeight(1)
          Row({ space: 4 }) {
            Text(this.importedConfigExpanded ? '收起 ▲' : '展开 ▼')
              .fontSize(12)
              .fontColor('#5A7A9A')
          }
        }
        .width('100%')
        .onClick(() => {
          this.importedConfigExpanded = !this.importedConfigExpanded
        })
        Text('可修改已导入模型的名称、描述和系统提示词')
          .fontSize(11)
          .fontColor('#5A7A9A')
          .width('100%')
        if (this.importedConfigExpanded) {
          Column({ space: 4 }) {
            Text('模型名称')
              .fontSize(12)
              .fontColor('#8CA2B8')
              .width('100%')
            TextInput({ text: this.viewModel.importedModelNameInput, placeholder: '模型名称' })
              .onChange((value: string) => {
                this.viewModel.updateImportedModelName(value)
              })
              .enabled(this.controlsEnabled())
              .height(40)
              .fontSize(12)
              .fontColor('#EAF4FF')
              .backgroundColor('#0A1623')
              .width('100%')
          }
          .width('100%')

          Column({ space: 4 }) {
            Text('短名称')
              .fontSize(12)
              .fontColor('#8CA2B8')
              .width('100%')
            TextInput({ text: this.viewModel.importedModelShortNameInput, placeholder: '短名称' })
              .onChange((value: string) => {
                this.viewModel.updateImportedModelShortName(value)
              })
              .enabled(this.controlsEnabled())
              .height(40)
              .fontSize(12)
              .fontColor('#EAF4FF')
              .backgroundColor('#0A1623')
              .width('100%')
          }
          .width('100%')

          Column({ space: 4 }) {
            Text('模型描述')
              .fontSize(12)
              .fontColor('#8CA2B8')
              .width('100%')
            TextInput({ text: this.viewModel.importedModelDescriptionInput, placeholder: '模型描述' })
              .onChange((value: string) => {
                this.viewModel.updateImportedModelDescription(value)
              })
              .enabled(this.controlsEnabled())
              .height(40)
              .fontSize(12)
              .fontColor('#EAF4FF')
              .backgroundColor('#0A1623')
              .width('100%')
          }
          .width('100%')

          Column({ space: 4 }) {
            Text('系统提示词')
              .fontSize(12)
              .fontColor('#8CA2B8')
              .width('100%')
            TextInput({ text: this.viewModel.importedModelSystemPromptInput, placeholder: '系统提示词' })
              .onChange((value: string) => {
                this.viewModel.updateImportedModelSystemPrompt(value)
              })
              .enabled(this.controlsEnabled())
              .height(44)
              .fontSize(12)
              .fontColor('#EAF4FF')
              .backgroundColor('#0A1623')
              .width('100%')
          }
          .width('100%')

          Button('保存配置')
            .enabled(this.controlsEnabled())
            .height(38)
            .width('100%')
            .fontColor('#F4FBFF')
            .onClick(() => {
              this.viewModel.saveImportedModelProfile().then((saved: boolean) => {
                if (saved) {
                  this.refreshModelProfiles()
                  this.showToast('模型配置已保存')
                }
              })
            })
        }
      }
      .width('100%')
      .padding(12)
      .backgroundColor('#101D2B')
      .borderRadius(8)
    }
  }

  @Builder
  private ModelManagementCard() {
    Column({ space: 8 }) {
      this.SectionTitle('模型管理')
      Button('扫描已推送目录')
        .enabled(this.controlsEnabled())
        .height(38)
        .width('100%')
        .fontColor('#F4FBFF')
        .backgroundColor('#26384D')
        .onClick(() => {
          this.viewModel.scanPushedModelDirectories()
        })
      Button(this.viewModel.modelImporting ? '正在导入' : '导入模型压缩包')
        .enabled(this.controlsEnabled())
        .height(38)
        .width('100%')
        .fontColor('#F4FBFF')
        .onClick(() => {
          this.viewModel.importModelPackage()
        })
      Text(this.viewModel.modelImportMessage)
        .fontSize(12)
        .lineHeight(18)
        .fontColor(this.viewModel.modelImportMessage.indexOf('失败') >= 0 ? '#FF9C9C' : '#8CA2B8')
        .height(36)
        .width('100%')
      Text('大模型可推送到 model-imports 后扫描。')
        .fontSize(11)
        .lineHeight(16)
        .fontColor('#5A7A9A')
        .width('100%')
    }
    .width('100%')
    .padding(12)
    .backgroundColor('#101D2B')
    .borderRadius(8)
  }

  @Builder
  private ContextCard() {
    Column({ space: 6 }) {
      this.SectionTitle('上下文')
      Text(this.contextDescription())
        .width('100%')
        .fontSize(13)
        .lineHeight(20)
        .fontColor('#8CA2B8')
    }
    .width('100%')
    .padding(12)
    .backgroundColor('#101D2B')
    .borderRadius(8)
  }

  build() {
    Scroll(this.modelScroller) {
      Flex({ direction: this.contentWidth >= 800 ? FlexDirection.Row : FlexDirection.Column }) {
        Column() {
          this.ModelListCard()
        }
        .width(this.contentWidth >= 800 ? Math.max(320, Math.min(420, this.contentWidth * 0.4)) : this.contentWidth)
        .flexShrink(0)
        .zIndex(this.draggingModelId.length > 0 ? 10 : 0)
        .margin({ right: this.contentWidth >= 800 ? 16 : 0, bottom: this.contentWidth >= 800 ? 0 : 12 })
        Column({ space: 12 }) {
          this.GenerationSettingsCard()
          this.RuntimeSettingsCard()
          this.ImportedModelConfigCard()
          this.ContextCard()
          this.ModelManagementCard()
        }
        .width(this.contentWidth >= 800 ?
          this.contentWidth - Math.max(320, Math.min(420, this.contentWidth * 0.4)) - 16 : this.contentWidth)
        .flexShrink(0)
      }
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      this.contentWidth = Number(newArea.width)
    })
    .align(Alignment.Top)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .enableScrollInteraction(this.draggingModelId.length <= 0)
  }
}
