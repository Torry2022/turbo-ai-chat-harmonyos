export interface ModelProfile {
  id: string
  name: string
  shortName: string
  directoryName: string
  description: string
  supportsImage: boolean
  systemPrompt: string
  source: string
  configPath?: string
  chatFormat?: string
  promptTemplate?: string
  stopSequence?: string
  contextMessageLimit?: number
  templateOverride?: boolean
  catalogItemId?: string
  downloadId?: string
  editable?: boolean
  removable?: boolean
  generationDefaults?: GenerationDefaults
}

export interface GenerationDefaults {
  maxNewTokens?: number
  temperature?: number
  topP?: number
  topK?: number
  repetitionPenalty?: number
  frequencyPenalty?: number
  presencePenalty?: number
  penaltyWindow?: number
}

export const CHAT_FORMAT_MNN_AUTO: string = 'mnn-auto'
export const MAX_GENERATION_TOKENS: number = 2048
export const DEFAULT_MAX_NEW_TOKENS: number = 512
export const DEFAULT_THREAD_NUM: number = 6
export const DEFAULT_TEMPERATURE: number = 0.6
export const DEFAULT_TOP_P: number = 0.9
export const DEFAULT_TOP_K: number = 40
export const DEFAULT_REPETITION_PENALTY: number = 1.05
export const DEFAULT_FREQUENCY_PENALTY: number = 0.0
export const DEFAULT_PRESENCE_PENALTY: number = 0.0
export const DEFAULT_PENALTY_WINDOW: number = 256
export const DEFAULT_MODEL_ID: string = 'qwen3-4b-instruct'

export const MODEL_PROFILES: ModelProfile[] = [
  {
    id: 'qwen3-4b-instruct',
    name: 'Qwen3-4B-Instruct',
    shortName: 'Qwen3-4B-Instruct',
    directoryName: 'Qwen3-4B-Instruct-2507-MNN',
    description: '通用中文文本模型，适合作为默认本地对话。',
    supportsImage: false,
    systemPrompt: '你是运行在本地设备上的 Qwen3-4B-Instruct。请始终使用简体中文回答，表达简洁清楚。',
    source: 'builtin',
    chatFormat: CHAT_FORMAT_MNN_AUTO,
    contextMessageLimit: 6,
    generationDefaults: {
      temperature: 0.7,
      topP: 0.8,
      topK: 20,
      repetitionPenalty: 1.05,
      frequencyPenalty: 0.0,
      presencePenalty: 0.0,
      penaltyWindow: 256
    },
    catalogItemId: 'qwen3-4b-instruct',
    downloadId: 'qwen3-4b-instruct',
    editable: false,
    removable: false
  },
  {
    id: 'minicpm5-1b',
    name: 'MiniCPM5-1B',
    shortName: 'MiniCPM5-1B',
    directoryName: 'MiniCPM5-1B-MNN',
    description: '超小参数文本模型，适合轻量本地对话与快速验证。',
    supportsImage: false,
    systemPrompt: '你是运行在本地设备上的 MiniCPM5-1B。请始终使用简体中文回答，表达简洁清楚。',
    source: 'builtin',
    chatFormat: CHAT_FORMAT_MNN_AUTO,
    contextMessageLimit: 0,
    generationDefaults: {
      temperature: 0.6,
      topP: 0.9,
      topK: 40,
      repetitionPenalty: 1.05,
      frequencyPenalty: 0.0,
      presencePenalty: 0.0,
      penaltyWindow: 256
    },
    catalogItemId: 'minicpm5-1b',
    downloadId: 'minicpm5-1b',
    editable: false,
    removable: false
  },
  {
    id: 'qwen3-0.6b',
    name: 'Qwen3-0.6B',
    shortName: 'Qwen3-0.6B',
    directoryName: 'Qwen3-0.6B-MNN',
    description: '超轻量 Qwen3 文本模型，适合快速响应和低存储占用。',
    supportsImage: false,
    systemPrompt: '你是运行在本地设备上的 Qwen3-0.6B。请始终使用简体中文回答，表达简洁清楚。',
    source: 'builtin',
    chatFormat: CHAT_FORMAT_MNN_AUTO,
    contextMessageLimit: 6,
    generationDefaults: {
      temperature: 0.7,
      topP: 0.8,
      topK: 20,
      repetitionPenalty: 1.05,
      frequencyPenalty: 0.0,
      presencePenalty: 0.0,
      penaltyWindow: 256
    },
    catalogItemId: 'qwen3-0.6b',
    downloadId: 'qwen3-0.6b',
    editable: false,
    removable: false
  },
  {
    id: 'qwen3-1.7b',
    name: 'Qwen3-1.7B',
    shortName: 'Qwen3-1.7B',
    directoryName: 'Qwen3-1.7B-MNN',
    description: '轻量 Qwen3 文本模型，兼顾速度、效果和占用。',
    supportsImage: false,
    systemPrompt: '你是运行在本地设备上的 Qwen3-1.7B。请始终使用简体中文回答，表达简洁清楚。',
    source: 'builtin',
    chatFormat: CHAT_FORMAT_MNN_AUTO,
    contextMessageLimit: 6,
    generationDefaults: {
      temperature: 0.7,
      topP: 0.8,
      topK: 20,
      repetitionPenalty: 1.05,
      frequencyPenalty: 0.0,
      presencePenalty: 0.0,
      penaltyWindow: 256
    },
    catalogItemId: 'qwen3-1.7b',
    downloadId: 'qwen3-1.7b',
    editable: false,
    removable: false
  },
  {
    id: 'qwen2.5-1.5b-instruct',
    name: 'Qwen2.5-1.5B-Instruct',
    shortName: 'Qwen2.5-1.5B',
    directoryName: 'Qwen2.5-1.5B-Instruct-MNN',
    description: '低内存 Qwen2.5 指令模型，适合常规文本对话。',
    supportsImage: false,
    systemPrompt: '你是运行在本地设备上的 Qwen2.5-1.5B-Instruct。请始终使用简体中文回答，表达简洁清楚。',
    source: 'builtin',
    chatFormat: CHAT_FORMAT_MNN_AUTO,
    contextMessageLimit: 6,
    generationDefaults: {
      temperature: 0.6,
      topP: 0.9,
      topK: 40,
      repetitionPenalty: 1.05,
      frequencyPenalty: 0.0,
      presencePenalty: 0.0,
      penaltyWindow: 256
    },
    catalogItemId: 'qwen2.5-1.5b-instruct',
    downloadId: 'qwen2.5-1.5b-instruct',
    editable: false,
    removable: false
  },
  {
    id: 'qwen2.5-3b-instruct',
    name: 'Qwen2.5-3B-Instruct',
    shortName: 'Qwen2.5-3B',
    directoryName: 'Qwen2.5-3B-Instruct-MNN',
    description: '中档 Qwen2.5 指令模型，适合对话、摘要和轻量写作。',
    supportsImage: false,
    systemPrompt: '你是运行在本地设备上的 Qwen2.5-3B-Instruct。请始终使用简体中文回答，表达简洁清楚。',
    source: 'builtin',
    chatFormat: CHAT_FORMAT_MNN_AUTO,
    contextMessageLimit: 6,
    generationDefaults: {
      temperature: 0.6,
      topP: 0.9,
      topK: 40,
      repetitionPenalty: 1.05,
      frequencyPenalty: 0.0,
      presencePenalty: 0.0,
      penaltyWindow: 256
    },
    catalogItemId: 'qwen2.5-3b-instruct',
    downloadId: 'qwen2.5-3b-instruct',
    editable: false,
    removable: false
  },
  {
    id: 'qwen3-8b',
    name: 'Qwen3-8B',
    shortName: 'Qwen3-8B',
    directoryName: 'Qwen3-8B-MNN',
    description: '较大参数 Qwen3 文本模型，适合大内存设备尝试。',
    supportsImage: false,
    systemPrompt: '你是运行在本地设备上的 Qwen3-8B。请始终使用简体中文回答，表达简洁清楚。',
    source: 'builtin',
    chatFormat: CHAT_FORMAT_MNN_AUTO,
    contextMessageLimit: 6,
    generationDefaults: {
      temperature: 0.7,
      topP: 0.8,
      topK: 20,
      repetitionPenalty: 1.05,
      frequencyPenalty: 0.0,
      presencePenalty: 0.0,
      penaltyWindow: 256
    },
    catalogItemId: 'qwen3-8b',
    downloadId: 'qwen3-8b',
    editable: false,
    removable: false
  },
  {
    id: 'gemma4',
    name: 'Gemma-4-E2B-it',
    shortName: 'Gemma-4-E2B',
    directoryName: 'gemma-4-E2B-it-MNN',
    description: '图片理解实验模型，支持文本和图片输入。',
    supportsImage: true,
    systemPrompt: '你是运行在本地设备上的 Gemma 4。请始终使用简体中文回答，表达简洁清楚，并在回答结尾使用与回答语言匹配的句末标点。优先用一小段话直接回答，除非用户明确要求，不要分条列举、不要重复同一句话。用户提供图片时，请结合图片内容回答；如果用户要求提取文字，请尽量逐行转写图片中的可见文字。',
    source: 'builtin',
    chatFormat: CHAT_FORMAT_MNN_AUTO,
    contextMessageLimit: 6,
    generationDefaults: {
      temperature: 1.0,
      topP: 0.95,
      topK: 64,
      repetitionPenalty: 1.0,
      frequencyPenalty: 0.0,
      presencePenalty: 0.0,
      penaltyWindow: 0
    },
    catalogItemId: 'gemma4',
    downloadId: 'gemma4',
    editable: false,
    removable: false
  }
]
