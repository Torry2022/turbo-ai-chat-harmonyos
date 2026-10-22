// Derived from Turbo1123/turbo-ai-chat-harmonyos and subsequently modified.
// See README.md and Git history for provenance and change details.

import { common } from '@kit.AbilityKit'
import { deviceInfo } from '@kit.BasicServicesKit'
import { KeyCode } from '@kit.InputKit'
import { KeyboardAvoidMode, window } from '@kit.ArkUI'
import { AppHeader } from '../components/AppHeader'
import { DesktopTitleBar } from '../components/DesktopTitleBar'
import { DesktopHelpDialog } from '../components/DesktopHelpDialog'
import { ApiServerTab } from '../components/ApiServerTab'
import { ApiUsageDialog } from '../components/ApiUsageDialog'
import { LayaDecisionDialog } from '../components/LayaDecisionDialog'
import { PhoneTabs } from '../components/PhoneTabs'
import { BottomTabs } from '../components/BottomTabs'
import { BuiltinModelInstallDialog } from '../components/BuiltinModelInstallDialog'
import { ChatTab } from '../components/ChatTab'
import { ChatHistoryPanel } from '../components/ChatHistoryPanel'
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
  @State @Watch('onSettingsChanged') private helpDialog: string = ''
  @State @Watch('onSettingsChanged') private showLayaDecision: boolean = false
  @State @Watch('onSettingsChanged') private apiUsageMode: string = ''
  @State private apiUsageExample: string = ''
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
  private mainWindow?: window.Window
  @State private desktopTitleVisible: boolean = false
  @State private desktopTitleHeight: number = 37
  @State private desktopControlsWidth: number = 148
  private readonly onTitleButtonRectChange = (rect: window.TitleButtonRect): void => {
    this.desktopControlsWidth = rect.width + rect.right
  }
  @State private topInset: number = 0
  @State private bottomInset: number = 0
  @State private keyboardVisible: boolean = false
  @State private chatInputExpanded: boolean = false
  @State private phoneHistoryOpen: boolean = false
  @State private phoneTabBarHidden: boolean = false
  private phoneTabBarScrollDelta: number = 0
  private readonly onKeyboardHeightChange = (height: number): void => {
    this.keyboardVisible = height > 0
  }
  private readonly onAvoidAreaChange = (event: window.AvoidAreaOptions): void => {
    if (event.type === window.AvoidAreaType.TYPE_SYSTEM) {
      this.topInset = this.getUIContext().px2vp(event.area.topRect.height)
    }
    if (event.type === window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR) {
      this.bottomInset = this.getUIContext().px2vp(event.area.bottomRect.height)
    }
  }

  onBackPress(): boolean {
    if (this.dialogExitBlocking) return true
    if (this.apiUsageMode.length > 0) {
      this.apiUsageMode = ''
      return true
    }
    if (this.showLayaDecision) {
      this.showLayaDecision = false
      return true
    }
    if (this.helpDialog.length > 0) {
      this.helpDialog = ''
      return true
    }
    if (this.showSettings) {
      this.showSettings = false
      return true
    }
    if (this.viewModel.dismissTopDialogIfIdle()) {
      return true
    }
    if (this.chatInputExpanded) {
      if (this.keyboardVisible) {
        this.getUIContext().getFocusController().clearFocus()
      } else {
        this.chatInputExpanded = false
      }
      return true
    }
    if (this.viewModel.closeHistoryDrawer()) return true
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
    window.getLastWindow(context).then((mainWindow: window.Window) => {
      this.mainWindow = mainWindow
      if (deviceInfo.deviceType === '2in1') {
        this.desktopTitleHeight = mainWindow.getWindowDecorHeight()
        this.onTitleButtonRectChange(mainWindow.getTitleButtonRect())
        mainWindow.on('windowTitleButtonRectChange', this.onTitleButtonRectChange)
        mainWindow.setWindowDecorVisible(false)
        this.desktopTitleVisible = true
      }
      this.topInset = this.getUIContext().px2vp(mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM).topRect.height)
      this.bottomInset = this.getUIContext().px2vp(
        mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR).bottomRect.height)
      mainWindow.on('avoidAreaChange', this.onAvoidAreaChange)
      mainWindow.on('keyboardHeightChange', this.onKeyboardHeightChange)
    }).catch(() => {})
    this.viewModel.initialize(context)
    setTimeout(() => {
      this.showLaunch = false
      themeService.finishLaunch()
    }, 1200)
  }

  onPageShow(): void {
    this.viewModel.setConversationTitleActive(true)
  }

  onPageHide(): void {
    this.viewModel.setConversationTitleActive(false)
  }

  aboutToDisappear(): void {
    if (this.desktopTitleVisible) {
      this.mainWindow?.off('windowTitleButtonRectChange', this.onTitleButtonRectChange)
    }
    this.mainWindow?.off('avoidAreaChange', this.onAvoidAreaChange)
    this.mainWindow?.off('keyboardHeightChange', this.onKeyboardHeightChange)
    clearTimeout(this.focusTimer)
    this.viewModel.dispose()
  }

  private modalFocusId(): string {
    if (this.apiUsageMode.length > 0) return 'api-usage-dialog'
    if (this.showLayaDecision) return 'laya-decision-dialog'
    if (this.helpDialog.length > 0) return 'desktop-help-dialog'
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
    this.chatInputExpanded = false
    this.phoneTabBarHidden = false
    this.phoneTabBarScrollDelta = 0
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
    this.chatInputExpanded = false
    this.viewModel.closeHistoryDrawer()
    this.viewModel.newChat()
    this.changeTab(0)
  }

  private showMenuInfo(about: boolean): void {
    this.helpDialog = about ? 'about' : 'shortcuts'
  }

  private handleKey(event: KeyEvent): boolean {
    if (this.dialogExitBlocking) return true
    if (event.keyCode === KeyCode.KEYCODE_ESCAPE && event.type === KeyType.Down) {
      if (this.apiUsageMode.length > 0) {
        this.apiUsageMode = ''
        return true
      }
      if (this.showLayaDecision) {
        this.showLayaDecision = false
        return true
      }
      if (this.helpDialog.length > 0) {
        this.helpDialog = ''
        return true
      }
      if (this.showSettings) {
        this.showSettings = false
        return true
      }
      if (this.viewModel.dismissTopDialogIfIdle()) return true
      return this.viewModel.closeHistoryDrawer()
    }
    if (event.keyCode !== KeyCode.KEYCODE_N) {
      return false
    }
    if (event.type === KeyType.Up) {
      this.newChatKeyHeld = false
      return false
    }
    if (this.apiUsageMode.length > 0 || this.showLayaDecision || this.helpDialog.length > 0 || this.showSettings || this.activeTab !== 0 || !event.getModifierKeyState?.(['ctrl']) ||
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

  private usePhoneTabs(): boolean {
    return this.windowWidth < 600 && deviceInfo.deviceType === 'phone' && deviceInfo.apiAvailable('26.0.0')
  }

  private mobileNavigationHeight(): number {
    return this.usePhoneTabs() ? 84 : 52
  }

  private handleLongPageScroll(yOffset: number): void {
    if (!this.usePhoneTabs() || Math.abs(yOffset) < 0.2) return
    if (this.phoneTabBarScrollDelta === 0 || this.phoneTabBarScrollDelta * yOffset > 0) {
      this.phoneTabBarScrollDelta += yOffset
    } else {
      this.phoneTabBarScrollDelta = yOffset
    }
    if (Math.abs(this.phoneTabBarScrollDelta) < 8) return
    this.phoneTabBarHidden = this.phoneTabBarScrollDelta > 0
    this.phoneTabBarScrollDelta = 0
  }

  private setPhoneHistoryOpen(open: boolean): void {
    this.getUIContext().animateTo({ duration: 220, curve: Curve.EaseInOut }, () => {
      this.phoneHistoryOpen = open
    })
  }

  private finishHistorySwipe(event: GestureEvent): void {
    if (this.usePhoneTabs() && this.activeTab === 0 && !this.phoneHistoryOpen && !this.chatInputExpanded && event.offsetX >= 48) {
      this.setPhoneHistoryOpen(true)
    }
  }

  private pageContentWidth(): number {
    const navigationWidth = this.windowWidth >= 840 ? 160 : this.windowWidth >= 600 ? 88 : 0
    return Math.max(1, Math.min(1280, this.windowWidth - navigationWidth - 2 * this.pagePadding()))
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
  private ChatPage() {
    Column({ space: this.windowWidth < 600 ? 4 : 8 }) {
      if (!this.usePhoneTabs()) {
        ChatRunTicker({
          viewModel: this.viewModel,
          active: this.activeTab === 0,
          compact: this.windowWidth < 600,
          topSpacing: this.windowWidth >= 600 ? 4 : 0
        })
      }
      ChatTab({
        compactTicker: this.usePhoneTabs(),
        compactPage: this.windowWidth < 600,
        inputExpanded: this.chatInputExpanded,
        onInputExpandedChange: (expanded: boolean): void => { this.chatInputExpanded = expanded },
        contentInset: this.usePhoneTabs() ? this.pagePadding() : 0,
        contentBottomInset: this.usePhoneTabs() && !this.keyboardVisible ? (this.mobileNavigationHeight() + 8) : 0,
        compactHistoryManaged: this.usePhoneTabs(),
        compactHistoryOpen: this.phoneHistoryOpen,
        onCompactHistoryChange: (open: boolean): void => { this.setPhoneHistoryOpen(open) },
        leadingInset: this.windowWidth >= 840 ? this.pagePadding() : 0,
        onRequestModel: () => {
          this.changeTab(1)
          this.showToast('请先加载模型', 1800)
        },
        viewModel: this.viewModel,
        renderVersion: this.stateVersion,
        active: this.activeTab === 0,
        dialogVisible: this.apiUsageMode.length > 0 || this.showLayaDecision || this.helpDialog.length > 0 || this.dialogExitBlocking || this.showSettings || this.viewModel.showModelLoadDialog || this.viewModel.showBuiltinModelInstallDialog ||
          this.viewModel.showModelMarketDialog || this.viewModel.showDeleteModelDialog
      })
      .padding({ left: this.usePhoneTabs() || this.windowWidth >= 840 ? 0 : this.pagePadding(), right: this.usePhoneTabs() ? 0 : this.pagePadding() })
      .width('100%')
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    // The window handles system navigation avoidance; the chat page adds only a visual gap.
    .padding({ bottom: this.windowWidth >= 600 ? $r('app.float.wide_bottom_spacing') :
      (this.usePhoneTabs() || this.keyboardVisible ? 0 : this.mobileNavigationHeight() + 8) })
    .opacity(this.usePhoneTabs() || this.transitionTab === 0 ? 1 : 0)
    .visibility(this.usePhoneTabs() || (this.visibleTabs & 1) !== 0 ? Visibility.Visible : Visibility.Hidden)
    .hitTestBehavior(this.activeTab === 0 ? HitTestMode.Default : HitTestMode.None)
    .accessibilityLevel(this.activeTab === 0 ? 'auto' : 'no-hide-descendants')
    .parallelGesture(PanGesture({ direction: PanDirection.Horizontal, distance: 12 })
      .onActionEnd((event: GestureEvent) => this.finishHistorySwipe(event)))
  }

  @Builder
  private ModelsPage() {
    ModelTab({
      onContentScroll: (yOffset: number): void => {
        this.handleLongPageScroll(yOffset)
      },
      layaReady: this.viewModel.layaReady,
      layaStatus: this.viewModel.layaStatusText(),
      onLayaDecision: () => { this.showLayaDecision = true },
      extendBottom: this.windowWidth >= 600,
      bottomOverlayInset: this.windowWidth < 600 && !this.keyboardVisible && !this.usePhoneTabs() ?
        this.mobileNavigationHeight() : 0,
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
    .opacity(this.usePhoneTabs() || this.transitionTab === 1 ? 1 : 0)
    .visibility(this.usePhoneTabs() || (this.visibleTabs & 2) !== 0 ? Visibility.Visible : Visibility.Hidden)
    .hitTestBehavior(this.activeTab === 1 ? HitTestMode.Default : HitTestMode.None)
    .accessibilityLevel(this.activeTab === 1 ? 'auto' : 'no-hide-descendants')
  }

  @Builder
  private ServicePage() {
    ApiServerTab({
      contentWidth: this.pageContentWidth(),
      onContentScroll: (yOffset: number): void => {
        this.handleLongPageScroll(yOffset)
      },
      layaReady: this.viewModel.layaReady,
      layaStatus: this.viewModel.layaStatusText(),
      apiServiceTarget: this.viewModel.apiServiceTarget,
      onApiHelp: (mode: 'chat' | 'decision', example: string) => {
        this.apiUsageMode = mode
        this.apiUsageExample = example
      },
      extendBottom: this.windowWidth >= 600,
      bottomOverlayInset: this.windowWidth < 600 && !this.keyboardVisible && !this.usePhoneTabs() ?
        this.mobileNavigationHeight() : 0,
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
    .opacity(this.usePhoneTabs() || this.transitionTab === 2 ? 1 : 0)
    .visibility(this.usePhoneTabs() || (this.visibleTabs & 4) !== 0 ? Visibility.Visible : Visibility.Hidden)
    .hitTestBehavior(this.activeTab === 2 ? HitTestMode.Default : HitTestMode.None)
    .accessibilityLevel(this.activeTab === 2 ? 'auto' : 'no-hide-descendants')
  }

  @Builder
  private MonitorPage() {
    MonitorTab({
      contentWidth: this.pageContentWidth(),
      onContentScroll: (yOffset: number): void => {
        this.handleLongPageScroll(yOffset)
      },
      extendBottom: this.windowWidth >= 600,
      bottomOverlayInset: this.windowWidth < 600 && !this.keyboardVisible ?
        (this.usePhoneTabs() && this.phoneTabBarHidden ? this.bottomInset : this.mobileNavigationHeight()) : 0,
      viewModel: this.viewModel,
      active: this.activeTab === 3
    })
    .padding({ left: this.pagePadding(), right: this.pagePadding(), top: this.windowWidth < 600 ? 8 : 0 })
    .width(Math.max(1, Math.min(1280 + 2 * this.pagePadding(), this.windowWidth -
      (this.windowWidth >= 840 ? 160 : this.windowWidth >= 600 ? 88 : 0))))
    .height('100%')
    .opacity(this.usePhoneTabs() || this.transitionTab === 3 ? 1 : 0)
    .visibility(this.usePhoneTabs() || (this.visibleTabs & 8) !== 0 ? Visibility.Visible : Visibility.Hidden)
    .hitTestBehavior(this.activeTab === 3 ? HitTestMode.Default : HitTestMode.None)
    .accessibilityLevel(this.activeTab === 3 ? 'auto' : 'no-hide-descendants')
  }

  @Builder
  private PhonePage(index: number) {
    if (index === 0) {
      this.ChatPage()
    }
    else if (index === 1) {
      this.ModelsPage()
    }
    else if (index === 2) {
      this.ServicePage()
    }
    else if (index === 3) {
      this.MonitorPage()
    }
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
            status: this.viewModel.headerStatus(),
            statusColor: this.viewModel.headerColor(),
            newChatEnabled: this.viewModel.canManageConversations(),
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
        if (this.usePhoneTabs()) {
          PhoneTabs({
            activeTab: this.activeTab, keyboardVisible: this.keyboardVisible,
            barHidden: this.phoneTabBarHidden,
            pageContent: (index: number): void => { this.PhonePage(index) },
            onTabChange: (index: number): void => { this.changeTab(index) }
          }).width('100%').layoutWeight(1)
        } else {
        Flex({ direction: this.windowWidth >= 600 ? FlexDirection.RowReverse : FlexDirection.Column }) {
          Stack() {
            this.ChatPage()
            this.ModelsPage()
            this.ServicePage()
            this.MonitorPage()
          }
          .layoutWeight(1)
          .width(this.windowWidth >= 600 ? 0 : '100%')
          .height(this.windowWidth >= 600 ? '100%' : 0)
          .margin({ bottom: this.windowWidth < 600 && !this.keyboardVisible ? -this.mobileNavigationHeight() : 0 })
          .zIndex(this.modelCardDragging ? 10 : 0)
          BottomTabs({
            bottomInset: this.keyboardVisible ? 0 : this.bottomInset,
            onSettings: () => { this.showSettings = true },
            activeTab: this.activeTab,
            windowWidth: this.windowWidth,
            onTabChange: (index: number) => {
              this.changeTab(index)
            }
          })
          .width(this.windowWidth >= 840 ? 160 : this.windowWidth >= 600 ? 88 : '100%')
          .height(this.windowWidth >= 600 ? '100%' : this.mobileNavigationHeight())
          .zIndex(this.windowWidth < 600 ? 11 : 0)
          .flexShrink(0)
          .visibility(this.windowWidth < 600 && this.keyboardVisible ? Visibility.None : Visibility.Visible)
        }
        .width('100%')
        .layoutWeight(1)
        }
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Start)
      .padding({ top: this.usePhoneTabs() ? this.topInset : 0,
        bottom: this.windowWidth < 600 && this.keyboardVisible ? 8 : 0 })
      .id('app-content')
      .focusable(!this.dialogExitBlocking && this.modalFocusId() === 'app-content')

      if (this.usePhoneTabs() && this.phoneHistoryOpen) {
        Column()
          .width('100%').height('100%').backgroundColor('#66000000')
          .hitTestBehavior(HitTestMode.Block)
          .onClick(() => { this.setPhoneHistoryOpen(false) })
          .transition(TransitionEffect.OPACITY.animation({ duration: 220, curve: Curve.EaseInOut }))
        Column() {
          ChatHistoryPanel({
            viewModel: this.viewModel,
            renderVersion: this.stateVersion,
            closeOnSelection: true,
            onClose: () => { this.setPhoneHistoryOpen(false) }
          })
        }
        .width(Math.max(1, Math.min(280, this.windowWidth - 40)))
        .height('100%')
        .padding({ top: this.topInset, bottom: this.bottomInset })
        .backgroundColor($r('app.color.page'))
        .border({ width: { right: 0.5 }, color: $r('app.color.divider') })
        .hitTestBehavior(HitTestMode.BLOCK_HIERARCHY)
        .gesture(PanGesture({ direction: PanDirection.Horizontal, distance: 12 })
          .onActionEnd((event: GestureEvent) => {
            if (event.offsetX <= -48) this.setPhoneHistoryOpen(false)
          }))
        .transition(TransitionEffect.move(TransitionEdge.START).combine(TransitionEffect.OPACITY)
          .animation({ duration: 220, curve: Curve.EaseInOut }))
      }

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
      if (this.apiUsageMode.length > 0) {
        ApiUsageDialog({
          mode: this.apiUsageMode,
          example: this.apiUsageExample,
          availableWidth: this.windowWidth,
          availableHeight: this.windowHeight,
          onClose: () => { this.apiUsageMode = '' }
        })
        .id('api-usage-dialog')
        .focusable(true)
        .onAppear(() => this.updateModalFocus(true))
      }
      if (this.showLayaDecision) {
        LayaDecisionDialog({
          availableWidth: this.windowWidth,
          availableHeight: this.windowHeight,
          filesDir: this.abilityContext?.filesDir ?? '',
          onModelReady: () => { this.viewModel.refreshLayaReady() },
          onClose: () => {
            this.showLayaDecision = false
            this.viewModel.refreshLayaReady()
          }
        })
        .id('laya-decision-dialog')
        .focusable(true)
        .onAppear(() => this.updateModalFocus(true))
      }
      if (this.helpDialog.length > 0) {
        DesktopHelpDialog({
          about: this.helpDialog === 'about',
          version: this.viewModel.appVersion,
          availableWidth: this.windowWidth,
          availableHeight: this.windowHeight,
          onClose: () => { this.helpDialog = '' }
        })
        .id('desktop-help-dialog')
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
      Column() {
        if (this.desktopTitleVisible) {
          DesktopTitleBar({
            mainWindow: this.mainWindow,
            barHeight: this.desktopTitleHeight,
            controlsWidth: this.desktopControlsWidth,
            busy: this.viewModel.busy,
            onNewChat: () => this.newChat(),
            onSettings: () => { this.showSettings = true },
            onShortcuts: () => this.showMenuInfo(false),
            onAbout: () => this.showMenuInfo(true)
          })
          .enabled(!this.showLaunch && !this.dialogExitBlocking && this.modalFocusId() === 'app-content')
        }
        Stack() {
          Column()
            .width('100%')
            .height('100%')
            .backgroundColor(this.windowWidth < 600 ? $r('app.color.page_compact') : $r('app.color.page'))
            .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
          this.MainScreen()
        }
        .width('100%')
        .height('100%')
        .backgroundColor(this.windowWidth < 600 ? $r('app.color.page_compact') : $r('app.color.page'))
        .layoutWeight(1)
      }
      .width('100%')
      .height('100%')
      if (this.showLaunch) {
        LaunchScreen()
          .width('100%')
          .height('100%')
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
          .hitTestBehavior(HitTestMode.Block)
          .zIndex(100)
      }
    }
    .width('100%')
    .height('100%')
    .onKeyEvent((event: KeyEvent): boolean => this.handleKey(event))
  }
}
