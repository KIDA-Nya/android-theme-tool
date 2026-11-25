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
