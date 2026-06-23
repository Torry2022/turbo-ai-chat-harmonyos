@Component
export struct AppHeader {
  @Prop status: string = ''
  @Prop loaded: boolean = false
  @Prop busy: boolean = false
  @Prop showNewChat: boolean = true
  @Prop actionLabel: string = ''
  onNewChat: () => void = () => {}
  onAction: () => void = () => {}

  build() {
    Row({ space: 10 }) {
      Image($r('app.media.app_icon'))
        .width(38)
        .height(38)
        .borderRadius(10)
      Column({ space: 2 }) {
        Text('Turbo AI Chat')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor('#F4FBFF')
        Marquee({
          start: true,
          step: 4,
          loop: -1,
          fromStart: true,
          src: this.status
        })
          .fontSize(12)
          .fontColor(this.busy ? '#F2B35D' : (this.loaded ? '#45D6A4' : '#8CA2B8'))
          .width('100%')
          .height(18)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      if (this.showNewChat || this.actionLabel.length > 0) {
        Button(this.showNewChat ? '新对话' : this.actionLabel)
          .enabled(!this.busy)
          .height(40)
          .width(78)
          .fontSize(this.showNewChat ? 16 : 15)
          .fontColor(this.showNewChat ? '#F4FBFF' : '#8DE4C3')
          .backgroundColor(this.showNewChat ? '#26384D' : '#12372E')
          .borderRadius(8)
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
    }
    .width('100%')
    .height(50)
  }
}
