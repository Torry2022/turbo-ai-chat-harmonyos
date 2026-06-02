import {
  DEFAULT_MODEL_ID,
  MODEL_PROFILES,
  ModelProfile
} from '../models/ModelProfile';

export class ModelManager {
  selectedModelId: string = DEFAULT_MODEL_ID;
  modelPath: string = '';

  profiles(): ModelProfile[] {
    return MODEL_PROFILES;
  }

  currentModel(): ModelProfile {
    const fallback = MODEL_PROFILES[0];
    for (let index = 0; index < MODEL_PROFILES.length; index++) {
      if (MODEL_PROFILES[index].id === this.selectedModelId) {
        return MODEL_PROFILES[index];
      }
    }
    return fallback;
  }

  defaultConfigPath(filesDir: string, model: ModelProfile): string {
    return `${filesDir}/${model.directoryName}/config.json`;
  }

  initialize(filesDir: string): void {
    this.modelPath = this.defaultConfigPath(filesDir, this.currentModel());
  }

  switchModel(modelId: string, filesDir: string): ModelProfile {
    this.selectedModelId = modelId;
    const model = this.currentModel();
    this.modelPath = this.defaultConfigPath(filesDir, model);
    return model;
  }

  updateModelPath(value: string): boolean {
    if (this.modelPath === value) {
      return false;
    }
    this.modelPath = value;
    return true;
  }
}
