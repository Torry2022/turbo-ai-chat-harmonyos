import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit'
import { BusinessError } from '@kit.BasicServicesKit'
import { speechRecognizer } from '@kit.CoreSpeechKit'

export interface SpeechRecognitionCallbacks {
  onStarted: () => void
  onSpeechActivity: (active: boolean) => void
  onTranscript: (text: string) => void
  onCompleted: () => void
  onError: (message: string) => void
}

export class SpeechRecognitionService {
  private engine?: speechRecognizer.SpeechRecognitionEngine
  private callbacks?: SpeechRecognitionCallbacks
  private sessionId: string = ''
  private committedTranscript: string = ''
  private partialTranscript: string = ''
  private startSequence: number = 0

  async start(
    context: common.UIAbilityContext,
    callbacks: SpeechRecognitionCallbacks
  ): Promise<void> {
    if (this.sessionId.length > 0) {
      throw new Error('已有语音识别任务正在运行')
    }
    const startSequence = ++this.startSequence
    const granted = await this.requestMicrophonePermission(context)
    if (startSequence !== this.startSequence) {
      return
    }
    if (!granted) {
      throw new Error('需要麦克风权限才能使用语音输入')
    }

    const engine = await this.ensureEngine()
    if (startSequence !== this.startSequence) {
      return
    }
    this.callbacks = callbacks
    this.sessionId = `voice_${Date.now()}`
    this.committedTranscript = ''
    this.partialTranscript = ''
    engine.setListener(this.createListener())

    const recognizerOption: Record<string, Object> = {
      'enablePartialResult': true
    }
    const extraParams: Record<string, Object> = {
      'recognitionMode': 0,
      'vadBegin': 10000,
      'vadEnd': 1800,
      'maxAudioDuration': 60000,
      'recognizerOption': recognizerOption
    }
    const startParams: speechRecognizer.StartParams = {
      sessionId: this.sessionId,
      audioInfo: {
        audioType: 'pcm',
        sampleRate: 16000,
        soundChannel: 1,
        sampleBit: 16
      },
      extraParams
    }
    try {
      engine.startListening(startParams)
    } catch (err) {
      this.resetSession()
      throw new Error(this.describeError('启动语音识别失败', err as BusinessError))
    }
  }

  finish(): void {
    if (this.engine === undefined || this.sessionId.length === 0) {
      return
    }
    try {
      this.engine.finish(this.sessionId)
    } catch (err) {
      throw new Error(this.describeError('停止语音识别失败', err as BusinessError))
    }
  }

  cancel(): void {
    this.startSequence++
    if (this.engine !== undefined && this.sessionId.length > 0) {
      try {
        this.engine.cancel(this.sessionId)
      } catch (_) {
      }
    }
    this.resetSession()
  }

  shutdown(): void {
    this.cancel()
    if (this.engine !== undefined) {
      try {
        this.engine.shutdown()
      } catch (_) {
      }
      this.engine = undefined
    }
  }

  private async requestMicrophonePermission(context: common.UIAbilityContext): Promise<boolean> {
    const permission: Permissions = 'ohos.permission.MICROPHONE'
    try {
      const result = await abilityAccessCtrl.createAtManager().requestPermissionsFromUser(context, [permission])
      return result.authResults.length > 0 && result.authResults[0] === 0
    } catch (err) {
      throw new Error(this.describeError('申请麦克风权限失败', err as BusinessError))
    }
  }

  private async ensureEngine(): Promise<speechRecognizer.SpeechRecognitionEngine> {
    if (this.engine !== undefined) {
      return this.engine
    }
    const extraParams: Record<string, Object> = {
      'locate': 'CN',
      'recognizerMode': 'short'
    }
    const createParams: speechRecognizer.CreateEngineParams = {
      language: 'zh-CN',
      online: 1,
      extraParams
    }
    try {
      this.engine = await speechRecognizer.createEngine(createParams)
      return this.engine
    } catch (err) {
      throw new Error(this.describeError('初始化语音识别失败', err as BusinessError))
    }
  }

  private createListener(): speechRecognizer.RecognitionListener {
    const service = this
    return {
      onStart(sessionId: string, _eventMessage: string): void {
        if (!service.isCurrentSession(sessionId)) {
          return
        }
        service.callbacks?.onStarted()
      },
      onEvent(sessionId: string, eventCode: number, _eventMessage: string): void {
        if (!service.isCurrentSession(sessionId)) {
          return
        }
        if (eventCode === 1) {
          service.callbacks?.onSpeechActivity(true)
        } else if (eventCode === 3) {
          service.callbacks?.onSpeechActivity(false)
        }
      },
      onResult(sessionId: string, result: speechRecognizer.SpeechRecognitionResult): void {
        if (!service.isCurrentSession(sessionId)) {
          return
        }
        if (result.isFinal) {
          service.committedTranscript += result.result
          service.partialTranscript = ''
        } else {
          service.partialTranscript = result.result
        }
        service.callbacks?.onTranscript(service.committedTranscript + service.partialTranscript)
      },
      onComplete(sessionId: string, _eventMessage: string): void {
        if (!service.isCurrentSession(sessionId)) {
          return
        }
        const callbacks = service.callbacks
        service.resetSession()
        callbacks?.onCompleted()
      },
      onError(sessionId: string, errorCode: number, errorMessage: string): void {
        if (!service.isCurrentSession(sessionId)) {
          return
        }
        const callbacks = service.callbacks
        service.resetSession()
        callbacks?.onError(`错误码 ${errorCode}：${errorMessage}`)
      }
    }
  }

  private isCurrentSession(sessionId: string): boolean {
    return this.sessionId.length > 0 && this.sessionId === sessionId
  }

  private resetSession(): void {
    this.callbacks = undefined
    this.sessionId = ''
    this.committedTranscript = ''
    this.partialTranscript = ''
  }

  private describeError(prefix: string, error: BusinessError): string {
    if (error.message.length <= 0) {
      return prefix
    }
    return `${prefix}：${error.message}`
  }
}
