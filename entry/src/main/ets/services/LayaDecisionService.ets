import { LAYA_MODEL_DIRECTORY, LAYA_MODEL_FILE, LAYA_TOKENIZER_FILE,
  LAYA_MODEL_BYTES, LAYA_TOKENIZER_BYTES } from '../models/LayaModelConfig'
import { isRerankerActive } from './RerankerService'
import fs from '@ohos.file.fs'
import entry from 'libentry.so'


export type LayaRuntimeState = 'idle' | 'loading' | 'running' | 'loaded' | 'releasing'
let runtimeState: LayaRuntimeState = 'idle'
let onRuntimeState: (state: LayaRuntimeState) => void = () => {}

export function observeLayaRuntime(callback: (state: LayaRuntimeState) => void): void {
  onRuntimeState = callback
  callback(runtimeState)
}

function setRuntimeState(state: LayaRuntimeState): void {
  runtimeState = state
  onRuntimeState(state)
}

export function isLayaLoaded(): boolean {
  return runtimeState === 'loaded' || runtimeState === 'running'
}

export async function loadLaya(filesDir: string): Promise<void> {
  if (isRerankerActive() || runtimeState !== 'idle') throw new Error('请等待当前模型任务结束')
  if (!isLayaReady(filesDir)) throw new Error('请先下载完整的决策模型')
  setRuntimeState('loading')
  try {
    await entry.layaLoadAsync(`${filesDir}/${LAYA_MODEL_DIRECTORY}/${LAYA_MODEL_FILE}`,
      `${filesDir}/${LAYA_MODEL_DIRECTORY}/${LAYA_TOKENIZER_FILE}`)
    setRuntimeState('loaded')
  } catch (error) {
    setRuntimeState('idle')
    throw new Error(`${error}`)
  }
}

export async function releaseLaya(): Promise<void> {
  if (isRerankerActive()) throw new Error('请等待重排任务结束')
  if (runtimeState === 'loading' || runtimeState === 'running' || runtimeState === 'releasing') {
    throw new Error('请等待当前决策完成')
  }
  const previous = runtimeState
  setRuntimeState('releasing')
  try {
    await entry.layaReleaseAsync()
    setRuntimeState('idle')
  } catch (error) {
    setRuntimeState(previous)
    throw new Error(`${error}`)
  }
}

export function isLayaReady(filesDir: string): boolean {
  if (filesDir.length === 0) return false
  try {
    const model = fs.statSync(`${filesDir}/${LAYA_MODEL_DIRECTORY}/${LAYA_MODEL_FILE}`)
    const tokenizer = fs.statSync(`${filesDir}/${LAYA_MODEL_DIRECTORY}/${LAYA_TOKENIZER_FILE}`)
    return model.isFile() && model.size === LAYA_MODEL_BYTES &&
      tokenizer.isFile() && tokenizer.size === LAYA_TOKENIZER_BYTES
  } catch (_error) {
    return false
  }
}

export async function decideLaya(filesDir: string, state: string, type: string, instruction: string,
  options: string[]): Promise<string> {
  if (isRerankerActive()) throw new Error('请等待重排任务结束')
  if (runtimeState === 'loading' || runtimeState === 'running' || runtimeState === 'releasing') {
    throw new Error('当前正在使用决策模型，请稍后重试')
  }
  if (!isLayaLoaded()) throw new Error('请先在模型页加载决策模型')
  setRuntimeState('running')
  try {
    const output: string = await entry.layaDecideAsync(`${filesDir}/${LAYA_MODEL_DIRECTORY}/${LAYA_MODEL_FILE}`,
      `${filesDir}/${LAYA_MODEL_DIRECTORY}/${LAYA_TOKENIZER_FILE}`, state, type, instruction, options)
    setRuntimeState('loaded')
    return output
  } catch (error) {
    try {
      await entry.layaReleaseAsync()
    } finally {
      setRuntimeState('idle')
    }
    throw new Error(`${error}`)
  }
}
