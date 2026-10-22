import { EditQuestionConfirmDialog } from './EditQuestionConfirmDialog'
import { ActionButtonStyle, CompactActionStyle } from './ButtonStyles'
import { ChatMessage } from '../models/ChatTypes'
import { MarkdownBlock, MarkdownSpan, parseInlineMarkdown, parseLightMarkdown } from '../utils/markdown'
import { parseAssistantText } from '../utils/thinking'
import { deviceInfo, pasteboard } from '@kit.BasicServicesKit'
import { common } from '@kit.AbilityKit'
import { SelectionContainer, SelectionContainerAttribute, SelectionContainerController } from '@kit.ArkUI'
import { MessageSelectionPart, joinMessageSelection } from '../utils/messageSelection'

@Component
export struct MessageBubble {
  @Prop message: ChatMessage = {
    id: 0,
    role: 'assistant',
    content: '',
    imageUri: '',
    time: '',
    includeInContext: false,
    thinkingExpanded: false
  }
  onToggleThinking: (messageId: number) => void = (_messageId: number) => {}
  onAnswerSelection: () => void = () => {}
  @Prop canRegenerate: boolean = false
  @Prop canEdit: boolean = false
  @State private editing: boolean = false
  @State private editText: string = ''
  private editController: TextAreaController = new TextAreaController()
  @Prop confirmEdit: boolean = false
  onEdit: (text: string, skipConfirmation: boolean) => Promise<boolean> = async (_text: string, _skip: boolean) => false
  private editDialog: CustomDialogController = new CustomDialogController({
    builder: EditQuestionConfirmDialog({
      onCancel: (): void => { this.editDialog.close() },
      onConfirm: (skip: boolean) => {
        this.editDialog.close()
        this.submitEdit(skip)
      }
    }),
    alignment: DialogAlignment.Center,
    customStyle: true,
    autoCancel: true,
    maskColor: $r('app.color.scrim')
  })
  @Prop highlighted: boolean = false
  onRegenerate: () => void = () => {}
  @State private selectionSnapshot: string = ''
  private answerSelection: Map<string, MessageSelectionPart> = new Map()
  private selectionController: SelectionContainerController | undefined = undefined
  @StorageLink('chatMouseInput') private mouseInput: boolean = false
  @State private hovered: boolean = false
  @State private actionsFocused: boolean = false
  @State private copied: boolean = false
  private copiedTimer: number = -1

  aboutToAppear(): void {
    if (deviceInfo.apiAvailable('26.0.0')) {
      this.selectionController = new SelectionContainerController()
    }
  }

  private async submitEdit(skipConfirmation: boolean): Promise<void> {
    if (await this.onEdit(this.editText.trim(), skipConfirmation)) {
      this.editController.stopEditing()
      this.editing = false
      this.editText = ''
    }
  }

  aboutToDisappear(): void {
    this.editDialog.close()
    if (this.copiedTimer >= 0) clearTimeout(this.copiedTimer)
  }

  private inlinePlainText(text: string): string {
    return parseInlineMarkdown(text).map((span: MarkdownSpan) => span.text).join('')
  }

  private updateAnswerSelection(text: string, start: number, end: number,
    block: number, row: number = 0, column: number = 0, kind: string = 'text'): void {
    if (!deviceInfo.apiAvailable('26.0.0')) return
    const key = `${block}:${row}:${column}`
    if (start < 0 || end <= start) {
      this.answerSelection.delete(key)
    } else {
      this.answerSelection.set(key, { block, row, column, kind, text: text.substring(start, end) })
    }
  }

  private clearAnswerSelection(): void {
    this.selectionController?.clearTextSelection()
    this.answerSelection.clear()
    this.selectionSnapshot = ''
  }

  private async copyText(text: string): Promise<boolean> {
    try {
      await pasteboard.getSystemPasteboard().setData(pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text))
      this.clearAnswerSelection()
      return true
    } catch (_) {
      this.showLinkToast('复制失败，请重试')
      return false
    }
  }

  private copySelectedAnswer(nativeText: string): boolean {
    const text = joinMessageSelection(Array.from(this.answerSelection.values()), nativeText)
    if (text === nativeText) return true
    this.copyText(text)
    return false
  }

  private async copyMessage(): Promise<void> {
    if (await this.copyText(this.answerText())) {
      this.copied = true
      if (this.copiedTimer >= 0) clearTimeout(this.copiedTimer)
      this.copiedTimer = setTimeout(() => {
        this.copied = false
        this.copiedTimer = -1
      }, 1500)
    }
  }

  private showActions(): boolean {
    return this.message.role !== 'user' || !this.mouseInput || this.hovered || this.actionsFocused
  }

  @Builder
  private MessageAction(icon: Resource, label: string, action: () => void) {
    Button({ type: ButtonType.Normal }) {
      Image(label === '复制' && this.copied ? $r('app.media.icon_message_check') : icon)
        .width(16).height(16).fillColor(this.message.role === 'user' ?
          $r('app.color.chat_user_meta') : $r('app.color.text_muted'))
    }
    .id(`message-${this.message.id}-${label}`)
    .width(20).height(20).padding(0)
    .responseRegion({ x: -6, y: -10, width: 32, height: 40 })
    .borderRadius($r('app.float.button_radius'))
    .backgroundColor(Color.Transparent)
    .hoverEffect(HoverEffect.Auto)
    .accessibilityText(label)
    .bindTips(label, { enableArrow: false })
    .onFocus(() => { this.actionsFocused = true })
    .onBlur(() => { this.actionsFocused = false })
    .onClick(action)
  }

  @Builder
  private MessageActions() {
    Row({ space: 12 }) {
      if (this.answerText().length > 0) {
        this.MessageAction($r('app.media.icon_message_copy'), '复制', () => { this.copyMessage() })
      }
      if (this.canEdit) {
        this.MessageAction($r('app.media.icon_message_edit'), '编辑', () => {
          this.clearAnswerSelection()
          this.editText = this.message.content
          this.editing = true
          this.onAnswerSelection()
        })
      }
      if (this.canRegenerate) {
        this.MessageAction($r('app.media.icon_message_regenerate'), '重新生成', () => {
          this.clearAnswerSelection()
          this.onRegenerate()
        })
      }
    }
    .height(20).flexShrink(0)
    .alignItems(VerticalAlign.Center)
    // Reserve the header actions so hover and keyboard focus never move the text.
    .opacity(this.showActions() ? 1 : 0)
    .hitTestBehavior(this.showActions() ? HitTestMode.Default : HitTestMode.None)
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
  private MarkdownLine(text: string, color: ResourceColor = $r('app.color.text_body'),
    blockIndex: number = 0, rowIndex: number = 0, columnIndex: number = 0, kind: string = 'text') {
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
    .onTextSelectionChange((start: number, end: number) => {
      this.updateAnswerSelection(this.inlinePlainText(text), start, end, blockIndex, rowIndex, columnIndex, kind)
    })
    .copyOption(CopyOptions.LocalDevice)
    .textSelectable(TextSelectableMode.SELECTABLE_FOCUSABLE)
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
      .onTextSelectionChange((start: number, end: number) => {
        this.updateAnswerSelection(this.inlinePlainText(block.text), start, end, blockIndex)
      })
      .copyOption(CopyOptions.LocalDevice)
      .textSelectable(TextSelectableMode.SELECTABLE_FOCUSABLE)
      .width('100%')
      .fontSize(15)
      .lineHeight(22)
      .textAlign(TextAlign.Start)
    } else if (block.type === 'code') {
      Stack({ alignContent: Alignment.TopEnd }) {
        Text(block.text)
          .onTextSelectionChange((start: number, end: number) => {
            this.updateAnswerSelection(block.text, start, end, blockIndex)
          })
          .copyOption(CopyOptions.LocalDevice)
          .textSelectable(TextSelectableMode.SELECTABLE_FOCUSABLE)
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
          .onClick(() => this.copyText(block.text))
      }
      .width('100%')
    } else if (block.type === 'blockquote') {
      Row() {
        this.MarkdownLine(block.text, $r('app.color.text_secondary'), blockIndex)
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
            ForEach(block.headers, (h: string, hi: number) => {
              Column() {
                this.MarkdownLine(h, $r('app.color.text_title'), blockIndex, 0, hi, 'table')
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
              ForEach(row, (cell: string, ci: number) => {
                Column() {
                  this.MarkdownLine(cell, $r('app.color.code_text'), blockIndex, ri + 1, ci, 'table')
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
              .onTextSelectionChange((start: number, end: number) => {
                this.updateAnswerSelection(block.type === 'ordered-list' ? `${(block.startNumber ?? 1) + itemIndex}.` : '•',
                  start, end, blockIndex, itemIndex, 0, 'list')
              })
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
            .onTextSelectionChange((start: number, end: number) => {
              this.updateAnswerSelection(this.inlinePlainText(item), start, end, blockIndex, itemIndex, 1, 'list')
            })
            .copyOption(CopyOptions.LocalDevice)
            .textSelectable(TextSelectableMode.SELECTABLE_FOCUSABLE)
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
      this.MarkdownLine(block.text, $r('app.color.text_body'), blockIndex)
    }
  }

  @Builder
  private MarkdownContent() {
    Column({ space: 8 }) {
      ForEach(parseLightMarkdown(this.selectionSnapshot || this.answerText() || '...'), (block: MarkdownBlock, blockIndex: number) => {
        this.MarkdownBlock(block, blockIndex)
      }, (block: MarkdownBlock, blockIndex: number) => `${blockIndex}:${JSON.stringify(block)}`)
    }
    .width('100%')
  }

  @Builder
  private SelectableAnswer() {
    if (deviceInfo.apiAvailable('26.0.0')) {
      SelectionContainer({ controller: this.selectionController }) {
        this.MarkdownContent()
      }
      .copyOption(CopyOptions.LocalDevice)
      .onTextSelectionChange((texts: string[]) => {
        if (texts.length > 0) {
          if (this.selectionSnapshot.length === 0) {
            this.onAnswerSelection()
            this.selectionSnapshot = this.answerText()
          }
        } else {
          this.answerSelection.clear()
          this.selectionSnapshot = ''
        }
      })
      .onWillCopy((text: string) => this.copySelectedAnswer(text))
      .onCopy(() => this.clearAnswerSelection())
      .width('100%')
    } else {
      this.MarkdownContent()
    }
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
          .copyOption(CopyOptions.LocalDevice)
          .textSelectable(TextSelectableMode.SELECTABLE_FOCUSABLE)
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
      Column({ space: 2 }) {
        Column({ space: this.editing ? 6 : 4 }) {
          if (!this.editing) {
            Row() {
              Text(this.message.role === 'user' ? '你' : (this.message.modelName?.trim().length ? this.message.modelName : '助手'))
                .fontSize(11)
                .fontColor(this.message.role === 'user' ? $r('app.color.chat_user_meta') : $r('app.color.text_assistant_meta'))
                .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
              if (this.message.kind !== 'notice' &&
                (this.answerText().length > 0 || this.canEdit || this.canRegenerate)) {
                this.MessageActions()
              }
              Text(this.message.time)
                .fontSize(11)
                .fontColor(this.message.role === 'user' ? $r('app.color.chat_user_time') : $r('app.color.text_caption'))
                .margin({ left: 16 }).flexShrink(0)
            }.width('100%').height(20)
          }
          if (this.message.imageUnavailable) {
            Text('此图片未能保存').fontSize(11).fontColor($r('app.color.text_muted'))
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
              this.SelectableAnswer()
            } else if (this.editing) {
              TextArea({ text: this.editText, controller: this.editController })
                .id(`edit-question-${this.message.id}`)
                .onAppear(() => {
                  this.getUIContext().getFocusController().requestFocus(`edit-question-${this.message.id}`)
                })
                .height('auto')
                .minLines(2)
                .width('100%')
                .constraintSize({ minHeight: 44, maxHeight: 240 })
                .fontSize(15)
                .lineHeight(22)
                .fontColor($r('app.color.input_text'))
                .caretColor($r('app.color.control_accent'))
                .backgroundColor(Color.Transparent)
                .border({ width: 0 })
                .borderRadius(0)
                .padding(0)
                .onChange((value: string) => { this.editText = value })
              Row({ space: 8 }) {
                Blank()
                Button('取消', { type: ButtonType.Normal })
                  .attributeModifier(new ActionButtonStyle(Color.Transparent, $r('app.color.button_secondary_text')))
                  .height(32).width(64).fontSize(13)
                  .border({ width: 1, color: $r('app.color.text_muted'), radius: $r('app.float.button_radius') })
                  .onClick(() => {
                    this.editController.stopEditing()
                    this.editing = false
                    this.editText = ''
                  })
                Button('发送', { type: ButtonType.Normal })
                  .attributeModifier(new ActionButtonStyle($r('app.color.button_primary_background'), $r('app.color.button_primary_text')))
                  .height(32).width(64).fontSize(13)
                  .enabled(this.canEdit && this.editText.trim().length > 0)
                  .onClick(() => {
                    if (this.confirmEdit) this.editDialog.open()
                    else this.submitEdit(false)
                  })
              }.width('100%').margin({ top: 4 })
            } else {
              Text(this.answerText().length > 0 ? this.answerText() : '...')
                .copyOption(CopyOptions.LocalDevice)
                .textSelectable(TextSelectableMode.SELECTABLE_FOCUSABLE)
                .width('100%')
                .fontSize(15)
                .lineHeight(22)
                .textAlign(TextAlign.Start)
                .fontColor($r('app.color.chat_user_text'))
            }
          }
          if (this.message.generationState === 'stopped') {
            Text('已停止生成').fontSize(11).fontColor($r('app.color.text_muted'))
          }
          if (this.message.generationState === 'interrupted') {
            Text('生成已中断').fontSize(11).fontColor($r('app.color.status_warning'))
          }
          if (this.message.generationState === 'failed') {
            Text(this.answerText().length > 0 ? '生成失败，已保留以上内容' : '生成失败')
              .fontSize(11)
              .fontColor($r('app.color.status_error'))
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
        .backgroundColor(this.editing ? $r('app.color.input_background') :
          (this.message.role === 'user' ? $r('app.color.chat_user') : $r('app.color.chat_assistant')))
        .borderRadius(8)
        .border({ width: this.highlighted || this.editing ? 1 : 0, color: $r('app.color.control_accent') })
        .width('100%')
      }
      .width(this.editing ? '100%' : (this.message.role === 'user' ? '84%' : '94%'))
      .constraintSize({ maxWidth: this.editing ? 900 : (this.message.role === 'user' ? 720 : 880) })
      .onHover((hover: boolean, event: HoverEvent) => {
        this.hovered = hover
        if (hover && event.source === SourceType.Mouse) this.mouseInput = true
      })
      if (this.message.role !== 'user') {
        Blank()
      }
    }
    .width('100%')
  }
}
