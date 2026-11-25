<#
.SYNOPSIS
    共享工具函数（被其它脚本 dot-source 引入）。

.DESCRIPTION
    解决四类共性问题：
      1. 硬编码路径 —— adb / python 自动探测，可用环境变量覆盖
      2. root 探测 —— su / ksud 多种实现，失败自动降级到 shell 身份
      3. 多层引号 —— 命令写成临时脚本再执行，避免 su -c '...' 嵌套引号被破坏
      4. 设备选择 —— 未指定时自动选择，多设备时给出明确提示
#>

$ErrorActionPreference = 'Continue'

$script:TMP = '/data/local/tmp'
$script:Adb = $null
$script:Device = ''
$script:SuCmd = $null      # 可用的 su 命令；$null 表示无 root
$script:Python = $null

# ---------------------------------------------------------------- 基础输出

function Write-Step { param([string]$m) Write-Host $m -ForegroundColor Cyan }
function Write-Ok   { param([string]$m) Write-Host "  [OK] $m" -ForegroundColor Green }
function Write-Warn2{ param([string]$m) Write-Host "  [!]  $m" -ForegroundColor Yellow }
function Write-Bad  { param([string]$m) Write-Host "  [x]  $m" -ForegroundColor Red }
function Write-Info { param([string]$m) Write-Host "       $m" -ForegroundColor Gray }

# ---------------------------------------------------------------- adb

function Resolve-Adb {
    if ($script:Adb) { return $script:Adb }

    $candidates = @()
    if ($env:THEME_ADB) { $candidates += $env:THEME_ADB }
    $candidates += @('adb', 'adb.exe')

    foreach ($c in $candidates) {
        $cmd = Get-Command $c -ErrorAction SilentlyContinue
        if ($cmd) { $script:Adb = $cmd.Source; return $script:Adb }
    }

    # 常见 SDK 位置兜底
    $roots = @(
        (Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools\adb.exe'),
        'C:\Android\platform-tools\adb.exe',
        (Join-Path $env:ProgramFiles 'Android\platform-tools\adb.exe')
    )
    foreach ($p in $roots) {
        if ($p -and (Test-Path -LiteralPath $p)) { $script:Adb = $p; return $script:Adb }
    }

    throw "找不到 adb。请安装 Android Platform Tools，或设置环境变量 THEME_ADB 指向 adb 可执行文件。"
}

function Invoke-Adb {
    param([string[]]$ArgList)
    $exe = Resolve-Adb
    if ($script:Device) { & $exe -s $script:Device @ArgList 2>&1 }
    else { & $exe @ArgList 2>&1 }
}

function Select-Device {
    param([string]$Requested = '')

    if ($Requested) { $script:Device = $Requested; return $script:Device }

    $raw = ((Invoke-Adb @('devices')) | Out-String)
    $list = @()
    foreach ($m in [regex]::Matches($raw, '(?m)^(\S+)\s+device\s*$')) { $list += $m.Groups[1].Value }

    if ($list.Count -eq 0) {
        $raw | Write-Host
        throw "没有检测到已授权的设备。`n        1) 手机：设置 → 开发者选项 → 打开「USB 调试」`n        2) 数据线连接电脑，手机弹窗点「允许」`n        3) 重新运行本脚本"
    }
    if ($list.Count -eq 1) { $script:Device = $list[0]; return $script:Device }

    Write-Warn2 "检测到多台设备："
    for ($i = 0; $i -lt $list.Count; $i++) { Write-Info ("[{0}] {1}" -f ($i + 1), $list[$i]) }
    $sel = Read-Host '  请输入序号'
    $idx = 0
    if ([int]::TryParse($sel, [ref]$idx) -and $idx -ge 1 -and $idx -le $list.Count) {
        $script:Device = $list[$idx - 1]
        return $script:Device
    }
    throw '设备选择无效。'
}

# ---------------------------------------------------------------- root / shell

function Test-Root {
    # 依次尝试：已是 root → su → ksud 软链
    if (-not $script:Device) { return $false }

    $id = (Invoke-Adb @('shell', 'id')) -join ''
    if ($id -match 'uid=0') { $script:SuCmd = ''; return $true }   # 本身即 root

    # 普通 su（Magisk / 其它）
    $probe = (Invoke-Adb @('shell', 'command -v su')) -join ''
    if ($probe -match '/su') {
        $who = (Invoke-Adb @('shell', 'su -c id')) -join ''
        if ($who -match 'uid=0') { $script:SuCmd = 'su'; return $true }
    }

    # KernelSU / ReSukiSU
    $ksud = (Invoke-Adb @('shell', 'ls /data/adb/ksud 2>/dev/null')) -join ''
    if ($ksud -match '/data/adb/ksud') {
        $sh = 'ln -sf /data/adb/ksud ' + $script:TMP + '/ksu-su; chmod 755 ' + $script:TMP + '/ksu-su'
        Invoke-Adb @('shell', $sh) | Out-Null
        $who = (Invoke-Adb @('shell', "$($script:TMP)/ksu-su -c id")) -join ''
        if ($who -match 'uid=0') { $script:SuCmd = "$($script:TMP)/ksu-su"; return $true }
    }

    $script:SuCmd = $null
    return $false
}

function Initialize-Device {
    <#
      完成设备侧准备：选设备、探 root、取应用 uid、就绪时投放解冻脚本。
      返回 $true 表示拿到 root（可选能力），$false 表示只能走 shell 身份。
    #>
    param([string]$Device = '', [string]$AppPackage = 'com.heytap.themestore')

    Select-Device $Device | Out-Null
    Write-Info "设备: $($script:Device)"

    $isRoot = Test-Root
    if ($isRoot) {
        $script:AppUid = Get-AppUid $AppPackage
        Initialize-Unfreeze $AppPackage
        $how = if ($script:SuCmd -eq '') { 'adb shell 已是 root' } else { $script:SuCmd }
        Write-Ok "root 可用（$how），$AppPackage uid=$($script:AppUid)"
    }
    else {
        Write-Warn2 '没有 root：以 shell 身份运行（投递服务仍可成功，但无法解冻/写 /data/theme）'
    }
    return $isRoot
}

function Get-AppUid {
    param([string]$Package = 'com.heytap.themestore')
    if ($script:SuCmd -eq $null) { return '' }

    $out = (Invoke-Root "stat -c %u /data/data/$Package" | Out-String).Trim()
    if ($out -match '^\d+$') { return $out }

    $dump = (Invoke-Adb @('shell', "dumpsys package $Package")) | Out-String
    $m = [regex]::Match($dump, 'userId=(\d+)')
    if ($m.Success) { return $m.Groups[1].Value }
    return ''
}

# ---------------------------------------------------------------- 安全执行

function Push-Script {
    <# 把一段 shell 命令写成 .sh 推到设备，返回远端路径 #>
    param([string]$Name, [string]$Body)

    $local = Join-Path $env:TEMP ("themetool_" + $Name + ".sh")
    $content = "#!/system/bin/sh`n" + ($Body -replace "`r`n", "`n") + "`n"
    [System.IO.File]::WriteAllText($local, $content, (New-Object System.Text.UTF8Encoding($false)))

    $remote = "$($script:TMP)/$Name.sh"
    Invoke-Adb @('push', $local, $remote) | Out-Null
    Remove-Item -LiteralPath $local -Force -ErrorAction SilentlyContinue
    Invoke-Adb @('shell', "chmod 755 $remote") | Out-Null
    return $remote
}

function Invoke-Root {
    <# 以 root 执行命令；命令走临时脚本，彻底避开嵌套引号问题 #>
    param([string]$Command, [string]$Tag = 'cmd')

    if ($script:SuCmd -eq $null) { throw '当前没有 root 权限。' }
    $remote = Push-Script $Tag $Command
    if ($script:SuCmd -eq '') { return (Invoke-Adb @('shell', $remote)) }
    return (Invoke-Adb @('shell', "$($script:SuCmd) $remote"))
}

function Invoke-Shell {
    <# 以当前 shell 身份执行（root 时自动提升） #>
    param([string]$Command, [string]$Tag = 'cmd')

    if ($script:SuCmd -ne $null) { return (Invoke-Root $Command $Tag) }
    $remote = Push-Script $Tag $Command
    return (Invoke-Adb @('shell', "sh $remote"))
}

# ---------------------------------------------------------------- 解冻

function Initialize-Unfreeze {
    <# 预先投放解冻脚本：ColorOS 的 OplusHansManager 会冻结 :applyTheme #>
    param([string]$Package = 'com.heytap.themestore')

    $uid = Get-AppUid $Package
    if (-not $uid) { return }
    $body = @'
U="$1"
[ -z "$U" ] && exit 0
F=/sys/fs/cgroup/apps/uid_$U/cgroup.freeze
[ -f "$F" ] && echo 0 > "$F" 2>/dev/null
for d in /sys/fs/cgroup/apps/uid_$U/pid_*/cgroup.freeze; do
  [ -f "$d" ] && echo 0 > "$d" 2>/dev/null
done
exit 0
'@
    $script:UnfreezeScript = Push-Script 'unfreeze' $body
    $script:AppUid = $uid
}

function Unfreeze-App {
    if ($script:SuCmd -eq $null -or -not $script:UnfreezeScript) { return }
    Invoke-Adb @('shell', "$($script:SuCmd) $($script:UnfreezeScript) $($script:AppUid)") | Out-Null
}

# ---------------------------------------------------------------- python

function Resolve-Python {
    param([string]$Prefer = '')
    if ($script:Python) { return $script:Python }

    $candidates = @()
    if ($Prefer) { $candidates += $Prefer }
    if ($env:THEME_PYTHON) { $candidates += $env:THEME_PYTHON }
    $candidates += @('python', 'python3', 'py')

    foreach ($c in $candidates) {
        if (-not $c) { continue }
        $cmd = Get-Command $c -ErrorAction SilentlyContinue
        if (-not $cmd) { continue }
        # 注意：$args 是自动变量，不能复用
        $probeArgs = @('-c', 'import sys;sys.exit(0 if sys.version_info>=(3,8) else 1)')
        & $cmd.Source @probeArgs 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) { $script:Python = $cmd.Source; return $script:Python }
    }

    throw "找不到 Python 3.8+。请安装 Python，或设置环境变量 THEME_PYTHON 指向 python 可执行文件。"
}

# ---------------------------------------------------------------- settings 读写

function Get-Setting {
    param([string]$Namespace = 'global', [string]$Key)
    return ((Invoke-Adb @('shell', "settings get $Namespace $Key")) | Out-String).Trim()
}

function Set-Setting {
    param([string]$Namespace = 'global', [string]$Key, [string]$Value)
    Invoke-Adb @('shell', "settings put $Namespace $Key $Value") | Out-Null
}

function Restore-Setting {
    param([string]$Namespace = 'global', [string]$Key, [string]$Previous)
    if ($Previous -eq 'null' -or $Previous -eq '') {
        Invoke-Adb @('shell', "settings delete $Namespace $Key") | Out-Null
    }
    else {
        Invoke-Adb @('shell', "settings put $Namespace $Key $Previous") | Out-Null
    }
}
