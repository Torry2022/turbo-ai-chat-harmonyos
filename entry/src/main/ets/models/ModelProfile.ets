export interface ModelProfile {
  id: string;
  name: string;
  shortName: string;
  directoryName: string;
  description: string;
  supportsImage: boolean;
  systemPrompt: string;
  source: string;
  configPath?: string;
  chatFormat?: string;
  promptTemplate?: string;
  stopSequence?: string;
  contextMessageLimit?: number;
  templateOverride?: boolean;
  downloadId?: string;
  editable?: boolean;
  removable?: boolean;
}

export const CHAT_FORMAT_MNN_AUTO: string = 'mnn-auto';
export const CHAT_FORMAT_RAW_TEMPLATE: string = 'raw-template';
export const CHAT_FORMAT_QWEN_IM: string = 'qwen-im';
export const CHAT_FORMAT_GEMMA_TURN: string = 'gemma-turn';
export const CHAT_FORMAT_MINICPM_THINKING: string = 'minicpm-thinking';
export const MAX_GENERATION_TOKENS: number = 2048;
export const DEFAULT_MAX_NEW_TOKENS: number = 512;
export const DEFAULT_THREAD_NUM: number = 6;
export const DEFAULT_TEMPERATURE: number = 0.6;
export const DEFAULT_TOP_P: number = 0.9;
export const DEFAULT_TOP_K: number = 40;
export const DEFAULT_REPETITION_PENALTY: number = 1.05;
export const DEFAULT_MODEL_ID: string = 'gemma4';

export const MODEL_PROFILES: ModelProfile[] = [
  {
    id: 'gemma4',
    name: 'Gemma 4 E2B',
    shortName: 'Gemma 4 E2B',
    directoryName: 'gemma-4-E2B-it-MNN',
    description: '多模态模型，支持文本和图片输入。',
    supportsImage: true,
    systemPrompt: '你是运行在本地设备上的 Gemma 4。请始终使用简体中文回答，表达简洁清楚。用户提供图片时，请结合图片内容回答；如果用户要求提取文字，请尽量逐行转写图片中的可见文字。',
    source: 'builtin',
    chatFormat: CHAT_FORMAT_GEMMA_TURN,
    stopSequence: '<turn|>',
    contextMessageLimit: 6,
    downloadId: 'gemma4',
    editable: false,
    removable: false
  },
  {
    id: 'minicpm5-1b',
    name: 'MiniCPM5-1B',
    shortName: 'MiniCPM5-1B',
    directoryName: 'MiniCPM5-1B-MNN',
    description: '轻量文本模型，适合快速本地对话。',
    supportsImage: false,
    systemPrompt: '你是运行在本地设备上的 MiniCPM5-1B。请始终使用简体中文回答，表达简洁清楚。',
    source: 'builtin',
    chatFormat: CHAT_FORMAT_MINICPM_THINKING,
    stopSequence: '</s>',
    contextMessageLimit: 0,
    downloadId: 'minicpm5-1b',
    editable: false,
    removable: false
  }
];
