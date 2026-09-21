import { dialogFade, dialogScale } from './DialogMotion'

@Component
export struct DesktopHelpDialog {
  @Prop about: boolean = false
  @Prop version: string = ''
  @Prop availableWidth: number = 600
  @Prop availableHeight: number = 640
  @State private isClosePressed: boolean = false
  onClose: () => void = () => {}

  @Builder
  private Shortcut(label: string, keys: string[]) {
    Row({ space: 12 }) {
      Text(label).fontSize(14).fontColor($r('app.color.text_title')).layoutWeight(1)
      Row({ space: 6 }) {
        ForEach(keys, (key: string) => {
          Text(key).fontSize(12).fontColor($r('app.color.text_secondary'))
            .padding({ left: 9, right: 9, top: 5, bottom: 5 })
            .backgroundColor($r('app.color.nav_idle'))
            .border({ width: 1, color: $r('app.color.border') }).borderRadius(4)
        })
      }
    }
    .width('100%').constraintSize({ minHeight: 44 })
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Column().width('100%').height('100%')
        .backgroundColor($r('app.color.scrim'))
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        .onClick(() => this.onClose())
      Column({ space: 20 }) {
        Row() {
          Text(this.about ? '关于' : '快捷键说明')
            .fontSize(20).fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_title')).layoutWeight(1)
          Button({ type: ButtonType.Normal }) {
            Image(this.isClosePressed ? $r('app.media.model_market_close_icon_pressed') :
              $r('app.media.model_market_close_icon'))
              .width(24)
              .height(24)
          }
            .width(40)
            .height(40)
            .focusable(true)
            .accessibilityText(this.about ? '关闭关于' : '关闭快捷键说明')
            .hoverEffect(HoverEffect.Auto)
            .backgroundColor(Color.Transparent)
            .onTouch((event: TouchEvent) => {
              if (event.type === TouchType.Down) {
                this.isClosePressed = true
              } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
                this.isClosePressed = false
              }
            })
            .id('desktop-help-close').onClick(() => this.onClose())
        }.width('100%')
        Scroll() {
          Column({ space: 16 }) {
            if (this.about) {
              Row({ space: 16 }) {
                Image($r('app.media.app_icon')).width(64).height(64).borderRadius(14)
                Column({ space: 6 }) {
                  Text('Turbo AI Chat').fontSize(22).fontWeight(FontWeight.Bold)
                    .fontColor($r('app.color.text_title'))
                  Text('版本 ' + this.version).fontSize(13).fontColor($r('app.color.text_secondary'))
                }.alignItems(HorizontalAlign.Start)
              }.width('100%')
              Divider().color($r('app.color.border'))
              Text('鸿蒙原生端侧 AI 聊天应用')
                .fontSize(16).fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_title')).width('100%')
              Text('基于 MNN Runtime，在本机运行大语言模型，支持文本对话与图片理解。')
                .fontSize(14).lineHeight(23).fontColor($r('app.color.text_secondary')).width('100%')
              Text('模型下载后可离线推理；图片理解能力取决于所加载的模型。')
                .fontSize(12).lineHeight(20).fontColor($r('app.color.text_muted')).width('100%')
            } else {
              Column() {
                this.Shortcut('发送消息', ['Enter'])
                this.Shortcut('输入换行', ['Shift', 'Enter'])
                this.Shortcut('新对话（聊天页）', ['Ctrl', 'N'])
                this.Shortcut('关闭弹窗或退出输入框编辑', ['Esc'])
              }.width('100%')
              Divider().color($r('app.color.border'))
              Text('输入法选词期间，Enter 用于确认候选词，不会发送消息。')
                .fontSize(12).lineHeight(20).fontColor($r('app.color.text_muted')).width('100%')
            }
          }.width('100%').alignItems(HorizontalAlign.Start)
        }.width('100%')
          .constraintSize({ maxHeight: Math.max(40, this.availableHeight - 160) })
      }
      .padding(24)
      .width(Math.max(1, Math.min(520, this.availableWidth - 32)))
      .constraintSize({ maxHeight: Math.max(1, this.availableHeight - 32) })
      .backgroundColor($r('app.color.dialog'))
      .border({ width: 1, color: $r('app.color.border') })
      .borderRadius($r('app.float.dialog_radius'))
      .transition(dialogScale())
    }.width('100%').height('100%').transition(dialogFade())
  }
}
