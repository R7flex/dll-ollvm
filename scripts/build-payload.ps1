param(
    [string]$LLVMDir = "",
    [string]$PluginDll = "",
    [switch]$EnableFla,
    [switch]$EnableBcf,
    [switch]$EnableSub,
    [switch]$EnableTrim,
    [switch]$Smoke,
    [switch]$VerboseTess
)

. "$PSScriptRoot\common.ps1"

$SdkDir = Get-TessLlvmDir
$ClangDir = Get-TessClangDir
if ($LLVMDir) {
    if (Test-LlvmSdk $LLVMDir) { $SdkDir = $LLVMDir }
    if (Test-ClangTools $LLVMDir) { $ClangDir = $LLVMDir }
}
if (-not $SdkDir) {
    throw "LLVM SDK (opt + cmake) not found. Run scripts\setup-llvm.ps1 (from-source SDK)."
}
if (-not $ClangDir) {
    throw "clang/clang-cl not found. Run scripts\setup-llvm.ps1 (tools installer)."
}

$clang = Join-Path $ClangDir "bin\clang.exe"
$clangCl = Join-Path $ClangDir "bin\clang-cl.exe"
$opt = Join-Path $SdkDir "bin\opt.exe"
$llc = Join-Path $SdkDir "bin\llc.exe"

foreach ($t in @($clang, $clangCl, $opt, $llc)) {
    if (-not (Test-Path $t)) { throw "Missing tool: $t" }
}
Write-Host "SDK:   $SdkDir"
Write-Host "Clang: $ClangDir"

if (-not $PluginDll) {
    $candidates = @(
        (Join-Path $PluginBuildDir "LLVMObfuscationx.dll"),
        (Join-Path $PluginBuildDir "bin\Release\LLVMObfuscationx.dll"),
        (Join-Path $PluginBuildDir "Release\LLVMObfuscationx.dll"),
        (Join-Path $PluginBuildDir "bin\LLVMObfuscationx.dll")
    )
    $PluginDll = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
}
if (-not $PluginDll -or -not (Test-Path $PluginDll)) {
    throw "Plugin DLL not found. Run scripts\build-plugin.ps1 first."
}
$PluginDll = (Resolve-Path $PluginDll).Path

$src = Join-Path $RepoRoot "samples\payload_dll\src\dllmain.cpp"
$def = Join-Path $RepoRoot "samples\payload_dll\payload.def"
$outDir = $PayloadOutDir
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

$bc = Join-Path $outDir "payload.bc"
$obfBc = Join-Path $outDir "payload.obf.bc"
$obj = Join-Path $outDir "payload.obj"
$dll = Join-Path $outDir "payload.dll"

Write-Host "Plugin: $PluginDll"
Write-Host "Out:    $dll"

Invoke-InVsDevShell -Command "`"$clang`" -c -emit-llvm -O2 -Xclang -disable-llvm-passes --target=x86_64-pc-windows-msvc -o `"$bc`" `"$src`""

$passList = @()
if ($Smoke) {
    $passList = @("tess-obf")
} else {
    if ($EnableFla)  { $passList += "tess-fla" }
    if ($EnableBcf)  { $passList += "tess-bcf" }
    if ($EnableSub)  { $passList += "tess-sub" }
    if ($EnableTrim) { $passList += "tess-trim" }
}

if ($passList.Count -eq 0) {
    Write-Host "No Tess passes enabled; copying bitcode through."
    Copy-Item -Force $bc $obfBc
} else {
    $passes = ($passList -join ",")
    if ($VerboseTess) { $env:TESS_VERBOSE = "1" }
    Write-Host "opt passes: $passes"
    Invoke-InVsDevShell -Command "`"$opt`" `"-load-pass-plugin=$PluginDll`" `"-passes=$passes`" `"$bc`" -o `"$obfBc`""
}

Invoke-InVsDevShell -Command "`"$llc`" -filetype=obj -mtriple=x86_64-pc-windows-msvc -O2 `"$obfBc`" -o `"$obj`""
Remove-Item -Force -ErrorAction SilentlyContinue @(
    (Join-Path $outDir "payload.exp"),
    (Join-Path $outDir "payload.lib"),
    $dll
)
Invoke-InVsDevShell -Command "link /nologo /dll /machine:x64 /out:`"$dll`" /def:`"$def`" `"$obj`" /defaultlib:libcmt /defaultlib:libvcruntime /defaultlib:libucrt"

if (-not (Test-Path $dll)) {
    throw "payload.dll was not produced"
}

$size = (Get-Item $dll).Length
Write-Host ("OK: {0} ({1} bytes)" -f $dll, $size)
$dll
