import { ThemeMode, themeService } from '../services/ThemeService'
import { ActionButtonStyle } from './ButtonStyles'
import { ChatViewModel } from '../state/ChatViewModel'

import { dialogFade, dialogScale } from './DialogMotion'

@Component
export struct SettingsDialog {
  @ObjectLink viewModel: ChatViewModel
  @StorageLink('themeMode') private themeMode: ThemeMode = 'system'
  @Prop availableWidth: number = 360
  @Prop availableHeight: number = 640
  @State private isClosePressed: boolean = false
  onClose: () => void = () => {}

  aboutToDisappear(): void {
    this.viewModel.cancelChatRestore()
  }

  @Builder
  private ThemeButton(label: string, mode: ThemeMode, icon: Resource) {
    Button() {
      Row({ space: 6 }) {
        Image(icon)
          .width(18)
          .height(18)
          .fillColor(this.themeMode === mode ? $r('app.color.nav_active_text') : $r('app.color.text_secondary'))
        Text(label)
          .fontSize(12)
          .fontWeight(this.themeMode === mode ? FontWeight.Medium : FontWeight.Normal)
          .fontColor(this.themeMode === mode ? $r('app.color.nav_active_text') : $r('app.color.text_secondary'))
      }
      .justifyContent(FlexAlign.Center)
    }
      .attributeModifier(new ActionButtonStyle(
        this.themeMode === mode ? $r('app.color.selected_background') : $r('app.color.nav_idle'),
        this.themeMode === mode ? $r('app.color.nav_active_text') : $r('app.color.text_secondary')))
      .padding({ left: 4, right: 4 })
      .accessibilityText(label)
      .layoutWeight(1)
      .onClick(() => themeService.select(mode))
  }


  build() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.scrim'))
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        .onClick(() => this.onClose())

      Column({ space: 18 }) {
        Row() {
          Text('设置')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_title'))
            .layoutWeight(1)
          Button({ type: ButtonType.Normal }) {
            Image(this.isClosePressed ? $r('app.media.model_market_close_icon_pressed') :
              $r('app.media.model_market_close_icon'))
              .width(24)
              .height(24)
          }
            .width(40)
            .height(40)
            .focusable(true)
            .accessibilityText('关闭设置')
            .hoverEffect(HoverEffect.Auto)
            .backgroundColor(Color.Transparent)
            .onTouch((event: TouchEvent) => {
              if (event.type === TouchType.Down) {
                this.isClosePressed = true
              } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
                this.isClosePressed = false
              }
            })
            .onClick(() => this.onClose())
        }
        .width('100%')
        Scroll() {
          Column({ space: 12 }) {
            Text('外观')
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_title'))
              .width('100%')
            Text('外观切换后立即生效').fontSize(11).fontColor($r('app.color.text_model_hint')).width('100%')
            Row({ space: 6 }) {
              this.ThemeButton('浅色模式', 'light', $r('app.media.theme_day'))
              this.ThemeButton('深色模式', 'dark', $r('app.media.theme_night'))
              this.ThemeButton('跟随系统', 'system', $r('app.media.theme_system'))
            }
            .width('100%')
            Row({ space: 12 }) {
              Text('排查记录')
                .fontSize(16)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.text_title'))
                .layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: this.viewModel.diagnosticLoggingEnabled })
                .height(22)
                .selectedColor($r('app.color.status_good'))
                .onChange((enabled: boolean) => this.viewModel.setDiagnosticLogging(enabled))
            }
            .width('100%').margin({ top: 12 })
            Text('仅在排查问题时开启。记录最近一次文字对话的输入、回答和参数，保存在本机。关闭、重启或删除对话时会清除。')
              .fontSize(11)
              .fontColor($r('app.color.text_model_hint'))
              .width('100%')
            Button('清除并关闭记录')
              .attributeModifier(new ActionButtonStyle($r('app.color.button_secondary_background'), $r('app.color.button_secondary_text')))
              .width('100%').onClick(() => this.viewModel.setDiagnosticLogging(false))
            Text('对话数据').fontSize(16).fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_title')).width('100%').margin({ top: 12 })
            Text('备份包含对话、图片和回答版本。恢复后添加为独立对话。')
              .fontSize(11).fontColor($r('app.color.text_model_hint')).width('100%')
            if (this.viewModel.restoreConversationCount > 0) {
              Text(`备份中有 ${this.viewModel.restoreConversationCount} 条对话，是否恢复？`)
                .fontSize(14).fontColor($r('app.color.text_body')).width('100%')
              Row({ space: 10 }) {
                Button('取消', { type: ButtonType.Normal })
                  .attributeModifier(new ActionButtonStyle($r('app.color.button_secondary_background'), $r('app.color.button_secondary_text')))
                  .layoutWeight(1).enabled(!this.viewModel.historyBusy)
                  .onClick(() => this.viewModel.cancelChatRestore())
                Button('恢复', { type: ButtonType.Normal })
                  .attributeModifier(new ActionButtonStyle($r('app.color.button_primary_background'), $r('app.color.button_primary_text')))
                  .layoutWeight(1).enabled(this.viewModel.canManageConversations())
                  .onClick(() => this.viewModel.confirmChatRestore())
              }.width('100%')
            } else {
              Row({ space: 10 }) {
                Button('保存备份', { type: ButtonType.Normal })
                  .attributeModifier(new ActionButtonStyle($r('app.color.button_secondary_background'), $r('app.color.button_secondary_text')))
                  .layoutWeight(1).enabled(this.viewModel.canManageConversations() && this.viewModel.conversations.length > 0)
                  .onClick(() => this.viewModel.exportChatData(true))
                Button('恢复备份', { type: ButtonType.Normal })
                  .attributeModifier(new ActionButtonStyle($r('app.color.button_secondary_background'), $r('app.color.button_secondary_text')))
                  .layoutWeight(1).enabled(this.viewModel.canManageConversations())
                  .onClick(() => this.viewModel.chooseChatBackup())
              }.width('100%')
            }
            if (this.viewModel.historyBusy) {
              Text('正在处理对话数据…').fontSize(11).fontColor($r('app.color.text_model_hint')).width('100%')
            }
          }
          .width('100%')
          .animation({ duration: 220, curve: Curve.EaseInOut })
        }
        .width('100%')
        .constraintSize({ maxHeight: Math.max(40, this.availableHeight - 140) })
      }
      .padding(18)
      .width(Math.max(1, Math.min(480, this.availableWidth - 32)))
      .constraintSize({ maxHeight: Math.max(1, this.availableHeight - 32) })
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
