import { ColorMetrics } from '@kit.ArkUI'
import { MarkdownSpan, parseInlineMarkdown } from '../utils/markdown'
import { FadingMarkdownSpan, StreamingTextFade } from '../utils/streamingTextFade'

@Component
export struct StreamingText {
  @Prop @Watch('updateText') text: string = ''
  @Prop @Watch('updateText') streaming: boolean = false
  @Prop inlineMarkdown: boolean = true
  @Prop inlineCode: boolean = false
  @Prop bold: boolean = false
  @Prop color: ResourceColor = $r('app.color.text_body')
  @Prop textSize: number = 14
  @Prop textLineHeight: number = 21
  onSelectionChange: (start: number, end: number) => void = () => {}
  onOpenLink: (url: string) => void = () => {}
  @State private parts: FadingMarkdownSpan[] = []
  private fade: StreamingTextFade = new StreamingTextFade()
  private fadeTimer: number = -1

  aboutToAppear(): void {
    this.updateText()
  }

  aboutToDisappear(): void {
    this.stopFadeTimer()
  }

  private inlineSpans(): MarkdownSpan[] {
    return this.inlineMarkdown ? parseInlineMarkdown(this.text, this.streaming) : [{ text: this.text, bold: false }]
  }

  private updateText(): void {
    const now = Date.now()
    const plain = this.inlineSpans().map((span: MarkdownSpan) => span.text).join('')
    this.fade.update(plain, this.streaming, now)
    this.parts = this.fade.spans(this.inlineSpans(), now)
    if (!this.fade.active(now)) {
      this.stopFadeTimer()
      return
    }
    if (this.fadeTimer >= 0) return
    // Only this native Text's colors change between text commits. Markdown is cached.
    this.fadeTimer = setInterval(() => {
      const now = Date.now()
      this.parts = this.fade.spans(this.inlineSpans(), now)
      if (!this.fade.active(now)) this.stopFadeTimer()
    }, 16)
  }

  private stopFadeTimer(): void {
    if (this.fadeTimer >= 0) clearInterval(this.fadeTimer)
    this.fadeTimer = -1
  }

  private spanColor(part: FadingMarkdownSpan): ResourceColor {
    const color = part.span.code && this.inlineCode ? $r('app.color.code_text') :
      (part.span.link ? $r('app.color.link_markdown') : this.color)
    if (part.opacity >= 1) return color
    try {
      const value = ColorMetrics.resourceColor(color)
      return ColorMetrics.rgba(value.red, value.green, value.blue, value.alpha / 255 * part.opacity).color
    } catch (_) {
      return color
    }
  }

  build() {
    Text() {
      ForEach(this.parts, (_part: FadingMarkdownSpan, index: number) => {
        Span(this.parts[index].span.text)
          .fontColor(this.spanColor(this.parts[index]))
          .fontWeight(this.bold || this.parts[index].span.bold ? FontWeight.Bold : FontWeight.Normal)
          .fontStyle(this.parts[index].span.italic ? FontStyle.Italic : FontStyle.Normal)
          .fontFamily(this.parts[index].span.code && this.inlineCode ? 'monospace' : 'HarmonyOS Sans')
          .fontSize(this.parts[index].span.code && this.inlineCode ? 13 : this.textSize)
          .decoration({ type: this.parts[index].span.link ? TextDecorationType.Underline :
            (this.parts[index].span.strikethrough ? TextDecorationType.LineThrough : TextDecorationType.None) })
          .onClick(() => {
            if (this.parts[index].span.link) this.onOpenLink(this.parts[index].span.link ?? '')
          })
      }, (_part: FadingMarkdownSpan, index: number) => `${index}`)
    }
    .onTextSelectionChange((start: number, end: number) => this.onSelectionChange(start, end))
    .copyOption(CopyOptions.LocalDevice)
    .textSelectable(TextSelectableMode.SELECTABLE_FOCUSABLE)
    .width('100%')
    .fontSize(this.textSize)
    .lineHeight(this.textLineHeight)
    .textAlign(TextAlign.Start)
  }
}
