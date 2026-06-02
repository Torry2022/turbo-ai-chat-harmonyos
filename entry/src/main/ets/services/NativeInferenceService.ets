import entry from 'libentry.so';
import { ChatTurn, ImagePayload } from '../models/ChatTypes';

export class NativeInferenceService {
  loadModel(configPath: string, threadNum: number, maxNewTokens: number): Promise<boolean> {
    return entry.loadModelAsync(configPath, threadNum, maxNewTokens).then((_result: string) => {
      return entry.isLoaded() as boolean;
    });
  }

  generateText(turns: ChatTurn[], maxNewTokens: number, onChunk: (chunk: string) => void): Promise<string> {
    return entry.generateChatStream(turns, maxNewTokens, onChunk);
  }

  generateImage(
    turns: ChatTurn[],
    image: ImagePayload,
    maxNewTokens: number,
    onChunk: (chunk: string) => void
  ): Promise<string> {
    return entry.generateImageChatStream(
      turns,
      image.pixels,
      image.width,
      image.height,
      maxNewTokens,
      onChunk
    );
  }

  reset(): void {
    entry.reset();
  }

  isLoaded(): boolean {
    return entry.isLoaded() as boolean;
  }
}
