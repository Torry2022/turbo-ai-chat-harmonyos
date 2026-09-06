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
import { SettingsDialog } from '../components/SettingsDialog'
import { DIALOG_MOTION_DURATION } from '../components/DialogMotion'
import { themeService } from '../services/ThemeService'
import { ChatViewModel } from '../state/ChatViewModel'

@Entry
@Component
struct Index {
  @State private viewModel: ChatViewModel = new ChatViewModel()
  @State private showLaunch: boolean = true
  @State private activeTab: number = 0
  @State private transitionTab: number = 0
  @State private visibleTabs: number = 1
  private tabTransitionSerial: number = 0
  @State @Watch('onSettingsChanged') private showSettings: boolean = false
  @State private dialogExitBlocking: boolean = false
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
    if (this.dialogExitBlocking) return true
    if (this.showSettings) {
      this.showSettings = false
      return true
    }
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
      themeService.finishLaunch()
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
    if (this.showSettings) return 'settings-dialog'
    if (this.viewModel.showDeleteModelDialog) return 'delete-dialog'
    if (this.viewModel.showModelMarketDialog) return 'market-dialog'
    if (this.viewModel.showBuiltinModelInstallDialog) return 'install-dialog'
    if (this.viewModel.showModelLoadDialog) return 'load-dialog'
    return 'app-content'
  }

  private updateModalFocus(force: boolean = false): void {
    const id = this.modalFocusId()
    if (!force && this.focusScope === id) return
    if (id === 'app-content' && this.focusScope.length > 0 && this.focusScope !== id) {
      this.dialogExitBlocking = true
    } else if (id !== 'app-content') {
      this.dialogExitBlocking = false
    }
    this.focusScope = id
    clearTimeout(this.focusTimer)
    this.focusTimer = setTimeout(() => {
      this.dialogExitBlocking = false
      try {
        this.getUIContext().getFocusController().requestFocus(this.modalFocusId())
      } catch (_) {
      }
    }, this.dialogExitBlocking ? DIALOG_MOTION_DURATION + 20 : 0)
  }

  private onSettingsChanged(): void {
    this.updateModalFocus(true)
  }

  private changeTab(index: number): void {
    if (index === this.activeTab) {
      return
    }
    if (index !== 0) {
      if (this.viewModel.speechRecognitionStarting) {
        this.viewModel.cancelSpeechRecognition()
      } else {
        this.viewModel.stopSpeechRecognition()
      }
    }
    const serial = ++this.tabTransitionSerial
    this.visibleTabs |= 1 << index
    this.activeTab = index
    this.getUIContext().animateTo({ duration: 150, curve: Curve.EaseOut,
      onFinish: () => {
        if (serial === this.tabTransitionSerial) {
          this.visibleTabs = 1 << this.activeTab
        }
      }
    }, () => {
      this.transitionTab = index
    })
    if (index === 2) {
      this.viewModel.refreshApiServerAddress()
    }
  }

  private newChat(): void {
    this.viewModel.newChat()
    this.changeTab(0)
  }

  private handleKey(event: KeyEvent): boolean {
    if (this.dialogExitBlocking) return true
    if (event.keyCode === KeyCode.KEYCODE_ESCAPE && event.type === KeyType.Down) {
      if (this.showSettings) {
        this.showSettings = false
        return true
      }
      return this.viewModel.dismissTopDialogIfIdle()
    }
    if (event.keyCode !== KeyCode.KEYCODE_N) {
      return false
    }
    if (event.type === KeyType.Up) {
      this.newChatKeyHeld = false
      return false
    }
    if (this.showSettings || this.activeTab !== 0 || !event.getModifierKeyState?.(['ctrl']) ||
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
  private HeaderShadow() {
    Column() {}
      .height(3)
      .width('100%')
      .opacity(this.windowWidth >= 600 ? 1 : 0)
      .linearGradient({ direction: GradientDirection.Bottom,
        colors: [[$r('app.color.header_shadow'), 0], [Color.Transparent, 1]] })
      .translate({ y: 3 })
      .hitTestBehavior(HitTestMode.None)
  }

  @Builder
  private MainScreen() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.windowWidth >= 600) {
        Column()
          .width(this.windowWidth >= 840 ? 160 : 88)
          .height('100%')
          .backgroundColor($r('app.color.sidebar_background'))
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
      }
      Column()
        .width('100%')
        .height(58)
        .backgroundColor($r('app.color.header_background'))
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
      Column({ space: this.windowWidth < 600 ? 0 : 8 }) {
        Column({ space: 0 }) {
          AppHeader({
            compact: this.windowWidth < 600,
            onSettings: () => { this.showSettings = true },
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
        .padding({ top: 4, bottom: 4 })
        .backgroundColor($r('app.color.header_background'))
        .overlay(this.HeaderShadow(), { align: Alignment.Bottom })
        .zIndex(1)
        Flex({ direction: this.windowWidth >= 600 ? FlexDirection.RowReverse : FlexDirection.Column }) {
          Stack() {
            Column({ space: 8 }) {
              ChatRunTicker({
                viewModel: this.viewModel,
                active: this.activeTab === 0,
                compact: this.windowWidth < 600,
                topSpacing: this.windowWidth >= 600 ? 4 : 0
              })
              ChatTab({
                viewModel: this.viewModel,
                renderVersion: this.stateVersion,
                active: this.activeTab === 0,
                dialogVisible: this.dialogExitBlocking || this.showSettings || this.viewModel.showModelLoadDialog || this.viewModel.showBuiltinModelInstallDialog ||
                  this.viewModel.showModelMarketDialog || this.viewModel.showDeleteModelDialog
              })
              .padding({ left: this.pagePadding(), right: this.pagePadding() })
              .width(Math.max(1, Math.min(1280 + 2 * this.pagePadding(), this.windowWidth -
                (this.windowWidth >= 840 ? 160 : this.windowWidth >= 600 ? 88 : 0))))
              .layoutWeight(1)
            }
            .width('100%')
            .height('100%')
            .opacity(this.transitionTab === 0 ? 1 : 0)
            .visibility((this.visibleTabs & 1) !== 0 ? Visibility.Visible : Visibility.Hidden)
            .hitTestBehavior(this.activeTab === 0 ? HitTestMode.Default : HitTestMode.None)
            .accessibilityLevel(this.activeTab === 0 ? 'auto' : 'no-hide-descendants')

              ModelTab({
                viewModel: this.viewModel,
                renderVersion: this.stateVersion,
                onDragStateChange: (dragging: boolean) => {
                  this.modelCardDragging = dragging
                }
              })
              .padding({ left: this.pagePadding(), right: this.pagePadding(), top: this.windowWidth < 600 ? 8 : 0 })
              .width(Math.max(1, Math.min(1280 + 2 * this.pagePadding(), this.windowWidth -
                (this.windowWidth >= 840 ? 160 : this.windowWidth >= 600 ? 88 : 0))))
              .height('100%')
              .opacity(this.transitionTab === 1 ? 1 : 0)
              .visibility((this.visibleTabs & 2) !== 0 ? Visibility.Visible : Visibility.Hidden)
              .hitTestBehavior(this.activeTab === 1 ? HitTestMode.Default : HitTestMode.None)
              .accessibilityLevel(this.activeTab === 1 ? 'auto' : 'no-hide-descendants')

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
              .padding({ left: this.pagePadding(), right: this.pagePadding(), top: this.windowWidth < 600 ? 8 : 0 })
              .width(Math.max(1, Math.min(1280 + 2 * this.pagePadding(), this.windowWidth -
                (this.windowWidth >= 840 ? 160 : this.windowWidth >= 600 ? 88 : 0))))
              .height('100%')
              .opacity(this.transitionTab === 2 ? 1 : 0)
              .visibility((this.visibleTabs & 4) !== 0 ? Visibility.Visible : Visibility.Hidden)
              .hitTestBehavior(this.activeTab === 2 ? HitTestMode.Default : HitTestMode.None)
              .accessibilityLevel(this.activeTab === 2 ? 'auto' : 'no-hide-descendants')

              MonitorTab({
                viewModel: this.viewModel,
                active: this.activeTab === 3
              })
              .padding({ left: this.pagePadding(), right: this.pagePadding(), top: this.windowWidth < 600 ? 8 : 0 })
              .width(Math.max(1, Math.min(1280 + 2 * this.pagePadding(), this.windowWidth -
                (this.windowWidth >= 840 ? 160 : this.windowWidth >= 600 ? 88 : 0))))
              .height('100%')
              .opacity(this.transitionTab === 3 ? 1 : 0)
              .visibility((this.visibleTabs & 8) !== 0 ? Visibility.Visible : Visibility.Hidden)
              .hitTestBehavior(this.activeTab === 3 ? HitTestMode.Default : HitTestMode.None)
              .accessibilityLevel(this.activeTab === 3 ? 'auto' : 'no-hide-descendants')
          }
          .layoutWeight(1)
          .width(this.windowWidth >= 600 ? 0 : '100%')
          .height(this.windowWidth >= 600 ? '100%' : 0)
          .zIndex(this.modelCardDragging ? 10 : 0)
          BottomTabs({
            onSettings: () => { this.showSettings = true },
            activeTab: this.activeTab,
            windowWidth: this.windowWidth,
            onTabChange: (index: number) => {
              this.changeTab(index)
            }
          })
          .width(this.windowWidth >= 840 ? 160 : this.windowWidth >= 600 ? 88 : '100%')
          .height(this.windowWidth >= 600 ? '100%' : 62)
          .margin({ top: this.windowWidth < 600 ? 8 : 0 })
          .flexShrink(0)
        }
        .width('100%')
        .layoutWeight(1)
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Start)
      .padding({ bottom: 8 })
      .id('app-content')
      .focusable(!this.dialogExitBlocking && this.modalFocusId() === 'app-content')

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
      if (this.showSettings) {
        SettingsDialog({
          availableWidth: this.windowWidth,
          availableHeight: this.windowHeight,
          onClose: () => { this.showSettings = false }
        })
        .id('settings-dialog')
        .focusable(true)
        .onAppear(() => this.updateModalFocus(true))
      }
      if (this.dialogExitBlocking) {
        Column()
          .width('100%')
          .height('100%')
          .hitTestBehavior(HitTestMode.Block)
          .onClick(() => {})
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.windowWidth < 600 ? $r('app.color.page_compact') : $r('app.color.page'))
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      this.windowWidth = Number(newArea.width)
      this.windowHeight = Number(newArea.height)
    })
  }

  build() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(this.showLaunch ? $r('app.color.start_window_background') :
          (this.windowWidth < 600 ? $r('app.color.page_compact') : $r('app.color.page')))
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      if (this.showLaunch) {
        LaunchScreen()
      } else {
        this.MainScreen()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.showLaunch ? $r('app.color.start_window_background') :
      (this.windowWidth < 600 ? $r('app.color.page_compact') : $r('app.color.page')))
    .onKeyEvent((event: KeyEvent): boolean => this.handleKey(event))
  }
}
