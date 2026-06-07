import { ChatMessage } from '../models/ChatTypes';
import { MarkdownBlock, MarkdownSpan, parseInlineMarkdown, parseLightMarkdown } from '../utils/markdown';
import { parseAssistantText } from '../utils/thinking';

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
  };
  onToggleThinking: (messageId: number) => void = (_messageId: number) => {};

  private hasThinking(): boolean {
    return parseAssistantText(this.message.content).hasThinking;
  }

  private thinkingText(): string {
    return parseAssistantText(this.message.content).thinking;
  }

  private answerText(): string {
    if (this.message.role !== 'assistant') {
      return this.message.content;
    }
    return parseAssistantText(this.message.content).answer;
  }

  private thinkingClosed(): boolean {
    return parseAssistantText(this.message.content).thinkingClosed;
  }

  @Builder
  private MarkdownLine(text: string, color: ResourceColor = '#EAF4FF') {
    Text() {
      ForEach(parseInlineMarkdown(text), (span: MarkdownSpan, index: number) => {
        Span(span.text)
          .fontWeight(span.bold ? FontWeight.Bold : FontWeight.Normal)
          .fontColor(color);
      }, (_span: MarkdownSpan, index: number) => `${index}`);
    }
    .width('100%')
    .fontSize(15)
    .lineHeight(22)
    .textAlign(TextAlign.Start);
  }

  @Builder
  private MarkdownBlock(block: MarkdownBlock, blockIndex: number) {
    if (block.type === 'heading') {
      Text() {
        ForEach(parseInlineMarkdown(block.text), (span: MarkdownSpan, index: number) => {
          Span(span.text)
            .fontWeight(FontWeight.Bold)
            .fontColor('#F4FBFF');
        }, (_span: MarkdownSpan, index: number) => `${blockIndex}-${index}`);
      }
      .width('100%')
      .fontSize(15)
      .lineHeight(22)
      .textAlign(TextAlign.Start);
    } else if (block.type === 'code') {
      Text(block.text)
        .width('100%')
        .fontSize(13)
        .lineHeight(19)
        .fontColor('#D7E8F7')
        .fontFamily('monospace')
        .padding(8)
        .backgroundColor('#0B1724')
        .borderRadius(6);
    } else if (block.type === 'ordered-list' || block.type === 'unordered-list') {
      Column({ space: 4 }) {
        ForEach(block.items, (item: string, itemIndex: number) => {
          Row({ space: 6 }) {
            Text(block.type === 'ordered-list' ? `${itemIndex + 1}.` : '•')
              .width(20)
              .fontSize(15)
              .lineHeight(22)
              .fontColor('#9FBDD5')
              .textAlign(TextAlign.End);
            Text() {
              ForEach(parseInlineMarkdown(item), (span: MarkdownSpan, spanIndex: number) => {
                Span(span.text)
                  .fontWeight(span.bold ? FontWeight.Bold : FontWeight.Normal)
                  .fontColor('#EAF4FF');
              }, (_span: MarkdownSpan, spanIndex: number) => `${blockIndex}-${itemIndex}-${spanIndex}`);
            }
            .fontSize(15)
            .lineHeight(22)
            .layoutWeight(1)
            .textAlign(TextAlign.Start);
          }
          .width('100%')
          .alignItems(VerticalAlign.Top);
        }, (_item: string, itemIndex: number) => `${blockIndex}-${itemIndex}`);
      }
      .width('100%');
    } else {
      this.MarkdownLine(block.text);
    }
  }

  @Builder
  private MarkdownContent(content: string) {
    Column({ space: 8 }) {
      ForEach(parseLightMarkdown(content), (block: MarkdownBlock, blockIndex: number) => {
        this.MarkdownBlock(block, blockIndex);
      }, (_block: MarkdownBlock, blockIndex: number) => `${blockIndex}`);
    }
    .width('100%');
  }

  @Builder
  private ThinkingBlock() {
    Column({ space: 6 }) {
      Row() {
        Text('深度思考')
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor('#A9B9C8')
          .layoutWeight(1);
        Text(this.answerText().length > 0 && !this.message.thinkingExpanded ? '已折叠' : (this.thinkingClosed() ? '已完成' : '思考中'))
          .fontSize(11)
          .fontColor('#71879B');
      }
      .width('100%')
      .onClick(() => {
        if (this.answerText().length > 0) {
          this.onToggleThinking(this.message.id);
        }
      });

      if (this.message.thinkingExpanded || this.answerText().length === 0) {
        Text(this.thinkingText().length > 0 ? this.thinkingText() : '...')
          .fontSize(13)
          .lineHeight(20)
          .fontColor('#92A6B8')
          .width('100%');
      }
    }
    .width('100%')
    .padding(8)
    .backgroundColor('#172331')
    .borderRadius(8);
  }

  build() {
    Row() {
      if (this.message.role === 'user') {
        Blank();
      }
      Column({ space: 6 }) {
        Row() {
          Text(this.message.role === 'user' ? '你' : '助手')
            .fontSize(11)
            .fontColor(this.message.role === 'user' ? '#DFF7FF' : '#8FA9C3');
          Text(this.message.time)
            .fontSize(11)
            .fontColor(this.message.role === 'user' ? '#B8DAE8' : '#64788D')
            .margin({ left: 8 });
        }
        if (this.message.imageUri.length > 0) {
          Image(this.message.imageUri)
            .width(132)
            .height(88)
            .objectFit(ImageFit.Cover)
            .borderRadius(8);
        }
        if (this.message.role === 'assistant' && this.hasThinking()) {
          this.ThinkingBlock();
        }
        if (this.answerText().length > 0 || !this.hasThinking()) {
          if (this.message.role === 'assistant') {
            this.MarkdownContent(this.answerText().length > 0 ? this.answerText() : '...');
          } else {
            Text(this.answerText().length > 0 ? this.answerText() : '...')
              .width('100%')
              .fontSize(15)
              .lineHeight(22)
              .textAlign(TextAlign.Start)
              .fontColor(Color.White);
          }
        }
      }
      .padding({ left: 12, right: 12, top: 10, bottom: 10 })
      .backgroundColor(this.message.role === 'user' ? '#1267A8' : '#111E2C')
      .borderRadius(8)
      .width(this.message.role === 'user' ? '84%' : '94%');
      if (this.message.role !== 'user') {
        Blank();
      }
    }
    .width('100%');
  }
}
