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

  private downloadPercent(): number {
    return Math.min(99, Math.round(this.viewModel.builtinModelInstallProgress))
  }

  private downloadAccentColor(): ResourceColor {
    if (this.viewModel.modelDownloadCompleted) return $r('app.color.status_good')
    return this.viewModel.builtinModelInstalling ?
      $r('app.color.button_action_text') : $r('app.color.status_warning')
  }

  build() {
    Button({ type: ButtonType.Circle }) {
      Stack({ alignContent: Alignment.Center }) {
        Circle().width(DOWNLOAD_TASK_BUTTON_SIZE).height(DOWNLOAD_TASK_BUTTON_SIZE)
          .fill(this.pressed ? $r('app.color.selected_background') : $r('app.color.card'))
          .shadow(ShadowStyle.OUTER_DEFAULT_SM)
          .opacity(0.95)
        Progress({ value: this.viewModel.builtinModelInstallProgress, total: 100, type: ProgressType.Ring })
          .width(DOWNLOAD_TASK_BUTTON_SIZE).height(DOWNLOAD_TASK_BUTTON_SIZE)
          .color(this.downloadAccentColor())
          .backgroundColor($r('app.color.control_track'))
          .style({ strokeWidth: 2.5,
            status: this.viewModel.builtinModelInstalling && this.viewModel.builtinModelInstallProgress <= 0 ?
              ProgressStatus.LOADING : ProgressStatus.PROGRESSING })
          .accessibilityLevel('no')
        if (this.viewModel.modelDownloadCompleted) {
          Image($r('app.media.icon_download_complete')).width(22).height(22)
            .fillColor($r('app.color.status_good'))
            .transition(TransitionEffect.OPACITY.combine(TransitionEffect.scale({ x: 0.82, y: 0.82 }))
              .animation({ duration: 200, curve: Curve.EaseOut }))
        } else if (this.viewModel.builtinModelInstalling && this.viewModel.builtinModelInstallProgress > 0) {
          Text(`${this.downloadPercent()}%`)
            .fontSize(14).fontWeight(600).fontColor($r('app.color.button_action_text'))
            .transition(TransitionEffect.OPACITY.animation({ duration: 120, curve: Curve.EaseOut }))
        } else {
          Image($r('app.media.icon_download_task')).width(22).height(22)
            .fillColor(this.downloadAccentColor())
            .translate({ y: -1.5 })
        }
      }.width('100%').height('100%').accessibilityLevel('no-hide-descendants')
    }
    .width(DOWNLOAD_TASK_BUTTON_SIZE).height(DOWNLOAD_TASK_BUTTON_SIZE).padding(0)
    .position({ x: this.dragging ? this.dragX : this.dockX(), y: this.dragging ? this.dragY : this.dockY() })
    .backgroundColor(Color.Transparent)
    .borderRadius(DOWNLOAD_TASK_BUTTON_SIZE / 2)
    .scale({ x: this.pressed ? 0.94 : 1, y: this.pressed ? 0.94 : 1 })
    .hoverEffect(HoverEffect.Auto)
    .id('model-download-task')
    .accessibilityText(this.viewModel.modelDownloadCompleted ? '模型下载完成，查看模型列表' : this.viewModel.builtinModelInstalling ?
      `查看模型下载进度，已完成 ${this.downloadPercent()}%` :
      (this.viewModel.builtinModelInstallCanceled ? '查看已暂停的模型下载' : '查看未完成的模型下载'))
    .transition(TransitionEffect.OPACITY.animation({ duration: 110, curve: Curve.EaseOut }))
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) this.setPressed(true)
      else if (event.type === TouchType.Up || event.type === TouchType.Cancel) this.setPressed(false)
    })
    .gesture(PanGesture({ direction: PanDirection.All, distance: 8 })
      .onActionStart(() => {
        if (this.viewModel.modelDownloadCompleted) return
        this.setPressed(false)
        this.dragStartX = this.dockX()
        this.dragStartY = this.dockY()
        this.dragX = this.dragStartX
        this.dragY = this.dragStartY
        this.dragging = true
      })
      .onActionUpdate((event: GestureEvent) => {
        if (!this.dragging) return
        this.dragX = Math.min(Math.max(0, this.availableWidth - DOWNLOAD_TASK_BUTTON_SIZE),
          Math.max(0, this.dragStartX + event.offsetX))
        this.dragY = this.clampY(this.dragStartY + event.offsetY)
      })
      .onActionEnd(() => this.settleDrag())
      .onActionCancel(() => this.settleDrag()))
    .onClick(() => { if (!this.dragging) this.onOpen() })
  }
}
