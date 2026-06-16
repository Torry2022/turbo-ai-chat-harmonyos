export interface RuntimeStats {
  appCpu: string
  systemCpu: string
  appPss: string
  appRss: string
  nativeHeapAllocated: string
  nativeHeapTotal: string
  systemMemTotal: string
  systemMemAvailable: string
  socTemp: string
  threadCount: string
}

export const EMPTY_RUNTIME_STATS: RuntimeStats = {
  appCpu: '--',
  systemCpu: '--',
  appPss: '--',
  appRss: '--',
  nativeHeapAllocated: '--',
  nativeHeapTotal: '--',
  systemMemTotal: '--',
  systemMemAvailable: '--',
  socTemp: '--',
  threadCount: '--'
}
