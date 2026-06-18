import { ChatViewModel } from '../state/ChatViewModel'
import { EMPTY_RUNTIME_STATS, RuntimeStats } from '../models/RuntimeStats'
import { RuntimeStatsService } from '../services/RuntimeStatsService'

@Component
export struct ChatRunTicker {
  @ObjectLink viewModel: ChatViewModel
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

  private tickerText(): string {
    return `CPU占用 ${this.stats.appCpu} · 内存占用 ${this.stats.appPss} · 设备温度 ${this.stats.socTemp}`
  }

  build() {
    Row() {
      Text(this.tickerText())
        .fontSize(11)
        .fontColor('#8CA2B8')
        .textAlign(TextAlign.Center)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
    }
    .width('100%')
    .height(20)
    .padding({ left: 8, right: 8 })
    .margin({ top: 6 })
    .backgroundColor('#0D2232')
  }
}
