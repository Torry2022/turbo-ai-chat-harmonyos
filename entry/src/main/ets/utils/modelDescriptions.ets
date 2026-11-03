export interface ModelDescriptionEntry {
  repo: string
  description: string
  sources: string[]
}

export interface ModelDescriptionManifest {
  schemaVersion: number
  descriptionVersion: number
  publishedAt: string
  entries: ModelDescriptionEntry[]
}

export function parseModelDescriptions(text: string): ModelDescriptionManifest {
  const manifest = JSON.parse(text) as ModelDescriptionManifest
  if (manifest.schemaVersion !== 1 || !Number.isSafeInteger(manifest.descriptionVersion) ||
    manifest.descriptionVersion < 1 || typeof manifest.publishedAt !== 'string' ||
    !Number.isFinite(Date.parse(manifest.publishedAt)) || !Array.isArray(manifest.entries)) {
    throw new Error('模型描述目录格式无效')
  }
  const repos: string[] = []
  for (const entry of manifest.entries) {
    if (typeof entry?.repo !== 'string' || !/^[A-Za-z0-9_-][A-Za-z0-9_.-]*\/[A-Za-z0-9_-][A-Za-z0-9_.-]*$/.test(entry.repo) ||
      repos.includes(entry.repo.toLowerCase()) || typeof entry.description !== 'string' ||
      entry.description.trim().length === 0 || entry.description.length > 80 || /[\r\n]/.test(entry.description) ||
      !Array.isArray(entry.sources) || entry.sources.length === 0 ||
      entry.sources.some((url: string) => typeof url !== 'string' || !url.startsWith('https://'))) {
      throw new Error('模型描述条目无效')
    }
    repos.push(entry.repo.toLowerCase())
  }
  return manifest
}

export function descriptionRepo(sourceUrl: string): string {
  const prefix = 'https://modelscope.cn/models/'
  return sourceUrl.startsWith(prefix) ? sourceUrl.substring(prefix.length).toLowerCase() : ''
}
