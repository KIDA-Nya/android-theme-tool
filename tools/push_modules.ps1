<#
.SYNOPSIS
    直接把 .theme 里的模块文件写入 /data/theme（需 root）。

.DESCRIPTION
    ⚠ 这是「兜底手段」，不是首选：
      uxdesign 是按「应用记录」激活模块的，单纯把文件拷进 /data/theme
      通常不会让模块生效（config 里的 icons 仍为空数组）。
      首选做法仍然是用 apply_local_theme.ps1 走一次带声明的正常应用。

    本脚本适用场景：
      · 已经用带声明的包应用过一次，但某个模块文件缺失需要补齐；
      · 排查问题时想确认某个模块文件是否齐全。

    它会读取 zip 实际条目，与 /data/theme 现有文件比对，只补缺失的。

.PARAMETER Theme   .theme 路径
.PARAMETER All     连多版本条目（*_003 / *_006 等）也一并写入
.PARAMETER Device  指定设备序列号

.EXAMPLE
    .\push_modules.ps1 -Theme '.\纳西妲.theme'
#>
param(
    [Parameter(Mandatory = $true)][string]$Theme,
    [switch]$All,
    [string]$Device = ''
)

. (Join-Path $PSScriptRoot 'common.ps1')

if (-not (Test-Path -LiteralPath $Theme)) { throw "找不到：$Theme" }

Write-Warn2 '提醒：直接写文件不一定会被 uxdesign 认作「已应用模块」。'
Write-Info '首选 apply_local_theme.ps1 走一次带声明的正常应用。'
Write-Host ''

Initialize-Device -Device $Device | Out-Null
if ($SuCmd -eq $null) { throw '本脚本需要 root（要写 /data/theme 并改属主）。' }

# uxdesign 的 uid/gid —— 绝不能硬编码
$uxUid = ((Invoke-Root 'stat -c %u /data/data/com.oplus.uxdesign' 'uxuid') | Out-String).Trim()
$uxGid = ((Invoke-Root 'stat -c %g /data/data/com.oplus.uxdesign' 'uxuid') | Out-String).Trim()
if ($uxUid -notmatch '^\d+$') { throw '取不到 com.oplus.uxdesign 的 uid，无法设置属主。' }
if ($uxGid -notmatch '^\d+$') { $uxGid = $uxUid }
Write-Info "uxdesign uid:gid = ${uxUid}:${uxGid}"

# 读 zip 条目
Add-Type -AssemblyName System.IO.Compression.FileSystem
$full = (Get-Item -LiteralPath $Theme).FullName
$zip = [System.IO.Compression.ZipFile]::OpenRead($full)
try {
    if (-not ($zip.Entries | Where-Object { $_.FullName -eq 'themeInfo.xml' })) {
        throw "不是 ColorOS 主题包（缺少 themeInfo.xml）：$Theme"
    }
    $entries = @()
    foreach ($e in $zip.Entries) {
        if ($e.FullName.EndsWith('/')) { continue }
        if ($e.FullName -eq 'themeInfo.xml') { continue }
        if ($e.FullName.StartsWith('picture/')) { continue }
        $entries += [pscustomobject]@{ Name = $e.FullName; Size = $e.Length }
    }
} finally { $zip.Dispose() }

Write-Info ("主题条目 {0} 个（不含 themeInfo.xml / picture）" -f $entries.Count)

# 读 /data/theme 现状
$raw = (Invoke-Root 'ls -1 /data/theme 2>/dev/null' 'lstheme' | Out-String)
$existing = @{}
foreach ($line in ($raw -split "`n")) {
    $n = $line.Trim()
    if ($n -and $n -ne 'applying' -and $n -ne 'config') { $existing[$n] = $true }
}

# 计算缺失
$missing = @()
foreach ($e in $entries) {
    $base = [regex]::Replace($e.Name, '_\d{2,3}$', '')
    if ($existing.ContainsKey($base)) { continue }
    if (-not $All -and $base -ne $e.Name) { continue }
    $missing += $e
}

if ($missing.Count -eq 0) {
    Write-Ok '/data/theme 里所有模块都在，无需补齐。'
    return
}

Write-Step '需要补写的模块：'
foreach ($m in $missing) { Write-Info ("+ {0}  {1:N1} MB" -f $m.Name, ($m.Size / 1MB)) }

$work = Join-Path $env:TEMP 'themetool_modules'
New-Item -ItemType Directory -Path $work -Force | Out-Null

$zip = [System.IO.Compression.ZipFile]::OpenRead($full)
$fail = 0
try {
    foreach ($m in $missing) {
        $entry = $zip.GetEntry($m.Name)
        if (-not $entry) { Write-Bad "zip 里找不到条目：$($m.Name)"; $fail++; continue }

        $local = Join-Path $work ([System.IO.Path]::GetFileName($m.Name))
        [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $local, $true)

        $remote = "$($script:TMP)/mod_upload.bin"
        Invoke-Adb @('push', $local, $remote) | Out-Null

        $dst = "/data/theme/$($m.Name)"
        $script = @"
cp "$remote" "$dst" || exit 1
chown ${uxUid}:${uxGid} "$dst" || exit 1
chmod 777 "$dst" || exit 1
rm -f "$remote"
stat -c %s "$dst"
"@
        $size = ((Invoke-Root $script 'putmod') | Out-String).Trim()

        if ($size -eq "$($m.Size)") { Write-Ok ("{0}  {1} bytes" -f $m.Name, $size) }
        else { Write-Bad ("{0}  期望 {1} 实得 {2}" -f $m.Name, $m.Size, $size); $fail++ }
    }
}
finally { $zip.Dispose() }

Invoke-Adb @('shell', 'am force-stop com.android.launcher') | Out-Null

Write-Host ''
if ($fail -eq 0) { Write-Ok '模块文件已补齐，桌面已重启。' }
else { Write-Warn2 "$fail 个模块写入失败，见上面的输出。" }
Write-Info '注意：文件到位不等于模块被激活；如需真正生效请重跑 apply_local_theme.ps1。'
