import { ActionButtonStyle } from './ButtonStyles'
import { ChatViewModel } from '../state/ChatViewModel'
import { formatBytes } from '../models/BuiltinModelDownloadTypes'

import { dialogFade, dialogScale } from './DialogMotion'

@Component
export struct BuiltinModelInstallDialog {
  @ObjectLink viewModel: ChatViewModel
  @Prop availableWidth: number = 360
  @Prop availableHeight: number = 640

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
        Row({ space: 10 }) {
          Image($r('app.media.app_icon'))
            .width(42)
            .height(42)
            .borderRadius(12)
          Column({ space: 2 }) {
            Text('安装模型')
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_title'))
            Text(`${this.viewModel.builtinModelInstallModelName} · ${this.viewModel.builtinModelInstallSourceName}`)
              .fontSize(12)
              .fontColor($r('app.color.dialog_subtitle'))
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')

        Scroll() {
          Column({ space: 14 }) {
            Text(this.viewModel.builtinModelInstallMessage)
              .fontSize(14)
              .lineHeight(21)
              .fontColor($r('app.color.text_secondary'))
              .width('100%')

            if (this.viewModel.builtinModelInstallError.length > 0) {
              Text(this.viewModel.builtinModelInstallError)
                .fontSize(13)
                .lineHeight(20)
                .fontColor($r('app.color.status_error'))
                .width('100%')
            }

            if (this.viewModel.builtinModelInstallProgress <= 0) {
              Row()
                .width('100%')
                .height(8)
                .backgroundColor($r('app.color.control_track'))
                .borderRadius(4)
            } else {
              Progress({ value: this.viewModel.builtinModelInstallProgress, total: 100, type: ProgressType.Linear })
                .width('100%')
                .height(8)
                .color($r('app.color.status_good'))
                .style({ strokeWidth: 8, strokeRadius: 4, enableScanEffect: this.viewModel.builtinModelInstalling })
            }

            Row() {
              Text(`${Math.round(this.viewModel.builtinModelInstallProgress)}%`)
                .fontSize(12)
                .fontColor($r('app.color.text_muted'))
                .layoutWeight(1)
              Text(`${formatBytes(this.viewModel.builtinModelInstallDownloadedBytes)} / ${formatBytes(this.viewModel.builtinModelInstallTotalBytes)}`)
                .fontSize(12)
                .fontColor($r('app.color.text_muted'))
            }
            .width('100%')

          }
          .width('100%')
        }
        .width('100%')
        .constraintSize({ maxHeight: Math.max(40, this.availableHeight - 220) })
        .scrollBar(BarState.Auto)

        Row({ space: 10 }) {
          Button(this.viewModel.builtinModelInstalling ? '停止下载' : (this.viewModel.builtinModelInstallCanceled ? '关闭' : '稍后'))
            .attributeModifier(new ActionButtonStyle($r('app.color.button_secondary_background'), $r('app.color.button_secondary_text')))
            .layoutWeight(1)
            .onClick(() => {
              if (this.viewModel.builtinModelInstalling) {
                this.viewModel.cancelBuiltinModelInstall()
                return
              }
              this.viewModel.closeBuiltinModelInstallDialog()
            })

          Button(this.viewModel.builtinModelInstalling ? '下载中...' : (this.viewModel.builtinModelInstallCanceled ? '继续下载' : '下载并安装'))
            .attributeModifier(new ActionButtonStyle($r('app.color.button_primary_background'), $r('app.color.button_primary_text')))
            .layoutWeight(1)
            .enabled(!this.viewModel.builtinModelInstalling)
            .onClick(() => {
              this.viewModel.startBuiltinModelInstall()
            })
        }
        .width('100%')
      }
      .width(Math.max(1, Math.min(560, this.availableWidth - 32)))
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
