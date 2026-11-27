export type ModelType = 'chat' | 'decision' | 'rerank' | 'embedding'

@Component
export struct ModelTypeSelector {
  @Prop selected: ModelType = 'chat'
  @Prop showReranker: boolean = false
  @Prop interactionEnabled: boolean = true
  onChange: (type: ModelType) => void = (_type: ModelType) => {}
  @State private contentWidth: number = 0

  private segmentWidth(): number {
    return this.contentWidth / (this.showReranker ? 4 : 2)
  }

  private indicatorOffset(): number {
    const index = this.selected === 'decision' ? 1 : this.selected === 'embedding' ? 2 : this.selected === 'rerank' ? 3 : 0
    return index * this.segmentWidth() + (this.segmentWidth() - this.indicatorWidth()) / 2
  }

  private indicatorWidth(): number {
    return Math.min(26, this.segmentWidth())
  }

  @Builder
  private Segment(title: string, type: ModelType) {
    Button(title)
      .height(40)
      .layoutWeight(1)
      .fontSize(14)
      .fontWeight(this.selected === type ? 600 : FontWeight.Medium)
      .fontColor(this.selected === type ?
        $r('app.color.nav_tab_selected') : $r('app.color.text_secondary'))
      .borderRadius($r('app.float.button_radius'))
      .backgroundColor(Color.Transparent)
      .enabled(this.interactionEnabled)
      .accessibilitySelected(this.selected === type)
      .hoverEffect(HoverEffect.Auto)
      .onClick(() => {
        if (type !== this.selected) {
          this.onChange(type)
        }
      })
  }

  build() {
    Stack({ alignContent: Alignment.BottomStart }) {
      Row() {
        this.Segment('对话', 'chat')
        this.Segment('决策', 'decision')
        if (this.showReranker) {
          this.Segment('向量', 'embedding')
          this.Segment('重排', 'rerank')
        }
      }
      .width('100%')
      Divider().color($r('app.color.divider')).opacity(0.6)
        .hitTestBehavior(HitTestMode.None)
      Column()
        .width(this.indicatorWidth())
        .height(2.5)
        .borderRadius(2)
        .backgroundColor($r('app.color.nav_tab_selected'))
        .translate({ x: this.indicatorOffset() })
        .animation({ duration: 180, curve: Curve.EaseOut })
        .hitTestBehavior(HitTestMode.None)
    }
    .height(40)
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      this.contentWidth = Number(newArea.width)
    })
  }
}
