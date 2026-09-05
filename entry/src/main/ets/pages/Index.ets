// Derived from Turbo1123/turbo-ai-chat-harmonyos and subsequently modified.
// See README.md and Git history for provenance and change details.

import { common } from '@kit.AbilityKit'
import { KeyCode } from '@kit.InputKit'
import { KeyboardAvoidMode } from '@kit.ArkUI'
import { AppHeader } from '../components/AppHeader'
import { ApiServerTab } from '../components/ApiServerTab'
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
  @State private modelCardDragging: boolean = false
  @State private windowWidth: number = 0
  @State private windowHeight: number = 0
  private lastBackTime: number = 0
  private newChatKeyHeld: boolean = false
  private focusScope: string = ''
  private focusTimer: number = -1
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
    this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE)
    this.viewModel.bindNotify(() => {
      this.stateVersion++
      this.updateModalFocus()
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
    clearTimeout(this.focusTimer)
    this.viewModel.dispose()
  }

  private modalFocusId(): string {
    if (this.viewModel.showDeleteModelDialog) return 'delete-dialog'
    if (this.viewModel.showModelMarketDialog) return 'market-dialog'
    if (this.viewModel.showBuiltinModelInstallDialog) return 'install-dialog'
    if (this.viewModel.showModelLoadDialog) return 'load-dialog'
    return 'app-content'
  }

  private updateModalFocus(force: boolean = false): void {
    const id = this.modalFocusId()
    if (!force && this.focusScope === id) return
    this.focusScope = id
    clearTimeout(this.focusTimer)
    this.focusTimer = setTimeout(() => {
      try {
        this.getUIContext().getFocusController().requestFocus(this.modalFocusId())
      } catch (_) {
      }
    }, 0)
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
    if (index === 2) {
      this.viewModel.refreshApiServerAddress()
    }
  }

  private newChat(): void {
    this.viewModel.newChat()
    this.activeTab = 0
  }

  private handleKey(event: KeyEvent): boolean {
    if (event.keyCode === KeyCode.KEYCODE_ESCAPE && event.type === KeyType.Down) {
      return this.viewModel.dismissTopDialogIfIdle()
    }
    if (event.keyCode !== KeyCode.KEYCODE_N) {
      return false
    }
    if (event.type === KeyType.Up) {
      this.newChatKeyHeld = false
      return false
    }
    if (this.activeTab !== 0 || !event.getModifierKeyState?.(['ctrl']) ||
      this.viewModel.showModelLoadDialog || this.viewModel.showBuiltinModelInstallDialog ||
      this.viewModel.showModelMarketDialog || this.viewModel.showDeleteModelDialog) {
      return false
    }
    if (!this.newChatKeyHeld && !this.viewModel.busy && !this.viewModel.generating) {
      this.newChat()
    }
    this.newChatKeyHeld = true
    return true
  }

  private pagePadding(): number {
    return this.windowWidth >= 840 ? 24 : this.windowWidth >= 600 ? 20 : 14
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
            renderVersion: this.stateVersion,
            showNewChat: this.activeTab === 0,
            actionLabel: this.activeTab === 1 ? '模型广场' : '',
            onNewChat: () => {
              this.newChat()
            },
            onAction: () => {
              if (this.activeTab === 1) {
                this.viewModel.openModelMarketDialog()
              }
            }
          })
          .padding({ left: this.pagePadding(), right: this.pagePadding() })
        }
        .width('100%')
        Flex({ direction: this.windowWidth >= 600 ? FlexDirection.RowReverse : FlexDirection.Column }) {
          Column({ space: 8 }) {
            if (this.activeTab === 0) {
              ChatRunTicker({
                viewModel: this.viewModel,
                topSpacing: this.windowWidth >= 600 ? 4 : 6
              })
            }
            Stack() {
              ChatTab({
                viewModel: this.viewModel,
                renderVersion: this.stateVersion,
                active: this.activeTab === 0,
                dialogVisible: this.viewModel.showModelLoadDialog || this.viewModel.showBuiltinModelInstallDialog ||
                  this.viewModel.showModelMarketDialog || this.viewModel.showDeleteModelDialog
              })
              .padding({ left: this.pagePadding(), right: this.pagePadding() })
              .width(Math.max(1, Math.min(1280 + 2 * this.pagePadding(), this.windowWidth -
                (this.windowWidth >= 840 ? 160 : this.windowWidth >= 600 ? 88 : 0))))
              .height('100%')
              .visibility(this.activeTab === 0 ? Visibility.Visible : Visibility.Hidden)

              ModelTab({
                viewModel: this.viewModel,
                renderVersion: this.stateVersion,
                onDragStateChange: (dragging: boolean) => {
                  this.modelCardDragging = dragging
                }
              })
              .padding({ left: this.pagePadding(), right: this.pagePadding() })
              .width(Math.max(1, Math.min(1280 + 2 * this.pagePadding(), this.windowWidth -
                (this.windowWidth >= 840 ? 160 : this.windowWidth >= 600 ? 88 : 0))))
              .height('100%')
              .visibility(this.activeTab === 1 ? Visibility.Visible : Visibility.Hidden)

              ApiServerTab({
                viewModel: this.viewModel,
                renderVersion: this.stateVersion,
                loaded: this.viewModel.loaded,
                busy: this.viewModel.busy,
                currentModelName: this.viewModel.currentModel().shortName,
                apiServerRunning: this.viewModel.apiServerRunning,
                apiServerStarting: this.viewModel.apiServerStarting,
                apiServerPortInput: this.viewModel.apiServerPortInput,
                apiServerRequireKey: this.viewModel.apiServerRequireKey,
                apiServerKey: this.viewModel.apiServerKey,
                apiServerAddress: this.viewModel.apiServerAddress,
                apiServerStatus: this.viewModel.apiServerStatus,
                apiServerRequestCount: this.viewModel.apiServerRequestCount,
                apiServerLogs: this.viewModel.apiServerLogs
              })
              .padding({ left: this.pagePadding(), right: this.pagePadding() })
              .width(Math.max(1, Math.min(1280 + 2 * this.pagePadding(), this.windowWidth -
                (this.windowWidth >= 840 ? 160 : this.windowWidth >= 600 ? 88 : 0))))
              .height('100%')
              .visibility(this.activeTab === 2 ? Visibility.Visible : Visibility.Hidden)

              MonitorTab({
                viewModel: this.viewModel,
                active: this.activeTab === 3
              })
              .padding({ left: this.pagePadding(), right: this.pagePadding() })
              .width(Math.max(1, Math.min(1280 + 2 * this.pagePadding(), this.windowWidth -
                (this.windowWidth >= 840 ? 160 : this.windowWidth >= 600 ? 88 : 0))))
              .height('100%')
              .visibility(this.activeTab === 3 ? Visibility.Visible : Visibility.Hidden)
            }
            .width('100%')
            .layoutWeight(1)
          }
          .layoutWeight(1)
          .width(this.windowWidth >= 600 ? 0 : '100%')
          .height(this.windowWidth >= 600 ? '100%' : 0)
          .zIndex(this.modelCardDragging ? 10 : 0)
          BottomTabs({
            activeTab: this.activeTab,
            windowWidth: this.windowWidth,
            onTabChange: (index: number) => {
              this.changeTab(index)
            }
          })
          .width(this.windowWidth >= 840 ? 160 : this.windowWidth >= 600 ? 88 : '100%')
          .height(this.windowWidth >= 600 ? '100%' : 62)
          .flexShrink(0)
        }
        .width('100%')
        .layoutWeight(1)
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Start)
      .padding({ top: 8, bottom: 8 })
      .id('app-content')
      .focusable(this.modalFocusId() === 'app-content')

      if (this.viewModel.showModelLoadDialog) {
        ModelLoadDialog({
          viewModel: this.viewModel,
          availableWidth: this.windowWidth,
          availableHeight: this.windowHeight
        })
        .id('load-dialog')
        .focusable(this.modalFocusId() === 'load-dialog')
        .onAppear(() => this.updateModalFocus(true))
      }
      if (this.viewModel.showBuiltinModelInstallDialog) {
        BuiltinModelInstallDialog({
          viewModel: this.viewModel,
          availableWidth: this.windowWidth,
          availableHeight: this.windowHeight
        })
        .id('install-dialog')
        .focusable(this.modalFocusId() === 'install-dialog')
        .onAppear(() => this.updateModalFocus(true))
      }
      if (this.viewModel.showModelMarketDialog) {
        ModelMarketDialog({
          viewModel: this.viewModel,
          availableWidth: this.windowWidth,
          availableHeight: this.windowHeight
        })
        .id('market-dialog')
        .focusable(this.modalFocusId() === 'market-dialog')
        .onAppear(() => this.updateModalFocus(true))
      }
      if (this.viewModel.showDeleteModelDialog) {
        DeleteModelDialog({
          viewModel: this.viewModel,
          availableWidth: this.windowWidth,
          availableHeight: this.windowHeight
        })
        .id('delete-dialog')
        .focusable(this.modalFocusId() === 'delete-dialog')
        .onAppear(() => this.updateModalFocus(true))
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#06121F')
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      this.windowWidth = Number(newArea.width)
      this.windowHeight = Number(newArea.height)
    })
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
    .backgroundColor('#06121F')
    .onKeyEvent((event: KeyEvent): boolean => this.handleKey(event))
  }
}
