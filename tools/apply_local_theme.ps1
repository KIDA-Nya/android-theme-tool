<#
.SYNOPSIS
    把本地 .theme 主题包应用到 ColorOS 系统，并自动对齐模块声明。

.DESCRIPTION
    原理：直接向主题商店导出的 ThemeApplyService 投递 THEME_PATH，
    等价于在商店里点「应用」；随后由 uxdesign 落盘到 /data/theme。

    两条路径的模块识别差异（本脚本已抹平）：
      · 商店 UI 路径 (apply/n9b) —— 扫描 zip 实际条目
      · ThemeApplyService 捷径   —— 只认 themeInfo.xml 的 <packageInfo>
    因此默认会先做「对齐」：扫描真实条目、补全声明，避免 icons / launcher 被漏掉。

    环境要求：
      · adb（可用 THEME_ADB 指定）
      · Python 3.8+（可用 THEME_PYTHON 指定；仅 -NoAlign 时不需要）
      · root 可选：有 root 时可自动解冻进程、核对已落盘模块

.PARAMETER Theme     本地 .theme / .hwt 路径
.PARAMETER Revert    恢复系统默认主题
.PARAMETER Verify    只查看当前主题状态
.PARAMETER NoAlign   跳过声明对齐（直接应用原包）
.PARAMETER NoLock    不自动设置锁屏壁纸（默认跟随主题一起换）
.PARAMETER Force     已是当前主题时不先切回默认
.PARAMETER Ask       应用后询问是否换锁屏壁纸（默认直接换）
.PARAMETER Root      要求 root；不可用时自动降级为 shell 身份
.PARAMETER KeepRemote 应用成功后保留设备上的临时主题文件
.PARAMETER Device    指定设备序列号（多设备时需要）

.EXAMPLE
    .\apply_local_theme.ps1 -Theme '.\纳西妲.theme'

.EXAMPLE
    .\apply_local_theme.ps1 -Verify

.EXAMPLE
    .\apply_local_theme.ps1 -Revert
#>
[CmdletBinding(DefaultParameterSetName = 'Apply')]
param(
    [Parameter(ParameterSetName = 'Apply', Mandatory = $true)]
    [string]$Theme,
    [Parameter(ParameterSetName = 'Revert', Mandatory = $true)]
    [switch]$Revert,
    [Parameter(ParameterSetName = 'Verify', Mandatory = $true)]
    [switch]$Verify,
    [switch]$NoAlign,
    [switch]$NoLock,
    [switch]$Force,
    [switch]$Ask,
    [switch]$Root,
    [switch]$KeepRemote,
    [string]$Device = ''
)

. (Join-Path $PSScriptRoot 'common.ps1')

# 包名与服务组件由 common.ps1 的 Resolve-ThemeStore 探测后填充（不同 ROM 可能不同）
$PKG = ''
$SVC = ''
$REMOTE = '/sdcard/Download/theme_apply.theme'
$ALIGN_PY = Join-Path $PSScriptRoot 'theme_align.py'

# ---------------------------------------------------------------- 工具

function Get-ThemeInfo {
    <# 读取 themeInfo.xml 的关键字段；不是 ColorOS 主题包时抛出明确错误 #>
    param([string]$Path)

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $full = (Get-Item -LiteralPath $Path).FullName
    $zip = [System.IO.Compression.ZipFile]::OpenRead($full)
    try {
        $entry = $zip.Entries | Where-Object { $_.FullName -eq 'themeInfo.xml' } | Select-Object -First 1
        if (-not $entry) {
            throw "不是 ColorOS 主题包：$Path 缺少根级 themeInfo.xml（商店 inner 格式不被此通道接受）"
        }
        $reader = New-Object System.IO.StreamReader($entry.Open())
        try { [xml]$x = $reader.ReadToEnd() } finally { $reader.Dispose() }

        $rootNode = $x.OplusSmartPhoneThemeInfo
        if (-not $rootNode) { throw "themeInfo.xml 根节点不是 OplusSmartPhoneThemeInfo：$Path" }

        $pkgs = @()
        foreach ($p in @($rootNode.packageInfo.package)) {
            if ($p -and $p.name) { $pkgs += $p.name }
        }
        return [pscustomobject]@{
            Path   = $full
            Uuid   = "$($rootNode.UUID)".Trim()
            Editor = "$($rootNode.EditorVersion)".Trim()
            Name   = "$($rootNode.Summary)".Trim()
            Pkgs   = $pkgs
        }
    }
    finally { $zip.Dispose() }
}

function Show-ThemeState {
    param([string]$ExpectUuid = '')

    $uuid = Get-Setting global 'applied_default_theme_package_name'
    $ver = ((Invoke-Adb @('shell', 'getprop ro.oplus.theme.version')) | Out-String).Trim()

    Write-Host ''
    Write-Step '=== 当前系统主题 ==='
    if ($ExpectUuid) {
        if ($uuid -eq $ExpectUuid) { Write-Ok "UUID : $uuid（与所选主题一致）" }
        else { Write-Warn2 ("UUID : {0}（与所选主题 {1} 不一致）" -f $uuid, $ExpectUuid) }
    }
    else { Write-Info "UUID : $uuid" }
    Write-Info "主题版本 : $ver"

    if ($SuCmd -eq $null) {
        Write-Info '已应用模块 : （需要 root 才能读取 /data/theme）'
        return @()
    }

    $raw = (Invoke-Root 'for f in /data/theme/*; do stat -c "%n|%s|%y" "$f" 2>/dev/null; done' 'ls_theme' | Out-String)
    Write-Host ''
    Write-Step '=== 已应用模块 ==='
    Write-Host ("    {0,-26} {1,10}  {2}" -f '模块', '大小', '时间')
    $names = @()
    foreach ($line in ($raw -split "`n")) {
        $parts = $line.Trim() -split '\|'
        if ($parts.Count -lt 3) { continue }
        $n = [System.IO.Path]::GetFileName($parts[0])
        if (-not $n -or $n -eq 'applying' -or $n -eq 'config') { continue }
        $names += $n
        $size = '{0:N1} MB' -f ([double]$parts[1] / 1MB)
        $ts = if ($parts[2].Length -ge 16) { $parts[2].Substring(0, 16) } else { $parts[2] }
        Write-Host ("    {0,-26} {1,10}  {2}" -f $n, $size, $ts) -ForegroundColor Gray
    }
    return $names
}

function Get-ZipModules {
    <# 返回 zip 里真实存在的模块基名（如 icons / com.android.settings），不含 themeInfo.xml 与 picture #>
    param([string]$Path)
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $names = @()
    $zip = [System.IO.Compression.ZipFile]::OpenRead((Get-Item -LiteralPath $Path).FullName)
    try {
        foreach ($e in $zip.Entries) {
            if ($e.FullName.EndsWith('/')) { continue }
            if ($e.FullName -eq 'themeInfo.xml') { continue }
            if ($e.FullName.StartsWith('picture/')) { continue }
            $names += [regex]::Replace($e.FullName, '_\d{2,3}$', '')
        }
    }
    finally { $zip.Dispose() }
    return $names
}

function Test-ModulesApplied {
    <# 核对「声明过的模块」是否真的落盘，返回缺失列表 #>
    param([string[]]$Declared, [string[]]$Present)

    $missing = @()
    foreach ($d in $Declared) {
        $base = [regex]::Replace($d, '_\d{2,3}$', '')
        if ($Present -contains $base) { continue }
        if ($Present -contains $d) { continue }
        $missing += $d
    }
    return $missing
}

# ---------------------------------------------------------------- 初始化

$hasRoot = Initialize-Device -Device $Device
$PKG = $script:ThemePkg
$SVC = $script:ThemeSvc
if ($Root -and -not $hasRoot) {
    Write-Warn2 '要求 root 但未取得，将以 shell 身份继续（无法解冻进程，失败时请重试）'
}

if ($Verify) {
    Show-ThemeState | Out-Null
    return
}

# ---------------------------------------------------------------- 恢复默认

if ($PSCmdlet.ParameterSetName -eq 'Revert') {
    Write-Step '恢复系统默认主题 ...'
    Invoke-Adb @('shell', 'input keyevent KEYCODE_WAKEUP') | Out-Null
    Invoke-Shell "am startservice -n $SVC --es THEME_PATH Defult_Theme" 'revert' | Out-Null
    for ($i = 1; $i -le 12; $i++) {
        Start-Sleep -Seconds 5
        Unfreeze-App
        if ((Get-Setting global 'applied_default_theme_package_name') -ne 'null') {
            $cur = Get-Setting global 'applied_default_theme_package_name'
            if ($cur -ne '' -and $i -gt 2) { break }
        }
    }
    Show-ThemeState | Out-Null
    Write-Host ''
    Write-Ok '已请求恢复默认主题；若外观未变，锁屏一次或重启桌面。'
    return
}

# ---------------------------------------------------------------- 校验主题

if (-not (Test-Path -LiteralPath $Theme)) { throw "找不到主题文件：$Theme" }
$fi = Get-Item -LiteralPath $Theme
Write-Info ("主题包: {0} ({1:N1} MB)" -f $fi.Name, ($fi.Length / 1MB))

$info = Get-ThemeInfo $fi.FullName
$devVer = ((Invoke-Adb @('shell', 'getprop ro.oplus.theme.version')) | Out-String).Trim()
Write-Info "UUID         : $($info.Uuid)"
Write-Info "EditorVersion: $($info.Editor)    设备: $devVer"
Write-Info ("原声明       : {0} 项 — {1}" -f $info.Pkgs.Count, ($info.Pkgs -join ', '))

if ($info.Editor -ne $devVer) {
    Write-Warn2 "版本不匹配：应用会走 'ThemeOSVersion is diff' 分支中止。"
    Write-Info '  解决：换适配本机版本的主题，或改 themeInfo.xml 的 EditorVersion 后重新打包。'
    $answer = Read-Host '  仍要继续？(y/N)'
    if ($answer -notmatch '^[yY]') { Write-Bad '已取消'; return }
}

# ---------------------------------------------------------------- 对齐声明

$toPush = $info.Path
if ($NoAlign) {
    Write-Info '已跳过对齐（-NoAlign）'
}
elseif (-not $ALIGN_PY -or -not (Test-Path -LiteralPath $ALIGN_PY)) {
    $toPush = $fi.FullName
    Write-Warn2 "找不到 theme_align.py，跳过对齐（icons 可能不生效）"
}
else {
    try {
        $py = Resolve-Python
        Write-Step '对齐模块声明（扫描 zip 实际条目）...'
        $aligned = Join-Path $env:TEMP ('aligned_' + [System.IO.Path]::GetFileNameWithoutExtension($fi.Name) + '.theme')
        & $py -X utf8 $ALIGN_PY $fi.FullName $aligned | ForEach-Object { Write-Info $_ }
        if ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $aligned)) {
            $toPush = $aligned
            $newInfo = Get-ThemeInfo $aligned
            Write-Ok ("对齐后声明 {0} 项 — {1}" -f $newInfo.Pkgs.Count, ($newInfo.Pkgs -join ', '))
            $info = $newInfo
        }
        else {
            Write-Warn2 '对齐失败，使用原包'
        }
    }
    catch {
        Write-Warn2 $_.Exception.Message
        Write-Info '  跳过对齐；若图标未生效，请手工在 themeInfo.xml 补 <package name="icons" .../>'
    }
}

# ---------------------------------------------------------------- 推送

Write-Step '推送主题到设备 ...'
$pushed = (Invoke-Adb @('push', $toPush, $REMOTE)) | Out-String
if ($pushed -notmatch 'pushed|skipped') { Write-Warn2 $pushed.Trim() }
Invoke-Shell "appops set $PKG MANAGE_EXTERNAL_STORAGE allow" 'appops' | Out-Null

# ---------------------------------------------------------------- 备份并调整系统设置

Write-Step '准备环境（亮屏 / 防冻结）...'
$prevFreezer = Get-Setting global 'cached_apps_freezer'
$prevStayon = ((Invoke-Adb @('shell', 'svc power get stayon')) | Out-String).Trim()

Invoke-Adb @('shell', 'input keyevent KEYCODE_WAKEUP') | Out-Null
Invoke-Adb @('shell', 'svc power stayon true') | Out-Null
Set-Setting global 'cached_apps_freezer' 'disabled'

# ---------------------------------------------------------------- 已是当前主题则先切回默认

$cur0 = Get-Setting global 'applied_default_theme_package_name'
if (-not $Force -and $cur0 -eq $info.Uuid) {
    Write-Warn2 '当前已是该主题：系统会按 UUID 判定「无需重做」而空转。'
    if ($hasRoot) {
        Write-Step '先切回默认主题以强制重新应用 ...'
        Invoke-Shell "am startservice -n $SVC --es THEME_PATH Defult_Theme" 'revert' | Out-Null
        for ($k = 0; $k -lt 12; $k++) {
            Start-Sleep -Seconds 5
            Unfreeze-App
            if ((Get-Setting global 'applied_default_theme_package_name') -ne $info.Uuid) { break }
        }
        $now = Get-Setting global 'applied_default_theme_package_name'
        Write-Info "  当前 UUID：$now"
        if ($now -eq $info.Uuid) {
            Write-Warn2 '切回默认失败。可改用 tools\newuuid.py 生成新 UUID 的副本后重试。'
        }
    }
    else {
        Write-Warn2 '无 root，无法切回默认。建议用 tools\newuuid.py 换 UUID 后重试。'
    }
}

# ---------------------------------------------------------------- 触发

Write-Step ("触发 ThemeApplyService（{0}）..." -f $(if ($hasRoot) { 'root' } else { 'shell' }))
$startUuid = Get-Setting global 'applied_default_theme_package_name'
Invoke-Adb @('shell', "am force-stop $PKG") | Out-Null
Start-Sleep -Seconds 2
Invoke-Adb @('logcat', '-c') | Out-Null
$dispatch = (Invoke-Shell "am startservice -n $SVC --es THEME_PATH $REMOTE" 'apply') | Out-String
if ($dispatch -match 'Error|Exception|denied') { Write-Warn2 $dispatch.Trim() }

# ---------------------------------------------------------------- 等待完成

Write-Step '等待应用完成（最多 5 分钟，期间自动解冻）...'
# 判定成功有两条依据：
#   1) UUID 由「别的值」变成目标值 —— 最可靠，不受日志刷屏影响
#   2) 日志里出现 apply success —— 辅助确认
$ok = $false
for ($i = 1; $i -le 20; $i++) {
    Start-Sleep -Seconds 15
    Unfreeze-App
    $cur = Get-Setting global 'applied_default_theme_package_name'
    $succ = ((Invoke-Adb @('logcat', '-d', '-s', 'ApplyColorThemeFromOS12', 'TSpace.ApplyColorThemeFromOS12', '-v', 'brief')) 2>&1 |
        Select-String -SimpleMatch 'apply success' | Measure-Object).Count -gt 0
    $switched = ($cur -eq $info.Uuid) -and ($startUuid -ne $info.Uuid)
    Write-Host ("  t={0,3}s  uuid={1}  log={2}  switched={3}" -f ($i * 15), $cur, $succ, $switched) -ForegroundColor Gray
    if ($succ -or $switched) { $ok = $true; break }
}

# ---------------------------------------------------------------- 还原设置

if ($prevStayon -notmatch 'true') { Invoke-Adb @('shell', 'svc power stayon false') | Out-Null }
Restore-Setting global 'cached_apps_freezer' $prevFreezer

# ---------------------------------------------------------------- 结果

Write-Host ''
Write-Step '=== 关键日志 ==='
$log = (Invoke-Adb @('logcat', '-d', '-s', 'ApplyColorThemeFromOS12', 'TSpace.ApplyColorThemeFromOS12',
        'ThemeApplyService', 'TSpace.ThemeApplyService', 'TSpace.CommonApplyFlag_UxAidlHelper', '-v', 'brief')) 2>&1 |
    ForEach-Object { [string]$_ }
$interesting = $log | Where-Object { $_ -match 'unzip package|apply success|EACCES|Permission Denial|apply fail' }
if ($interesting) { $interesting | Select-Object -Last 16 | ForEach-Object { Write-Host ('  ' + $_.Trim()) -ForegroundColor Gray } }
else { Write-Info '（日志缓冲区已滚动，未取到；以 UUID 与模块列表为准）' }

$present = Show-ThemeState $info.Uuid

if ($ok) {
    if ($present.Count -gt 0) {
        # 只关心「zip 里确实有」的模块：声明了但包内没有的，本就不会落盘
        $zipMods = Get-ZipModules $info.Path
        $expected = @($info.Pkgs | Where-Object { $zipMods -contains ([regex]::Replace($_, '_\d{2,3}$', '')) })
        $missing = Test-ModulesApplied $expected $present
        if ($missing.Count -gt 0) {
            Write-Warn2 ("包内有内容但未落盘：{0}" -f ($missing -join ', '))
            Write-Info '  可重试一次；仍缺则用 tools\push_modules.ps1 补齐。'
        }
        else {
            Write-Ok ("包内 {0} 个模块全部落盘。" -f $expected.Count)
        }
    }
    Write-Host ''
    Write-Ok '应用成功。'
}
else {
    Write-Host ''
    Write-Warn2 '未确认成功（日志未出现 apply success）。'
    Write-Info '  1) 保持亮屏后重试一次（进程可能被 ColorOS 冻结）'
    Write-Info '  2) 若仍是同一主题，用 tools\newuuid.py 换 UUID 后重试'
    Write-Info '  3) 桌面图标未刷新：adb shell am force-stop com.android.launcher'
}

# ---------------------------------------------------------------- 锁屏壁纸

if ($ok -and -not $NoLock -and $PSCmdlet.ParameterSetName -eq 'Apply') {
    $doLock = $true
    if ($Ask) {
        $answer = Read-Host '  是否同时把锁屏壁纸换成这个主题里的那张？(Y/n)'
        if ($answer -match '^[nN]') { $doLock = $false }
    }
    if ($doLock) {
        $lockScript = Join-Path $PSScriptRoot 'set_lock_wallpaper.ps1'
        if (Test-Path -LiteralPath $lockScript) {
            Write-Host ''
            Write-Step '=== 设置锁屏壁纸 ==='
            & $lockScript -Theme $fi.FullName -Device $script:Device
        }
        else { Write-Warn2 '找不到 set_lock_wallpaper.ps1，跳过锁屏壁纸' }
    }
}

# ---------------------------------------------------------------- 清理

if ($ok -and -not $KeepRemote) {
    Invoke-Adb @('shell', "rm -f $REMOTE") | Out-Null
}
