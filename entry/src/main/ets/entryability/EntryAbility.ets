// Derived from Turbo1123/turbo-ai-chat-harmonyos and subsequently modified.
// See README.md and Git history for provenance and change details.

import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { window } from '@kit.ArkUI'

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(0x0000, 'TurboAIChat', 'Ability created')
  }

  private configureWindow(windowStage: window.WindowStage): void {
    try {
      const mainWindow = windowStage.getMainWindowSync()
      mainWindow.setWindowBackgroundColor('#06121F')
      mainWindow.setWindowLayoutFullScreen(false).catch((err: Error) => {
        hilog.warn(0x0000, 'TurboAIChat', 'set window layout failed: %{public}s', JSON.stringify(err))
      })
      mainWindow.setWindowSystemBarEnable(['status', 'navigation']).catch((err: Error) => {
        hilog.warn(0x0000, 'TurboAIChat', 'set system bar enable failed: %{public}s', JSON.stringify(err))
      })
      mainWindow.setWindowSystemBarProperties({
        statusBarColor: '#00000000',
        navigationBarColor: '#00000000',
        statusBarContentColor: '#F4FBFF',
        navigationBarContentColor: '#F4FBFF',
        isStatusBarLightIcon: true,
        isNavigationBarLightIcon: true
      }).catch((err: Error) => {
        hilog.warn(0x0000, 'TurboAIChat', 'set system bar style failed: %{public}s', JSON.stringify(err))
      })
    } catch (err) {
      hilog.warn(0x0000, 'TurboAIChat', 'configure window failed: %{public}s', JSON.stringify(err))
    }
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
