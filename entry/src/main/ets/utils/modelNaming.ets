import { ModelProfile } from '../models/ModelProfile'

export function stripMnnSuffix(name: string): string {
  let normalized = name.trim()
  const lowerName = normalized.toLowerCase()
  if (lowerName.endsWith('-mnn') || lowerName.endsWith('_mnn') || lowerName.endsWith(' mnn')) {
    normalized = normalized.substring(0, normalized.length - 4)
  }
  return normalized.trim()
}

export function importedModelShortName(name: string): string {
  const normalized = stripMnnSuffix(name)
  const tokens = normalized.split('-').filter((token: string) => token.length > 0)
  if (tokens.length <= 1) {
    return normalized.length > 32 ? normalized.substring(0, 32) : normalized
  }

  let parameterIndex = -1
  for (let index = 1; index < tokens.length; index++) {
    if (isParameterToken(tokens[index])) {
      parameterIndex = index
      break
    }
  }
  if (parameterIndex < 0) {
    return normalized.length > 32 ? normalized.substring(0, 32) : normalized
  }

  let endIndex = tokens.length
  while (endIndex > parameterIndex + 1 && isTrailingModelMetadataToken(tokens[endIndex - 1])) {
    endIndex--
  }
  const shortName = tokens.slice(0, endIndex).join('-')
  if (shortName.length <= 32) {
    return shortName
  }

  const nameWithParameter = tokens.slice(0, parameterIndex + 1).join('-')
  if (nameWithParameter.length <= 32) {
    return nameWithParameter
  }
  const parameterToken = tokens[parameterIndex]
  const familyName = tokens.slice(0, parameterIndex).join('-')
  return `${familyName.substring(0, 31 - parameterToken.length)}-${parameterToken}`
}

export function isLegacyFamilyOnlyImportedShortName(name: string, shortName: string): boolean {
  const tokens = stripMnnSuffix(name).split('-').filter((token: string) => token.length > 0)
  if (tokens.length <= 1 || shortName !== tokens[0]) {
    return false
  }
  return tokens.some((token: string, index: number) => index > 0 && isParameterToken(token))
}

export function legacyImportedModelShortName(name: string): string {
  const normalized = name.trim()
  const tokens = normalized.split('-').filter((token: string) => token.length > 0)
  if (tokens.length <= 1) {
    return normalized
  }
  for (let index = 1; index < tokens.length; index++) {
    if (isParameterToken(tokens[index])) {
      return `${tokens[0]}-${tokens[index]}`
    }
  }
  return tokens[0]
}

export function uniqueModelName(baseName: string, profiles: ModelProfile[], selfId: string = ''): string {
  const name = baseName.length > 0 ? baseName : 'Imported MNN Model'
  let candidate = name
  let suffix = 2
  while (profiles.some((profile: ModelProfile) => profile.id !== selfId && profile.name === candidate)) {
    candidate = `${name} ${suffix}`
    suffix++
  }
  return candidate
}

export function uniqueModelShortName(baseName: string, profiles: ModelProfile[], selfId: string = ''): string {
  const name = baseName.length > 0 ? baseName : 'Imported'
  let candidate = name
  let suffix = 2
  while (profiles.some((profile: ModelProfile) => profile.id !== selfId && profile.shortName === candidate)) {
    candidate = `${name} ${suffix}`
    suffix++
  }
  return candidate
}

export function uniqueModelId(baseId: string, profiles: ModelProfile[]): string {
  const id = baseId.length > 0 ? baseId : 'imported-model'
  let candidate = id
  let suffix = 2
  while (profiles.some((profile: ModelProfile) => profile.id === candidate)) {
    candidate = `${id}-${suffix}`
    suffix++
  }
  return candidate
}

export function safeModelId(name: string): string {
  const normalized = name.trim().toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '')
  return normalized.length > 0 ? normalized : 'model'
}

function isParameterToken(token: string): boolean {
  return /^[0-9]+([._][0-9]+)?[BMK]?$/i.test(token) || /^E[0-9]+B$/i.test(token)
}

function isTrailingModelMetadataToken(token: string): boolean {
  const lowerToken = token.toLowerCase()
  return lowerToken === 'it' ||
    /^[0-9]{4,8}$/.test(lowerToken) ||
    /^v[0-9]+(\.[0-9]+)*$/.test(lowerToken)
}
