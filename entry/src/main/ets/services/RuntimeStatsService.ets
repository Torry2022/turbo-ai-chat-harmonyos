import hidebug from '@ohos.hidebug';
import { EMPTY_RUNTIME_STATS, RuntimeStats } from '../models/RuntimeStats';
import { bytesToMb, formatError, kbToMb } from '../utils/formatters';

export class RuntimeStatsService {
  readStats(): RuntimeStats {
    try {
      const systemMem = hidebug.getSystemMemInfo();
      const appMem = hidebug.getAppNativeMemInfo();
      return {
        appCpu: `${(hidebug.getCpuUsage() * 100).toFixed(1)}%`,
        systemCpu: `${(hidebug.getSystemCpuUsage() * 100).toFixed(1)}%`,
        appPss: kbToMb(appMem.pss),
        nativeHeap: bytesToMb(hidebug.getNativeHeapAllocatedSize()),
        systemMem: `${kbToMb(systemMem.availableMem)} 可用`
      };
    } catch (err) {
      return {
        appCpu: EMPTY_RUNTIME_STATS.appCpu,
        systemCpu: EMPTY_RUNTIME_STATS.systemCpu,
        appPss: EMPTY_RUNTIME_STATS.appPss,
        nativeHeap: EMPTY_RUNTIME_STATS.nativeHeap,
        systemMem: `不可用：${formatError(err as Object)}`
      };
    }
  }
}
