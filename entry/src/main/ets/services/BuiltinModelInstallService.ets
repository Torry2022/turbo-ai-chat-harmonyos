import { common } from '@kit.AbilityKit'
import fs from '@ohos.file.fs'
import http from '@ohos.net.http'
import {
  BuiltinModelDownloadSpec,
  BuiltinModelFileSpec,
  BuiltinModelInstallProgress,
  findBuiltinModelDownloadSpec
} from '../models/BuiltinModelDownloadTypes'
import { ModelProfile } from '../models/ModelProfile'

type ProgressCallback = (progress: BuiltinModelInstallProgress) => void

interface DownloadRequestHeader {
  'User-Agent': string
  'Accept': string
}

export class BuiltinModelInstallService {
  getDownloadSpec(profile: ModelProfile): BuiltinModelDownloadSpec | undefined {
    return findBuiltinModelDownloadSpec(profile.downloadId)
  }

  async isInstalled(filesDir: string, profile: ModelProfile): Promise<boolean> {
    const spec = this.getDownloadSpec(profile)
    if (spec === undefined) {
      return true
    }
    for (let index = 0; index < spec.files.length; index++) {
      const targetPath = this.filePath(filesDir, spec, spec.files[index])
      if (!await this.isCompleteFile(targetPath, spec.files[index].sizeBytes)) {
        return false
      }
    }
    return true
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
    await this.ensureDir(`${context.filesDir}/${spec.directoryName}`)

    let completedBytes = 0
    for (let index = 0; index < spec.files.length; index++) {
      const file = spec.files[index]
      const targetPath = this.filePath(context.filesDir, spec, file)
      if (await this.isCompleteFile(targetPath, file.sizeBytes)) {
        completedBytes += file.sizeBytes
        this.emitProgress(spec, file, completedBytes, 0, onProgress, '已存在，跳过')
        continue
      }

      const tempPath = `${targetPath}.part`
      if (await this.exists(tempPath)) {
        await fs.unlink(tempPath)
      }
      this.emitProgress(spec, file, completedBytes, 0, onProgress, '开始下载')
      await this.downloadFile(spec, file, tempPath, completedBytes, onProgress)
      if (!await this.isCompleteFile(tempPath, file.sizeBytes)) {
        throw new Error(`${file.relativePath} 下载不完整`)
      }
      if (await this.exists(targetPath)) {
        await fs.unlink(targetPath)
      }
      await fs.rename(tempPath, targetPath)
      completedBytes += file.sizeBytes
      this.emitProgress(spec, file, completedBytes, 0, onProgress, '下载完成')
    }
  }

  private async downloadFile(
    spec: BuiltinModelDownloadSpec,
    file: BuiltinModelFileSpec,
    targetPath: string,
    completedBytes: number,
    onProgress: ProgressCallback
  ): Promise<void> {
    const httpRequest = http.createHttp()
    const output = fs.openSync(targetPath, fs.OpenMode.WRITE_ONLY | fs.OpenMode.CREATE | fs.OpenMode.TRUNC)
    let receivedBytes = 0
    let writeErrorMessage = ''

    const dataCallback = (chunk: ArrayBuffer): void => {
      if (writeErrorMessage.length > 0) {
        return
      }
      try {
        fs.writeSync(output.fd, chunk)
        receivedBytes += chunk.byteLength
        this.emitProgress(spec, file, completedBytes, receivedBytes, onProgress, '下载中')
      } catch (err) {
        writeErrorMessage = `${file.relativePath} 写入失败：${err}`
      }
    }

    const requestHeader: DownloadRequestHeader = {
      'User-Agent': 'Mozilla/5.0',
      'Accept': 'application/octet-stream'
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
      const responseCode = await httpRequest.requestInStream(file.url, requestOptions)
      if (writeErrorMessage.length > 0) {
        throw new Error(writeErrorMessage)
      }
      if (responseCode < 200 || responseCode >= 300) {
        throw new Error(`${file.relativePath} 下载失败：HTTP ${responseCode}`)
      }
      this.emitProgress(spec, file, completedBytes, receivedBytes, onProgress, '下载完成')
    } finally {
      httpRequest.off('dataReceive', dataCallback)
      httpRequest.destroy()
      fs.closeSync(output)
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
    const downloadedBytes = Math.min(spec.totalBytes, completedBytes + currentFileBytes)
    const progress = spec.totalBytes > 0 ? Math.round(downloadedBytes / spec.totalBytes * 1000) / 10 : 0
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

  private async exists(path: string): Promise<boolean> {
    try {
      return await fs.access(path)
    } catch (_) {
      return false
    }
  }
}
