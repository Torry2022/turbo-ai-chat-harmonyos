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
  @Prop itemWeight: number = 1
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
    .borderRadius($r('app.float.card_radius'))
    .layoutWeight(this.itemWeight)
  }
}

@Component
export struct MonitorTab {
  @ObjectLink viewModel: ChatViewModel
  @Prop @Watch('onActiveChanged') active: boolean = false
  @State stats: RuntimeStats = EMPTY_RUNTIME_STATS
  @State storageStats: StorageStats = EMPTY_STORAGE_STATS
  @State private contentWidth: number = 0
  private statsTimer: number = -1
  private scroller: Scroller = new Scroller()
  private storageStatsReading: boolean = false
  private statsService: RuntimeStatsService = new RuntimeStatsService()

  aboutToAppear(): void {
    this.onActiveChanged()
  }

  private onActiveChanged(): void {
    if (!this.active) {
      this.stopTimer()
      return
    }
    this.storageStats = this.viewModel.storageStatsForCurrentModel()
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
    const modelConfig = this.viewModel.modelPath
    this.viewModel.readStorageStatsForCurrentModel().then((storageStats: StorageStats) => {
      this.viewModel.cacheStorageStats(modelConfig, storageStats)
      if (modelConfig === this.viewModel.modelPath) {
        this.storageStats = storageStats
      }
    }).catch((_err: Error) => {
      this.storageStats = this.viewModel.storageStatsForCurrentModel()
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

  private cardWidth(): number {
    return this.contentWidth >= 720 ? (this.contentWidth - 16) / 2 : this.contentWidth
  }

  private modelNameWeight(): number {
    const length = this.viewModel.currentModel().shortName.length
    return length > 18 ? 2 : length > 12 ? 1.5 : 1
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
    Scroll(this.scroller) {
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

        Flex({ wrap: FlexWrap.Wrap }) {
          // Model state
          Column({ space: 6 }) {
            this.SectionTitle('模型状态')
            Row({ space: 8 }) {
              MonitorStatItem({
                label: '模型',
                value: this.viewModel.currentModel().shortName,
                itemWeight: this.modelNameWeight()
              })
              MonitorStatItem({
                label: '状态',
                value: this.viewModel.busy ? '生成中...' : (this.viewModel.modelLoading ? '加载中...' : (this.viewModel.loaded ? '就绪' : '未加载')),
                itemWeight: 1,
                valueColor: this.viewModel.busy ? '#F2B35D' : (this.viewModel.modelLoading ? '#5BA4E6' : (this.viewModel.loaded ? '#45D6A4' : '#8CA2B8'))
              })
            }
            .width('100%')
            .alignItems(VerticalAlign.Top)
          }
          .width(this.cardWidth())
          .margin({ right: this.contentWidth >= 720 ? 16 : 0, bottom: 10 })
          .padding(10)
          .backgroundColor('#0D1A28')
          .borderRadius($r('app.float.card_radius'))

          // CPU
          Column({ space: 6 }) {
            this.SectionTitle('CPU')
            Row({ space: 8 }) {
              MonitorStatItem({
                label: '应用 CPU',
                value: this.stats.appCpu,
                itemWeight: 1,
                valueColor: colorForAppCpu(this.stats.appCpu)
              })
              MonitorStatItem({
                label: '系统 CPU',
                value: this.stats.systemCpu,
                itemWeight: 1,
                valueColor: colorForSystemCpu(this.stats.systemCpu)
              })
            }
            .width('100%')
            .alignItems(VerticalAlign.Top)
            Row({ space: 8 }) {
              MonitorStatItem({ label: '线程数', value: this.stats.threadCount, itemWeight: 1 })
              MonitorStatItem({
                label: '电池温度',
                value: this.stats.socTemp,
                itemWeight: 1,
                valueColor: colorForTemperature(this.stats.socTemp)
              })
            }
            .width('100%')
            .alignItems(VerticalAlign.Top)
          }
          .width(this.cardWidth())
          .margin({ bottom: 10 })
          .padding(10)
          .backgroundColor('#0D1A28')
          .borderRadius($r('app.float.card_radius'))

          // App memory
          Column({ space: 6 }) {
            this.SectionTitle('应用内存')
            Row({ space: 8 }) {
              MonitorStatItem({
                label: '进程占用',
                value: this.stats.appPss,
                itemWeight: 1,
                valueColor: colorForMemoryUsage(this.stats.appPss)
              })
              MonitorStatItem({
                label: '原生堆占用',
                value: this.stats.nativeHeapAllocated,
                itemWeight: 1,
                valueColor: colorForMemoryUsage(this.stats.nativeHeapAllocated)
              })
            }
            .width('100%')
            .alignItems(VerticalAlign.Top)
          }
          .width(this.cardWidth())
          .margin({ right: this.contentWidth >= 720 ? 16 : 0, bottom: 10 })
          .padding(10)
          .backgroundColor('#0D1A28')
          .borderRadius($r('app.float.card_radius'))

          // System memory
          Column({ space: 6 }) {
            this.SectionTitle('系统内存')
            Row({ space: 8 }) {
              MonitorStatItem({ label: '总内存', value: this.stats.systemMemTotal, itemWeight: 1 })
              MonitorStatItem({
                label: '可用',
                value: this.stats.systemMemAvailable,
                itemWeight: 1,
                valueColor: colorForAvailableMemory(this.stats.systemMemAvailable)
              })
            }
            .width('100%')
            .alignItems(VerticalAlign.Top)
          }
          .width(this.cardWidth())
          .margin({ bottom: 10 })
          .padding(10)
          .backgroundColor('#0D1A28')
          .borderRadius($r('app.float.card_radius'))

          // App storage
          Column({ space: 6 }) {
            this.SectionTitle('存储占用')
            Row({ space: 8 }) {
              MonitorStatItem({ label: '文件目录', value: this.storageStats.appFiles, itemWeight: 1 })
              MonitorStatItem({ label: '当前模型', value: this.storageStats.currentModel, itemWeight: 1 })
            }
            .width('100%')
            .alignItems(VerticalAlign.Top)
          }
          .width(this.cardWidth())
          .margin({ right: this.contentWidth >= 720 ? 16 : 0, bottom: 10 })
          .padding(10)
          .backgroundColor('#0D1A28')
          .borderRadius($r('app.float.card_radius'))

        }
        .width('100%')

        Text(this.viewModel.appVersion.length > 0 ? `Turbo AI Chat v${this.viewModel.appVersion}` : 'Turbo AI Chat')
          .width('100%')
          .textAlign(TextAlign.Center)
          .fontSize(11)
          .fontColor('#5E748A')
      }
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      this.contentWidth = Number(newArea.width)
    })
    .align(Alignment.Top)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
  }
}
