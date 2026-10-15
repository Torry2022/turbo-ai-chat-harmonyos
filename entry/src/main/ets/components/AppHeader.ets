@Component
export struct AppHeader {
  @Prop status: string = ''
  @Prop statusColor: ResourceColor = $r('app.color.text_muted')
  @Prop newChatEnabled: boolean = true
  @Prop busy: boolean = false
  @Prop renderVersion: number = 0
  @Prop showNewChat: boolean = true
  @Prop actionLabel: string = ''
  @Prop compact: boolean = false
  onSettings: () => void = () => {}
  onNewChat: () => void = () => {}
  onAction: () => void = () => {}

  @Builder
  private SettingsMenu() {
    Menu() {
      MenuItem() {
        Row({ space: 10 }) {
          SymbolGlyph($r('sys.symbol.gearshape'))
            .fontSize(20)
            .fontColor([$r('app.color.text_secondary')])
          Text('设置')
            .fontSize(14)
            .fontColor($r('app.color.text_title'))
        }
        .height(40)
        .width('100%')
        .padding({ left: 10, right: 10 })
      }
      .onClick(() => this.onSettings())
    }
    .width(156)
    .borderRadius($r('app.float.button_radius'))
    .backgroundColor($r('app.color.dialog'))
  }

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
        .bindMenu(this.SettingsMenu, {
          backgroundColor: $r('app.color.dialog'),
          backgroundBlurStyle: BlurStyle.NONE,
          borderRadius: $r('app.float.button_radius')
        })
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
        Text(this.status)
          .fontSize(12)
          .fontColor(this.statusColor)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .height(18)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

        Button(this.showNewChat ? '新对话' : this.actionLabel)
          .visibility(this.showNewChat || this.actionLabel.length > 0 ? Visibility.Visible : Visibility.Hidden)
          .enabled(this.showNewChat ? this.newChatEnabled : !this.busy)
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
