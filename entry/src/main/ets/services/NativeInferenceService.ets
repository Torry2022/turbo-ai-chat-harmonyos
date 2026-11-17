import { ModelExecutionService } from './ModelExecutionService'
import entry from 'libentry.so'
import { ChatTurn, GenerationResult, GenerationSettings, ImagePayload, PreparedChatInput } from '../models/ChatTypes'

export interface ModelThreadWidth {
  requested: number
  actual: number
}

export interface NativeModelThreadInfo {
  runtimeLibrarySha256?: string
  maxThreads: number
  chat: ModelThreadWidth
  rerank: ModelThreadWidth
}

// A request keeps prepared image state exclusive until generation has finished.
export class ChatRequestExecution {
  private active: boolean = true
  private running: boolean = false
  private released: boolean = false
  private finish: () => void

  constructor(finish: () => void) { this.finish = finish }

  async run<T>(operation: () => Promise<T>): Promise<T> {
    if (!this.active || this.running) throw new Error('当前模型请求不能执行此操作')
    this.running = true
    try { return await operation() }
    finally {
      this.running = false
      this.finishIfClosed()
    }
  }

  release(): void {
    this.active = false
    this.finishIfClosed()
  }

  private finishIfClosed(): void {
    if (!this.active && !this.running && !this.released) {
      this.released = true
      this.finish()
    }
  }
}

export class NativeInferenceService {
  setDiagnosticLogging(enabled: boolean): boolean {
    return entry.setDiagnosticLogging(enabled)
  }

  modelThreadInfo(): NativeModelThreadInfo {
    return JSON.parse(entry.modelThreadInfo()) as NativeModelThreadInfo
  }
  private static titleTask?: Promise<GenerationResult>
  private static modelBarrier: Promise<void> = Promise.resolve()
  private static pendingResets: number = 0
  private static foregroundStopEpoch: number = 0
  private static foregroundJobs: number = 0

  async beginChatRequest(): Promise<ChatRequestExecution> {
    NativeInferenceService.foregroundJobs++
    try {
      await this.cancelTitleGeneration()
      await NativeInferenceService.modelBarrier
      const release = ModelExecutionService.acquire('chat')
      return new ChatRequestExecution((): void => {
        release()
        NativeInferenceService.foregroundJobs--
      })
    } catch (error) {
      NativeInferenceService.foregroundJobs--
      throw new Error(`${error}`)
    }
  }

  private foreground<T>(operation: () => Promise<T>, request?: ChatRequestExecution): Promise<T> {
    if (request !== undefined) return request.run(operation)
    NativeInferenceService.foregroundJobs++
    const cancelled = this.cancelTitleGeneration()
    const barrier = NativeInferenceService.modelBarrier
    return cancelled.then(() => barrier).then(async (): Promise<T> => {
      const release = ModelExecutionService.acquire('chat')
      try { return await operation() } finally { release() }
    }).finally(() => {
      NativeInferenceService.foregroundJobs--
    })
  }

  private generateForeground(operation: () => Promise<GenerationResult>, request?: ChatRequestExecution): Promise<GenerationResult> {
    const epoch = NativeInferenceService.foregroundStopEpoch
    return this.foreground<GenerationResult>((): Promise<GenerationResult> => {
      if (epoch !== NativeInferenceService.foregroundStopEpoch) {
        const stopped: GenerationResult = { text: '', generatedTokens: 0, stopReason: 'user_stop' }
        return Promise.resolve(stopped)
      }
      return operation()
    }, request)
  }

  generateTitle(turns: ChatTurn[]): Promise<GenerationResult> {
    if (NativeInferenceService.titleTask !== undefined || NativeInferenceService.pendingResets > 0 ||
      NativeInferenceService.foregroundJobs > 0) return Promise.reject(new Error('模型任务尚未结束'))
    const settings: GenerationSettings = {
      temperature: 0.1, topP: 0.8, topK: 1, repetitionPenalty: 1.05,
      frequencyPenalty: 0, presencePenalty: 0, penaltyWindow: 256
    }
    let release: () => void
    try { release = ModelExecutionService.acquire('title') } catch (error) { return Promise.reject(error) }
    let task: Promise<GenerationResult>
    try { task = entry.generateChatStream(turns, 48, settings, (_chunk: string) => {}, true) }
    catch (error) { release(); return Promise.reject(error) }
    NativeInferenceService.titleTask = task
    const clear = (): void => {
      release()
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

  prepareChatInput(turns: ChatTurn[], settings: GenerationSettings, imageInput: boolean, image?: ImagePayload, request?: ChatRequestExecution): Promise<PreparedChatInput> {
    return this.foreground<PreparedChatInput>((): Promise<PreparedChatInput> =>
      entry.prepareChatInput(turns, settings, imageInput, image?.pixels, image?.width, image?.height), request)
  }

  generateText(
    turns: ChatTurn[],
    maxNewTokens: number,
    settings: GenerationSettings,
    onChunk: (chunk: string) => void,
    request?: ChatRequestExecution
  ): Promise<GenerationResult> {
    return this.generateForeground((): Promise<GenerationResult> =>
      entry.generateChatStream(turns, maxNewTokens, settings, onChunk), request)
  }

  generateRawPrompt(
    prompt: string,
    maxNewTokens: number,
    endWith: string,
    settings: GenerationSettings,
    onChunk: (chunk: string) => void,
    request?: ChatRequestExecution
  ): Promise<GenerationResult> {
    return this.generateForeground((): Promise<GenerationResult> =>
      entry.generateRawPromptStream(prompt, maxNewTokens, endWith, settings, onChunk), request)
  }

  generateImage(
    turns: ChatTurn[],
    image: ImagePayload,
    maxNewTokens: number,
    settings: GenerationSettings,
    onChunk: (chunk: string) => void,
    request?: ChatRequestExecution
  ): Promise<GenerationResult> {
    return this.generateForeground((): Promise<GenerationResult> => entry.generateImageChatStream(
      turns,
      image.pixels,
      image.width,
      image.height,
      maxNewTokens,
      settings,
      onChunk
    ), request)
  }

  reset(): Promise<void> {
    NativeInferenceService.pendingResets++
    const cancelled = this.cancelTitleGeneration()
    const task = NativeInferenceService.modelBarrier.then(() => cancelled).then(() => {
      const release = ModelExecutionService.acquire('chat')
      try { entry.reset() } finally { release() }
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
