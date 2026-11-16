import { rcp } from '@kit.RemoteCommunicationKit'
import connection from '@ohos.net.connection'
import url from '@ohos.url'
import util from '@ohos.util'

interface ImageDownloadState {
  session?: rcp.Session
}

export const API_IMAGE_MAX_BYTES = 10 * 1024 * 1024

export function invalidImageError(message: string): Error {
  const error = new Error(message)
  error.name = 'InvalidImageError'
  return error
}

export function publicImageAddress(address: string): boolean {
  const value = address.toLowerCase().replace(/^\[|\]$/g, '')
  if (value.includes(':')) {
    return /^[23][0-9a-f]{3}:/.test(value) && !value.startsWith('2001:db8:') &&
      !value.startsWith('2001:0:') && !value.startsWith('2002:') && !value.includes('.')
  }
  const parts = value.split('.')
  if (parts.length !== 4 || parts.some((part: string) => !/^\d{1,3}$/.test(part) || Number(part) > 255)) return false
  const a = Number(parts[0])
  const b = Number(parts[1])
  return a > 0 && a < 224 && a !== 10 && a !== 127 &&
    !(a === 100 && b >= 64 && b <= 127) && !(a === 169 && b === 254) &&
    !(a === 172 && b >= 16 && b <= 31) && !(a === 192 && (b === 168 || b === 0 || b === 2)) &&
    !(a === 198 && (b === 18 || b === 19 || b === 51)) && !(a === 203 && b === 0)
}

export async function downloadApiImage(address: string, isCancelled: () => boolean): Promise<string> {
  const state: ImageDownloadState = {}
  let ended = false
  const started = Date.now()
  let failure = ''
  let timer = -1
  const guard = new Promise<string>((_resolve, reject) => {
    timer = setInterval(() => {
      if (isCancelled() || Date.now() - started >= 30000) {
        failure = isCancelled() ? '图片请求已取消。' : '图片下载超时，请稍后重试。'
        ended = true
        state.session?.cancel()
        reject(new Error(failure))
      }
    }, 100)
  })
  const fetchImage = async (): Promise<string> => {
    let current = address
    for (let hop = 0; hop <= 3; hop++) {
      const parsed = new url.URL(current)
      if (!['https:', 'http:'].includes(parsed.protocol) || parsed.username.length > 0 || parsed.password.length > 0) {
        throw invalidImageError('请提供有效的 HTTP 或 HTTPS 图片地址。')
      }
      const host = parsed.hostname.replace(/^\[|\]$/g, '')
      const addresses = await connection.getAddressesByName(host)
      if (ended || isCancelled()) throw invalidImageError('图片请求已取消。')
      if (addresses.length === 0 || addresses.some((item: connection.NetAddress) => !publicImageAddress(item.address))) {
        throw invalidImageError('图片地址需要使用公网地址。')
      }
      const chunks: ArrayBuffer[] = []
      let size = 0
      state.session = rcp.createSession({ requestConfiguration: {
        proxy: 'no-proxy',
        dns: { dnsRules: [{ host, port: Number(parsed.port || (parsed.protocol === 'https:' ? '443' : '80')),
          ipAddresses: addresses.map((item: connection.NetAddress) => item.address) }] },
        transfer: { autoRedirect: false, timeout: { connectMs: 10000, transferMs: 30000 } },
        tracing: { httpEventsHandler: { onDataReceive: (data: ArrayBuffer): void => {
          if (ended || failure.length > 0) return
          size += data.byteLength
          if (size > API_IMAGE_MAX_BYTES) {
            failure = '图片文件过大，请使用不超过 10 MB 的图片。'
            state.session?.cancel()
            return
          }
          chunks.push(data)
        } } }
      } })
      let response: rcp.Response
      try {
        response = await state.session.fetch(new rcp.Request(current, 'GET', { Accept: 'image/png,image/jpeg,image/webp' }))
      } finally {
        state.session.close()
        state.session = undefined
      }
      if (failure.length > 0) throw invalidImageError(failure)
      if (ended || isCancelled()) throw invalidImageError('图片请求已取消。')
      if ([301, 302, 303, 307, 308].includes(response.statusCode)) {
        const location = response.headers.location
        if (location === undefined || hop === 3) throw invalidImageError('图片地址跳转过多或无效。')
        current = new url.URL(location, current).toString()
        continue
      }
      if (response.statusCode !== 200) throw invalidImageError('图片下载失败，请确认图片地址可以直接访问。')
      const type = (response.headers['content-type'] ?? '').toString().split(';')[0].trim().toLowerCase()
      if (!['image/png', 'image/jpeg', 'image/webp'].includes(type) || size === 0) {
        throw invalidImageError('图片地址需要返回 PNG、JPEG 或 WebP 图片。')
      }
      const bytes = new Uint8Array(size)
      let offset = 0
      for (const chunk of chunks) { bytes.set(new Uint8Array(chunk), offset); offset += chunk.byteLength }
      return `data:${type};base64,${new util.Base64Helper().encodeToStringSync(bytes)}`
    }
    throw invalidImageError('图片地址跳转过多。')
  }
  try {
    return await Promise.race([fetchImage(), guard])
  } catch (error) {
    const cause = error as Error
    if (cause.name === 'InvalidImageError') throw cause
    throw invalidImageError(failure.length > 0 ? failure : '无法读取远程图片，请确认图片地址、格式和大小。')
  } finally {
    ended = true
    clearInterval(timer)
    state.session?.cancel()
    state.session?.close()
  }
}
