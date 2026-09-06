@Component
export struct AppHeader {
  @Prop status: string = ''
  @Prop loaded: boolean = false
  @Prop busy: boolean = false
  @Prop renderVersion: number = 0
  @Prop showNewChat: boolean = true
  @Prop actionLabel: string = ''
  @Prop compact: boolean = false
  onSettings: () => void = () => {}
  onNewChat: () => void = () => {}
  onAction: () => void = () => {}

  build() {
    Row({ space: 10 }) {
      if (this.compact) {
        Button({ type: ButtonType.Normal }) {
          Image($r('app.media.app_icon'))
            .width(38)
            .height(38)
            .borderRadius(10)
        }
        .width(38)
        .height(38)
        .padding(0)
        .backgroundColor(Color.Transparent)
        .accessibilityText('打开应用菜单')
        .bindMenu([{ value: '设置', action: () => this.onSettings() }])
      } else {
        Image($r('app.media.app_icon'))
          .width(38)
          .height(38)
          .borderRadius(10)
      }
      Column({ space: 2 }) {
        Text('Turbo AI Chat')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_title'))
        Marquee({
          start: true,
          step: 4,
          loop: -1,
          fromStart: true,
          src: this.status
        })
          .fontSize(12)
          .fontColor(this.busy ? $r('app.color.status_warning') : (this.loaded ? $r('app.color.status_good') : $r('app.color.text_muted')))
          .width('100%')
          .height(18)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

        Button(this.showNewChat ? '新对话' : this.actionLabel)
          .visibility(this.showNewChat || this.actionLabel.length > 0 ? Visibility.Visible : Visibility.Hidden)
          .enabled(!this.busy)
          .height(40)
          .width(78)
          .fontSize(this.showNewChat ? $r('app.float.button_font_size') : 15)
          .fontWeight(this.showNewChat ? FontWeight.Medium : FontWeight.Normal)
          .fontColor(this.showNewChat ? $r('app.color.button_secondary_text') : $r('app.color.tag_green_text'))
          .backgroundColor(this.showNewChat ? $r('app.color.button_secondary_background') : $r('app.color.gallery_entry_background'))
          .borderRadius(this.showNewChat ? $r('app.float.button_radius') : 8)
          .padding(0)
          .margin({ right: 4 })
          .onClick(() => {
            if (this.showNewChat) {
              this.onNewChat()
              return
            }
            this.onAction()
          })
    }
    .width('100%')
    .height(50)
  }
}
