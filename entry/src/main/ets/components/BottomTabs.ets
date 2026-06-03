@Component
export struct BottomTabs {
  @Prop activeTab: number;
  onTabChange: (index: number) => void = (_index: number) => {};

  @Builder
  private TabButton(index: number, title: string, desc: string) {
    Column({ space: 2 }) {
      Text(title)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.activeTab === index ? '#F4FBFF' : '#8CA2B8');
      Text(desc)
        .fontSize(10)
        .fontColor(this.activeTab === index ? '#8DE4C3' : '#5F748A')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis });
    }
    .height(54)
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .backgroundColor(this.activeTab === index ? '#14344A' : '#091522')
    .borderRadius(8)
    .onClick(() => {
      this.onTabChange(index);
    });
  }

  build() {
    Row({ space: 8 }) {
      this.TabButton(0, '聊天', '全屏对话');
      this.TabButton(1, '模型', '加载参数');
      this.TabButton(2, '监控', 'CPU 内存');
    }
    .width('100%')
    .padding(4)
    .backgroundColor('#07111D')
    .borderRadius(10);
  }
}
