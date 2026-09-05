@Component
export struct LaunchScreen {
  build() {
    Stack() {
      Image($r('app.media.launch_art'))
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Cover)
      Column({ space: 12 }) {
        Image($r('app.media.app_icon'))
          .width(92)
          .height(92)
          .borderRadius(24)
        Text('Turbo AI Chat')
          .fontSize(28)
          .fontWeight(FontWeight.Bold)
          .fontColor('#F4FBFF')
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#06121F')
  }
}
