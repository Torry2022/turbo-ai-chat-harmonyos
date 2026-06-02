export interface ModelProfile {
  id: string;
  name: string;
  shortName: string;
  directoryName: string;
  description: string;
  supportsImage: boolean;
  systemPrompt: string;
}

export const MAX_GENERATION_TOKENS: number = 512;
export const DEFAULT_MAX_NEW_TOKENS: number = 256;
export const DEFAULT_THREAD_NUM: number = 6;
export const DEFAULT_MODEL_ID: string = 'gemma4';

export const MODEL_PROFILES: ModelProfile[] = [
  {
    id: 'gemma4',
    name: 'Gemma 4 E2B',
    shortName: 'Gemma 4',
    directoryName: 'gemma-4-E2B-it-MNN',
    description: '多模态 MNN 模型，支持文本和图片输入。',
    supportsImage: true,
    systemPrompt: '你是运行在鸿蒙 NEXT 本地设备上的 Gemma 4。请始终使用简体中文回答，表达简洁清楚。用户提供图片时，请结合图片内容回答；如果用户要求提取文字，请尽量逐行转写图片中的可见文字。'
  },
  {
    id: 'minicpm5-1b',
    name: 'MiniCPM5-1B',
    shortName: 'MiniCPM5',
    directoryName: 'MiniCPM5-1B-MNN',
    description: '轻量文本 MNN 模型，适合快速本地对话。',
    supportsImage: false,
    systemPrompt: '你是运行在鸿蒙 NEXT 本地设备上的 MiniCPM5-1B。请始终使用简体中文回答，表达简洁清楚。'
  }
];
