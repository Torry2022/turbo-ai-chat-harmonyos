import { ModelProfile } from '../models/ModelProfile'
import { ModelDragFrame, resolveModelDragPreview } from '../utils/modelDrag'

@Component
export struct SortableModelList {
  @Prop profiles: ModelProfile[] = []
  @Prop selectedId: string = ''
  @Prop loadedId: string = ''
  @Prop interactionEnabled: boolean = true
  onSelect: (id: string) => void = (_id: string) => {}
  onMove: (id: string, index: number) => void = (_id: string, _index: number) => {}
  onDragStateChange: (dragging: boolean) => void = (_dragging: boolean) => {}
  @StorageProp('darkAppearance') private darkAppearance: boolean = true
  @State private draggingModelId: string = ''
  @State private dragOffsetY: number = 0
  @State private dragTargetIndex: number = -1
  private dragStartIndex: number = -1
  private dragFrames: ModelDragFrame[] = []
  private modelCardFrames: Map<string, ModelDragFrame> = new Map()
  private readonly modelCardGap: number = 8

  aboutToDisappear(): void { this.cancelModelDrag() }
  private beginModelDrag(profile: ModelProfile): void {
    if (!this.interactionEnabled) {
      return
    }
    const index = this.profiles.findIndex((item: ModelProfile) => item.id === profile.id)
    if (index < 0) {
      return
    }
    this.draggingModelId = profile.id
    this.dragFrames = this.currentModelCardFrames() ?? []
    this.dragStartIndex = index
    this.dragTargetIndex = index
    this.dragOffsetY = 0
    this.onDragStateChange(true)
  }

  private updateModelDrag(offsetY: number): void {
    if (this.draggingModelId.length <= 0 || this.dragStartIndex < 0) {
      return
    }
    const frames = this.dragFrames
    if (frames.length !== this.profiles.length) {
      this.dragOffsetY = offsetY
      return
    }
    const preview = resolveModelDragPreview(frames, this.dragStartIndex, offsetY)
    this.dragTargetIndex = preview.targetIndex
    this.dragOffsetY = preview.offsetY
  }

  private endModelDrag(): void {
    const modelId = this.draggingModelId
    const startIndex = this.dragStartIndex
    const targetIndex = this.dragTargetIndex
    this.cancelModelDrag()
    if (modelId.length > 0 && targetIndex >= 0 && targetIndex !== startIndex) {
      this.onMove(modelId, targetIndex)
    }
  }

  private cancelModelDrag(): void {
    if (this.draggingModelId.length > 0) {
      this.onDragStateChange(false)
    }
    this.draggingModelId = ''
    this.dragStartIndex = -1
    this.dragTargetIndex = -1
    this.dragOffsetY = 0
    this.dragFrames = []
  }

  private modelCardOffset(modelId: string): number {
    if (this.draggingModelId.length <= 0 || this.dragStartIndex < 0 || this.dragTargetIndex < 0) {
      return 0
    }
    if (modelId === this.draggingModelId) {
      return this.dragOffsetY
    }
    const index = this.profiles.findIndex((profile: ModelProfile) => profile.id === modelId)
    const draggedFrame = this.dragFrames[this.dragStartIndex]
    if (index < 0 || draggedFrame === undefined) {
      return 0
    }
    const placeholderOffset = draggedFrame.height + this.modelCardGap
    if (this.dragTargetIndex > this.dragStartIndex &&
      index > this.dragStartIndex && index <= this.dragTargetIndex) {
      return -placeholderOffset
    }
    if (this.dragTargetIndex < this.dragStartIndex &&
      index >= this.dragTargetIndex && index < this.dragStartIndex) {
      return placeholderOffset
    }
    return 0
  }

  private currentModelCardFrames(): ModelDragFrame[] | undefined {
    const frames: ModelDragFrame[] = []
    for (let index = 0; index < this.profiles.length; index++) {
      const frame = this.modelCardFrames.get(this.profiles[index].id)
      if (frame === undefined) {
        return undefined
      }
      frames.push(frame)
    }
    return frames
  }

  private lengthValue(value: Length | undefined): number {
    if (value === undefined) {
      return 0
    }
    const numericValue = typeof value === 'number' ? value : Number.parseFloat(`${value}`)
    return Number.isFinite(numericValue) ? numericValue : 0
  }

  private rememberModelCardFrame(modelId: string, area: Area): void {
    const top = this.lengthValue(area.position.y)
    const height = this.lengthValue(area.height)
    if (height > 0) {
      this.modelCardFrames.set(modelId, { top, height })
    }
  }

  @Builder
  private CapabilityTag(text: string, color: ResourceColor, background: ResourceColor) {
    Text(text)
      .fontSize(11)
      .fontColor(color)
      .padding({ left: 7, right: 7, top: 3, bottom: 3 })
      .backgroundColor(background)
      .borderRadius(4)
  }

  @Builder
  private ModelOption(profile: ModelProfile) {
    Stack({ alignContent: Alignment.BottomEnd }) {
      Column({ space: 4 }) {
        Row({ space: 6 }) {
          Text(profile.name)
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.selectedId === profile.id ? $r('app.color.text_title') : $r('app.color.text_secondary'))
            .layoutWeight(1)
          if (this.loadedId === profile.id) {
            this.CapabilityTag('已加载', $r('app.color.tag_green_text'), $r('app.color.tag_green_background'))
          }

        }
        .width('100%')

        Text(profile.description)
          .fontSize(12)
          .lineHeight(18)
          .fontColor(this.selectedId === profile.id ? $r('app.color.text_note') : $r('app.color.text_caption'))
          .width('100%')
          .padding({ right: 22 })
      }
      .width('100%')

      Image($r('app.media.model_drag_handle_icon'))
        .width(18)
        .height(18)
        .colorFilter(this.darkAppearance ?
          [1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0] :
          [0.35, 0, 0, 0, 0, 0, 0.35, 0, 0, 0, 0, 0, 0.35, 0, 0, 0, 0, 0, 1, 0])
        .visibility(this.profiles.length > 1 ? Visibility.Visible : Visibility.None)
        .opacity(this.draggingModelId === profile.id ? 0.9 : 0.5)
        .gesture(
          GestureGroup(GestureMode.Parallel,
            LongPressGesture({ duration: 350 })
              .onAction(() => {
                this.beginModelDrag(profile)
              })
              .onActionEnd(() => {
                this.endModelDrag()
              })
              .onActionCancel(() => {
                this.cancelModelDrag()
              }),
            PanGesture({ direction: PanDirection.Vertical, distance: 1 })
              .onActionStart((event: GestureEvent) => {
                if (event.source === SourceType.Mouse) {
                  this.beginModelDrag(profile)
                }
              })
              .onActionUpdate((event: GestureEvent) => {
                this.updateModelDrag(event.offsetY)
              })
              .onActionEnd(() => {
                this.endModelDrag()
              })
              .onActionCancel(() => {
                this.cancelModelDrag()
              })
          )
        )
    }
    .width('100%')
    .padding(10)
    .backgroundColor(this.selectedId === profile.id ? $r('app.color.selected_background') : $r('app.color.list_background'))
    .borderRadius(8)
    .shadow(this.draggingModelId === profile.id ? {
      radius: 16,
      color: '#00000066',
      offsetX: 0,
      offsetY: 8
    } : {
      radius: 0,
      color: '#00000000',
      offsetX: 0,
      offsetY: 0
    })
    .scale(this.draggingModelId === profile.id ? { x: 1.02, y: 1.02 } : { x: 1, y: 1 })
    .translate({ x: 0, y: this.modelCardOffset(profile.id) })
    .zIndex(this.draggingModelId === profile.id ? 10 : 0)
    .onAreaChange((_oldValue: Area, newValue: Area) => {
      this.rememberModelCardFrame(profile.id, newValue)
    })
    .onClick(() => {
      if (!this.interactionEnabled || this.draggingModelId.length > 0) {
        return
      }
      this.onSelect(profile.id)
    })
  }

  build() {
    Column({ space: 8 }) {
      ForEach(this.profiles, (profile: ModelProfile) => { this.ModelOption(profile) },
        (profile: ModelProfile) => profile.id)
    }.width('100%').zIndex(this.draggingModelId.length > 0 ? 10 : 0)
  }
}
