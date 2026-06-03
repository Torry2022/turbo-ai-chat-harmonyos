import { CONTEXT_MESSAGE_LIMIT } from '../models/ChatTypes';
import { CHAT_FORMAT_MNN_AUTO, ModelProfile } from '../models/ModelProfile';
import { ChatViewModel } from '../state/ChatViewModel';

@Component
export struct ModelTab {
  @ObjectLink viewModel: ChatViewModel;

  @Builder
  private ModelOption(profile: ModelProfile) {
    Column({ space: 4 }) {
      Row() {
        Text(profile.name)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.viewModel.selectedModelId === profile.id ? '#F4FBFF' : '#B7CDE1')
          .layoutWeight(1);
        if (profile.source === 'imported') {
          Text('导入')
            .fontSize(10)
            .fontColor('#45D6A4')
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .backgroundColor('#12372E')
            .borderRadius(4);
        }
        Text(profile.supportsImage ? '文本 + 图片' : '仅文本')
          .fontSize(11)
          .fontColor(profile.supportsImage ? '#8DE4C3' : '#F2B35D');
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

  build() {
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
            ForEach(this.viewModel.modelProfiles(), (profile: ModelProfile) => {
              this.ModelOption(profile);
            }, (profile: ModelProfile) => profile.id);
          }
          .width('100%');

          Column({ space: 8 }) {
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
          .padding(10)
          .backgroundColor('#091522')
          .borderRadius(8);

          if (this.viewModel.currentModel().source === 'imported') {
            Column({ space: 8 }) {
              Text('导入模型配置')
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
                .fontColor('#F4FBFF')
                .width('100%');

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
                  .height(40)
                  .fontSize(12)
                  .fontColor('#EAF4FF')
                  .backgroundColor('#0A1623')
                  .width('100%');
              }
              .width('100%');

              Column({ space: 4 }) {
                Text('模板类型')
                  .fontSize(12)
                  .fontColor('#8CA2B8')
                  .width('100%');
                Button(this.viewModel.importedModelChatFormatInput.length > 0 ?
                  this.viewModel.importedModelChatFormatInput :
                  CHAT_FORMAT_MNN_AUTO)
                  .enabled(!this.viewModel.busy)
                  .height(38)
                  .width('100%')
                  .onClick(() => {
                    this.viewModel.cycleImportedModelChatFormat();
                  });
              }
              .width('100%');

              Column({ space: 4 }) {
                Text('Prompt 模板（%s 为对话内容）')
                  .fontSize(12)
                  .fontColor('#8CA2B8')
                  .width('100%');
                TextInput({ text: this.viewModel.importedModelPromptTemplateInput, placeholder: '留空则使用 MNN 默认模板' })
                  .onChange((value: string) => {
                    this.viewModel.updateImportedModelPromptTemplate(value);
                  })
                  .enabled(!this.viewModel.busy)
                  .height(54)
                  .fontSize(11)
                  .fontColor('#EAF4FF')
                  .backgroundColor('#0A1623')
                  .width('100%');
              }
              .width('100%');

              Column({ space: 4 }) {
                Text('停止符')
                  .fontSize(12)
                  .fontColor('#8CA2B8')
                  .width('100%');
                TextInput({ text: this.viewModel.importedModelStopSequenceInput, placeholder: '例如 <|im_end|>' })
                  .onChange((value: string) => {
                    this.viewModel.updateImportedModelStopSequence(value);
                  })
                  .enabled(!this.viewModel.busy)
                  .height(40)
                  .fontSize(12)
                  .fontColor('#EAF4FF')
                  .backgroundColor('#0A1623')
                  .width('100%');
              }
              .width('100%');

              Row({ space: 8 }) {
                Button(this.viewModel.importedModelSupportsImage ? '图片输入：开' : '图片输入：关')
                  .enabled(!this.viewModel.busy)
                  .height(38)
                  .layoutWeight(1)
                  .onClick(() => {
                    this.viewModel.updateImportedModelSupportsImage(!this.viewModel.importedModelSupportsImage);
                  });
                Button('保存配置')
                  .enabled(!this.viewModel.busy)
                  .height(38)
                  .layoutWeight(1)
                  .onClick(() => {
                    this.viewModel.saveImportedModelProfile();
                  });
              }
              .width('100%');

              Button('删除该导入模型')
                .enabled(!this.viewModel.busy)
                .height(38)
                .width('100%')
                .backgroundColor('#733030')
                .onClick(() => {
                  this.viewModel.requestDeleteImportedModel(this.viewModel.currentModel().id);
                });
            }
            .width('100%')
            .padding(10)
            .backgroundColor('#101D2B')
            .borderRadius(8);
          }

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

          Text(`当前模型：${this.viewModel.currentModel().name} · ${this.viewModel.currentModel().supportsImage ? '支持图片输入' : '仅支持文本输入'}`)
            .fontSize(12)
            .fontColor('#8CA2B8')
            .width('100%');

          Row({ space: 8 }) {
            Button(this.viewModel.loaded ? '重新加载模型' : '加载模型')
              .enabled(!this.viewModel.busy)
              .height(40)
              .layoutWeight(1)
              .onClick(() => {
                this.viewModel.loadModel();
              });

            Button(`输出 ${this.viewModel.maxNewTokens}/${this.viewModel.maxGenerationTokens}`)
              .enabled(false)
              .height(40);
          }

          Column({ space: 4 }) {
            Text(`最大输出 ${this.viewModel.maxNewTokens} tokens`)
              .fontSize(12)
              .fontColor('#8CA2B8');
            Slider({ value: this.viewModel.maxNewTokens, min: 16, max: this.viewModel.maxGenerationTokens, step: 16 })
              .onChange((value: number) => {
                this.viewModel.updateMaxNewTokens(value);
              });
          }
          .width('100%');

          Column({ space: 4 }) {
            Text(`推理线程 ${this.viewModel.threadNum}`)
              .fontSize(12)
              .fontColor('#8CA2B8');
            Slider({ value: this.viewModel.threadNum, min: 2, max: 8, step: 1 })
              .onChange((value: number) => {
                this.viewModel.updateThreadNum(value);
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
}
