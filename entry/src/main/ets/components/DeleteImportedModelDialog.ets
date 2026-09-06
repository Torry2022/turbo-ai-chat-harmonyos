import { ActionButtonStyle } from './ButtonStyles'
import { ChatViewModel } from '../state/ChatViewModel'

import { dialogFade, dialogScale } from './DialogMotion'

@Component
export struct DeleteModelDialog {
  @ObjectLink viewModel: ChatViewModel
  @Prop availableWidth: number = 360
  @Prop availableHeight: number = 640

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
        .focusable(false)
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.scrim'))
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        .onClick(() => {
          this.viewModel.dismissTopDialogIfIdle()
        })

      Column({ space: 14 }) {
        Text(`删除 ${this.modelName()}`)
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_title'))
          .width('100%')

        Scroll() {
          Column({ space: 14 }) {
            Text(this.description())
              .fontSize(14)
              .lineHeight(21)
              .fontColor($r('app.color.text_secondary'))
              .width('100%')

          }
          .width('100%')
        }
        .width('100%')
        .constraintSize({ maxHeight: Math.max(40, this.availableHeight - 220) })
        .scrollBar(BarState.Auto)

        Row({ space: 10 }) {
          Button('取消')
            .attributeModifier(new ActionButtonStyle($r('app.color.button_secondary_background'), $r('app.color.button_secondary_text')))
            .layoutWeight(1)
            .onClick(() => {
              this.viewModel.cancelDeleteModel()
            })
          Button('确认')
            .attributeModifier(new ActionButtonStyle($r('app.color.button_destructive_background'), $r('app.color.button_destructive_text')))
            .layoutWeight(1)
            .onClick(() => {
              this.viewModel.confirmDeleteModel()
            })
        }
        .width('100%')
      }
      .width(Math.max(1, Math.min(480, this.availableWidth - 32)))
      .constraintSize({ maxHeight: Math.max(1, this.availableHeight - 32) })
      .padding(18)
      .backgroundColor($r('app.color.dialog'))
      .border({ width: 1, color: $r('app.color.border') })
      .borderRadius($r('app.float.dialog_radius'))
      .transition(dialogScale())
    }
    .width('100%')
    .height('100%')
    .transition(dialogFade())
  }
}
