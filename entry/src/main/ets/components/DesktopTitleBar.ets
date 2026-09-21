import { window } from '@kit.ArkUI'
import { KeyCode } from '@kit.InputKit'

@Component
export struct DesktopTitleBar {
  @Prop busy: boolean = false
  @Prop barHeight: number = 37
  @Prop controlsWidth: number = 148
  @State private opened: boolean = false
  @State private activeMenu: number = 0
  @State private hovered: number = -1
  @State private menuOffsets: number[] = [0, 0, 0]
  @State private barWidth: number = 1000
  private readonly menuNames: string[] = ['对话', '设置', '帮助']
  private readonly menuIds: string[] = ['desktop-chat-menu', 'desktop-settings-menu', 'desktop-help-menu']
  mainWindow?: window.Window
  onNewChat: () => void = () => {}
  onSettings: () => void = () => {}
  onShortcuts: () => void = () => {}
  onAbout: () => void = () => {}

  private moveWindow(event: TouchEvent): void {
    if (event.type === TouchType.Down) {
      this.opened = false
      this.mainWindow?.startMoving().catch(() => {})
    }
  }

  private toggleWindowSize(): void {
    if (this.mainWindow?.getWindowStatus() === window.WindowStatusType.FLOATING) {
      this.mainWindow.maximize().catch(() => {})
    } else {
      this.mainWindow?.recover().catch(() => {})
    }
  }

  private menuKey(event: KeyEvent): boolean {
    if (event.type !== KeyType.Down) return false
    if (event.keyCode === KeyCode.KEYCODE_ESCAPE && this.opened) {
      this.opened = false
      this.getUIContext().getFocusController().requestFocus(this.menuIds[this.activeMenu])
      return true
    }
    if (this.opened && (event.keyCode === KeyCode.KEYCODE_DPAD_LEFT ||
      event.keyCode === KeyCode.KEYCODE_DPAD_RIGHT)) {
      this.activeMenu = (this.activeMenu + (event.keyCode === KeyCode.KEYCODE_DPAD_LEFT ? 2 : 1)) % 3
      return true
    }
    return false
  }

  @Builder
  private Action(label: string, id: string, enabled: boolean, action: () => void) {
    Button({ type: ButtonType.Normal }) {
      Text(label)
        .width('100%')
        .textAlign(TextAlign.Start)
        .fontSize(14)
        .fontWeight(FontWeight.Normal)
        .fontColor($r('app.color.text_title'))
    }
      .id(id)
      .width('100%').height(32)
      .padding({ left: 10, right: 10 })
      .backgroundColor(Color.Transparent)
      .borderRadius(4)
      .enabled(enabled)
      .onClick(() => {
        this.opened = false
        action()
      })
  }

  @Builder
  private MenuContent() {
    Column() {
      if (this.activeMenu === 0) {
        this.Action('新对话', 'desktop-new-chat', !this.busy, () => this.onNewChat())
      } else if (this.activeMenu === 1) {
        this.Action('外观设置…', 'desktop-appearance', true, () => this.onSettings())
      } else {
        this.Action('快捷键说明', 'desktop-shortcuts', true, () => this.onShortcuts())
        this.Action('关于 Turbo AI Chat', 'desktop-about', true, () => this.onAbout())
      }
    }
    .width(208).padding(6)
    .backgroundColor($r('app.color.dialog'))
    .borderRadius(6)
    .onKeyEvent((event: KeyEvent) => this.menuKey(event))
  }

  build() {
    Row({ space: 4 }) {
      Row({ space: 8 }) {
        if (this.barWidth - this.controlsWidth >= 390) {
          Text('Turbo AI Chat').fontSize(14).fontColor($r('sys.color.font_primary'))
            .maxLines(1)
        }
      }
      .height('100%')
      .margin({ right: 12 })
      .flexShrink(0)
      .onTouch((event: TouchEvent) => this.moveWindow(event))
      .gesture(TapGesture({ count: 2 }).onAction(() => this.toggleWindowSize()))
      Row({ space: 4 }) {
        ForEach(this.menuNames, (label: string, index: number) => {
          Button(label, { type: ButtonType.Normal })
            .height(32).padding({ left: 12, right: 12 })
            .fontSize(14)
            .fontColor($r('sys.color.font_primary'))
            .backgroundColor((this.opened && this.activeMenu === index) || this.hovered === index
              ? $r('sys.color.interactive_hover') : Color.Transparent)
            .borderRadius(4)
            .id(this.menuIds[index])
            .accessibilityText(label + '菜单')
            .onAreaChange((_old: Area, area: Area) => {
              this.menuOffsets[index] = Number(area.position.x)
            })
            .onHover((hover: boolean) => {
              this.hovered = hover ? index : -1
              if (hover && this.opened) this.activeMenu = index
            })
            .onClick(() => {
              if (this.opened && this.activeMenu === index) {
                this.opened = false
              } else {
                this.activeMenu = index
                this.opened = true
              }
            })
        }, (label: string) => label)
      }
      .flexShrink(0)
      // Keep one popup open while the pointer switches its content and anchor.
      .bindPopup(this.opened, {
        builder: this.MenuContent(),
        placement: Placement.BottomLeft,
        offset: { x: this.menuOffsets[this.activeMenu], y: 0 },
        enableArrow: false,
        mask: false,
        focusable: true,
        targetSpace: 4,
        popupColor: $r('app.color.dialog'),
        backgroundBlurStyle: BlurStyle.NONE,
        radius: 6,
        onStateChange: (event) => { if (!event.isVisible) this.opened = false }
      })
      Row()
        .layoutWeight(1)
        .height('100%')
        .id('desktop-title-drag')
        .onTouch((event: TouchEvent) => this.moveWindow(event))
        .gesture(TapGesture({ count: 2 }).onAction(() => this.toggleWindowSize()))
    }
    .padding({ left: 12, right: this.controlsWidth + 8 })
    .width('100%')
    .height(this.barHeight)
    .onAreaChange((_old: Area, area: Area) => { this.barWidth = Number(area.width) })
    .onKeyEvent((event: KeyEvent) => this.menuKey(event))
    .backgroundColor($r('sys.color.container_modal_background'))
  }
}
