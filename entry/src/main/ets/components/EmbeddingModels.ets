import { ChatViewModel } from '../state/ChatViewModel'
import { ModelProfile } from '../models/ModelProfile'
import { ActionButtonStyle } from './ButtonStyles'
import { ParameterSliderStyle } from './ControlStyles'

@Component
export struct EmbeddingModels {
  @ObjectLink viewModel: ChatViewModel
  @Prop renderVersion: number = 0
  @Prop settings: boolean = false
  @State private runtimeExpanded: boolean = false

  private controlsEnabled(): boolean {
    return !this.viewModel.busy && !this.viewModel.modelLoading && !this.viewModel.embeddingLoading && !this.viewModel.embedder.busy && !this.viewModel.embeddingImporting
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
          .fontColor(model.id === this.viewModel.embeddingSelectedId ?
            $r('app.color.text_title') : $r('app.color.text_secondary'))
        if (model.id === this.viewModel.embedder.loadedId) {
          this.ModelTag('已加载', $r('app.color.tag_green_text'), $r('app.color.tag_green_background'))
        }
      }
      .width('100%')
      Text(model.description === '用户导入的 MNN 模型。' ?
        '用户导入的 MNN 向量模型。' : model.description).fontSize(12).lineHeight(18).width('100%')
        .fontColor(model.id === this.viewModel.embeddingSelectedId ?
          $r('app.color.text_note') : $r('app.color.text_caption'))
    }
    .width('100%').padding(10).borderRadius(8)
    .backgroundColor(model.id === this.viewModel.embeddingSelectedId ?
      $r('app.color.selected_background') : $r('app.color.list_background'))
    .onClick(() => this.viewModel.selectEmbeddingModel(model.id))
  }

  build() {
    Column({ space: 10 }) {
      if (this.settings) {
        Row() {
          Text('运行配置').fontSize(16).fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_title')).layoutWeight(1)
          Text(this.runtimeExpanded ? '收起 ▲' : '展开 ▼')
            .fontSize(12).fontColor($r('app.color.button_action_text'))
        }.width('100%').onClick(() => {
          this.getUIContext().animateTo({ duration: 220, curve: Curve.EaseInOut }, () => {
            this.runtimeExpanded = !this.runtimeExpanded
          })
        })
        if (this.viewModel.embeddingRuntimeHint().length > 0) {
          Text(this.viewModel.embeddingRuntimeHint())
            .fontSize(11).fontColor($r('app.color.text_model_hint')).width('100%')
        }
        if (this.runtimeExpanded) {
          Column({ space: 10 }) {
            Text(`推理线程：${this.viewModel.embeddingThreads}`)
              .fontSize(12).fontColor($r('app.color.text_secondary')).width('100%')
            Slider({ value: this.viewModel.embeddingThreads, min: 1, max: this.viewModel.threadMax, step: 1 })
              .attributeModifier(new ParameterSliderStyle()).enabled(this.controlsEnabled() && !this.viewModel.busy && !this.viewModel.modelLoading)
              .onChange((value: number, mode: SliderChangeMode) => {
                this.viewModel.embeddingThreads = Math.round(value)
                if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
                  this.viewModel.settingFeedback(this.viewModel.embeddingRuntimeHint())
                }
              })
            if (this.viewModel.embeddingRuntimeChanged()) {
              Button('重新加载')
                .attributeModifier(new ActionButtonStyle($r('app.color.button_primary_background'), $r('app.color.button_primary_text')))
                .width('100%').enabled(this.controlsEnabled() && !this.viewModel.busy && !this.viewModel.modelLoading)
                .onClick(() => this.viewModel.reloadEmbeddingModel())
            }
          }.width('100%').transition(TransitionEffect.OPACITY)
        }
      } else {
        if (this.viewModel.embeddingProfiles.length === 0) {
          Column({ space: 12 }) {
            Image($r('app.media.model_search_empty')).width(36).height(36)
              .fillColor($r('app.color.text_muted')).opacity(0.65).accessibilityLevel('no')
            Text('尚未安装向量模型').fontSize(13).fontColor($r('app.color.text_muted'))
          }.width('100%').height(156).justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
        } else {
          ForEach(this.viewModel.embeddingProfiles, (model: ModelProfile) => { this.ModelOption(model) },
            (model: ModelProfile) => model.id)
          Text(this.viewModel.recentModelLoadText(this.viewModel.embeddingSelectedId))
            .fontSize(12).lineHeight(18).fontColor($r('app.color.text_muted')).width('100%')
          if (this.viewModel.embeddingLoading) {
            LoadingProgress().width(24).height(24).color($r('app.color.status_good'))
          }
          if (this.viewModel.embedder.loadedId.length === 0) {
            Button('加载当前模型')
              .attributeModifier(new ActionButtonStyle($r('app.color.button_primary_background'), $r('app.color.button_primary_text')))
              .width('100%').enabled(this.controlsEnabled() && !!this.viewModel.selectedEmbeddingModel() && !this.viewModel.busy && !this.viewModel.modelLoading)
              .onClick(() => this.viewModel.loadEmbeddingModel())
          } else {
            Button('释放当前模型')
              .attributeModifier(new ActionButtonStyle($r('app.color.button_secondary_background'), $r('app.color.button_secondary_text')))
              .width('100%').enabled(this.controlsEnabled())
              .onClick(() => this.viewModel.releaseEmbeddingModel())
          }
          if (this.viewModel.selectedEmbeddingModel() !== undefined) {
            Button('删除当前模型')
              .attributeModifier(new ActionButtonStyle($r('app.color.button_danger_background'), $r('app.color.button_danger_text')))
              .width('100%').enabled(this.controlsEnabled())
              .onClick(() => this.viewModel.requestDeleteEmbedding())
          }
          if (this.viewModel.embeddingMessage.length > 0) {
            Text(this.viewModel.embeddingMessage).fontSize(12).lineHeight(18)
              .fontColor($r('app.color.text_secondary')).width('100%')
          }
        }
      }
    }.width('100%')
  }
}
