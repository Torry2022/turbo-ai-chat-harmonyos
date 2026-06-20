import {
  DEFAULT_MODEL_ID,
  MODEL_PROFILES,
  ModelProfile
} from '../models/ModelProfile'

export class ModelManager {
  selectedModelId: string = DEFAULT_MODEL_ID
  modelPath: string = ''
  private importedProfiles: ModelProfile[] = []
  private modelOrder: string[] = []

  profiles(): ModelProfile[] {
    const allProfiles = MODEL_PROFILES.concat(this.importedProfiles)
    if (this.modelOrder.length <= 0) {
      return allProfiles
    }
    const orderedProfiles: ModelProfile[] = []
    for (let orderIndex = 0; orderIndex < this.modelOrder.length; orderIndex++) {
      const profile = this.findProfileInList(allProfiles, this.modelOrder[orderIndex])
      if (profile !== undefined) {
        orderedProfiles.push(profile)
      }
    }
    for (let index = 0; index < allProfiles.length; index++) {
      if (!this.containsProfileId(orderedProfiles, allProfiles[index].id)) {
        orderedProfiles.push(allProfiles[index])
      }
    }
    return orderedProfiles
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

  setModelOrder(order: string[], filesDir: string): void {
    this.modelOrder = order
    this.modelPath = this.defaultConfigPath(filesDir, this.currentModel())
  }

  modelOrderIds(): string[] {
    return this.profiles().map((profile: ModelProfile) => profile.id)
  }

  moveProfile(modelId: string, targetIndex: number, filesDir: string): boolean {
    const profiles = this.profiles()
    const currentIndex = profiles.findIndex((profile: ModelProfile) => profile.id === modelId)
    if (currentIndex < 0) {
      return false
    }
    const nextIndex = Math.max(0, Math.min(profiles.length - 1, Math.round(targetIndex)))
    if (nextIndex === currentIndex) {
      return false
    }
    const nextIds = profiles.map((profile: ModelProfile) => profile.id)
    const moved = nextIds.splice(currentIndex, 1)[0]
    nextIds.splice(nextIndex, 0, moved)
    this.modelOrder = nextIds
    this.modelPath = this.defaultConfigPath(filesDir, this.currentModel())
    return true
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

  private findProfileInList(profiles: ModelProfile[], modelId: string): ModelProfile | undefined {
    for (let index = 0; index < profiles.length; index++) {
      if (profiles[index].id === modelId) {
        return profiles[index]
      }
    }
    return undefined
  }

  private containsProfileId(profiles: ModelProfile[], modelId: string): boolean {
    for (let index = 0; index < profiles.length; index++) {
      if (profiles[index].id === modelId) {
        return true
      }
    }
    return false
  }
}
