import { ChatViewModel } from '../state/ChatViewModel';

@Component
export struct MonitorTab {
  @ObjectLink viewModel: ChatViewModel;

  @Builder
  private StatItem(label: string, value: string) {
    Column({ space: 2 }) {
      Text(label)
        .fontSize(11)
        .fontColor('#8CA2B8');
      Text(value)
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor('#F2F8FF')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis });
    }
    .alignItems(HorizontalAlign.Start)
    .padding(8)
    .backgroundColor('#101D2B')
    .borderRadius(8)
    .width('32%');
  }

  build() {
    Column({ space: 12 }) {
      Column({ space: 8 }) {
        Row() {
          Text('设备监控')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor('#F4FBFF')
            .layoutWeight(1);
          Button('刷新')
            .height(34)
            .onClick(() => {
              this.viewModel.refreshStats();
            });
        }
        .width('100%');

        Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
          this.StatItem('应用 CPU', this.viewModel.stats.appCpu);
          this.StatItem('系统 CPU', this.viewModel.stats.systemCpu);
          this.StatItem('应用内存', this.viewModel.stats.appPss);
          this.StatItem('原生堆', this.viewModel.stats.nativeHeap);
          this.StatItem('系统内存', this.viewModel.stats.systemMem);
        }
        .width('100%');
      }
      .width('100%')
      .padding(12)
      .backgroundColor('#0D1A28')
      .borderRadius(8);

      Column({ space: 6 }) {
        Text('运行状态')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor('#F4FBFF');
        Text(this.viewModel.status)
          .fontSize(13)
          .lineHeight(20)
          .fontColor('#9FBDD5');
      }
      .width('100%')
      .padding(12)
      .backgroundColor('#101D2B')
      .borderRadius(8);

      Blank();
    }
    .layoutWeight(1)
    .width('100%');
  }
}
