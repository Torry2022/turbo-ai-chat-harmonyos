import { dialogFade, dialogScale } from './DialogMotion'
import { ActionButtonStyle } from './ButtonStyles'
import { pasteboard } from '@kit.BasicServicesKit'

@Component
export struct ApiUsageDialog {
  @Prop mode: string = 'chat'
  @Prop example: string = ''
  @Prop availableWidth: number = 600
  @Prop availableHeight: number = 640
  @State private isClosePressed: boolean = false
  onClose: () => void = () => {}

  private async copyExample(): Promise<void> {
    try {
      await pasteboard.getSystemPasteboard().setData(
        pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, this.example))
      this.getUIContext().getPromptAction().showToast({ message: '示例已复制', duration: 1500 })
    } catch (_) {
      this.getUIContext().getPromptAction().showToast({ message: '复制失败', duration: 1500 })
    }
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Column().width('100%').height('100%')
        .backgroundColor($r('app.color.scrim'))
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        .onClick(() => this.onClose())
      Column({ space: 16 }) {
        Row() {
          Text('调用说明')
            .fontSize(20).fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_title')).layoutWeight(1)
          Button({ type: ButtonType.Normal }) {
            Image(this.isClosePressed ? $r('app.media.model_market_close_icon_pressed') :
              $r('app.media.model_market_close_icon'))
              .width(24).height(24)
          }
          .width(40).height(40).backgroundColor(Color.Transparent)
          .accessibilityText('关闭调用说明')
          .hoverEffect(HoverEffect.Auto)
          .onTouch((event: TouchEvent) => {
            this.isClosePressed = event.type === TouchType.Down
          })
          .onClick(() => this.onClose())
        }.width('100%')
        Scroll() {
          Column({ space: 14 }) {
            Text(this.mode === 'rerank' ? '本地重排 API' : this.mode === 'decision' ? 'Laya 决策 API' : 'OpenAI 兼容聊天 API')
              .fontSize(14).fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_title')).width('100%')
            Text(this.mode === 'rerank' ?
              '向 /v1/rerank 发送 POST 请求。query 为问题，documents 为候选文本数组，top_n 为可选的返回数量。结果按相关性降序排列，index 对应输入位置（从 0 开始）。需先在模型页加载重排模型。' : this.mode === 'decision' ?
              '向 API 地址后的 /v1/decisions 发送 POST 请求，Content-Type 设为 application/json。需先在模型页安装并加载决策模型。下方为选择题的请求体示例。' :
                '在 Cherry Studio 等客户端中选择 OpenAI 兼容服务，填入本页 API 地址和 API Key，通过 GET /v1/models 获取模型列表。聊天需先在模型页加载模型，支持 Chat Completions 和 Responses 请求。')
              .fontSize(13).lineHeight(21).fontColor($r('app.color.text_secondary')).width('100%')
            if (this.mode !== 'chat') {
              Text(this.example)
                .fontSize(12).lineHeight(20).fontFamily('monospace')
                .fontColor($r('app.color.text_body')).copyOption(CopyOptions.LocalDevice)
                .width('100%').padding(14)
                .backgroundColor($r('app.color.inset')).borderRadius($r('app.float.card_radius'))
            }
            Text('运行状态：GET /turbo/runtime 返回 CPU、内存、温度、存储占用及聊天、重排模型状态。生成期间也可查询，无需切换到监控页。')
              .fontSize(13).lineHeight(21).fontColor($r('app.color.text_secondary')).width('100%')
            Text('启用 API 认证时，请使用服务页的 API Key。请求头格式为 Authorization: Bearer <API Key>。')
              .fontSize(12).lineHeight(20).fontColor($r('app.color.text_muted')).width('100%')
          }.width('100%').alignItems(HorizontalAlign.Start)
        }.width('100%').align(Alignment.TopStart)
          // Reserve the outer margin, padding, header and optional footer button.
          .constraintSize({ maxHeight: Math.max(1, this.availableHeight - (this.mode === 'chat' ? 136 : 192)) })
          .scrollBar(BarState.Auto)
        if (this.mode !== 'chat') {
          Button('复制示例')
            .attributeModifier(new ActionButtonStyle($r('app.color.button_secondary_background'), $r('app.color.button_secondary_text')))
            .width('100%').onClick(() => { this.copyExample() })
        }
      }
      .padding(24)
      .width(Math.max(1, Math.min(560, this.availableWidth - 32)))
      .constraintSize({ maxHeight: Math.max(1, this.availableHeight - 32) })
      .backgroundColor($r('app.color.dialog'))
      .border({ width: 1, color: $r('app.color.border') })
      .borderRadius($r('app.float.dialog_radius'))
      .transition(dialogScale())
    }.width('100%').height('100%').transition(dialogFade())
  }
}
