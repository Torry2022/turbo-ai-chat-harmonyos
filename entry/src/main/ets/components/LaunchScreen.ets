@Component
export struct LaunchScreen {
  build() {
    Stack() {
      Image($r('app.media.launch_art'))
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Cover);
      Column({ space: 12 }) {
        Image($r('app.media.app_icon'))
          .width(92)
          .height(92)
          .borderRadius(24);
        Text('Turbo AI Chat')
          .fontSize(28)
          .fontWeight(FontWeight.Bold)
          .fontColor('#F4FBFF');
        Text('本地智能对话')
          .fontSize(15)
          .fontColor('#9FBDD5');
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center);
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#06121F')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM]);
  }
}
