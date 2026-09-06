@Component
export struct LaunchScreen {
  build() {
    Stack() {
      Image($r('app.media.launch_art'))
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Cover)
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      Column({ space: 12 }) {
        Image($r('app.media.app_icon'))
          .width(92)
          .height(92)
          .borderRadius(24)
        Text('Turbo AI Chat')
          .fontSize(28)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.launch_text'))
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.start_window_background'))
  }
}
