import fs from '@ohos.file.fs'
import { BuiltinModelFileSpec } from '../models/BuiltinModelDownloadTypes'
import {
  ExpectedModelFile,
  ModelDirectorySnapshot,
  ModelFileSnapshot,
  ModelPreflightResult,
  validateModelDirectorySnapshot
} from '../utils/modelCompatibility'
import { MnnTemplateService } from './MnnTemplateService'

export class ModelDirectoryPreflightService {
  async validate(
    configPath: string,
    supportsImage: boolean,
    expectedFiles: BuiltinModelFileSpec[] = []
  ): Promise<ModelPreflightResult> {
    const modelRoot = this.modelRoot(configPath)
    const files = modelRoot.length > 0 ? await this.listFilesRecursive(modelRoot, modelRoot) : []
    const configText = await this.readTextIfExists(configPath)
    const llmConfigPath = modelRoot.length > 0 ? `${modelRoot}/llm_config.json` : ''
    let llmConfigText = await this.readTextIfExists(llmConfigPath)
    const expected = expectedFiles.map((file: BuiltinModelFileSpec): ExpectedModelFile => {
      return {
        relativePath: file.relativePath,
        sizeBytes: file.relativePath === 'llm_config.json' ? 0 : file.sizeBytes
      }
    })
    let result = validateModelDirectorySnapshot({
      configText,
      llmConfigText,
      files,
      expectedFiles: expected,
      supportsImage
    } as ModelDirectorySnapshot)

    if (result.compatible && result.legacyTemplate) {
      await MnnTemplateService.ensureChatMessagesTemplate(configPath)
      llmConfigText = await this.readTextIfExists(llmConfigPath)
      result = validateModelDirectorySnapshot({
        configText,
        llmConfigText,
        files,
        expectedFiles: expected,
        supportsImage
      } as ModelDirectorySnapshot)
    }
    return result
  }

  async requireCompatible(
    configPath: string,
    supportsImage: boolean,
    expectedFiles: BuiltinModelFileSpec[] = []
  ): Promise<void> {
    const result = await this.validate(configPath, supportsImage, expectedFiles)
    if (!result.compatible) {
      throw new Error(result.message)
    }
  }

  private modelRoot(configPath: string): string {
    const normalized = configPath.replace(/\\/g, '/')
    const suffix = '/config.json'
    if (!normalized.toLowerCase().endsWith(suffix)) {
      return ''
    }
    return normalized.substring(0, normalized.length - suffix.length)
  }

  private async readTextIfExists(path: string): Promise<string> {
    if (path.length <= 0 || !await this.exists(path)) {
      return ''
    }
    try {
      return await fs.readText(path)
    } catch (_) {
      return ''
    }
  }

  private async listFilesRecursive(root: string, current: string): Promise<ModelFileSnapshot[]> {
    if (!await this.exists(current)) {
      return []
    }
    const result: ModelFileSnapshot[] = []
    const names = await fs.listFile(current)
    for (let index = 0; index < names.length; index++) {
      const path = `${current}/${names[index]}`
      const stat = await fs.stat(path)
      if (stat.isDirectory()) {
        const children = await this.listFilesRecursive(root, path)
        children.forEach((child: ModelFileSnapshot) => result.push(child))
      } else if (stat.isFile()) {
        result.push({
          relativePath: path.substring(root.length + 1),
          sizeBytes: stat.size
        })
      }
    }
    return result
  }

  private async exists(path: string): Promise<boolean> {
    try {
      return await fs.access(path)
    } catch (_) {
      return false
    }
  }
}
