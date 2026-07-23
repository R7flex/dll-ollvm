$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$DefaultToolsDir = Join-Path $RepoRoot "third_party\LLVM-18.1.5"
$DefaultSdkDir = Join-Path $RepoRoot "third_party\LLVM-18.1.5-dev"
$PluginBuildDir = Join-Path $RepoRoot "build\plugin"
$PayloadOutDir = Join-Path $RepoRoot "out\payload"

function Test-LlvmSdk([string]$Dir) {
    if (-not $Dir) { return $false }
    return (Test-Path (Join-Path $Dir "bin\opt.exe")) -and
           (Test-Path (Join-Path $Dir "lib\cmake\llvm\LLVMConfig.cmake"))
}

function Test-ClangTools([string]$Dir) {
    if (-not $Dir) { return $false }
    return (Test-Path (Join-Path $Dir "bin\clang.exe")) -and
           (Test-Path (Join-Path $Dir "bin\clang-cl.exe"))
}

function Get-TessLlvmDir {
    if ($env:TESS_LLVM_DIR -and (Test-LlvmSdk $env:TESS_LLVM_DIR)) {
        return (Resolve-Path $env:TESS_LLVM_DIR).Path
    }
    if (Test-LlvmSdk $DefaultSdkDir) {
        return (Resolve-Path $DefaultSdkDir).Path
    }
    if (Test-LlvmSdk $DefaultToolsDir) {
        return (Resolve-Path $DefaultToolsDir).Path
    }
    if (Test-LlvmSdk "C:\LLVM-18.1.5-dev") { return "C:\LLVM-18.1.5-dev" }
    return $null
}

function Get-TessClangDir {
    if ($env:TESS_CLANG_DIR -and (Test-ClangTools $env:TESS_CLANG_DIR)) {
        return (Resolve-Path $env:TESS_CLANG_DIR).Path
    }
    $sdk = Get-TessLlvmDir
    if ($sdk -and (Test-ClangTools $sdk)) { return $sdk }
    if (Test-ClangTools $DefaultToolsDir) {
        return (Resolve-Path $DefaultToolsDir).Path
    }
    if (Test-ClangTools "C:\Program Files\LLVM") { return "C:\Program Files\LLVM" }
    if ($sdk) { return $sdk }
    return $null
}

function Get-VsDevCmd {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
    if (-not (Test-Path $vswhere)) {
        throw "vswhere.exe not found. Install Visual Studio 2022."
    }
    $vsPath = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    if (-not $vsPath) {
        throw "VS2022 with C++ toolset not found."
    }
    $devCmd = Join-Path $vsPath "Common7\Tools\VsDevCmd.bat"
    if (-not (Test-Path $devCmd)) {
        throw "VsDevCmd.bat not found at $devCmd"
    }
    return $devCmd
}

function Get-CMake {
    $candidates = @(
        (Get-Command cmake -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source),
        "C:\Program Files\CMake\bin\cmake.exe",
        "C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe",
        "C:\Program Files\Microsoft Visual Studio\2022\Professional\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe",
        "C:\Program Files\Microsoft Visual Studio\2022\Enterprise\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe"
    )
    foreach ($c in $candidates) {
        if ($c -and (Test-Path $c)) { return $c }
    }
    throw "cmake.exe not found. Install CMake or VS2022 CMake tools."
}

function Invoke-InVsDevShell {
    param(
        [Parameter(Mandatory = $true)][string]$Command
    )
    $devCmd = Get-VsDevCmd
    $bat = Join-Path $env:TEMP "tess-vsdev-$([guid]::NewGuid().ToString('N')).bat"
    @"
@echo off
call "$devCmd" -arch=x64 -host_arch=x64 >nul
$Command
exit /b %ERRORLEVEL%
"@ | Set-Content -Path $bat -Encoding ASCII
    try {
        & cmd.exe /c $bat
        if ($LASTEXITCODE -ne 0) {
            throw "Command failed with exit code $LASTEXITCODE"
        }
    }
    finally {
        Remove-Item -Force $bat -ErrorAction SilentlyContinue
    }
}
