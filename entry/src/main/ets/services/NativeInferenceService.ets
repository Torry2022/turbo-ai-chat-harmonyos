import entry from 'libentry.so'
import { ChatTurn, GenerationResult, GenerationSettings, ImagePayload } from '../models/ChatTypes'

export class NativeInferenceService {
  loadModel(configPath: string, threadNum: number, maxNewTokens: number, settings: GenerationSettings): Promise<boolean> {
    return entry.loadModelAsync(configPath, threadNum, maxNewTokens, settings).then((_result: string) => {
      return entry.isLoaded() as boolean
    })
  }

  generateText(
    turns: ChatTurn[],
    maxNewTokens: number,
    settings: GenerationSettings,
    onChunk: (chunk: string) => void
  ): Promise<GenerationResult> {
    return entry.generateChatStream(turns, maxNewTokens, settings, onChunk)
  }

  generateRawPrompt(
    prompt: string,
    maxNewTokens: number,
    endWith: string,
    settings: GenerationSettings,
    onChunk: (chunk: string) => void
  ): Promise<GenerationResult> {
    return entry.generateRawPromptStream(prompt, maxNewTokens, endWith, settings, onChunk)
  }

  generateImage(
    turns: ChatTurn[],
    image: ImagePayload,
    maxNewTokens: number,
    settings: GenerationSettings,
    onChunk: (chunk: string) => void
  ): Promise<GenerationResult> {
    return entry.generateImageChatStream(
      turns,
      image.pixels,
      image.width,
      image.height,
      maxNewTokens,
      settings,
      onChunk
    )
  }

  reset(): void {
    entry.reset()
  }

  isLoaded(): boolean {
    return entry.isLoaded() as boolean
  }
}
