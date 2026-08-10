// Derived from Turbo1123/turbo-ai-chat-harmonyos and subsequently modified.
// See README.md and Git history for provenance and change details.

export interface ChatTurn {
  role: string;
  content: string;
}

export type GenerationStopReason = 'eos' | 'max_tokens' | 'user_stop' | 'timeout' | 'internal_error' | 'unknown';

export interface GenerationResult {
  text: string;
  generatedTokens: number;
  stopReason: GenerationStopReason;
}

export interface GenerationSettings {
  temperature: number;
  topP: number;
  topK: number;
  repetitionPenalty: number;
}

export const loadModel: (configPath: string, threadNum?: number, maxNewTokens?: number, settings?: GenerationSettings) => string;
export const loadModelAsync: (configPath: string, threadNum?: number, maxNewTokens?: number, settings?: GenerationSettings) => Promise<string>;
export const generate: (prompt: string, maxNewTokens?: number, settings?: GenerationSettings) => string;
export const generateAsync: (prompt: string, maxNewTokens?: number, settings?: GenerationSettings) => Promise<string>;
export const generateStream: (
  prompt: string,
  maxNewTokens: number,
  settings: GenerationSettings,
  onChunk: (chunk: string) => void
) => Promise<GenerationResult>;
export const generateRawPromptStream: (
  prompt: string,
  maxNewTokens: number,
  endWith: string,
  settings: GenerationSettings,
  onChunk: (chunk: string) => void
) => Promise<GenerationResult>;
export const generateChatStream: (
  messages: ChatTurn[],
  maxNewTokens: number,
  settings: GenerationSettings,
  onChunk: (chunk: string) => void
) => Promise<GenerationResult>;
export const generateImageChatStream: (
  messages: ChatTurn[],
  rgbaPixels: ArrayBuffer,
  width: number,
  height: number,
  maxNewTokens: number,
  settings: GenerationSettings,
  onChunk: (chunk: string) => void
) => Promise<GenerationResult>;
export const stopGeneration: () => void;
export const reset: () => void;
export const isLoaded: () => boolean;
