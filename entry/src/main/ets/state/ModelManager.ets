import {
  DEFAULT_MODEL_ID,
  MODEL_PROFILES,
  ModelProfile
} from '../models/ModelProfile'

export class ModelManager {
  selectedModelId: string = DEFAULT_MODEL_ID
  modelPath: string = ''
  private importedProfiles: ModelProfile[] = []

  profiles(): ModelProfile[] {
    return MODEL_PROFILES.concat(this.importedProfiles)
  }

  currentModel(): ModelProfile {
    const fallback = MODEL_PROFILES[0]
    const profiles = this.profiles()
    for (let index = 0; index < profiles.length; index++) {
      if (profiles[index].id === this.selectedModelId) {
        return profiles[index]
      }
    }
    return fallback
  }

  defaultConfigPath(filesDir: string, model: ModelProfile): string {
    if (model.configPath !== undefined && model.configPath.length > 0) {
      return model.configPath
    }
    return `${filesDir}/${model.directoryName}/config.json`
  }

  initialize(filesDir: string, importedProfiles: ModelProfile[] = []): void {
    this.importedProfiles = importedProfiles
    this.modelPath = this.defaultConfigPath(filesDir, this.currentModel())
  }

  updateImportedProfiles(importedProfiles: ModelProfile[], filesDir: string): void {
    this.importedProfiles = importedProfiles
    const current = this.currentModel()
    if (current.id !== this.selectedModelId) {
      this.selectedModelId = DEFAULT_MODEL_ID
    }
    this.modelPath = this.defaultConfigPath(filesDir, this.currentModel())
  }

  addImportedProfile(profile: ModelProfile, filesDir: string): void {
    this.importedProfiles = this.importedProfiles.concat([profile])
    this.selectedModelId = profile.id
    this.modelPath = this.defaultConfigPath(filesDir, profile)
  }

  switchModel(modelId: string, filesDir: string): ModelProfile {
    this.selectedModelId = modelId
    const model = this.currentModel()
    this.modelPath = this.defaultConfigPath(filesDir, model)
    return model
  }

  updateModelPath(value: string): boolean {
    if (this.modelPath === value) {
      return false
    }
    this.modelPath = value
    return true
  }
}
