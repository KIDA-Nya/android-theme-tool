<#
.SYNOPSIS
    兼容性探测：判断当前设备能否用本工具，以及缺什么。

.DESCRIPTION
    只读操作，不改任何东西。用于"换机型/换 ROM 后能不能用"的快速判断。
    需要 adb；有 root 时信息更全（能看到 /data/theme 属主等）。

.PARAMETER Device  指定设备序列号

.EXAMPLE
    .\probe.ps1
#>
param([string]$Device = '')

. (Join-Path $PSScriptRoot 'common.ps1')

$rows = New-Object System.Collections.ArrayList
function Add-Row {
    param([string]$Item, [string]$Value, [string]$Status = '')  # OK / WARN / FAIL / INFO
    [void]$rows.Add([pscustomobject]@{ Item = $Item; Value = $Value; Status = $Status })
}
function Say-Status {
    param([string]$s)
    switch ($s) {
        'OK' { return '✓' }
        'WARN' { return '!' }
        'FAIL' { return '✗' }
        default { return '·' }
    }
}

Write-Host ''
Write-Host '=============================================' -ForegroundColor DarkCyan
Write-Host '   ColorOS 主题工具 · 兼容性探测' -ForegroundColor DarkCyan
Write-Host '=============================================' -ForegroundColor DarkCyan

# ---------------------------------------------------------------- adb / 设备
try { $adbPath = Resolve-Adb; Add-Row 'adb' $adbPath 'OK' }
catch { Add-Row 'adb' $_.Exception.Message 'FAIL'; }

try {
    Select-Device $Device | Out-Null
    Add-Row '设备' $script:Device 'OK'
}
catch {
    Add-Row '设备' '未连接/未授权' 'FAIL'
}

if (-not $script:Device) {
    # 没有设备也要能给出结论
    Write-Host ''
    foreach ($r in $rows) { Write-Host ("  {0} {1,-14} {2}" -f (Say-Status $r.Status), $r.Item, $r.Value) }
    Write-Host ''
    Write-Warning '没有可用设备，无法继续探测。'
    exit 1
}

# ---------------------------------------------------------------- 身份
$id = ((Invoke-Adb @('shell', 'id')) | Out-String).Trim()
$isRoot = $id -match 'uid=0'
$isShell = $id -match 'uid=2000'
$hasRoot = Test-Root
Add-Row '执行身份' $id $(if ($hasRoot) { 'OK' } elseif ($isShell) { 'OK' } else { 'WARN' })

# ---------------------------------------------------------------- 主题商店
$store = $null
try {
    $store = Resolve-ThemeStore
    Add-Row '主题商店包' $store.Package 'OK'
    Add-Row '服务组件' $store.Service 'OK'

    $dump = ((Invoke-Adb @('shell', "dumpsys package $($store.Package)")) | Out-String)
    $perm = if ($dump -match 'oppo\.permission\.OPPO_COMPONENT_SAFE') { 'oppo.permission.OPPO_COMPONENT_SAFE' }
            elseif ($dump -match 'oplus\.permission\.OPLUS_COMPONENT_SAFE') { 'oplus.permission.OPLUS_COMPONENT_SAFE' }
            else { '（未检测到）' }
    Add-Row '服务权限要求' $perm $(if ($perm -match 'COMPONENT_SAFE') { 'OK' } else { 'WARN' })
}
catch {
    Add-Row '主题商店包' $_.Exception.Message 'FAIL'
}

# ---------------------------------------------------------------- 主题版本 / 当前主题
$ver = ((Invoke-Adb @('shell', 'getprop ro.oplus.theme.version')) | Out-String).Trim()
Add-Row 'ro.oplus.theme.version' $(if ($ver) { $ver } else { '（空）' }) $(if ($ver) { 'OK' } else { 'WARN' })

$cur = ((Invoke-Adb @('shell', 'settings get global applied_default_theme_package_name')) | Out-String).Trim()
Add-Row '当前主题 UUID' $(if ($cur -and $cur -ne 'null') { $cur } else { '（未设置）' }) 'INFO'

# ---------------------------------------------------------------- uxdesign
$ux = ((Invoke-Adb @('shell', 'pm list packages com.oplus.uxdesign')) | Out-String)
$hasUx = $ux -match 'com\.oplus\.uxdesign'
Add-Row 'uxdesign' $(if ($hasUx) { '已安装（OS12+ 应用通道）' } else { '未安装（可能走旧版通道）' }) $(if ($hasUx) { 'OK' } else { 'WARN' })

# ---------------------------------------------------------------- /data/theme
$themeDir = ((Invoke-Adb @('shell', 'ls -1 /data/theme 2>/dev/null')) | Out-String).Trim()
if ($themeDir) {
    $n = ($themeDir -split "`n").Count
    Add-Row '/data/theme' "存在（$n 项）" 'OK'
    if ($hasRoot) {
        # 注意：不要给 stat 的格式串加引号——PowerShell 5.1 调原生程序会吞掉引号，
        # 远端 sh 会把 "%a" 当成文件名。这里拆成两个无空格格式。
        $own = ((Invoke-Adb @('shell', 'stat -c %U:%G /data/theme')) | Out-String).Trim()
        $mod = ((Invoke-Adb @('shell', 'stat -c %a /data/theme')) | Out-String).Trim()
        $owner = "$own  mode=$mod"
        Add-Row '/data/theme 属主' $owner 'INFO'
    }
}
else { Add-Row '/data/theme' '不存在或不可读' $(if ($hasRoot) { 'FAIL' } else { 'WARN' }) }

# ---------------------------------------------------------------- 冻结控制
$freeze = ((Invoke-Adb @('shell', 'ls -d /sys/fs/cgroup/apps 2>/dev/null')) | Out-String)
$hasFreeze = $freeze -match 'cgroup/apps'
Add-Row '冻结控制(cgroup v2)' $(if ($hasFreeze) { '可用，失败时能自动解冻' } else { '不可用，失败需手动重试' }) $(if ($hasFreeze) { 'OK' } else { 'WARN' })

# ---------------------------------------------------------------- 可选组件
$lockwall = ((Invoke-Adb @('shell', 'pm list packages com.keke.lockwall')) | Out-String)
Add-Row 'LockWall' $(if ($lockwall -match 'lockwall') { '已安装' } else { '未安装（锁屏壁纸不可用）' }) $(if ($lockwall -match 'lockwall') { 'OK' } else { 'INFO' })

try { $py = Resolve-Python; Add-Row 'Python' $py 'OK' }
catch { Add-Row 'Python' '未找到（无法自动对齐声明，需 -NoAlign）' 'WARN' }

# ---------------------------------------------------------------- 结论
Write-Host ''
foreach ($r in $rows) {
    $color = switch ($r.Status) { 'OK' { 'Green' } 'WARN' { 'Yellow' } 'FAIL' { 'Red' } default { 'Gray' } }
    Write-Host ("  {0} {1,-22} {2}" -f (Say-Status $r.Status), $r.Item, $r.Value) -ForegroundColor $color
}

Write-Host ''
$fails = @($rows | Where-Object { $_.Status -eq 'FAIL' })
$warns = @($rows | Where-Object { $_.Status -eq 'WARN' })

if ($fails.Count -gt 0) {
    Write-Host '  结论：不可用' -ForegroundColor Red
    foreach ($f in $fails) { Write-Host ("    - {0}: {1}" -f $f.Item, $f.Value) -ForegroundColor Red }
}
elseif (-not $hasRoot -and -not $isShell) {
    Write-Host '  结论：权限不足' -ForegroundColor Yellow
    Write-Host '    投递服务需要 shell/root 身份（签名级权限）。请用 adb shell 或 root 运行。'
}
elseif ($warns.Count -gt 0) {
    Write-Host '  结论：可用，但有降级项' -ForegroundColor Yellow
    foreach ($w in $warns) { Write-Host ("    - {0}: {1}" -f $w.Item, $w.Value) }
}
else {
    Write-Host '  结论：完全可用' -ForegroundColor Green
}
Write-Host ''
Write-Host '  说明：本方案依赖 ColorOS 主题栈（ThemeApplyService + uxdesign + /data/theme）。' -ForegroundColor DarkGray
Write-Host '        华为/小米/三星等其它品牌没有这套组件，不适用。' -ForegroundColor DarkGray
Write-Host ''
