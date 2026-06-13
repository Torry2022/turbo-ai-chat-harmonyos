import { ChatMessage } from '../models/ChatTypes';
import { ChatViewModel } from '../state/ChatViewModel';
import { MessageBubble } from './MessageBubble';

@Component
export struct ChatTab {
  @ObjectLink viewModel: ChatViewModel;
  @Prop renderVersion: number;

  build() {
    Column({ space: 8 }) {
      List({ space: 10, scroller: this.viewModel.chatScroller }) {
        ForEach(this.viewModel.messages, (message: ChatMessage) => {
          ListItem() {
            MessageBubble({
              message,
              onToggleThinking: (messageId: number) => {
                this.viewModel.toggleMessageThinking(messageId);
              }
            });
          }
        }, (message: ChatMessage) => {
          if (message.role === 'assistant') {
            return `${message.id}-${message.content.length}-${message.thinkingExpanded ? 1 : 0}-${message.perfMetrics !== undefined ? 1 : 0}`;
          }
          return `${message.id}`;
        });
      }
      .layoutWeight(1)
      .width('100%')
      .divider({ strokeWidth: 0 });

      if (this.viewModel.selectedImageUri.length > 0) {
        Row({ space: 8 }) {
          Image(this.viewModel.selectedImageUri)
            .width(72)
            .height(48)
            .objectFit(ImageFit.Cover)
            .borderRadius(8);
          Text(this.viewModel.selectedImageUri)
            .fontSize(12)
            .fontColor('#8CA2B8')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1);
          Button('清除')
            .height(34)
            .onClick(() => {
              this.viewModel.clearSelectedImage();
            });
        }
        .width('100%')
        .padding(8)
        .backgroundColor('#101D2B')
        .borderRadius(8);
      }

      Row({ space: 8 }) {
        if (this.viewModel.currentModel().supportsImage) {
          Button('图片')
            .enabled(!this.viewModel.busy)
            .height(44)
            .onClick(() => {
              this.viewModel.chooseImage();
            });
        }

        TextArea({ text: this.viewModel.inputText, placeholder: '输入消息' })
          .height(58)
          .layoutWeight(1)
          .fontSize(14)
          .fontColor('#EAF4FF')
          .placeholderColor('#8CA2B8')
          .backgroundColor('#101D2B')
          .maxLines(3)
          .onChange((value: string) => {
            this.viewModel.updateInputText(value);
          });

        Button(this.viewModel.busy ? '生成中' : '发送')
          .enabled(this.viewModel.loaded && !this.viewModel.busy && this.viewModel.inputText.trim().length > 0 && (this.viewModel.selectedImageUri.length === 0 || this.viewModel.currentModel().supportsImage))
          .height(44)
          .onClick(() => {
            this.viewModel.sendMessage();
          });
      }
      .width('100%');
    }
    .layoutWeight(1)
    .width('100%');
  }
}
