import fs from '@ohos.file.fs'
import entry from 'libentry.so'

export const LAYA_MODEL_DIRECTORY = 'laya-probe'
export const LAYA_MODEL_BYTES = 644944912
export const LAYA_TOKENIZER_BYTES = 13257378

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

export async function releaseLaya(): Promise<void> {
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
    const model = fs.statSync(`${filesDir}/${LAYA_MODEL_DIRECTORY}/laya.mnn`)
    const tokenizer = fs.statSync(`${filesDir}/${LAYA_MODEL_DIRECTORY}/laya.tokbin`)
    return model.isFile() && model.size === LAYA_MODEL_BYTES &&
      tokenizer.isFile() && tokenizer.size === LAYA_TOKENIZER_BYTES
  } catch (_error) {
    return false
  }
}

export async function decideLaya(filesDir: string, state: string, type: string, instruction: string,
  options: string[]): Promise<string> {
  if (runtimeState === 'loading' || runtimeState === 'running' || runtimeState === 'releasing') {
    throw new Error('当前正在使用决策模型，请稍后重试')
  }
  setRuntimeState(runtimeState === 'loaded' ? 'running' : 'loading')
  try {
    const output: string = await entry.layaDecideAsync(`${filesDir}/${LAYA_MODEL_DIRECTORY}/laya.mnn`,
      `${filesDir}/${LAYA_MODEL_DIRECTORY}/laya.tokbin`, state, type, instruction, options)
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
