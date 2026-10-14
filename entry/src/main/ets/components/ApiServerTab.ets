import { InputFieldStyle } from './ControlStyles'
import { ActionButtonStyle, CompactActionStyle } from './ButtonStyles'
import { ApiServerLogEntry, ChatViewModel } from '../state/ChatViewModel'
import { pasteboard } from '@kit.BasicServicesKit'
import { ModelType, ModelTypeSelector } from './ModelTypeSelector'

@Component
export struct ApiServerTab {
  private scroller: Scroller = new Scroller()
  onContentScroll: (yOffset: number) => void = (_yOffset: number) => {}
  @Prop extendBottom: boolean = false
  @Prop bottomOverlayInset: number = 0
  @ObjectLink viewModel: ChatViewModel
  @Prop renderVersion: number = 0
  @Prop loaded: boolean = false
  @Prop layaReady: boolean = false
  @Prop apiServiceTarget: 'chat' | 'decision' = 'chat'
  @Prop layaStatus: string = '未安装'
  onApiHelp: (mode: 'chat' | 'decision', example: string) => void = () => {}
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
  private portInputController: TextInputController = new TextInputController()

  private wideLayout(): boolean {
    return this.contentWidth >= 800
  }

  aboutToAppear(): void {
    this.viewModel.refreshApiServerAddress()
  }

  @Builder
  private Label(text: string) {
    Text(text)
      .fontSize(12)
      .lineHeight(18)
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

  private decisionExample(): string {
    return `{
  "model": "Laya-Multilingual-MNN-FP16",
  "input": "手机键盘弹出后底部标签也跟着上移。",
  "task": {
    "type": "choice",
    "instruction": "这段反馈主要描述哪一类问题？",
    "options": { "ui": "页面布局或交互", "other": "其他问题" }
  }
}`
  }


  private serviceName(): string {
    if (this.apiServiceTarget === 'decision') return 'Laya-Multilingual-MNN-FP16'
    return this.currentModelName
  }

  private serviceState(): string {
    if (this.apiServiceTarget === 'decision') return this.layaStatus
    return this.loaded ? '已加载' : '未加载'
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

  @Builder
  private CapabilitiesCard() {
    Column({ space: 8 }) {
      Row() {
        this.SectionTitle('服务内容')
        Blank()
        Button('调用说明')
          .attributeModifier(new CompactActionStyle())
          .onClick(() => {
            const example = this.apiServiceTarget === 'decision' ? this.decisionExample() : ''
            this.onApiHelp(this.apiServiceTarget, example)
          })
      }.width('100%')
      ModelTypeSelector({
        selected: this.apiServiceTarget,
        interactionEnabled: !this.apiServerRunning && !this.apiServerStarting,
        onChange: (type: ModelType): void => { this.viewModel.selectApiServiceTarget(type) }
      })
      .width('100%')
      Text(this.serviceName())
        .fontSize(13).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_body'))
      Text(this.serviceState())
        .fontSize(12).fontColor($r('app.color.text_secondary'))
      if (this.apiServiceTarget === 'chat') {
        this.Endpoint('GET', '/v1/models', $r('app.color.endpoint_post'))
        this.Endpoint('POST', '/v1/chat/completions', $r('app.color.link'))
        this.Endpoint('POST', '/v1/responses', $r('app.color.link'))
      } else if (this.apiServiceTarget === 'decision') {
        this.Endpoint('GET', '/v1/models', $r('app.color.endpoint_post'))
        this.Endpoint('POST', '/v1/decisions', $r('app.color.link'))

      }
      Text(this.apiServerRunning ? '切换服务内容前，请先关闭服务。' : '服务启动后，只接收所选内容的请求。')
        .fontSize(12).lineHeight(18).fontColor($r('app.color.text_hint')).width('100%')
    }
    .width('100%').alignItems(HorizontalAlign.Start).padding(10)
    .backgroundColor($r('app.color.card')).borderRadius($r('app.float.card_radius'))
  }

  @Builder
  private ServiceSettings() {
    Column({ space: 10 }) {
      Column({ space: 6 }) {
        Row() {
          this.SectionTitle('服务状态')
          Blank()
          Button({ type: ButtonType.Normal }) {
            Toggle({ type: ToggleType.Switch, isOn: this.apiServerRunning })
              .height(22)
              .margin(0)
              .selectedColor($r('app.color.status_good'))
              .focusable(false)
              .accessibilityLevel('no')
          }
            .height(22)
            .padding(0)
            .backgroundColor(Color.Transparent)
            .stateEffect(false)
            .hitTestBehavior(HitTestMode.Block)
            .accessibilityText('API 服务')
            .accessibilityDescription(this.apiServerRunning ? '已开启' : '已关闭')
            .enabled(!this.apiServerStarting && (!this.busy || this.apiServerRunning))
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
        Text(`服务内容：${this.serviceName()}`)
          .fontSize(12)
          .lineHeight(18)
          .fontColor($r('app.color.text_hint'))
          .width('100%')
        Text(`累计处理 ${this.apiServerRequestCount} 个 API 请求`)
          .fontSize(12)
          .lineHeight(18)
          .fontColor($r('app.color.text_hint'))
          .width('100%')
        if ((this.apiServiceTarget === 'chat' && !this.loaded) || (this.apiServiceTarget === 'decision' && !this.layaReady)) {
          Text(this.apiServiceTarget === 'chat' ? '开启服务时可选择并加载聊天模型。' : '请先在模型页的决策分类中安装 Laya。')
            .fontSize(12)
            .lineHeight(18)
            .fontColor($r('app.color.status_warning'))
            .width('100%')
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding(10)
      .backgroundColor($r('app.color.card'))
      .borderRadius($r('app.float.card_radius'))

      this.CapabilitiesCard()

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
            .backgroundColor($r('app.color.input_background'))
            .borderRadius($r('app.float.button_radius'))
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
          this.SectionTitle('API 认证')
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

        this.Label('开启后，调用 API 需携带有效的 API Key。')

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
    .width('100%')
  }

  @Builder
  private ServiceActivity() {
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
            .height(this.wideLayout() ? undefined : 120)
            .layoutWeight(this.wideLayout() ? 1 : 0)
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
          .height(this.wideLayout() ? undefined : 180)
          .layoutWeight(this.wideLayout() ? 1 : 0)
          .constraintSize({ minHeight: 0 })
          .scrollBar(BarState.Auto)
          .edgeEffect(EdgeEffect.Spring)
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding(10)
      .backgroundColor($r('app.color.card'))
      .borderRadius($r('app.float.card_radius'))
      .layoutWeight(this.wideLayout() ? 1 : 0)
      .constraintSize({ minHeight: 0 })

    }
    .width('100%')
    .height(this.wideLayout() ? '100%' : undefined)
  }

  build() {
    Column({ space: 10 }) {
      Text('让其他应用通过 API 调用本机模型')
        .width('100%').lineHeight(18).fontSize(12).fontColor($r('app.color.text_muted'))
        .padding({ left: 11, bottom: 4 })
      if (this.wideLayout()) {
        Row({ space: 16 }) {
          Scroll() {
            this.ServiceSettings()
          }.layoutWeight(1).height('100%').scrollBar(BarState.Auto).align(Alignment.Top)
            .edgeEffect(EdgeEffect.Spring)
          Column() {
            this.ServiceActivity()
          }.layoutWeight(1).height('100%')
        }.width('100%').layoutWeight(1)
      } else {
        Scroll(this.scroller) {
          Column({ space: 10 }) {
            this.ServiceSettings()
            this.ServiceActivity()
          }.width('100%')
            .padding({ bottom: $r('app.float.page_scroll_bottom_padding') })
            .margin({ bottom: this.bottomOverlayInset })
        }.width('100%').layoutWeight(1).scrollBar(BarState.Off).align(Alignment.Top)
          .onWillScroll((_xOffset: number, yOffset: number, _scrollState: ScrollState, source: ScrollSource) => {
            if (source !== ScrollSource.EDGE_EFFECT) this.onContentScroll(yOffset)
          })
          .edgeEffect(EdgeEffect.Spring)
      }
    }.width('100%').height('100%')
      .padding({ bottom: this.wideLayout() ? 12 : 0 })
      .onAreaChange((_oldArea: Area, newArea: Area) => {
        this.contentWidth = Number(newArea.width)
      })
      .onClick(() => this.portInputController.stopEditing())
      .expandSafeArea([SafeAreaType.SYSTEM], this.extendBottom ? [SafeAreaEdge.BOTTOM] : [])
  }
}
