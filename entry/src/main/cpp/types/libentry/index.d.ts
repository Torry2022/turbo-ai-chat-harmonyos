export interface ChatTurn {
  role: string;
  content: string;
}

export const loadModel: (configPath: string, threadNum?: number, maxNewTokens?: number) => string;
export const loadModelAsync: (configPath: string, threadNum?: number, maxNewTokens?: number) => Promise<string>;
export const generate: (prompt: string, maxNewTokens?: number) => string;
export const generateAsync: (prompt: string, maxNewTokens?: number) => Promise<string>;
export const generateStream: (prompt: string, maxNewTokens: number, onChunk: (chunk: string) => void) => Promise<string>;
export const generateChatStream: (messages: ChatTurn[], maxNewTokens: number, onChunk: (chunk: string) => void) => Promise<string>;
export const generateImageChatStream: (
  messages: ChatTurn[],
  rgbaPixels: ArrayBuffer,
  width: number,
  height: number,
  maxNewTokens: number,
  onChunk: (chunk: string) => void
) => Promise<string>;
export const reset: () => void;
export const isLoaded: () => boolean;
