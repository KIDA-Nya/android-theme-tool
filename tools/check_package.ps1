<#
.SYNOPSIS
    统一包体检：按平台自动选择适配器检查主题包（只读）。

.DESCRIPTION
    支持：
      · .theme  → ColorOS 适配器（themeInfo.xml、EditorVersion、声明与内容比对）
      · .mtz    → MIUI/HyperOS 适配器（description.xml、模块目录）
      · .hwt    → EMUI/HarmonyOS 适配器（description.xml 根节点 HwTheme、模块目录）
    扩展名不认识时，会打开 zip 按描述文件猜。

    有设备时会顺带比对版本号；没有设备也能离线检查。

.PARAMETER Path    主题包路径
.PARAMETER Device  设备序列号（可选）

.EXAMPLE
    .\check_package.ps1 -Path '.\xxx.theme'
#>
param(
    [Parameter(Mandatory = $true)][string]$Path,
    [string]$Device = ''
)

. (Join-Path (Split-Path $PSScriptRoot -Parent) 'tools\common.ps1')
. (Join-Path $PSScriptRoot 'adapters\_registry.ps1')

if (-not (Test-Path -LiteralPath $Path)) { throw "找不到文件：$Path" }

$adapter = Get-AdapterForPackage -Path $Path
if (-not $adapter) {
    Write-Host ''
    Write-Host '  [x] 无法识别这个包：' -ForegroundColor Red
    Write-Host "      $Path"
    Write-Host '      既不是 .theme / .mtz / .hwt，包内也没有 themeInfo.xml 或 description.xml'
    exit 1
}

# 设备版本（有设备才比对，没有就跳过）
$devVer = ''
$devNote = '（无设备，跳过版本比对）'
try {
    Initialize-Device -Device $Device -Quiet | Out-Null
    $devVer = ((Invoke-Adb @('shell', 'getprop ro.oplus.theme.version')) | Out-String).Trim()
    if (-not $devVer) {
        $devVer = ((Invoke-Adb @('shell', 'getprop ro.build.version.emui')) | Out-String).Trim()
    }
    if ($devVer) { $devNote = "（设备版本 $devVer）" }
}
catch {
    $devNote = '（无设备或未授权，跳过版本比对）'
}

Write-Host ''
Write-Host '=============================================' -ForegroundColor DarkCyan
Write-Host ("   包体检 · {0}" -f $adapter.DisplayName) -ForegroundColor DarkCyan
Write-Host '=============================================' -ForegroundColor DarkCyan
Write-Host ("  文件: {0}" -f (Split-Path $Path -Leaf))
Write-Host ("  大小: {0:N1} MB" -f ((Get-Item -LiteralPath $Path).Length / 1MB))
Write-Host ("  适配器: {0}  {1}" -f $adapter.Name, $devNote) -ForegroundColor Gray

$r = & $adapter.TestPackage $Path $devVer

Write-Host ''
Write-Host ("  类型: {0}" -f $r.Kind)
if ($r.Info -and $r.Info.Count -gt 0) {
    Write-Host ''
    Write-Host '  关键字段:' -ForegroundColor Cyan
    foreach ($k in @('Root', 'Summary', 'Uuid', 'EditorVersion', 'title', 'title-cn', 'author', 'version', 'screen', 'RootNote')) {
        if ($r.Info.ContainsKey($k) -and $r.Info[$k]) { Write-Host ("    {0,-14} {1}" -f $k, $r.Info[$k]) -ForegroundColor Gray }
    }
    foreach ($k in @('Modules', 'KnownModules', 'TopLevel', 'Declared')) {
        if ($r.Info.ContainsKey($k)) {
            $v = @($r.Info[$k])
            if ($v.Count -gt 0) { Write-Host ("    {0,-14} {1}" -f $k, ($v -join ', ')) -ForegroundColor Gray }
        }
    }
    if ($r.Info.ContainsKey('DeclaredButAbsent')) {
        Write-Host ("    {0,-14} {1}" -f '声明但缺失', (@($r.Info['DeclaredButAbsent']) -join ', ')) -ForegroundColor Yellow
    }
}

Write-Host ''
if ($r.Ok) {
    Write-Host '  [OK] 结构检查通过' -ForegroundColor Green
}
else {
    Write-Host '  [!] 发现问题：' -ForegroundColor Yellow
    foreach ($p in $r.Problems) { Write-Host ("      - {0}" -f $p) -ForegroundColor Yellow }
}

if (-not $adapter.SupportsApply) {
    Write-Host ''
    Write-Host ("  提示：{0} 适配器只支持体检，暂不支持写入应用。" -f $adapter.Name) -ForegroundColor DarkGray
}

Write-Host ''
if ($r.Ok) { exit 0 } else { exit 2 }
