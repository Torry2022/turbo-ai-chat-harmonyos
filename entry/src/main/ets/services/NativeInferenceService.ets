import entry from 'libentry.so'
import { ChatTurn, GenerationResult, GenerationSettings, ImagePayload } from '../models/ChatTypes'

export class NativeInferenceService {
  private static titleTask?: Promise<GenerationResult>
  private static modelBarrier: Promise<void> = Promise.resolve()
  private static pendingResets: number = 0
  private static foregroundStopEpoch: number = 0
  private static foregroundJobs: number = 0

  private foreground<T>(operation: () => Promise<T>): Promise<T> {
    NativeInferenceService.foregroundJobs++
    const cancelled = this.cancelTitleGeneration()
    const barrier = NativeInferenceService.modelBarrier
    return cancelled.then(() => barrier).then(operation).finally(() => {
      NativeInferenceService.foregroundJobs--
    })
  }

  private generateForeground(operation: () => Promise<GenerationResult>): Promise<GenerationResult> {
    const epoch = NativeInferenceService.foregroundStopEpoch
    return this.foreground<GenerationResult>((): Promise<GenerationResult> => {
      if (epoch !== NativeInferenceService.foregroundStopEpoch) {
        const stopped: GenerationResult = { text: '', generatedTokens: 0, stopReason: 'user_stop' }
        return Promise.resolve(stopped)
      }
      return operation()
    })
  }

  generateTitle(turns: ChatTurn[]): Promise<GenerationResult> {
    if (NativeInferenceService.titleTask !== undefined || NativeInferenceService.pendingResets > 0 ||
      NativeInferenceService.foregroundJobs > 0) return Promise.reject(new Error('模型任务尚未结束'))
    const settings: GenerationSettings = {
      temperature: 0.1, topP: 0.8, topK: 1, repetitionPenalty: 1.05,
      frequencyPenalty: 0, presencePenalty: 0, penaltyWindow: 256
    }
    const task: Promise<GenerationResult> = entry.generateChatStream(turns, 48, settings, (_chunk: string) => {}, true)
    NativeInferenceService.titleTask = task
    const clear = (): void => {
      if (NativeInferenceService.titleTask === task) NativeInferenceService.titleTask = undefined
    }
    task.then(clear, clear)
    return task
  }

  cancelTitleGeneration(): Promise<void> {
    const task = NativeInferenceService.titleTask
    if (task === undefined) return Promise.resolve()
    entry.cancelTitleGeneration()
    return task.then(() => {}, () => {})
  }

  loadModel(configPath: string, threadNum: number, maxNewTokens: number, settings: GenerationSettings): Promise<boolean> {
    return this.foreground<string>((): Promise<string> =>
      entry.loadModelAsync(configPath, threadNum, maxNewTokens, settings)).then((_result: string) => {
      return entry.isLoaded() as boolean
    })
  }

  generateText(
    turns: ChatTurn[],
    maxNewTokens: number,
    settings: GenerationSettings,
    onChunk: (chunk: string) => void
  ): Promise<GenerationResult> {
    return this.generateForeground((): Promise<GenerationResult> =>
      entry.generateChatStream(turns, maxNewTokens, settings, onChunk))
  }

  generateRawPrompt(
    prompt: string,
    maxNewTokens: number,
    endWith: string,
    settings: GenerationSettings,
    onChunk: (chunk: string) => void
  ): Promise<GenerationResult> {
    return this.generateForeground((): Promise<GenerationResult> =>
      entry.generateRawPromptStream(prompt, maxNewTokens, endWith, settings, onChunk))
  }

  generateImage(
    turns: ChatTurn[],
    image: ImagePayload,
    maxNewTokens: number,
    settings: GenerationSettings,
    onChunk: (chunk: string) => void
  ): Promise<GenerationResult> {
    return this.generateForeground((): Promise<GenerationResult> => entry.generateImageChatStream(
      turns,
      image.pixels,
      image.width,
      image.height,
      maxNewTokens,
      settings,
      onChunk
    ))
  }

  reset(): Promise<void> {
    NativeInferenceService.pendingResets++
    const cancelled = this.cancelTitleGeneration()
    const task = NativeInferenceService.modelBarrier.then(() => cancelled).then(() => {
      entry.reset()
    }).finally(() => { NativeInferenceService.pendingResets-- })
    NativeInferenceService.modelBarrier = task.catch(() => {})
    return task
  }

  stopGeneration(): void {
    NativeInferenceService.foregroundStopEpoch++
    if (NativeInferenceService.titleTask !== undefined) entry.cancelTitleGeneration()
    else entry.stopGeneration()
  }

  isLoaded(): boolean {
    return entry.isLoaded() as boolean
  }
}
