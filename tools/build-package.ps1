<#
.SYNOPSIS
    打一个可直接分发的 zip 包（不含主题样本、APK、密钥等）。

.DESCRIPTION
    打包内容：tools/（含 adapters）、phone/、docs/、README.md、LICENSE、主题工具.bat
    默认不含：dist/、_samples/、*.theme、*.apk、*.keystore、__pycache__、.git
    LockWall 源码默认包含（lockwall/），可用 -NoLockwall 排除。

.PARAMETER Version  版本号（默认取 git describe，取不到用 dev）
.PARAMETER Out      输出目录（默认 dist）
.PARAMETER NoLockwall  不打包 lockwall 源码

.EXAMPLE
    .\build-package.ps1
    .\build-package.ps1 -Version v5.0.0
#>
param(
    [string]$Version = '',
    [string]$Out = '',
    [switch]$NoLockwall
)

. (Join-Path $PSScriptRoot 'common.ps1')

$repoRoot = Split-Path $PSScriptRoot -Parent
if (-not $Out) { $Out = Join-Path $repoRoot 'dist' }
if (-not (Test-Path -LiteralPath $Out)) { New-Item -ItemType Directory -Path $Out -Force | Out-Null }

if (-not $Version) {
    try {
        $Version = (git -C $repoRoot describe --tags --abbrev=0 2>$null)
    }
    catch { }
    if (-not $Version) { $Version = 'dev' }
}
$Version = "$Version".Trim()

$name = "android-theme-tool-$Version"
$stage = Join-Path $env:TEMP ("pkg_" + [guid]::NewGuid().ToString('N').Substring(0, 8))
$root = Join-Path $stage $name
New-Item -ItemType Directory -Path $root -Force | Out-Null

function Copy-Filtered {
    param([string]$From, [string]$To, [string[]]$ExcludeDirs = @(), [string[]]$ExcludeFiles = @())

    if (-not (Test-Path -LiteralPath $From)) { return }
    New-Item -ItemType Directory -Path $To -Force | Out-Null
    foreach ($item in (Get-ChildItem -LiteralPath $From -Force)) {
        if ($item.PSIsContainer) {
            if ($ExcludeDirs -contains $item.Name) { continue }
            Copy-Filtered -From $item.FullName -To (Join-Path $To $item.Name) -ExcludeDirs $ExcludeDirs -ExcludeFiles $ExcludeFiles
            continue
        }
        if ($ExcludeFiles -contains $item.Name) { continue }
        Copy-Item -LiteralPath $item.FullName -Destination (Join-Path $To $item.Name) -Force
    }
}

Write-Step "打包 $name"

$skipDirs = @('__pycache__', 'dist', 'build', 'out', '_samples')
Copy-Filtered -From (Join-Path $repoRoot 'tools') -To (Join-Path $root 'tools') -ExcludeDirs $skipDirs
Copy-Filtered -From (Join-Path $repoRoot 'phone') -To (Join-Path $root 'phone') -ExcludeDirs $skipDirs
Copy-Filtered -From (Join-Path $repoRoot 'docs') -To (Join-Path $root 'docs') -ExcludeDirs $skipDirs
Copy-Filtered -From (Join-Path $repoRoot 'tests') -To (Join-Path $root 'tests') -ExcludeDirs $skipDirs
if (-not $NoLockwall) {
    Copy-Filtered -From (Join-Path $repoRoot 'lockwall') -To (Join-Path $root 'lockwall') -ExcludeDirs @('out', '__pycache__') -ExcludeFiles @('lock.jpg', 'lock.png')
}
foreach ($f in 'README.md', 'LICENSE', '主题工具.bat') {
    $p = Join-Path $repoRoot $f
    if (Test-Path -LiteralPath $p) { Copy-Item -LiteralPath $p -Destination (Join-Path $root $f) -Force }
}

# 清掉不该进包的扩展名
$banned = '*.apk', '*.idsig', '*.keystore', '*.jks', '*.theme', '*.mtz', '*.hwt', '*.hnt', '*.itz', '*.pyc'
foreach ($pat in $banned) {
    Get-ChildItem -LiteralPath $root -Recurse -File -Filter $pat -ErrorAction SilentlyContinue |
        ForEach-Object { Remove-Item -LiteralPath $_.FullName -Force }
}

$files = @(Get-ChildItem -LiteralPath $root -Recurse -File)
$rawSize = ($files | Measure-Object -Property Length -Sum).Sum
Write-Info ("文件 {0} 个，未压缩 {1:N1} MB" -f $files.Count, ($rawSize / 1MB))

$zip = Join-Path $Out "$name.zip"
if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }

Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::CreateFromDirectory($stage, $zip, [System.IO.Compression.CompressionLevel]::Optimal, $false)
Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue

if (-not (Test-Path -LiteralPath $zip)) { Write-Bad '打包失败：zip 未生成'; return }

$hash = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLower()
$size = (Get-Item -LiteralPath $zip).Length

Write-Host ''
Write-Ok ("已生成：{0}" -f $zip)
Write-Info ("  大小  ：{0:N1} MB" -f ($size / 1MB))
Write-Info ("  SHA256：{0}" -f $hash)
Write-Host ''
Write-Info '上传到 GitHub Release：'
Write-Info ('  gh release upload {0} "{1}"' -f $Version, $zip)
