import { ChatViewModel } from '../state/ChatViewModel'
import { EMPTY_RUNTIME_STATS, RuntimeStats } from '../models/RuntimeStats'
import { RuntimeStatsService } from '../services/RuntimeStatsService'
import { colorForAppCpu, colorForMemoryUsage, colorForTemperature } from '../utils/runtimeStatColors'

@Component
export struct ChatRunTicker {
  @ObjectLink viewModel: ChatViewModel
  @Prop topSpacing: number = 6
  @State private stats: RuntimeStats = EMPTY_RUNTIME_STATS
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

  build() {
    Row() {
      Text('应用CPU ')
        .fontSize(11)
        .fontColor('#8CA2B8')
        .maxLines(1)
      Text(this.stats.appCpu)
        .fontSize(11)
        .fontColor(colorForAppCpu(this.stats.appCpu))
        .maxLines(1)
      Text(' · ')
        .fontSize(11)
        .fontColor('#8CA2B8')
        .maxLines(1)
      Text('应用内存 ')
        .fontSize(11)
        .fontColor('#8CA2B8')
        .maxLines(1)
      Text(this.stats.appPss)
        .fontSize(11)
        .fontColor(colorForMemoryUsage(this.stats.appPss))
        .maxLines(1)
      Text(' · ')
        .fontSize(11)
        .fontColor('#8CA2B8')
        .maxLines(1)
      Text('设备温度 ')
        .fontSize(11)
        .fontColor('#8CA2B8')
        .maxLines(1)
      Text(this.stats.socTemp)
        .fontSize(11)
        .fontColor(colorForTemperature(this.stats.socTemp))
        .maxLines(1)
    }
    .width('100%')
    .height(20)
    .padding({ left: 8, right: 8 })
    .margin({ top: this.topSpacing })
    .backgroundColor('#0D2232')
    .justifyContent(FlexAlign.Center)
  }
}
