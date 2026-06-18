import { common } from '@kit.AbilityKit'
import { promptAction } from '@kit.ArkUI'
import { AppHeader } from '../components/AppHeader'
import { BottomTabs } from '../components/BottomTabs'
import { BuiltinModelInstallDialog } from '../components/BuiltinModelInstallDialog'
import { ChatTab } from '../components/ChatTab'
import { ChatRunTicker } from '../components/ChatRunTicker'
import { DeleteImportedModelDialog } from '../components/DeleteImportedModelDialog'
import { LaunchScreen } from '../components/LaunchScreen'
import { ModelLoadDialog } from '../components/ModelLoadDialog'
import { ModelTab } from '../components/ModelTab'
import { MonitorTab } from '../components/MonitorTab'
import { ChatViewModel } from '../state/ChatViewModel'

@Entry
@Component
struct Index {
  @State private viewModel: ChatViewModel = new ChatViewModel()
  @State private showLaunch: boolean = true
  @State private activeTab: number = 0
  @State private stateVersion: number = 0
  private lastBackTime: number = 0
  private abilityContext?: common.UIAbilityContext

  onBackPress(): boolean {
    const now: number = Date.now()
    if (now - this.lastBackTime < 2000) {
      this.abilityContext?.terminateSelf().catch((_err: Error) => {
        promptAction.showToast({ message: '退出失败', duration: 1500, bottom: 80 })
      })
      return true
    }
    this.lastBackTime = now
    promptAction.showToast({ message: '再按一次退出', duration: 2000, bottom: 80 })
    return true
  }

  aboutToAppear(): void {
    this.viewModel.bindNotify(() => {
      this.stateVersion++
    })
    const context = getContext(this) as common.UIAbilityContext
    this.abilityContext = context
    this.viewModel.initialize(context)
    setTimeout(() => {
      this.showLaunch = false
      if (!this.viewModel.loaded) {
        this.viewModel.openModelLoadDialog(true)
      }
    }, 1200)
  }

  aboutToDisappear(): void {
    this.viewModel.dispose()
  }

  private changeTab(index: number): void {
    this.activeTab = index
    if (index === 0) {
      this.viewModel.scrollToBottom()
    }
  }

  private newChat(): void {
    this.viewModel.newChat()
    this.activeTab = 0
  }

  @Builder
  private MainScreen() {
    Stack() {
      Column({ space: 8 }) {
        Column({ space: 0 }) {
          AppHeader({
            status: this.viewModel.status,
            loaded: this.viewModel.loaded,
            busy: this.viewModel.busy,
            onNewChat: () => {
              this.newChat()
            }
          })
          .padding({ left: 14, right: 14 })
          if (this.activeTab === 0) {
            ChatRunTicker({
              viewModel: this.viewModel
            })
          }
        }
        .width('100%')
        Column() {
          if (this.activeTab === 0) {
            ChatTab({
              viewModel: this.viewModel,
              renderVersion: this.stateVersion
            })
            .padding({ left: 14, right: 14 })
          } else if (this.activeTab === 1) {
            ModelTab({
              viewModel: this.viewModel
            })
            .padding({ left: 14, right: 14 })
          } else {
            MonitorTab({
              viewModel: this.viewModel
            })
            .padding({ left: 14, right: 14 })
          }
        }
        .layoutWeight(1)
        .width('100%')
        BottomTabs({
          activeTab: this.activeTab,
          onTabChange: (index: number) => {
            this.changeTab(index)
          }
        })
        .padding({ left: 14, right: 14 })
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Start)
      .padding({ top: 42, bottom: 12 })

      if (this.viewModel.showModelLoadDialog) {
        ModelLoadDialog({
          viewModel: this.viewModel
        })
      }
      if (this.viewModel.showBuiltinModelInstallDialog) {
        BuiltinModelInstallDialog({
          viewModel: this.viewModel
        })
      }
      if (this.viewModel.showDeleteImportedModelDialog) {
        DeleteImportedModelDialog({
          viewModel: this.viewModel
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#06121F')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
  }

  build() {
    Stack() {
      if (this.showLaunch) {
        LaunchScreen()
      } else {
        this.MainScreen()
      }
    }
    .width('100%')
    .height('100%')
  }
}
