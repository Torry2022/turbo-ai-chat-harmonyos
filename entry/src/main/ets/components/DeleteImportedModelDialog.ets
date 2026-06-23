import { ChatViewModel } from '../state/ChatViewModel'

@Component
export struct DeleteModelDialog {
  @ObjectLink viewModel: ChatViewModel

  private modelName(): string {
    const model = this.viewModel.pendingDeleteModel()
    return model === undefined ? '模型' : model.shortName
  }

  private description(): string {
    const model = this.viewModel.pendingDeleteModel()
    if (model !== undefined && model.source === 'builtin') {
      return '删除后会清理该内置模型在 App 沙箱中的文件，模型条目仍会保留，可在需要时重新下载安装。当前对话不会被删除。'
    }
    return '删除后会移除该导入模型条目和 App 沙箱中的文件，当前对话不会被删除。'
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#00000099')
        .onClick(() => {
          this.viewModel.dismissTopDialogIfIdle()
        })

      Column({ space: 14 }) {
        Text(`删除 ${this.modelName()}`)
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor('#F4FBFF')
          .width('100%')

        Text(this.description())
          .fontSize(14)
          .lineHeight(21)
          .fontColor('#B7CDE1')
          .width('100%')

        Row({ space: 10 }) {
          Button('取消')
            .height(38)
            .layoutWeight(1)
            .fontColor('#F4FBFF')
            .backgroundColor('#26384D')
            .onClick(() => {
              this.viewModel.cancelDeleteModel()
            })
          Button('确认')
            .height(38)
            .layoutWeight(1)
            .backgroundColor('#B43B3B')
            .onClick(() => {
              this.viewModel.confirmDeleteModel()
            })
        }
        .width('100%')
      }
      .width('90%')
      .padding(18)
      .backgroundColor('#102235')
      .border({ width: 1, color: '#23445F' })
      .borderRadius(10)
    }
    .width('100%')
    .height('100%')
  }
}
