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

  @Builder
  private TabButton(index: number, title: string, desc: string) {
    Column({ space: 2 }) {
      Text(title)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.activeTab === index ? '#F4FBFF' : '#8CA2B8')
      if (this.windowWidth < 600 || this.windowWidth >= 840) {
        Text(desc)
        .fontSize(10)
        .fontColor(this.activeTab === index ? '#8DE4C3' : '#5F748A')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
    }
    .height(54)
    .width(this.windowWidth >= 600 ? '100%' : `${100 / this.entries.length}%`)
    .flexShrink(this.windowWidth >= 600 ? 0 : 1)
    .justifyContent(FlexAlign.Center)
    .backgroundColor(this.activeTab === index ? '#14344A' : '#091522')
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
    .width('100%')
    .padding(4)
    .backgroundColor('#07111D')
    .borderRadius(10)
  }
}
