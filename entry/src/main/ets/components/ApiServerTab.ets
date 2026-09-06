import { InputFieldStyle } from './ControlStyles'
import { ActionButtonStyle, CompactActionStyle } from './ButtonStyles'
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
  @State private contentWidth: number = 0
  @State private viewportHeight: number = 0
  private portInputController: TextInputController = new TextInputController()

  private wideLayout(): boolean {
    return this.contentWidth >= 800
  }

  private columnWidth(): number {
    return this.wideLayout() ? (this.contentWidth - 16) / 2 : this.contentWidth
  }

  private logHeight(): number {
    return this.wideLayout() ? Math.max(240, Math.min(640, this.viewportHeight - 48)) : 180
  }

  aboutToAppear(): void {
    this.viewModel.refreshApiServerAddress()
  }

  @Builder
  private Label(text: string) {
    Text(text)
      .fontSize(12)
      .fontColor($r('app.color.text_muted'))
      .width('100%')
  }

  @Builder
  private SectionTitle(text: string) {
    Text(text)
      .fontSize(16)
      .lineHeight(22)
      .fontWeight(FontWeight.Bold)
      .fontColor($r('app.color.text_title'))
  }

  private logLevelColor(level: string): ResourceColor {
    if (level === 'ERROR') {
      return $r('app.color.status_error_alt')
    }
    if (level === 'RESP') {
      return $r('app.color.endpoint_post')
    }
    if (level === 'REQ') {
      return $r('app.color.link')
    }
    return $r('app.color.text_muted')
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
  private Endpoint(method: string, path: string, methodColor: ResourceColor) {
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
        .fontColor($r('app.color.text_secondary'))
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
            .fontColor($r('app.color.text_muted'))
        }
        .width('100%')
        .padding({ left: 4, bottom: 4 })

        Flex({ direction: this.wideLayout() ? FlexDirection.Row : FlexDirection.Column }) {
          Column({ space: 10 }) {
            Column({ space: 6 }) {
              Row() {
                this.SectionTitle('服务状态')
                Blank()
                Toggle({ type: ToggleType.Switch, isOn: this.apiServerRunning })
                  .height(22)
                  .enabled(!this.apiServerStarting && (!this.busy || this.apiServerRunning))
                  .selectedColor($r('app.color.status_good'))
                  .onClick(() => {
                    this.viewModel.setApiServerEnabled(!this.apiServerRunning)
                  })
              }
              .height(22)
              .width('100%')
              .alignItems(VerticalAlign.Center)
              Text(this.apiServerStatus)
                .fontSize(13)
                .lineHeight(19)
                .fontColor(this.apiServerRunning ? $r('app.color.status_good') : $r('app.color.text_secondary'))
                .width('100%')
              Text(`当前模型：${this.currentModelName} · 已处理 ${this.apiServerRequestCount} 个请求`)
                .fontSize(11)
                .fontColor($r('app.color.text_hint'))
                .width('100%')
              if (!this.loaded) {
                Text('请先在模型页加载模型，再启动 API 服务。')
                  .fontSize(11)
                  .lineHeight(17)
                  .fontColor($r('app.color.status_warning'))
                  .width('100%')
              }
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
            .padding(10)
            .backgroundColor($r('app.color.card'))
            .borderRadius($r('app.float.card_radius'))

            Column({ space: 6 }) {
              this.SectionTitle('连接设置')
              Row({ space: 8 }) {
                Column({ space: 4 }) {
                  this.Label('API 地址（点击下方复制）')
                  Row() {
                    Text(this.apiServerAddress)
                      .fontSize(12)
                      .fontColor($r('app.color.link'))
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .copyOption(CopyOptions.LocalDevice)
                  }
                  .height(38)
                  .width('100%')
                  .padding({ left: 10, right: 10 })
                  .backgroundColor($r('app.color.inset'))
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
                    .attributeModifier(new InputFieldStyle())
                    .height(38)
                    .width('100%')
                    .fontSize(13)
                    .textAlign(TextAlign.Center)
                    .inputFilter('[0-9]')
                    .enabled(!this.apiServerRunning && !this.apiServerStarting)
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
            .backgroundColor($r('app.color.card'))
            .borderRadius($r('app.float.card_radius'))

            Column({ space: 6 }) {
              Row() {
                this.SectionTitle('访问控制')
                Blank()
                Toggle({ type: ToggleType.Switch, isOn: this.apiServerRequireKey })
                  .height(22)
                  .enabled(!this.apiServerRunning && !this.apiServerStarting)
                  .selectedColor($r('app.color.status_good'))
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
                    .fontColor($r('app.color.text_body'))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
                  .height(38)
                  .width('100%')
                  .padding({ left: 12, right: 12 })
                  .backgroundColor($r('app.color.inset'))
                  .borderRadius(8)
                  .onClick(async () => {
                    await this.copyText(this.apiServerKey, 'API Key')
                  })

                Row({ space: 8 }) {
                  Button(this.apiKeyVisible ? '隐藏 API Key' : '显示 API Key')
                    .attributeModifier(new ActionButtonStyle($r('app.color.button_secondary_background'), $r('app.color.button_secondary_text')))
                    .layoutWeight(1)
                    .onClick(() => {
                      this.apiKeyVisible = !this.apiKeyVisible
                    })
                  Button('重新生成')
                    .attributeModifier(new ActionButtonStyle($r('app.color.button_secondary_background'), $r('app.color.button_secondary_text')))
                    .layoutWeight(1)
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
            .backgroundColor($r('app.color.card'))
            .borderRadius($r('app.float.card_radius'))

          }
          .width(this.columnWidth())
          .flexShrink(0)
          .margin({ right: this.wideLayout() ? 16 : 0, bottom: this.wideLayout() ? 0 : 10 })

          Column({ space: 10 }) {
            Column({ space: 6 }) {
              Row() {
                this.SectionTitle('API 日志')
                Blank()
                Button('清空')
                  .attributeModifier(new CompactActionStyle())
                  .width(64)
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
                  .height(this.wideLayout() ? 240 : 120)
                  .fontSize(12)
                  .fontColor($r('app.color.text_log_time'))
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
                          .fontColor($r('app.color.text_log_time'))
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
                          .fontColor($r('app.color.text_secondary'))
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
                .height(this.logHeight())
                .scrollBar(BarState.Auto)
                .edgeEffect(EdgeEffect.Spring)
              }
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
            .padding(10)
            .backgroundColor($r('app.color.card'))
            .borderRadius($r('app.float.card_radius'))

            Column({ space: 6 }) {
              this.SectionTitle('支持的端点')
              Column({ space: 0 }) {
                this.Endpoint('GET', '/v1/models', $r('app.color.endpoint_post'))
                this.Endpoint('POST', '/v1/chat/completions', $r('app.color.link'))
                this.Endpoint('POST', '/v1/responses', $r('app.color.link'))
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)
              Text('当前版本仅支持文本输入和当前已加载模型，同时只处理一个生成请求。App 退出后服务会停止。')
                .fontSize(11)
                .lineHeight(17)
                .fontColor($r('app.color.text_hint'))
                .width('100%')
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
            .padding(10)
            .backgroundColor($r('app.color.card'))
            .borderRadius($r('app.float.card_radius'))
          }
          .width(this.columnWidth())
          .flexShrink(0)
        }
        .width('100%')
      }
      .width('100%')
      .padding({ bottom: 8 })
      .onClick(() => {
        this.portInputController.stopEditing()
      })
    }
    .width('100%')
    .height('100%')
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      this.contentWidth = Number(newArea.width)
      this.viewportHeight = Number(newArea.height)
    })
    .align(Alignment.Top)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
  }
}
