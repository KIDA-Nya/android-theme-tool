<#
.SYNOPSIS
    把主题包"交给"系统主题商店，让它用自己的权限完成导入（不做特权投递）。

.DESCRIPTION
    适用场景：目标机型没有可调用的应用接口（MIUI / 华为 都是这样），
    但商店自己有"本地导入"能力。本脚本只负责两件事：
      1) 把包放到商店能扫到/能选到的地方
      2) 拉起商店界面，并告诉你点哪里

    各平台的路子（都有公开依据）：
      · 华为 / 荣耀  /sdcard/Huawei/Themes/<x>.hwt
                      → 主题 App「我的 → 主题」出现条目，点「应用」
                      （华为开发者问答 & 多个社区教程一致）
      · MIUI / HyperOS 商店没有声明任何接收本地主题文件的 intent
                      （manifest 里 SEND/OPENABLE/file:// 全为 0），
                      所以只能：放到 Download → 商店里「本地导入」→ 选文件
      · ColorOS        已支持直接投递，本脚本只提示用 apply_local_theme.ps1

.PARAMETER Theme   主题包路径
.PARAMETER Platform  强制指定平台（coloros / miui / huawei），默认自动探测
.PARAMETER NoOpen  只放文件，不拉起商店

.EXAMPLE
    .\route_to_store.ps1 -Theme '.\某主题.hwt'
#>
param(
    [Parameter(Mandatory = $true)][string]$Theme,
    [ValidateSet('auto', 'coloros', 'miui', 'huawei', 'honor', 'vivo')][string]$Platform = 'auto',
    [switch]$NoOpen,
    [string]$Device = ''
)

. (Join-Path $PSScriptRoot 'common.ps1')

if (-not (Test-Path -LiteralPath $Theme)) { throw "找不到主题：$Theme" }
$fi = Get-Item -LiteralPath $Theme
$ext = [System.IO.Path]::GetExtension($fi.Name).ToLowerInvariant()

Initialize-Device -Device $Device | Out-Null

# ---------------------------------------------------------------- 平台判定
if ($Platform -eq 'auto') {
    $pkgs = ((Invoke-Adb @('shell', 'pm list packages')) | Out-String)
    if ($pkgs -match 'com\.heytap\.themestore|com\.oplus\.themestore') { $Platform = 'coloros' }
    elseif ($pkgs -match 'com\.android\.thememanager') { $Platform = 'miui' }
    elseif ($pkgs -match 'com\.hihonor\.android\.thememanager') { $Platform = 'honor' }
    elseif ($pkgs -match 'com\.huawei\.android\.thememanager') { $Platform = 'huawei' }
    elseif ($pkgs -match 'com\.bbk\.theme|com\.vivo\.themestore') { $Platform = 'vivo' }
    else { $Platform = 'unknown' }
}
Write-Info "平台：$Platform"

switch ($Platform) {

    'coloros' {
        Write-Ok 'ColorOS 支持直接投递，不需要"交给商店"'
        Write-Info '  用：tools\apply_local_theme.ps1 -Theme <路径>'
        Write-Info '  或：tools\adb-apply.sh <路径>'
        return
    }

    'huawei' {
        $dest = '/sdcard/Huawei/Themes'
        Invoke-Adb @('shell', "mkdir -p $dest") | Out-Null
        $remote = "$dest/$($fi.Name)"
        $r = (Invoke-Adb @('push', $fi.FullName, $remote)) | Out-String
        if ($r -notmatch 'pushed|skipped') { Write-Bad "推送失败：$($r.Trim())"; return }
        Write-Ok "已放入：$remote"

        if (-not $NoOpen) {
            Invoke-Adb @('shell', 'monkey -p com.huawei.android.thememanager -c android.intent.category.LAUNCHER 1') | Out-Null
            Start-Sleep -Seconds 2
        }

        Write-Host ''
        Write-Step '接下来手动两步（商店用自己的权限导入）'
        Write-Info '  1) 主题 App → 底部「我的」→「主题」'
        Write-Info '  2) 找到刚放进去的主题 → 点「应用」'
        Write-Host ''
        Write-Warn2 '注意：鸿蒙 5 / 高版本 MagicOS 已收紧该目录，可能扫不到（社区反馈）'
        return
    }

    'honor' {
        # 新荣耀（2023-11 之后出厂）用自己的主题 App 与 .hnt 格式
        $dest = '/sdcard/Android/data/com.hihonor.android.thememanager/files/Download/Honor/Themes'
        Invoke-Adb @('shell', "mkdir -p $dest") | Out-Null
        $remote = "$dest/$($fi.Name)"
        $r = (Invoke-Adb @('push', $fi.FullName, $remote)) | Out-String
        if ($r -notmatch 'pushed|skipped') { Write-Bad "推送失败：$($r.Trim())"; return }
        Write-Ok "已放入：$remote"

        if (-not $NoOpen) {
            Invoke-Adb @('shell', 'monkey -p com.hihonor.android.thememanager -c android.intent.category.LAUNCHER 1') | Out-Null
            Start-Sleep -Seconds 2
        }

        Write-Host ''
        Write-Step '接下来手动两步'
        Write-Info '  1) 荣耀主题 App → 我的 → 主题'
        Write-Info '  2) 找到刚放进去的主题 → 应用'
        Write-Host ''
        Write-Warn2 '荣耀第三方主题建议用「鸿蒙 .hwt」，并按 MagicOS 版本选：'
        Write-Info '  MagicUI / MagicOS 7 → 鸿蒙 2；MagicOS 8 → 鸿蒙 3；MagicOS 9/10 → 鸿蒙 4'
        Write-Info '  .hnt 是荣耀官方编辑器导出的格式，第三方主题不推荐'
        Write-Info '  MagicOS 6+ 对第三方主题识别变差，必要时重启或降级主题 App'
        return
    }

    'vivo' {
        $remote = "/sdcard/Download/$($fi.Name)"
        $r = (Invoke-Adb @('push', $fi.FullName, $remote)) | Out-String
        if ($r -notmatch 'pushed|skipped') { Write-Bad "推送失败：$($r.Trim())"; return }
        Write-Ok "已放入：$remote"

        if (-not $NoOpen) {
            Invoke-Adb @('shell', 'monkey -p com.bbk.theme -c android.intent.category.LAUNCHER 1') | Out-Null
            Start-Sleep -Seconds 2
        }

        Write-Host ''
        Write-Step '接下来手动三步（i主题自己导入 + 应用）'
        Write-Info '  1) i主题 → 我的 → 主题 → 本地主题 → 导入'
        Write-Info '  2) 选 Download 里的这个 .itz'
        Write-Info '  3) 导入后点「应用」'
        Write-Host ''
        Write-Warn2 '前提：2023 年后机型、≥ OriginOS 4，且必须能卸载 i主题与 vivo 文档'
        Write-Info '  OriginOS 6 起不再支持第三方主题；作者本人也已停止维护 vivo'
        Write-Info '  已知参考实现会拒绝「包内自带字体」的 itz，导入失败可先去掉 fonts/'
        Write-Info '  vivo 也有私有 Binder 写入通道，但需要真机反查接口，本项目未实现'
        return
    }

    'miui' {
        $remote = "/sdcard/Download/$($fi.Name)"
        $r = (Invoke-Adb @('push', $fi.FullName, $remote)) | Out-String
        if ($r -notmatch 'pushed|skipped') { Write-Bad "推送失败：$($r.Trim())"; return }
        Write-Ok "已放入：$remote"

        if (-not $NoOpen) {
            Invoke-Adb @('shell', 'monkey -p com.android.thememanager -c android.intent.category.LAUNCHER 1') | Out-Null
            Start-Sleep -Seconds 2
        }

        Write-Host ''
        Write-Step '接下来手动三步（商店自己导入 + 应用）'
        Write-Info '  1) 主题 App → 我的 → 主题 → 「从本地导入」（或右上角菜单里的本地导入）'
        Write-Info '  2) 选 Download 里的这个文件'
        Write-Info '  3) 导入后点「应用」'
        Write-Host ''
        Write-Warn2 '受内容 DRM 限制：商店主题/他人分享的受保护主题，点应用仍会被拦（见 docs/VENDOR-FINDINGS.md 第八节）'
        Write-Info '  想要"双击文件就进商店"，MIUI 没给这个入口——manifest 里没有接收本地主题文件的 intent'
        return
    }

    default {
        # 未知平台：折中——放 Download 并通过 ACTION_VIEW 尝试交给系统选应用
        $remote = "/sdcard/Download/$($fi.Name)"
        Invoke-Adb @('push', $fi.FullName, $remote) | Out-Null
        Write-Warn2 "没认出平台，已放到 $remote"
        Write-Info '  可用下面这条让系统自己选打开方式：'
        Write-Info "  adb shell am start -a android.intent.action.VIEW -d file://$remote -t application/octet-stream"
        return
    }
}
