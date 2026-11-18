import entry, { EmbeddingResult } from 'libentry.so'
import { ModelProfile } from '../models/ModelProfile'
import { ModelExecutionService } from './ModelExecutionService'
import { NativeInferenceService } from './NativeInferenceService'
import { ModelDirectoryPreflightService } from './ModelDirectoryPreflightService'

export class EmbeddingService {
  loadedId: string = ''
  dimension: number = 0
  threads: number = 0
  busy: boolean = false

  async load(model: ModelProfile, threads: number): Promise<void> {
    if (this.busy || this.loadedId.length > 0) throw new Error('请先释放已加载的向量模型')
    this.busy = true
    let release: (() => void) | undefined
    try {
      await new NativeInferenceService().cancelTitleGeneration()
      release = ModelExecutionService.acquire('embedding')
      await new ModelDirectoryPreflightService().requireCompatible(model.configPath ?? '', false, [], false, true)
      const result: EmbeddingResult = await entry.embeddingAsync('load', model.configPath ?? '', threads, [])
      this.loadedId = model.id
      this.dimension = result.dimension
      this.threads = result.threads
    } finally { release?.(); this.busy = false }
  }

  async encode(texts: string[]): Promise<EmbeddingResult> {
    if (this.busy) throw new Error('向量模型正在使用中')
    if (!this.loadedId) throw new Error('请先加载向量模型')
    this.busy = true
    let release: (() => void) | undefined
    try {
      await new NativeInferenceService().cancelTitleGeneration()
      release = ModelExecutionService.acquire('embedding')
      return await entry.embeddingAsync('encode', '', 0, texts)
    } finally { release?.(); this.busy = false }
  }

  async release(): Promise<void> {
    if (this.busy) throw new Error('请等待向量任务结束')
    this.busy = true
    let release: (() => void) | undefined
    try {
      await new NativeInferenceService().cancelTitleGeneration()
      release = ModelExecutionService.acquire('embedding')
      await entry.embeddingAsync('release', '', 0, [])
      this.loadedId = ''
      this.dimension = 0
      this.threads = 0
    } finally { release?.(); this.busy = false }
  }
}
