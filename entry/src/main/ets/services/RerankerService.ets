import entry from 'libentry.so'
import { ModelProfile } from '../models/ModelProfile'
import { ModelDirectoryPreflightService } from './ModelDirectoryPreflightService'

let active: boolean = false
export function isRerankerActive(): boolean { return active }

export class RerankerService {
  loadedId: string = ''
  busy: boolean = false
  private cancelled: boolean = false

  async load(model: ModelProfile, threads: number, tokens: number): Promise<void> {
    if (active || this.busy || this.loadedId.length > 0) throw new Error('请先释放已加载的重排模型')
    active = true
    this.busy = true
    try {
      await new ModelDirectoryPreflightService().requireCompatible(model.configPath ?? '', false, [], false)
      await entry.rerankerAsync('load', model.configPath ?? '', threads, tokens, '', [])
      this.loadedId = model.id
    } finally { this.busy = false; active = false }
  }

  async score(query: string, documents: string[], prepare: () => Promise<void>): Promise<number[]> {
    if (active || this.busy) throw new Error('重排模型正在使用中')
    if (this.loadedId.length === 0) throw new Error('请先加载重排模型')
    active = true
    this.busy = true
    this.cancelled = false
    try {
      await prepare()
      if (this.cancelled) throw new Error('重排已取消')
      return await entry.rerankerAsync('score', '', 0, 0, query, documents)
    } finally { this.busy = false; active = false }
  }

  cancel(): void { this.cancelled = true; entry.rerankerCancel() }

  async release(): Promise<void> {
    if (active || this.busy) throw new Error('请等待重排任务结束')
    active = true
    this.busy = true
    try {
      await entry.rerankerAsync('release', '', 0, 0, '', [])
      this.loadedId = ''
    } finally { this.busy = false; active = false }
  }
}
