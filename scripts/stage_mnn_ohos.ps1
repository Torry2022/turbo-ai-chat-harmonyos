param(
  [string]$MnnRoot = "$PSScriptRoot\..\.codex_mnn_source_3.6.0",
  [string]$BuildDir = "$PSScriptRoot\..\.codex_mnn_build_3.6.0",
  [string]$HarmonyNativeHome = $env:HARMONY_NATIVE_HOME
)

$ErrorActionPreference = 'Stop'
$expectedCommit = 'cc20f672af9e177e2fa338c332dc097de2fc9264'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$MnnRoot = [IO.Path]::GetFullPath($MnnRoot)
$BuildDir = [IO.Path]::GetFullPath($BuildDir)
$library = Join-Path $BuildDir 'libMNN.so'
$libraryOutput = Join-Path $root 'entry\src\main\libs\arm64-v8a\libMNN.so'
$includeOutput = Join-Path $root 'third_party\mnn\include'

$actualCommit = (& git -C $MnnRoot rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or $actualCommit -ne $expectedCommit) {
  throw "Expected MNN $expectedCommit, found $actualCommit"
}
if (-not (Test-Path $library)) { throw "Missing $library" }

New-Item -ItemType Directory -Force -Path (Split-Path $libraryOutput), $includeOutput | Out-Null
Copy-Item -LiteralPath $library -Destination $libraryOutput -Force

$mnnHeaders = Join-Path $includeOutput 'MNN'
$llmHeaders = Join-Path $includeOutput 'llm'
if (Test-Path $mnnHeaders) { Remove-Item -LiteralPath $mnnHeaders -Recurse -Force }
if (Test-Path $llmHeaders) { Remove-Item -LiteralPath $llmHeaders -Recurse -Force }
Copy-Item -Path (Join-Path $MnnRoot 'include\MNN') -Destination $mnnHeaders -Recurse
Copy-Item -Path (Join-Path $MnnRoot 'transformers\llm\engine\include\llm') -Destination $llmHeaders -Recurse

$sdkInfo = @{}
if ($HarmonyNativeHome) {
  if (Test-Path (Join-Path $HarmonyNativeHome 'native\oh-uni-package.json')) {
    $HarmonyNativeHome = Join-Path $HarmonyNativeHome 'native'
  }
  $sdkManifest = Join-Path $HarmonyNativeHome 'oh-uni-package.json'
  if (Test-Path $sdkManifest) {
    $sdkInfo = Get-Content -Raw $sdkManifest | ConvertFrom-Json
  }
}
$manifest = [ordered]@{
  version = '3.6.0'
  commit = $expectedCommit
  architecture = 'arm64-v8a'
  stl = 'c++_shared'
  ohosPlatformLevel = 9
  harmonySdkApiVersion = $sdkInfo.apiVersion
  harmonySdkVersion = $sdkInfo.version
  features = [ordered]@{
    sharedLibraries = $true
    llm = $true
    llmOmni = $true
    lowMemory = $true
    transformerFuse = $true
    arm82 = $true
    opencv = $true
    imageCodecs = $true
    opencl = $false
  }
  libMnnSha256 = (Get-FileHash $libraryOutput -Algorithm SHA256).Hash.ToLowerInvariant()
}
$manifest | ConvertTo-Json | Set-Content -Encoding utf8 (Join-Path $root 'third_party\mnn\BUILD_INFO.json')
Write-Output 'Staged MNN 3.6.0 runtime and headers.'
