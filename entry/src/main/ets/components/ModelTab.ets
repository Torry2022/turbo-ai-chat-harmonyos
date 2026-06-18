import {
  CHAT_FORMAT_GEMMA_TURN,
  CHAT_FORMAT_MINICPM_THINKING,
  CHAT_FORMAT_QWEN_IM,
  CHAT_FORMAT_RAW_TEMPLATE,
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

@Component
export struct ModelTab {
  @ObjectLink viewModel: ChatViewModel
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

  aboutToAppear(): void {
    this.syncGenerationSlidersFromViewModel()
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
      !this.viewModel.builtinModelInstalling
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
        this.CapabilityTag(profile.supportsImage ? '文本 + 图片' : '仅文本', profile.supportsImage ? '#8DE4C3' : '#F2B35D', '#0B1B2A')
      }
      .width('100%')

      Text(profile.description)
        .fontSize(12)
        .lineHeight(18)
        .fontColor(this.viewModel.selectedModelId === profile.id ? '#9FBDD5' : '#64788D')
        .width('100%')
    }
    .width('100%')
    .padding(10)
    .backgroundColor(this.viewModel.selectedModelId === profile.id ? '#14344A' : '#091522')
    .borderRadius(8)
    .onClick(() => {
      if (!this.controlsEnabled()) {
        return
      }
      this.viewModel.switchModel(profile.id)
      this.syncGenerationSlidersFromViewModel()
    })
  }

  private chatFormatLabel(): string {
    if (this.viewModel.importedModelChatFormatInput === CHAT_FORMAT_RAW_TEMPLATE) {
      return '原始模板'
    }
    if (this.viewModel.importedModelChatFormatInput === CHAT_FORMAT_QWEN_IM) {
      return 'Qwen IM'
    }
    if (this.viewModel.importedModelChatFormatInput === CHAT_FORMAT_GEMMA_TURN) {
      return 'Gemma Turn'
    }
    if (this.viewModel.importedModelChatFormatInput === CHAT_FORMAT_MINICPM_THINKING) {
      return 'MiniCPM Thinking'
    }
    return '自动'
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
        ForEach(this.viewModel.modelProfiles(), (profile: ModelProfile) => {
          this.ModelOption(profile)
        }, (profile: ModelProfile) => profile.id)
      }
      .width('100%')
      if (this.viewModel.loaded) {
        Button('释放模型')
          .width('100%')
          .height(38)
          .enabled(this.controlsEnabled())
          .fontColor('#B7CDE1')
          .backgroundColor('#14344A')
          .onClick(() => {
            this.viewModel.unloadModel()
          })
      }
      Button(this.viewModel.loaded ? '重新加载模型' : '加载模型')
        .width('100%')
        .height(38)
        .enabled(this.controlsEnabled())
        .fontColor('#F4FBFF')
        .backgroundColor('#0F62FE')
        .onClick(() => {
            this.viewModel.loadModel()
          })
    }
    .width('100%')
    .padding(12)
    .backgroundColor('#0D1A28')
    .borderRadius(8)
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
      Slider({ value: this.sliderMaxNewTokens, min: 64, max: this.viewModel.maxGenerationTokens, step: 64 })
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
        Text('可修改已导入模型的名称、系统提示词、对话格式和停止序列')
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

        Button(this.viewModel.showAdvancedModelSettings ? '收起高级参数' : '展开高级参数')
          .enabled(this.controlsEnabled())
          .height(38)
          .width('100%')
          .onClick(() => {
            this.viewModel.toggleAdvancedModelSettings()
          })

        if (this.viewModel.showAdvancedModelSettings) {
          this.ImportedAdvancedSettings()
        }

        Button('保存配置')
          .enabled(this.controlsEnabled())
          .height(38)
          .width('100%')
          .onClick(() => {
            this.viewModel.saveImportedModelProfile()
          })

        Button('删除模型')
          .enabled(this.controlsEnabled())
          .height(38)
          .width('100%')
          .backgroundColor('#733030')
          .onClick(() => {
            this.viewModel.requestDeleteImportedModel(this.viewModel.currentModel().id)
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
  private ImportedAdvancedSettings() {
    Column({ space: 8 }) {
      Column({ space: 4 }) {
        Text('对话格式')
          .fontSize(12)
          .fontColor('#8CA2B8')
          .width('100%')
        Button(this.chatFormatLabel())
          .enabled(this.controlsEnabled())
          .height(38)
          .backgroundColor('#15283D')
          .width('100%')
          .onClick(() => {
            this.viewModel.cycleImportedModelChatFormat()
          })
      }
      .width('100%')

    }
    .width('100%')
    .padding(10)
    .backgroundColor('#091522')
    .borderRadius(8)
  }

  @Builder
  private ModelManagementCard() {
    Column({ space: 8 }) {
      this.SectionTitle('模型管理')
      Button(this.viewModel.modelImporting ? '正在导入' : '导入模型包')
        .enabled(this.controlsEnabled())
        .height(38)
        .width('100%')
        .onClick(() => {
          this.viewModel.importModelPackage()
        })
      Text(this.viewModel.modelImportMessage)
        .fontSize(12)
        .lineHeight(18)
        .fontColor(this.viewModel.modelImportMessage.startsWith('导入失败') ? '#FF9C9C' : '#8CA2B8')
        .width('100%')
      Text('过大的 zip 包可能因格式兼容问题导入失败，建议用 hdc file send -b 命令直接推送模型目录。')
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
    Scroll() {
      Column({ space: 12 }) {
        this.ModelListCard()
        this.GenerationSettingsCard()
        this.RuntimeSettingsCard()
        this.ImportedModelConfigCard()
        this.ContextCard()
        this.ModelManagementCard()
      }
      .width('100%')
    }
    .layoutWeight(1)
    .width('100%')
    .align(Alignment.Top)
    .scrollBar(BarState.Off)
  }
}
