import { ChatContextOmission, ChatContextSnapshot, ChatTurn } from '../models/ChatTypes'
import { dialogFade, dialogScale } from './DialogMotion'
import { parseAssistantText } from '../utils/thinking'

interface ContextDisplayEntry {
  key: string
  title: string
  content: string
  reason: string
}

interface ContextRound {
  question: string
  answer: string
  current: boolean
  hasImage: boolean
}

class ContextEntries implements IDataSource {
  private entries: ContextDisplayEntry[]
  private listeners: DataChangeListener[] = []
  constructor(entries: ContextDisplayEntry[]) { this.entries = entries }
  totalCount(): number { return this.entries.length }
  getData(index: number): ContextDisplayEntry { return this.entries[index] }
  registerDataChangeListener(listener: DataChangeListener): void { this.listeners.push(listener) }
  unregisterDataChangeListener(listener: DataChangeListener): void {
    this.listeners = this.listeners.filter((item: DataChangeListener) => item !== listener)
  }
  replace(entries: ContextDisplayEntry[]): void {
    this.entries = entries
    this.listeners.forEach((listener: DataChangeListener) => listener.onDataReloaded())
  }
}

function roleTitle(role: string): string {
  if (role === 'system') return '系统提示词'
  if (role === 'user') return '你的问题'
  if (role === 'assistant') return '模型回答'
  return '应用提示'
}

@Component
export struct ChatContextDialog {
  @Prop snapshot: ChatContextSnapshot
  @Prop availableWidth: number = 360
  @Prop availableHeight: number = 640
  onClose: () => void = () => {}
  @State private showOmitted: boolean = false
  @State private showInstructions: boolean = false
  private entries: ContextEntries = new ContextEntries([])
  @State private closePressed: boolean = false

  aboutToAppear(): void {
    this.entries.replace(this.snapshot.omitted.filter((item: ChatContextOmission) => item.reason !== '应用提示')
      .map((item: ChatContextOmission, index: number): ContextDisplayEntry => {
        const parts = item.role === 'assistant' ? parseAssistantText(item.content) : undefined
        const thinkingOnly = parts !== undefined && parts.hasThinking && parts.answer.trim().length === 0
        return {
          key: `omitted-${index}`, title: thinkingOnly ? '思考内容' : roleTitle(item.role),
          content: parts !== undefined && parts.hasThinking ? (thinkingOnly ? parts.thinking : parts.answer) : item.content,
          reason: item.reason
        }
      }))
  }

  private conversationTurns(): ChatTurn[] {
    return this.snapshot.turns.filter((turn: ChatTurn) => turn.role !== 'system')
  }

  private instructions(): string {
    return this.snapshot.turns.filter((turn: ChatTurn) => turn.role === 'system')
      .map((turn: ChatTurn) => turn.content).join('\n\n')
  }

  private conversationRounds(): ContextRound[] {
    const rounds: ContextRound[] = []
    const turns = this.conversationTurns()
    turns.forEach((turn: ChatTurn, index: number) => {
      if (turn.role === 'user') {
        rounds.push({ question: turn.content, answer: '', current: index === turns.length - 1,
          hasImage: (turn.imageUri ?? '').length > 0 })
      } else if (turn.role === 'assistant') {
        if (rounds.length === 0) rounds.push({ question: '', answer: turn.content, current: false, hasImage: false })
        else rounds[rounds.length - 1].answer = turn.content
      }
    })
    return rounds
  }

  @Builder
  private RoundCard(round: ContextRound) {
    Column({ space: 12 }) {
      if (round.question.length > 0 || round.current) {
        Column({ space: 6 }) {
          Text(round.current ? '本次问题' : '你的问题').fontSize(12).fontWeight(FontWeight.Medium)
            .fontColor(round.current ? $r('app.color.tag_blue_text') : $r('app.color.text_muted'))
          Text(round.question).fontSize(14).lineHeight(22).fontColor($r('app.color.text_body'))
            .copyOption(CopyOptions.InApp).width('100%')
        }.width('100%').alignItems(HorizontalAlign.Start)
      }
      if (round.answer.length > 0) {
        Divider().color($r('app.color.border'))
        Column({ space: 6 }) {
          Text('模型回答').fontSize(12).fontColor($r('app.color.text_muted'))
          Text(round.answer).fontSize(14).lineHeight(22).fontColor($r('app.color.text_body'))
            .copyOption(CopyOptions.InApp).width('100%')
        }.width('100%').alignItems(HorizontalAlign.Start)
      }
      if (round.hasImage) {
        Text('附有图片').fontSize(12).fontColor($r('app.color.text_secondary'))
      }
    }.width('100%').padding(14).alignItems(HorizontalAlign.Start)
      .backgroundColor(round.current ? $r('app.color.nav_selected_background') : $r('app.color.page_compact'))
      .borderRadius($r('app.float.card_radius'))
  }

  @Builder
  private Disclosure(title: string, expanded: boolean, action: () => void) {
    Button({ type: ButtonType.Normal }) {
      Row() {
        Text(title).fontSize(13).fontColor($r('app.color.text_secondary')).layoutWeight(1).textAlign(TextAlign.Start)
        Image($r('app.media.icon_message_previous')).width(14).height(14)
          .fillColor($r('app.color.text_muted')).rotate({ angle: expanded ? 90 : 270 })
      }.width('100%')
    }.height(36).width('100%').padding(0).backgroundColor(Color.Transparent)
      .hoverEffect(HoverEffect.Auto).borderRadius($r('app.float.button_radius'))
      .accessibilityText(`${expanded ? '收起' : '展开'}${title}`)
      .onClick(() => {
        this.getUIContext().animateTo({ duration: 220, curve: Curve.EaseInOut }, action)
      })
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Column().width('100%').height('100%').backgroundColor($r('app.color.scrim'))
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        .onClick(() => this.onClose())
      Column({ space: 14 }) {
        Row() {
          Text('对话上下文').fontSize(20).fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_title')).layoutWeight(1)
          Button({ type: ButtonType.Normal }) {
            Image(this.closePressed ? $r('app.media.model_market_close_icon_pressed') : $r('app.media.model_market_close_icon'))
              .width(24).height(24)
          }.width(40).height(40).backgroundColor(Color.Transparent).hoverEffect(HoverEffect.Auto)
            .accessibilityText('关闭上下文').onClick(() => this.onClose())
            .onTouch((event: TouchEvent) => {
              if (event.type === TouchType.Down) this.closePressed = true
              else if (event.type === TouchType.Up || event.type === TouchType.Cancel) this.closePressed = false
            })
        }.width('100%')
        Text('以下内容用于生成最近一次回答。').fontSize(13)
          .fontColor($r('app.color.text_secondary')).width('100%')
        Scroll() {
          Column({ space: 18 }) {
            Column() {
              ForEach(this.conversationRounds(), (round: ContextRound, index: number) => {
                if (index > 0) {
                  Column().width(1).height(12).backgroundColor($r('app.color.border'))
                }
                this.RoundCard(round)
              }, (_round: ContextRound, index: number) => `round-${index}`)
            }.width('100%')
            if (this.entries.totalCount() > 0) {
              this.Disclosure(`未带入的消息（${this.entries.totalCount()}）`, this.showOmitted,
                () => { this.showOmitted = !this.showOmitted })
            }
            if (this.showOmitted) {
              List({ space: 10 }) {
                LazyForEach(this.entries, (entry: ContextDisplayEntry) => {
                  ListItem() {
                    Column({ space: 8 }) {
                      Text(entry.title).fontSize(13).fontWeight(FontWeight.Medium)
                        .fontColor($r('app.color.text_title')).width('100%')
                      if (entry.reason.length > 0) {
                        Text(entry.reason).fontSize(12).fontColor($r('app.color.text_muted')).width('100%')
                      }
                      Text(entry.content).fontSize(14).lineHeight(22).fontColor($r('app.color.text_secondary'))
                        .copyOption(CopyOptions.InApp).width('100%')
                    }.width('100%')
                  }
                }, (entry: ContextDisplayEntry): string => entry.key)
              }.width('100%').height(Math.max(80, Math.min(240, this.availableHeight - 260))).scrollBar(BarState.Auto)
                .transition(TransitionEffect.OPACITY)
            }
            if (this.instructions().length > 0) {
              this.Disclosure('查看系统提示词', this.showInstructions, () => { this.showInstructions = !this.showInstructions })
              if (this.showInstructions) {
                Text(this.instructions()).fontSize(13).lineHeight(20).fontColor($r('app.color.text_secondary'))
                  .copyOption(CopyOptions.InApp).width('100%')
                  .transition(TransitionEffect.OPACITY)
              }
            }
          }.width('100%').alignItems(HorizontalAlign.Start)
        }.width('100%').align(Alignment.TopStart).scrollBar(BarState.Auto)
          .constraintSize({ maxHeight: Math.max(80, Math.min(480, this.availableHeight - 180)) })
      }.width(Math.max(1, Math.min(640, this.availableWidth - 32))).padding(20)
        .constraintSize({ maxHeight: Math.max(1, this.availableHeight - 32) })
        .backgroundColor($r('app.color.dialog')).border({ width: 1, color: $r('app.color.border') })
        .borderRadius($r('app.float.dialog_radius')).transition(dialogScale())
    }.width('100%').height('100%').transition(dialogFade())
  }
}
