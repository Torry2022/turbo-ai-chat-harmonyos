import hidebug from '@ohos.hidebug'
import deviceInfo from '@ohos.deviceInfo'
import batteryInfo from '@ohos.batteryInfo'
import fs from '@ohos.file.fs'
import { storageStatistics } from '@kit.CoreFileKit'
import { EMPTY_RUNTIME_STATS, EMPTY_STORAGE_STATS, RuntimeStats, StorageStats, RuntimeSample, StorageSample } from '../models/RuntimeStats'
import { bytesToDisplay, formatError } from '../utils/formatters'

export class RuntimeStatsService {
  private static cachedSample?: RuntimeSample
  private static pendingSample?: Promise<RuntimeSample>
  private storageKey: string = ''
  private storageSample?: StorageSample
  private pendingStorage?: Promise<StorageSample>

  private cachedRuntimeSample(): RuntimeSample | undefined {
    const cached = RuntimeStatsService.cachedSample
    return cached !== undefined && Date.now() - cached.sampledAt >= 0 &&
      Date.now() - cached.sampledAt < 1000 ? cached : undefined
  }

  private collectSample(memory: hidebug.NativeMemInfo): RuntimeSample {
    const system = hidebug.getSystemMemInfo()
    const sample: RuntimeSample = {
      sampledAt: Date.now(),
      appCpuPercent: hidebug.getCpuUsage() * 100,
      systemCpuPercent: hidebug.getSystemCpuUsage() * 100,
      pssWithSwapBytes: Number(memory.pss) * 1024,
      rssBytes: Number(memory.rss) * 1024,
      swapBytes: deviceInfo.sdkApiVersion >= 24 ? Number(hidebug.getRssInfo().swapRss) * 1024 : null,
      nativeHeapAllocatedBytes: Number(hidebug.getNativeHeapAllocatedSize()),
      nativeHeapTotalBytes: Number(hidebug.getNativeHeapSize()),
      systemMemTotalBytes: Number(system.totalMem) * 1024,
      systemMemAvailableBytes: Number(system.availableMem) * 1024,
      batteryTemperatureC: batteryInfo.batteryTemperature / 10,
      threadCount: hidebug.getAppThreadCpuUsage().length
    }
    RuntimeStatsService.cachedSample = sample
    return sample
  }

  async readSample(): Promise<RuntimeSample> {
    const cached = this.cachedRuntimeSample()
    if (cached !== undefined) return cached
    if (RuntimeStatsService.pendingSample !== undefined) return RuntimeStatsService.pendingSample
    const pending = (deviceInfo.sdkApiVersion >= 20 ? hidebug.getAppNativeMemInfoAsync() :
      Promise.resolve(hidebug.getAppNativeMemInfo())).then((memory: hidebug.NativeMemInfo) => this.collectSample(memory))
    RuntimeStatsService.pendingSample = pending
    try {
      return await pending
    } finally {
      if (RuntimeStatsService.pendingSample === pending) RuntimeStatsService.pendingSample = undefined
    }
  }

  readStats(): RuntimeStats {
    try {
      const sample = this.cachedRuntimeSample() ?? this.collectSample(hidebug.getAppNativeMemInfo())
      return {
        appCpu: `${sample.appCpuPercent.toFixed(1)}%`,
        systemCpu: `${sample.systemCpuPercent.toFixed(1)}%`,
        appRss: `${(sample.rssBytes / 1024 / 1024).toFixed(1)} MB`,
        nativeHeapAllocated: `${(sample.nativeHeapAllocatedBytes / 1024 / 1024).toFixed(1)} MB`,
        nativeHeapTotal: `${(sample.nativeHeapTotalBytes / 1024 / 1024).toFixed(1)} MB`,
        systemMemTotal: `${(sample.systemMemTotalBytes / 1024 / 1024).toFixed(1)} MB`,
        systemMemAvailable: `${(sample.systemMemAvailableBytes / 1024 / 1024).toFixed(1)} MB 可用`,
        socTemp: `${sample.batteryTemperatureC.toFixed(1)}°C`,
        threadCount: `${sample.threadCount}`
      }
    } catch (err) {
      return {
        appCpu: EMPTY_RUNTIME_STATS.appCpu,
        systemCpu: EMPTY_RUNTIME_STATS.systemCpu,
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
      const sample = await this.readStorageSample(filesDir, currentModelDir, true)
      return {
        appFiles: bytesToDisplay(sample.appBytes),
        currentModel: sample.currentModelBytes > 0 ? bytesToDisplay(sample.currentModelBytes) : '未安装'
      }
    } catch (err) {
      return {
        appFiles: `不可用：${formatError(err as Object)}`,
        currentModel: EMPTY_STORAGE_STATS.currentModel
      }
    }
  }

  async readStorageSample(filesDir: string, currentModelDir: string, refresh: boolean = false): Promise<StorageSample> {
    const key = `${filesDir}|${currentModelDir}`
    if (key === this.storageKey) {
      if (this.pendingStorage !== undefined) return this.pendingStorage
      if (!refresh && this.storageSample !== undefined && Date.now() - this.storageSample.sampledAt < 30000) {
        return this.storageSample
      }
    }
    if (this.storageKey !== key) this.storageSample = undefined
    this.storageKey = key
    const pending = this.collectStorageSample(currentModelDir)
    this.pendingStorage = pending
    try {
      const sample = await pending
      if (this.storageKey === key) this.storageSample = sample
      return sample
    } finally {
      if (this.pendingStorage === pending) this.pendingStorage = undefined
    }
  }

  private async collectStorageSample(currentModelDir: string): Promise<StorageSample> {
    const bundle = await storageStatistics.getCurrentBundleStats()
    const currentModelBytes = currentModelDir.length > 0 && (await this.exists(currentModelDir)) ?
      await this.pathSize(currentModelDir) : 0
    return { sampledAt: Date.now(), appBytes: bundle.appSize + bundle.dataSize + bundle.cacheSize, currentModelBytes }
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
