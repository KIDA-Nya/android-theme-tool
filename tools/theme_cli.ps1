<#
.SYNOPSIS
    统一入口：按当前设备的平台自动选择合适的做法。

.DESCRIPTION
    这是"多系统适配"的那一层——你不需要记每个品牌该用哪个脚本：

        ColorOS  → 直接投递（apply_local_theme.ps1）
        MIUI     → 交给商店（route_to_store.ps1）+ 可选的 backup 注入
        华为/荣耀 → 交给商店（放 Huawei/Themes 或荣耀目录）
        vivo     → 交给商店（放 Download，走 i主题 本地主题）
        其它     → 只做包体检 + 说明

.PARAMETER Action
    status | check | apply | route | backup | restore | watch | probe

.PARAMETER Theme
    check / apply / route 需要的主题包路径

.EXAMPLE
    .\theme_cli.ps1 status
    .\theme_cli.ps1 check -Theme '.\某主题.hwt'
    .\theme_cli.ps1 apply -Theme '.\某主题.theme'      # ColorOS 会真的应用；其它平台会转为"交给商店"
#>
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateSet('status', 'check', 'apply', 'route', 'backup', 'restore', 'watch', 'probe')]
    [string]$Action,

    [Parameter(Position = 1)]
    [string]$Theme = '',

    [int]$Minutes = 10,
    [switch]$Reboot,
    [switch]$DryRun,
    [string]$Device = ''
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')
. (Join-Path $PSScriptRoot 'adapters\_registry.ps1')

$here = $PSScriptRoot

function Get-Platform {
    Initialize-Device -Device $Device -Quiet | Out-Null
    $hit = Get-AdapterCatalog | Where-Object { $_.Present } | Select-Object -First 1
    if ($hit) { return $hit }
    return $null
}

function Get-PackageHint {
    param([string]$Path)
    $ext = [System.IO.Path]::GetExtension($Path).ToLowerInvariant()
    switch ($ext) {
        '.theme' { return 'ColorOS（.theme）' }
        '.mtz' { return 'MIUI / HyperOS（.mtz）' }
        '.hwt' { return '华为 / 荣耀（.hwt）' }
        '.hnt' { return '荣耀（.hnt）' }
        '.itz' { return 'vivo / iQOO（.itz）' }
        default { return "未知（$ext）" }
    }
}

Write-Host ''
Write-Host '  Android 主题工具' -ForegroundColor DarkCyan
Write-Host '  ----------------------------------------' -ForegroundColor DarkCyan

$platform = Get-Platform
if (-not $platform) {
    Write-Warn2 '没有识别到已适配的平台（可能是未支持品牌，或设备未连接）'
    Write-Info '  跑 `theme_cli.ps1 probe` 看完整探测结果'
    if ($Action -ne 'probe') { return }
}
else {
    Write-Info ("平台：{0}    可写入：{1}" -f $platform.Name, $(if ($platform.SupportsApply) { '是' } else { '否' }))
}

switch ($Action) {

    'probe' {
        & (Join-Path $here 'probe.ps1') -Device $Device
    }

    'status' {
        if ($platform.Name -eq 'coloros') {
            & (Join-Path $here 'apply_local_theme.ps1') -Verify
        }
        else {
            Write-Step '当前状态'
            foreach ($e in $platform.Evidence) { Write-Info "  $e" }
            Write-Host ''
            Write-Info "$($platform.DisplayName)：$($platform.Reason)"
            Write-Info '  该平台没有可查询的"当前主题"设置项，只能看商店里显示的主题名'
        }
    }

    'check' {
        if (-not $Theme) { Write-Bad '需要 -Theme <主题包路径>'; return }
        & (Join-Path $here 'check_package.ps1') -Path $Theme -Device $Device
    }

    'apply' {
        if (-not $Theme) { Write-Bad '需要 -Theme <主题包路径>'; return }
        if (-not (Test-Path -LiteralPath $Theme)) { Write-Bad "找不到：$Theme"; return }

        Write-Info ("包格式：{0}" -f (Get-PackageHint $Theme))

        if ($platform.Name -eq 'coloros') {
            Write-Step 'ColorOS：直接投递'
            $args = @('-Theme', $Theme)
            if ($DryRun) { Write-Warn2 '-DryRun 仅对"交给商店"有效，ColorOS 走真实投递'; }
            & (Join-Path $here 'apply_local_theme.ps1') @args
            return
        }

        # 其它平台：转为"交给商店"，并明确说明为什么不能直接应用
        Write-Step '该平台不支持直接投递，改用「交给商店」'
        Write-Info "  原因：$($platform.Reason)"
        if ($DryRun) { Write-Info '  （-DryRun：只打印计划）' }
        & (Join-Path $here 'route_to_store.ps1') -Theme $Theme -Platform $platform.Name -Device $Device
    }

    'route' {
        if (-not $Theme) { Write-Bad '需要 -Theme <主题包路径>'; return }
        if (-not (Test-Path -LiteralPath $Theme)) { Write-Bad "找不到：$Theme"; return }
        $p = if ($platform) { $platform.Name } else { 'auto' }
        & (Join-Path $here 'route_to_store.ps1') -Theme $Theme -Platform $p -Device $Device
    }

    'backup' {
        if (-not $platform -or $platform.Name -ne 'coloros') {
            Write-Bad '备份只对 ColorOS 有效（要读 /data/theme）'
            return
        }
        & (Join-Path $here 'apply_local_theme.ps1') -Backup
    }

    'restore' {
        if (-not $platform -or $platform.Name -ne 'coloros') {
            Write-Bad '恢复只对 ColorOS 有效（要写 /data/theme 并改属主）'
            return
        }
        & (Join-Path $here 'apply_local_theme.ps1') -Restore
    }

    'watch' {
        $a = @('-Minutes', $Minutes)
        if ($Reboot) { $a += '-Reboot' }
        & (Join-Path $here 'watch_theme.ps1') @a
    }
}

Write-Host ''
