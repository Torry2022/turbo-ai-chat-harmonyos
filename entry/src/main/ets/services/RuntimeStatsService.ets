import hidebug from '@ohos.hidebug'
import batteryInfo from '@ohos.batteryInfo'
import fs from '@ohos.file.fs'
import { EMPTY_RUNTIME_STATS, EMPTY_STORAGE_STATS, RuntimeStats, StorageStats } from '../models/RuntimeStats'
import { bytesToDisplay, bytesToMb, formatError, kbToMb } from '../utils/formatters'

export class RuntimeStatsService {
  readStats(): RuntimeStats {
    try {
      const systemMem = hidebug.getSystemMemInfo()
      const appMem = hidebug.getAppNativeMemInfo()
      return {
        appCpu: `${(hidebug.getCpuUsage() * 100).toFixed(1)}%`,
        systemCpu: `${(hidebug.getSystemCpuUsage() * 100).toFixed(1)}%`,
        appPss: kbToMb(appMem.pss),
        appRss: kbToMb(appMem.rss),
        nativeHeapAllocated: bytesToMb(hidebug.getNativeHeapAllocatedSize()),
        nativeHeapTotal: bytesToMb(hidebug.getNativeHeapSize()),
        systemMemTotal: kbToMb(systemMem.totalMem),
        systemMemAvailable: `${kbToMb(systemMem.availableMem)} 可用`,
        socTemp: `${(batteryInfo.batteryTemperature / 10).toFixed(1)}°C`,
        threadCount: `${hidebug.getAppThreadCpuUsage().length}`
      }
    } catch (err) {
      return {
        appCpu: EMPTY_RUNTIME_STATS.appCpu,
        systemCpu: EMPTY_RUNTIME_STATS.systemCpu,
        appPss: EMPTY_RUNTIME_STATS.appPss,
        appRss: EMPTY_RUNTIME_STATS.appRss,
        nativeHeapAllocated: EMPTY_RUNTIME_STATS.nativeHeapAllocated,
        nativeHeapTotal: EMPTY_RUNTIME_STATS.nativeHeapTotal,
        systemMemTotal: EMPTY_RUNTIME_STATS.systemMemTotal,
        systemMemAvailable: `不可用：${formatError(err as Object)}`,
        socTemp: EMPTY_RUNTIME_STATS.socTemp,
        threadCount: EMPTY_RUNTIME_STATS.threadCount
      }
    }
  }

  async readStorageStats(filesDir: string, currentModelDir: string): Promise<StorageStats> {
    if (filesDir.length <= 0) {
      return EMPTY_STORAGE_STATS
    }
    try {
      const appFilesBytes = await this.pathSize(filesDir)
      const currentModelBytes = currentModelDir.length > 0 && (await this.exists(currentModelDir)) ?
        await this.pathSize(currentModelDir) : 0
      return {
        appFiles: bytesToDisplay(appFilesBytes),
        currentModel: currentModelBytes > 0 ? bytesToDisplay(currentModelBytes) : '未安装'
      }
    } catch (err) {
      return {
        appFiles: `不可用：${formatError(err as Object)}`,
        currentModel: EMPTY_STORAGE_STATS.currentModel
      }
    }
  }

  async readCurrentModelStorage(currentModelDir: string): Promise<string> {
    if (currentModelDir.length <= 0) {
      return '未安装'
    }
    try {
      const currentModelBytes = await this.exists(currentModelDir) ? await this.pathSize(currentModelDir) : 0
      return currentModelBytes > 0 ? bytesToDisplay(currentModelBytes) : '未安装'
    } catch (_) {
      return EMPTY_STORAGE_STATS.currentModel
    }
  }

  private async pathSize(path: string): Promise<number> {
    const stat = await fs.stat(path)
    if (stat.isFile()) {
      return stat.size
    }
    if (!stat.isDirectory()) {
      return 0
    }
    let total = 0
    const names = await fs.listFile(path)
    for (let index = 0; index < names.length; index++) {
      total += await this.pathSize(`${path}/${names[index]}`)
    }
    return total
  }

  private async exists(path: string): Promise<boolean> {
    try {
      return await fs.access(path)
    } catch (_) {
      return false
    }
  }
}
