export function calculateDownloadProgress(downloadedBytes: number, totalBytes: number): number {
  if (totalBytes <= 0) {
    return 0
  }
  const safeDownloadedBytes = Math.max(0, Math.min(totalBytes, downloadedBytes))
  return Math.round(safeDownloadedBytes / totalBytes * 1000) / 10
}

export function calculateDownloadedBytes(completedBytes: number, currentFileBytes: number, totalBytes: number): number {
  return Math.max(0, Math.min(totalBytes, completedBytes + currentFileBytes))
}
