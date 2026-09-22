export interface AppTabEntry {
  title: string
  description: string
  icon: Resource
}

@Component
export struct BottomTabs {
  @Prop activeTab: number
  @Prop windowWidth: number = 0
  @Prop bottomInset: number = 0
  @Prop entries: AppTabEntry[] = [
    { title: '聊天', description: '全屏对话', icon: $r('sys.symbol.message') },
    { title: '模型', description: '加载参数', icon: $r('sys.symbol.square_grid_2x2') },
    { title: 'API 服务', description: 'OpenAI API', icon: $r('sys.symbol.externaldrive_3') },
    { title: '监控', description: 'CPU 内存', icon: $r('sys.symbol.waveform_path_ecg_square') }
  ]
  onTabChange: (index: number) => void = (_index: number) => {}
  onSettings: () => void = () => {}
  private readonly wideLabelWidth: number = 64

  @Builder
  private TabButton(index: number, title: string, desc: string, icon: Resource) {
    Flex({ direction: this.windowWidth >= 840 ? FlexDirection.Row : FlexDirection.Column,
      alignItems: ItemAlign.Center, justifyContent: FlexAlign.Center }) {
        SymbolGlyph(icon)
          .fontSize(22)
          .fontWeight(400)
          .width(24)
          .height(24)
          .fontColor([this.activeTab === index ?
            (this.windowWidth < 600 ? $r('app.color.nav_mobile_selected') : $r('app.color.nav_selected_text')) : $r('app.color.text_muted')])
          .accessibilityLevel('no')
      Column({ space: 2 }) {
      Text(this.windowWidth >= 840 && title === 'API 服务' ? '服务' : title)
        .fontSize(this.windowWidth < 600 ? 11 : 14)
        .lineHeight(this.windowWidth < 600 ? 16 : 20)
        .maxLines(1)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.activeTab === index ?
          (this.windowWidth < 600 ? $r('app.color.nav_mobile_selected') : $r('app.color.nav_selected_text')) : $r('app.color.text_muted'))
      if (this.windowWidth >= 840) {
        Text(desc)
        .fontSize(10)
        .fontColor(this.activeTab === index ? $r('app.color.nav_selected_description') : $r('app.color.text_nav_hint'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      }
      .alignItems(this.windowWidth >= 840 ? HorizontalAlign.Start : HorizontalAlign.Center)
      .width(this.windowWidth >= 840 ? this.wideLabelWidth : undefined)
      .margin(this.windowWidth >= 840 ? { left: 8 } : { top: this.windowWidth < 600 ? 1 : 3 })
    }
    .height(this.windowWidth < 600 ? 52 : 54)
    .padding({ top: this.windowWidth < 600 ? 9 : 0, bottom: this.windowWidth < 600 ? 2 : 0,
      left: this.windowWidth >= 840 ? 12 : 0, right: this.windowWidth >= 840 ? 12 : 0 })
    .width(this.windowWidth >= 600 ? '100%' : `${100 / this.entries.length}%`)
    .flexShrink(this.windowWidth >= 600 ? 0 : 1)
    .backgroundColor(this.windowWidth < 600 ? Color.Transparent :
      (this.activeTab === index ? $r('app.color.nav_selected_background') : $r('app.color.nav_idle')))
    .borderRadius(this.windowWidth < 600 ? 0 : 8)
    .margin(this.windowWidth >= 600 ? { bottom: 8 } : { left: 0, right: 0 })
    .focusable(true)
    .hoverEffect(this.windowWidth < 600 ? HoverEffect.None : HoverEffect.Auto)
    .accessibilityText(title)
    .onClick(() => {
      this.onTabChange(index)
    })
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
    Column() {}
      .width('100%')
      .height(this.windowWidth < 600 ? 52 + this.bottomInset : '100%')
      .backgroundColor(this.windowWidth >= 600 ? $r('app.color.sidebar_background') : Color.Transparent)
      .backgroundBlurStyle(this.windowWidth < 600 ? BlurStyle.Thin : BlurStyle.NONE, {
        colorMode: ThemeColorMode.SYSTEM,
        adaptiveColor: AdaptiveColor.DEFAULT,
        scale: 1,
        policy: BlurStyleActivePolicy.ALWAYS_ACTIVE
      })
      .hitTestBehavior(HitTestMode.None)
    Column({ space: 8 }) {
      Scroll() {
      Flex({ direction: this.windowWidth >= 600 ? FlexDirection.Column : FlexDirection.Row }) {
        ForEach(this.entries, (entry: AppTabEntry, index: number) => {
          this.TabButton(index, entry.title, entry.description, entry.icon)
        }, (entry: AppTabEntry) => entry.title)
      }
      .width('100%')
      }
      .scrollable(this.windowWidth >= 600 ? ScrollDirection.Vertical : ScrollDirection.None)
      .scrollBar(BarState.Off)
      .align(Alignment.TopStart)
      .width('100%')
      .layoutWeight(1)
      if (this.windowWidth >= 600) {
        Button({ type: ButtonType.Normal }) {
          Flex({ direction: this.windowWidth >= 840 ? FlexDirection.Row : FlexDirection.Column,
            alignItems: ItemAlign.Center, justifyContent: FlexAlign.Center }) {
            SymbolGlyph($r('sys.symbol.gearshape'))
              .fontSize(22)
              .fontWeight(400)
              .width(24)
              .height(24)
              .fontColor([$r('app.color.text_secondary')])
            Text('设置')
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_secondary'))
              .width(this.windowWidth >= 840 ? this.wideLabelWidth : undefined)
              .textAlign(this.windowWidth >= 840 ? TextAlign.Start : TextAlign.Center)
              .margin(this.windowWidth >= 840 ? { left: 8 } : { top: 3 })
          }
          .padding({ left: this.windowWidth >= 840 ? 12 : 0, right: this.windowWidth >= 840 ? 12 : 0 })
        }
        .width('100%')
        .height(this.windowWidth >= 840 ? 44 : 54)
        .padding(0)
        .borderRadius($r('app.float.button_radius'))
        .backgroundColor($r('app.color.nav_idle'))
        .hoverEffect(HoverEffect.Auto)
        .accessibilityText('设置')
        .translate({ y: this.bottomInset })
        .onClick(() => this.onSettings())
      }
    }
    .width('100%')
    .height(this.windowWidth >= 600 ? '100%' : 52)
    .padding({ left: this.windowWidth >= 840 ? 12 : this.windowWidth >= 600 ? 8 : 4,
      right: this.windowWidth >= 840 ? 12 : this.windowWidth >= 600 ? 8 : 4,
      top: this.windowWidth >= 600 ? 4 : 0,
      bottom: this.windowWidth >= 600 ? $r('app.float.wide_bottom_spacing') : 0 })
    }
    .width('100%')
    .height(this.windowWidth >= 600 ? '100%' : 52)
  }
}
