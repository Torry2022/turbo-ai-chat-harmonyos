@Component
export struct AppHeader {
  @Prop status: string = ''
  @Prop loaded: boolean = false
  @Prop busy: boolean = false
  onNewChat: () => void = () => {}

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

      Button('新对话')
        .enabled(!this.busy)
        .height(32)
        .fontSize(15)
        .backgroundColor('#14344A')
        .borderRadius(8)
        .padding({ left: 14, right: 14 })
        .onClick(() => {
          this.onNewChat()
        })
    }
    .width('100%')
    .height(50)
  }
}
