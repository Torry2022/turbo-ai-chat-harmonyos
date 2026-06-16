import { ChatViewModel } from '../state/ChatViewModel'
import { EMPTY_RUNTIME_STATS, RuntimeStats } from '../models/RuntimeStats'
import { RuntimeStatsService } from '../services/RuntimeStatsService'

@Component
struct MonitorStatItem {
  @Prop label: string
  @Prop value: string
  @Prop itemWidth: string
  @Prop valueColor: string = '#EAF4FF'

  build() {
    Column({ space: 3 }) {
      Text(this.value)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.valueColor)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(this.label)
        .fontSize(11)
        .fontColor('#7A92A8')
    }
    .alignItems(HorizontalAlign.Start)
    .padding(10)
    .backgroundColor('#101D2B')
    .borderRadius(8)
    .width(this.itemWidth)
  }
}

@Component
export struct MonitorTab {
  @ObjectLink viewModel: ChatViewModel
  @State stats: RuntimeStats = EMPTY_RUNTIME_STATS
  private statsTimer: number = -1
  private statsService: RuntimeStatsService = new RuntimeStatsService()

  aboutToAppear(): void {
    this.refreshStats()
    this.startTimer()
  }

  aboutToDisappear(): void {
    this.stopTimer()
  }

  private refreshStats(): void {
    this.stats = this.statsService.readStats()
  }

  private startTimer(): void {
    if (this.statsTimer >= 0) {
      return
    }
    this.statsTimer = setInterval(() => {
      this.refreshStats()
    }, 2000)
  }

  private stopTimer(): void {
    if (this.statsTimer < 0) {
      return
    }
    clearInterval(this.statsTimer)
    this.statsTimer = -1
  }

  @Builder
  private SectionTitle(title: string) {
    Text(title)
      .fontSize(16)
      .fontWeight(FontWeight.Bold)
      .fontColor('#F4FBFF')
      .width('100%')
  }

  build() {
    Scroll() {
      Column({ space: 12 }) {
        // Intro
        Column({ space: 4 }) {
          Text('在此处实时查看当前设备的 CPU、内存和模型运行状态，\n数据每两秒自动刷新')
            .width('100%')
            .lineHeight(18)
            .padding({ left: 8 })
            .fontSize(12)
            .fontColor('#8CA2B8')
        }
        .width('100%')
        .padding({ left: 4, bottom: 4 })

        // Model state
        Column({ space: 8 }) {
          this.SectionTitle('模型状态')
          Column({ space: 8 }) {
            MonitorStatItem({
              label: '模型',
              value: this.viewModel.currentModel().shortName,
              itemWidth: '100%'
            })
            MonitorStatItem({
              label: '状态',
              value: this.viewModel.busy ? '生成中...' : (this.viewModel.modelLoading ? '加载中...' : (this.viewModel.loaded ? '就绪' : '未加载')),
              itemWidth: '100%',
              valueColor: this.viewModel.busy ? '#F2B35D' : (this.viewModel.modelLoading ? '#5BA4E6' : (this.viewModel.loaded ? '#45D6A4' : '#8CA2B8'))
            })
          }
          .width('100%')
        }
        .width('100%')
        .padding(12)
        .backgroundColor('#0D1A28')
        .borderRadius(8)

        // CPU
        Column({ space: 8 }) {
          this.SectionTitle('CPU')
          Row({ space: 8 }) {
            MonitorStatItem({ label: '应用 CPU', value: this.stats.appCpu, itemWidth: '48%' })
            MonitorStatItem({ label: '系统 CPU', value: this.stats.systemCpu, itemWidth: '48%' })
          }
          .width('100%')
          .alignItems(VerticalAlign.Top)
          Row({ space: 8 }) {
            MonitorStatItem({ label: '线程数', value: this.stats.threadCount, itemWidth: '48%' })
            MonitorStatItem({ label: '电池温度', value: this.stats.socTemp, itemWidth: '48%' })
          }
          .width('100%')
          .alignItems(VerticalAlign.Top)
        }
        .width('100%')
        .padding(12)
        .backgroundColor('#0D1A28')
        .borderRadius(8)

        // App memory
        Column({ space: 8 }) {
          this.SectionTitle('应用内存')
          Row({ space: 8 }) {
            MonitorStatItem({ label: '进程占用', value: this.stats.appPss, itemWidth: '48%' })
            MonitorStatItem({ label: '原生堆占用', value: this.stats.nativeHeapAllocated, itemWidth: '48%' })
          }
          .width('100%')
          .alignItems(VerticalAlign.Top)
        }
        .width('100%')
        .padding(12)
        .backgroundColor('#0D1A28')
        .borderRadius(8)

        // System memory
        Column({ space: 8 }) {
          this.SectionTitle('系统内存')
          Row({ space: 8 }) {
            MonitorStatItem({ label: '总内存', value: this.stats.systemMemTotal, itemWidth: '48%' })
            MonitorStatItem({ label: '可用', value: this.stats.systemMemAvailable, itemWidth: '48%' })
          }
          .width('100%')
          .alignItems(VerticalAlign.Top)
        }
        .width('100%')
        .padding(12)
        .backgroundColor('#0D1A28')
        .borderRadius(8)

      }
      .width('100%')
    }
    .layoutWeight(1)
    .width('100%')
    .align(Alignment.Top)
    .scrollBar(BarState.Off)
  }
}
