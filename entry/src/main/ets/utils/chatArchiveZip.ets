// Inspect ZIP metadata before allowing the system decompressor to write files.
import { CHAT_ARCHIVE_MANIFEST_MAX_BYTES } from './chatArchive'
export function inspectChatArchiveZip(size: number, read: (offset: number, length: number) => Uint8Array): number {
  const fail = (): never => { throw new Error('备份压缩包损坏或格式不受支持') }
  if (size < 22) return fail()
  const tailStart = Math.max(0, size - 65557)
  const tail = read(tailStart, size - tailStart)
  const tailView = new DataView(tail.buffer, tail.byteOffset, tail.byteLength)
  let end = tail.length - 22
  while (end >= 0 && (tailView.getUint32(end, true) !== 0x06054b50 ||
    end + 22 + tailView.getUint16(end + 20, true) !== tail.length)) end--
  if (end < 0 || tailView.getUint16(end + 4, true) !== 0 || tailView.getUint16(end + 6, true) !== 0) return fail()
  const count = tailView.getUint16(end + 10, true)
  const centralSize = tailView.getUint32(end + 12, true)
  const centralStart = tailView.getUint32(end + 16, true)
  if (count === 65535 || count !== tailView.getUint16(end + 8, true) ||
    centralStart + centralSize !== tailStart + end) return fail()
  let cursor = centralStart
  let total = 0
  let manifests = 0
  let root: string | undefined = undefined
  const names: Set<string> = new Set()
  for (let index = 0; index < count; index++) {
    const header = read(cursor, 46)
    const view = new DataView(header.buffer, header.byteOffset, header.byteLength)
    if (view.getUint32(0, true) !== 0x02014b50) return fail()
    const flags = view.getUint16(8, true)
    const method = view.getUint16(10, true)
    const compressed = view.getUint32(20, true)
    const original = view.getUint32(24, true)
    const nameLength = view.getUint16(28, true)
    const localOffset = view.getUint32(42, true)
    if ((flags & 1) !== 0 || (method !== 0 && method !== 8) || compressed === 0xffffffff ||
      original === 0xffffffff || view.getUint16(34, true) !== 0 ||
      ((view.getUint32(38, true) >>> 16) & 0xf000) === 0xa000 || nameLength === 0) return fail()
    const bytes = read(cursor + 46, nameLength)
    let name = ''
    for (const byte of bytes) {
      if (byte < 32 || byte > 126) return fail()
      name += String.fromCharCode(byte)
    }
    if (names.has(name)) return fail()
    names.add(name)
    const prefix = name.startsWith('backup/') ? 'backup/' : ''
    if (name !== 'backup/') {
      if (root !== undefined && root !== prefix) return fail()
      root = prefix
    }
    const relative = name.substring(prefix.length)
    if (!['', 'images/', 'manifest.json'].includes(relative) && !/^images\/[0-9]+-[0-9]+$/.test(relative)) return fail()
    if (relative === 'manifest.json') {
      manifests++
      if (original > CHAT_ARCHIVE_MANIFEST_MAX_BYTES) throw new Error('备份中的对话文本过大，无法在本机恢复')
    }
    const local = read(localOffset, 30)
    const localView = new DataView(local.buffer, local.byteOffset, local.byteLength)
    if (localView.getUint32(0, true) !== 0x04034b50 || localView.getUint16(6, true) !== flags ||
      localView.getUint16(8, true) !== method || localView.getUint16(26, true) !== nameLength) return fail()
    const localName = read(localOffset + 30, nameLength)
    if (localName.some((byte: number, offset: number) => byte !== bytes[offset]) ||
      localOffset + 30 + nameLength + localView.getUint16(28, true) + compressed > centralStart) return fail()
    total += original
    cursor += 46 + nameLength + view.getUint16(30, true) + view.getUint16(32, true)
    if (cursor > centralStart + centralSize) return fail()
  }
  if (manifests !== 1 || cursor !== centralStart + centralSize) return fail()
  return total
}
