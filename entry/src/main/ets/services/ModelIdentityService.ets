import fs from '@ohos.file.fs'
import { util } from '@kit.ArkTS'
import cryptoFramework from '@ohos.security.cryptoFramework'

export interface ModelIdentity {
  configurationSha256?: string
  fileManifestSha256?: string
}

interface ModelFileMetadata {
  path: string
  size: number
  modifiedAt: number
}

// The file manifest identifies directory metadata. It does not claim to hash weight contents.
export class ModelIdentityService {
  async read(configPath: string): Promise<ModelIdentity> {
    const normalized = configPath.replace(/\\/g, '/')
    const root = normalized.substring(0, normalized.lastIndexOf('/'))
    const identity: ModelIdentity = {}
    if (root.length === 0) return identity
    try {
      const config = await fs.readText(normalized)
      const llmConfig = await fs.readText(`${root}/llm_config.json`)
      identity.configurationSha256 = await this.digest(JSON.stringify([config, llmConfig]))
    } catch (_) {}
    try {
      const files = await this.files(root, root)
      files.sort((left: ModelFileMetadata, right: ModelFileMetadata) =>
        left.path < right.path ? -1 : left.path > right.path ? 1 : 0)
      if (files.length > 0) identity.fileManifestSha256 = await this.digest(JSON.stringify(files))
    } catch (_) {}
    return identity
  }

  private async files(root: string, directory: string): Promise<ModelFileMetadata[]> {
    const result: ModelFileMetadata[] = []
    for (const name of await fs.listFile(directory)) {
      if (name.endsWith('.part') || name.endsWith('.part.meta') || name.endsWith('.part.range') ||
        name.endsWith('.tmp') || name === '.git') continue
      const path = `${directory}/${name}`
      const stat = await fs.stat(path)
      if (stat.isDirectory()) {
        const children = await this.files(root, path)
        children.forEach((file: ModelFileMetadata) => result.push(file))
      } else if (stat.isFile()) {
        result.push({ path: path.substring(root.length + 1), size: stat.size, modifiedAt: stat.mtime })
      }
    }
    return result
  }

  private async digest(text: string): Promise<string> {
    const digest = cryptoFramework.createMd('SHA256')
    await digest.update({ data: new util.TextEncoder().encodeInto(text) })
    const result = await digest.digest()
    return Array.from(result.data).map((byte: number) => byte.toString(16).padStart(2, '0')).join('')
  }
}
