import { ChatConversationSummary, historyGroup } from '../models/ChatHistoryTypes'
import { ChatViewModel } from '../state/ChatViewModel'
import { ActionButtonStyle } from './ButtonStyles'
import { KeyCode } from '@kit.InputKit'
import { InputFieldStyle } from './ControlStyles'

@Component
export struct ChatHistoryPanel {
  @ObjectLink viewModel: ChatViewModel
  @Prop renderVersion: number = 0
  @Prop closeOnSelection: boolean = false
  onClose: () => void = () => {}
  @State private editingId: string = ''
  @State private titleInput: string = ''

  private groupBefore(index: number): string {
    const items = this.viewModel.conversations
    const group = historyGroup(items[index].updatedAt)
    return index === 0 || historyGroup(items[index - 1].updatedAt) !== group ? group : ''
  }

  private handleRenameKey(event: KeyEvent): boolean {
    if (event.keyCode === KeyCode.KEYCODE_ESCAPE && event.type === KeyType.Down && !this.viewModel.historyBusy) {
      this.editingId = ''
      return true
    }
    return false
  }

  private saveTitle(): void {
    if (!this.editingId || !this.titleInput.trim() || !this.viewModel.canManageConversations()) return
    const editingId = this.editingId
    this.viewModel.renameConversation(editingId, this.titleInput).then(() => {
      if (this.editingId === editingId && !this.viewModel.historyError) this.editingId = ''
    })
  }

  private confirmDelete(item?: ChatConversationSummary): void {
    this.getUIContext().getPromptAction().showDialog({
      title: item ? '删除对话？' : '清空全部对话？',
      message: item ? `“${item.title}”将被删除，此操作无法撤销。` : '所有历史对话将被删除，此操作无法撤销。',
      buttons: [
        { text: '取消', color: $r('app.color.text_muted') },
        { text: item ? '删除' : '清空全部', color: $r('app.color.button_danger_text') }
      ]
    }).then((result) => {
      if (result.index === 1) this.viewModel.deleteConversation(item?.id)
    }).catch(() => {})
  }

  build() {
    Column({ space: 8 }) {
      Row({ space: 4 }) {
        Text('历史对话').fontSize(14).fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_secondary')).layoutWeight(1)
        Button('清空').width(40).height(30).padding(0).fontSize(12).borderRadius(6)
          .fontColor($r('app.color.text_muted')).backgroundColor(Color.Transparent)
          .hoverEffect(HoverEffect.Auto).accessibilityText('清空全部对话')
          .enabled(this.viewModel.canManageConversations() &&
            (this.viewModel.conversations.length > 0 || this.viewModel.historyError.length > 0))
          .onClick(() => this.confirmDelete())
      }.width('100%').height(36).padding({ left: 8, right: 2 })
      if (this.viewModel.conversations.length === 0) {
        Column({ space: 6 }) {
          Text(this.viewModel.historyReady ? '暂无对话' : '正在读取…')
            .fontSize(13).fontColor($r('app.color.text_secondary'))
        }.width('100%').alignItems(HorizontalAlign.Start).padding({ left: 6, right: 6, top: 18 })
        Blank()
      } else {
        List({ space: 2 }) {
          ForEach(this.viewModel.conversations, (item: ChatConversationSummary, index: number) => {
            ListItem() {
              Column({ space: 4 }) {
                if (this.groupBefore(index).length > 0) {
                  Text(this.groupBefore(index)).fontSize(11).fontColor($r('app.color.text_muted'))
                    .width('100%').padding({ left: 8, top: index > 0 ? 12 : 6, bottom: 4 })
                }
                if (this.editingId === item.id) {
                  Column({ space: 8 }) {
                    TextInput({ text: this.titleInput, placeholder: '对话名称' })
                      .attributeModifier(new InputFieldStyle()).fontSize(13).height(36).maxLength(100)
                      .border({ width: 1, color: $r('app.color.control_accent') })
                      .padding({ left: 10, right: 10 })
                      .enabled(!this.viewModel.historyBusy).id('history-rename-input')
                      .onChange((value: string) => { this.titleInput = value })
                      .onSubmit(() => this.saveTitle())
                      .onKeyEvent((event: KeyEvent): boolean => this.handleRenameKey(event))
                      .onAppear(() => this.getUIContext().getFocusController().requestFocus('history-rename-input'))
                    Row({ space: 8 }) {
                      Button('取消')
                        .attributeModifier(new ActionButtonStyle($r('app.color.button_secondary_background'), $r('app.color.button_secondary_text')))
                        .layoutWeight(1).height(30).fontSize(12).borderRadius(6)
                        .enabled(!this.viewModel.historyBusy).onClick(() => { this.editingId = '' })
                      Button(this.viewModel.historyBusy ? '保存中…' : '保存')
                        .attributeModifier(new ActionButtonStyle($r('app.color.button_primary_background'), $r('app.color.button_primary_text')))
                        .layoutWeight(1).height(30).fontSize(12).borderRadius(6)
                        .enabled(this.titleInput.trim().length > 0 && this.viewModel.canManageConversations())
                        .onClick(() => this.saveTitle())
                    }.width('100%')
                  }.width('100%').padding({ left: 8, right: 8, top: 9, bottom: 9 })
                    .onKeyEvent((event: KeyEvent): boolean => this.handleRenameKey(event))
                } else {
                  Row({ space: 4 }) {
                    Button({ type: ButtonType.Normal }) {
                      Column({ space: 4 }) {
                        Text(item.title).fontSize(13).fontColor($r('app.color.text_body'))
                          .fontWeight(item.id === this.viewModel.activeConversationId ? FontWeight.Medium : FontWeight.Normal)
                          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                          .width('100%').textAlign(TextAlign.Start)
                        Text(item.modelName).fontSize(10).fontColor($r('app.color.text_muted'))
                          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                          .width('100%').textAlign(TextAlign.Start)
                      }.width('100%').alignItems(HorizontalAlign.Start)
                    }.layoutWeight(1).padding(0).backgroundColor(Color.Transparent)
                      .enabled(this.viewModel.canManageConversations())
                      .onClick(() => { this.viewModel.openConversation(item.id).then((opened: boolean) => { if (opened && this.closeOnSelection) this.onClose() }) })
                    Button({ type: ButtonType.Normal }) {
                      Text('⋯').fontSize(21).fontColor($r('app.color.text_muted'))
                    }.width(28).height(30).padding(0).borderRadius(6).backgroundColor(Color.Transparent)
                      .hoverEffect(HoverEffect.Auto).accessibilityText(`管理对话 ${item.title}`)
                      .enabled(this.viewModel.canManageConversations())
                      .bindMenu([
                        { value: '重命名', action: () => { this.editingId = item.id; this.titleInput = item.title } },
                        { value: '删除', action: () => this.confirmDelete(item) }
                      ])
                  }.width('100%').padding({ left: 8, right: 8, top: 9, bottom: 9 })
                    .backgroundColor(item.id === this.viewModel.activeConversationId ? $r('app.color.nav_selected_background') : Color.Transparent)
                    .borderRadius(8).hoverEffect(HoverEffect.Auto)
                }
              }.width('100%')
            }
          }, (item: ChatConversationSummary) => `${item.id}:${item.updatedAt}:${item.title}:${item.modelName}`)
        }.width('100%').layoutWeight(1).scrollBar(BarState.Auto)
      }
    }.width('100%').height('100%').padding({ left: 8, right: 8, top: 2, bottom: 4 })
  }
}
