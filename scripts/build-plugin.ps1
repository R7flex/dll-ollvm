param(
    [string]$LLVMDir = "",
    [ValidateSet("Release", "Debug", "RelWithDebInfo")]
    [string]$Config = "Release",
    [switch]$Clean
)

. "$PSScriptRoot\common.ps1"

if (-not $LLVMDir) {
    $LLVMDir = Get-TessLlvmDir
}
if (-not $LLVMDir) {
    throw "LLVM not found. Run scripts\setup-llvm.ps1 first (or set TESS_LLVM_DIR)."
}

$cmake = Get-CMake
$src = Join-Path $RepoRoot "plugin"
$build = $PluginBuildDir

if ($Clean -and (Test-Path $build)) {
    Remove-Item -Recurse -Force $build
}
New-Item -ItemType Directory -Force -Path $build | Out-Null

Write-Host "LLVM:  $LLVMDir"
Write-Host "Build: $build ($Config)"

$cmakeCfg = "`"$cmake`" -S `"$src`" -B `"$build`" -G `"Visual Studio 17 2022`" -A x64 `"-DLT_LLVM_INSTALL_DIR=$LLVMDir`""
Invoke-InVsDevShell -Command $cmakeCfg

$cmakeBuild = "`"$cmake`" --build `"$build`" --config $Config --parallel"
Invoke-InVsDevShell -Command $cmakeBuild

$dllCandidates = @(
    (Join-Path $build "LLVMObfuscationx.dll"),
    (Join-Path $build "bin\$Config\LLVMObfuscationx.dll"),
    (Join-Path $build "$Config\LLVMObfuscationx.dll"),
    (Join-Path $build "bin\LLVMObfuscationx.dll")
)

$dll = $dllCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $dll) {
    throw "Build finished but LLVMObfuscationx.dll not found under $build"
}

Write-Host "OK: $dll"
$dll
