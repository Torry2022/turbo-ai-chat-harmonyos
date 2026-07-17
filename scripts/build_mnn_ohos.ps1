param(
  [string]$MnnRoot = "$PSScriptRoot\..\.codex_mnn_source_3.6.0",
  [string]$BuildDir = "$PSScriptRoot\..\.codex_mnn_build_3.6.0",
  [string]$HarmonyNativeHome = $env:HARMONY_NATIVE_HOME,
  [int]$Jobs = [Environment]::ProcessorCount
)

$ErrorActionPreference = 'Stop'
$expectedCommit = 'cc20f672af9e177e2fa338c332dc097de2fc9264'
$MnnRoot = [IO.Path]::GetFullPath($MnnRoot)
$BuildDir = [IO.Path]::GetFullPath($BuildDir)

if (-not $HarmonyNativeHome -and $env:HARMONY_HOME) {
  $HarmonyNativeHome = $env:HARMONY_HOME
}
if ($HarmonyNativeHome -and (Test-Path (Join-Path $HarmonyNativeHome 'native\build\cmake\ohos.toolchain.cmake'))) {
  $HarmonyNativeHome = Join-Path $HarmonyNativeHome 'native'
}
if (-not $HarmonyNativeHome -or -not (Test-Path (Join-Path $HarmonyNativeHome 'build\cmake\ohos.toolchain.cmake'))) {
  throw 'Set HARMONY_NATIVE_HOME to the HarmonyOS native SDK directory.'
}
if (-not (Test-Path (Join-Path $MnnRoot '.git'))) {
  throw "Missing MNN source checkout: $MnnRoot"
}

$actualCommit = (& git -C $MnnRoot rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or $actualCommit -ne $expectedCommit) {
  throw "Expected MNN $expectedCommit, found $actualCommit"
}

$cmake = Join-Path $HarmonyNativeHome 'build-tools\cmake\bin\cmake.exe'
$ninja = Join-Path $HarmonyNativeHome 'build-tools\cmake\bin\ninja.exe'
if (-not (Test-Path $cmake) -or -not (Test-Path $ninja)) {
  throw "Missing CMake or Ninja under $HarmonyNativeHome"
}

& $cmake -S $MnnRoot -B $BuildDir -G Ninja `
  "-DCMAKE_MAKE_PROGRAM=$ninja" `
  "-DCMAKE_TOOLCHAIN_FILE=$HarmonyNativeHome\build\cmake\ohos.toolchain.cmake" `
  '-DCMAKE_BUILD_TYPE=Release' `
  '-DOHOS_ARCH=arm64-v8a' `
  '-DOHOS_STL=c++_shared' `
  '-DOHOS_PLATFORM_LEVEL=9' `
  '-DMNN_BUILD_SHARED_LIBS=ON' `
  '-DMNN_BUILD_LLM=ON' `
  '-DMNN_BUILD_LLM_OMNI=ON' `
  '-DMNN_LOW_MEMORY=ON' `
  '-DMNN_SUPPORT_TRANSFORMER_FUSE=ON' `
  '-DMNN_ARM82=ON' `
  '-DMNN_USE_LOGCAT=ON' `
  '-DMNN_BUILD_TEST=OFF' `
  '-DMNN_BUILD_BENCHMARK=OFF' `
  '-DMNN_BUILD_AUDIO=OFF' `
  '-DMNN_BUILD_OPENCV=ON' `
  '-DMNN_IMGCODECS=ON' `
  '-DMNN_BUILD_DIFFUSION=OFF' `
  '-DMNN_OPENCL=OFF' `
  '-DMNN_SEP_BUILD=OFF' `
  '-DMNN_USE_SSE=OFF'
if ($LASTEXITCODE -ne 0) { throw 'MNN CMake configuration failed.' }

& $cmake --build $BuildDir --target MNN -j $Jobs
if ($LASTEXITCODE -ne 0) { throw 'MNN build failed.' }
Write-Output (Join-Path $BuildDir 'libMNN.so')
