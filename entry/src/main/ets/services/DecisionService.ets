import { ModelExecutionService } from './ModelExecutionService'
import { NativeInferenceService } from './NativeInferenceService'
import fs from '@ohos.file.fs'
import entry from 'libentry.so'
import { ModelProfile } from '../models/ModelProfile'
import { ImagePayload } from '../models/ChatTypes'
import { LAYA_MODEL_ID } from '../models/LayaModelConfig'
import { loadLaya, releaseLaya, decideLaya, isLayaReady, isLayaLoaded, LayaRuntimeState } from './LayaDecisionService'
import { isRerankerActive } from './RerankerService'
import { ModelDirectoryPreflightService } from './ModelDirectoryPreflightService'

interface DecisionThreadConfig { thread_num?: number }
interface DecisionLoadReceipt { cpu_threads?: number }

export type DecisionRuntimeState = LayaRuntimeState
let state: DecisionRuntimeState = 'idle'
let loaded: ModelProfile | undefined = undefined
let observer: (value: DecisionRuntimeState) => void = () => {}

export function observeDecisionRuntime(callback: (value: DecisionRuntimeState) => void): void {
  observer = callback
  callback(state)
}

function update(value: DecisionRuntimeState): void { state = value; observer(value) }
export function loadedDecisionModel(): ModelProfile | undefined { return loaded }
export function isDecisionLoaded(): boolean { return loaded !== undefined }

export function isDecisionReady(filesDir: string, model: ModelProfile): boolean {
  if (model.id === LAYA_MODEL_ID) return isLayaReady(filesDir)
  try { return fs.statSync(model.configPath ?? '').isFile() } catch (_) { return false }
}

export async function loadDecision(filesDir: string, model: ModelProfile, requestedThreads?: number): Promise<number | undefined> {
  if (state !== 'idle' || isRerankerActive()) throw new Error('请先释放已加载的决策模型，并等待当前任务结束')
  update('loading')
  let release: (() => void) | undefined
  try {
    await new NativeInferenceService().cancelTitleGeneration()
    release = ModelExecutionService.acquire('decision')
    let actualThreads: number | undefined
    if (model.id === LAYA_MODEL_ID) actualThreads = await loadLaya(filesDir, requestedThreads ?? 4)
    else {
      await new ModelDirectoryPreflightService().requireCompatible(model.configPath ?? '', true, [], false)
      const configPath = model.configPath ?? ''
      const config = JSON.parse((await fs.readText(configPath)).replace(/^\uFEFF/, '')) as DecisionThreadConfig
      const threads = requestedThreads ?? config.thread_num ?? 4
      if (!Number.isInteger(threads) || threads < 1 || threads > 16)
        throw new Error('决策模型 thread_num 应为 1 至 16 的整数')
      const receipt: string = await entry.h2oLoadAsync(configPath, threads)
      console.info(`[ModelThreads] H2O requested=${threads} receipt=${receipt}`)
      actualThreads = (JSON.parse(receipt) as DecisionLoadReceipt).cpu_threads
    }
    loaded = model
    update('loaded')
    return actualThreads
  } catch (error) { loaded = undefined; update('idle'); throw new Error(`${error}`) } finally { release?.() }
}

export async function releaseDecision(): Promise<void> {
  if (state === 'loading' || state === 'running' || state === 'releasing' || isRerankerActive())
    throw new Error('请等待当前模型任务结束')
  if (loaded === undefined) return
  const model = loaded
  update('releasing')
  let release: (() => void) | undefined
  try {
    await new NativeInferenceService().cancelTitleGeneration()
    release = ModelExecutionService.acquire('decision')
    if (model.id === LAYA_MODEL_ID) await releaseLaya()
    else await entry.h2oReleaseAsync()
    loaded = undefined
    update('idle')
  } catch (error) { update('loaded'); throw new Error(`${error}`) } finally { release?.() }
}

export async function decide(filesDir: string, record: string, type: string, instruction: string,
  options: string[], names: string[], descriptions: string[], image?: ImagePayload): Promise<string> {
  if (state !== 'loaded' || loaded === undefined || isRerankerActive()) throw new Error('请先加载决策模型，并等待当前任务结束')
  if (image !== undefined && loaded.id === LAYA_MODEL_ID) throw new Error('当前决策模型不支持图片')
  update('running')
  let release: (() => void) | undefined
  try {
    await new NativeInferenceService().cancelTitleGeneration()
    release = ModelExecutionService.acquire('decision')
    return loaded.id === LAYA_MODEL_ID ? await decideLaya(filesDir, record, type, instruction, options) :
      await entry.h2oDecideAsync(record, type, instruction, names, descriptions,
        image?.pixels ?? new ArrayBuffer(0), image?.width ?? 0, image?.height ?? 0)
  } catch (error) {
    if (loaded?.id === LAYA_MODEL_ID && !isLayaLoaded()) loaded = undefined
    throw new Error(`${error}`)
  } finally { release?.(); update(loaded === undefined ? 'idle' : 'loaded') }
}
