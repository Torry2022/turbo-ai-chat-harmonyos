export interface ChatMessage {
  id: number;
  role: string;
  content: string;
  imageUri: string;
  time: string;
  includeInContext: boolean;
  thinkingExpanded: boolean;
}

export interface ChatTurn {
  role: string;
  content: string;
}

export interface ImagePayload {
  pixels: ArrayBuffer;
  width: number;
  height: number;
}

export interface GenerationResult {
  text: string;
  generatedTokens: number;
  stopReason: string;
}

export interface GenerationSettings {
  temperature: number;
  topP: number;
  topK: number;
  repetitionPenalty: number;
  frequencyPenalty: number;
  presencePenalty: number;
  penaltyWindow: number;
}

export const CONTEXT_MESSAGE_LIMIT: number = 6;
export const VISION_MAX_PIXELS: number = 640000;
