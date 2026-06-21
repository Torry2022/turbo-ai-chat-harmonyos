const COLOR_NORMAL = '#8CA2B8'
const COLOR_GOOD = '#45D6A4'
const COLOR_WARNING = '#F2B35D'
const COLOR_DANGER = '#FF9A9A'

function hasErrorText(value: string): boolean {
  return value.indexOf('不可用') >= 0 || value.indexOf('失败') >= 0 || value.indexOf('Error') >= 0
}

function firstNumber(value: string): number {
  const match = value.match(/-?\d+(\.\d+)?/)
  if (match === null || match.length <= 0) {
    return -1
  }
  return Number(match[0])
}

function memoryToMb(value: string): number {
  const amount = firstNumber(value)
  if (amount < 0) {
    return -1
  }
  if (value.indexOf('GB') >= 0) {
    return amount * 1024
  }
  if (value.indexOf('KB') >= 0) {
    return amount / 1024
  }
  return amount
}

export function colorForAppCpu(value: string): string {
  if (hasErrorText(value)) {
    return COLOR_DANGER
  }
  const percent = firstNumber(value)
  if (percent < 0 || percent < 5) {
    return COLOR_NORMAL
  }
  if (percent < 15) {
    return COLOR_GOOD
  }
  if (percent < 30) {
    return COLOR_WARNING
  }
  return COLOR_DANGER
}

export function colorForSystemCpu(value: string): string {
  if (hasErrorText(value)) {
    return COLOR_DANGER
  }
  const percent = firstNumber(value)
  if (percent < 0 || percent < 50) {
    return COLOR_NORMAL
  }
  if (percent < 75) {
    return COLOR_WARNING
  }
  return COLOR_DANGER
}

export function colorForMemoryUsage(value: string): string {
  if (hasErrorText(value)) {
    return COLOR_DANGER
  }
  const mb = memoryToMb(value)
  if (mb < 0 || mb < 3072) {
    return COLOR_NORMAL
  }
  if (mb < 5120) {
    return COLOR_WARNING
  }
  return COLOR_DANGER
}

export function colorForAvailableMemory(value: string): string {
  if (hasErrorText(value)) {
    return COLOR_DANGER
  }
  const mb = memoryToMb(value)
  if (mb < 0 || mb > 3072) {
    return COLOR_NORMAL
  }
  if (mb >= 1024) {
    return COLOR_WARNING
  }
  return COLOR_DANGER
}

export function colorForTemperature(value: string): string {
  if (hasErrorText(value)) {
    return COLOR_DANGER
  }
  const temp = firstNumber(value)
  if (temp < 0 || temp < 38) {
    return COLOR_NORMAL
  }
  if (temp < 42) {
    return COLOR_WARNING
  }
  return COLOR_DANGER
}
