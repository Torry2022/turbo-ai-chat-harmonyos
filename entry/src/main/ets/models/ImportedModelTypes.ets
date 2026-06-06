import { ModelProfile } from './ModelProfile';

export interface ImportedModelManifest {
  models: ModelProfile[];
}

export interface ImportedModelDraft {
  name: string;
  shortName: string;
  supportsImage: boolean;
  systemPrompt: string;
  chatFormat: string;
  promptTemplate: string;
  stopSequence: string;
}

export interface ModelImportResult {
  profile: ModelProfile;
  message: string;
}

export const IMPORTED_MODELS_DIR: string = 'model-imports';
export const IMPORTED_MODELS_STORE_FILE: string = 'imported-models.json';
export const IMPORTED_MODEL_SOURCE: string = 'imported';
export const LEGACY_IMPORTED_MODEL_PROMPT: string = '你是运行在本地设备上的模型。请始终使用简体中文回答，表达简洁清楚。';
export const DEFAULT_IMPORTED_MODEL_PROMPT: string = '你是本地 AI 助手。请始终使用简体中文回答，表达简洁清楚；只回答用户最新问题；不要编造具体年份、型号、版本或来源；遇到不确定的事实请直接说明不确定；不要把专有名词按字面拆解翻译；不要重复同一句话。';
