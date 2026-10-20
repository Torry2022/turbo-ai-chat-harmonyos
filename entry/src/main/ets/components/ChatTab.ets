import { ChatRunTicker } from './ChatRunTicker'
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
  @Prop renderVersion: number
  @Prop @Watch('onActiveChange') active: boolean = false
  @Prop dialogVisible: boolean = false
  @Prop contentInset: number = 0
  @Prop contentBottomInset: number = 0
  @Prop compactTicker: boolean = false
  @Prop compactPage: boolean = false
  @Prop compactHistoryManaged: boolean = false
  @Prop compactHistoryOpen: boolean = false
  @Prop leadingInset: number = 0
  @Prop inputExpanded: boolean = false
  onInputExpandedChange: (expanded: boolean) => void = (_expanded: boolean) => {}
  onRequestModel: () => void = () => {}
  onCompactHistoryChange: (open: boolean) => void = (_open: boolean) => {}
  @State private historyWidth: number = 0
  @State private historyOpen: boolean = false
  @StorageLink('chatMouseInput') private mouseInput: boolean = false

  // Refresh plain message snapshots without remounting the native text selection.
  private messageForRender(previous: ChatMessage, _renderVersion: number): ChatMessage {
    const message = this.viewModel.messages.find((item: ChatMessage) => item.id === previous.id) ?? previous
    return {
      id: message.id,
      role: message.role,
      content: message.content,
      imageUri: message.imageUri,
      time: message.time,
      includeInContext: message.includeInContext,
      thinkingExpanded: message.thinkingExpanded,
      createdAt: message.createdAt,
      completedAt: message.completedAt,
      modelId: message.modelId,
      modelName: message.modelName,
      kind: message.kind,
      generationState: message.generationState,
      imageUnavailable: message.imageUnavailable,
      perfMetrics: message.perfMetrics
    }
  }

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
  @State private chatHeight: number = 0
  @State private editorRegionHeight: number = 0
  @State private attachmentHeight: number = 64
  @State private composerHeaderHeight: number = 16
  @State private collapsedComposerRegionHeight: number = 64
  @State private inputFrameHeight: number = 44
  @State private animatedInputHeight: number = -1
  private composerAnimationSerial: number = 0
  private composing: boolean = false
  private enterHeld: boolean = false
  private enterConsumed: boolean = false
  private suppressEnterNewline: boolean = false
  private submitOnNewline: boolean = false

  private wideHistory(): boolean {
    return this.historyWidth >= 872
  }

  private isHistoryOpen(): boolean {
    return this.compactHistoryManaged && !this.wideHistory() ? this.compactHistoryOpen : this.historyOpen
  }

  private setHistoryOpen(open: boolean): void {
    if (this.compactHistoryManaged && !this.wideHistory()) {
      this.onCompactHistoryChange(open)
      return
    }
    this.getUIContext().animateTo({ duration: 220, curve: Curve.EaseInOut }, () => {
      this.historyOpen = open
    })
  }

  aboutToAppear(): void {
    this.viewModel.bindHistoryClose((): boolean => {
      if (!this.isHistoryOpen() || this.wideHistory()) return false
      this.setHistoryOpen(false)
      return true
    })
  }

  private onActiveChange(): void {
    if (!this.active) {
      if (!this.wideHistory()) this.setHistoryOpen(false)
      this.inputController.stopEditing()
      this.composerAnimationSerial++
      this.animatedInputHeight = -1
      this.onInputExpandedChange(false)
    }
  }

  private sendKeyboardMessage(): void {
    if (this.active && this.inputFocused && (this.wideHistory() || !this.isHistoryOpen()) && !this.dialogVisible && this.viewModel.loaded &&
      !this.viewModel.busy && !this.viewModel.generating && !this.viewModel.speechRecognitionStarting &&
      !this.viewModel.speechRecognizing && this.viewModel.inputText.trim().length > 0) {
      this.submitMessage()
    }
  }

  private handleInputKey(event: KeyEvent): boolean {
    if (event.keyCode === KeyCode.KEYCODE_ESCAPE && event.type === KeyType.Down &&
      this.active && this.inputFocused && !this.dialogVisible && !this.composing) {
      if (this.inputExpanded) {
        this.toggleInputSize()
      } else {
        this.inputController.stopEditing()
      }
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

  private composerMaxHeight(): number {
    return this.chatHeight > 0 ? Math.min(144, Math.max(66, this.chatHeight * 0.35)) : 144
  }

  private composerRightPadding(): number {
    return this.viewModel.currentModel().supportsImage && this.viewModel.loaded ? 94 : 58
  }

  private wideComposer(): boolean {
    return this.historyWidth >= 600
  }

  private expandedInputHeight(): number {
    return this.wideComposer() ? Math.min(240, Math.max(144, this.chatHeight * 0.5)) :
      Math.max(44, this.editorRegionHeight - this.composerHeaderHeight - 6 -
        (this.viewModel.selectedImageUri.length > 0 ? this.attachmentHeight + 6 : 0))
  }

  private collapsedInputHeight(): number {
    const textHeight = this.getUIContext().px2vp(this.inputController.getTextContentRect().height)
    return Math.min(this.composerMaxHeight(), Math.max(44, textHeight + 23))
  }

  private toggleInputSize(): void {
    const expanded = !this.inputExpanded
    const serial = ++this.composerAnimationSerial
    const targetHeight = expanded ? this.expandedInputHeight() : this.collapsedInputHeight()
    const targetComposerHeight = targetHeight + this.composerHeaderHeight + 6 +
      (this.viewModel.selectedImageUri.length > 0 ? this.attachmentHeight + 6 : 0)
    this.animatedInputHeight = this.inputFrameHeight
    this.getUIContext().animateTo({ duration: 220, curve: Curve.EaseInOut,
      onFinish: () => {
        if (serial === this.composerAnimationSerial) {
          if (!expanded) this.collapsedComposerRegionHeight = targetComposerHeight
          this.animatedInputHeight = -1
        }
      }
    }, () => {
      this.onInputExpandedChange(expanded)
      this.animatedInputHeight = targetHeight
    })
  }

  private submitMessage(): void {
    this.composerAnimationSerial++
    this.animatedInputHeight = -1
    this.inputController.stopEditing()
    this.getUIContext().getFocusController().clearFocus()
    this.onInputExpandedChange(false)
    this.viewModel.sendMessage()
  }

  @Builder
  private ComposerInput() {
    TextArea({ text: this.viewModel.inputText,
      placeholder: this.viewModel.speechRecognizing ? '正在聆听...' :
        (this.viewModel.loaded ? '输入您的问题...' : '请先加载模型...'),
      controller: this.inputController })
      .hitTestBehavior(this.viewModel.loaded ? HitTestMode.Default : HitTestMode.None)
      .enabled(this.viewModel.loaded && !this.viewModel.speechRecognitionStarting &&
        !this.viewModel.speechRecognizing)
      .id('chat-input')
      .height(this.animatedInputHeight >= 0 ? this.animatedInputHeight :
        (this.inputExpanded ? this.expandedInputHeight() : 'auto'))
      .minLines(1)
      .constraintSize({ minHeight: 44, maxHeight: this.inputExpanded || this.animatedInputHeight >= 0 ? undefined : this.composerMaxHeight() })
      .lineHeight(21)
      .align(Alignment.TopStart)
      .fontSize(14)
      .fontColor($r('app.color.text_body'))
      .placeholderColor($r('app.color.text_muted'))
      .placeholderFont({ size: 14 })
      .backgroundColor($r('app.color.composer_background'))
      .borderRadius(10)
      .padding({ left: 16, right: this.composerRightPadding(), top: 11.5, bottom: 11.5 })
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
      .onAreaChange((_oldArea: Area, newArea: Area) => {
        this.inputFrameHeight = Number(newArea.height)
      })
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

  @Builder
  private ChatBody() {
    Column({ space: 6 }) {
      if (this.compactTicker) {
        ChatRunTicker({ viewModel: this.viewModel, active: this.active, compact: true, topSpacing: 0 })
          .margin({ left: -this.contentInset, right: -this.contentInset })
      }
      Row({ space: 8 }) {
        Button({ type: ButtonType.Normal }) {
          Image($r('app.media.icon_chat_history')).width(22).height(22)
            .fillColor($r('app.color.text_secondary'))
        }.width(34).height(34).padding(0).borderRadius(8)
          .backgroundColor(this.isHistoryOpen() ? $r('app.color.nav_selected_background') : Color.Transparent)
          .hoverEffect(HoverEffect.Auto)
          .accessibilityText(this.isHistoryOpen() ? '收起历史对话' : '展开历史对话')
          .onClick(() => {
            this.inputController.stopEditing()
            this.setHistoryOpen(!this.isHistoryOpen())
          })
        Text(this.viewModel.currentConversationTitle())
          .fontSize(15).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_title'))
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
      }.width('100%').height(34)
      if (this.viewModel.historyError.length > 0) {
        Row({ space: 8 }) {
          Text(this.viewModel.historyError).fontSize(12).lineHeight(18)
            .fontColor($r('app.color.status_warning')).layoutWeight(1)
          Button('重试').attributeModifier(new CompactActionStyle())
            .enabled(!this.viewModel.historyBusy).onClick(() => this.viewModel.retryHistorySave())
        }.width('100%').padding(8).backgroundColor($r('app.color.inset')).borderRadius(8)
      }
      Stack({ alignContent: Alignment.Bottom }) {
      Column() {
      List({ space: 10, scroller: this.viewModel.chatScroller }) {
        ForEach(this.viewModel.messages, (message: ChatMessage, index: number) => {
          ListItem() {
            Column({ space: 8 }) {
              if (this.dateBefore(index).length > 0) {
                Text(this.dateBefore(index)).fontSize(11).fontColor($r('app.color.text_muted'))
                  .width('100%').textAlign(TextAlign.Center).padding({ top: 6, bottom: 2 })
              }
              if (message.kind === 'notice' && message.role !== 'assistant') {
                Text(message.content).fontSize(12).lineHeight(18).fontColor($r('app.color.text_muted'))
                  .width('100%').textAlign(TextAlign.Center).padding({ left: 12, right: 12, top: 6, bottom: 6 })
              } else {
            MessageBubble({
              message: this.messageForRender(message, this.renderVersion),
              canRegenerate: this.viewModel.canRegenerateAnswer(message.id),
              canEdit: this.viewModel.canEditQuestion(message.id),
              confirmEdit: this.viewModel.needsEditQuestionConfirmation(message.id),
              onEdit: (text: string, skip: boolean) => this.viewModel.resendEditedQuestion(message.id, text, skip),
              highlighted: this.viewModel.highlightedMessageId === message.id,
              onRegenerate: () => { this.viewModel.regenerateAnswer(message.id) },
              onAnswerSelection: () => this.viewModel.pauseChatAutoScroll(),
              onToggleThinking: (messageId: number) => {
                this.viewModel.toggleMessageThinking(messageId)
              }
            })
              }
            }.width('100%')
          }
        }, (message: ChatMessage) => {
          return `${this.viewModel.activeConversationId}:${message.id}`
        })
      }
      .layoutWeight(1)
      .clip(true)
      .id('chat-messages')
      .onAppear(() => {
        if (this.active) this.viewModel.scrollToBottom()
      })
      .width('100%')
      .divider({ strokeWidth: 0 })
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .onTouch((event: TouchEvent) => {
        if (event.type === TouchType.Down) {
          this.viewModel.pauseChatAutoScroll()
        }
      })
      .onClick(() => {
        this.inputController.stopEditing()
      })
      }.width('100%').height('100%')
        .padding({ bottom: this.collapsedComposerRegionHeight + 6 })

      Column({ space: 6 }) {
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
        .onAreaChange((_oldArea: Area, newArea: Area) => { this.attachmentHeight = Number(newArea.height) })
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
        .onAreaChange((_oldArea: Area, newArea: Area) => { this.composerHeaderHeight = Number(newArea.height) })

        Stack({ alignContent: Alignment.BottomEnd }) {
          this.ComposerInput()

          if (this.inputFrameHeight >= 80) {
            Button({ type: ButtonType.Normal }) {
              SymbolGlyph(this.inputExpanded ? $r('sys.symbol.arrow_down_right_and_arrow_up_left') :
                $r('sys.symbol.arrow_up_left_and_arrow_down_right')).fontSize(18)
                .fontColor([$r('app.color.text_secondary')])
            }.width(32).height(32).padding(0).borderRadius(8).backgroundColor(Color.Transparent)
              .enabled(!this.viewModel.speechRecognitionStarting && !this.viewModel.speechRecognizing)
              .position({ top: 4, right: 14 })
              .focusOnTouch(false)
              .id(this.inputExpanded ? 'chat-input-collapse' : 'chat-input-expand')
              .accessibilityText(this.inputExpanded ? '收起编辑区' : '展开编辑区').onClick(() => {
                this.toggleInputSize()
              })
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
                      this.submitMessage()
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
          .margin({ right: 10, bottom: 2 })
        }
        .width('100%')
        .backgroundColor($r('app.color.composer_background'))
        .borderRadius(10)
        .clip(true)
        .onClick(() => {
          if (!this.viewModel.loaded && !this.viewModel.modelLoading) {
            this.onRequestModel()
          }
        })
      }
      .width('100%')
      .flexShrink(0)
      .justifyContent(FlexAlign.End)
      }.width('100%').backgroundColor(this.compactPage ? $r('app.color.page_compact') : $r('app.color.page'))
        .onAreaChange((_oldArea: Area, newArea: Area) => {
          if (!this.inputExpanded && this.animatedInputHeight < 0) {
            this.collapsedComposerRegionHeight = Number(newArea.height)
          }
        })
      }.width('100%').layoutWeight(1).clip(true)
        .onAreaChange((_oldArea: Area, newArea: Area) => { this.editorRegionHeight = Number(newArea.height) })
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
          .border({ width: { right: 0.5 }, color: $r('app.color.divider') })
          .hitTestBehavior(this.wideHistory() && this.historyOpen ? HitTestMode.Default : HitTestMode.None)
          .accessibilityLevel(this.wideHistory() && this.historyOpen ? 'auto' : 'no-hide-descendants')
        Column() {
          this.ChatBody()
        }.layoutWeight(1).height('100%').alignItems(HorizontalAlign.Center)
          .padding({ left: this.wideHistory() && this.historyOpen ? 12 : this.leadingInset + this.contentInset,
            right: this.contentInset, bottom: this.contentBottomInset })
      }.width('100%').height('100%')
      if (!this.compactHistoryManaged && !this.wideHistory() && this.historyOpen) {
        Column().width('100%').height('100%').backgroundColor('#66000000')
          .onClick(() => this.setHistoryOpen(false))
          .transition(TransitionEffect.OPACITY.animation({ duration: 220, curve: Curve.EaseInOut }))
        Column() {
          ChatHistoryPanel({ viewModel: this.viewModel, renderVersion: this.renderVersion,
            closeOnSelection: true, onClose: () => this.setHistoryOpen(false) })
        }.width(Math.max(1, Math.min(280, this.historyWidth - 40))).height('100%')
          .padding({ bottom: 8 })
          .border({ width: { right: 0.5 }, color: $r('app.color.divider') })
          .backgroundColor($r('app.color.page')).hitTestBehavior(HitTestMode.BLOCK_HIERARCHY)
          .transition(TransitionEffect.move(TransitionEdge.START).combine(TransitionEffect.OPACITY)
            .animation({ duration: 220, curve: Curve.EaseInOut }))
      }
    }.width('100%').layoutWeight(1)
      .onTouch((event: TouchEvent) => {
        if (event.source === SourceType.TouchScreen) this.mouseInput = false
      })
      .onMouse(() => { this.mouseInput = true })
      .onAreaChange((_oldArea: Area, newArea: Area) => {
        const wasWide = this.wideHistory()
        this.historyWidth = Number(newArea.width)
        this.chatHeight = Number(newArea.height)
        if (wasWide !== this.wideHistory()) this.historyOpen = false
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
