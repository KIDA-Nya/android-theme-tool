<#
.SYNOPSIS
    监视"主题有没有被系统改回去"，用于验证方案能不能长期稳定。

.DESCRIPTION
    不同平台能观测到的信号不一样，脚本按平台取可读的证据：
      · ColorOS  UUID + /data/theme 模块清单 + config 时间戳
      · MIUI    商店库 .data 的条目数与最新时间；有 root 时再看 /data/system/theme
      · 华为/荣耀 /data/themes（需 root）、Huawei|Honor Themes 目录
      · vivo    /sdcard/Android/data/com.bbk.theme；有 root 时看 /data/bbkcore/theme
    任何一项变化都会立刻标出来，并把整段采样写成 CSV。

.PARAMETER Minutes   持续观察多少分钟（默认 10）
.PARAMETER Interval  采样间隔秒（默认 30）
.PARAMETER Reboot    观察前先重启一次，再对比重启前后（最硬的稳定性测试）
.PARAMETER Csv       采样明细写到这个文件

.EXAMPLE
    .\watch_theme.ps1 -Minutes 30
    .\watch_theme.ps1 -Reboot -Minutes 5
#>
param(
    [int]$Minutes = 10,
    [int]$Interval = 30,
    [switch]$Reboot,
    [string]$Csv = '',
    [string]$Device = ''
)

. (Join-Path $PSScriptRoot 'common.ps1')
. (Join-Path $PSScriptRoot 'adapters\_registry.ps1')

Initialize-Device -Device $Device -Quiet | Out-Null
$hit = Get-AdapterCatalog | Where-Object { $_.Present } | Select-Object -First 1
$platform = if ($hit) { $hit.Name } else { 'unknown' }
Write-Info "平台：$platform    采样：每 ${Interval}s，共 ${Minutes}min"

function Invoke-Sh {
    param([string]$Cmd)
    try {
        $out = ((Invoke-Adb @('shell', $Cmd)) | Out-String).Trim()
        if ($out -match 'adb\.exe: (error|device)|error: (closed|device)') { return $null }
        return $out
    }
    catch { return $null }
}

function Wait-DeviceReady {
    <# 重启后必须等真正可用：能连上 + 开机完成 + 能读到设置 #>
    param([int]$TimeoutSec = 300)
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        # 不能用 adb wait-for-device：它没有超时，设备回不来就永久挂住
        $state = ((Invoke-Adb @('get-state')) | Out-String).Trim()
        if ($state -eq 'device') {
            $boot = (Invoke-Sh 'getprop sys.boot_completed')
            $probe = (Invoke-Sh 'settings get global adb_enabled')
            if ($boot -match '1' -and $null -ne $probe) { return $true }
        }
        Start-Sleep -Seconds 5
    }
    return $false
}

function Get-Snapshot {
    $snap = [ordered]@{ time = (Get-Date -Format 'HH:mm:ss'); ok = 'yes' }
    $nulls = 0

    switch ($platform) {
        'coloros' {
            $snap['uuid'] = (Get-Setting global 'applied_default_theme_package_name')
            $snap['modules'] = (Invoke-Sh '[ -r /data/theme ] && { ls -1 /data/theme | tr "\n" ","; } || echo __NA__')
            $snap['configMtime'] = (Invoke-Sh '[ -f /data/theme/config ] && stat -c %Y /data/theme/config || echo __NA__')
            $snap['iconsMtime'] = (Invoke-Sh '[ -e /data/theme/icons ] && stat -c %Y /data/theme/icons || echo __NA__')
        }
        'miui' {
            $snap['libraryCount'] = (Invoke-Sh "ls -1 /sdcard/Android/data/com.android.thememanager/files/MIUI/theme/.data/meta/theme 2>/dev/null | wc -l")
            $snap['libraryNewest'] = (Invoke-Sh "ls -1t /sdcard/Android/data/com.android.thememanager/files/MIUI/theme/.data/meta/theme 2>/dev/null | head -1")
            $snap['applied'] = (Invoke-Sh '[ -r /data/system/theme ] && { ls -1 /data/system/theme | tr "\n" ","; } || echo __NA__')
        }
        'emui' {
            $snap['dataThemes'] = (Invoke-Sh '[ -r /data/themes ] && ls -1 /data/themes | wc -l || echo __NA__')
            $snap['hwThemes'] = (Invoke-Sh "ls -1 /sdcard/Huawei/Themes 2>/dev/null | wc -l")
            $snap['honorThemes'] = (Invoke-Sh "ls -1 /sdcard/Android/data/com.hihonor.android.thememanager/files/Download/Honor/Themes 2>/dev/null | wc -l")
        }
        'vivo' {
            $snap['themeData'] = (Invoke-Sh "ls -1 /sdcard/Android/data/com.bbk.theme 2>/dev/null | wc -l")
            $snap['core'] = (Invoke-Sh '[ -r /data/bbkcore/theme ] && ls -1 /data/bbkcore/theme | wc -l || echo __NA__')
        }
        default {
            $snap['packages'] = (Invoke-Sh "pm list packages 2>/dev/null | wc -l")
        }
    }
    foreach ($k in @($snap.Keys)) {
        if ($k -in @('time', 'ok')) { continue }
        if ($null -eq $snap[$k] -or "$($snap[$k])" -eq '__NA__') { $nulls++ }
    }
    if ($nulls -gt 0) { $snap['ok'] = 'unavailable' }
    return [pscustomobject]$snap
}

function Format-Snapshot {
    param($Snap)
    $parts = @()
    foreach ($k in $Snap.PSObject.Properties.Name) {
        if ($k -eq 'time') { continue }
        $v = $Snap.$k
        if ("$v".Length -gt 40) { $v = "$v".Substring(0, 37) + '...' }
        $parts += ('{0}={1}' -f $k, $v)
    }
    return ($parts -join '  ')
}

$rows = New-Object System.Collections.ArrayList
function Add-Row {
    param($Snap)
    [void]$rows.Add($Snap)
    Write-Host ('  [{0}] {1}' -f $Snap.time, (Format-Snapshot $Snap)) -ForegroundColor Gray
}

Write-Step '基线'
$base = Get-Snapshot
Add-Row $base

if ($Reboot) {
    Write-Step '重启设备（验证能否扛过重启）'
    Invoke-Adb @('reboot') | Out-Null
    Start-Sleep -Seconds 15
    if (-not (Wait-DeviceReady -TimeoutSec 420)) { Write-Bad '设备未在 7 分钟内就绪'; return }
    Write-Ok '已开机并就绪'
    Start-Sleep -Seconds 8

    $after = Get-Snapshot
    Add-Row $after
    $diff = @()
    foreach ($k in $base.PSObject.Properties.Name) {
        if ($k -in @('time', 'ok')) { continue }
        if ("$($base.$k)" -ne "$($after.$k)") { $diff += $k }
    }
    if ($diff.Count -eq 0) { Write-Ok '重启前后完全一致 —— 扛过重启' }
    else { Write-Warn2 ("重启后有变化：{0}" -f ($diff -join ', ')) }
}

$deadline = (Get-Date).AddMinutes($Minutes)
$changes = 0
$prev = if ($Reboot -and $after) { $after } else { $base }
Write-Step "持续观察 $Minutes 分钟"
while ((Get-Date) -lt $deadline) {
    Start-Sleep -Seconds $Interval
    $cur = Get-Snapshot

    if ($cur.ok -ne 'yes' -or $prev.ok -ne 'yes') {
        Write-Host ('  [{0}] 设备暂不可用，跳过本次采样' -f $cur.time) -ForegroundColor DarkGray
        continue
    }

    $diff = @()
    foreach ($k in $prev.PSObject.Properties.Name) {
        if ($k -in @('time', 'ok')) { continue }
        if ("$($prev.$k)" -ne "$($cur.$k)") { $diff += $k }
    }

    if ($diff.Count -eq 0) {
        Write-Host ('  [{0}] 无变化' -f $cur.time) -ForegroundColor DarkGray
    }
    else {
        $changes++
        Add-Row $cur
        Write-Warn2 ("  变化字段：{0}" -f ($diff -join ', '))
    }
    $prev = $cur
}

Write-Host ''
if ($changes -eq 0) { Write-Ok "观察期结束：$Minutes 分钟内没有任何变化" }
else { Write-Warn2 "观察期结束：发生 $changes 次变化（见上方记录）" }

if ($Csv) {
    try {
        $rows | Export-Csv -LiteralPath $Csv -NoTypeInformation -Encoding UTF8
        Write-Info "明细已写入：$Csv"
    }
    catch { Write-Warn2 "写 CSV 失败：$($_.Exception.Message)" }
}
