import { ChatViewModel } from '../state/ChatViewModel'
import { EMPTY_RUNTIME_STATS, EMPTY_STORAGE_STATS, RuntimeStats, StorageStats } from '../models/RuntimeStats'
import { RuntimeStatsService } from '../services/RuntimeStatsService'
import {
  colorForAppCpu,
  colorForAvailableMemory,
  colorForMemoryUsage,
  colorForSystemCpu,
  colorForTemperature
} from '../utils/runtimeStatColors'

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
  @State storageStats: StorageStats = EMPTY_STORAGE_STATS
  private statsTimer: number = -1
  private storageStatsReading: boolean = false
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
    if (this.storageStatsReading) {
      return
    }
    this.storageStatsReading = true
    this.statsService.readStorageStats(
      this.viewModel.appFilesDir,
      `${this.viewModel.appFilesDir}/${this.viewModel.currentModel().directoryName}`
    ).then((storageStats: StorageStats) => {
      this.storageStats = storageStats
    }).catch((_err: Error) => {
      this.storageStats = EMPTY_STORAGE_STATS
    }).finally(() => {
      this.storageStatsReading = false
    })
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

  private modelStateModelWidth(): string {
    const modelName = this.viewModel.currentModel().shortName
    if (modelName.length > 18) {
      return '64%'
    }
    if (modelName.length > 12) {
      return '58%'
    }
    return '48%'
  }

  private modelStateStatusWidth(): string {
    const modelName = this.viewModel.currentModel().shortName
    if (modelName.length > 18) {
      return '32%'
    }
    if (modelName.length > 12) {
      return '38%'
    }
    return '48%'
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
      Column({ space: 10 }) {
        // Intro
        Column({ space: 4 }) {
          Text('实时查看设备与模型运行状态，每两秒自动刷新')
            .width('100%')
            .lineHeight(18)
            .padding({ left: 7 })
            .fontSize(12)
            .fontColor('#8CA2B8')
        }
        .width('100%')
        .padding({ left: 4, bottom: 4 })

        // Model state
        Column({ space: 6 }) {
          this.SectionTitle('模型状态')
          Row({ space: 8 }) {
            MonitorStatItem({
              label: '模型',
              value: this.viewModel.currentModel().shortName,
              itemWidth: this.modelStateModelWidth()
            })
            MonitorStatItem({
              label: '状态',
              value: this.viewModel.busy ? '生成中...' : (this.viewModel.modelLoading ? '加载中...' : (this.viewModel.loaded ? '就绪' : '未加载')),
              itemWidth: this.modelStateStatusWidth(),
              valueColor: this.viewModel.busy ? '#F2B35D' : (this.viewModel.modelLoading ? '#5BA4E6' : (this.viewModel.loaded ? '#45D6A4' : '#8CA2B8'))
            })
          }
          .width('100%')
          .alignItems(VerticalAlign.Top)
        }
        .width('100%')
        .padding(10)
        .backgroundColor('#0D1A28')
        .borderRadius(8)

        // CPU
        Column({ space: 6 }) {
          this.SectionTitle('CPU')
          Row({ space: 8 }) {
            MonitorStatItem({
              label: '应用 CPU',
              value: this.stats.appCpu,
              itemWidth: '48%',
              valueColor: colorForAppCpu(this.stats.appCpu)
            })
            MonitorStatItem({
              label: '系统 CPU',
              value: this.stats.systemCpu,
              itemWidth: '48%',
              valueColor: colorForSystemCpu(this.stats.systemCpu)
            })
          }
          .width('100%')
          .alignItems(VerticalAlign.Top)
          Row({ space: 8 }) {
            MonitorStatItem({ label: '线程数', value: this.stats.threadCount, itemWidth: '48%' })
            MonitorStatItem({
              label: '电池温度',
              value: this.stats.socTemp,
              itemWidth: '48%',
              valueColor: colorForTemperature(this.stats.socTemp)
            })
          }
          .width('100%')
          .alignItems(VerticalAlign.Top)
        }
        .width('100%')
        .padding(10)
        .backgroundColor('#0D1A28')
        .borderRadius(8)

        // App memory
        Column({ space: 6 }) {
          this.SectionTitle('应用内存')
          Row({ space: 8 }) {
            MonitorStatItem({
              label: '进程占用',
              value: this.stats.appPss,
              itemWidth: '48%',
              valueColor: colorForMemoryUsage(this.stats.appPss)
            })
            MonitorStatItem({
              label: '原生堆占用',
              value: this.stats.nativeHeapAllocated,
              itemWidth: '48%',
              valueColor: colorForMemoryUsage(this.stats.nativeHeapAllocated)
            })
          }
          .width('100%')
          .alignItems(VerticalAlign.Top)
        }
        .width('100%')
        .padding(10)
        .backgroundColor('#0D1A28')
        .borderRadius(8)

        // System memory
        Column({ space: 6 }) {
          this.SectionTitle('系统内存')
          Row({ space: 8 }) {
            MonitorStatItem({ label: '总内存', value: this.stats.systemMemTotal, itemWidth: '48%' })
            MonitorStatItem({
              label: '可用',
              value: this.stats.systemMemAvailable,
              itemWidth: '48%',
              valueColor: colorForAvailableMemory(this.stats.systemMemAvailable)
            })
          }
          .width('100%')
          .alignItems(VerticalAlign.Top)
        }
        .width('100%')
        .padding(10)
        .backgroundColor('#0D1A28')
        .borderRadius(8)

        // App storage
        Column({ space: 6 }) {
          this.SectionTitle('存储占用')
          Row({ space: 8 }) {
            MonitorStatItem({ label: '文件目录', value: this.storageStats.appFiles, itemWidth: '48%' })
            MonitorStatItem({ label: '当前模型', value: this.storageStats.currentModel, itemWidth: '48%' })
          }
          .width('100%')
          .alignItems(VerticalAlign.Top)
        }
        .width('100%')
        .padding(10)
        .backgroundColor('#0D1A28')
        .borderRadius(8)

        Text('Turbo AI Chat v1.5.0')
          .width('100%')
          .textAlign(TextAlign.Center)
          .fontSize(11)
          .fontColor('#5E748A')
      }
      .width('100%')
    }
    .layoutWeight(1)
    .width('100%')
    .align(Alignment.Top)
    .scrollBar(BarState.Off)
  }
}
