<#
.SYNOPSIS
    把 .theme 里的锁屏壁纸设为系统锁屏壁纸。

.DESCRIPTION
    为什么需要单独一步：
      主题包的 wallpaper 条目是内嵌 zip，同时含锁屏图与桌面图；
      但 OS12 应用路径只调用 setDesktopWallpaper，锁屏那张不会生效。
      本脚本用 tools/extract_keyguard.py 取出锁屏图，再交给 LockWall（小工具 APK）
      调用 WallpaperManager.setBitmap(FLAG_LOCK) 写入。

    图片放置位置（按优先级）：
      1. root 可用  -> 应用私有目录 /data/data/<pkg>/files/lock.jpg（最可靠）
      2. 无 root    -> 应用外部私有目录 /sdcard/Android/data/<pkg>/files/lock.jpg
      3. 再退一步   -> /sdcard/Pictures/lock.jpg + MANAGE_EXTERNAL_STORAGE
    因为 Android 11+ 上 /data/local/tmp 对普通应用不可读，
    早期版本放在那里会静默回退到内置图片，这是个真实踩过的坑。

    前置：设备已安装 lockwall.apk（tools\build-lockwall.ps1 -Install）。

.PARAMETER Theme    .theme 路径（自动提取锁屏图）
.PARAMETER Image    也可直接指定一张图片
.PARAMETER Desktop  同时设为桌面壁纸
.PARAMETER Device   指定设备序列号

.EXAMPLE
    .\set_lock_wallpaper.ps1 -Theme '.\纳西妲.theme'
#>
param(
    [Parameter(Mandatory = $true, ParameterSetName = 'Theme')]
    [string]$Theme,
    [Parameter(Mandatory = $true, ParameterSetName = 'Image')]
    [string]$Image,
    [switch]$Desktop,
    [string]$Device = ''
)

. (Join-Path $PSScriptRoot 'common.ps1')

$LOCKPKG = 'com.keke.lockwall'
$EXTRACT = Join-Path $PSScriptRoot 'extract_keyguard.py'
$WORK = Join-Path $env:TEMP 'themetool_lockwall'
$LOCKFILE = '/data/system/users/0/wallpaper_lock'

# ---------------------------------------------------------------- 取图

if ($PSCmdlet.ParameterSetName -eq 'Theme') {
    if (-not (Test-Path -LiteralPath $Theme)) { throw "找不到主题：$Theme" }
    if (-not (Test-Path -LiteralPath $EXTRACT)) { throw "缺少工具脚本：$EXTRACT" }

    $py = Resolve-Python
    New-Item -ItemType Directory -Path $WORK -Force | Out-Null
    $out = & $py -X utf8 $EXTRACT ((Get-Item -LiteralPath $Theme).FullName) $WORK 2>&1
    if ($LASTEXITCODE -ne 0) { throw ("提取锁屏壁纸失败：{0}" -f (($out | Out-String).Trim())) }

    $candidate = @($out | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ -and (Test-Path -LiteralPath $_) })
    if ($candidate.Count -eq 0) { throw '提取锁屏壁纸失败：未得到文件路径' }
    $Image = $candidate[-1]
    Write-Ok "提取到：$Image"
}

if (-not (Test-Path -LiteralPath $Image)) { throw "找不到图片：$Image" }
$imgItem = Get-Item -LiteralPath $Image

# ---------------------------------------------------------------- 设备

Initialize-Device -Device $Device | Out-Null

$installed = (Invoke-Adb @('shell', "pm list packages $LOCKPKG")) | Out-String
if ($installed -notmatch [regex]::Escape($LOCKPKG)) {
    throw "设备未安装 $LOCKPKG。请先运行 tools\build-lockwall.ps1 -Install。"
}

# ---------------------------------------------------------------- 投放到应用可读位置

$remote = ''
$appUid = ''
if ($SuCmd -ne $null) {
    $appUid = ((Invoke-Root "stat -c %u /data/data/$LOCKPKG" 'lockuid') | Out-String).Trim()
}

$stage = "$($TMP)/lock_stage.bin"
$pushed = (Invoke-Adb @('push', $imgItem.FullName, $stage)) | Out-String
if ($pushed -notmatch 'pushed|skipped') { throw "推送图片失败：$($pushed.Trim())" }

if ($appUid -match '^\d+$') {
    # 应用私有目录最可靠
    $private = "/data/data/$LOCKPKG/files/lock.jpg"
    $body = @"
mkdir -p /data/data/$LOCKPKG/files || exit 1
cp "$stage" "$private" || exit 1
chown ${appUid}:${appUid} "$private" || exit 1
chmod 600 "$private" || exit 1
rm -f "$stage"
stat -c '%s|%U' "$private"
"@
    $check = ((Invoke-Root $body 'putlock') | Out-String).Trim()
    if ($check -match '^\d+\|') {
        $remote = $private
        Write-Info "图片已就位（应用私有目录）：$private  [$check]"
    }
}

if (-not $remote) {
    # 无 root 或私有目录写入失败：用外部私有目录
    $extDir = "/sdcard/Android/data/$LOCKPKG/files"
    Invoke-Adb @('shell', "mkdir -p $extDir") | Out-Null
    $ext = "$extDir/lock.jpg"
    $mv = (Invoke-Adb @('shell', "cp $stage $ext && chmod 644 $ext && rm -f $stage && echo OK")) | Out-String
    if ($mv -match 'OK') {
        $remote = $ext
        Write-Info "图片已就位（外部私有目录）：$ext"
    }
}

if (-not $remote) {
    $fallback = '/sdcard/Pictures/lock.jpg'
    Invoke-Adb @('shell', "cp $stage $fallback; rm -f $stage") | Out-Null
    Invoke-Adb @('shell', "appops set $LOCKPKG MANAGE_EXTERNAL_STORAGE allow") | Out-Null
    $remote = $fallback
    Write-Warn2 "退回到公共目录：$fallback"
}

# ---------------------------------------------------------------- 记录旧状态

$beforeLock = ''
$beforeDesk = ''
if ($SuCmd -ne $null) {
    $beforeLock = ((Invoke-Root "stat -c %Y $LOCKFILE 2>/dev/null" 'lockmtime') | Out-String).Trim()
    $beforeDesk = ((Invoke-Root "stat -c %Y /data/system/users/0/wallpaper 2>/dev/null" 'deskmtime') | Out-String).Trim()
}

# ---------------------------------------------------------------- 调用 LockWall

if ($Desktop) { Write-Info '-Desktop：LockWall 会同时设置锁屏与桌面（which=3），系统随后删除 wallpaper_lock' }
$extra = if ($Desktop) { ' --ez desktop true' } else { '' }
Invoke-Adb @('logcat', '-c') | Out-Null
Invoke-Adb @('shell', "am start -W -n $LOCKPKG/.Main --es path $remote$extra") | Out-Null
Start-Sleep -Seconds 5

# ---------------------------------------------------------------- 校验

Write-Host ''
Write-Step '=== 结果 ==='
$log = (Invoke-Adb @('logcat', '-d', '-v', 'brief')) 2>&1 | ForEach-Object { [string]$_ }
$mine = $log | Where-Object { $_ -match 'I/LockWall|E/LockWall|W/LockWall' }
if ($mine) { $mine | Select-Object -Last 6 | ForEach-Object { Write-Host ('  ' + $_.Trim()) -ForegroundColor Gray } }
else { Write-Warn2 '未捕获到 LockWall 日志（应用可能未启动）' }

# 关键判定：必须确认用的是 path 指定的文件，而不是内置图
$usedAsset = ($log | Where-Object { $_ -match 'from=asset|内置图' } | Measure-Object).Count -gt 0
$usedFile = ($log | Where-Object { $_ -match 'source=file:' } | Measure-Object).Count -gt 0

if ($usedAsset -and -not $usedFile) {
    Write-Bad 'LockWall 回退到了内置图片：它读不到指定文件。'
    Write-Info "  尝试过的路径：$remote"
    Write-Info '  这是 Android 11+ 的存储访问限制；有 root 时本脚本会写入应用私有目录。'
    return
}

if ($SuCmd -eq $null) {
    Write-Info '无 root：无法核对 wallpaper_lock，请自行锁屏确认。'
    return
}

# 校验：
#   -Desktop  → which=SYSTEM|LOCK，系统会删除 wallpaper_lock（锁屏跟随桌面），看 wallpaper
#   只设锁屏   → 看 wallpaper_lock
#   首选「把系统里那张图拉下来和源图做像素比对」，因为它不受「重复设同一张图时 mtime 不变」影响。
$target = if ($Desktop) { '/data/system/users/0/wallpaper' } else { $LOCKFILE }
$targetName = if ($Desktop) { 'wallpaper（桌面+锁屏）' } else { 'wallpaper_lock（锁屏）' }
$beforeT = if ($Desktop) { $beforeDesk } else { $beforeLock }

$afterT = ((Invoke-Root "stat -c %Y $target 2>/dev/null" 'wmtime') | Out-String).Trim()

$pixelOk = $null
if ($SuCmd -ne $null) {
    $diffPy = Join-Path (Split-Path $PSScriptRoot -Parent) 'tests\pixel_diff.py'
    if (Test-Path -LiteralPath $diffPy) {
        try { $pyv = Resolve-Python } catch { $pyv = $null }
        if ($pyv) {
            $tmpW = Join-Path $env:TEMP 'wallpaper_check.bin'
            Invoke-Root "cp $target /data/local/tmp/_wcheck.bin; chmod 644 /data/local/tmp/_wcheck.bin" 'wcheck' | Out-Null
            Invoke-Adb @('pull', '/data/local/tmp/_wcheck.bin', $tmpW) | Out-Null
            Invoke-Root 'rm -f /data/local/tmp/_wcheck.bin' 'wclean' | Out-Null
            if (Test-Path -LiteralPath $tmpW) {
                & $pyv -X utf8 $diffPy $tmpW $Image '6.0' | ForEach-Object { Write-Host ('  ' + $_) -ForegroundColor Gray }
                $pixelOk = ($LASTEXITCODE -eq 0)
            }
        }
    }
}

if ($pixelOk -eq $true) {
    Write-Ok "$targetName 已写入（像素比对一致，时间戳 $afterT）"
}
elseif ($pixelOk -eq $false) {
    Write-Bad "$targetName 与源图不一致，可能没有真正写入。"
}
elseif (-not $afterT) {
    Write-Bad "未生成 $targetName，设置失败。"
}
elseif ($beforeT -and $afterT -eq $beforeT) {
    Write-Warn2 "$targetName 时间戳未变化（$afterT）；若刚设过同一张图属正常，否则可能没写入。"
}
else {
    Write-Ok "$targetName 已写入（时间戳 $afterT）"
}

# 清理
Invoke-Root "rm -f /data/data/$LOCKPKG/files/lock.jpg" 'cleanlock' | Out-Null
Invoke-Adb @('shell', "rm -f '$remote'") | Out-Null
