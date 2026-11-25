<#
.SYNOPSIS
    主题一键控制台（交互式菜单）。

.DESCRIPTION
    把「体检 / 应用 / 只设锁屏 / 查看状态 / 恢复默认 / 补齐模块」串成一个菜单，
    自动发现设备与本地主题包。

.EXAMPLE
    .\theme_console.ps1
    .\theme_console.ps1 -Action status
#>
[CmdletBinding()]
param(
    [ValidateSet('menu', 'status', 'apply', 'revert', 'help')]
    [string]$Action = 'menu',
    [string]$Theme = '',
    [string]$Device = ''
)

. (Join-Path $PSScriptRoot 'common.ps1')

$here = $PSScriptRoot
$root = Split-Path $here -Parent
$APPLY = Join-Path $here 'apply_local_theme.ps1'
$LOCK = Join-Path $here 'set_lock_wallpaper.ps1'
$FILL = Join-Path $here 'push_modules.ps1'
$CHECK = Join-Path $here 'check_theme.py'

function Line { param([string]$c = 'DarkGray') Write-Host ('-' * 62) -ForegroundColor $c }
function Title { param([string]$t) Write-Host ''; Write-Host "  $t" -ForegroundColor Cyan; Line }
function Ok { param([string]$t) Write-Host "  [OK] $t" -ForegroundColor Green }
function Warn2 { param([string]$t) Write-Host "  [!]  $t" -ForegroundColor Yellow }
function Bad { param([string]$t) Write-Host "  [x]  $t" -ForegroundColor Red }
function Info { param([string]$t) Write-Host "       $t" -ForegroundColor Gray }
function Pause2 { Write-Host ''; Write-Host '  按回车继续...' -ForegroundColor DarkGray; [void](Read-Host) }
function Clear-Screen { try { Clear-Host } catch { } }

function Get-Devices {
    try {
        $raw = ((Invoke-Adb @('devices')) | Out-String)
    }
    catch {
        return @()
    }
    $list = @()
    foreach ($m in [regex]::Matches($raw, '(?m)^(\S+)\s+device\s*$')) { $list += $m.Groups[1].Value }
    return , $list
}

function Pick-Device {
    if ($Device) { return $Device }
    $ds = Get-Devices
    if ($ds.Count -eq 0) {
        Bad '没有检测到设备'
        Info '1) 手机：设置 → 开发者选项 → 打开「USB 调试」'
        Info '2) 数据线连接电脑，手机弹窗点「允许」'
        Info '3) 回来后重试'
        return $null
    }
    if ($ds.Count -eq 1) { Ok "设备已连接：$($ds[0])"; return $ds[0] }

    Warn2 '检测到多台设备：'
    for ($i = 0; $i -lt $ds.Count; $i++) { Info ("[{0}] {1}" -f ($i + 1), $ds[$i]) }
    $sel = Read-Host '  请输入序号'
    $idx = 0
    if ([int]::TryParse($sel, [ref]$idx) -and $idx -ge 1 -and $idx -le $ds.Count) { return $ds[$idx - 1] }
    Bad '选择无效'
    return $null
}

function Get-LocalThemes {
    $result = @()
    foreach ($d in @($root, (Join-Path $root 'themes'), (Join-Path $root 'build'))) {
        if (-not (Test-Path -LiteralPath $d)) { continue }
        $result += @(Get-ChildItem -LiteralPath $d -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Extension -eq '.theme' -or $_.Extension -eq '.hwt' })
    }
    return , @($result | Sort-Object LastWriteTime -Descending)
}

function Pick-Theme {
    if ($Theme) {
        if (Test-Path -LiteralPath $Theme) { return (Get-Item -LiteralPath $Theme).FullName }
        Bad "找不到：$Theme"
        return $null
    }
    $files = Get-LocalThemes
    Title '选择主题包'
    if ($files.Count -eq 0) {
        Warn2 "在 $root 里没找到 .theme / .hwt"
        Info '把主题文件放进去，或直接输入完整路径（可把文件拖进本窗口）'
        $p = (Read-Host '  路径').Trim('"', ' ')
        if ($p -and (Test-Path -LiteralPath $p)) { return (Get-Item -LiteralPath $p).FullName }
        Bad '路径无效'
        return $null
    }
    for ($i = 0; $i -lt $files.Count; $i++) {
        $f = $files[$i]
        Info ("[{0}] {1}   {2:N1} MB   {3:yyyy-MM-dd}" -f ($i + 1), $f.Name, ($f.Length / 1MB), $f.LastWriteTime)
    }
    Info '[0] 手动输入路径'
    $sel = Read-Host '  请输入序号'
    $idx = 0
    if ([int]::TryParse($sel, [ref]$idx)) {
        if ($idx -eq 0) {
            $p = (Read-Host '  路径').Trim('"', ' ')
            if ($p -and (Test-Path -LiteralPath $p)) { return (Get-Item -LiteralPath $p).FullName }
            Bad '路径无效'
            return $null
        }
        if ($idx -ge 1 -and $idx -le $files.Count) { return $files[$idx - 1].FullName }
    }
    Bad '选择无效'
    return $null
}

function Do-Apply {
    $dev = Pick-Device
    if (-not $dev) { Pause2; return }
    $t = Pick-Theme
    if (-not $t) { Pause2; return }

    Title '开始应用'
    Info '过程中请保持手机亮屏、不要锁屏、不要拔线（约 2~5 分钟）'
    Info '应用成功后会接着把锁屏壁纸换成主题里的那张'
    Write-Host ''
    # 不强制 -Root：脚本自己探测，有 root 用 root，没有则降级为 shell 身份
    & $APPLY -Theme $t -Device $dev

    Write-Host ''
    Ok '完成。若桌面图标没刷新，锁屏再解锁一次即可。'
    Pause2
}

function Do-Check {
    $t = Pick-Theme
    if (-not $t) { Pause2; return }
    Title '主题包体检'
    try {
        $py = Resolve-Python
        $dev = Pick-Device
        # 注意：$args 是自动变量，这里必须用别的名字
        $cliArgs = @('-X', 'utf8', $CHECK, $t)
        if ($dev) {
            $ver = ((Invoke-Adb @('shell', 'getprop ro.oplus.theme.version')) | Out-String).Trim()
            if ($ver) { $cliArgs += @('--device-version', $ver) }
        }
        & $py @cliArgs | ForEach-Object { Write-Host ('  ' + $_) }
    }
    catch {
        Bad $_.Exception.Message
    }
    Pause2
}

function Do-LockOnly {
    $dev = Pick-Device
    if (-not $dev) { Pause2; return }
    $t = Pick-Theme
    if (-not $t) { Pause2; return }
    Title '只设置锁屏壁纸'
    & $LOCK -Theme $t -Device $dev
    Write-Host ''
    Ok '完成。'
    Pause2
}

function Do-Revert {
    $dev = Pick-Device
    if (-not $dev) { Pause2; return }
    Warn2 '将恢复系统默认主题（当前主题会被替换）'
    $ans = Read-Host '  确认？(y/N)'
    if ($ans -notmatch '^[yY]') { Info '已取消'; Pause2; return }
    & $APPLY -Revert -Device $dev
    Pause2
}

function Do-Status {
    $dev = Pick-Device
    if (-not $dev) { Pause2; return }
    & $APPLY -Verify -Device $dev
    Pause2
}

function Do-FillModules {
    $dev = Pick-Device
    if (-not $dev) { Pause2; return }
    $t = Pick-Theme
    if (-not $t) { Pause2; return }
    Title '按内容补齐缺失模块'
    & $FILL -Theme $t -Device $dev
    Pause2
}

function Show-Help {
    Title '使用说明'
    Info '功能：把 .theme 主题应用到 ColorOS'
    Info '      （壁纸 / 系统UI / 设置 / 短信 / 联系人 / 图标 / 桌面）'
    Info '      并可选把主题里的锁屏壁纸设为系统锁屏壁纸'
    Info ''
    Info '准备：手机开 USB 调试并授权；电脑已装 adb 与 Python 3.8+'
    Info "主题：把 .theme 放进 $root"
    Info ''
    Info '注意：主题的 EditorVersion 必须等于手机 ro.oplus.theme.version，'
    Info '      不匹配会被 ThemeOSVersion 检查中止（体检会提示）'
    Info ''
    Info '环境变量（可选）：'
    Info '  THEME_ADB     adb 可执行文件路径'
    Info '  THEME_PYTHON  python 可执行文件路径'
    Pause2
}

function Main-Menu {
    while ($true) {
        Clear-Screen
        Write-Host ''
        Write-Host '  ======================================================' -ForegroundColor DarkCyan
        Write-Host '              主题一键工具  ·  ColorOS' -ForegroundColor DarkCyan
        Write-Host '  ======================================================' -ForegroundColor DarkCyan
        $ds = Get-Devices
        if ($ds.Count -gt 0) { Ok "已连接：$($ds[0])" } else { Warn2 '未连接设备（插线并授权 USB 调试）' }
        $files = Get-LocalThemes
        if ($files.Count -gt 0) { Info "本地主题：$($files.Count) 个" } else { Warn2 "本地主题：$root 下没有 .theme 文件" }
        Line
        Write-Host '   [1]  主题包体检（应用前建议先跑一次）'
        Write-Host '   [2]  应用主题（自动含锁屏壁纸）'
        Write-Host '   [3]  只设置锁屏壁纸'
        Write-Host '   [4]  查看当前主题状态'
        Write-Host '   [5]  恢复系统默认主题'
        Write-Host '   [6]  按内容补齐缺失模块（需 root）'
        Write-Host '   [7]  使用说明'
        Write-Host '   [0]  退出'
        Line
        $c = (Read-Host '   请输入序号').Trim()
        switch ($c) {
            '1' { Do-Check }
            '2' { Do-Apply }
            '3' { Do-LockOnly }
            '4' { Do-Status }
            '5' { Do-Revert }
            '6' { Do-FillModules }
            '7' { Show-Help }
            '0' { return }
        }
    }
}

switch ($Action) {
    'menu' { Main-Menu }
    'status' { Do-Status }
    'apply' { Do-Apply }
    'revert' { Do-Revert }
    'help' { Show-Help }
}
