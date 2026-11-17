import fs from '@ohos.file.fs'
import { util } from '@kit.ArkTS'

export interface ModelLoadRecord {
  outcome?: 'loaded' | 'failed'
  modelId: string
  modelName: string
  loadedAt: number
  loadDurationMs: number
  requestedThreads: number
  actualThreads?: number
  configurationSha256?: string
  fileManifestSha256?: string
  runtimeLibrarySha256?: string
}

export class ModelUsageService {
  private records: ModelLoadRecord[] = []
  private directory: string = ''
  private writes: Promise<void> = Promise.resolve()

  async initialize(filesDir: string): Promise<void> {
    this.directory = filesDir
    try {
      const records = JSON.parse(await fs.readText(`${filesDir}/model-usage.json`)) as ModelLoadRecord[]
      if (Array.isArray(records)) this.records = records.filter((record: ModelLoadRecord) =>
        record !== null && typeof record === 'object' &&
        (record.outcome === undefined || record.outcome === 'loaded' || record.outcome === 'failed') &&
        typeof record.modelId === 'string' && typeof record.modelName === 'string' &&
        Number.isFinite(record.loadedAt) && Number.isFinite(record.loadDurationMs) && record.loadDurationMs >= 0)
    } catch (_) { this.records = [] }
  }

  latest(modelId: string): ModelLoadRecord | undefined {
    return this.records.find((record: ModelLoadRecord) => record.modelId === modelId && record.outcome !== 'failed')
  }

  latestAttempt(modelId: string): ModelLoadRecord | undefined {
    return this.records.find((record: ModelLoadRecord) => record.modelId === modelId)
  }

  async recordLoad(record: ModelLoadRecord): Promise<void> {
    this.records = [record, ...this.records.filter((item: ModelLoadRecord) => item.modelId !== record.modelId ||
      (record.outcome === 'failed' && item.outcome !== 'failed'))]
    const text = JSON.stringify(this.records)
    const task = this.writes.then(async (): Promise<void> => {
      if (this.directory.length === 0) return
      const temporary = `${this.directory}/model-usage.json.tmp`
      const output = fs.openSync(temporary, fs.OpenMode.WRITE_ONLY | fs.OpenMode.CREATE | fs.OpenMode.TRUNC)
      try {
        const bytes = new util.TextEncoder().encodeInto(text)
        let offset = 0
        while (offset < bytes.byteLength) {
          const written = fs.writeSync(output.fd, bytes.buffer.slice(offset))
          if (written <= 0) throw new Error('模型使用记录写入失败')
          offset += written
        }
        fs.fsyncSync(output.fd)
      } finally { fs.closeSync(output) }
      await fs.rename(temporary, `${this.directory}/model-usage.json`)
    })
    this.writes = task.catch(() => {})
    await task
  }
}
