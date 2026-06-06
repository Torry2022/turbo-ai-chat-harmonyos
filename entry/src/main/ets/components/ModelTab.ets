import { CONTEXT_MESSAGE_LIMIT } from '../models/ChatTypes';
import {
  CHAT_FORMAT_MNN_AUTO,
  CHAT_FORMAT_QWEN_IM,
  CHAT_FORMAT_RAW_TEMPLATE,
  DEFAULT_MAX_NEW_TOKENS,
  DEFAULT_REPETITION_PENALTY,
  DEFAULT_TEMPERATURE,
  DEFAULT_TOP_K,
  DEFAULT_TOP_P,
  ModelProfile
} from '../models/ModelProfile';
import { ChatViewModel } from '../state/ChatViewModel';

@Component
export struct ModelTab {
  @ObjectLink viewModel: ChatViewModel;
  @State sliderMaxNewTokens: number = DEFAULT_MAX_NEW_TOKENS;
  @State sliderTemperature: number = DEFAULT_TEMPERATURE;
  @State sliderTopP: number = DEFAULT_TOP_P;
  @State sliderTopK: number = DEFAULT_TOP_K;
  @State sliderRepetitionPenalty: number = DEFAULT_REPETITION_PENALTY;

  aboutToAppear(): void {
    this.syncGenerationSlidersFromViewModel();
  }

  private syncGenerationSlidersFromViewModel(): void {
    this.sliderMaxNewTokens = this.viewModel.maxNewTokens;
    this.sliderTemperature = this.viewModel.temperature;
    this.sliderTopP = this.viewModel.topP;
    this.sliderTopK = this.viewModel.topK;
    this.sliderRepetitionPenalty = this.viewModel.repetitionPenalty;
  }

  private resetGenerationSliders(): void {
    this.sliderMaxNewTokens = DEFAULT_MAX_NEW_TOKENS;
    this.sliderTemperature = DEFAULT_TEMPERATURE;
    this.sliderTopP = DEFAULT_TOP_P;
    this.sliderTopK = DEFAULT_TOP_K;
    this.sliderRepetitionPenalty = DEFAULT_REPETITION_PENALTY;
    this.viewModel.resetGenerationSettings();
  }

  @Builder
  private SectionTitle(title: string, subtitle: string = '') {
    Column({ space: 2 }) {
      Text(title)
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor('#F4FBFF')
        .width('100%');
      if (subtitle.length > 0) {
        Text(subtitle)
          .fontSize(12)
          .lineHeight(18)
          .fontColor('#8CA2B8')
          .width('100%');
      }
    }
    .width('100%');
  }

  @Builder
  private CapabilityTag(text: string, color: string, background: string) {
    Text(text)
      .fontSize(11)
      .fontColor(color)
      .padding({ left: 7, right: 7, top: 3, bottom: 3 })
      .backgroundColor(background)
      .borderRadius(4);
  }

  @Builder
  private ModelOption(profile: ModelProfile) {
    Column({ space: 4 }) {
      Row({ space: 6 }) {
        Text(profile.name)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.viewModel.selectedModelId === profile.id ? '#F4FBFF' : '#B7CDE1')
          .layoutWeight(1);
        if (profile.source === 'imported') {
          this.CapabilityTag('导入', '#45D6A4', '#12372E');
        }
        this.CapabilityTag(profile.supportsImage ? '文本 + 图片' : '仅文本', profile.supportsImage ? '#8DE4C3' : '#F2B35D', '#0B1B2A');
      }
      .width('100%');

      Text(profile.description)
        .fontSize(12)
        .lineHeight(18)
        .fontColor(this.viewModel.selectedModelId === profile.id ? '#9FBDD5' : '#64788D')
        .width('100%');
    }
    .width('100%')
    .padding(10)
    .backgroundColor(this.viewModel.selectedModelId === profile.id ? '#14344A' : '#091522')
    .borderRadius(8)
    .onClick(() => {
      this.viewModel.switchModel(profile.id);
    });
  }

  private chatFormatLabel(): string {
    if (this.viewModel.importedModelChatFormatInput === CHAT_FORMAT_RAW_TEMPLATE) {
      return '原始模板';
    }
    if (this.viewModel.importedModelChatFormatInput === CHAT_FORMAT_QWEN_IM) {
      return 'Qwen IM';
    }
    return '自动';
  }

  @Builder
  private ModelListCard() {
    Column({ space: 10 }) {
      this.SectionTitle('模型列表');
      Column({ space: 8 }) {
        ForEach(this.viewModel.modelProfiles(), (profile: ModelProfile) => {
          this.ModelOption(profile);
        }, (profile: ModelProfile) => profile.id);
      }
      .width('100%');
      Button(this.viewModel.loaded ? '重新加载模型' : '加载模型')
        .enabled(!this.viewModel.busy)
        .height(42)
        .width('100%')
        .onClick(() => {
          this.viewModel.loadModel();
        });
    }
    .width('100%')
    .padding(12)
    .backgroundColor('#0D1A28')
    .borderRadius(8);
  }

  @Builder
  private GenerationSliders() {
    Column({ space: 4 }) {
      Row() {
        Text('最大输出')
          .fontSize(12)
          .fontColor('#8CA2B8')
          .layoutWeight(1);
        Text(`${this.sliderMaxNewTokens} tokens`)
          .fontSize(12)
          .fontColor('#EAF4FF');
      }
      .width('100%');
      Slider({ value: this.sliderMaxNewTokens, min: 16, max: this.viewModel.maxGenerationTokens, step: 16 })
        .onChange((value: number, _mode: SliderChangeMode) => {
          this.sliderMaxNewTokens = Math.round(value);
          this.viewModel.updateMaxNewTokens(this.sliderMaxNewTokens, false);
        });
    }
    .width('100%');

    Column({ space: 4 }) {
      Row() {
        Text('温度')
          .fontSize(12)
          .fontColor('#8CA2B8')
          .layoutWeight(1);
        Text(`${this.sliderTemperature}`)
          .fontSize(12)
          .fontColor('#EAF4FF');
      }
      .width('100%');
      Slider({ value: this.sliderTemperature, min: 0, max: 2, step: 0.05 })
        .onChange((value: number, _mode: SliderChangeMode) => {
          this.sliderTemperature = Math.round(value * 100) / 100;
          this.viewModel.updateTemperature(this.sliderTemperature, false);
        });
    }
    .width('100%');

    Column({ space: 4 }) {
      Row() {
        Text('Top P')
          .fontSize(12)
          .fontColor('#8CA2B8')
          .layoutWeight(1);
        Text(`${this.sliderTopP}`)
          .fontSize(12)
          .fontColor('#EAF4FF');
      }
      .width('100%');
      Slider({ value: this.sliderTopP, min: 0.05, max: 1, step: 0.05 })
        .onChange((value: number, _mode: SliderChangeMode) => {
          this.sliderTopP = Math.round(value * 100) / 100;
          this.viewModel.updateTopP(this.sliderTopP, false);
        });
    }
    .width('100%');

    Column({ space: 4 }) {
      Row() {
        Text('Top K')
          .fontSize(12)
          .fontColor('#8CA2B8')
          .layoutWeight(1);
        Text(`${this.sliderTopK}`)
          .fontSize(12)
          .fontColor('#EAF4FF');
      }
      .width('100%');
      Slider({ value: this.sliderTopK, min: 1, max: 128, step: 1 })
        .onChange((value: number, _mode: SliderChangeMode) => {
          this.sliderTopK = Math.round(value);
          this.viewModel.updateTopK(this.sliderTopK, false);
        });
    }
    .width('100%');

    Column({ space: 4 }) {
      Row() {
        Text('重复惩罚')
          .fontSize(12)
          .fontColor('#8CA2B8')
          .layoutWeight(1);
        Text(`${this.sliderRepetitionPenalty}`)
          .fontSize(12)
          .fontColor('#EAF4FF');
      }
      .width('100%');
      Slider({ value: this.sliderRepetitionPenalty, min: 0.8, max: 1.5, step: 0.05 })
        .onChange((value: number, _mode: SliderChangeMode) => {
          this.sliderRepetitionPenalty = Math.round(value * 100) / 100;
          this.viewModel.updateRepetitionPenalty(this.sliderRepetitionPenalty, false);
        });
    }
    .width('100%');
  }

  @Builder
  private GenerationSettingsCard() {
    Column({ space: 10 }) {
      Row() {
        Text('生成参数')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor('#F4FBFF')
          .layoutWeight(1);
        Button('恢复默认')
          .enabled(!this.viewModel.busy)
          .height(32)
          .fontSize(12)
          .onClick(() => {
            this.resetGenerationSliders();
          });
      }
      .width('100%');
      this.GenerationSliders();
    }
    .width('100%')
    .padding(12)
    .backgroundColor('#101D2B')
    .borderRadius(8);
  }

  @Builder
  private RuntimeSettingsCard() {
    Column({ space: 10 }) {
      this.SectionTitle('运行参数');
      Column({ space: 4 }) {
        Text('模型配置路径')
          .fontSize(12)
          .fontColor('#8CA2B8')
          .width('100%');
        TextInput({ text: this.viewModel.modelPath, placeholder: '模型配置路径' })
          .onChange((value: string) => {
            this.viewModel.updateModelPath(value);
          })
          .enabled(!this.viewModel.busy)
          .height(42)
          .fontSize(12)
          .fontColor('#EAF4FF')
          .backgroundColor('#0A1623')
          .width('100%');
      }
      .width('100%');
      Column({ space: 4 }) {
        Row() {
          Text('推理线程')
            .fontSize(12)
            .fontColor('#8CA2B8')
            .layoutWeight(1);
          Text(`${this.viewModel.threadNum}`)
            .fontSize(12)
            .fontColor('#EAF4FF');
        }
        .width('100%');
        Slider({ value: this.viewModel.threadNum, min: 2, max: 8, step: 1 })
          .onChange((value: number, _mode: SliderChangeMode) => {
            this.viewModel.updateThreadNum(value);
          });
      }
      .width('100%');
    }
    .width('100%')
    .padding(12)
    .backgroundColor('#101D2B')
    .borderRadius(8);
  }

  @Builder
  private ImportedModelConfigCard() {
    if (this.viewModel.currentModel().source === 'imported') {
      Column({ space: 10 }) {
        this.SectionTitle('导入模型配置');
        Column({ space: 4 }) {
          Text('模型名称')
            .fontSize(12)
            .fontColor('#8CA2B8')
            .width('100%');
          TextInput({ text: this.viewModel.importedModelNameInput, placeholder: '模型名称' })
            .onChange((value: string) => {
              this.viewModel.updateImportedModelName(value);
            })
            .enabled(!this.viewModel.busy)
            .height(40)
            .fontSize(12)
            .fontColor('#EAF4FF')
            .backgroundColor('#0A1623')
            .width('100%');
        }
        .width('100%');

        Column({ space: 4 }) {
          Text('短名称')
            .fontSize(12)
            .fontColor('#8CA2B8')
            .width('100%');
          TextInput({ text: this.viewModel.importedModelShortNameInput, placeholder: '短名称' })
            .onChange((value: string) => {
              this.viewModel.updateImportedModelShortName(value);
            })
            .enabled(!this.viewModel.busy)
            .height(40)
            .fontSize(12)
            .fontColor('#EAF4FF')
            .backgroundColor('#0A1623')
            .width('100%');
        }
        .width('100%');

        Column({ space: 4 }) {
          Text('系统提示词')
            .fontSize(12)
            .fontColor('#8CA2B8')
            .width('100%');
          TextInput({ text: this.viewModel.importedModelSystemPromptInput, placeholder: '系统提示词' })
            .onChange((value: string) => {
              this.viewModel.updateImportedModelSystemPrompt(value);
            })
            .enabled(!this.viewModel.busy)
            .height(44)
            .fontSize(12)
            .fontColor('#EAF4FF')
            .backgroundColor('#0A1623')
            .width('100%');
        }
        .width('100%');

        Button(this.viewModel.showAdvancedModelSettings ? '收起高级参数' : '展开高级参数')
          .enabled(!this.viewModel.busy)
          .height(38)
          .width('100%')
          .onClick(() => {
            this.viewModel.toggleAdvancedModelSettings();
          });

        if (this.viewModel.showAdvancedModelSettings) {
          this.ImportedAdvancedSettings();
        }

        Row({ space: 8 }) {
          Button('保存配置')
            .enabled(!this.viewModel.busy)
            .height(38)
            .layoutWeight(1)
            .onClick(() => {
              this.viewModel.saveImportedModelProfile();
            });
          Button('删除模型')
            .enabled(!this.viewModel.busy)
            .height(38)
            .layoutWeight(1)
            .backgroundColor('#733030')
            .onClick(() => {
              this.viewModel.requestDeleteImportedModel(this.viewModel.currentModel().id);
            });
        }
        .width('100%');
      }
      .width('100%')
      .padding(12)
      .backgroundColor('#101D2B')
      .borderRadius(8);
    }
  }

  @Builder
  private ImportedAdvancedSettings() {
    Column({ space: 8 }) {
      Column({ space: 4 }) {
        Text('对话格式')
          .fontSize(12)
          .fontColor('#8CA2B8')
          .width('100%');
        Button(this.chatFormatLabel())
          .enabled(!this.viewModel.busy)
          .height(38)
          .width('100%')
          .onClick(() => {
            this.viewModel.cycleImportedModelChatFormat();
          });
      }
      .width('100%');

    }
    .width('100%')
    .padding(10)
    .backgroundColor('#091522')
    .borderRadius(8);
  }

  @Builder
  private ModelManagementCard() {
    Column({ space: 8 }) {
      this.SectionTitle('模型管理');
      Button(this.viewModel.modelImporting ? '正在导入...' : '导入模型包')
        .enabled(!this.viewModel.busy && !this.viewModel.modelImporting)
        .height(40)
        .width('100%')
        .onClick(() => {
          this.viewModel.importModelPackage();
        });
      Text(this.viewModel.modelImportMessage)
        .fontSize(12)
        .lineHeight(18)
        .fontColor(this.viewModel.modelImportMessage.startsWith('导入失败') ? '#FF9C9C' : '#8CA2B8')
        .width('100%');
    }
    .width('100%')
    .padding(12)
    .backgroundColor('#101D2B')
    .borderRadius(8);
  }

  @Builder
  private ContextCard() {
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

  build() {
    Scroll() {
      Column({ space: 12 }) {
        this.ModelListCard();
        this.ImportedModelConfigCard();
        this.GenerationSettingsCard();
        this.RuntimeSettingsCard();
        this.ModelManagementCard();
        this.ContextCard();
      }
      .width('100%');
    }
    .layoutWeight(1)
    .width('100%')
    .scrollBar(BarState.Off);
  }
}
