import { ThemeMode, themeService } from '../services/ThemeService'
import { ActionButtonStyle, CompactActionStyle } from './ButtonStyles'

import { dialogFade, dialogScale } from './DialogMotion'

@Component
export struct SettingsDialog {
  @StorageLink('themeMode') private themeMode: ThemeMode = 'dark'
  @Prop availableWidth: number = 360
  @Prop availableHeight: number = 640
  onClose: () => void = () => {}

  @Builder
  private ThemeButton(label: string, mode: ThemeMode, icon: Resource) {
    Button() {
      Row({ space: 6 }) {
        Image(icon)
          .width(18)
          .height(18)
          .fillColor(this.themeMode === mode ? $r('app.color.nav_active_text') : $r('app.color.text_secondary'))
        Text(label)
          .fontSize(12)
          .fontWeight(this.themeMode === mode ? FontWeight.Medium : FontWeight.Normal)
          .fontColor(this.themeMode === mode ? $r('app.color.nav_active_text') : $r('app.color.text_secondary'))
      }
      .justifyContent(FlexAlign.Center)
    }
      .attributeModifier(new ActionButtonStyle(
        this.themeMode === mode ? $r('app.color.selected_background') : Color.Transparent,
        this.themeMode === mode ? $r('app.color.nav_active_text') : $r('app.color.text_secondary')))
      .padding({ left: 4, right: 4 })
      .accessibilityText(label)
      .layoutWeight(1)
      .onClick(() => themeService.select(mode))
  }


  build() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.scrim'))
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        .onClick(() => this.onClose())

      Column({ space: 18 }) {
        Row() {
          Text('设置')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_title'))
            .layoutWeight(1)
          Button('关闭')
            .attributeModifier(new CompactActionStyle())
            .onClick(() => this.onClose())
        }
        .width('100%')
        Scroll() {
          Column({ space: 12 }) {
            Text('外观')
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_title'))
              .width('100%')
            Row({ space: 6 }) {
              this.ThemeButton('浅色模式', 'light', $r('app.media.theme_day'))
              this.ThemeButton('深色模式', 'dark', $r('app.media.theme_night'))
              this.ThemeButton('跟随系统', 'system', $r('app.media.theme_system'))
            }
            .width('100%')
          }
          .width('100%')
        }
        .width('100%')
        .constraintSize({ maxHeight: Math.max(40, this.availableHeight - 140) })
      }
      .padding(18)
      .width(Math.max(1, Math.min(480, this.availableWidth - 32)))
      .constraintSize({ maxHeight: Math.max(1, this.availableHeight - 32) })
      .backgroundColor($r('app.color.dialog'))
      .border({ width: 1, color: $r('app.color.border') })
      .borderRadius($r('app.float.dialog_radius'))
      .transition(dialogScale())
    }
    .width('100%')
    .height('100%')
    .transition(dialogFade())
  }
}
