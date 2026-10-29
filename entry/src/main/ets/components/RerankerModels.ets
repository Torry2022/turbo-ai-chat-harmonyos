import { ChatViewModel } from '../state/ChatViewModel'
import { ModelProfile } from '../models/ModelProfile'
import { ActionButtonStyle } from './ButtonStyles'
import { ParameterSliderStyle } from './ControlStyles'

@Component
export struct RerankerModels {
  @ObjectLink viewModel: ChatViewModel
  @Prop renderVersion: number = 0
  @Prop settings: boolean = false

  private controlsEnabled(): boolean {
    return !this.viewModel.rerankLoading && !this.viewModel.reranker.busy && !this.viewModel.rerankImporting
  }

  @Builder
  private ModelTag(text: string, color: ResourceColor, background: ResourceColor) {
    Text(text).fontSize(11).fontColor(color)
      .padding({ left: 7, right: 7, top: 3, bottom: 3 })
      .backgroundColor(background).borderRadius(4)
  }

  @Builder
  private ModelOption(model: ModelProfile) {
    Column({ space: 4 }) {
      Row({ space: 6 }) {
        Text(model.name).layoutWeight(1).fontSize(14).fontWeight(FontWeight.Medium)
          .fontColor(model.id === this.viewModel.rerankSelectedId ?
            $r('app.color.text_title') : $r('app.color.text_secondary'))
        if (model.id === this.viewModel.reranker.loadedId) {
          this.ModelTag('已加载', $r('app.color.tag_green_text'), $r('app.color.tag_green_background'))
        }
      }
      .width('100%')
      Text(model.description === '用户导入的 MNN 模型。' ?
        '用户导入的 MNN 重排模型。' : model.description).fontSize(12).lineHeight(18).width('100%')
        .fontColor(model.id === this.viewModel.rerankSelectedId ?
          $r('app.color.text_note') : $r('app.color.text_caption'))
    }
    .width('100%').padding(10).borderRadius(8)
    .backgroundColor(model.id === this.viewModel.rerankSelectedId ?
      $r('app.color.selected_background') : $r('app.color.list_background'))
    .onClick(() => this.viewModel.selectReranker(model.id))
  }

  build() {
    Column({ space: 10 }) {
      if (this.settings) {
        Text('运行配置').fontSize(16).fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_title')).width('100%')
        Text(`推理线程：${this.viewModel.rerankThreads}`)
          .fontSize(12).fontColor($r('app.color.text_secondary')).width('100%')
        Slider({ value: this.viewModel.rerankThreads, min: 2, max: 8, step: 1 })
          .attributeModifier(new ParameterSliderStyle()).enabled(this.controlsEnabled() && !this.viewModel.loadedReranker())
          .onChange((value: number) => { this.viewModel.rerankThreads = Math.round(value) })
        Text(`单条输入上限：${this.viewModel.rerankMaxTokens} tokens`)
          .fontSize(12).fontColor($r('app.color.text_secondary')).width('100%')
        Slider({ value: this.viewModel.rerankMaxTokens, min: 128, max: 8192, step: 128 })
          .attributeModifier(new ParameterSliderStyle()).enabled(this.controlsEnabled() && !this.viewModel.loadedReranker())
          .onChange((value: number) => { this.viewModel.rerankMaxTokens = Math.round(value) })
        Text('输入上限包含问题、候选文本和模型模板。超长请求会报错，不会自动截断。释放模型后可修改运行配置。')
          .fontSize(12).lineHeight(18).fontColor($r('app.color.text_hint')).width('100%')
        Divider().color($r('app.color.divider')).opacity(0.6)
        Text('导入重排模型').fontSize(16).fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_title')).width('100%')
        Text('支持 Qwen3-Reranker 的 MNN 导出目录。请导入专用重排模型，普通聊天模型不能用于相关性评分。')
          .fontSize(12).lineHeight(18).fontColor($r('app.color.text_muted')).width('100%')
        Row({ space: 10 }) {
          Button('选择文件夹')
            .attributeModifier(new ActionButtonStyle($r('app.color.button_secondary_background'), $r('app.color.button_secondary_text')))
            .layoutWeight(1).enabled(this.controlsEnabled())
            .onClick(() => this.viewModel.importReranker(true))
          Button('导入 ZIP')
            .attributeModifier(new ActionButtonStyle($r('app.color.button_secondary_background'), $r('app.color.button_secondary_text')))
            .layoutWeight(1).enabled(this.controlsEnabled())
            .onClick(() => this.viewModel.importReranker(false))
        }.width('100%')
        Button('扫描已推送目录')
          .attributeModifier(new ActionButtonStyle($r('app.color.button_secondary_background'), $r('app.color.button_secondary_text')))
          .width('100%').enabled(this.controlsEnabled())
          .onClick(() => this.viewModel.importReranker(false, true))
        Text('电脑推送路径：应用沙箱 files/rerank-models。导入或扫描只添加条目，不自动加载模型。')
          .fontSize(12).lineHeight(18).fontColor($r('app.color.text_hint')).width('100%')
        if (this.viewModel.rerankProfiles.length === 0 && this.viewModel.rerankMessage.length > 0) {
          Text(this.viewModel.rerankMessage).fontSize(12).lineHeight(18)
            .fontColor($r('app.color.text_secondary')).width('100%')
        }
      } else {
        if (this.viewModel.rerankProfiles.length === 0) {
          Column({ space: 12 }) {
            Image($r('app.media.model_search_empty')).width(36).height(36)
              .fillColor($r('app.color.text_muted')).opacity(0.65).accessibilityLevel('no')
            Text('尚未导入重排模型').fontSize(13).fontColor($r('app.color.text_muted'))
          }.width('100%').height(156).justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
        } else {
          ForEach(this.viewModel.rerankProfiles, (model: ModelProfile) => { this.ModelOption(model) },
            (model: ModelProfile) => model.id)
          if (this.viewModel.rerankLoading) {
            LoadingProgress().width(24).height(24).color($r('app.color.status_good'))
          }
          if (this.viewModel.reranker.loadedId.length === 0) {
            Button('加载当前模型')
              .attributeModifier(new ActionButtonStyle($r('app.color.button_primary_background'), $r('app.color.button_primary_text')))
              .width('100%').enabled(this.controlsEnabled() && !!this.viewModel.selectedReranker() && !this.viewModel.busy && !this.viewModel.modelLoading)
              .onClick(() => this.viewModel.loadRerankModel())
          } else {
            Button('释放已加载模型')
              .attributeModifier(new ActionButtonStyle($r('app.color.button_secondary_background'), $r('app.color.button_secondary_text')))
              .width('100%').enabled(this.controlsEnabled())
              .onClick(() => this.viewModel.releaseRerankModel())
          }
          if (this.viewModel.selectedReranker() !== undefined) {
            Button('删除当前模型')
              .attributeModifier(new ActionButtonStyle($r('app.color.button_danger_background'), $r('app.color.button_danger_text')))
              .width('100%').enabled(this.controlsEnabled())
              .onClick(() => this.viewModel.requestDeleteReranker())
          }
          if (this.viewModel.rerankMessage.length > 0) {
            Text(this.viewModel.rerankMessage).fontSize(12).lineHeight(18)
              .fontColor($r('app.color.text_secondary')).width('100%')
          }
        }
      }
    }.width('100%')
  }
}
