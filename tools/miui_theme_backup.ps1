<#
.SYNOPSIS
    HyperOS / MIUI 免 root 换主题组件：把 .mtz 的模块注入商店的 "Theme backup"。

.DESCRIPTION
    为什么这样做（详见 docs/MIUI-THEME-BACKUP.md）：
      · 商店把主题库放在 /sdcard/Android/data/com.android.thememanager/files/MIUI/theme/.data
        —— 这个目录 shell(uid 2000) 可读写，而 /data/system/theme 不行。
      · "Theme backup" 是商店自己「定制主题」时生成的主题，没有 rights 记录，
        应用时不需要联网授权；手动塞进去的主题则会被 DRM 拦。
      · 所以不新建主题，而是把已有 backup 的某个组件（content/<code>/<id>.mrc）
        换成我们的文件，并同步 meta 里的 hash/size。

    应用时由商店自己把组件拷进 /data/system/theme —— 权限仍在商店手里。

.PARAMETER Mtz       提供模块的主题包
.PARAMETER List      只列出设备上的主题与组件
.PARAMETER Theme     要注入的 Theme backup 的 localId
.PARAMETER Component 模块代码，默认 icons
.PARAMETER DryRun    只拉库并打印计划，不回推

.EXAMPLE
    .\miui_theme_backup.ps1 -List
    .\miui_theme_backup.ps1 -Mtz '.\某主题.mtz' -Theme <localId> -Component icons
#>
param(
    [string]$Mtz = '',
    [switch]$List,
    [string]$Theme = '',
    [string]$Component = 'icons',
    [switch]$DryRun,
    [string]$Device = ''
)

. (Join-Path $PSScriptRoot 'common.ps1')

$PKG = 'com.android.thememanager'
$REMOTE = "/sdcard/Android/data/$PKG/files/MIUI/theme/.data"
$TOOL = Join-Path $PSScriptRoot 'miui_backup_inject.py'

Initialize-Device -Device $Device -Quiet | Out-Null

$pkgs = ((Invoke-Adb @('shell', 'pm list packages')) | Out-String)
if ($pkgs -notmatch [regex]::Escape($PKG)) {
    Write-Bad "设备上没有 $PKG，这不是 MIUI/HyperOS"
    return
}
if (-not (Test-Path -LiteralPath $TOOL)) { Write-Bad "缺少 $TOOL"; return }
try { $py = Resolve-Python } catch { Write-Bad "需要 Python：$($_.Exception.Message)"; return }

$work = Join-Path $env:TEMP ('miui_data_' + [guid]::NewGuid().ToString('N').Substring(0, 6))
New-Item -ItemType Directory -Path $work -Force | Out-Null

Write-Step '拉取商店主题库（shell 可读）...'
$r = (Invoke-Adb @('pull', $REMOTE, $work)) | Out-String
$dataDir = Join-Path $work '.data'
if (-not (Test-Path -LiteralPath $dataDir)) {
    Write-Bad "拉取失败：$($r.Trim())"
    Write-Info '  提示：该目录需要 shell 身份可读；若无 Theme backup，先在手机上「定制主题 → 改一项 → 应用」'
    return
}
Write-Ok "已拉到：$dataDir"

if ($List -or -not $Mtz) {
    & $py -X utf8 $TOOL --data $dataDir --list
    if (-not $Mtz) { Write-Info '  要注入请加 -Mtz <主题.mtz> -Theme <localId>' }
    return
}

if (-not $Theme) { Write-Bad '缺少 -Theme（可先用 -List 看 localId）'; return }
if (-not (Test-Path -LiteralPath $Mtz)) { Write-Bad "找不到主题包：$Mtz"; return }

$report = Join-Path $work 'changed.json'
$cliArgs = @('-X', 'utf8', $TOOL, '--data', $dataDir, '--theme', $Theme,
    '--mtz', (Get-Item -LiteralPath $Mtz).FullName, '--component', $Component,
    '--report', $report)
if ($DryRun) { $cliArgs += '--dry-run' }

Write-Step '注入 ...'
& $py @cliArgs
if ($LASTEXITCODE -ne 0) { Write-Bad '注入失败'; return }

if ($DryRun) { Write-Info '（-DryRun，未回推）'; return }

# 只回推改动过的文件
if (-not (Test-Path -LiteralPath $report)) { Write-Bad '没有生成变更清单，放弃回推'; return }
$changed = (Get-Content -LiteralPath $report -Raw | ConvertFrom-Json).changed
Write-Step "回推 $($changed.Count) 个文件 ..."
$ok = 0
foreach ($rel in $changed) {
    $local = Join-Path $dataDir ($rel -replace '/', '\')
    $remote = "$REMOTE/$rel"
    $dir = ($remote -replace '/[^/]+$', '')
    Invoke-Adb @('shell', "mkdir -p '$dir'") | Out-Null
    $out = (Invoke-Adb @('push', $local, $remote)) | Out-String
    if ($out -match 'pushed|skipped') { $ok++ } else { Write-Warn2 "推送失败：$rel" }
}
Write-Ok "已回推 $ok/$($changed.Count) 个文件"

Invoke-Adb @('shell', "am force-stop $PKG") | Out-Null
Write-Info '已强制停止主题商店，让它下次启动时重新读库'

Write-Host ''
Write-Step '接下来在手机上两步'
Write-Info '  1) 打开主题应用 → 我的 → 主题 → 选中那个「Theme backup」→ 应用'
Write-Info "  2) 应用后由商店自己写入 /data/system/theme/$Component"
Write-Host ''
Write-Warn2 '未在真机验证过：本工具按 HyperOS 商店的库结构实现，逻辑有单元测试，但不能保证所有版本一致'
Write-Info '  出问题可在手机上删除新生成的 content/<code>/<id>.mrc 与 meta 里对应 .mrm 回退'
Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
