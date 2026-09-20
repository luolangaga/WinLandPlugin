<#
.SYNOPSIS
    把插件的构建输出打包成 .lwp 并生成待提交的 plugins/<id>/ 目录。

.DESCRIPTION
    一条命令完成投稿前的准备：
      1. 从 SourceDir（构建输出目录，需含 plugin.json 与入口 DLL）打 .lwp；
      2. 过滤掉宿主自带的程序集（WinIsland.Core / WinAppSDK / WinUI 等）与 *.pdb；
      3. 生成 plugins/<id>/ = plugin.json + <id>.lwp + logo.png + README.md；
      4. 调用 build-index.ps1 校验并刷新 index.json / README 表格。

.EXAMPLE
    pwsh tools/submit-plugin.ps1 -SourceDir ..\samples\HardwareMonitor\bin\Release\net10.0-windows10.0.26100.0\win-x64

.EXAMPLE
    pwsh tools/submit-plugin.ps1 -SourceDir .\publish -Logo .\logo.png -Readme .\README.md -NoIndex
#>
param(
    [Parameter(Mandatory = $true)][string]$SourceDir,
    [string]$Logo = "",
    [string]$Readme = "",
    [switch]$NoIndex
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$source = (Resolve-Path $SourceDir).Path
$manifestPath = Join-Path $source "plugin.json"

if (-not (Test-Path $manifestPath)) {
    throw "SourceDir 里缺少 plugin.json：$source"
}

$manifest = Get-Content $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
$id = "$($manifest.id)".Trim()
if (-not $id) { throw "plugin.json 缺少 id" }
if ($id -notmatch '^[a-z0-9][a-z0-9-]{1,63}$') { throw "id 不合法（小写字母/数字/连字符，2-64 字符）：$id" }
if (-not $manifest.entry_dll) { throw "plugin.json 缺少 entry_dll" }
if (-not (Test-Path (Join-Path $source $manifest.entry_dll))) {
    throw "SourceDir 里没有入口程序集 $($manifest.entry_dll)（请先 dotnet build）"
}

# 宿主自带 / 用不到的运行时文件不进插件包
$skipNames = @(
    "WinIsland.Core.dll",
    "Microsoft.WinUI.dll",
    "Microsoft.Windows.SDK.NET.dll",
    "WinRT.Runtime.dll",
    "WebView2Loader.dll",
    "Microsoft.ML.OnnxRuntime.dll",
    "System.Numerics.Tensors.dll",
    "Dia2Lib.dll",
    "TraceReloggerLib.dll",
    "KernelTraceControl.dll",
    "msdia140.dll"
)
$skipPatterns = @(
    "Microsoft.Windows.*.dll",
    "Microsoft.Web.WebView2*.dll",
    "Microsoft.Graphics.*.dll",
    "Microsoft.InteractiveExperiences.*.dll",
    "Microsoft.*.Projection.dll",
    "Microsoft.WindowsAppRuntime*"
)

$pluginDir = Join-Path (Join-Path $root "plugins") $id
New-Item -ItemType Directory -Path $pluginDir -Force | Out-Null

$staging = Join-Path $env:TEMP "winland-pack-$([Guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $staging -Force | Out-Null

try {
    $copied = 0
    Get-ChildItem $source -Recurse -File | ForEach-Object {
        if ($_.Extension -eq ".pdb") { return }
        if ($skipNames -contains $_.Name) { return }
        $skip = $false
        foreach ($pattern in $skipPatterns) { if ($_.Name -like $pattern) { $skip = $true } }
        if ($skip) { return }

        $relative = $_.FullName.Substring($source.Length).TrimStart('\')
        $target = Join-Path $staging $relative
        New-Item -ItemType Directory -Path (Split-Path $target) -Force | Out-Null
        Copy-Item $_.FullName $target -Force
        $script:copied++
    }

    if ($copied -eq 0) { throw "SourceDir 里没有可打包的文件" }

    $packagePath = Join-Path $pluginDir "$id.lwp"
    if (Test-Path $packagePath) { Remove-Item $packagePath -Force }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::CreateFromDirectory($staging, $packagePath)

    Copy-Item $manifestPath (Join-Path $pluginDir "plugin.json") -Force
    if ($Logo) { Copy-Item (Resolve-Path $Logo).Path (Join-Path $pluginDir "logo.png") -Force }
    if ($Readme) { Copy-Item (Resolve-Path $Readme).Path (Join-Path $pluginDir "README.md") -Force }

    $size = [math]::Round((Get-Item $packagePath).Length / 1KB, 1)
    Write-Output "已生成 plugins/$id/（$copied 个文件，$id.lwp $size KB）"
} finally {
    if (Test-Path $staging) { Remove-Item $staging -Recurse -Force }
}

if (-not $NoIndex) {
    & (Join-Path $PSScriptRoot "build-index.ps1") -Root $root
}

Write-Output ""
Write-Output "下一步："
Write-Output "  gh repo fork luolangaga/WinLandPlugin --clone"
Write-Output "  git checkout -b add-plugin-$id"
Write-Output "  git add plugins/$id index.json README.md"
Write-Output "  git commit -m `"feat: add $id plugin`" && git push"
