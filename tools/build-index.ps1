<#
.SYNOPSIS
    扫描 plugins/<id>/ 生成 index.json 与 README 的插件清单。

.DESCRIPTION
    每个插件一个目录：

        plugins/<id>/
          plugin.json      清单（id/name/version/entry_dll/api_version 必填，与包内那份一致）
          <id>.lwp         插件包（一个目录只允许一个 .lwp）
          logo.png         可选，建议 240x240 透明 PNG（脚本会缩成 128x128 内嵌进 index.json）
          README.md        可选，插件详细说明

    生成物：
      index.json       客户端唯一数据源（含 sha256、体积、缩略 logo），整个市场列表只需一次请求
      README.md        人看的插件清单表格（替换 <!-- PLUGINS:START --> / <!-- PLUGINS:END --> 之间内容）

    校验不通过会以非 0 退出码结束，CI 里即视为失败。

.EXAMPLE
    pwsh tools/build-index.ps1
    pwsh tools/build-index.ps1 -Root D:\WinLandPlugin -CheckOnly
#>
param(
    [string]$Root = "",
    [switch]$CheckOnly
)

$ErrorActionPreference = "Stop"

if (-not $Root) { $Root = Split-Path -Parent $PSScriptRoot }
$Root = (Resolve-Path $Root).Path
$pluginsRoot = Join-Path $Root "plugins"

$logoMaxBytes = 40960
$logoSourceMaxBytes = 2MB
$idPattern = '^[a-z0-9][a-z0-9-]{1,63}$'
$skipNames = @(
    "WinIsland.Core.dll",
    "Microsoft.WinUI.dll",
    "Microsoft.Windows.SDK.NET.dll",
    "WinRT.Runtime.dll"
)

$errors = @()
$warnings = @()
$entries = @()

function Add-Error([string]$message) { $script:errors += $message }
function Add-Warning([string]$message) { $script:warnings += $message }

function Get-RequiredString($manifest, [string]$field, [string]$where) {
    $value = $manifest.$field
    if ($null -eq $value -or "$value".Trim().Length -eq 0) {
        Add-Error "$where 的 plugin.json 缺少必填字段 $field"
        return ""
    }
    return "$value".Trim()
}

<#
    把 logo.png 缩放成正方形缩略图并编码为 data URI：
    先在 128x128 试，超过 40KB 就退到 96 / 64，保证 index.json 不会因为图标膨胀。
#>
function Convert-LogoToDataUri([string]$path, [string]$where) {
    $info = Get-Item $path
    if ($info.Length -gt $logoSourceMaxBytes) {
        Add-Error "$where 的 logo.png 过大（$([math]::Round($info.Length / 1KB)) KB），请先压缩到 1MB 以内"
        return $null
    }

    try {
        Add-Type -AssemblyName System.Drawing -ErrorAction Stop
    } catch {
        Add-Warning "无法加载 System.Drawing，已跳过 logo 缩略图（index.json 里不会有 logo_data）"
        return $null
    }

    $source = $null
    try {
        $source = [System.Drawing.Image]::FromFile($info.FullName)
    } catch {
        Add-Error "$where 的 logo.png 不是有效的图片：$($_.Exception.Message)"
        return $null
    }

    try {
        foreach ($size in @(128, 96, 64)) {
            $bitmap = New-Object System.Drawing.Bitmap($size, $size)
            $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
            try {
                $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
                $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
                $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
                $graphics.Clear([System.Drawing.Color]::Transparent)

                $scale = [Math]::Min($size / $source.Width, $size / $source.Height)
                $width = [int][Math]::Max(1, [Math]::Round($source.Width * $scale))
                $height = [int][Math]::Max(1, [Math]::Round($source.Height * $scale))
                $x = [int](($size - $width) / 2)
                $y = [int](($size - $height) / 2)
                $graphics.DrawImage($source, $x, $y, $width, $height)
            } finally {
                $graphics.Dispose()
            }

            $stream = New-Object System.IO.MemoryStream
            try {
                $bitmap.Save($stream, [System.Drawing.Imaging.ImageFormat]::Png)
                $bytes = $stream.ToArray()
            } finally {
                $stream.Dispose()
                $bitmap.Dispose()
            }

            if ($bytes.Length -le $logoMaxBytes -or $size -eq 64) {
                if ($size -lt 128) {
                    Add-Warning "$where 的 logo 已降采样到 ${size}x${size} 以控制清单体积（$([math]::Round($bytes.Length / 1KB)) KB）"
                }
                return "data:image/png;base64," + [Convert]::ToBase64String($bytes)
            }
        }
    } finally {
        $source.Dispose()
    }

    return $null
}

function Get-GitDate([string]$relativePath) {
    try {
        $stamp = & git -C $Root log -1 --format=%cI -- $relativePath 2>$null
        if ($LASTEXITCODE -eq 0 -and $stamp) { return ([DateTimeOffset]::Parse($stamp.Trim())).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ") }
    } catch {
    }
    return $null
}

Write-Output "扫描插件目录：$pluginsRoot"

if (-not (Test-Path $pluginsRoot)) {
    Write-Error "缺少 plugins 目录：$pluginsRoot"
    exit 1
}

foreach ($directory in (Get-ChildItem $pluginsRoot -Directory | Sort-Object Name)) {
    $folder = $directory.Name
    $where = "plugins/$folder"

    if ($folder.StartsWith(".") -or $folder.StartsWith("_")) { continue }

    $manifestPath = Join-Path $directory.FullName "plugin.json"
    if (-not (Test-Path $manifestPath)) {
        Add-Error "$where 缺少 plugin.json"
        continue
    }

    $manifest = $null
    try {
        $manifest = Get-Content $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        Add-Error "$where 的 plugin.json 不是有效的 JSON：$($_.Exception.Message)"
        continue
    }

    $id = Get-RequiredString $manifest "id" $where
    $name = Get-RequiredString $manifest "name" $where
    $version = Get-RequiredString $manifest "version" $where
    $entryDll = Get-RequiredString $manifest "entry_dll" $where

    if ($id -and $id -notmatch $idPattern) {
        Add-Error "$where 的 id 不合法（要求小写字母/数字/连字符，2-64 字符）：$id"
    }
    if ($id -and $id -ne $folder) {
        Add-Error "$where 的 id（$id）必须与目录名一致"
    }
    if ($version -and -not ([System.Version]::TryParse($version, [ref]$null))) {
        Add-Error "$where 的 version 不是有效版本号：$version"
    }
    if ($entryDll -and ($entryDll -match '[\\/:]' -or $entryDll -notmatch '\.dll$')) {
        Add-Error "$where 的 entry_dll 必须是包内 .dll 文件名（不含路径）：$entryDll"
    }
    if ($entryDll -and $entryDll -ieq "WinIsland.Core.dll") {
        Add-Error "$where 的 entry_dll 不能是 WinIsland.Core.dll（由宿主提供）"
    }

    $apiVersion = 0
    if ($null -eq $manifest.api_version) {
        Add-Error "$where 的 plugin.json 缺少必填字段 api_version"
    } elseif (-not [int]::TryParse("$($manifest.api_version)", [ref]$apiVersion) -or $apiVersion -lt 1) {
        Add-Error "$where 的 api_version 必须是大于 0 的整数"
    }

    $minHostVersion = $null
    if ($null -ne $manifest.min_host_version -and "$($manifest.min_host_version)".Trim().Length -gt 0) {
        $minHostVersion = "$($manifest.min_host_version)".Trim()
        if (-not ([System.Version]::TryParse($minHostVersion, [ref]$null))) {
            Add-Error "$where 的 min_host_version 不是有效版本号：$minHostVersion"
        }
    }

    if ($name -and $name.Length -gt 24) {
        Add-Warning "$where 的 name 较长（$($name.Length) 字），列表里可能显示不全"
    }

    # 插件包：优先 <id>.lwp，否则该目录下唯一的 .lwp
    $packages = @(Get-ChildItem $directory.FullName -File -Filter "*.lwp")
    $package = $packages | Where-Object { $_.BaseName -ieq $id } | Select-Object -First 1
    if (-not $package) { $package = $packages | Select-Object -First 1 }
    if (-not $package) {
        Add-Error "$where 缺少插件包（*.lwp）"
        continue
    }
    if ($packages.Count -gt 1) {
        Add-Warning "$where 目录下有 $($packages.Count) 个 .lwp，已选用 $($package.Name)"
    }

    $packageRelative = "plugins/$folder/$($package.Name)"

    # 包内校验：必须含 plugin.json 与 entry_dll，且 id/version 与目录里的清单一致
    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
    try {
        $archive = [System.IO.Compression.ZipFile]::OpenRead($package.FullName)
        try {
            $innerManifestEntry = $archive.Entries | Where-Object { $_.FullName -ieq "plugin.json" } | Select-Object -First 1
            if (-not $innerManifestEntry) {
                Add-Error "$where 的插件包缺少根目录 plugin.json"
            } else {
                $reader = New-Object System.IO.StreamReader($innerManifestEntry.Open())
                try { $innerManifest = $reader.ReadToEnd() | ConvertFrom-Json } finally { $reader.Dispose() }

                if ($innerManifest.id -and $id -and "$($innerManifest.id)" -ne $id) {
                    Add-Error "$where 的插件包内 id（$($innerManifest.id)）与 plugin.json（$id）不一致，请重新打包"
                }
                if ($innerManifest.version -and $version -and "$($innerManifest.version)" -ne $version) {
                    Add-Error "$where 的插件包内 version（$($innerManifest.version)）与 plugin.json（$version）不一致，请重新打包"
                }
                if ($innerManifest.entry_dll -and $entryDll -and "$($innerManifest.entry_dll)" -ine $entryDll) {
                    Add-Error "$where 的插件包内 entry_dll（$($innerManifest.entry_dll)）与 plugin.json（$entryDll）不一致"
                }
            }

            if ($entryDll -and -not ($archive.Entries | Where-Object { $_.FullName -ieq $entryDll } | Select-Object -First 1)) {
                Add-Error "$where 的插件包内缺少入口程序集 $entryDll"
            }

            if ($archive.Entries | Where-Object { $_.FullName -ieq "WinIsland.Core.dll" } | Select-Object -First 1) {
                Add-Error "$where 的插件包不允许携带 WinIsland.Core.dll（由宿主提供）"
            }

            $appSdkEntries = @($archive.Entries | Where-Object { $_.Name -match '^Microsoft\.(WinUI|WindowsAppRuntime|WindowsAppSDK)' })
            if ($appSdkEntries.Count -gt 0) {
                Add-Warning "$where 的插件包内含 Windows App SDK 运行时文件（$($appSdkEntries.Count) 个），宿主已自带，建议打包时排除"
            }

            $forbidden = @($archive.Entries | Where-Object { $skipNames -contains $_.Name -and $_.Name -ine "WinIsland.Core.dll" })
            if ($forbidden.Count -gt 0) {
                Add-Warning "$where 的插件包内含宿主自带的程序集：$(($forbidden | ForEach-Object { $_.Name }) -join '、')"
            }
        } finally {
            $archive.Dispose()
        }
    } catch {
        Add-Error "$where 读取插件包失败：$($_.Exception.Message)"
        continue
    }

    $logoRelative = $null
    $logoData = $null
    $logoPath = Join-Path $directory.FullName "logo.png"
    if (Test-Path $logoPath) {
        $logoRelative = "plugins/$folder/logo.png"
        $logoData = Convert-LogoToDataUri $logoPath $where
    } else {
        Add-Warning "$where 没有 logo.png，市场里会退化成用 icon_glyph 显示"
    }

    $readmePath = Join-Path $directory.FullName "README.md"
    $readmeRelative = if (Test-Path $readmePath) { "plugins/$folder/README.md" } else { $null }
    if (-not $readmeRelative) { Add-Warning "$where 没有 README.md，详情页没有说明文字" }

    $tags = @()
    if ($manifest.tags) {
        foreach ($tag in $manifest.tags) {
            if ("$tag".Trim().Length -gt 0) { $tags += "$tag".Trim() }
        }
    }

    $hash = (Get-FileHash $package.FullName -Algorithm SHA256).Hash.ToLowerInvariant()

    $entries += [ordered]@{
        id               = $id
        name             = $name
        version          = $version
        description      = if ($manifest.description) { "$($manifest.description)".Trim() } else { $null }
        author           = if ($manifest.author) { "$($manifest.author)".Trim() } else { $null }
        icon_glyph       = if ($manifest.icon_glyph) { "$($manifest.icon_glyph)" } else { $null }
        homepage         = if ($manifest.homepage) { "$($manifest.homepage)".Trim() } else { $null }
        license          = if ($manifest.license) { "$($manifest.license)".Trim() } else { $null }
        tags             = $tags
        api_version      = $apiVersion
        min_host_version = $minHostVersion
        package          = $packageRelative
        package_size     = $package.Length
        sha256           = $hash
        readme           = $readmeRelative
        logo             = $logoRelative
        logo_data        = $logoData
        updated_at       = (Get-GitDate $packageRelative)
    }

    Write-Output ("  ✓ {0} {1}（{2}，{3} KB）" -f $id, $version, $package.Name, [math]::Round($package.Length / 1KB, 1))
}

foreach ($warning in $warnings) { Write-Warning $warning }

if ($errors.Count -gt 0) {
    Write-Output ""
    foreach ($message in $errors) { Write-Output "✗ $message" }
    Write-Output ""
    Write-Output "共 $($errors.Count) 个错误，未生成 index.json。"
    exit 1
}

$entries = @($entries | Sort-Object { $_["name"] })

$index = [ordered]@{
    schema  = 1
    repo    = "luolangaga/WinLandPlugin"
    updated = [DateTimeOffset]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
    count   = $entries.Count
    plugins = $entries
}

$json = $index | ConvertTo-Json -Depth 8
# Windows PowerShell 会把非 ASCII 转成 \uXXXX，这里把中文还原成字面量（方便阅读 diff）；
# 私用区码位（Segoe 图标字形，如 \uE950）保持转义，和 plugin.json 的写法一致。
$json = [regex]::Replace($json, '(?<!\\)\\u([0-9a-fA-F]{4})', {
        param($match)
        $code = [Convert]::ToInt32($match.Groups[1].Value, 16)
        if ($code -ge 0xE000 -and $code -le 0xF8FF) { return $match.Value }
        [string][char]$code
    })
$json = [regex]::Replace($json, '[\uE000-\uF8FF]', { param($match) '\u{0:X4}' -f [int][char]$match.Value })

if (-not $CheckOnly) {
    [System.IO.File]::WriteAllText((Join-Path $Root "index.json"), $json + "`n", (New-Object System.Text.UTF8Encoding($false)))
    Write-Output "已写入 index.json（$($entries.Count) 个插件）"

    # README 清单表格
    $readmePath = Join-Path $Root "README.md"
    if (Test-Path $readmePath) {
        $rows = @()
        foreach ($entry in $entries) {
            $icon = if ($entry["logo"]) { "![]($($entry["logo"]))" } else { "" }
            $description = if ($entry["description"]) { "$($entry["description"])".Replace("|", "\|") } else { "" }
            $rows += "| $icon | **$($entry["name"])**<br/>``$($entry["id"])`` | $($entry["version"]) | $($entry["author"]) | $description |"
        }

        if ($rows.Count -eq 0) {
            $rows += "| | 还没有插件 | | | 欢迎投稿！ |"
        }

        $table = @(
            "| 图标 | 插件（Id） | 版本 | 作者 | 说明 |",
            "| :---: | :--- | :---: | :--- | :--- |"
        ) + $rows

        $text = [System.IO.File]::ReadAllText($readmePath, [System.Text.Encoding]::UTF8)
        $start = "<!-- PLUGINS:START -->"
        $end = "<!-- PLUGINS:END -->"
        $pattern = "(?s)" + [regex]::Escape($start) + ".*?" + [regex]::Escape($end)
        $block = $start + "`n" + ($table -join "`n") + "`n" + $end
        if ($text -match $pattern) {
            $text = [regex]::Replace($text, $pattern, { param($m) $block })
            [System.IO.File]::WriteAllText($readmePath, $text, (New-Object System.Text.UTF8Encoding($false)))
            Write-Output "已更新 README.md 的插件清单表格"
        } else {
            Add-Warning "README.md 缺少 $start / $end 标记，未更新表格"
        }
    }
} else {
    Write-Output "校验通过（$($entries.Count) 个插件），未写入文件。"
}
