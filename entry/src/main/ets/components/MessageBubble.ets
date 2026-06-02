import { ChatMessage } from '../models/ChatTypes';
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
          Text(this.answerText().length > 0 ? this.answerText() : '...')
            .fontSize(15)
            .lineHeight(22)
            .fontColor(this.message.role === 'user' ? Color.White : '#EAF4FF');
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
