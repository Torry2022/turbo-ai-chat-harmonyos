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
  // Normalize decimal underscores before splitting ordinary separators.
  const normalized = name.trim().replace(/([0-9])_([0-9]+[bmk])/gi, '$1.$2')
  let tokens = normalized.split(/[-_\s]+/).filter((token: string) => token.length > 0 && token.toLowerCase() !== 'mnn')
  const hasParameters = tokens.some((token: string) => isExplicitParameterToken(token))
  if (hasParameters) {
    while (tokens.length > 1 && /^(it|[0-9]{4,8})$/i.test(tokens[tokens.length - 1])) tokens.pop()
  }
  if (tokens.join('-').length <= 32) return tokens.join('-')

  // Remove task suffixes before sacrificing identity or quantization information.
  tokens = tokens.filter((token: string, index: number) => index === 0 || !/^(instruct|chat|it)$/i.test(token))
  if (tokens.join('-').length <= 32) return tokens.join('-')
  for (let index = tokens.length - 1; index > 0 && tokens.join('-').length > 32; index--) {
    if (!isShortNameIdentityToken(tokens[index])) tokens.splice(index, 1)
  }
  const suffix = tokens.slice(1).join('-')
  const budget = 32 - suffix.length - (suffix.length > 0 ? 1 : 0)
  if (budget > 0) return tokens[0].substring(0, budget) + (suffix.length > 0 ? '-' + suffix : '')
  // Unusually long collections of identity tokens cannot all fit; do not invent a name.
  return tokens.join('-').substring(0, 32)
}

export function resolveImportedShortName(name: string, savedShortName: string): string {
  // Old manifests do not record whether the user edited the name. Preserve it.
  return savedShortName.trim().length > 0 ? savedShortName : importedModelShortName(name)
}

function isExplicitParameterToken(token: string): boolean {
  return /^(?:[EA])?[0-9]+(?:\.[0-9]+)?[BMK]$/i.test(token)
}

function isShortNameIdentityToken(token: string): boolean {
  return isExplicitParameterToken(token) ||
    /^[0-9]+(?:\.[0-9]+)*$/.test(token) ||
    /^v[0-9]+(?:\.[0-9]+)*$/i.test(token) ||
    /^(VL|V|R[0-9]+|Coder|Thinking|Reasoning|INT[0-9]+|BF[0-9]+|FP[0-9]+|Q[0-9]+|K|S|M)$/i.test(token)
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
