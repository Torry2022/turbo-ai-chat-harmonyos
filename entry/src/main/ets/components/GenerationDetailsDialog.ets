import { ChatMessage } from '../models/ChatTypes'
import { generationDetailRows, RunDetailRow } from '../utils/generationDetails'
import { ActionButtonStyle } from './ButtonStyles'

@CustomDialog
export struct GenerationDetailsDialog {
  controller: CustomDialogController
  message: ChatMessage = { id: 0, role: 'assistant', content: '', imageUri: '', time: '',
    includeInContext: false, thinkingExpanded: false }
  onClose: () => void = () => {}
  onExport: () => void = () => {}

  build() {
    Column({ space: 16 }) {
      Text('运行详情').fontSize(20).fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_title')).width('100%')
      Scroll() {
        Column({ space: 12 }) {
          ForEach(generationDetailRows(this.message), (row: RunDetailRow) => {
            Row({ space: 16 }) {
              Text(row.label).fontSize(14).fontColor($r('app.color.text_secondary')).layoutWeight(1)
              Text(row.value).fontSize(14).fontColor($r('app.color.text_body'))
                .textAlign(TextAlign.End).constraintSize({ maxWidth: '65%' })
            }.width('100%')
          }, (row: RunDetailRow) => row.label)
          Text('首段等待从请求开始计至收到首段输出。推理框架记录的阶段耗时可能重叠。')
            .fontSize(12).lineHeight(18).fontColor($r('app.color.text_muted')).width('100%')
        }.width('100%').padding({ right: 12 })
      }.constraintSize({ maxHeight: 380 }).width('100%')
      Row({ space: 10 }) {
        Button('关闭', { type: ButtonType.Normal })
          .attributeModifier(new ActionButtonStyle($r('app.color.button_secondary_background'), $r('app.color.button_secondary_text')))
          .layoutWeight(1).onClick(this.onClose)
        Button('导出记录', { type: ButtonType.Normal })
          .attributeModifier(new ActionButtonStyle($r('app.color.button_primary_background'), $r('app.color.button_primary_text')))
          .layoutWeight(1).onClick(this.onExport)
      }.width('100%')
    }.padding(18).width('90%').constraintSize({ maxWidth: 480 })
      .backgroundColor($r('app.color.dialog')).border({ width: 1, color: $r('app.color.border') })
      .borderRadius($r('app.float.dialog_radius'))
  }
}
