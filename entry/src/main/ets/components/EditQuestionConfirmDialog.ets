import { ActionButtonStyle } from './ButtonStyles'

@CustomDialog
export struct EditQuestionConfirmDialog {
  controller: CustomDialogController
  @State private skipNextTime: boolean = false
  onCancel: () => void = () => {}
  onConfirm: (skipNextTime: boolean) => void = (_skipNextTime: boolean) => {}

  build() {
    Column({ space: 14 }) {
      Text('重发这条问题？')
        .fontSize(20).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_title'))
        .width('100%')
      Text('原来的回答和后续聊天记录将被删除，随后会按修改后的问题重新回答。删除的记录无法恢复。')
        .fontSize(14).lineHeight(21).fontColor($r('app.color.text_secondary')).width('100%')
      Row({ space: 8 }) {
        Checkbox({ name: 'skip-edit-confirmation' })
          .select(this.skipNextTime)
          .selectedColor($r('app.color.button_primary_background'))
          .width(18).height(18).margin(0)
          .onChange((value: boolean) => { this.skipNextTime = value })
        Text('不再提示').fontSize(13).fontColor($r('app.color.text_secondary'))
          .onClick(() => { this.skipNextTime = !this.skipNextTime })
      }.width('100%').height(32)
      Row({ space: 10 }) {
        Button('取消', { type: ButtonType.Normal })
          .attributeModifier(new ActionButtonStyle($r('app.color.button_secondary_background'), $r('app.color.button_secondary_text')))
          .layoutWeight(1).onClick(() => this.onCancel())
        Button('确认重发', { type: ButtonType.Normal })
          .attributeModifier(new ActionButtonStyle($r('app.color.button_primary_background'), $r('app.color.button_primary_text')))
          .layoutWeight(1).onClick(() => this.onConfirm(this.skipNextTime))
      }.width('100%')
    }
    .padding(18)
    .width('90%').constraintSize({ maxWidth: 480 })
    .backgroundColor($r('app.color.dialog'))
    .border({ width: 1, color: $r('app.color.border') })
    .borderRadius($r('app.float.dialog_radius'))
  }
}
