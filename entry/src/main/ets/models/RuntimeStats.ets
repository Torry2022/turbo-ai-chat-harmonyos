export interface RuntimeStats {
  appCpu: string;
  systemCpu: string;
  appPss: string;
  nativeHeap: string;
  systemMem: string;
}

export const EMPTY_RUNTIME_STATS: RuntimeStats = {
  appCpu: '--',
  systemCpu: '--',
  appPss: '--',
  nativeHeap: '--',
  systemMem: '--'
};
