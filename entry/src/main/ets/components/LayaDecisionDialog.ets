import { dialogFade, dialogScale } from './DialogMotion'
import { InputFieldStyle } from './ControlStyles'
import { common } from '@kit.AbilityKit'
import fs from '@ohos.file.fs'
import { BuiltinModelInstallProgress, formatBytes } from '../models/BuiltinModelDownloadTypes'
import { BuiltinModelInstallService } from '../services/BuiltinModelInstallService'
import { isLayaLoaded } from '../services/LayaDecisionService'
import { LAYA_MODEL_ID, LAYA_MODEL_DIRECTORY, LAYA_MODEL_FILE, LAYA_TOKENIZER_FILE,
  LAYA_MODEL_BYTES, LAYA_TOKENIZER_BYTES, LAYA_DOWNLOAD_SPEC } from '../models/LayaModelConfig'
import { formatDownloadError } from '../utils/formatters'


type LayaQuestionType = 'choice' | 'score' | 'noul'

interface LayaQuestionInput {
  t: LayaQuestionType
  ins: string
  crit: string[] | Record<string, string>
}

interface LayaRequestInput {
  state: string
  question: LayaQuestionInput
}

interface PreparedQuestion {
  request: LayaRequestInput
  labels: string[]
  options: string[]
}

interface LayaNativeResult {
  logits: number[]
  act_probs: number[]
  elapsed_ms: number
}

interface LayaDisplayAnswer {
  type: LayaQuestionType
  choice?: string
  score?: number
  noul?: number
  probabilities: Record<string, number>
}

interface LayaDisplayAnswers {
  question: LayaDisplayAnswer
}

interface LayaDisplayMetadata {
  task_calibrated: boolean
  elapsed_ms: number
}

interface LayaDisplayReport {
  model: string
  answers: LayaDisplayAnswers
  metadata: LayaDisplayMetadata
}

@Component
export struct LayaDecisionDialog {
  @Prop availableWidth: number = 360
  @Prop availableHeight: number = 640
  @Prop filesDir: string = ''
  @State private stateText: string = ''
  @State private questionText: string = ''
  @State private questionType: LayaQuestionType = 'choice'
  @State private criteriaText: string = ''
  @State private previewText: string = ''
  @State private validationText: string = ''
  @State private resultText: string = ''
  @State private jsonResultText: string = ''
  @State private showRawResult: boolean = false
  @State private running: boolean = false
  @State private modelChecking: boolean = true
  @State private modelReady: boolean = false
  @State private downloadRunning: boolean = false
  @State private downloadBytes: number = 0
  @State private downloadProgress: number = 0
  @State private downloadError: string = ''
  @State private mobileView: 'input' | 'result' = 'input'
  @State private isClosePressed: boolean = false
  private closing: boolean = false
  private inputRevision: number = 0
  private installService: BuiltinModelInstallService = new BuiltinModelInstallService()
  onClose: () => void = () => {}
  onDecision: (state: string, type: string, instruction: string, options: string[]) => Promise<string> =
    async () => { throw new Error('请先在模型页加载决策模型') }
  onModelReady: () => void = () => {}

  aboutToAppear(): void {
    this.refreshModelState()
  }

  aboutToDisappear(): void {
    this.closing = true
    if (this.downloadRunning) this.installService.cancelInstall()
  }

  private async hasCompleteFile(name: string, size: number): Promise<boolean> {
    try {
      const stat = await fs.stat(`${this.filesDir}/${LAYA_MODEL_DIRECTORY}/${name}`)
      return stat.isFile() && stat.size === size
    } catch (_error) {
      return false
    }
  }

  private async refreshModelState(): Promise<void> {
    const ready = await this.hasCompleteFile(LAYA_MODEL_FILE, LAYA_MODEL_BYTES) &&
      await this.hasCompleteFile(LAYA_TOKENIZER_FILE, LAYA_TOKENIZER_BYTES)
    if (this.closing) return
    this.modelReady = ready
    this.onModelReady()
    const downloadedBytes = ready ? LAYA_DOWNLOAD_SPEC.totalBytes :
      await this.installService.existingPartialDownloadBytes(this.filesDir, LAYA_DOWNLOAD_SPEC)
    if (this.closing) return
    this.downloadBytes = downloadedBytes
    this.downloadProgress = Math.round(this.downloadBytes / LAYA_DOWNLOAD_SPEC.totalBytes * 100)
    this.modelChecking = false
  }

  private async downloadModel(): Promise<void> {
    if (this.downloadRunning || this.modelReady) return
    this.downloadRunning = true
    this.downloadError = ''
    try {
      await this.installService.installCatalogItem(this.getUIContext().getHostContext() as common.UIAbilityContext,
        LAYA_DOWNLOAD_SPEC, (progress: BuiltinModelInstallProgress) => {
          if (this.closing) return
          if (progress.progress - this.downloadProgress >= 0.5 || progress.progress === 100) {
            this.downloadProgress = progress.progress
            this.downloadBytes = progress.downloadedBytes
          }
        })
    } catch (error) {
      if (!this.closing && `${error}`.indexOf('下载已取消') < 0) {
        this.downloadError = formatDownloadError(error as Object)
      }
    } finally {
      if (!this.closing) {
        this.downloadRunning = false
        await this.refreshModelState()
      }
    }
  }

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
    if (state.length === 0 || instruction.length === 0) {
      this.validationText = '请填写状态和任务说明'
      this.previewText = ''
      return undefined
    }
    if (this.questionType !== 'noul' && lines.length < 2) {
      this.validationText = this.questionType === 'choice' ? '请至少填写两个候选项' : '请至少填写两个评分等级'
      this.previewText = ''
      return undefined
    }
    if (this.questionType !== 'noul' && lines.length > 20) {
      this.validationText = this.questionType === 'choice' ? '候选项最多 20 个' : '评分等级最多 20 个'
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
    const question: LayaQuestionInput = { t: this.questionType, ins: instruction, crit: criteria }
    const request: LayaRequestInput = { state: state, question: question }
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
    if (!this.modelReady) {
      await this.refreshModelState()
      if (!this.modelReady) {
        this.validationText = '请先下载 Laya 模型和词表'
        return
      }
    }
    if (!isLayaLoaded()) {
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
        prepared.request.question.ins, prepared.options)
      if (revision !== this.inputRevision) {
        this.resultText = '输入已修改，请重新运行决策。'
        return
      }
      const result = JSON.parse(report) as LayaNativeResult
      if (result.logits.length !== prepared.labels.length) throw new Error('模型输出数量与候选项不符')
      const peak = Math.max(...result.logits)
      const weights: number[] = result.logits.map((value: number) => Math.exp(value - peak))
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
      const answer: LayaDisplayAnswer = { type: type, probabilities: probabilities }
      if (type === 'score') answer.score = Number(expectedLevel.toFixed(4))
      else if (type === 'noul') answer.noul = probabilities['true']
      else answer.choice = prepared.labels[winner]
      const displayReport: LayaDisplayReport = {
        model: LAYA_MODEL_ID,
        answers: { question: answer },
        metadata: { task_calibrated: false, elapsed_ms: result.elapsed_ms }
      }
      this.jsonResultText = JSON.stringify(displayReport, null, 2)
      const summary = type === 'score' ? `期望等级：${expectedLevel.toFixed(2)}` : `结果：${prepared.labels[winner]}`
      this.resultText = `${summary}\n${lines.join('\n')}\n耗时：${result.elapsed_ms} ms\n概率未经任务校准。`
    } catch (_error) {
      this.resultText = revision !== this.inputRevision ? '输入已修改，请重新运行决策。' :
        '决策失败，请检查模型状态与输入内容。'
    } finally {
      this.running = false
    }
  }

  @Builder
  private ModelInstallBar() {
    Column({ space: 8 }) {
      Row({ space: 10 }) {
        Column({ space: 3 }) {
          Text(this.modelChecking ? '正在检查 Laya 模型' : this.modelReady ? 'Laya 模型已安装' :
            this.downloadRunning ? '正在下载 Laya 模型' : 'Laya 模型未安装')
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_title'))
          Text(this.downloadError.length > 0 ? this.downloadError :
            this.modelReady ? (isLayaLoaded() ? '模型已加载，可运行决策' : '已安装，请在模型页加载') :
            `${formatBytes(this.downloadBytes)} / ${formatBytes(LAYA_DOWNLOAD_SPEC.totalBytes)} · ModelScope`)
            .fontSize(11)
            .fontColor(this.downloadError.length > 0 ? $r('app.color.status_error') : $r('app.color.text_secondary'))
            .maxLines(2)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        if (!this.modelReady && !this.modelChecking) {
          Button(this.downloadRunning ? '停止下载' : this.downloadBytes > 0 ? '继续下载' : '下载模型')
            .height(34)
            .fontSize(12)
            .fontColor($r('app.color.button_action_text'))
            .backgroundColor($r('app.color.button_action_background'))
            .borderRadius($r('app.float.button_radius'))
            .onClick(() => {
              if (this.downloadRunning) this.installService.cancelInstall()
              else this.downloadModel()
            })
        }
      }
      .width('100%')
      Progress({ value: this.downloadProgress, total: 100, type: ProgressType.Linear })
        .width('100%')
        .height(5)
        .color($r('app.color.status_good'))
        .style({ strokeWidth: 5, strokeRadius: 3 })
    }
    .padding(10)
    .width('100%')
    .backgroundColor($r('app.color.inset'))
    .borderRadius($r('app.float.card_radius'))
  }

  @Builder
  private TypeButton(label: string, type: LayaQuestionType) {
    Button(label)
      .height(38)
      .layoutWeight(1)
      .fontSize(13)
      .fontColor(this.questionType === type ? $r('app.color.nav_active_text') : $r('app.color.text_secondary'))
      .backgroundColor(this.questionType === type ? $r('app.color.selected_background') : $r('app.color.input_background'))
      .borderRadius($r('app.float.button_radius'))
      .border({ width: 1, color: $r('app.color.border') })
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
      Row({ space: 8 }) {
        Text('决策输入')
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_title'))
          .layoutWeight(1)
        Button('填入示例')
          .fontSize(12)
          .height(32)
          .fontColor($r('app.color.button_action_text'))
          .backgroundColor($r('app.color.button_action_background'))
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
      }
      .width('100%')
      Scroll() {
        Column({ space: 14 }) {
          Text('输入文本')
            .fontSize(14)
            .fontColor($r('app.color.text_title'))
            .width('100%')
          TextArea({ placeholder: '粘贴要判断的文本', text: this.stateText })
            .height(88)
            .backgroundColor($r('app.color.input_background'))
            .fontColor($r('app.color.input_text'))
            .placeholderColor($r('app.color.input_placeholder'))
            .caretColor($r('app.color.control_accent'))
            .borderRadius($r('app.float.button_radius'))
            .border({ width: 1, color: $r('app.color.border') })
            .onChange((value: string) => { this.stateText = value; this.invalidateResult() })
          Text('任务类型')
            .fontSize(14)
            .fontColor($r('app.color.text_title'))
            .width('100%')
          Row({ space: 8 }) {
            this.TypeButton('选择', 'choice')
            this.TypeButton('评分', 'score')
            this.TypeButton('是非判断', 'noul')
          }
          .width('100%')
          Text('任务说明')
            .fontSize(14)
            .fontColor($r('app.color.text_title'))
            .width('100%')
          TextInput({ placeholder: '例如：这条反馈主要描述什么问题？', text: this.questionText })
            .attributeModifier(new InputFieldStyle())
            .border({ width: 1, color: $r('app.color.border') })
            .onChange((value: string) => { this.questionText = value; this.invalidateResult() })
          Text(this.questionType === 'choice' ? '候选项（每行“标签：含义”）' :
            this.questionType === 'score' ? '评分等级（由低到高，每行一个）' : '判断标准（可选：第一行“否”，第二行“是”）')
            .fontSize(14)
            .fontColor($r('app.color.text_title'))
            .width('100%')
          TextArea({ placeholder: this.questionType === 'choice' ? '界面：页面布局或交互\n运行：模型加载或生成' :
            this.questionType === 'score' ? '不符合\n部分符合\n完全符合' : '不符合条件\n符合条件', text: this.criteriaText })
            .height(90)
            .backgroundColor($r('app.color.input_background'))
            .fontColor($r('app.color.input_text'))
            .placeholderColor($r('app.color.input_placeholder'))
            .caretColor($r('app.color.control_accent'))
            .borderRadius($r('app.float.button_radius'))
            .border({ width: 1, color: $r('app.color.border') })
            .onChange((value: string) => { this.criteriaText = value; this.invalidateResult() })
        }
        .width('100%')
      }
      .scrollBar(BarState.Auto)
      .layoutWeight(1)
      if (this.validationText.length > 0) {
      Text(this.validationText)
        .fontSize(12)
        .fontColor($r('app.color.status_warning'))
        .height(18)
        .width('100%')
      }
      Row({ space: 8 }) {
        Button('查看输入 JSON')
          .layoutWeight(1)
          .height(40)
          .fontSize(14)
          .fontColor($r('app.color.button_secondary_text'))
          .backgroundColor($r('app.color.button_secondary_background'))
          .borderRadius($r('app.float.button_radius'))
          .onClick(() => this.preview())
        Button(this.running ? '决策中…' : '运行决策')
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
            .height(32)
            .fontSize(12)
            .fontColor($r('app.color.button_action_text'))
            .backgroundColor($r('app.color.button_action_background'))
            .onClick(() => { this.mobileView = 'input' })
        }
        Text(this.previewText.length > 0 && !this.running && this.resultText.length === 0 ? '输入预览' : '决策结果')
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_title'))
          .layoutWeight(1)
        if (this.jsonResultText.length > 0 && !this.running) {
          Button(this.showRawResult ? '查看解读' : '查看 JSON')
            .height(32)
            .fontSize(12)
            .fontColor($r('app.color.button_action_text'))
            .backgroundColor($r('app.color.button_action_background'))
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

      Column({ space: 14 }) {
        Row() {
          Text('Laya 决策')
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
          .accessibilityText('关闭 Laya 决策')
          .onTouch((event: TouchEvent) => {
            this.isClosePressed = event.type === TouchType.Down
          })
          .onClick(() => this.onClose())
        }
        Text('根据输入完成选择、评分或是非判断。')
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
        this.ModelInstallBar()
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
      .padding(18)
      .width(Math.max(1, Math.min(840, this.availableWidth - 32)))
      .height(Math.max(1, Math.min(800, this.availableHeight * 0.85)))
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
