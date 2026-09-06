export interface AppTabEntry {
  title: string
  description: string
}

@Component
export struct BottomTabs {
  @Prop activeTab: number
  @Prop windowWidth: number = 0
  @Prop entries: AppTabEntry[] = [
    { title: '聊天', description: '全屏对话' },
    { title: '模型', description: '加载参数' },
    { title: '服务', description: 'OpenAI API' },
    { title: '监控', description: 'CPU 内存' }
  ]
  onTabChange: (index: number) => void = (_index: number) => {}
  onSettings: () => void = () => {}

  @Builder
  private TabButton(index: number, title: string, desc: string) {
    Column({ space: 2 }) {
      Text(title)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.activeTab === index ? $r('app.color.nav_selected_text') : $r('app.color.text_muted'))
      if (this.windowWidth < 600 || this.windowWidth >= 840) {
        Text(desc)
        .fontSize(10)
        .fontColor(this.activeTab === index ? $r('app.color.nav_selected_description') : $r('app.color.text_nav_hint'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
    }
    .height(54)
    .width(this.windowWidth >= 600 ? '100%' : `${100 / this.entries.length}%`)
    .flexShrink(this.windowWidth >= 600 ? 0 : 1)
    .justifyContent(FlexAlign.Center)
    .backgroundColor(this.activeTab === index ? $r('app.color.nav_selected_background') : $r('app.color.nav_idle'))
    .borderRadius(8)
    .margin(this.windowWidth >= 600 ? { bottom: 8 } : { left: 4, right: 4 })
    .focusable(true)
    .hoverEffect(HoverEffect.Auto)
    .accessibilityText(title)
    .onClick(() => {
      this.onTabChange(index)
    })
  }

  build() {
    Column({ space: 8 }) {
      Scroll() {
      Flex({ direction: this.windowWidth >= 600 ? FlexDirection.Column : FlexDirection.Row }) {
        ForEach(this.entries, (entry: AppTabEntry, index: number) => {
          this.TabButton(index, entry.title, entry.description)
        }, (entry: AppTabEntry) => entry.title)
      }
      .width('100%')
      }
      .scrollable(this.windowWidth >= 600 ? ScrollDirection.Vertical : ScrollDirection.None)
      .scrollBar(BarState.Off)
      .align(Alignment.TopStart)
      .width('100%')
      .layoutWeight(1)
      if (this.windowWidth >= 600) {
        Button({ type: ButtonType.Normal }) {
          Row({ space: 8 }) {
            SymbolGlyph($r('sys.symbol.gearshape'))
              .fontSize(18)
              .fontColor([$r('app.color.text_secondary')])
            Text('设置')
              .fontSize(14)
              .fontColor($r('app.color.text_secondary'))
          }
          .justifyContent(FlexAlign.Center)
        }
        .width('100%')
        .height(44)
        .borderRadius($r('app.float.button_radius'))
        .backgroundColor($r('app.color.nav_idle'))
        .hoverEffect(HoverEffect.Auto)
        .accessibilityText('设置')
        .onClick(() => this.onSettings())
      }
    }
    .width('100%')
    .height(this.windowWidth >= 600 ? '100%' : 62)
    .padding({ left: this.windowWidth >= 840 ? 12 : this.windowWidth >= 600 ? 8 : 4,
      right: this.windowWidth >= 840 ? 12 : this.windowWidth >= 600 ? 8 : 4, top: 4,
      bottom: this.windowWidth >= 600 ? 0 : 4 })
    .backgroundColor(this.windowWidth >= 600 ? $r('app.color.sidebar_background') : $r('app.color.page_compact'))
    .borderRadius(this.windowWidth >= 600 ? 0 : 10)
  }
}
