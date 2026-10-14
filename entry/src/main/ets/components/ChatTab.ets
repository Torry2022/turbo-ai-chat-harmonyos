import { ChatHistoryPanel } from './ChatHistoryPanel'
import { messageDate } from '../models/ChatHistoryTypes'
import { ActionButtonStyle, CompactActionStyle } from './ButtonStyles'
import { ChatMessage } from '../models/ChatTypes'
import { ChatViewModel } from '../state/ChatViewModel'
import { MessageBubble } from './MessageBubble'
import { KeyCode } from '@kit.InputKit'

@Component
export struct ChatTab {
  @ObjectLink viewModel: ChatViewModel
  @Prop @Watch('onHistoryReady') renderVersion: number
  @Prop @Watch('onActiveChange') active: boolean = false
  @Prop dialogVisible: boolean = false
  @Prop leadingInset: number = 0
  @Prop inputBottomOffset: number = 0
  onRequestModel: () => void = () => {}
  @State private historyWidth: number = 0
  @State private historyOpen: boolean = false
  private historyInitialized: boolean = false

  private dateBefore(index: number): string {
    const message = this.viewModel.messages[index]
    if (message.kind === 'notice' || !message.createdAt) return ''
    const day = messageDate(message.createdAt)
    for (let previous = index - 1; previous >= 0; previous--) {
      const item = this.viewModel.messages[previous]
      if (item.kind !== 'notice' && item.createdAt) {
        return messageDate(item.createdAt) === day ? '' : day
      }
    }
    return day
  }

  @State private inputFocused: boolean = false
  @State private voiceWaveRaised: boolean = false
  private inputController: TextAreaController = new TextAreaController()
  private composing: boolean = false
  private enterHeld: boolean = false
  private enterConsumed: boolean = false
  private suppressEnterNewline: boolean = false
  private submitOnNewline: boolean = false

  private wideHistory(): boolean {
    return this.historyWidth >= 872
  }

  private setHistoryOpen(open: boolean): void {
    this.getUIContext().animateTo({ duration: 220, curve: Curve.EaseInOut }, () => {
      this.historyOpen = open
    })
  }

  private onHistoryReady(): void {
    if (!this.historyInitialized && this.viewModel.historyReady && this.historyWidth > 0) {
      this.historyInitialized = true
      this.historyOpen = this.wideHistory() && this.viewModel.conversations.length > 0
    }
  }

  aboutToAppear(): void {
    this.viewModel.bindHistoryClose((): boolean => {
      if (!this.historyOpen || this.wideHistory()) return false
      this.setHistoryOpen(false)
      return true
    })
  }

  private onActiveChange(): void {
    if (!this.active) {
      if (!this.wideHistory()) this.setHistoryOpen(false)
      this.inputController.stopEditing()
    }
  }

  private sendKeyboardMessage(): void {
    if (this.active && this.inputFocused && (this.wideHistory() || !this.historyOpen) && !this.dialogVisible && this.viewModel.loaded &&
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
            .backgroundColor(this.viewModel.speechDetected ? $r('app.color.composer_text') : $r('app.color.attachment_icon'))
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
    .backgroundColor($r('app.color.attachment_background'))
    .border({ width: 1, color: $r('app.color.attachment_border') })
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

  private hasConversation(): boolean {
    return this.viewModel.messages.some((message: ChatMessage) => message.role === 'user')
  }

  @Builder
  private EmptyConversation() {
    Column({ space: 16 }) {
      if (!this.viewModel.loaded) {
        Text('尚未加载模型').fontSize(15).fontColor($r('app.color.text_muted'))
        Button(this.viewModel.modelLoading ? '正在加载…' : '加载模型')
          .attributeModifier(new ActionButtonStyle($r('app.color.button_primary_background'), $r('app.color.button_primary_text')))
          .width(132).height(38)
          .enabled(!this.viewModel.busy && !this.viewModel.modelLoading)
          .onClick(() => this.viewModel.openModelLoadDialog())
      }
    }.width('100%').padding({ left: 24, right: 24 })
  }

  @Builder
  private ChatBody() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Button({ type: ButtonType.Normal }) {
          Image($r('app.media.icon_chat_history')).width(22).height(22)
            .fillColor($r('app.color.text_secondary'))
        }.width(34).height(34).padding(0).borderRadius(8)
          .backgroundColor(this.historyOpen ? $r('app.color.nav_selected_background') : Color.Transparent)
          .hoverEffect(HoverEffect.Auto)
          .accessibilityText(this.historyOpen ? '收起历史对话' : '展开历史对话')
          .onClick(() => {
            this.inputController.stopEditing()
            this.setHistoryOpen(!this.historyOpen)
          })
        Text(this.viewModel.currentConversationTitle())
          .fontSize(15).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_title'))
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
      }.width('100%').height(40)
      if (this.viewModel.historyError.length > 0) {
        Row({ space: 8 }) {
          Text(this.viewModel.historyError).fontSize(12).lineHeight(18)
            .fontColor($r('app.color.status_warning')).layoutWeight(1)
          Button('重试').attributeModifier(new CompactActionStyle())
            .enabled(!this.viewModel.historyBusy).onClick(() => this.viewModel.retryHistorySave())
        }.width('100%').padding(8).backgroundColor($r('app.color.inset')).borderRadius(8)
      }
      if (!this.hasConversation()) {
        Column() {
          this.EmptyConversation()
        }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
      } else {
      List({ space: 10, scroller: this.viewModel.chatScroller }) {
        ForEach(this.viewModel.messages, (message: ChatMessage, index: number) => {
          ListItem() {
            Column({ space: 8 }) {
              if (this.dateBefore(index).length > 0) {
                Text(this.dateBefore(index)).fontSize(11).fontColor($r('app.color.text_muted'))
                  .width('100%').textAlign(TextAlign.Center).padding({ top: 6, bottom: 2 })
              }
              if (message.kind === 'notice') {
                Text(message.content).fontSize(12).lineHeight(18).fontColor($r('app.color.text_muted'))
                  .width('100%').textAlign(TextAlign.Center).padding({ left: 12, right: 12, top: 6, bottom: 6 })
              } else {
            MessageBubble({
              message,
              onToggleThinking: (messageId: number) => {
                this.viewModel.toggleMessageThinking(messageId)
              }
            })
              }
            }.width('100%')
          }.visibility(message.kind === 'notice' && message.role === 'assistant' ? Visibility.None : Visibility.Visible)
        }, (message: ChatMessage) => {
          if (message.role === 'assistant') {
            return `${message.id}-${message.content.length}-${message.thinkingExpanded ? 1 : 0}-${message.perfMetrics !== undefined ? 1 : 0}-${message.generationState ?? ''}`
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

      }

      if (this.viewModel.selectedImageUri.length > 0) {
        Row({ space: 8 }) {
          Image(this.viewModel.selectedImageUri)
            .width(72)
            .height(48)
            .objectFit(ImageFit.Cover)
            .borderRadius(8)
          Text(this.viewModel.selectedImageUri)
            .fontSize(12)
            .fontColor($r('app.color.text_muted'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          Button('清除')
            .attributeModifier(new ActionButtonStyle($r('app.color.button_secondary_background'), $r('app.color.button_secondary_text')))
            .onClick(() => {
              this.inputController.stopEditing()
              this.viewModel.clearSelectedImage()
            })
        }
        .width('100%')
        .padding(8)
        .backgroundColor($r('app.color.composer_background'))
        .borderRadius(8)
        .onClick(() => {
          this.inputController.stopEditing()
        })
      }

      Column({ space: 6 }) {
        Row({ space: 6 }) {
          Circle()
            .width(6)
            .height(6)
            .fill(this.viewModel.modelLoading ? $r('app.color.status_loading') :
              (this.viewModel.loaded ? $r('app.color.model_ready_indicator') : $r('app.color.text_muted')))
          Text(this.viewModel.modelLoading ? '正在加载 ' + this.viewModel.currentModel().shortName + '…' :
            (this.viewModel.loaded ? this.viewModel.currentModel().shortName : '未加载模型'))
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
          .textAlign(TextAlign.Start)
          .onClick(() => {
            if (this.viewModel.loaded || this.viewModel.modelLoading) {
              this.getUIContext().getPromptAction().showToast({
                message: this.viewModel.currentModel().name, duration: 2500
              })
            }
          })
        }
        .width('100%')
        .padding({ left: 16, right: 16 })

        Stack({ alignContent: Alignment.End }) {
          TextArea({ text: this.viewModel.inputText, controller: this.inputController })
            .hitTestBehavior(this.viewModel.loaded ? HitTestMode.Default : HitTestMode.None)
            .enabled(this.viewModel.loaded && !this.viewModel.speechRecognitionStarting &&
              !this.viewModel.speechRecognizing)
            .constraintSize({ minHeight: 44, maxHeight: 120 })
            .fontSize(14)
            .fontColor($r('app.color.text_body'))
            .backgroundColor($r('app.color.composer_background'))
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
              .fontColor($r('app.color.text_muted'))
              .width('100%')
              .height(38)
              .textAlign(TextAlign.Start)
              .padding({ left: 16, right: 94 })
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
              Stack() {
                Image($r('app.media.icon_send'))
                  .width(40)
                  .height(40)
                  .syncLoad(true)
                  .opacity(this.viewModel.inputText.trim().length > 0 || this.inputFocused ?
                    (this.viewModel.loaded && this.viewModel.inputText.trim().length > 0 &&
                    (this.viewModel.selectedImageUri.length === 0 ||
                      this.viewModel.currentModel().supportsImage) ? 1 : 0.45) : 0)
                  .hitTestBehavior(HitTestMode.None)
                  .accessibilityLevel('no')
                Image($r('app.media.icon_microphone'))
                  .width(40)
                  .height(40)
                  .syncLoad(true)
                  .opacity(this.viewModel.inputText.trim().length > 0 || this.inputFocused ? 0 :
                    (this.viewModel.loaded && !this.viewModel.speechRecognitionStarting ? 1 : 0.45))
                  .hitTestBehavior(HitTestMode.None)
                  .accessibilityLevel('no')
              }
              .width(40)
              .height(40)
              .onClick(() => {
                  if (this.viewModel.inputText.trim().length > 0 || this.inputFocused) {
                    if (this.viewModel.loaded && this.viewModel.inputText.trim().length > 0) {
                      this.inputController.stopEditing()
                      this.viewModel.sendMessage()
                    }
                  } else if (this.viewModel.loaded && !this.viewModel.speechRecognitionStarting) {
                      this.inputController.stopEditing()
                      this.viewModel.startSpeechRecognition()
                  }
              })
              .accessibilityText(this.viewModel.inputText.trim().length > 0 || this.inputFocused ?
                '发送消息' : '开始语音输入')
            }
          }
          .margin({ right: 10 })
        }
        .width('100%')
        .backgroundColor($r('app.color.composer_background'))
        .borderRadius(10)
        .onClick(() => {
          if (!this.viewModel.loaded && !this.viewModel.modelLoading) {
            this.onRequestModel()
          }
        })
      }
      .width('100%')
      .translate({ y: this.inputBottomOffset })
    }
    .layoutWeight(1)
    .width('100%')
    .constraintSize({ maxWidth: 900 })
  }

  build() {
    Stack({ alignContent: Alignment.Start }) {
      Row() {
        Column() {
          ChatHistoryPanel({ viewModel: this.viewModel, renderVersion: this.renderVersion })
            .width(220).height('100%')
        }.width(this.wideHistory() && this.historyOpen ? 220 : 0).height('100%')
          .alignItems(HorizontalAlign.Start).clip(true)
          .opacity(this.wideHistory() && this.historyOpen ? 1 : 0)
          .border({ width: { right: 1 }, color: $r('app.color.attachment_border') })
          .hitTestBehavior(this.wideHistory() && this.historyOpen ? HitTestMode.Default : HitTestMode.None)
          .accessibilityLevel(this.wideHistory() && this.historyOpen ? 'auto' : 'no-hide-descendants')
        Column() {
          this.ChatBody()
        }.layoutWeight(1).height('100%').alignItems(HorizontalAlign.Center)
          .padding({ left: this.wideHistory() && this.historyOpen ? 12 : this.leadingInset })
      }.width('100%').height('100%')
      if (!this.wideHistory() && this.historyOpen) {
        Column().width('100%').height('100%').backgroundColor('#66000000')
          .onClick(() => this.setHistoryOpen(false))
          .transition(TransitionEffect.OPACITY.animation({ duration: 220, curve: Curve.EaseInOut }))
        Column() {
          ChatHistoryPanel({ viewModel: this.viewModel, renderVersion: this.renderVersion,
            closeOnSelection: true, onClose: () => this.setHistoryOpen(false) })
        }.width(Math.max(1, Math.min(260, this.historyWidth - 48))).height('100%')
          .padding({ left: 8, right: 8, top: 4, bottom: 8 })
          .backgroundColor($r('app.color.page')).hitTestBehavior(HitTestMode.Block).onClick(() => {})
          .transition(TransitionEffect.move(TransitionEdge.START).combine(TransitionEffect.OPACITY)
            .animation({ duration: 220, curve: Curve.EaseInOut }))
      }
    }.width('100%').layoutWeight(1)
      .onAreaChange((_oldArea: Area, newArea: Area) => {
        const wasWide = this.wideHistory()
        this.historyWidth = Number(newArea.width)
        if (wasWide !== this.wideHistory() && this.historyInitialized) this.historyOpen = false
        this.onHistoryReady()
      })
      .onKeyEvent((event: KeyEvent): boolean => {
        if (!this.wideHistory() && this.historyOpen && event.keyCode === KeyCode.KEYCODE_ESCAPE && event.type === KeyType.Down) {
          this.setHistoryOpen(false)
          return true
        }
        return false
      })
  }
}
