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

export function formatDownloadError(err: Object): string {
  if (err === undefined || err === null) {
    return '未知错误'
  }

  const record = err as Record<string, Object>
  let message = typeof err === 'string' ? err :
    (record.message !== undefined ? `${record.message}` : `${err}`)
  while (message.startsWith('Error:') || message.startsWith('BusinessError:')) {
    message = message.substring(message.indexOf(':') + 1).trim()
  }
  if (message === '[object Object]') {
    message = ''
  }

  if (record.code !== undefined) {
    return message.length > 0 ? `错误码 ${record.code}：${message}` : `错误码 ${record.code}`
  }
  return message.length > 0 ? message : '未知错误'
}
