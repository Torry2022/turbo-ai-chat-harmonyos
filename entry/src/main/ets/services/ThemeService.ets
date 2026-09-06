import { common, ConfigurationConstant } from '@kit.AbilityKit'
import { preferences } from '@kit.ArkData'
import { window } from '@kit.ArkUI'
import { hilog } from '@kit.PerformanceAnalysisKit'

export type ThemeMode = 'dark' | 'light' | 'system'

class ThemeService {
  private context?: common.UIAbilityContext
  private settings?: preferences.Preferences
  private mainWindow?: window.Window
  private launching: boolean = true

  initialize(context: common.UIAbilityContext): void {
    this.context = context
    let mode: ThemeMode = 'dark'
    try {
      this.settings = preferences.getPreferencesSync(context, { name: 'appearance' })
      const saved = this.settings.getSync('theme', 'dark')
      if (saved === 'light' || saved === 'system') {
        mode = saved
      }
    } catch (err) {
      hilog.warn(0, 'TurboAIChat', 'Read appearance failed: %{public}s', String(err))
    }
    this.apply(mode)
  }

  private apply(mode: ThemeMode): void {
    try {
      this.context?.getApplicationContext().setColorMode(mode === 'system'
        ? ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET
        : mode === 'light' ? ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT
          : ConfigurationConstant.ColorMode.COLOR_MODE_DARK)
      AppStorage.setOrCreate<ThemeMode>('themeMode', mode)
    } catch (err) {
      hilog.warn(0, 'TurboAIChat', 'Apply appearance failed: %{public}s', String(err))
    }
  }

  select(mode: ThemeMode): void {
    this.apply(mode)
    try {
      this.settings?.putSync('theme', mode)
      this.settings?.flush().catch((err: Error) => {
        hilog.warn(0, 'TurboAIChat', 'Save appearance failed: %{public}s', String(err))
      })
    } catch (err) {
      hilog.warn(0, 'TurboAIChat', 'Save appearance failed: %{public}s', String(err))
    }
  }

  attachWindow(mainWindow: window.Window): void {
    this.mainWindow = mainWindow
    this.updateWindow()
  }

  finishLaunch(): void {
    this.launching = false
    this.updateWindow()
  }

  updateWindow(): void {
    if (!this.context || !this.mainWindow) {
      return
    }
    try {
      const resources = this.context.resourceManager
      const background = resources.getColorByNameSync(this.launching ? 'start_window_background' : 'page')
      const backgroundColor = `#${(background >>> 0).toString(16).padStart(8, '0')}`
      const text = resources.getColorByNameSync(this.launching ? 'launch_text' : 'text_title')
      const dark = this.launching || this.context.config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK
      AppStorage.setOrCreate<boolean>('darkAppearance', dark)
      this.mainWindow.setWindowBackgroundColor(backgroundColor)
      this.mainWindow.setWindowSystemBarProperties({
        // Background-only ArkUI layers extend beneath the bars; content retains its insets.
        statusBarColor: '#00000000', navigationBarColor: '#00000000',
        statusBarContentColor: `#${text.toString(16).padStart(8, '0')}`,
        navigationBarContentColor: `#${text.toString(16).padStart(8, '0')}`,
        isStatusBarLightIcon: dark, isNavigationBarLightIcon: dark
      }).catch((err: Error) => {
        hilog.warn(0, 'TurboAIChat', 'Update appearance bars failed: %{public}s', String(err))
      })
    } catch (err) {
      hilog.warn(0, 'TurboAIChat', 'Update window appearance failed: %{public}s', String(err))
    }
  }
}

export const themeService = new ThemeService()
