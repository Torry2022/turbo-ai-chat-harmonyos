export type ModelType = 'chat' | 'decision' | 'rerank'

@Component
export struct ModelTypeSelector {
  @Prop selected: ModelType = 'chat'
  @Prop showReranker: boolean = false
  @Prop interactionEnabled: boolean = true
  onChange: (type: ModelType) => void = (_type: ModelType) => {}
  @State private contentWidth: number = 0

  private indicatorWidth(): number {
    return Math.max(0, (this.contentWidth - (this.showReranker ? 8 : 6)) / (this.showReranker ? 3 : 2))
  }

  private indicatorOffset(): number {
    return 2 + (this.selected === 'rerank' ? 2 : this.selected === 'decision' ? 1 : 0) * (this.indicatorWidth() + 2)
  }

  @Builder
  private Segment(title: string, type: ModelType) {
    Button(title)
      .height(36)
      .layoutWeight(1)
      .fontSize(14)
      .fontWeight(this.selected === type ? FontWeight.Medium : FontWeight.Regular)
      .fontColor(this.selected === type ?
        $r('app.color.nav_mobile_selected') : $r('app.color.text_muted'))
      .borderRadius(8)
      .backgroundColor(Color.Transparent)
      .enabled(this.interactionEnabled)
      .hoverEffect(HoverEffect.Auto)
      .onClick(() => {
        if (type !== this.selected) {
          this.getUIContext().animateTo({ duration: 180, curve: Curve.EaseOut }, () => {
            this.onChange(type)
          })
        }
      })
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column()
        .width(this.indicatorWidth())
        .height(36)
        .borderRadius(8)
        .backgroundColor($r('app.color.gallery_entry_background'))
        .translate({ x: this.indicatorOffset(), y: 2 })
      Row({ space: 2 }) {
        this.Segment('聊天模型', 'chat')
        this.Segment('决策模型', 'decision')
        if (this.showReranker) {
          this.Segment('重排模型', 'rerank')
        }
      }
      .height(40)
      .padding(2)
    }
    .height(40)
    .borderRadius(10)
    .backgroundColor($r('app.color.input_background'))
    .clip(true)
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      this.contentWidth = Number(newArea.width)
    })
  }
}
