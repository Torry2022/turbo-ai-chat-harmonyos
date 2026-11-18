import { ChatViewModel } from '../state/ChatViewModel'
import { SortableModelList } from './SortableModelList'
import { ActionButtonStyle } from './ButtonStyles'
import { ParameterSliderStyle } from './ControlStyles'

@Component
export struct RerankerModels {
  @ObjectLink viewModel: ChatViewModel
  @Prop renderVersion: number = 0
  @Prop settings: boolean = false
  onDragStateChange: (dragging: boolean) => void = (_dragging: boolean) => {}
  @State private runtimeExpanded: boolean = false

  private controlsEnabled(): boolean {
    return !this.viewModel.rerankLoading && !this.viewModel.reranker.busy && !this.viewModel.rerankImporting
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
        if (this.viewModel.rerankRuntimeHint().length > 0) {
          Text(this.viewModel.rerankRuntimeHint())
            .fontSize(11).fontColor($r('app.color.text_model_hint')).width('100%')
        }
        if (this.runtimeExpanded) {
          Column({ space: 10 }) {
            Text(`推理线程：${this.viewModel.rerankThreads}`)
              .fontSize(12).fontColor($r('app.color.text_secondary')).width('100%')
            Slider({ value: this.viewModel.rerankThreads, min: 1, max: this.viewModel.threadMax, step: 1 })
              .attributeModifier(new ParameterSliderStyle()).enabled(this.controlsEnabled() && !this.viewModel.busy && !this.viewModel.modelLoading)
              .onChange((value: number, mode: SliderChangeMode) => {
                this.viewModel.rerankThreads = Math.round(value)
                if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
                  this.viewModel.settingFeedback(this.viewModel.rerankRuntimeHint())
                }
              })
            Text(`单条输入上限：${this.viewModel.rerankMaxTokens} tokens`)
              .fontSize(12).fontColor($r('app.color.text_secondary')).width('100%')
            Slider({ value: this.viewModel.rerankMaxTokens, min: 128, max: 8192, step: 128 })
              .attributeModifier(new ParameterSliderStyle()).enabled(this.controlsEnabled() && !this.viewModel.busy && !this.viewModel.modelLoading)
              .onChange((value: number, mode: SliderChangeMode) => {
                this.viewModel.rerankMaxTokens = Math.round(value)
                if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
                  this.viewModel.settingFeedback(this.viewModel.rerankRuntimeHint())
                }
              })
            if (this.viewModel.rerankRuntimeChanged()) {
              Button('重新加载')
                .attributeModifier(new ActionButtonStyle($r('app.color.button_primary_background'), $r('app.color.button_primary_text')))
                .width('100%').enabled(this.controlsEnabled() && !this.viewModel.busy && !this.viewModel.modelLoading)
                .onClick(() => this.viewModel.reloadRerankModel())
            }
            Text('输入上限包含问题、候选文本和模型模板。超长请求会报错，不会自动截断。')
              .fontSize(12).lineHeight(18).fontColor($r('app.color.text_hint')).width('100%')
          }.width('100%').transition(TransitionEffect.OPACITY)
        }
      } else {
        if (this.viewModel.rerankProfiles.length === 0) {
          Column({ space: 12 }) {
            Image($r('app.media.model_search_empty')).width(36).height(36)
              .fillColor($r('app.color.text_muted')).opacity(0.65).accessibilityLevel('no')
            Text('尚未安装重排模型').fontSize(13).fontColor($r('app.color.text_muted'))
            Button('前往模型广场')
              .attributeModifier(new ActionButtonStyle($r('app.color.button_secondary_background'), $r('app.color.button_secondary_text')))
              .onClick(() => this.viewModel.openModelMarketDialog())
          }.width('100%').height(156).justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
        } else {
          SortableModelList({
            profiles: this.viewModel.orderedSpecializedModels(this.viewModel.rerankProfiles),
            selectedId: this.viewModel.rerankSelectedId, loadedId: this.viewModel.reranker.loadedId,
            interactionEnabled: this.controlsEnabled(),
            onSelect: (id: string) => this.viewModel.selectReranker(id),
            onMove: (id: string, index: number) => this.viewModel.moveSpecializedModel('rerank', id, index),
            onDragStateChange: this.onDragStateChange
          })
          Text(this.viewModel.recentModelLoadText(this.viewModel.rerankSelectedId))
            .fontSize(12).lineHeight(18).fontColor($r('app.color.text_muted')).width('100%')
          if (this.viewModel.rerankLoading) {
            LoadingProgress().width(24).height(24).color($r('app.color.status_good'))
          }
          if (this.viewModel.reranker.loadedId.length === 0) {
            Button('加载当前模型')
              .attributeModifier(new ActionButtonStyle($r('app.color.button_primary_background'), $r('app.color.button_primary_text')))
              .width('100%').enabled(this.controlsEnabled() && !!this.viewModel.selectedReranker() && !this.viewModel.busy && !this.viewModel.modelLoading)
              .onClick(() => this.viewModel.loadRerankModel())
          } else {
            Button('释放当前模型')
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
