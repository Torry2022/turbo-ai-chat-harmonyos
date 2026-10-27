export interface RuntimeStats {
  appCpu: string
  systemCpu: string
  appRss: string
  nativeHeapAllocated: string
  nativeHeapTotal: string
  systemMemTotal: string
  systemMemAvailable: string
  socTemp: string
  threadCount: string
}

export interface StorageStats {
  appFiles: string
  currentModel: string
}

export interface RuntimeSample {
  sampledAt: number
  appCpuPercent: number
  systemCpuPercent: number
  pssWithSwapBytes: number
  rssBytes: number
  swapBytes: number | null
  nativeHeapAllocatedBytes: number
  nativeHeapTotalBytes: number
  systemMemTotalBytes: number
  systemMemAvailableBytes: number
  batteryTemperatureC: number
  threadCount: number
}

export interface StorageSample {
  sampledAt: number
  appBytes: number
  currentModelBytes: number
}

export const EMPTY_RUNTIME_STATS: RuntimeStats = {
  appCpu: '--',
  systemCpu: '--',
  appRss: '--',
  nativeHeapAllocated: '--',
  nativeHeapTotal: '--',
  systemMemTotal: '--',
  systemMemAvailable: '--',
  socTemp: '--',
  threadCount: '--'
}

export const EMPTY_STORAGE_STATS: StorageStats = {
  appFiles: '--',
  currentModel: '--'
}
