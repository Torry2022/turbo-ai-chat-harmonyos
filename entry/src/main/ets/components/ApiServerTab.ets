import { ApiServerLogEntry, ChatViewModel } from '../state/ChatViewModel'
import { pasteboard } from '@kit.BasicServicesKit'

@Component
export struct ApiServerTab {
  @ObjectLink viewModel: ChatViewModel
  @Prop renderVersion: number = 0
  @Prop loaded: boolean = false
  @Prop busy: boolean = false
  @Prop currentModelName: string = ''
  @Prop apiServerRunning: boolean = false
  @Prop apiServerStarting: boolean = false
  @Prop apiServerPortInput: string = '8080'
  @Prop apiServerRequireKey: boolean = true
  @Prop apiServerKey: string = ''
  @Prop apiServerAddress: string = ''
  @Prop apiServerStatus: string = ''
  @Prop apiServerRequestCount: number = 0
  @Prop apiServerLogs: ApiServerLogEntry[] = []
  @State apiKeyVisible: boolean = false
  private portInputController: TextInputController = new TextInputController()

  aboutToAppear(): void {
    this.viewModel.refreshApiServerAddress()
  }

  @Builder
  private Label(text: string) {
    Text(text)
      .fontSize(12)
      .fontColor('#8CA2B8')
      .width('100%')
  }

  @Builder
  private SectionTitle(text: string) {
    Text(text)
      .fontSize(16)
      .lineHeight(22)
      .fontWeight(FontWeight.Bold)
      .fontColor('#F4FBFF')
  }

  private logLevelColor(level: string): string {
    if (level === 'ERROR') {
      return '#F26D6D'
    }
    if (level === 'RESP') {
      return '#69D38A'
    }
    if (level === 'REQ') {
      return '#5AB0F2'
    }
    return '#8CA2B8'
  }

  private logItems(): ApiServerLogEntry[] {
    const items = this.apiServerLogs.slice()
    items.reverse()
    return items
  }

  private async copyText(text: string, label: string): Promise<void> {
    try {
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text)
      await pasteboard.getSystemPasteboard().setData(data)
      this.showToast(`${label} 已复制`)
    } catch (_) {
      this.showToast('复制失败')
    }
  }

  private showToast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message, duration: 1500, bottom: 80 })
    } catch (_) {
    }
  }

  @Builder
  private Endpoint(method: string, path: string, methodColor: string) {
    Row({ space: 7 }) {
      Text(method)
        .width(34)
        .fontSize(12)
        .lineHeight(20)
        .fontWeight(FontWeight.Medium)
        .fontColor(methodColor)
      Text(path)
        .fontSize(12)
        .lineHeight(20)
        .fontColor('#B7CDE1')
    }
    .width('100%')
  }

  build() {
    Scroll() {
      Column({ space: 10 }) {
        Column({ space: 4 }) {
          Text('通过局域网向 OpenAI 兼容客户端提供当前模型')
            .width('100%')
            .lineHeight(18)
            .padding({ left: 7 })
            .fontSize(12)
            .fontColor('#8CA2B8')
        }
        .width('100%')
        .padding({ left: 4, bottom: 4 })

        Column({ space: 6 }) {
          Row() {
            this.SectionTitle('服务状态')
            Blank()
            Toggle({ type: ToggleType.Switch, isOn: this.apiServerRunning })
              .height(22)
              .enabled(!this.apiServerStarting && (!this.busy || this.apiServerRunning))
              .selectedColor('#45D6A4')
              .onChange((enabled: boolean) => {
                this.viewModel.setApiServerEnabled(enabled)
              })
          }
          .height(22)
          .width('100%')
          .alignItems(VerticalAlign.Center)
          Text(this.apiServerStatus)
            .fontSize(13)
            .lineHeight(19)
            .fontColor(this.apiServerRunning ? '#45D6A4' : '#B7CDE1')
            .width('100%')
          Text(`当前模型：${this.currentModelName} · 已处理 ${this.apiServerRequestCount} 个请求`)
            .fontSize(11)
            .fontColor('#6F86A0')
            .width('100%')
          if (!this.loaded) {
            Text('请先在模型页加载模型，再启动 API 服务。')
              .fontSize(11)
              .lineHeight(17)
              .fontColor('#F2B35D')
              .width('100%')
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding(10)
        .backgroundColor('#0D1A28')
        .borderRadius(8)

        Column({ space: 6 }) {
          this.SectionTitle('连接设置')
          Row({ space: 8 }) {
            Column({ space: 4 }) {
              this.Label('API 地址（点击下方复制）')
              Row() {
                Text(this.apiServerAddress)
                  .fontSize(12)
                  .fontColor('#5AB0F2')
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .copyOption(CopyOptions.LocalDevice)
              }
              .height(38)
              .width('100%')
              .padding({ left: 10, right: 10 })
              .backgroundColor('#101D2B')
              .borderRadius(8)
              .onClick(async () => {
                await this.copyText(this.apiServerAddress, 'API 地址')
              })
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)

            Column({ space: 4 }) {
              this.Label('端口')
              TextInput({
                text: this.apiServerPortInput,
                placeholder: '8080',
                controller: this.portInputController
              })
                .height(38)
                .width('100%')
                .fontSize(13)
                .fontColor('#EAF4FF')
                .textAlign(TextAlign.Center)
                .inputFilter('[0-9]')
                .enabled(!this.apiServerRunning && !this.apiServerStarting)
                .backgroundColor('#101D2B')
                .borderRadius(8)
                .onChange((value: string) => {
                  this.viewModel.updateApiServerPort(value)
                })
            }
            .width(82)
            .alignItems(HorizontalAlign.Start)
          }
          .width('100%')
          .alignItems(VerticalAlign.Bottom)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding(10)
        .backgroundColor('#0D1A28')
        .borderRadius(8)

        Column({ space: 6 }) {
          Row() {
            this.SectionTitle('访问控制')
            Blank()
            Toggle({ type: ToggleType.Switch, isOn: this.apiServerRequireKey })
              .height(22)
              .enabled(!this.apiServerRunning && !this.apiServerStarting)
              .selectedColor('#45D6A4')
              .onChange((enabled: boolean) => {
                this.viewModel.updateApiServerRequireKey(enabled)
              })
          }
          .height(22)
          .width('100%')
          .alignItems(VerticalAlign.Center)

          if (this.apiServerRequireKey) {
            this.Label('API Key（点击下方复制）')
            Row() {
              Text(this.apiKeyVisible ? this.apiServerKey : '••••••••••••••••••••••••')
                .fontSize(12)
                .fontColor('#EAF4FF')
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
              .height(38)
              .width('100%')
              .padding({ left: 12, right: 12 })
              .backgroundColor('#101D2B')
              .borderRadius(8)
              .onClick(async () => {
                await this.copyText(this.apiServerKey, 'API Key')
              })

            Row({ space: 8 }) {
              Button(this.apiKeyVisible ? '隐藏 API Key' : '显示 API Key')
                .height(30)
                .layoutWeight(1)
                .fontSize(11)
                .fontColor('#F4FBFF')
                .backgroundColor('#26384D')
                .onClick(() => {
                  this.apiKeyVisible = !this.apiKeyVisible
                })
              Button('重新生成')
                .height(30)
                .layoutWeight(1)
                .fontSize(11)
                .fontColor('#8DE4C3')
                .backgroundColor('#12372E')
                .enabled(!this.apiServerRunning && !this.apiServerStarting)
                .onClick(() => {
                  this.viewModel.regenerateApiServerKey()
                })
            }
            .width('100%')
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding(10)
        .backgroundColor('#0D1A28')
        .borderRadius(8)

        Column({ space: 6 }) {
          Row() {
            this.SectionTitle('API 日志')
            Blank()
            Button('清空')
              .height(22)
              .width(64)
              .fontSize(10)
              .fontColor('#8CA2B8')
              .backgroundColor('#101D2B')
              .enabled(this.apiServerLogs.length > 0)
              .onClick(() => {
                this.viewModel.clearApiServerLogs()
              })
          }
          .height(22)
          .width('100%')
          .alignItems(VerticalAlign.Top)

          if (this.apiServerLogs.length <= 0) {
            Text('暂无 API 请求日志')
              .height(120)
              .fontSize(12)
              .fontColor('#5F758C')
              .width('100%')
              .textAlign(TextAlign.Center)
          } else {
            List({ space: 5 }) {
              ForEach(this.logItems(), (item: ApiServerLogEntry) => {
                ListItem() {
                  Row({ space: 7 }) {
                    Text(item.time)
                      .width(50)
                      .fontSize(10)
                      .lineHeight(16)
                      .fontColor('#5F758C')
                      .textAlign(TextAlign.Start)
                    Text(item.level)
                      .width(42)
                      .fontSize(10)
                      .lineHeight(16)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(this.logLevelColor(item.level))
                      .textAlign(TextAlign.Start)
                    Text(item.message)
                      .fontSize(10)
                      .lineHeight(16)
                      .fontColor('#B7CDE1')
                      .layoutWeight(1)
                      .maxLines(2)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                  }
                  .width('100%')
                  .alignItems(VerticalAlign.Top)
                }
              }, (item: ApiServerLogEntry) => `${item.id}`)
            }
            .width('100%')
            .height(180)
            .scrollBar(BarState.Auto)
            .edgeEffect(EdgeEffect.Spring)
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding(10)
        .backgroundColor('#0D1A28')
        .borderRadius(8)

        Column({ space: 6 }) {
          this.SectionTitle('支持的端点')
          Column({ space: 0 }) {
            this.Endpoint('GET', '/v1/models', '#69D38A')
            this.Endpoint('POST', '/v1/chat/completions', '#5AB0F2')
            this.Endpoint('POST', '/v1/responses', '#5AB0F2')
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          Text('当前版本仅支持文本输入和当前已加载模型，同时只处理一个生成请求。App 退出后服务会停止。')
            .fontSize(11)
            .lineHeight(17)
            .fontColor('#6F86A0')
            .width('100%')
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding(10)
        .backgroundColor('#0D1A28')
        .borderRadius(8)
      }
      .width('100%')
      .padding({ bottom: 8 })
      .onClick(() => {
        this.portInputController.stopEditing()
      })
    }
    .width('100%')
    .height('100%')
    .align(Alignment.Top)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
  }
}
