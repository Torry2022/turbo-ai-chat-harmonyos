import { GenerationConfiguration, GenerationEnvironment, GenerationModelIdentity, GenerationSettings } from '../models/ChatTypes'

export function captureGenerationConfiguration(maxNewTokens: number, settings: GenerationSettings,
  model?: GenerationModelIdentity, environment?: GenerationEnvironment, startedAt: number = Date.now()): GenerationConfiguration {
  return {
    maxNewTokens, startedAt,
    settings: { temperature: settings.temperature, topP: settings.topP, topK: settings.topK,
      repetitionPenalty: settings.repetitionPenalty, frequencyPenalty: settings.frequencyPenalty,
      presencePenalty: settings.presencePenalty, penaltyWindow: settings.penaltyWindow,
      thinkingEnabled: settings.thinkingEnabled },
    model: model === undefined ? undefined : { id: model.id, name: model.name,
        sourceRepository: model.sourceRepository, sourceRevision: model.sourceRevision,
      requestedThreads: model.requestedThreads, actualThreads: model.actualThreads,
      runtimeLibrarySha256: model.runtimeLibrarySha256, configurationSha256: model.configurationSha256, fileManifestSha256: model.fileManifestSha256 },
    environment: environment === undefined ? undefined : { appVersion: environment.appVersion,
      appVersionCode: environment.appVersionCode, deviceModel: environment.deviceModel, osVersion: environment.osVersion }
  }
}
