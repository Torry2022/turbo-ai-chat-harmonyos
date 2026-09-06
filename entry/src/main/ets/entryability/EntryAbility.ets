// Derived from Turbo1123/turbo-ai-chat-harmonyos and subsequently modified.
// See README.md and Git history for provenance and change details.

import { AbilityConstant, Configuration, UIAbility, Want } from '@kit.AbilityKit'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { window } from '@kit.ArkUI'
import { themeService } from '../services/ThemeService'

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    themeService.initialize(this.context)
    hilog.info(0x0000, 'TurboAIChat', 'Ability created')
  }

  private configureWindow(windowStage: window.WindowStage): void {
    try {
      const mainWindow = windowStage.getMainWindowSync()
      themeService.attachWindow(mainWindow)
      mainWindow.setWindowLayoutFullScreen(false).catch((err: Error) => {
        hilog.warn(0x0000, 'TurboAIChat', 'set window layout failed: %{public}s', JSON.stringify(err))
      })
      mainWindow.setWindowSystemBarEnable(['status', 'navigation']).catch((err: Error) => {
        hilog.warn(0x0000, 'TurboAIChat', 'set system bar enable failed: %{public}s', JSON.stringify(err))
      })
    } catch (err) {
      hilog.warn(0x0000, 'TurboAIChat', 'configure window failed: %{public}s', JSON.stringify(err))
    }
  }

  onConfigurationUpdate(newConfig: Configuration): void {
    themeService.updateWindow()
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    this.configureWindow(windowStage)
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(0x0000, 'TurboAIChat', 'loadContent failed: %{public}s', JSON.stringify(err))
      }
      this.configureWindow(windowStage)
    })
  }
}
