import { DrawContext, FrameCallback, FrameNode, LengthMetricsUnit, NodeController, RenderNode, UIContext } from '@kit.ArkUI'
import { image } from '@kit.ImageKit'
import { drawing } from '@kit.ArkGraphics2D'
import { DownloadTaskPoint } from './DownloadTaskButton'

export const DOWNLOAD_TASK_MOTION_DURATION: number = 280
export const DOWNLOAD_TASK_PANEL_ID: string = 'download-task-dialog-panel'

const MESH_COLUMNS: number = 12
const MESH_ROWS: number = 22

export interface DownloadPanelSnapshot {
  image: image.PixelMap
  x: number
  y: number
  width: number
  height: number
}

export class DownloadTaskFrame extends FrameCallback {
  private callback: (timeNs: number) => void

  constructor(callback: (timeNs: number) => void) {
    super()
    this.callback = callback
  }

  onFrame(timeNs: number): void {
    this.callback(timeNs)
  }
}

class DownloadPanelMesh extends RenderNode {
  private readonly vertices: number[] = []
  private readonly brush: drawing.Brush = new drawing.Brush()
  private readonly snapshot: DownloadPanelSnapshot
  private readonly dock: DownloadTaskPoint
  private readonly targetSize: number
  private readonly towardVerticalEdge: boolean
  private readonly towardEnd: boolean

  constructor(snapshot: DownloadPanelSnapshot, dock: DownloadTaskPoint, targetSize: number) {
    super()
    this.snapshot = snapshot
    this.dock = dock
    this.targetSize = targetSize
    this.lengthMetricsUnit = LengthMetricsUnit.PX
    const deltaX = dock.x - (snapshot.x + snapshot.width / 2)
    const deltaY = dock.y - (snapshot.y + snapshot.height / 2)
    this.towardVerticalEdge = Math.abs(deltaY) >= Math.abs(deltaX)
    this.towardEnd = (this.towardVerticalEdge ? deltaY : deltaX) >= 0
  }

  setProgress(progress: number): void {
    const panel = this.snapshot
    const bend = Math.sin(Math.PI * progress) * 0.37
    let index = 0
    for (let row = 0; row <= MESH_ROWS; row++) {
      const v = row / MESH_ROWS
      for (let column = 0; column <= MESH_COLUMNS; column++) {
        const u = column / MESH_COLUMNS
        const fraction = this.towardVerticalEdge ? v : u
        const towardDock = this.towardEnd ? fraction : 1 - fraction
        const squeeze = Math.max(0, Math.min(1, progress + (2 * towardDock - 1) * bend))
        const blendX = this.towardVerticalEdge ? squeeze : progress
        const blendY = this.towardVerticalEdge ? progress : squeeze
        this.vertices[index++] = (panel.x + panel.width * u) * (1 - blendX) +
          (this.dock.x + (u - 0.5) * this.targetSize) * blendX
        this.vertices[index++] = (panel.y + panel.height * v) * (1 - blendY) +
          (this.dock.y + (v - 0.5) * this.targetSize) * blendY
      }
    }
    this.opacity = 1 - Math.max(0, (progress - 0.86) / 0.14) * 0.8
    this.invalidate()
  }

  draw(context: DrawContext): void {
    if (this.vertices.length === 0) return
    const canvas = context.canvas
    canvas.attachBrush(this.brush)
    canvas.drawPixelMapMesh(this.snapshot.image, MESH_COLUMNS, MESH_ROWS, this.vertices, 0, null, 0)
    canvas.detachBrush()
  }
}

class DownloadPanelMotionController extends NodeController {
  private readonly mesh: DownloadPanelMesh
  private readonly widthPx: number
  private readonly heightPx: number

  constructor(snapshot: DownloadPanelSnapshot, dock: DownloadTaskPoint, targetSizePx: number,
    widthPx: number, heightPx: number) {
    super()
    this.mesh = new DownloadPanelMesh(snapshot, dock, targetSizePx)
    this.widthPx = widthPx
    this.heightPx = heightPx
  }

  makeNode(context: UIContext): FrameNode {
    const frame = new FrameNode(context)
    this.mesh.frame = { x: 0, y: 0, width: this.widthPx, height: this.heightPx }
    frame.getRenderNode()?.appendChild(this.mesh)
    return frame
  }

  setProgress(progress: number): void {
    this.mesh.setProgress(progress)
  }
}

@Component
export struct DownloadTaskMotion {
  snapshot: DownloadPanelSnapshot | undefined = undefined
  dock: DownloadTaskPoint = { x: 0, y: 0 }
  @Prop widthPx: number = 0
  @Prop heightPx: number = 0
  @Prop targetSizePx: number = 0
  @Prop opening: boolean = false
  onComplete: () => void = () => {}
  private controller?: DownloadPanelMotionController
  private frameStartNs: number = -1
  private running: boolean = false

  aboutToAppear(): void {
    if (this.snapshot === undefined) return
    this.controller = new DownloadPanelMotionController(this.snapshot, this.dock, this.targetSizePx,
      this.widthPx, this.heightPx)
    this.controller.setProgress(this.opening ? 1 : 0)
    this.running = true
    this.requestFrame()
  }

  aboutToDisappear(): void {
    this.running = false
  }

  private requestFrame(): void {
    this.getUIContext().postFrameCallback(new DownloadTaskFrame((timeNs: number) => {
      if (!this.running) return
      if (this.frameStartNs < 0) this.frameStartNs = timeNs
      const elapsed = (timeNs - this.frameStartNs) / 1000000
      const fraction = Math.min(1, elapsed / DOWNLOAD_TASK_MOTION_DURATION)
      const eased = fraction * fraction * (3 - 2 * fraction)
      this.controller?.setProgress(this.opening ? 1 - eased : eased)
      if (fraction < 1) {
        this.requestFrame()
      } else {
        this.running = false
        this.onComplete()
      }
    }))
  }

  build() {
    NodeContainer(this.controller)
      .width('100%')
      .height('100%')
      .hitTestBehavior(HitTestMode.None)
      .accessibilityLevel('no-hide-descendants')
      .zIndex(15)
  }
}
