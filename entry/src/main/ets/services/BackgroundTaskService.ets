import { backgroundProcessManager, backgroundTaskManager } from '@kit.BackgroundTasksKit'
import { common, wantAgent } from '@kit.AbilityKit'
import { process } from '@kit.ArkTS'
import { deviceInfo } from '@kit.BasicServicesKit'
import { notificationManager } from '@kit.NotificationKit'
import { formatError } from '../utils/formatters'

type BackgroundTaskKind = 'compute' | 'download'

class BackgroundTaskState {
  wanted: boolean = false
  blocked: boolean = false
  id: number = -1
  notificationId: number = -1
  queue: Promise<void> = Promise.resolve()
}

export class BackgroundTaskService {
  private context?: common.UIAbilityContext
  private disposed: boolean = false
  private compute: BackgroundTaskState = new BackgroundTaskState()
  private download: BackgroundTaskState = new BackgroundTaskState()
  private progress: number = 0
  private modelName: string = ''
  private lastProgress: number = -1
  private lastPublishedAt: number = 0
  private foreground: boolean = true
  private inferenceActive: boolean = false
  private performanceApplied: boolean = false
  private performanceQueue: Promise<void> = Promise.resolve()
  computeSupported: boolean = false
  onUnavailable: (kind: BackgroundTaskKind) => void = () => {}

  private onCancelled = (event: backgroundTaskManager.ContinuousTaskCancelInfo): void => {
    for (const kind of ['compute', 'download'] as BackgroundTaskKind[]) {
      const state = kind === 'compute' ? this.compute : this.download
      if (state.id !== event.id) continue
      state.id = -1
      state.notificationId = -1
      if (state.wanted && !this.disposed) {
        state.blocked = true
        this.onUnavailable(kind)
      }
    }
  }

  initialize(context: common.UIAbilityContext): void {
    this.context = context
    this.computeSupported = deviceInfo.deviceType === '2in1'
    try {
      backgroundTaskManager.on('continuousTaskCancel', this.onCancelled)
    } catch (error) {
      console.warn(`Background task listener failed: ${formatError(error as Object)}`)
    }
  }

  setComputeActive(active: boolean): void {
    this.setWanted('compute', this.compute, active && this.computeSupported)
  }

  setPerformanceState(foreground: boolean, active: boolean): void {
    if (!this.computeSupported || this.disposed ||
      (this.foreground === foreground && this.inferenceActive === active)) return
    this.foreground = foreground
    this.inferenceActive = active
    this.performanceQueue = this.performanceQueue.then(() => this.reconcilePerformance()).catch((error: Error) => {
      console.warn(`Background performance mode failed: ${formatError(error as Object)}`)
    })
  }

  private async reconcilePerformance(): Promise<void> {
    const wanted = !this.disposed && !this.foreground && this.inferenceActive
    if (wanted === this.performanceApplied) return
    const result: number | void = await backgroundProcessManager.setPowerSaveMode(process.pid, wanted ?
      backgroundProcessManager.PowerSaveMode.EFFICIENCY_MODE : backgroundProcessManager.PowerSaveMode.DEFAULT_MODE)
    if (typeof result === 'number' && result !== 0) throw new Error(`power mode error ${result}`)
    this.performanceApplied = wanted
    if (wanted !== (!this.disposed && !this.foreground && this.inferenceActive)) {
      await this.reconcilePerformance()
    }
  }

  setDownloadActive(active: boolean, progress: number, modelName: string): void {
    this.progress = Math.max(0, Math.min(100, Math.floor(progress)))
    this.modelName = modelName
    this.setWanted('download', this.download, active)
    if (active && this.download.id >= 0 &&
      (this.progress !== this.lastProgress || Date.now() - this.lastPublishedAt >= 30000) &&
      Date.now() - this.lastPublishedAt >= 1000) {
      this.lastProgress = this.progress
      this.lastPublishedAt = Date.now()
      this.enqueue('download', this.download, () => this.publishProgress())
    }
  }

  private setWanted(kind: BackgroundTaskKind, state: BackgroundTaskState, active: boolean): void {
    if (this.context === undefined || this.disposed || state.wanted === active) return
    state.wanted = active
    state.blocked = false
    this.enqueue(kind, state, () => this.reconcile(kind, state))
  }

  private enqueue(kind: BackgroundTaskKind, state: BackgroundTaskState, task: () => Promise<void>): void {
    state.queue = state.queue.then(task).catch((error: Error) => {
      console.warn(`Background ${kind} task failed: ${formatError(error as Object)}`)
      if (state.wanted && !this.disposed) {
        state.blocked = true
        this.onUnavailable(kind)
      }
    })
  }

  private async reconcile(kind: BackgroundTaskKind, state: BackgroundTaskState): Promise<void> {
    const context = this.context
    if (context === undefined) return
    if (state.wanted && !this.disposed && !state.blocked && state.id < 0) {
      const agent = await wantAgent.getWantAgent({
        wants: [{ bundleName: context.abilityInfo.bundleName, abilityName: context.abilityInfo.name }],
        actionType: wantAgent.OperationType.START_ABILITY,
        requestCode: kind === 'compute' ? 1 : 2,
        wantAgentFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
      })
      if (!state.wanted || this.disposed) return
      const request = new backgroundTaskManager.ContinuousTaskRequest()
      request.backgroundTaskModes = [kind === 'compute' ?
        backgroundTaskManager.BackgroundTaskMode.MODE_TASK_KEEPING :
        backgroundTaskManager.BackgroundTaskMode.MODE_DATA_TRANSFER]
      request.backgroundTaskSubmodes = [kind === 'compute' ?
        backgroundTaskManager.BackgroundTaskSubmode.SUBMODE_NORMAL_NOTIFICATION :
        backgroundTaskManager.BackgroundTaskSubmode.SUBMODE_LIVE_VIEW_NOTIFICATION]
      request.wantAgent = agent
      const result = await backgroundTaskManager.startBackgroundRunning(context, request)
      state.id = result.continuousTaskId as number
      state.notificationId = result.notificationId
      console.info(`Background ${kind} task registered: ${state.id}`)
      if (kind === 'download' && state.wanted && !this.disposed) await this.publishProgress()
    }
    if ((!state.wanted || this.disposed) && state.id >= 0) {
      await backgroundTaskManager.stopBackgroundRunning(context, state.id)
      console.info(`Background ${kind} task released: ${state.id}`)
      state.id = -1
      state.notificationId = -1
    }
  }

  private async publishProgress(): Promise<void> {
    if (!this.download.wanted || this.disposed || this.download.notificationId < 0) return
    await notificationManager.publish({
      id: this.download.notificationId,
      content: {
        notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_SYSTEM_LIVE_VIEW,
        systemLiveView: { typeCode: 8, title: '模型下载', text: this.modelName }
      },
      notificationSlotType: notificationManager.SlotType.LIVE_VIEW,
      template: {
        name: 'downloadTemplate',
        data: { title: '模型下载', fileName: this.modelName, progressValue: this.progress }
      }
    })
    this.lastProgress = this.progress
    this.lastPublishedAt = Date.now()
  }

  refresh(): void {
    if (this.context === undefined || this.disposed) return
    this.enqueue('compute', this.compute, () => this.reconcile('compute', this.compute))
    this.enqueue('download', this.download, () => this.reconcile('download', this.download))
  }

  async saveBeforeSuspend(save: () => Promise<void>): Promise<void> {
    let requestId = -1
    try {
      requestId = backgroundTaskManager.requestSuspendDelay('保存对话', () => {}).requestId
    } catch (error) {
      console.warn(`Background save delay unavailable: ${formatError(error as Object)}`)
    }
    try {
      await save()
    } finally {
      if (requestId >= 0) {
        try { backgroundTaskManager.cancelSuspendDelay(requestId) } catch (_) {}
      }
    }
  }

  dispose(): void {
    this.disposed = true
    this.performanceQueue = this.performanceQueue.then(() => this.reconcilePerformance()).catch((error: Error) => {
      console.warn(`Background performance reset failed: ${formatError(error as Object)}`)
    })
    try {
      backgroundTaskManager.off('continuousTaskCancel', this.onCancelled)
    } catch (_) {}
    this.compute.wanted = false
    this.download.wanted = false
    this.enqueue('compute', this.compute, () => this.reconcile('compute', this.compute))
    this.enqueue('download', this.download, () => this.reconcile('download', this.download))
  }
}
