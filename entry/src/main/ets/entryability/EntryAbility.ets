import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { window } from '@kit.ArkUI'

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(0x0000, 'Gemma4MNN', 'Ability created')
  }

  private configureImmersiveWindow(windowStage: window.WindowStage): void {
    try {
      const mainWindow = windowStage.getMainWindowSync()
      mainWindow.setWindowLayoutFullScreen(true).catch((err: Error) => {
        hilog.warn(0x0000, 'Gemma4MNN', 'set fullscreen failed: %{public}s', JSON.stringify(err))
      })
      mainWindow.setWindowSystemBarEnable(['status', 'navigation']).catch((err: Error) => {
        hilog.warn(0x0000, 'Gemma4MNN', 'set system bar enable failed: %{public}s', JSON.stringify(err))
      })
      mainWindow.setWindowSystemBarProperties({
        statusBarColor: '#00000000',
        navigationBarColor: '#00000000',
        statusBarContentColor: '#F4FBFF',
        navigationBarContentColor: '#F4FBFF',
        isStatusBarLightIcon: true,
        isNavigationBarLightIcon: true
      }).catch((err: Error) => {
        hilog.warn(0x0000, 'Gemma4MNN', 'set system bar style failed: %{public}s', JSON.stringify(err))
      })
    } catch (err) {
      hilog.warn(0x0000, 'Gemma4MNN', 'configure window failed: %{public}s', JSON.stringify(err))
    }
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    this.configureImmersiveWindow(windowStage)
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(0x0000, 'Gemma4MNN', 'loadContent failed: %{public}s', JSON.stringify(err))
      }
      this.configureImmersiveWindow(windowStage)
    })
  }
}
