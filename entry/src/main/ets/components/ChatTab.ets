import { ChatMessage } from '../models/ChatTypes'
import { ChatViewModel } from '../state/ChatViewModel'
import { MessageBubble } from './MessageBubble'
import { KeyCode } from '@kit.InputKit'

@Component
export struct ChatTab {
  @ObjectLink viewModel: ChatViewModel
  @Prop renderVersion: number
  @Prop @Watch('onActiveChange') active: boolean = false
  @Prop dialogVisible: boolean = false
  @State private inputFocused: boolean = false
  @State private voiceWaveRaised: boolean = false
  private inputController: TextAreaController = new TextAreaController()
  private composing: boolean = false
  private enterHeld: boolean = false
  private enterConsumed: boolean = false
  private suppressEnterNewline: boolean = false
  private submitOnNewline: boolean = false

  private onActiveChange(): void {
    if (!this.active) {
      this.inputController.stopEditing()
    }
  }

  private sendKeyboardMessage(): void {
    if (this.active && this.inputFocused && !this.dialogVisible && this.viewModel.loaded &&
      !this.viewModel.busy && !this.viewModel.generating && !this.viewModel.speechRecognitionStarting &&
      !this.viewModel.speechRecognizing && this.viewModel.inputText.trim().length > 0) {
      this.viewModel.sendMessage()
    }
  }

  private handleInputKey(event: KeyEvent): boolean {
    if (event.keyCode === KeyCode.KEYCODE_ESCAPE && event.type === KeyType.Down &&
      this.active && this.inputFocused && !this.dialogVisible && !this.composing) {
      this.inputController.stopEditing()
      return true
    }
    if (event.keyCode !== KeyCode.KEYCODE_ENTER && event.keyCode !== KeyCode.KEYCODE_NUMPAD_ENTER) {
      return false
    }
    if (event.type === KeyType.Up) {
      this.enterHeld = false
      return this.enterConsumed
    }
    if (!this.active || !this.inputFocused || this.dialogVisible) {
      return false
    }
    if (this.enterHeld) {
      return this.enterConsumed
    }
    this.enterHeld = true
    this.enterConsumed = !event.getModifierKeyState?.(['ctrl']) && !event.getModifierKeyState?.(['alt'])
    if (!this.enterConsumed) {
      return false
    }
    if (event.getModifierKeyState?.(['shift'])) {
      this.inputController.addText('\n')
      this.suppressEnterNewline = true
      return true
    }
    this.suppressEnterNewline = true
    this.sendKeyboardMessage()
    return true
  }

  private voiceWaveHeight(index: number): number {
    const quietLow: number[] = [4, 6, 5, 4]
    const quietHigh: number[] = [7, 10, 8, 6]
    const activeLow: number[] = [8, 13, 9, 11]
    const activeHigh: number[] = [16, 9, 18, 14]
    if (this.viewModel.speechDetected) {
      return this.voiceWaveRaised ? activeHigh[index] : activeLow[index]
    }
    return this.voiceWaveRaised ? quietHigh[index] : quietLow[index]
  }

  @Builder
  private VoiceRecordingButton() {
    Row({ space: 5 }) {
      Row({ space: 3 }) {
        ForEach([0, 1, 2, 3], (index: number) => {
          Row()
            .width(3)
            .height(this.voiceWaveHeight(index))
            .backgroundColor(this.viewModel.speechDetected ? '#F4FAFF' : '#7FA9C7')
            .borderRadius(2)
            .animation({
              duration: 280 + index * 55,
              curve: Curve.EaseInOut,
              iterations: -1,
              playMode: PlayMode.Alternate
            })
        }, (index: number) => `${index}`)
      }
      .width(29)
      .height(24)
      .justifyContent(FlexAlign.Center)

      Image($r('app.media.icon_stop_generation'))
        .width(30)
        .height(30)
        .opacity(this.viewModel.speechRecognitionStopping ? 0.45 : 1)
    }
    .width(72)
    .height(40)
    .padding({ left: 5, right: 2 })
    .justifyContent(FlexAlign.SpaceBetween)
    .backgroundColor('#142C40')
    .border({ width: 1, color: '#286B9C' })
    .borderRadius(18)
    .onAppear(() => {
      this.voiceWaveRaised = true
    })
    .onDisAppear(() => {
      this.voiceWaveRaised = false
    })
    .onClick(() => {
      this.viewModel.stopSpeechRecognition()
    })
    .accessibilityText('停止语音输入')
  }

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
          .enabled(this.viewModel.loaded && !this.viewModel.speechRecognitionStarting &&
            !this.viewModel.speechRecognizing)
          .constraintSize({ minHeight: 44, maxHeight: 120 })
          .fontSize(14)
          .fontColor('#EAF4FF')
          .backgroundColor('#101D2B')
          .borderRadius(10)
          .padding({ left: 16, right: 94, top: 13, bottom: 10 })
          .onChange((value: string, previewText?: PreviewText) => {
            this.composing = (previewText?.value.length ?? 0) > 0
            this.viewModel.updateInputText(value)
          })
          .onKeyPreIme((event: KeyEvent): boolean => {
            if (event.type === KeyType.Down &&
              (event.keyCode === KeyCode.KEYCODE_ENTER || event.keyCode === KeyCode.KEYCODE_NUMPAD_ENTER)) {
              this.submitOnNewline = !event.getModifierKeyState?.(['shift']) &&
                !event.getModifierKeyState?.(['ctrl']) && !event.getModifierKeyState?.(['alt'])
            }
            if (event.type === KeyType.Up &&
              (event.keyCode === KeyCode.KEYCODE_ENTER || event.keyCode === KeyCode.KEYCODE_NUMPAD_ENTER)) {
              this.enterHeld = false
              this.suppressEnterNewline = false
              this.submitOnNewline = false
            }
            return false
          })
          .onKeyEvent((event: KeyEvent): boolean => this.handleInputKey(event))
          .onWillInsert((value: InsertValue): boolean => {
            if (value.insertValue !== '\n') {
              return true
            }
            if (this.suppressEnterNewline) {
              return false
            }
            // Some input methods insert a newline directly instead of redispatching Enter.
            if (this.submitOnNewline && this.active && this.inputFocused && !this.dialogVisible) {
              if (!this.enterHeld) {
                this.enterHeld = true
                this.enterConsumed = true
                this.sendKeyboardMessage()
              }
              return false
            }
            return true
          })
          .onFocus(() => {
            this.inputFocused = true
          })
          .onBlur(() => {
            this.inputFocused = false
            this.composing = false
            this.enterHeld = false
            this.enterConsumed = false
            this.suppressEnterNewline = false
            this.submitOnNewline = false
          })

        if (this.viewModel.inputText.length === 0) {
          Text(this.viewModel.speechRecognizing ? '正在聆听...' :
            (this.viewModel.loaded ? '输入您的问题...' : '请先加载模型...'))
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
            Image($r('app.media.icon_stop_generation'))
              .width(40)
              .height(40)
              .opacity(this.viewModel.generationStopping ? 0.45 : 1)
              .onClick(() => {
                if (!this.viewModel.generationStopping) {
                  this.inputController.stopEditing()
                  this.viewModel.stopGeneration()
                }
              })
          } else if (this.viewModel.speechRecognizing) {
            this.VoiceRecordingButton()
          } else {
            if (this.viewModel.currentModel().supportsImage && this.viewModel.loaded) {
              Image($r('app.media.icon_image_add'))
                .width(40)
                .height(40)
                .opacity(this.viewModel.speechRecognitionStarting ? 0.45 : 1)
                .onClick(() => {
                  if (!this.viewModel.speechRecognitionStarting) {
                    this.inputController.stopEditing()
                    this.viewModel.chooseImage()
                  }
                })
            }
            if (this.viewModel.inputText.trim().length > 0 || this.inputFocused) {
              Image($r('app.media.icon_send'))
                .width(40)
                .height(40)
                .opacity(this.viewModel.loaded && this.viewModel.inputText.trim().length > 0 &&
                  (this.viewModel.selectedImageUri.length === 0 ||
                    this.viewModel.currentModel().supportsImage) ? 1 : 0.45)
                .onClick(() => {
                  if (this.viewModel.loaded && this.viewModel.inputText.trim().length > 0) {
                    this.inputController.stopEditing()
                    this.viewModel.sendMessage()
                  }
                })
                .accessibilityText('发送消息')
            } else {
              Image($r('app.media.icon_microphone'))
                .width(40)
                .height(40)
                .opacity(this.viewModel.loaded && !this.viewModel.speechRecognitionStarting ? 1 : 0.45)
                .onClick(() => {
                  if (this.viewModel.loaded && !this.viewModel.speechRecognitionStarting) {
                    this.inputController.stopEditing()
                    this.viewModel.startSpeechRecognition()
                  }
                })
                .accessibilityText('开始语音输入')
            }
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
