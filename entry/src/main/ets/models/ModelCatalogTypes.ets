import {
  CatalogRuntimeSpec,
  ModelCatalogItem
} from './BuiltinModelDownloadTypes'

export interface RemoteCatalogSource {
  type: string
  repo: string
  revision: string
}

export interface RemoteCatalogFile {
  relativePath: string
  sizeBytes: number
}

export interface RemoteCatalogItem {
  id: string
  directoryName: string
  displayName: string
  shortName: string
  description: string
  provider: string
  supportsImage: boolean
  capabilities: string[]
  source: RemoteCatalogSource
  files: RemoteCatalogFile[]
  runtime?: CatalogRuntimeSpec
}

export interface RemoteModelCatalogManifest {
  schemaVersion: number
  catalogVersion: number
  publishedAt: string
  hiddenIds: string[]
  items: RemoteCatalogItem[]
}

export interface InstalledCatalogManifest {
  schemaVersion: number
  items: ModelCatalogItem[]
}

export interface ModelCatalogLoadResult {
  source: string
  catalogVersion: number
  publishedAt: string
  message: string
}

export interface ModelCatalogRefreshResult extends ModelCatalogLoadResult {
  updated: boolean
}
