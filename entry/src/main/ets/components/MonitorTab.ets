import { ChatViewModel } from '../state/ChatViewModel';
import { EMPTY_RUNTIME_STATS, RuntimeStats } from '../models/RuntimeStats';
import { RuntimeStatsService } from '../services/RuntimeStatsService';

@Component
struct MonitorStatItem {
  @Prop label: string;
  @Prop value: string;

  build() {
    Column({ space: 2 }) {
      Text(this.label)
        .fontSize(11)
        .fontColor('#8CA2B8');
      Text(this.value)
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
}

@Component
export struct MonitorTab {
  @ObjectLink viewModel: ChatViewModel;
  @State appCpu: string = EMPTY_RUNTIME_STATS.appCpu;
  @State systemCpu: string = EMPTY_RUNTIME_STATS.systemCpu;
  @State appPss: string = EMPTY_RUNTIME_STATS.appPss;
  @State nativeHeap: string = EMPTY_RUNTIME_STATS.nativeHeap;
  @State systemMem: string = EMPTY_RUNTIME_STATS.systemMem;
  private statsTimer: number = -1;
  private statsService: RuntimeStatsService = new RuntimeStatsService();

  aboutToAppear(): void {
    this.refreshLocalStats();
    this.startStatsTimer();
  }

  aboutToDisappear(): void {
    this.stopStatsTimer();
  }

  private refreshLocalStats(): void {
    const stats: RuntimeStats = this.statsService.readStats();
    this.appCpu = stats.appCpu;
    this.systemCpu = stats.systemCpu;
    this.appPss = stats.appPss;
    this.nativeHeap = stats.nativeHeap;
    this.systemMem = stats.systemMem;
  }

  private startStatsTimer(): void {
    if (this.statsTimer >= 0) {
      return;
    }
    this.statsTimer = setInterval(() => {
      this.refreshLocalStats();
    }, 1500);
  }

  private stopStatsTimer(): void {
    if (this.statsTimer < 0) {
      return;
    }
    clearInterval(this.statsTimer);
    this.statsTimer = -1;
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
              this.refreshLocalStats();
            });
        }
        .width('100%');

        Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
          MonitorStatItem({ label: '应用 CPU', value: this.appCpu });
          MonitorStatItem({ label: '系统 CPU', value: this.systemCpu });
          MonitorStatItem({ label: '应用内存', value: this.appPss });
          MonitorStatItem({ label: '原生堆', value: this.nativeHeap });
          MonitorStatItem({ label: '系统内存', value: this.systemMem });
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
