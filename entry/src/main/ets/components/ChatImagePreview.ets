import fileUri from '@ohos.file.fileuri'
import { KeyCode } from '@kit.InputKit'

@Component
export struct ChatImagePreview {
  @Prop uri: string = ''
  @Prop topInset: number = 0
  @Prop bottomInset: number = 0
  onClose: () => void = () => {}
  @State private zoom: number = 1
  @State private offsetX: number = 0
  @State private offsetY: number = 0
  @State private viewportWidth: number = 0
  @State private viewportHeight: number = 0
  @State private imageWidth: number = 0
  @State private imageHeight: number = 0
  @State private failed: boolean = false
  private pinchStart: number = 1
  private panStartX: number = 0
  private panStartY: number = 0

  private constrainOffset(): void {
    if (this.imageWidth <= 0 || this.imageHeight <= 0) return
    const fit = Math.min(this.viewportWidth / this.imageWidth, this.viewportHeight / this.imageHeight)
    const limitX = Math.max(0, (this.imageWidth * fit * this.zoom - this.viewportWidth) / 2)
    const limitY = Math.max(0, (this.imageHeight * fit * this.zoom - this.viewportHeight) / 2)
    this.offsetX = Math.max(-limitX, Math.min(limitX, this.offsetX))
    this.offsetY = Math.max(-limitY, Math.min(limitY, this.offsetY))
  }

  private setZoom(value: number): void {
    this.zoom = Math.max(1, Math.min(5, value))
    this.constrainOffset()
  }

  build() {
    Stack() {
      Stack() {
        if (this.failed) {
          Text('图片暂时无法打开').fontSize(14).fontColor($r('app.color.text_secondary'))
        } else {
          Image(this.uri.startsWith('/') ? fileUri.getUriFromPath(this.uri) : this.uri).width('100%').height('100%').objectFit(ImageFit.Contain)
            .scale({ x: this.zoom, y: this.zoom })
            .translate({ x: this.offsetX, y: this.offsetY })
            .accessibilityText('图片预览，双指缩放，放大后可拖动')
            .onComplete((event) => {
              if (event) {
                this.imageWidth = event.width
                this.imageHeight = event.height
                this.constrainOffset()
              }
            })
            .onError(() => { this.failed = true })
        }
      }.width('100%').height('100%').clip(true).id('image-preview-canvas')
        .onAreaChange((_old: Area, area: Area) => {
          this.viewportWidth = Number(area.width)
          this.viewportHeight = Number(area.height)
          this.constrainOffset()
        })
        .gesture(GestureGroup(GestureMode.Exclusive,
          TapGesture({ count: 2 }).onAction(() => this.setZoom(this.zoom > 1 ? 1 : 2)),
          GestureGroup(GestureMode.Parallel,
            PinchGesture({ fingers: 2 })
              .onActionStart(() => { this.pinchStart = this.zoom })
              .onActionUpdate((event: GestureEvent) => this.setZoom(this.pinchStart * event.scale)),
            PanGesture({ fingers: 1, distance: 4 })
              .onActionStart(() => {
                this.panStartX = this.offsetX
                this.panStartY = this.offsetY
              })
              .onActionUpdate((event: GestureEvent) => {
                this.offsetX = this.panStartX + event.offsetX
                this.offsetY = this.panStartY + event.offsetY
                this.constrainOffset()
              })
          )
        ))
        .onAxisEvent((event: AxisEvent) => {
          if (event.getVerticalAxisValue() !== 0) {
            this.setZoom(this.zoom * (event.getVerticalAxisValue() > 0 ? 0.9 : 1.1))
          }
        })
      Column() {
        Row() {
          Blank()
          Button({ type: ButtonType.Circle }) {
            SymbolGlyph($r('sys.symbol.xmark')).fontSize(18).fontColor([Color.White])
          }.width(40).height(40).backgroundColor($r('app.color.scrim'))
            .accessibilityText('关闭图片预览').id('image-preview-close')
            .onClick(() => this.onClose())
        }.width('100%')
        Blank()
        Row() {
          Blank()
          Text(`${Math.round(this.zoom * 100)}%`)
            .fontSize(12).fontColor(Color.White).padding({ left: 8, right: 8, top: 4, bottom: 4 })
            .backgroundColor($r('app.color.scrim')).borderRadius(6).id('image-preview-zoom')
            .hitTestBehavior(HitTestMode.None)
        }.width('100%')
      }.width('100%').height('100%').padding(12).hitTestBehavior(HitTestMode.Transparent)
    }.width('100%').height('100%').padding({ top: this.topInset, bottom: this.bottomInset })
      .backgroundColor($r('app.color.page'))
      .focusable(true).id('image-preview')
      .onAppear(() => { this.getUIContext().getFocusController().requestFocus('image-preview') })
      .onKeyEvent((event: KeyEvent): boolean => {
        if (event.type === KeyType.Down && event.keyCode === KeyCode.KEYCODE_ESCAPE) {
          this.onClose()
          return true
        }
        return false
      })
  }
}
