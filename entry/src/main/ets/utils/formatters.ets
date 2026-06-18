export function nowTime(): string {
  const date = new Date()
  const hour = date.getHours().toString().padStart(2, '0')
  const minute = date.getMinutes().toString().padStart(2, '0')
  return `${hour}:${minute}`
}

export function kbToMb(value: bigint): string {
  return `${(Number(value.toString()) / 1024).toFixed(1)} MB`
}

export function bytesToMb(value: bigint): string {
  return `${(Number(value.toString()) / 1024 / 1024).toFixed(1)} MB`
}

export function bytesToDisplay(value: number): string {
  if (value >= 1024 * 1024 * 1024) {
    return `${(value / 1024 / 1024 / 1024).toFixed(2)} GB`
  }
  if (value >= 1024 * 1024) {
    return `${(value / 1024 / 1024).toFixed(2)} MB`
  }
  if (value >= 1024) {
    return `${(value / 1024).toFixed(2)} KB`
  }
  return `${value} B`
}

export function formatError(err: Object): string {
  if (err === undefined || err === null) {
    return '未知错误'
  }
  if (typeof err === 'string') {
    return err
  }

  const record = err as Record<string, Object>
  const parts: string[] = []
  if (record.code !== undefined) {
    parts.push(`code=${record.code}`)
  }
  if (record.name !== undefined) {
    parts.push(`name=${record.name}`)
  }
  if (record.message !== undefined) {
    parts.push(`${record.message}`)
  }
  if (parts.length > 0) {
    return parts.join(' ')
  }
  return `${err}`
}
