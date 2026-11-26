import { ChatViewModel } from '../state/ChatViewModel'

export const DOWNLOAD_TASK_BUTTON_SIZE: number = 46
export const DOWNLOAD_TASK_BUTTON_MARGIN: number = 12
export interface DownloadTaskPoint {
  x: number
  y: number
}

export function downloadTaskDockX(width: number, right: boolean): number {
  return right ? Math.max(0, width - DOWNLOAD_TASK_BUTTON_SIZE - DOWNLOAD_TASK_BUTTON_MARGIN) :
    DOWNLOAD_TASK_BUTTON_MARGIN
}

export function clampDownloadTaskTop(top: number, height: number, topInset: number, bottomInset: number): number {
  const minimum = topInset + DOWNLOAD_TASK_BUTTON_MARGIN
  const maximum = Math.max(minimum, height - bottomInset - DOWNLOAD_TASK_BUTTON_SIZE - DOWNLOAD_TASK_BUTTON_MARGIN)
  return Math.min(maximum, Math.max(minimum, top))
}

@Component
export struct DownloadTaskButton {
  @ObjectLink viewModel: ChatViewModel
  @Prop availableWidth: number = 0
  @Prop availableHeight: number = 0
  @Prop topInset: number = 0
  @Prop bottomInset: number = 0
  @Link dockRight: boolean
  @Link dockTop: number
  onOpen: () => void = () => {}
  @State private dragging: boolean = false
  @State private pressed: boolean = false
  @State private dragX: number = 0
  @State private dragY: number = 0
  private dragStartX: number = 0
  private dragStartY: number = 0

  private dockX(): number {
    return downloadTaskDockX(this.availableWidth, this.dockRight)
  }

  private clampY(top: number): number {
    return clampDownloadTaskTop(top, this.availableHeight, this.topInset, this.bottomInset)
  }

  private dockY(): number {
    return this.clampY(this.dockTop >= 0 ? this.dockTop : this.availableHeight)
  }

  private settleDrag(): void {
    if (!this.dragging) return
    this.getUIContext().animateTo({ duration: 200, curve: Curve.EaseOut }, () => {
      this.dockRight = this.dragX + DOWNLOAD_TASK_BUTTON_SIZE / 2 >= this.availableWidth / 2
      this.dockTop = this.dragY
      this.dragging = false
    })
  }

  private setPressed(pressed: boolean): void {
    if (this.pressed === pressed) return
    this.getUIContext().animateTo({ duration: pressed ? 75 : 115, curve: Curve.EaseOut }, () => {
      this.pressed = pressed
    })
  }

  build() {
    Button({ type: ButtonType.Circle }) {
      Stack({ alignContent: Alignment.Center }) {
        Progress({ value: this.viewModel.builtinModelInstallProgress, total: 100, type: ProgressType.Ring })
          .width(DOWNLOAD_TASK_BUTTON_SIZE).height(DOWNLOAD_TASK_BUTTON_SIZE)
          .color(this.viewModel.builtinModelInstalling ?
            $r('app.color.button_action_text') : $r('app.color.status_warning'))
          .backgroundColor($r('app.color.control_track'))
          .style({ strokeWidth: 2,
            status: this.viewModel.builtinModelInstalling && this.viewModel.builtinModelInstallProgress <= 0 ?
              ProgressStatus.LOADING : ProgressStatus.PROGRESSING })
          .accessibilityLevel('no')
        if (this.viewModel.builtinModelInstalling && this.viewModel.builtinModelInstallProgress > 0) {
          Text(`${Math.round(this.viewModel.builtinModelInstallProgress)}%`)
            .fontSize(13).fontWeight(FontWeight.Medium).fontColor($r('app.color.button_action_text'))
        } else {
          Image($r('app.media.icon_download')).width(20).height(20)
            .fillColor($r('app.color.button_action_text'))
            .translate({ y: -1.5 })
        }
      }.width('100%').height('100%').accessibilityLevel('no-hide-descendants')
    }
    .width(DOWNLOAD_TASK_BUTTON_SIZE).height(DOWNLOAD_TASK_BUTTON_SIZE).padding(0)
    .position({ x: this.dragging ? this.dragX : this.dockX(), y: this.dragging ? this.dragY : this.dockY() })
    .backgroundColor(this.pressed ? $r('app.color.selected_background') : $r('app.color.card'))
    .borderRadius(DOWNLOAD_TASK_BUTTON_SIZE / 2)
    .shadow(ShadowStyle.OUTER_DEFAULT_SM)
    .scale({ x: this.pressed ? 0.94 : 1, y: this.pressed ? 0.94 : 1 })
    .hoverEffect(HoverEffect.Auto)
    .id('model-download-task')
    .accessibilityText(this.viewModel.builtinModelInstalling ?
      `查看下载进度，已完成 ${Math.round(this.viewModel.builtinModelInstallProgress)}%` :
      (this.viewModel.builtinModelInstallCanceled ? '查看已暂停的下载' : '查看未完成的下载'))
    .transition(TransitionEffect.OPACITY.animation({ duration: 110, curve: Curve.EaseOut }))
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) this.setPressed(true)
      else if (event.type === TouchType.Up || event.type === TouchType.Cancel) this.setPressed(false)
    })
    .gesture(PanGesture({ direction: PanDirection.All, distance: 8 })
      .onActionStart(() => {
        this.setPressed(false)
        this.dragStartX = this.dockX()
        this.dragStartY = this.dockY()
        this.dragX = this.dragStartX
        this.dragY = this.dragStartY
        this.dragging = true
      })
      .onActionUpdate((event: GestureEvent) => {
        this.dragX = Math.min(Math.max(0, this.availableWidth - DOWNLOAD_TASK_BUTTON_SIZE),
          Math.max(0, this.dragStartX + event.offsetX))
        this.dragY = this.clampY(this.dragStartY + event.offsetY)
      })
      .onActionEnd(() => this.settleDrag())
      .onActionCancel(() => this.settleDrag()))
    .onClick(() => { if (!this.dragging) this.onOpen() })
  }
}
