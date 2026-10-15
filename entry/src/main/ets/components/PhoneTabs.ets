import { SymbolGlyphModifier } from '@kit.ArkUI'
import { DividerMode, HdsAnimationMode, HdsTabs, HdsTabsController, hdsMaterial } from '@kit.UIDesignKit'
import { AppTabEntry, DEFAULT_APP_TABS } from './BottomTabs'

@Component
export struct PhoneTabs {
  @Prop @Watch('syncTab') activeTab: number = 0
  @Prop keyboardVisible: boolean = false
  @Prop @Watch('syncBarVisibility') barHidden: boolean = false
  @Prop entries: AppTabEntry[] = DEFAULT_APP_TABS
  @BuilderParam pageContent: (index: number) => void = this.EmptyPage
  onTabChange: (index: number) => void = (_index: number) => {}
  private controller: HdsTabsController = new HdsTabsController()
  private currentIndex: number = 0
  @State private materialLevel: hdsMaterial.MaterialLevel = hdsMaterial.MaterialLevel.ADAPTIVE

  @Builder
  private EmptyPage(_index: number) {}

  private syncTab(): void {
    if (this.currentIndex === this.activeTab) return
    this.currentIndex = this.activeTab
    this.controller.changeIndex(this.activeTab)
  }

  private syncBarVisibility(): void {
    if (this.barHidden) {
      this.controller.applyHideAnimation(HdsAnimationMode.SCROLL_ANIMATION)
    } else {
      this.controller.applyShowAnimation(HdsAnimationMode.SCROLL_ANIMATION)
    }
  }

  aboutToAppear(): void {
    this.materialLevel = hdsMaterial.getSystemMaterialTypes().indexOf(hdsMaterial.MaterialType.IMMERSIVE) >= 0 ?
      hdsMaterial.MaterialLevel.EXQUISITE : hdsMaterial.MaterialLevel.SMOOTH
    this.currentIndex = this.activeTab
    this.syncBarVisibility()
  }

  build() {
    HdsTabs({ controller: this.controller }) {
      ForEach(this.entries, (entry: AppTabEntry, index: number) => {
        TabContent() {
          this.pageContent(index)
        }
        .tabBar(new BottomTabBarStyle({
          normal: new SymbolGlyphModifier(entry.icon).fontColor([$r('app.color.text_muted')]),
          selected: new SymbolGlyphModifier(entry.icon).fontColor([$r('app.color.nav_mobile_selected')])
        }, entry.title).labelStyle({
          font: { size: 11, weight: FontWeight.Medium },
          selectedColor: $r('app.color.nav_mobile_selected'),
          unselectedColor: $r('app.color.text_muted'), maxLines: 1
        }).layoutMode(LayoutMode.VERTICAL))
      }, (entry: AppTabEntry) => entry.title)
    }
    .width('100%').height('100%')
    .barHeight(this.keyboardVisible ? 0 : 56).barPosition(BarPosition.End)
    .divider({ mode: DividerMode.NONE })
    .vertical(false).barOverlap(true).scrollable(false).animationDuration(0)
    .barFloatingStyle(this.keyboardVisible ? undefined : {
      barBottomMargin: 28,
      systemMaterialEffect: { materialType: hdsMaterial.MaterialType.ADAPTIVE, materialLevel: this.materialLevel }
    })
    .onAppear(() => this.controller.changeIndex(this.activeTab))
    .onChange((index: number) => {
      this.currentIndex = index
      if (index !== this.activeTab) this.onTabChange(index)
    })
  }
}
