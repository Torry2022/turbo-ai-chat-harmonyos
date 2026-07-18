import { common } from '@kit.AbilityKit'
import { AppHeader } from '../components/AppHeader'
import { BottomTabs } from '../components/BottomTabs'
import { BuiltinModelInstallDialog } from '../components/BuiltinModelInstallDialog'
import { ChatTab } from '../components/ChatTab'
import { ChatRunTicker } from '../components/ChatRunTicker'
import { DeleteModelDialog } from '../components/DeleteImportedModelDialog'
import { LaunchScreen } from '../components/LaunchScreen'
import { ModelLoadDialog } from '../components/ModelLoadDialog'
import { ModelMarketDialog } from '../components/ModelMarketDialog'
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
    if (this.viewModel.dismissTopDialogIfIdle()) {
      return true
    }
    const now: number = Date.now()
    if (now - this.lastBackTime < 2000) {
      this.abilityContext?.terminateSelf().catch((_err: Error) => {
        this.showToast('退出失败', 1500)
      })
      return true
    }
    this.lastBackTime = now
    this.showToast('再按一次退出', 2000)
    return true
  }

  aboutToAppear(): void {
    this.viewModel.bindNotify(() => {
      this.stateVersion++
    })
    this.viewModel.bindToast((message: string) => {
      this.showToast(message, 1800)
    })
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext
    this.abilityContext = context
    this.viewModel.initialize(context)
    setTimeout(() => {
      this.showLaunch = false
      if (!this.viewModel.loaded) {
        this.viewModel.openModelLoadDialog(false)
      }
    }, 1200)
  }

  aboutToDisappear(): void {
    this.viewModel.dispose()
  }

  private changeTab(index: number): void {
    if (index !== 0) {
      if (this.viewModel.speechRecognitionStarting) {
        this.viewModel.cancelSpeechRecognition()
      } else {
        this.viewModel.stopSpeechRecognition()
      }
    }
    this.activeTab = index
    if (index === 0) {
      this.viewModel.scrollToBottom()
    }
  }

  private newChat(): void {
    this.viewModel.newChat()
    this.activeTab = 0
  }

  private showToast(message: string, duration: number): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message, duration, bottom: 80 })
    } catch (_) {
    }
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
            showNewChat: this.activeTab === 0,
            actionLabel: this.activeTab === 1 ? '模型市场' : '',
            onNewChat: () => {
              this.newChat()
            },
            onAction: () => {
              if (this.activeTab === 1) {
                this.viewModel.openModelMarketDialog()
              }
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
        Stack() {
          ChatTab({
            viewModel: this.viewModel,
            renderVersion: this.stateVersion
          })
          .padding({ left: 14, right: 14 })
          .height('100%')
          .visibility(this.activeTab === 0 ? Visibility.Visible : Visibility.Hidden)

          ModelTab({
            viewModel: this.viewModel,
            renderVersion: this.stateVersion
          })
          .padding({ left: 14, right: 14 })
          .height('100%')
          .visibility(this.activeTab === 1 ? Visibility.Visible : Visibility.Hidden)

          if (this.activeTab === 2) {
            MonitorTab({
              viewModel: this.viewModel
            })
            .padding({ left: 14, right: 14 })
            .height('100%')
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
      if (this.viewModel.showModelMarketDialog) {
        ModelMarketDialog({
          viewModel: this.viewModel
        })
      }
      if (this.viewModel.showDeleteModelDialog) {
        DeleteModelDialog({
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
