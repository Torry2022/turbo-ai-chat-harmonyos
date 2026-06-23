import { ChatViewModel } from '../state/ChatViewModel'

@Component
export struct ModelLoadDialog {
  @ObjectLink viewModel: ChatViewModel

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
        Row({ space: 10 }) {
          Image($r('app.media.app_icon'))
            .width(42)
            .height(42)
            .borderRadius(12)
          Column({ space: 2 }) {
            Text('加载本地模型')
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .fontColor('#F4FBFF')
            Text(`${this.viewModel.currentModel().shortName} · MNN`)
              .fontSize(12)
              .fontColor('#8DE4C3')
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')

        Text(this.viewModel.modelLoadMessage)
          .fontSize(14)
          .lineHeight(21)
          .fontColor('#B7CDE1')
          .width('100%')

        if (this.viewModel.modelLoadProgress <= 0) {
          Row()
            .width('100%')
            .height(8)
            .backgroundColor('#26384D')
            .borderRadius(4)
        } else {
          Progress({ value: this.viewModel.modelLoadProgress, total: 100, type: ProgressType.Linear })
            .width('100%')
            .height(8)
            .color('#45D6A4')
            .style({ strokeWidth: 8, strokeRadius: 4, enableScanEffect: this.viewModel.modelLoading })
        }

        Row() {
          Text(`${Math.round(this.viewModel.modelLoadProgress)}%`)
            .fontSize(12)
            .fontColor('#8CA2B8')
            .layoutWeight(1)
          Text(this.viewModel.modelLoading ? '加载中' : (this.viewModel.loaded ? '已完成' : '等待操作'))
            .fontSize(12)
            .fontColor(this.viewModel.loaded ? '#45D6A4' : '#F2B35D')
        }
        .width('100%')

        if (!this.viewModel.modelLoading && !this.viewModel.loaded) {
          Row({ space: 10 }) {
            Button('关闭')
              .height(38)
              .layoutWeight(1)
              .fontColor('#F4FBFF')
              .backgroundColor('#26384D')
              .onClick(() => {
                this.viewModel.closeModelLoadDialog()
              })
            Button('加载模型')
              .height(38)
              .layoutWeight(1)
              .onClick(() => {
                this.viewModel.loadModel()
              })
          }
          .width('100%')
        }
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
