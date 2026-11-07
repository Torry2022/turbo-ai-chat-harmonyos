@Component
export struct LaunchScreen {
  @State private canvasWidth: number = 0
  @State private canvasHeight: number = 0
  onReadyToExit: () => void = () => {}
  @State private artReady: boolean = false
  @State private artOpacity: number = 0.28
  private animationStarted: boolean = false
  private holdTimer: number = -1

  private landscape(): boolean {
    return this.canvasHeight > 0 && this.canvasWidth > this.canvasHeight
  }

  private startAnimation(): void {
    if (this.animationStarted) return
    this.animationStarted = true
    this.getUIContext().animateTo({
      duration: 450,
      curve: Curve.Linear,
      onFinish: () => {
        this.holdTimer = setTimeout(() => {
          this.holdTimer = -1
          this.onReadyToExit()
        }, 100)
      }
    }, () => {
      this.artOpacity = 1
    })
  }

  aboutToDisappear(): void {
    if (this.holdTimer !== -1) {
      clearTimeout(this.holdTimer)
      this.holdTimer = -1
    }
  }

  build() {
    Stack() {
      if (this.canvasWidth > 0 && this.canvasHeight > 0) {
        Stack() {
          Image(this.landscape() ? $r('app.media.launch_art_landscape') : $r('app.media.launch_art'))
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Cover)
            .scale({ x: this.landscape() ? 1 : 1.04, y: this.landscape() ? 1 : 1.04 })
            .translate({ y: this.landscape() ? 0 : '-2%' })
            .opacity(this.artOpacity)
            .onComplete((event) => {
              if (event?.loadingStatus === 1) {
                this.artReady = true
                this.startAnimation()
              }
            })
            .onError(() => this.onReadyToExit())
          Column({ space: 12 }) {
            Image($r('app.media.app_icon'))
              .syncLoad(true)
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
          .translate({ y: '-2%' })
        }
        .width('100%')
        .height('100%')
        .opacity(this.artReady ? 1 : 0)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Black)
    .clip(true)
    .blendMode(BlendMode.SRC_OVER, BlendApplyType.OFFSCREEN)
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      this.canvasWidth = Number(newArea.width)
      this.canvasHeight = Number(newArea.height)
    })
  }
}
