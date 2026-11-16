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
  const fallback = '下载未完成，请检查网络和可用存储空间后重试。'
  if (err === undefined || err === null) return fallback
  const record = err as Record<string, Object>
  const raw = formatError(err)
  const embeddedCode = /(?:code=|错误码\s*)(\d+)/i.exec(raw)
  const code = Number(record.code ?? embeddedCode?.[1] ?? 0)
  let message = typeof err === 'string' ? err :
    (record.message !== undefined ? String(record.message) : '')
  while (message.startsWith('Error:') || message.startsWith('BusinessError:')) {
    message = message.substring(message.indexOf(':') + 1).trim()
  }
  const lower = raw.toLowerCase()
  if (code === 2300028 || /timeout|timed out/.test(lower)) {
    return '连接下载服务超时，请检查网络或代理设置后重试。'
  }
  if (code === 2300005 || /proxy/.test(lower)) return '无法连接代理服务器，请检查代理设置后重试。'
  if (code === 2300006 || /resolve.*host|dns/.test(lower)) return '无法解析下载地址，请检查网络后重试。'
  if (code === 2300007 || /failed to connect|connection refused|network.*unavailable/.test(lower)) {
    return '无法连接下载服务，请检查网络或代理设置后重试。'
  }
  if (code === 2300060 || code === 2300077 || /certificate|ssl|tls/.test(lower)) {
    return '下载连接验证失败，请检查设备时间或更换网络后重试。'
  }
  if (code === 13900028 || /enospc|no space left|disk full/.test(lower)) {
    return '存储空间不足，请清理空间后重试。'
  }
  if (/http\s*404/i.test(raw)) return '下载地址已失效，请刷新模型广场后重试。'
  if (/http\s*(401|403)/i.test(raw)) return '下载源拒绝访问，请确认模型可公开下载后重试。'
  if (/http\s*416/i.test(raw)) return '续传信息已失效，请关闭安装窗口后重新下载。'
  if (/http\s*5\d\d/i.test(raw)) return '下载服务暂时不可用，请稍后重试。'
  if (code === 2300018 || code === 2300052 || code === 2300056 || /connection reset|partial file/.test(lower)) {
    return '下载连接已中断，请检查网络后继续下载。'
  }
  if (/[\u4e00-\u9fff]/.test(message) && !/Error:|code=|errno|HTTP\s*\d|\/data\//i.test(message)) return message
  return fallback
}
