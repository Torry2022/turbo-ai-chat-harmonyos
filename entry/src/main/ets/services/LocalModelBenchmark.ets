import { common } from '@kit.AbilityKit'
import preferences from '@ohos.data.preferences'
import { ChatTurn, GenerationSettings } from '../models/ChatTypes'
import { NativeInferenceService } from './NativeInferenceService'
import { RuntimeStatsService } from './RuntimeStatsService'

export const LOCAL_BENCHMARK_OUTPUT_LIMIT: number = 64
export const LOCAL_BENCHMARK_RUNS: number = 3
const BENCHMARK_PREFERENCES = 'local_model_benchmark_v1'

interface LocalBenchmarkRun {
  inputTokens: number
  outputTokens: number
  firstOutputMs: number
  prefillMs: number
  decodeMs: number
}

export interface LocalBenchmarkResult {
  completedAt: number
  threads: number
  peakRssBytes: number
  runs: LocalBenchmarkRun[]
}

export class LocalModelBenchmark {
  private stats: RuntimeStatsService = new RuntimeStatsService()

  async read(context: common.UIAbilityContext, modelId: string): Promise<LocalBenchmarkResult | undefined> {
    const store = await preferences.getPreferences(context, BENCHMARK_PREFERENCES)
    const raw = String(await store.get(modelId, ''))
    return raw.length > 0 ? JSON.parse(raw) as LocalBenchmarkResult : undefined
  }

  async save(context: common.UIAbilityContext, modelId: string, result: LocalBenchmarkResult): Promise<void> {
    const store = await preferences.getPreferences(context, BENCHMARK_PREFERENCES)
    await store.put(modelId, JSON.stringify(result))
    await store.flush()
  }

  async run(native: NativeInferenceService, supportsThinking: boolean, canceled: () => boolean,
    reportProgress: (message: string) => void): Promise<LocalBenchmarkResult | undefined> {
    const settings: GenerationSettings = {
      thinkingEnabled: supportsThinking ? false : undefined,
      temperature: 0.1, topP: 1, topK: 1, repetitionPenalty: 1,
      frequencyPenalty: 0, presencePenalty: 0, penaltyWindow: 64
    }
    const prompt: ChatTurn[] = [{
      role: 'user',
      content: '请用中文写一段约三百字的短文，介绍城市图书馆如何服务不同年龄的读者。' +
        '从儿童阅读、学习空间、无障碍设施和社区活动四方面展开，每个方面举一个实际例子。直接写正文。'
    }]
    const request = await native.beginChatRequest()
    try {
      const threads = native.modelThreadInfo().chat.actual
      const runs: LocalBenchmarkRun[] = []
      let peakRssBytes = 0
      for (let index = 0; index <= LOCAL_BENCHMARK_RUNS; index++) {
        if (canceled()) return undefined
        reportProgress(index === 0 ? '正在预热' : `正在测速 ${index}/${LOCAL_BENCHMARK_RUNS}`)
        let firstOutputMs = -1
        const startedAt = Date.now()
        const sampleRss = async (): Promise<void> => {
          try { peakRssBytes = Math.max(peakRssBytes, (await this.stats.readSample()).rssBytes) } catch (_) {}
        }
        const timer = index > 0 ? setInterval(() => { sampleRss() }, 1000) : -1
        try {
          const result = await native.generateText(prompt, LOCAL_BENCHMARK_OUTPUT_LIMIT, settings, (chunk: string) => {
            if (chunk.length > 0 && firstOutputMs < 0) firstOutputMs = Date.now() - startedAt
          }, request)
          if (canceled()) return undefined
          const timing = result.nativeTiming
          if ((result.stopReason !== 'eos' && result.stopReason !== 'max_tokens') ||
            result.inputTokens === undefined || result.generatedTokens <= 0 || timing === undefined || firstOutputMs < 0) {
            throw new Error('测速未取得完整结果')
          }
          if (index > 0) {
            await sampleRss()
            runs.push({ inputTokens: result.inputTokens, outputTokens: result.generatedTokens,
              firstOutputMs, prefillMs: timing.prefillMs, decodeMs: timing.decodeMs })
          }
        } finally {
          if (timer >= 0) clearInterval(timer)
        }
      }
      if (canceled()) return undefined
      return { completedAt: Date.now(), threads, peakRssBytes, runs }
    } finally {
      request.release()
    }
  }
}
