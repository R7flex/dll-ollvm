param(
    [switch]$ToolsOnly,
    [switch]$SkipTools,
    [string]$Jobs = ""
)

. "$PSScriptRoot\common.ps1"

$Version = "18.1.5"
$Tag = "llvmorg-$Version"
$ToolsUrl = "https://github.com/llvm/llvm-project/releases/download/$Tag/LLVM-$Version-win64.exe"
$ToolsDir = Join-Path $RepoRoot "third_party\LLVM-$Version"
$SdkDir = Join-Path $RepoRoot "third_party\LLVM-$Version-dev"
$SrcDir = Join-Path $RepoRoot "third_party\llvm-project"
$BuildDir = Join-Path $RepoRoot "third_party\llvm-build"
$DlDir = Join-Path $RepoRoot "third_party\download"

function Test-ClangTools([string]$Dir) {
    return (Test-Path (Join-Path $Dir "bin\clang-cl.exe")) -and
           (Test-Path (Join-Path $Dir "bin\clang.exe"))
}

function Test-LlvmSdk([string]$Dir) {
    return (Test-Path (Join-Path $Dir "bin\opt.exe")) -and
           (Test-Path (Join-Path $Dir "lib\cmake\llvm\LLVMConfig.cmake")) -and
           (Test-Path (Join-Path $Dir "include\llvm\Passes\PassPlugin.h"))
}

New-Item -ItemType Directory -Force -Path $DlDir | Out-Null

Write-Host "=== LLVM $Version setup ==="

if (-not $SkipTools) {
    if (Test-ClangTools $ToolsDir) {
        Write-Host "Clang tools OK: $ToolsDir"
    } else {
        $installer = Join-Path $DlDir "LLVM-$Version-win64.exe"
        if (-not (Test-Path $installer)) {
            Write-Host "Downloading tools installer..."
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            Invoke-WebRequest -Uri $ToolsUrl -OutFile $installer -UseBasicParsing
        }
        Write-Host "Installing tools -> $ToolsDir"
        if (Test-Path $ToolsDir) {
            Remove-Item -Recurse -Force $ToolsDir -ErrorAction SilentlyContinue
        }
        $proc = Start-Process -FilePath $installer -ArgumentList "/S", "/D=$ToolsDir" -Wait -PassThru
        if (-not (Test-ClangTools $ToolsDir)) {
            Write-Warning "Tools install incomplete (exit $($proc.ExitCode)). You can still build the SDK."
        } else {
            Write-Host "Clang tools OK: $ToolsDir"
        }
    }
}

if ($ToolsOnly) {
    Write-Host "ToolsOnly done. For plugin builds run without -ToolsOnly."
    exit 0
}

if (Test-LlvmSdk $SdkDir) {
    Write-Host "LLVM SDK already OK: $SdkDir"
    $env:TESS_LLVM_DIR = $SdkDir
    if (Test-ClangTools $ToolsDir) { $env:TESS_CLANG_DIR = $ToolsDir }
    Write-Host "TESS_LLVM_DIR=$SdkDir"
    & (Join-Path $SdkDir "bin\opt.exe") --version
    exit 0
}

$cmake = Get-CMake

$ninja = $null
foreach ($c in @(
    (Get-Command ninja -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source),
    "C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\Ninja\ninja.exe",
    "C:\Program Files\Microsoft Visual Studio\2022\Professional\Common7\IDE\CommonExtensions\Microsoft\CMake\Ninja\ninja.exe"
)) {
    if ($c -and (Test-Path $c)) { $ninja = $c; break }
}

if (-not (Test-Path (Join-Path $SrcDir "llvm\CMakeLists.txt"))) {
    Write-Host "Cloning $Tag (shallow)..."
    if (Test-Path $SrcDir) { Remove-Item -Recurse -Force $SrcDir }
    New-Item -ItemType Directory -Force -Path (Split-Path $SrcDir) | Out-Null
    & git clone --depth 1 --branch $Tag https://github.com/llvm/llvm-project.git $SrcDir
    if ($LASTEXITCODE -ne 0) { throw "git clone failed" }
} else {
    Write-Host "Source present: $SrcDir"
}

New-Item -ItemType Directory -Force -Path $BuildDir | Out-Null

$parallel = $Jobs
if (-not $parallel) { $parallel = [Environment]::ProcessorCount }

Write-Host "Configuring LLVM SDK build..."
$llvmSrc = Join-Path $SrcDir "llvm"

$cfg = "`"$cmake`" -S `"$llvmSrc`" -B `"$BuildDir`""
if ($ninja) {
    $cfg += " -G Ninja `"-DCMAKE_MAKE_PROGRAM=$ninja`""
} else {
    $cfg += " -G `"Visual Studio 17 2022`" -A x64"
}
$cfg += " -DCMAKE_BUILD_TYPE=Release"
$cfg += " `"-DCMAKE_INSTALL_PREFIX=$SdkDir`""
$cfg += " -DLLVM_TARGETS_TO_BUILD=X86"
$cfg += " -DLLVM_ENABLE_PROJECTS=llvm"
$cfg += " -DLLVM_INCLUDE_TESTS=OFF -DLLVM_INCLUDE_EXAMPLES=OFF -DLLVM_INCLUDE_BENCHMARKS=OFF"
$cfg += " -DLLVM_BUILD_TESTS=OFF"
$cfg += " -DLLVM_ENABLE_PLUGINS=ON -DLLVM_EXPORT_SYMBOLS_FOR_PLUGINS=ON"
$cfg += " -DLLVM_OPTIMIZED_TABLEGEN=ON"

Invoke-InVsDevShell -Command $cfg

Write-Host "Building + installing LLVM SDK..."
if ($ninja) {
    Invoke-InVsDevShell -Command "`"$cmake`" --build `"$BuildDir`" --target install --parallel $parallel"
} else {
    Invoke-InVsDevShell -Command "`"$cmake`" --build `"$BuildDir`" --config Release --target install --parallel $parallel"
}

if (-not (Test-LlvmSdk $SdkDir)) {
    throw "LLVM SDK install failed verification at $SdkDir"
}

$optImplibSrc = Join-Path $BuildDir "lib\opt.lib"
$optImplibDst = Join-Path $SdkDir "lib\opt.lib"
if (Test-Path $optImplibSrc) {
    Copy-Item -Force $optImplibSrc $optImplibDst
    Write-Host "Copied opt.lib -> $optImplibDst"
} else {
    Write-Warning "opt.lib not found at $optImplibSrc (Windows plugin link may fail)"
}

$env:TESS_LLVM_DIR = $SdkDir
if (Test-ClangTools $ToolsDir) { $env:TESS_CLANG_DIR = $ToolsDir }

Write-Host "OK. TESS_LLVM_DIR=$SdkDir"
if ($env:TESS_CLANG_DIR) { Write-Host "TESS_CLANG_DIR=$($env:TESS_CLANG_DIR)" }
& (Join-Path $SdkDir "bin\opt.exe") --version
Write-Host ""
Write-Host "Next: .\scripts\build-plugin.ps1"
