import { CompactActionStyle } from './ButtonStyles'
import { ChatMessage } from '../models/ChatTypes'
import { MarkdownBlock, MarkdownSpan, parseInlineMarkdown, parseLightMarkdown } from '../utils/markdown'
import { parseAssistantText } from '../utils/thinking'
import { pasteboard } from '@kit.BasicServicesKit'
import { common } from '@kit.AbilityKit'

@Component
export struct MessageBubble {
  message: ChatMessage = {
    id: 0,
    role: 'assistant',
    content: '',
    imageUri: '',
    time: '',
    includeInContext: false,
    thinkingExpanded: false
  }
  onToggleThinking: (messageId: number) => void = (_messageId: number) => {}

  private async copyToClipboard(): Promise<void> {
    const text = this.answerText()
    try {
      const pasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text)
      await pasteboard.getSystemPasteboard().setData(pasteData)
    } catch (_) {
      // clipboard may be unavailable
    }
  }

  private hasThinking(): boolean {
    return parseAssistantText(this.message.content).hasThinking
  }

  private thinkingText(): string {
    return parseAssistantText(this.message.content).thinking
  }

  private answerText(): string {
    if (this.message.role !== 'assistant') {
      return this.message.content
    }
    return parseAssistantText(this.message.content).answer
  }

  private thinkingClosed(): boolean {
    return parseAssistantText(this.message.content).thinkingClosed
  }

  private showLinkToast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message, duration: 1800, bottom: 80 })
    } catch (_) {
    }
  }

  private confirmOpenLink(link: string): void {
    const url = link.trim()
    const promptAction = this.getUIContext().getPromptAction()
    if (!/^https?:\/\//i.test(url)) {
      this.showLinkToast('仅支持打开 HTTP/HTTPS 链接')
      return
    }
    promptAction.showDialog({
      title: '使用系统浏览器打开？',
      message: url,
      buttons: [
        { text: '取消', color: $r('app.color.text_muted') },
        { text: '打开', color: $r('app.color.link_markdown'), primary: true }
      ]
    }).then((result) => {
      if (result.index !== 1) {
        return
      }
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext
      context.openLink(url).catch(() => {
        this.showLinkToast('无法打开该链接')
      })
    }).catch(() => {
    })
  }

  @Builder
  private MarkdownLine(text: string, color: ResourceColor = $r('app.color.text_body')) {
    Text() {
      ForEach(parseInlineMarkdown(text), (span: MarkdownSpan) => {
        if (span.code) {
          Span(span.text)
            .fontColor($r('app.color.code_text'))
            .fontFamily('monospace')
            .fontSize(13)
            .decoration({ type: TextDecorationType.None })
        } else if (span.link !== undefined && span.link.length > 0) {
          Span(span.text)
            .fontColor($r('app.color.link_markdown'))
            .decoration({ type: TextDecorationType.Underline })
            .fontWeight(FontWeight.Normal)
            .onClick(() => this.confirmOpenLink(span.link ?? ''))
        } else {
          Span(span.text)
            .fontWeight(span.bold ? FontWeight.Bold : FontWeight.Normal)
            .fontColor(color)
            .fontStyle(span.italic ? FontStyle.Italic : FontStyle.Normal)
            .decoration({ type: span.strikethrough ? TextDecorationType.LineThrough : TextDecorationType.None })
        }
      }, (_span: MarkdownSpan, index: number) => `${index}`)
    }
    .width('100%')
    .fontSize(14)
    .lineHeight(21)
    .textAlign(TextAlign.Start)
  }

  @Builder
  private MarkdownBlock(block: MarkdownBlock, blockIndex: number) {
    if (block.type === 'heading') {
      Text() {
        ForEach(parseInlineMarkdown(block.text), (span: MarkdownSpan) => {
          if (span.link !== undefined && span.link.length > 0) {
            Span(span.text)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.link_markdown'))
              .fontStyle(FontStyle.Normal)
              .decoration({ type: TextDecorationType.Underline })
              .onClick(() => this.confirmOpenLink(span.link ?? ''))
          } else {
            Span(span.text)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_title'))
              .fontStyle(FontStyle.Normal)
          }
        }, (_span: MarkdownSpan, index: number) => `${blockIndex}-${index}`)
      }
      .width('100%')
      .fontSize(15)
      .lineHeight(22)
      .textAlign(TextAlign.Start)
    } else if (block.type === 'code') {
      Stack({ alignContent: Alignment.TopEnd }) {
        Text(block.text)
          .width('100%')
          .fontSize(13)
          .lineHeight(19)
          .fontColor($r('app.color.code_text'))
          .fontFamily('monospace')
          .padding({ top: 44, bottom: 8, left: 8, right: 8 })
          .backgroundColor($r('app.color.code_background'))
          .borderRadius($r('app.float.card_radius'))
        Button('复制')
          .attributeModifier(new CompactActionStyle())
          .padding({ left: 8, right: 8 })
          .margin({ top: 9, right: 4 })
          .onClick(async () => {
            try {
              const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, block.text)
              await pasteboard.getSystemPasteboard().setData(data)
            } catch (_) {}
          })
      }
      .width('100%')
    } else if (block.type === 'blockquote') {
      Row() {
        this.MarkdownLine(block.text, $r('app.color.text_secondary'))
      }
      .width('100%')
      .padding({ left: 11, top: 4, bottom: 4 })
      .border({ width: { left: 3 }, color: $r('app.color.quote_border') })
      .backgroundColor($r('app.color.quote_background'))
      .borderRadius(4)
    } else if (block.type === 'table') {
      Column({ space: 0 }) {
        if (block.headers !== undefined) {
          Row() {
            ForEach(block.headers, (h: string) => {
              Column() {
                this.MarkdownLine(h, $r('app.color.text_title'))
              }
              .padding({ left: 8, right: 8, top: 4, bottom: 4 })
              .layoutWeight(1)
            }, (_h: string, hi: number) => `h-${blockIndex}-${hi}`)
          }
          .width('100%')
          .backgroundColor($r('app.color.table_header'))
        }
        if (block.rows !== undefined) {
          ForEach(block.rows, (row: string[], ri: number) => {
            Row() {
              ForEach(row, (cell: string) => {
                Column() {
                  this.MarkdownLine(cell, $r('app.color.code_text'))
                }
                .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                .layoutWeight(1)
              }, (_cell: string, ci: number) => `c-${blockIndex}-${ri}-${ci}`)
            }
            .width('100%')
            .backgroundColor(ri % 2 === 0 ? $r('app.color.card') : $r('app.color.chat_assistant'))
          }, (_row: string[], ri: number) => `r-${blockIndex}-${ri}`)
        }
      }
      .width('100%')
      .borderRadius(6)
      .clip(true)
    } else if (block.type === 'horizontal-rule') {
      Divider()
        .strokeWidth(1)
        .color($r('app.color.divider'))
    } else if (block.type === 'ordered-list' || block.type === 'unordered-list') {
      Column({ space: 4 }) {
        ForEach(block.items, (item: string, itemIndex: number) => {
          Row({ space: 6 }) {
            Text(block.type === 'ordered-list' ? `${(block.startNumber ?? 1) + itemIndex}.` : '•')
              .width(20)
              .fontSize(15)
              .lineHeight(22)
              .fontColor($r('app.color.text_note'))
              .textAlign(TextAlign.End)
            Text() {
              ForEach(parseInlineMarkdown(item), (span: MarkdownSpan) => {
                if (span.link !== undefined && span.link.length > 0) {
                  Span(span.text)
                    .fontWeight(span.bold ? FontWeight.Bold : FontWeight.Normal)
                    .fontColor($r('app.color.link_markdown'))
                    .fontStyle(span.italic ? FontStyle.Italic : FontStyle.Normal)
                    .decoration({ type: TextDecorationType.Underline })
                    .onClick(() => this.confirmOpenLink(span.link ?? ''))
                } else {
                  Span(span.text)
                    .fontWeight(span.bold ? FontWeight.Bold : FontWeight.Normal)
                    .fontColor($r('app.color.text_body'))
                    .fontStyle(span.italic ? FontStyle.Italic : FontStyle.Normal)
                }
              }, (_span: MarkdownSpan, spanIndex: number) => `${blockIndex}-${itemIndex}-${spanIndex}`)
            }
            .fontSize(15)
            .lineHeight(22)
            .layoutWeight(1)
            .textAlign(TextAlign.Start)
          }
          .width('100%')
          .alignItems(VerticalAlign.Top)
        }, (_item: string, itemIndex: number) => `${blockIndex}-${itemIndex}`)
      }
      .width('100%')
    } else {
      this.MarkdownLine(block.text)
    }
  }

  @Builder
  private MarkdownContent(content: string) {
    Column({ space: 8 }) {
      ForEach(parseLightMarkdown(content), (block: MarkdownBlock, blockIndex: number) => {
        this.MarkdownBlock(block, blockIndex)
      }, (_block: MarkdownBlock, blockIndex: number) => `${blockIndex}`)
    }
    .width('100%')
  }

  @Builder
  private ThinkingBlock() {
    Column({ space: 6 }) {
      Row() {
        Text('深度思考')
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_thinking'))
          .layoutWeight(1)
        Text(this.answerText().length > 0 && !this.message.thinkingExpanded ? '已折叠' : (this.thinkingClosed() ? '已完成' : '思考中'))
          .fontSize(11)
          .fontColor($r('app.color.text_thinking_meta'))
      }
      .width('100%')
      .onClick(() => {
        if (this.answerText().length > 0) {
          this.onToggleThinking(this.message.id)
        }
      })

      if (this.message.thinkingExpanded || this.answerText().length === 0) {
        Text(this.thinkingText().length > 0 ? this.thinkingText() : '...')
          .fontSize(13)
          .lineHeight(20)
          .fontColor($r('app.color.text_thinking_body'))
          .width('100%')
      }
    }
    .width('100%')
    .padding(8)
    .backgroundColor($r('app.color.thinking_background'))
    .borderRadius(8)
  }

  build() {
    Row() {
      if (this.message.role === 'user') {
        Blank()
      }
      Column({ space: 6 }) {
        Row() {
          Text(this.message.role === 'user' ? '你' : '助手')
            .fontSize(11)
            .fontColor(this.message.role === 'user' ? $r('app.color.chat_user_meta') : $r('app.color.text_assistant_meta'))
          Text(this.message.time)
            .fontSize(11)
            .fontColor(this.message.role === 'user' ? $r('app.color.chat_user_time') : $r('app.color.text_caption'))
            .margin({ left: 8 })
        }
        if (this.message.imageUri.length > 0) {
          Image(this.message.imageUri)
            .width(132)
            .height(88)
            .objectFit(ImageFit.Cover)
            .borderRadius(8)
        }
        if (this.message.role === 'assistant' && this.hasThinking()) {
          this.ThinkingBlock()
        }
        if (this.answerText().length > 0 || !this.hasThinking()) {
          if (this.message.role === 'assistant') {
            this.MarkdownContent(this.answerText().length > 0 ? this.answerText() : '...')
          } else {
            Text(this.answerText().length > 0 ? this.answerText() : '...')
              .width('100%')
              .fontSize(15)
              .lineHeight(22)
              .textAlign(TextAlign.Start)
              .fontColor($r('app.color.chat_user_text'))
          }
        }
        if (this.message.role === 'assistant' && this.message.perfMetrics !== undefined) {
          Text(`TTFT ${this.message.perfMetrics.ttft}ms · ${this.message.perfMetrics.tpot}ms/tok · ${this.message.perfMetrics.tokensPerSec} tok/s · ${this.message.perfMetrics.tokens} tokens`)
            .fontSize(10)
            .fontColor($r('app.color.text_stats'))
            .textAlign(TextAlign.Center)
            .width('100%')
        }
      }
      .padding({ left: 12, right: 12, top: 10, bottom: 10 })
      .backgroundColor(this.message.role === 'user' ? $r('app.color.chat_user') : $r('app.color.chat_assistant'))
      .borderRadius(8)
      .width(this.message.role === 'user' ? '84%' : '94%')
      .constraintSize({ maxWidth: this.message.role === 'user' ? 720 : 880 })
      .bindContextMenu(this.CopyMenuBuilder, ResponseType.LongPress)
      if (this.message.role !== 'user') {
        Blank()
      }
    }
    .width('100%')
  }

  @Builder
  CopyMenuBuilder() {
    Menu() {
      MenuItem({ content: '复制' })
        .onClick(() => {
          this.copyToClipboard()
        })
    }
  }
}
