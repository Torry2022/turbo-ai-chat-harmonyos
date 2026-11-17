import { ChatMessage, PerfMetrics } from '../models/ChatTypes'

export interface RunDetailRow {
  label: string
  value: string
}

function numberText(value: number | undefined, suffix: string = ''): string {
  return value !== undefined && Number.isFinite(value) ? `${Math.round(value * 100) / 100}${suffix}` : '未记录'
}

export function generationDetailRows(message: ChatMessage): RunDetailRow[] {
  const metrics = message.perfMetrics
  const config = metrics?.configuration
  const settings = config?.settings
  const model = config?.model
  const rows: RunDetailRow[] = [
    { label: '模型', value: model?.name ?? message.modelName ?? '未记录' },
    { label: '首段等待', value: numberText(metrics?.ttft, ' ms') },
    { label: '输入 Token', value: numberText(metrics?.inputTokens) },
    { label: '复用 Token', value: numberText(metrics?.reusedInputTokens) },
    { label: '输出 Token', value: `${metrics?.tokensEstimated ? '约 ' : ''}${numberText(metrics?.tokens)}` },
    { label: '预填充', value: numberText(metrics?.nativeTiming?.prefillMs, ' ms') },
    { label: '解码阶段', value: numberText(metrics?.nativeTiming?.decodeMs, ' ms') },
    { label: '视觉处理', value: numberText(metrics?.nativeTiming?.visionMs, ' ms') }
  ]
  if (config === undefined) {
    rows.push({ label: '生成配置', value: '此条历史回答未保存' })
    return rows
  }
  return rows.concat([
    { label: '应用版本', value: config.environment?.appVersion ?? '未记录' },
    { label: '总耗时', value: config.finishedAt !== undefined && config.startedAt !== undefined ?
      numberText(config.finishedAt - config.startedAt, ' ms') : '未记录' },
    { label: '请求线程', value: numberText(model?.requestedThreads) },
    { label: '实际线程', value: numberText(model?.actualThreads) },
    { label: '最大输出 Token', value: numberText(config?.maxNewTokens) },
    { label: '深度思考', value: settings === undefined ? '未记录' : settings.thinkingEnabled === undefined ? '模型默认' :
      (settings.thinkingEnabled ? '开启' : '关闭') },
    { label: 'Temperature', value: numberText(settings?.temperature) },
    { label: 'Top-P', value: numberText(settings?.topP) },
    { label: 'Top-K', value: numberText(settings?.topK) },
    { label: '重复惩罚', value: numberText(settings?.repetitionPenalty) },
    { label: '频率惩罚', value: numberText(settings?.frequencyPenalty) },
    { label: '存在惩罚', value: numberText(settings?.presencePenalty) },
    { label: '惩罚窗口', value: numberText(settings?.penaltyWindow) }
  ])
}

// Export only approved numeric/configuration fields. Never serialize the message or settings wholesale.
export function generationDetailsJson(message: ChatMessage): string {
  const source = message.perfMetrics
  const config = source?.configuration
  const settings = config?.settings
  const model = config?.model
  const metrics: PerfMetrics | undefined = source === undefined ? undefined : {
    ttft: source.ttft, tpot: source.tpot, tokensPerSec: source.tokensPerSec, tokens: source.tokens,
    tokensEstimated: source.tokensEstimated, inputTokens: source.inputTokens,
    reusedInputTokens: source.reusedInputTokens, nativeTiming: source.nativeTiming === undefined ? undefined : {
      prefillMs: source.nativeTiming.prefillMs, decodeMs: source.nativeTiming.decodeMs,
      visionMs: source.nativeTiming.visionMs },
    configuration: config === undefined ? undefined : {
      environment: config.environment === undefined ? undefined : {
        appVersion: config.environment.appVersion, appVersionCode: config.environment.appVersionCode,
        deviceModel: config.environment.deviceModel, osVersion: config.environment.osVersion },
      maxNewTokens: config.maxNewTokens, startedAt: config.startedAt, finishedAt: config.finishedAt,
      model: model === undefined ? undefined : { id: model.id, name: model.name,
        sourceRepository: model.sourceRepository, sourceRevision: model.sourceRevision,
        requestedThreads: model.requestedThreads, actualThreads: model.actualThreads,
        runtimeLibrarySha256: model.runtimeLibrarySha256, configurationSha256: model.configurationSha256, fileManifestSha256: model.fileManifestSha256 },
      settings: { temperature: settings!.temperature, topP: settings!.topP, topK: settings!.topK,
        repetitionPenalty: settings!.repetitionPenalty, frequencyPenalty: settings!.frequencyPenalty,
        presencePenalty: settings!.presencePenalty, penaltyWindow: settings!.penaltyWindow,
        thinkingEnabled: settings!.thinkingEnabled }
    }
  }
  return JSON.stringify({ version: 1, stopReason: message.stopReason, metrics }, null, 2)
}
