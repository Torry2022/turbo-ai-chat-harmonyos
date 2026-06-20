import { ChatMessage } from '../models/ChatTypes'
import { ChatViewModel } from '../state/ChatViewModel'
import { MessageBubble } from './MessageBubble'

@Component
export struct ChatTab {
  @ObjectLink viewModel: ChatViewModel
  @Prop renderVersion: number
  private inputController: TextAreaController = new TextAreaController()

  build() {
    Column({ space: 8 }) {
      List({ space: 10, scroller: this.viewModel.chatScroller }) {
        ForEach(this.viewModel.messages, (message: ChatMessage) => {
          ListItem() {
            MessageBubble({
              message,
              onToggleThinking: (messageId: number) => {
                this.viewModel.toggleMessageThinking(messageId)
              }
            })
          }
        }, (message: ChatMessage) => {
          if (message.role === 'assistant') {
            return `${message.id}-${message.content.length}-${message.thinkingExpanded ? 1 : 0}-${message.perfMetrics !== undefined ? 1 : 0}`
          }
          return `${message.id}`
        })
      }
      .layoutWeight(1)
      .width('100%')
      .divider({ strokeWidth: 0 })
      .scrollBar(BarState.Off)
      .onTouch((event: TouchEvent) => {
        if (event.type === TouchType.Down) {
          this.viewModel.pauseChatAutoScroll()
        }
      })
      .onClick(() => {
        this.inputController.stopEditing()
      })

      if (this.viewModel.selectedImageUri.length > 0) {
        Row({ space: 8 }) {
          Image(this.viewModel.selectedImageUri)
            .width(72)
            .height(48)
            .objectFit(ImageFit.Cover)
            .borderRadius(8)
          Text(this.viewModel.selectedImageUri)
            .fontSize(12)
            .fontColor('#8CA2B8')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          Button('清除')
            .height(34)
            .onClick(() => {
              this.inputController.stopEditing()
              this.viewModel.clearSelectedImage()
            })
        }
        .width('100%')
        .padding(8)
        .backgroundColor('#101D2B')
        .borderRadius(8)
        .onClick(() => {
          this.inputController.stopEditing()
        })
      }

      Stack({ alignContent: Alignment.End }) {
        TextArea({ text: this.viewModel.inputText, controller: this.inputController })
          .enabled(this.viewModel.loaded)
          .constraintSize({ minHeight: 44, maxHeight: 120 })
          .fontSize(14)
          .fontColor('#EAF4FF')
          .backgroundColor('#101D2B')
          .borderRadius(10)
          .padding({ left: 16, right: 84, top: 13, bottom: 10 })
          .onChange((value: string) => {
            this.viewModel.updateInputText(value)
          })

        if (this.viewModel.inputText.length === 0) {
          Text(this.viewModel.loaded ? '输入您的问题...' : '请先加载模型...')
            .fontSize(15)
            .fontColor('#8CA2B8')
            .width('100%')
            .height(38)
            .textAlign(TextAlign.Start)
            .padding({ left: 18 })
            .hitTestBehavior(HitTestMode.None)
        }

        Row({ space: 4 }) {
          if (this.viewModel.generating) {
            Image(this.viewModel.generationStopping ? $r('app.media.icon_stop_generation_disabled') : $r('app.media.icon_stop_generation'))
              .width(36)
              .height(36)
              .onClick(() => {
                if (!this.viewModel.generationStopping) {
                  this.inputController.stopEditing()
                  this.viewModel.stopGeneration()
                }
              })
          } else {
            if (this.viewModel.currentModel().supportsImage && this.viewModel.loaded) {
              Image($r('app.media.icon_image_add'))
                .width(36)
                .height(36)
                .onClick(() => {
                  this.inputController.stopEditing()
                  this.viewModel.chooseImage()
                })
            }
            Image(this.viewModel.loaded && this.viewModel.inputText.trim().length > 0 && (this.viewModel.selectedImageUri.length === 0 || this.viewModel.currentModel().supportsImage) ? $r('app.media.icon_send') : $r('app.media.icon_send_disabled'))
              .width(36)
              .height(36)
              .onClick(() => {
                if (this.viewModel.loaded && this.viewModel.inputText.trim().length > 0) {
                  this.inputController.stopEditing()
                  this.viewModel.sendMessage()
                }
              })
          }
        }
        .margin({ right: 10 })
      }
      .width('100%')
    }
    .layoutWeight(1)
    .width('100%')
  }
}
