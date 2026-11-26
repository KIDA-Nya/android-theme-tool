<#
.SYNOPSIS
    适配器与包体检的回归测试（不需要真机）。

.DESCRIPTION
    1. 用 tests/mk_fixtures.py 生成 mtz / hwt 合成夹具
    2. 逐个跑 tools/check_package.ps1，断言退出码与关键输出
    3. 若仓库里有 .theme 样本（或用 THEME_SAMPLE 指定），额外跑一次 ColorOS 分支

    退出码：0 全部通过 / 1 有失败

.EXAMPLE
    .\tests\run_tests.ps1
    $env:THEME_SAMPLE = 'D:\themes\x.theme'; .\tests\run_tests.ps1
#>
param([switch]$KeepFixtures)

$ErrorActionPreference = 'Continue'
$repoRoot = Split-Path $PSScriptRoot -Parent
$checker = Join-Path $repoRoot 'tools\check_package.ps1'
$mkfixtures = Join-Path $PSScriptRoot 'mk_fixtures.py'
$fx = Join-Path $env:TEMP 'themetool_fixtures'

if (-not (Test-Path -LiteralPath $checker)) { throw "找不到 $checker" }

# ---------------- Python ----------------
$py = $null
foreach ($cand in @($env:THEME_PYTHON, 'python', 'python3', 'py')) {
    if (-not $cand) { continue }
    $cmd = Get-Command $cand -ErrorAction SilentlyContinue
    if ($cmd) { $py = $cmd.Source; break }
}
if (-not $py) { throw '找不到 Python（用于生成夹具）。可设 THEME_PYTHON。' }

# ---------------- 生成夹具 ----------------
if (Test-Path -LiteralPath $fx) { Remove-Item -LiteralPath $fx -Recurse -Force }
& $py -X utf8 $mkfixtures $fx | ForEach-Object { Write-Host ("  " + $_) -ForegroundColor Gray }
if ($LASTEXITCODE -ne 0) { throw '夹具生成失败' }

# ---------------- 用例 ----------------
# Expect: 期望退出码；Contains: 输出里必须出现的关键字（可空）
$cases = @(
    @{ File = 'good.mtz'; Expect = 0; MustContain = 'MIUI 主题包' }
    @{ File = 'nodesc.mtz'; Expect = 2; MustContain = '缺少 description.xml' }
    @{ File = 'good.hwt'; Expect = 0; MustContain = 'HwTheme' }
    @{ File = 'badroot.hwt'; Expect = 2; MustContain = '应为 HwTheme' }
    @{ File = 'unknown.bin'; Expect = 1; MustContain = '无法识别' }
)

Write-Host ''
Write-Host '=== 适配器 / 包体检 测试 ===' -ForegroundColor Cyan

$pass = 0
$fail = 0
foreach ($c in $cases) {
    $path = Join-Path $fx $c.File
    $out = (& $checker -Path $path *>&1) -join "`n"
    $code = $LASTEXITCODE
    $okCode = ($code -eq $c.Expect)
    $okText = $true
    if ($c.MustContain) { $okText = $out -match [regex]::Escape($c.MustContain) }

    if ($okCode -and $okText) {
        Write-Host ("  [PASS] {0,-14} exit={1}" -f $c.File, $code) -ForegroundColor Green
        $pass++
    }
    else {
        Write-Host ("  [FAIL] {0,-14} exit={1}（期望 {2}）{3}" -f $c.File, $code, $c.Expect,
            $(if ($okText) { '' } else { " 缺少关键字：$($c.MustContain)" })) -ForegroundColor Red
        $fail++
    }
}

# ---------------- theme_mix：拼包 ----------------
Write-Host ''
Write-Host '=== theme_mix 拼包测试 ===' -ForegroundColor Cyan

$mixFx = Join-Path $env:TEMP 'themetool_mixfx'
$mixOut = Join-Path $env:TEMP 'themetool_mix.theme'
if (Test-Path -LiteralPath $mixFx) { Remove-Item -LiteralPath $mixFx -Recurse -Force }
if (Test-Path -LiteralPath $mixOut) { Remove-Item -LiteralPath $mixOut -Force }

$mkMix = Join-Path $PSScriptRoot 'mk_mix_fixtures.py'
$mixTool = Join-Path $repoRoot 'tools\theme_mix.py'
$checkMix = Join-Path $PSScriptRoot 'check_mix.py'

& $py -X utf8 $mkMix $mixFx | ForEach-Object { Write-Host ('  ' + $_) -ForegroundColor Gray }
$a = Join-Path $mixFx 'a.theme'
$b = Join-Path $mixFx 'b.theme'
$mixOutText = (& $py -X utf8 $mixTool -o $mixOut $a "icons:$b" "com.android.settings:$b" 2>&1) -join "`n"
$mixCode = $LASTEXITCODE

if ($mixCode -eq 0 -and (Test-Path -LiteralPath $mixOut)) {
    $chkOut = (& $py -X utf8 $checkMix $mixOut *>&1) -join "`n"
    $chkCode = $LASTEXITCODE
    if ($chkCode -eq 0) {
        Write-Host '  [PASS] theme_mix 替换内容与声明版本都正确' -ForegroundColor Green
        $pass++
    }
    else {
        Write-Host '  [FAIL] theme_mix 输出校验不符' -ForegroundColor Red
        Write-Host $chkOut -ForegroundColor DarkGray
        $fail++
    }
}
else {
    Write-Host "  [FAIL] theme_mix 执行失败（exit=$mixCode）" -ForegroundColor Red
    Write-Host $mixOutText -ForegroundColor DarkGray
    $fail++
}

# --only 子集
$onlyOut = Join-Path $env:TEMP 'themetool_only.theme'
if (Test-Path -LiteralPath $onlyOut) { Remove-Item -LiteralPath $onlyOut -Force }
$onlyText = (& $py -X utf8 $mixTool -o $onlyOut $a '--only' 'icons' 2>&1) -join "`n"
if ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $onlyOut)) {
    $listTool = Join-Path $PSScriptRoot 'list_entries.py'
    $names = (& $py -X utf8 $listTool $onlyOut | Out-String).Trim()
    if ($names -eq 'icons') {
        Write-Host '  [PASS] --only 只保留指定模块' -ForegroundColor Green
        $pass++
    }
    else {
        Write-Host "  [FAIL] --only 输出条目不对：$names" -ForegroundColor Red
        $fail++
    }
}
else {
    Write-Host "  [FAIL] --only 执行失败（exit=$LASTEXITCODE）" -ForegroundColor Red
    $fail++
}

# ---------------- extract_assets：资源提取 ----------------
Write-Host ''
Write-Host '=== extract_assets 资源提取测试 ===' -ForegroundColor Cyan

$asFx = Join-Path $env:TEMP 'themetool_assetfx'
$asOut = Join-Path $env:TEMP 'themetool_assetout'
$mkAs = Join-Path $PSScriptRoot 'mk_asset_fixture.py'
$exTool = Join-Path $repoRoot 'tools\extract_assets.py'
if (Test-Path -LiteralPath $asFx) { Remove-Item -LiteralPath $asFx -Recurse -Force }
if (Test-Path -LiteralPath $asOut) { Remove-Item -LiteralPath $asOut -Recurse -Force }
& $py -X utf8 $mkAs $asFx | ForEach-Object { Write-Host ('  ' + $_) -ForegroundColor Gray }

function Test-AssetExport {
    param([string]$Theme, [string]$Label, [hashtable]$Expect)

    $dir = Join-Path $asOut ([System.IO.Path]::GetFileNameWithoutExtension($Theme))
    $txt = (& $py -X utf8 $exTool $Theme -o $dir *>&1) -join "`n"
    if ($LASTEXITCODE -ne 0) {
        Write-Host ("  [FAIL] {0} 提取失败`n{1}" -f $Label, $txt) -ForegroundColor Red
        return $false
    }
    $ok = $true
    foreach ($cat in $Expect.Keys) {
        $count = @(Get-ChildItem -LiteralPath (Join-Path $dir $cat) -Recurse -File -ErrorAction SilentlyContinue).Count
        if ($count -ne $Expect[$cat]) {
            Write-Host ("  [FAIL] {0}/{1} 期望 {2} 个，实际 {3}" -f $Label, $cat, $Expect[$cat], $count) -ForegroundColor Red
            $ok = $false
        }
    }
    if ($ok) { Write-Host ("  [PASS] {0}：分类与数量正确" -f $Label) -ForegroundColor Green }
    return $ok
}

# nested.theme：壁纸/图标在内嵌 zip 里，字体与铃声在顶层
if (Test-AssetExport (Join-Path $asFx 'nested.theme') 'ColorOS 内嵌 zip' @{
        wallpaper = 1; icons = 1; fonts = 1; ringtone = 1 }) { $pass++ } else { $fail++ }

# flat.hwt：全部平铺
if (Test-AssetExport (Join-Path $asFx 'flat.hwt') '华为平铺目录' @{
        wallpaper = 1; icons = 1; fonts = 1 }) { $pass++ } else { $fail++ }

# ---------------- miui_backup_inject：Theme backup 注入 ----------------
Write-Host ''
Write-Host '=== miui Theme backup 注入测试 ===' -ForegroundColor Cyan

$mbFx = Join-Path $env:TEMP 'themetool_miuidata'
$mbTool = Join-Path $repoRoot 'tools\miui_backup_inject.py'
$mbMk = Join-Path $PSScriptRoot 'mk_miui_data_fixture.py'
$mbChk = Join-Path $PSScriptRoot 'check_miui_inject.py'
if (Test-Path -LiteralPath $mbFx) { Remove-Item -LiteralPath $mbFx -Recurse -Force }
& $py -X utf8 $mbMk $mbFx | ForEach-Object { Write-Host ('  ' + $_) -ForegroundColor Gray }

$mbTheme = 'THEMEBACKUP0000000000000000000001'
$mbReport = Join-Path $mbFx 'changed.json'
$mbOut = (& $py -X utf8 $mbTool --data (Join-Path $mbFx '.data') --theme $mbTheme `
        --mtz (Join-Path $mbFx 'sample.mtz') --component icons --report $mbReport *>&1) -join "`n"
if ($LASTEXITCODE -eq 0) {
    $chkOut = (& $py -X utf8 $mbChk $mbFx *>&1) -join "`n"
    if ($LASTEXITCODE -eq 0) {
        Write-Host '  [PASS] 注入后 hash/size/localId 与内容都正确' -ForegroundColor Green
        $pass++
    }
    else {
        Write-Host '  [FAIL] 注入结果校验不符' -ForegroundColor Red
        Write-Host $chkOut -ForegroundColor DarkGray
        $fail++
    }
}
else {
    Write-Host "  [FAIL] 注入执行失败（exit=$LASTEXITCODE）" -ForegroundColor Red
    Write-Host $mbOut -ForegroundColor DarkGray
    $fail++
}

# 变更清单应恰好包含 3 个文件
if (Test-Path -LiteralPath $mbReport) {
    $changed = (Get-Content -LiteralPath $mbReport -Raw | ConvertFrom-Json).changed
    if ($changed.Count -eq 3) {
        Write-Host '  [PASS] 变更清单只列出改动的 3 个文件' -ForegroundColor Green
        $pass++
    }
    else {
        Write-Host ("  [FAIL] 变更清单条目数不对：{0}" -f $changed.Count) -ForegroundColor Red
        $fail++
    }
}
else {
    Write-Host '  [FAIL] 没有生成变更清单' -ForegroundColor Red
    $fail++
}

# ---------------- 可选：真实 .theme ----------------
$sample = $env:THEME_SAMPLE
if (-not $sample) {
    $cand = Get-ChildItem -LiteralPath $repoRoot -Filter '*.theme' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($cand) { $sample = $cand.FullName }
}

if ($sample -and (Test-Path -LiteralPath $sample)) {
    Write-Host ''
    Write-Host '=== ColorOS 分支（真实样本）===' -ForegroundColor Cyan
    $out = (& $checker -Path $sample *>&1) -join "`n"
    $code = $LASTEXITCODE
    # 未对齐的包会报「有内容但未声明」；已对齐的包应为 0
    $mentions = $out -match 'ColorOS 主题包'
    if ($mentions -and ($code -eq 0 -or $code -eq 2)) {
        Write-Host ("  [PASS] {0}  exit={1}" -f (Split-Path $sample -Leaf), $code) -ForegroundColor Green
        if ($out -match '有内容但未声明') {
            Write-Host '         已正确识别出未声明模块（未对齐的包属正常）' -ForegroundColor DarkGray
        }
        $pass++
    }
    else {
        Write-Host ("  [FAIL] {0}  exit={1}" -f (Split-Path $sample -Leaf), $code) -ForegroundColor Red
        $fail++
    }
}
else {
    Write-Host ''
    Write-Host '  （跳过 ColorOS 真实样本：仓库里没有 .theme，可用 THEME_SAMPLE 指定）' -ForegroundColor DarkGray
}

if (-not $KeepFixtures) { Remove-Item -LiteralPath $fx -Recurse -Force -ErrorAction SilentlyContinue }

Write-Host ''
Write-Host ("=== 结果：{0} 通过 / {1} 失败 ===" -f $pass, $fail) -ForegroundColor $(if ($fail) { 'Red' } else { 'Green' })
if ($fail -gt 0) { exit 1 } else { exit 0 }
