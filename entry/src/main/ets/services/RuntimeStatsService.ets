import hidebug from '@ohos.hidebug'
import batteryInfo from '@ohos.batteryInfo'
import { EMPTY_RUNTIME_STATS, RuntimeStats } from '../models/RuntimeStats'
import { bytesToMb, formatError, kbToMb } from '../utils/formatters'

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
}
