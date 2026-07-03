import { common } from '@kit.AbilityKit'
import fs from '@ohos.file.fs'
import http from '@ohos.net.http'
import {
  BuiltinModelDownloadSpec,
  BuiltinModelFileSpec,
  BuiltinModelInstallProgress,
  ModelCatalogItem,
  findBuiltinModelDownloadSpec,
  findModelCatalogItem
} from '../models/BuiltinModelDownloadTypes'
import { ModelProfile } from '../models/ModelProfile'
import { calculateDownloadedBytes, calculateDownloadProgress } from '../utils/downloadProgress'
import { ModelDirectoryPreflightService } from './ModelDirectoryPreflightService'

type ProgressCallback = (progress: BuiltinModelInstallProgress) => void

interface DownloadRequestHeader {
  'User-Agent': string
  'Accept': string
  'Range'?: string
}

export class BuiltinModelInstallService {
  private cancelRequested: boolean = false
  private currentHttpRequest?: http.HttpRequest
  private preflightService: ModelDirectoryPreflightService = new ModelDirectoryPreflightService()

  cancelInstall(): void {
    this.cancelRequested = true
    if (this.currentHttpRequest !== undefined) {
      this.currentHttpRequest.destroy()
    }
  }

  getDownloadSpec(profile: ModelProfile): BuiltinModelDownloadSpec | undefined {
    const catalogSpec = findModelCatalogItem(profile.catalogItemId)
    if (catalogSpec !== undefined) {
      return catalogSpec
    }
    return findBuiltinModelDownloadSpec(profile.downloadId)
  }

  getCatalogItem(catalogItemId: string): ModelCatalogItem | undefined {
    return findModelCatalogItem(catalogItemId)
  }

  async isCatalogItemInstalled(filesDir: string, item: ModelCatalogItem): Promise<boolean> {
    const result = await this.preflightService.validate(
      `${filesDir}/${item.directoryName}/config.json`,
      item.supportsImage,
      item.files
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
    const targetDir = `${filesDir}/${spec.directoryName}`
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
      if (await this.isCompleteFile(tempPath, file.sizeBytes)) {
        completedBytes += file.sizeBytes
        continue
      }
      const partialBytes = await this.partialFileSize(tempPath, file.sizeBytes)
      const rangeBytes = await this.partialRangeFileSize(`${tempPath}.range`, file.sizeBytes - partialBytes)
      completedBytes += partialBytes + rangeBytes
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
    await this.ensureDir(`${context.filesDir}/${spec.directoryName}`)

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
      if (await this.isCompleteFile(tempPath, file.sizeBytes)) {
        if (await this.exists(targetPath)) {
          await fs.unlink(targetPath)
        }
        await fs.rename(tempPath, targetPath)
        await this.cleanupPartialFiles(targetPath)
        completedBytes += file.sizeBytes
        this.emitProgress(spec, file, completedBytes, 0, onProgress, '下载完成')
        continue
      }
      if (await this.isOversizedFile(tempPath, file.sizeBytes)) {
        await fs.unlink(tempPath)
        await this.unlinkIfExists(`${tempPath}.range`)
      }
      await this.mergePartialRangeIfPresent(tempPath, `${tempPath}.range`, file.sizeBytes)
      if (await this.isCompleteFile(tempPath, file.sizeBytes)) {
        if (await this.exists(targetPath)) {
          await fs.unlink(targetPath)
        }
        await fs.rename(tempPath, targetPath)
        await this.cleanupPartialFiles(targetPath)
        completedBytes += file.sizeBytes
        this.emitProgress(spec, file, completedBytes, 0, onProgress, '下载完成')
        continue
      }
      const partialBytes = await this.partialFileSize(tempPath, file.sizeBytes)
      this.emitProgress(spec, file, completedBytes, partialBytes, onProgress, partialBytes > 0 ? '继续下载' : '开始下载')
      try {
        await this.downloadFile(spec, file, tempPath, completedBytes, onProgress)
      } catch (err) {
        if (this.cancelRequested) {
          throw new Error('下载已取消')
        }
        throw new Error(`${err}`)
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
    const existingBytes = await this.partialFileSize(targetPath, file.sizeBytes)
    const rangeChunkPath = `${targetPath}.range`
    if (await this.exists(rangeChunkPath)) {
      await fs.unlink(rangeChunkPath)
    }

    const httpRequest = http.createHttp()
    this.currentHttpRequest = httpRequest
    const outputPath = existingBytes > 0 ? rangeChunkPath : targetPath
    const output = fs.openSync(outputPath, fs.OpenMode.WRITE_ONLY | fs.OpenMode.CREATE | fs.OpenMode.TRUNC)
    let outputClosed = false
    let receivedBytes = 0
    let writeErrorMessage = ''

    const dataCallback = (chunk: ArrayBuffer): void => {
      if (this.cancelRequested) {
        return
      }
      if (writeErrorMessage.length > 0) {
        return
      }
      try {
        fs.writeSync(output.fd, chunk)
        receivedBytes += chunk.byteLength
        this.emitProgress(spec, file, completedBytes, existingBytes + receivedBytes, onProgress, '下载中')
      } catch (err) {
        writeErrorMessage = `${file.relativePath} 写入失败：${err}`
      }
    }

    const requestHeader: DownloadRequestHeader = {
      'User-Agent': 'Mozilla/5.0',
      'Accept': 'application/octet-stream'
    }
    if (existingBytes > 0) {
      requestHeader.Range = `bytes=${existingBytes}-`
    }
    const requestOptions: http.HttpRequestOptions = {
      method: http.RequestMethod.GET,
      usingCache: false,
      readTimeout: 1000 * 60 * 30,
      connectTimeout: 1000 * 30,
      header: requestHeader
    }

    httpRequest.on('dataReceive', dataCallback)
    try {
      this.throwIfCanceled()
      const responseCode = await httpRequest.requestInStream(file.url, requestOptions)
      this.throwIfCanceled()
      if (writeErrorMessage.length > 0) {
        throw new Error(writeErrorMessage)
      }
      if (responseCode < 200 || responseCode >= 300) {
        throw new Error(`${file.relativePath} 下载失败：HTTP ${responseCode}`)
      }
      fs.closeSync(output)
      outputClosed = true
      if (existingBytes > 0) {
        if (responseCode === 206) {
          await this.appendFile(rangeChunkPath, targetPath)
          await fs.unlink(rangeChunkPath)
        } else {
          if (await this.exists(targetPath)) {
            await fs.unlink(targetPath)
          }
          await fs.rename(rangeChunkPath, targetPath)
        }
      }
      this.emitProgress(spec, file, completedBytes, await this.partialFileSize(targetPath, file.sizeBytes), onProgress, '下载完成')
    } finally {
      httpRequest.off('dataReceive', dataCallback)
      httpRequest.destroy()
      if (this.currentHttpRequest === httpRequest) {
        this.currentHttpRequest = undefined
      }
      if (!outputClosed) {
        fs.closeSync(output)
      }
    }
  }

  private async partialFileSize(path: string, expectedSize: number): Promise<number> {
    if (!await this.exists(path)) {
      return 0
    }
    const stat = await fs.stat(path)
    if (!stat.isFile()) {
      return 0
    }
    if (stat.size >= expectedSize) {
      return stat.size === expectedSize ? expectedSize : 0
    }
    return stat.size
  }

  private async partialRangeFileSize(path: string, maxSize: number): Promise<number> {
    if (maxSize <= 0 || !await this.exists(path)) {
      return 0
    }
    const stat = await fs.stat(path)
    if (!stat.isFile()) {
      return 0
    }
    return stat.size > maxSize ? 0 : stat.size
  }

  private async appendFile(sourcePath: string, targetPath: string): Promise<void> {
    const input = fs.openSync(sourcePath, fs.OpenMode.READ_ONLY)
    const output = fs.openSync(targetPath, fs.OpenMode.WRITE_ONLY | fs.OpenMode.CREATE | fs.OpenMode.APPEND)
    const buffer = new ArrayBuffer(1024 * 1024)
    try {
      while (true) {
        const readBytes = fs.readSync(input.fd, buffer)
        if (readBytes <= 0) {
          break
        }
        fs.writeSync(output.fd, buffer, { length: readBytes })
      }
    } finally {
      fs.closeSync(input)
      fs.closeSync(output)
    }
  }

  private async mergePartialRangeIfPresent(targetPath: string, rangePath: string, expectedSize: number): Promise<void> {
    if (!await this.exists(rangePath)) {
      return
    }
    const partialBytes = await this.partialFileSize(targetPath, expectedSize)
    const rangeBytes = await this.partialRangeFileSize(rangePath, expectedSize - partialBytes)
    if (partialBytes <= 0 || rangeBytes <= 0 || partialBytes + rangeBytes > expectedSize) {
      await this.unlinkIfExists(rangePath)
      return
    }
    await this.appendFile(rangePath, targetPath)
    await this.unlinkIfExists(rangePath)
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
    return `${filesDir}/${spec.directoryName}/${file.relativePath}`
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

  private async isOversizedFile(path: string, sizeBytes: number): Promise<boolean> {
    if (!await this.exists(path)) {
      return false
    }
    const stat = await fs.stat(path)
    return stat.isFile() && stat.size > sizeBytes
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
