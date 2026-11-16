import { common } from '@kit.AbilityKit'
import fs from '@ohos.file.fs'
import http from '@ohos.net.http'
import util from '@ohos.util'
import cryptoFramework from '@ohos.security.cryptoFramework'
import {
  BuiltinModelDownloadSpec,
  BuiltinModelFileSpec,
  BuiltinModelInstallProgress,
  ModelCatalogItem
} from '../models/BuiltinModelDownloadTypes'
import { modelInstallDirectory } from '../utils/modelCatalog'
import { ModelProfile } from '../models/ModelProfile'
import { calculateDownloadedBytes, calculateDownloadProgress } from '../utils/downloadProgress'
import { ModelDirectoryPreflightService } from './ModelDirectoryPreflightService'
import { ModelCatalogService } from './ModelCatalogService'

type ProgressCallback = (progress: BuiltinModelInstallProgress) => void

interface DownloadCheckpoint {
  url: string
  size: number
  bytes: number
  validator: string
  sha256?: string
}

const DOWNLOAD_BLOCK_BYTES: number = 16 * 1024 * 1024

export class BuiltinModelInstallService {
  private cancelRequested: boolean = false
  private currentHttpRequest?: http.HttpRequest
  private preflightService: ModelDirectoryPreflightService = new ModelDirectoryPreflightService()
  private catalogService: ModelCatalogService

  constructor(catalogService: ModelCatalogService = new ModelCatalogService()) {
    this.catalogService = catalogService
  }

  cancelInstall(): void {
    this.cancelRequested = true
    if (this.currentHttpRequest !== undefined) {
      this.currentHttpRequest.destroy()
    }
  }

  getDownloadSpec(profile: ModelProfile): BuiltinModelDownloadSpec | undefined {
    const catalogSpec = this.catalogService.findInstallItem(profile.catalogItemId)
    if (catalogSpec !== undefined) {
      return catalogSpec
    }
    return this.catalogService.findInstallItem(profile.downloadId)
  }

  getCatalogItem(catalogItemId: string): ModelCatalogItem | undefined {
    return this.catalogService.findMarketItem(catalogItemId)
  }

  async isCatalogItemInstalled(filesDir: string, item: ModelCatalogItem): Promise<boolean> {
    if (item.modelType === 'decision') {
      for (const file of item.files) {
        if (!await this.isInstalledFile(this.filePath(filesDir, item, file), file)) return false
      }
      return item.files.length > 0
    }
    const result = await this.preflightService.validate(
      `${modelInstallDirectory(filesDir, item)}/config.json`,
      item.supportsImage,
      item.files, item.modelType !== 'rerank'
    )
    return result.compatible
  }

  async isInstalled(filesDir: string, profile: ModelProfile): Promise<boolean> {
    const spec = this.getDownloadSpec(profile)
    if (spec === undefined) {
      const result = await this.preflightService.validate(
        profile.configPath ?? `${filesDir}/${profile.directoryName}/config.json`,
        profile.supportsImage
      )
      return result.compatible
    }
    const result = await this.preflightService.validate(
      `${filesDir}/${spec.directoryName}/config.json`,
      profile.supportsImage,
      spec.files
    )
    return result.compatible
  }

  async deleteInstalled(filesDir: string, profile: ModelProfile): Promise<boolean> {
    const spec = this.getDownloadSpec(profile)
    if (spec === undefined) {
      return false
    }
    const targetDir = modelInstallDirectory(filesDir, spec)
    if (!await this.exists(targetDir)) {
      return false
    }
    await this.deletePathRecursive(targetDir)
    return true
  }

  async clearPartialDownload(filesDir: string, spec: BuiltinModelDownloadSpec): Promise<number> {
    let removedBytes = 0
    for (let index = 0; index < spec.files.length; index++) {
      const targetPath = this.filePath(filesDir, spec, spec.files[index])
      removedBytes += await this.unlinkIfExists(`${targetPath}.part`)
      removedBytes += await this.unlinkIfExists(`${targetPath}.part.range`)
      await this.unlinkIfExists(`${targetPath}.part.meta`)
      await this.unlinkIfExists(`${targetPath}.part.meta.tmp`)
    }
    return removedBytes
  }

  async existingPartialDownloadBytes(filesDir: string, spec: BuiltinModelDownloadSpec): Promise<number> {
    let completedBytes = 0
    for (let index = 0; index < spec.files.length; index++) {
      const file = spec.files[index]
      const targetPath = this.filePath(filesDir, spec, file)
      if (await this.isInstalledFile(targetPath, file)) {
        completedBytes += file.sizeBytes
        continue
      }

      const tempPath = `${targetPath}.part`
      const checkpoint = await this.readCheckpoint(tempPath, file)
      completedBytes += checkpoint.bytes
      break
    }
    return Math.min(spec.totalBytes, completedBytes)
  }

  async install(
    context: common.UIAbilityContext,
    profile: ModelProfile,
    onProgress: ProgressCallback
  ): Promise<void> {
    const spec = this.getDownloadSpec(profile)
    if (spec === undefined) {
      return
    }
    await this.installSpec(context, spec, onProgress)
  }

  async installCatalogItem(
    context: common.UIAbilityContext,
    item: BuiltinModelDownloadSpec,
    onProgress: ProgressCallback
  ): Promise<void> {
    await this.installSpec(context, item, onProgress)
  }

  private async installSpec(
    context: common.UIAbilityContext,
    spec: BuiltinModelDownloadSpec,
    onProgress: ProgressCallback
  ): Promise<void> {
    this.cancelRequested = false
    await this.ensureDir(modelInstallDirectory(context.filesDir, spec))

    let completedBytes = 0
    for (let index = 0; index < spec.files.length; index++) {
      this.throwIfCanceled()
      const file = spec.files[index]
      const targetPath = this.filePath(context.filesDir, spec, file)
      if (await this.isInstalledFile(targetPath, file)) {
        await this.cleanupPartialFiles(targetPath)
        completedBytes += file.sizeBytes
        this.emitProgress(spec, file, completedBytes, 0, onProgress, '已存在，跳过')
        continue
      }

      const tempPath = `${targetPath}.part`
      const partialBytes = (await this.readCheckpoint(tempPath, file)).bytes
      this.emitProgress(spec, file, completedBytes, partialBytes, onProgress, partialBytes > 0 ? '继续下载' : '开始下载')
      try {
        await this.downloadFile(spec, file, tempPath, completedBytes, onProgress)
      } catch (err) {
        if (this.cancelRequested) {
          throw new Error('下载已取消')
        }
        throw err as Error
      }
      this.throwIfCanceled()
      if (!await this.isCompleteFile(tempPath, file.sizeBytes)) {
        throw new Error(`${file.relativePath} 下载不完整`)
      }
      if (await this.exists(targetPath)) {
        await fs.unlink(targetPath)
      }
      await fs.rename(tempPath, targetPath)
      await this.cleanupPartialFiles(targetPath)
      completedBytes += file.sizeBytes
      this.emitProgress(spec, file, completedBytes, 0, onProgress, '下载完成')
    }
    this.throwIfCanceled()
  }

  private async downloadFile(
    spec: BuiltinModelDownloadSpec,
    file: BuiltinModelFileSpec,
    targetPath: string,
    completedBytes: number,
    onProgress: ProgressCallback
  ): Promise<void> {
    let checkpoint = await this.readCheckpoint(targetPath, file)
    // Only checkpointed bytes may survive an interrupted merge or an old download.
    if (await this.exists(targetPath)) fs.truncateSync(targetPath, checkpoint.bytes)
    while (checkpoint.bytes < file.sizeBytes) {
      this.throwIfCanceled()
      const start = checkpoint.bytes
      const end = Math.min(file.sizeBytes - 1, start + DOWNLOAD_BLOCK_BYTES - 1)
      const rangePath = `${targetPath}.range`
      const request = http.createHttp()
      this.currentHttpRequest = request
      let responseHeaders: Record<string, string> = {}
      let receivedBytes = 0
      let writeError = ''
      const output = fs.openSync(rangePath, fs.OpenMode.WRITE_ONLY | fs.OpenMode.CREATE | fs.OpenMode.TRUNC)
      let outputClosed = false
      const headersCallback = (headers: Object): void => {
        responseHeaders = headers as Record<string, string>
      }
      const dataCallback = (chunk: ArrayBuffer): void => {
        if (this.cancelRequested || writeError.length > 0) return
        try {
          if (receivedBytes + chunk.byteLength > file.sizeBytes) throw new Error('响应超过文件大小')
          this.writeAll(output.fd, chunk)
          receivedBytes += chunk.byteLength
          this.emitProgress(spec, file, completedBytes, Math.min(file.sizeBytes, start + receivedBytes), onProgress, '下载中')
        } catch (error) {
          writeError = `${file.relativePath} 写入失败：${error}`
          request.destroy()
        }
      }
      const headers: Record<string, string> = {
        'User-Agent': 'Mozilla/5.0',
        'Accept': 'application/octet-stream',
        'Accept-Encoding': 'identity'
      }
      const pinned = /\/resolve\/[0-9a-f]{40}\//i.test(file.url)
      const useRange = start === 0 || pinned || checkpoint.validator.length > 0
      if (useRange) headers.Range = `bytes=${start}-${end}`
      if (start > 0 && checkpoint.validator.length > 0) headers['If-Range'] = checkpoint.validator
      request.on('headersReceive', headersCallback)
      request.on('dataReceive', dataCallback)
      try {
        const code = await request.requestInStream(file.url, {
          method: http.RequestMethod.GET, usingCache: false,
          readTimeout: 1000 * 60 * 30, connectTimeout: 1000 * 30, header: headers
        })
        this.throwIfCanceled()
        if (writeError.length > 0) throw new Error(writeError)
        const validator = this.responseValidator(responseHeaders)
        if (code === 206) {
          const range = /^bytes (\d+)-(\d+)\/(\d+)$/i.exec(this.headerValue(responseHeaders, 'content-range'))
          if (!useRange || range === null || Number(range[1]) !== start ||
            Number(range[2]) > end || Number(range[2]) < start || Number(range[3]) !== file.sizeBytes ||
            receivedBytes !== Number(range[2]) - start + 1) {
            throw new Error(`${file.relativePath} 续传范围或长度不匹配`)
          }
          if (checkpoint.validator.length > 0 && checkpoint.validator !== validator) {
            throw new Error(`${file.relativePath} 远端文件已变化，请重新下载`)
          }
        } else if (code !== 200 || receivedBytes !== file.sizeBytes) {
          throw new Error(`${file.relativePath} 下载响应无效：HTTP ${code}`)
        }
        fs.fsyncSync(output.fd)
        fs.closeSync(output)
        outputClosed = true
        if (code === 200 || start === 0) {
          await fs.rename(rangePath, targetPath)
        } else {
          await this.appendFile(rangePath, targetPath)
        }
        checkpoint = { url: file.url, size: file.sizeBytes,
          bytes: code === 200 ? receivedBytes : start + receivedBytes, validator, sha256: file.sha256 }
        await this.writeCheckpoint(targetPath, checkpoint)
      } finally {
        request.off('headersReceive', headersCallback)
        request.off('dataReceive', dataCallback)
        request.destroy()
        if (this.currentHttpRequest === request) this.currentHttpRequest = undefined
        if (!outputClosed) fs.closeSync(output)
        await this.unlinkIfExists(rangePath)
      }
    }
    if (file.sha256 !== undefined) {
      this.emitProgress(spec, file, completedBytes, checkpoint.bytes, onProgress, '正在校验')
      await this.verifyHash(targetPath, file.sha256)
    }
    this.emitProgress(spec, file, completedBytes, checkpoint.bytes, onProgress, '下载完成')
  }

  private headerValue(headers: Record<string, string>, name: string): string {
    const key = Object.keys(headers).find((key: string) => key.toLowerCase() === name)
    return key === undefined ? '' : String(headers[key]).trim()
  }

  private responseValidator(headers: Record<string, string>): string {
    const etag = this.headerValue(headers, 'etag')
    return etag.startsWith('"') && etag.endsWith('"') ? etag : this.headerValue(headers, 'last-modified')
  }

  private async readCheckpoint(path: string, file: BuiltinModelFileSpec): Promise<DownloadCheckpoint> {
    const empty: DownloadCheckpoint = { url: file.url, size: file.sizeBytes, bytes: 0, validator: '' }
    try {
      const saved = JSON.parse(await fs.readText(`${path}.meta`)) as DownloadCheckpoint
      const stat = await fs.stat(path)
      const pinned = /\/resolve\/[0-9a-f]{40}\//i.test(file.url)
      if (saved.url === file.url && saved.size === file.sizeBytes && saved.sha256 === file.sha256 &&
        Number.isSafeInteger(saved.bytes) && saved.bytes >= 0 && saved.bytes <= file.sizeBytes &&
        stat.isFile() && stat.size >= saved.bytes && typeof saved.validator === 'string' &&
        (pinned || saved.validator.length > 0 || saved.bytes === file.sizeBytes)) return saved
    } catch (_) {
    }
    return empty
  }

  private async writeCheckpoint(path: string, checkpoint: DownloadCheckpoint): Promise<void> {
    const temp = `${path}.meta.tmp`
    const output = fs.openSync(temp, fs.OpenMode.WRITE_ONLY | fs.OpenMode.CREATE | fs.OpenMode.TRUNC)
    try {
      const encoder = new util.TextEncoder()
      this.writeAll(output.fd, encoder.encodeInto(JSON.stringify(checkpoint)).buffer as ArrayBuffer)
      fs.fsyncSync(output.fd)
    } finally {
      fs.closeSync(output)
    }
    await fs.rename(temp, `${path}.meta`)
  }

  private writeAll(fd: number, bytes: ArrayBuffer): void {
    let offset = 0
    while (offset < bytes.byteLength) {
      const written = fs.writeSync(fd, bytes.slice(offset))
      if (written <= 0) throw new Error('文件写入未完成')
      offset += written
    }
  }

  private async verifyHash(path: string, expected: string): Promise<void> {
    const digest = cryptoFramework.createMd('SHA256')
    const input = fs.openSync(path, fs.OpenMode.READ_ONLY)
    const buffer = new ArrayBuffer(1024 * 1024)
    try {
      while (true) {
        this.throwIfCanceled()
        const count = fs.readSync(input.fd, buffer)
        if (count <= 0) break
        await digest.update({ data: new Uint8Array(buffer.slice(0, count)) })
      }
      const result = await digest.digest()
      const actual = Array.from(result.data).map((byte: number) => byte.toString(16).padStart(2, '0')).join('')
      if (actual !== expected.toLowerCase()) {
        fs.truncateSync(path, 0)
        await this.unlinkIfExists(`${path}.meta`)
        throw new Error('模型文件 SHA-256 校验失败，请重新下载')
      }
    } finally {
      fs.closeSync(input)
    }
  }

  private async appendFile(sourcePath: string, targetPath: string): Promise<void> {
    const input = fs.openSync(sourcePath, fs.OpenMode.READ_ONLY)
    const output = fs.openSync(targetPath, fs.OpenMode.WRITE_ONLY | fs.OpenMode.APPEND)
    const buffer = new ArrayBuffer(1024 * 1024)
    try {
      while (true) {
        const count = fs.readSync(input.fd, buffer)
        if (count <= 0) break
        this.writeAll(output.fd, buffer.slice(0, count))
      }
      fs.fsyncSync(output.fd)
    } finally {
      fs.closeSync(input)
      fs.closeSync(output)
    }
  }

  private throwIfCanceled(): void {
    if (this.cancelRequested) {
      throw new Error('下载已取消')
    }
  }

  private emitProgress(
    spec: BuiltinModelDownloadSpec,
    file: BuiltinModelFileSpec,
    completedBytes: number,
    currentFileBytes: number,
    onProgress: ProgressCallback,
    message: string
  ): void {
    const downloadedBytes = calculateDownloadedBytes(completedBytes, currentFileBytes, spec.totalBytes)
    const progress = calculateDownloadProgress(downloadedBytes, spec.totalBytes)
    const progressInfo: BuiltinModelInstallProgress = {
      modelName: spec.displayName,
      fileName: file.relativePath,
      downloadedBytes,
      totalBytes: spec.totalBytes,
      progress,
      message
    }
    onProgress(progressInfo)
  }

  private filePath(filesDir: string, spec: BuiltinModelDownloadSpec, file: BuiltinModelFileSpec): string {
    return `${modelInstallDirectory(filesDir, spec)}/${file.relativePath}`
  }

  private async ensureDir(path: string): Promise<void> {
    if (await this.exists(path)) {
      return
    }
    await fs.mkdir(path, true)
  }

  private async isCompleteFile(path: string, sizeBytes: number): Promise<boolean> {
    if (!await this.exists(path)) {
      return false
    }
    const stat = await fs.stat(path)
    return stat.isFile() && stat.size === sizeBytes
  }

  private async isInstalledFile(path: string, file: BuiltinModelFileSpec): Promise<boolean> {
    if (file.relativePath === 'llm_config.json') {
      return this.isExistingFile(path)
    }
    return this.isCompleteFile(path, file.sizeBytes)
  }

  private async isExistingFile(path: string): Promise<boolean> {
    if (!await this.exists(path)) {
      return false
    }
    const stat = await fs.stat(path)
    return stat.isFile() && stat.size > 0
  }

  private async exists(path: string): Promise<boolean> {
    try {
      return await fs.access(path)
    } catch (_) {
      return false
    }
  }

  private async unlinkIfExists(path: string): Promise<number> {
    if (!await this.exists(path)) {
      return 0
    }
    const stat = await fs.stat(path)
    if (!stat.isFile()) {
      return 0
    }
    const size = stat.size
    await fs.unlink(path)
    return size
  }

  private async cleanupPartialFiles(targetPath: string): Promise<void> {
    await this.unlinkIfExists(`${targetPath}.part`)
    await this.unlinkIfExists(`${targetPath}.part.range`)
    await this.unlinkIfExists(`${targetPath}.part.meta`)
    await this.unlinkIfExists(`${targetPath}.part.meta.tmp`)
  }

  private async deletePathRecursive(path: string): Promise<void> {
    const stat = await fs.stat(path)
    if (stat.isFile()) {
      await fs.unlink(path)
      return
    }
    if (!stat.isDirectory()) {
      return
    }
    const names = await fs.listFile(path)
    for (let index = 0; index < names.length; index++) {
      await this.deletePathRecursive(`${path}/${names[index]}`)
    }
    await fs.rmdir(path)
  }
}
