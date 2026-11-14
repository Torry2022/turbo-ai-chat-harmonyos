import { formatError } from '../utils/formatters'
import { dialogFade, dialogScale } from './DialogMotion'
import { InputFieldStyle } from './ControlStyles'
import { decisionProbabilities, DecisionOutput } from '../utils/decisionOutput'
import { ImagePayloadService } from '../services/ImagePayloadService'
import { ActionButtonStyle, CompactActionStyle } from './ButtonStyles'
import { LAYA_MODEL_ID } from '../models/LayaModelConfig'


type DecisionQuestionType = 'choice' | 'score' | 'noul'

interface DecisionQuestionInput {
  t: DecisionQuestionType
  ins: string
  crit: string[] | Record<string, string>
}

interface DecisionRequestInput {
  state: string
  question: DecisionQuestionInput
}

interface PreparedQuestion {
  request: DecisionRequestInput
  labels: string[]
  options: string[]
}


interface DecisionDisplayAnswer {
  type: DecisionQuestionType
  choice?: string
  score?: number
  noul?: number
  probabilities: Record<string, number>
}

interface DecisionDisplayAnswers {
  question: DecisionDisplayAnswer
}

interface DecisionDisplayMetadata {
  task_calibrated: boolean
  elapsed_ms: number
}

interface DecisionDisplayReport {
  model: string
  answers: DecisionDisplayAnswers
  metadata: DecisionDisplayMetadata
}

@Component
export struct DecisionDialog {
  @Prop availableWidth: number = 360
  @Prop availableHeight: number = 640
  @Prop modelId: string = LAYA_MODEL_ID
  @Prop modelName: string = 'Laya'
  @Prop installed: boolean = false
  @Prop loaded: boolean = false
  @Prop supportsImage: boolean = false
  @State private imageUri: string = ''
  private imageService: ImagePayloadService = new ImagePayloadService()
  @State private stateText: string = ''
  @State private questionText: string = ''
  @State private questionType: DecisionQuestionType = 'choice'
  @State private criteriaText: string = ''
  @State private previewText: string = ''
  @State private validationText: string = ''
  @State private resultText: string = ''
  @State private jsonResultText: string = ''
  @State private showRawResult: boolean = false
  @State private running: boolean = false
  @State private mobileView: 'input' | 'result' = 'input'
  @State private isClosePressed: boolean = false
  private inputRevision: number = 0
  onClose: () => void = () => {}
  onDecision: (state: string, type: string, instruction: string, options: string[], labels: string[], imageUri: string) => Promise<string> =
    async () => { throw new Error('请先在模型页加载决策模型') }

  private invalidateResult(): void {
    this.inputRevision++
    this.previewText = ''
    this.resultText = ''
    this.jsonResultText = ''
    this.validationText = ''
  }

  private prepare(): PreparedQuestion | undefined {
    const state = this.stateText.trim()
    const instruction = this.questionText.trim()
    const lines = this.criteriaText.split('\n').map((line: string) => line.trim()).filter((line: string) => line.length > 0)
    if ((state.length === 0 && this.imageUri.length === 0) || instruction.length === 0) {
      this.validationText = '请填写输入文本或添加图片，并填写任务说明'
      this.previewText = ''
      return undefined
    }
    if (this.questionType !== 'noul' && lines.length < 2) {
      this.validationText = this.questionType === 'choice' ? '请至少填写两个候选项' : '请至少填写两个评分等级'
      this.previewText = ''
      return undefined
    }
    if (this.questionType !== 'noul' && lines.length > (this.modelId === LAYA_MODEL_ID ? 20 : 255)) {
      this.validationText = `最多支持 ${this.modelId === LAYA_MODEL_ID ? 20 : 255} 个${this.questionType === 'choice' ? '候选项' : '评分等级'}`
      this.previewText = ''
      return undefined
    }
    let criteria: string[] | Record<string, string>
    const labels: string[] = []
    const options: string[] = []
    if (this.questionType === 'choice') {
      const choices: Record<string, string> = {}
      for (const line of lines) {
        const separator = line.indexOf('：') >= 0 ? line.indexOf('：') : line.indexOf(':')
        if (separator <= 0) {
          this.validationText = '候选项请按“标签：含义”逐行填写'
          this.previewText = ''
          return undefined
        }
        const label = line.substring(0, separator).trim()
        if (label.length === 0 || choices[label] !== undefined) {
          this.validationText = '候选项标签不能为空或重复'
          this.previewText = ''
          return undefined
        }
        const description = line.substring(separator + 1).trim()
        choices[label] = description
        labels.push(label)
        options.push(description.length > 0 ? `${label}: ${description}` : label)
      }
      criteria = choices
    } else if (this.questionType === 'score') {
      criteria = lines
      for (let index = 0; index < lines.length; index++) {
        labels.push(`等级 ${index}`)
        options.push(`level ${index}: ${lines[index]}`)
      }
    } else {
      criteria = {}
      if (lines.length > 0) criteria['false'] = lines[0]
      if (lines.length > 1) criteria['true'] = lines[1]
      labels.push('否', '是')
      options.push(`false: ${lines.length > 0 ? lines[0] : 'no, the statement does not hold'}`)
      options.push(`true: ${lines.length > 1 ? lines[1] : 'yes, the statement holds'}`)
    }
    this.validationText = ''
    const question: DecisionQuestionInput = { t: this.questionType, ins: instruction, crit: criteria }
    const request: DecisionRequestInput = { state: state, question: question }
    return { request: request, labels: labels, options: options }
  }

  private preview(): void {
    const prepared = this.prepare()
    if (prepared === undefined) return
    this.resultText = ''
    this.jsonResultText = ''
    this.previewText = JSON.stringify(prepared.request, null, 2)
    this.mobileView = 'result'
  }

  private async runDecision(): Promise<void> {
    if (this.running) return
    if (!this.loaded) {
      this.validationText = '请先关闭此窗口，在模型页加载决策模型。'
      return
    }
    const prepared = this.prepare()
    if (prepared === undefined) return
    const revision = this.inputRevision
    this.running = true
    this.resultText = ''
    this.jsonResultText = ''
    this.showRawResult = false
    this.mobileView = 'result'
    try {
      const report: string = await this.onDecision(prepared.request.state, prepared.request.question.t,
        prepared.request.question.ins, prepared.options, prepared.labels, this.imageUri)
      if (revision !== this.inputRevision) {
        this.resultText = '输入已修改，请重新运行决策。'
        return
      }
      const result = JSON.parse(report) as DecisionOutput
      const weights = decisionProbabilities(result, prepared.labels.length)
      const total = weights.reduce((sum: number, value: number) => sum + value, 0)
      const probabilities: Record<string, number> = {}
      for (let index = 0; index < weights.length; index++) {
        const key = prepared.request.question.t === 'choice' ? prepared.labels[index] :
          prepared.request.question.t === 'score' ? `${index}` : index === 0 ? 'false' : 'true'
        probabilities[key] = Number((weights[index] / total).toFixed(4))
      }
      const lines: string[] = prepared.labels.map((label: string, index: number) =>
        `${label}：${(weights[index] / total * 100).toFixed(1)}%`)
      const winner = weights.indexOf(Math.max(...weights))
      const expectedLevel = weights.reduce((sum: number, value: number, index: number) => sum + index * value, 0) / total
      const type = prepared.request.question.t
      const answer: DecisionDisplayAnswer = { type: type, probabilities: probabilities }
      if (type === 'score') answer.score = Number(expectedLevel.toFixed(4))
      else if (type === 'noul') answer.noul = probabilities['true']
      else answer.choice = prepared.labels[winner]
      const displayReport: DecisionDisplayReport = {
        model: this.modelId,
        answers: { question: answer },
        metadata: { task_calibrated: false, elapsed_ms: result.elapsed_ms }
      }
      this.jsonResultText = JSON.stringify(displayReport, null, 2)
      const summary = type === 'score' ? `期望等级：${expectedLevel.toFixed(2)}` : `结果：${prepared.labels[winner]}`
      this.resultText = `${summary}\n${lines.join('\n')}\n耗时：${Math.round(result.elapsed_ms)} ms`
    } catch (error) {
      this.resultText = revision !== this.inputRevision ? '输入已修改，请重新运行决策。' :
        `决策失败：${formatError(error as Object)}`
    } finally {
      this.running = false
    }
  }

  @Builder
  private ModelStatus() {
    Row({ space: 8 }) {
      Text(this.modelName).fontSize(13).lineHeight(18)
        .fontColor($r('app.color.text_secondary')).layoutWeight(1).maxLines(2)
      Text(this.loaded ? '已加载' : this.installed ? '未加载' : '未安装')
        .fontSize(11).fontColor(this.loaded ? $r('app.color.tag_green_text') : $r('app.color.text_muted'))
        .padding({ left: 7, right: 7, top: 3, bottom: 3 }).borderRadius(4)
        .backgroundColor(this.loaded ? $r('app.color.tag_green_background') : $r('app.color.input_background'))
    }.width('100%').padding({ top: 2, bottom: 2 })
  }

  @Builder
  private TypeButton(label: string, type: DecisionQuestionType) {
    Button(label, { type: ButtonType.Normal })
      .height(32)
      .layoutWeight(1)
      .fontSize(13)
      .fontColor(this.questionType === type ? $r('app.color.nav_mobile_selected') : $r('app.color.text_muted'))
      .backgroundColor(this.questionType === type ? $r('app.color.gallery_entry_background') : Color.Transparent)
      .borderRadius(8)
      .clip(true)
      .border({ width: 0 })
      .enabled(!this.running)
      .onClick(() => {
        if (this.questionType === type) return
        this.questionType = type
        this.criteriaText = ''
        this.invalidateResult()
        this.showRawResult = false
      })
  }

  @Builder
  private InputPane() {
    Column({ space: 12 }) {
      Scroll() {
        Column({ space: 10 }) {
          Row({ space: 8 }) {
            Text('输入文本').fontSize(12).fontColor($r('app.color.text_secondary')).layoutWeight(1)
            if (this.supportsImage) {
              Button(this.imageUri.length > 0 ? '更换图片' : '添加图片')
                .attributeModifier(new CompactActionStyle()).enabled(!this.running)
                .onClick(async () => {
                  const uri = await this.imageService.pickImage()
                  if (uri !== undefined) { this.imageUri = uri; this.invalidateResult() }
                })
            }
          }.width('100%')
          TextArea({ placeholder: '粘贴要判断的文本', text: this.stateText })
            .height(76)
            .backgroundColor($r('app.color.input_background'))
            .fontColor($r('app.color.input_text')).fontSize(14).padding(10)
            .placeholderColor($r('app.color.input_placeholder'))
            .caretColor($r('app.color.control_accent'))
            .borderRadius($r('app.float.button_radius'))
            .border({ width: 1, color: $r('app.color.border') })
            .onChange((value: string) => { this.stateText = value; this.invalidateResult() })
          if (this.imageUri.length > 0) {
            Row({ space: 8 }) {
              Image(this.imageUri).width(56).height(56).objectFit(ImageFit.Cover).borderRadius(8)
              Blank()
              Button('移除图片').attributeModifier(new CompactActionStyle()).enabled(!this.running)
                .onClick(() => { this.imageUri = ''; this.invalidateResult() })
            }.width('100%')
          }
          Text('任务类型')
            .fontSize(12)
            .fontColor($r('app.color.text_title'))
            .width('100%')
          Row({ space: 2 }) {
            this.TypeButton('选择', 'choice')
            this.TypeButton('评分', 'score')
            this.TypeButton('是非判断', 'noul')
          }
          .width('100%').height(36).padding(2).borderRadius(10).clip(true).backgroundColor($r('app.color.input_background'))
          Text('任务说明')
            .fontSize(12)
            .fontColor($r('app.color.text_title'))
            .width('100%')
          TextInput({ placeholder: '例如：这条反馈主要描述什么问题？', text: this.questionText })
            .attributeModifier(new InputFieldStyle())
            .border({ width: 1, color: $r('app.color.border') })
            .onChange((value: string) => { this.questionText = value; this.invalidateResult() })
          Text(this.questionType === 'choice' ? '候选项（每行“标签：含义”）' :
            this.questionType === 'score' ? '评分等级（由低到高，每行一个）' : '判断标准（可选：第一行“否”，第二行“是”）')
            .fontSize(12)
            .fontColor($r('app.color.text_title'))
            .width('100%')
          TextArea({ placeholder: this.questionType === 'choice' ? '界面：页面布局或交互\n运行：模型加载或生成' :
            this.questionType === 'score' ? '不符合\n部分符合\n完全符合' : '不符合条件\n符合条件', text: this.criteriaText })
            .height(84)
            .backgroundColor($r('app.color.input_background'))
            .fontColor($r('app.color.input_text')).fontSize(14).padding(10)
            .placeholderColor($r('app.color.input_placeholder'))
            .caretColor($r('app.color.control_accent'))
            .borderRadius($r('app.float.button_radius'))
            .border({ width: 1, color: $r('app.color.border') })
            .onChange((value: string) => { this.criteriaText = value; this.invalidateResult() })
        }
        .width('100%')
      }
      .scrollBar(BarState.Auto)
      .align(Alignment.TopStart)
      .layoutWeight(1)
      if (this.validationText.length > 0) {
      Text(this.validationText)
        .fontSize(12)
        .fontColor($r('app.color.status_warning'))
        .lineHeight(18).maxLines(2)
        .width('100%')
      }
      Row({ space: 8 }) {
        Button('查看 JSON')
          .attributeModifier(new CompactActionStyle())
          .enabled(!this.running)
          .onClick(() => this.preview())
        Button('填入示例')
          .attributeModifier(new CompactActionStyle())
          .onClick(() => {
            this.stateText = '手机键盘弹出后底部标签也跟着上移。'
            if (this.questionType === 'choice') {
              this.questionText = '这段反馈主要描述哪一类问题？'
              this.criteriaText = 'import：模型下载或导入\ninference：模型加载或回答生成\nui：页面布局或交互\nother：其他问题'
            } else if (this.questionType === 'score') {
              this.questionText = '这条反馈对正常使用的影响程度如何？'
              this.criteriaText = '几乎不影响使用\n影响部分操作\n严重阻碍使用'
            } else {
              this.questionText = '这条反馈是否描述界面布局问题？'
              this.criteriaText = '不是界面布局问题\n是界面布局问题'
            }
            this.invalidateResult()
            this.showRawResult = false
          })
        Button(this.running ? '决策中…' : '运行决策', { type: ButtonType.Normal })
          .attributeModifier(new ActionButtonStyle($r('app.color.button_primary_background'), $r('app.color.button_primary_text')))
          .enabled(this.loaded && !this.running)
          .layoutWeight(1)
          .height(40)
          .fontSize(14)
          .fontColor($r('app.color.button_primary_text'))
          .backgroundColor($r('app.color.button_primary_background'))
          .borderRadius($r('app.float.button_radius'))
          .onClick(() => { this.runDecision() })
      }
      .width('100%')
    }
    .height('100%')
  }

  @Builder
  private ResultPane(showBack: boolean) {
    Column({ space: 12 }) {
      Row({ space: 8 }) {
        if (showBack) {
          Button('返回修改')
            .attributeModifier(new CompactActionStyle())
            .onClick(() => { this.mobileView = 'input' })
        }
        Text(this.previewText.length > 0 && !this.running && this.resultText.length === 0 ? '输入预览' : '决策结果')
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_title'))
          .layoutWeight(1)
        if (this.jsonResultText.length > 0 && !this.running) {
          Button(this.showRawResult ? '查看解读' : '查看 JSON')
            .attributeModifier(new CompactActionStyle())
            .onClick(() => { this.showRawResult = !this.showRawResult })
        }
      }
      .width('100%')
      .height(32)
      Scroll() {
        Column() {
          Text(this.running ? '正在执行决策，请稍候…' :
            this.resultText.length > 0 ? (this.showRawResult ? this.jsonResultText : this.resultText) :
            this.previewText.length > 0 ? this.previewText : '运行决策后，结果将在这里显示。')
            .fontSize(this.showRawResult || this.previewText.length > 0 && this.resultText.length === 0 ? 12 : 14)
            .fontColor(this.running || this.resultText.length === 0 && this.previewText.length === 0 ?
              $r('app.color.text_secondary') : $r('app.color.text_body'))
            .lineHeight(this.showRawResult || this.previewText.length > 0 && this.resultText.length === 0 ? 18 : 22)
            .width('100%')
            .copyOption(CopyOptions.LocalDevice)
        }
        .width('100%')
      }
      .scrollBar(BarState.Auto)
      .align(Alignment.TopStart)
      .layoutWeight(1)
      .padding(14)
      .width('100%')
      .backgroundColor($r('app.color.inset'))
      .borderRadius($r('app.float.card_radius'))
    }
    .height('100%')
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.scrim'))
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        .onClick(() => this.onClose())

      Column({ space: 10 }) {
        Row() {
          Text('决策试用')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_title'))
            .layoutWeight(1)
          Button({ type: ButtonType.Normal }) {
            Image(this.isClosePressed ? $r('app.media.model_market_close_icon_pressed') :
              $r('app.media.model_market_close_icon'))
              .width(24)
              .height(24)
          }
          .width(40)
          .height(40)
          .backgroundColor(Color.Transparent)
          .accessibilityText('关闭决策窗口')
          .onTouch((event: TouchEvent) => {
            this.isClosePressed = event.type === TouchType.Down
          })
          .onClick(() => this.onClose())
        }
        this.ModelStatus()
        if (!this.loaded) {
          Text('请先在模型页加载所选模型。').fontSize(12).fontColor($r('app.color.text_muted')).width('100%')
        }
        if (this.availableWidth >= 820) {
          Row({ space: 16 }) {
            Column() {
              this.InputPane()
            }
            .layoutWeight(1)
            .height('100%')
            Column() {
              this.ResultPane(false)
            }
            .layoutWeight(1)
            .height('100%')
          }
          .width('100%')
          .layoutWeight(1)
        } else {
          Column() {
            if (this.mobileView === 'input') {
              this.InputPane()
            } else {
              this.ResultPane(true)
            }
          }
          .width('100%')
          .layoutWeight(1)
        }
      }
      .padding(12)
      .width(Math.max(1, Math.min(840, this.availableWidth - 32)))
      .height(Math.max(1, Math.min(this.availableWidth < 600 ? 640 : 800,
        this.availableHeight * (this.availableWidth < 600 ? 0.78 : 0.85))))
      .backgroundColor($r('app.color.dialog'))
      .border({ width: 1, color: $r('app.color.border') })
      .borderRadius($r('app.float.dialog_radius'))
      .transition(dialogScale())
    }
    .width('100%')
    .height('100%')
    .transition(dialogFade())
  }
}
