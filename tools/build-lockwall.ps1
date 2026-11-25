<#
.SYNOPSIS
    从源码构建 LockWall（设置锁屏壁纸的小工具 APK）。

.DESCRIPTION
    只用 Android SDK 自带命令行工具，不需要 Gradle：
        javac -> jar -> d8 -> aapt2 link -> 合并 classes.dex -> zipalign -> apksigner

    自动探测：
        Android SDK（ANDROID_HOME / ANDROID_SDK_ROOT / 默认安装位置）
        build-tools（取版本号最大且含 aapt2 / d8 / zipalign / apksigner 的那个）
        platform android.jar
        JDK（JAVA_HOME 或 PATH 里的 javac / jar / keytool）

.PARAMETER Install  构建完成后直接 adb install -r 到设备
.PARAMETER Output   输出 APK 路径，默认 dist\lockwall.apk

.EXAMPLE
    .\build-lockwall.ps1
    .\build-lockwall.ps1 -Install
#>
[CmdletBinding()]
param(
    [switch]$Install,
    [string]$Output = ''
)

. (Join-Path $PSScriptRoot 'common.ps1')

$projRoot = Split-Path $PSScriptRoot -Parent
$appDir = Join-Path $projRoot 'lockwall'
$srcJava = Join-Path $appDir 'src\com\keke\lockwall\Main.java'
$manifest = Join-Path $appDir 'AndroidManifest.xml'
$assetsDir = Join-Path $appDir 'assets'

if (-not (Test-Path -LiteralPath $srcJava)) { throw "找不到源码：$srcJava" }
if (-not (Test-Path -LiteralPath $manifest)) { throw "找不到 Manifest：$manifest" }
if (-not $Output) { $Output = Join-Path $projRoot 'dist\lockwall.apk' }

# ---------------------------------------------------------------- 工具探测

function Resolve-Sdk {
    $candidates = @($env:ANDROID_HOME, $env:ANDROID_SDK_ROOT,
        (Join-Path $env:LOCALAPPDATA 'Android\Sdk'),
        'C:\Android\Sdk',
        (Join-Path $env:ProgramFiles 'Android\Sdk'))
    foreach ($c in $candidates) {
        if ($c -and (Test-Path -LiteralPath (Join-Path $c 'build-tools'))) { return $c }
    }
    throw '找不到 Android SDK。请设置 ANDROID_HOME，或安装 SDK 到默认位置。'
}

function Resolve-BuildTools {
    param([string]$Sdk)
    $base = Join-Path $Sdk 'build-tools'
    $dirs = Get-ChildItem -LiteralPath $base -Directory -ErrorAction SilentlyContinue |
        Sort-Object { [version]($_.Name -replace '[^\d\.]', '') } -Descending
    foreach ($d in $dirs) {
        $need = @('aapt2.exe', 'zipalign.exe', 'apksigner.bat', 'd8.bat')
        $ok = $true
        foreach ($n in $need) { if (-not (Test-Path -LiteralPath (Join-Path $d.FullName $n))) { $ok = $false; break } }
        if ($ok) { return $d.FullName }
    }
    throw "在 $base 下找不到同时含 aapt2 / d8 / zipalign / apksigner 的 build-tools。"
}

function Resolve-AndroidJar {
    param([string]$Sdk)
    $base = Join-Path $Sdk 'platforms'
    $dirs = Get-ChildItem -LiteralPath $base -Directory -ErrorAction SilentlyContinue |
        Sort-Object { try { [version]($_.Name -replace '[^\d\.]', '') } catch { [version]'0.0' } } -Descending
    foreach ($d in $dirs) {
        $jar = Join-Path $d.FullName 'android.jar'
        if (Test-Path -LiteralPath $jar) { return $jar }
    }
    throw "在 $base 下找不到 platforms\android-*\android.jar"
}

function Get-JdkBin {
    <# 找出真实的 JDK bin 目录（PATH 里的 javac 常是 shim，同目录没有 jar/keytool） #>
    if ($script:JdkBin) { return $script:JdkBin }

    $cands = @()
    if ($env:JAVA_HOME) { $cands += (Join-Path $env:JAVA_HOME 'bin') }

    $javac = Get-Command javac -ErrorAction SilentlyContinue
    if ($javac) {
        $cands += (Split-Path $javac.Source -Parent)
        # 顺着 shim 往上一级找 JDK 根
        $parent = Split-Path (Split-Path $javac.Source -Parent) -Parent
        if ($parent) { $cands += (Join-Path $parent 'bin') }
    }

    $roots = @(
        (Join-Path $env:ProgramFiles 'Java'),
        (Join-Path ${env:ProgramFiles(x86)} 'Java'),
        (Join-Path $env:ProgramFiles 'Eclipse Adoptium'),
        (Join-Path $env:ProgramFiles 'Microsoft'),
        'C:\Java'
    )
    foreach ($r in $roots) {
        if (-not $r -or -not (Test-Path -LiteralPath $r)) { continue }
        Get-ChildItem -LiteralPath $r -Directory -ErrorAction SilentlyContinue |
            Sort-Object Name -Descending |
            ForEach-Object { $cands += (Join-Path $_.FullName 'bin') }
    }

    # PATH 里的 javac 常是 Oracle 的 shim 目录，只有 javac 没有 jar/keytool，
    # 所以优先选「同时含 javac 与 jar」的目录（真正的 JDK）。
    foreach ($c in $cands) {
        if (-not $c) { continue }
        if ((Test-Path -LiteralPath (Join-Path $c 'javac.exe')) -and
            (Test-Path -LiteralPath (Join-Path $c 'jar.exe'))) {
            $script:JdkBin = $c
            return $c
        }
    }
    foreach ($c in $cands) {
        if ($c -and (Test-Path -LiteralPath (Join-Path $c 'javac.exe'))) {
            $script:JdkBin = $c
            return $c
        }
    }
    throw '找不到 JDK。请安装 JDK 11+ 并设置 JAVA_HOME。'
}

function Resolve-JdkTool {
    param([string]$Name)
    $bin = Get-JdkBin
    $exe = Join-Path $bin "$Name.exe"
    if (Test-Path -LiteralPath $exe) { return $exe }
    $cmd = Get-Command $Name -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    throw "在 $bin 下找不到 $Name.exe。"
}

Write-Step '探测构建工具 ...'
$sdk = Resolve-Sdk
$bt = Resolve-BuildTools $sdk
$androidJar = Resolve-AndroidJar $sdk
$javac = Resolve-JdkTool 'javac'
$jarTool = Resolve-JdkTool 'jar'
$keytool = Resolve-JdkTool 'keytool'
Write-Info "SDK        : $sdk"
Write-Info "build-tools: $(Split-Path $bt -Leaf)"
Write-Info "android.jar: $(Split-Path $androidJar -Leaf) @ $(Split-Path (Split-Path $androidJar -Parent) -Leaf)"
Write-Info "javac      : $javac"

# ---------------------------------------------------------------- 构建目录

$outDir = Join-Path $projRoot 'build\lockwall'
foreach ($sub in 'classes', 'dex') {
    $p = Join-Path $outDir $sub
    if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Recurse -Force }
    New-Item -ItemType Directory -Path $p -Force | Out-Null
}
$baseApk = Join-Path $outDir 'base.apk'
$classesJar = Join-Path $outDir 'classes.jar'
$unsigned = Join-Path $outDir 'lockwall-unsigned.apk'
$aligned = Join-Path $outDir 'lockwall-aligned.apk'

# ---------------------------------------------------------------- 1) javac

Write-Step '编译 Java ...'
$classesDir = Join-Path $outDir 'classes'
& $javac -nowarn --release 11 -classpath $androidJar -d $classesDir $srcJava 2>&1 |
    ForEach-Object { Write-Host ('  ' + $_) -ForegroundColor Gray }
if ($LASTEXITCODE -ne 0) { throw 'javac 编译失败。' }
Write-Ok 'javac 完成'

# ---------------------------------------------------------------- 2) jar + d8

Write-Step '打包并 dex ...'
& $jarTool cf $classesJar -C $classesDir . 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'jar 打包失败。' }

$dexDir = Join-Path $outDir 'dex'
& "$bt\d8.bat" --release --min-api 30 --lib $androidJar --output $dexDir $classesJar 2>&1 |
    ForEach-Object { Write-Host ('  ' + $_) -ForegroundColor Gray }
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath (Join-Path $dexDir 'classes.dex'))) {
    throw 'd8 生成 classes.dex 失败。'
}
Write-Ok 'd8 完成'

# ---------------------------------------------------------------- 3) aapt2 link

function New-PlaceholderAsset {
    <# 生成一张占位壁纸，避免把第三方素材打进仓库或发布物 #>
    param([string]$Path)
    Add-Type -AssemblyName System.Drawing
    $w = 1080; $h = 2400
    $bmp = New-Object System.Drawing.Bitmap($w, $h)
    try {
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        try {
            $rect = New-Object System.Drawing.Rectangle(0, 0, $w, $h)
            $c1 = [System.Drawing.Color]::FromArgb(255, 28, 38, 56)
            $c2 = [System.Drawing.Color]::FromArgb(255, 122, 162, 204)
            $brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush($rect, $c1, $c2, 45.0)
            try { $g.FillRectangle($brush, $rect) } finally { $brush.Dispose() }

            $font = New-Object System.Drawing.Font('Arial', 44)
            try {
                $fmt = New-Object System.Drawing.StringFormat
                $fmt.Alignment = [System.Drawing.StringAlignment]::Center
                $g.DrawString('LockWall placeholder', $font, [System.Drawing.Brushes]::White,
                    (New-Object System.Drawing.RectangleF(0, ($h / 2), $w, 120)), $fmt)
            }
            finally { $font.Dispose() }
        }
        finally { $g.Dispose() }
        $bmp.Save($Path, [System.Drawing.Imaging.ImageFormat]::Jpeg)
    }
    finally { $bmp.Dispose() }
}

# assets 是 LockWall 的兜底图。仓库不带第三方壁纸，缺失时生成占位图。
if (-not (Test-Path -LiteralPath $assetsDir)) {
    New-Item -ItemType Directory -Path $assetsDir -Force | Out-Null
}
$assetImg = Join-Path $assetsDir 'lock.jpg'
if (-not (Test-Path -LiteralPath $assetImg)) {
    Write-Info "未找到 $assetImg，生成占位图"
    New-PlaceholderAsset $assetImg
}

Write-Step 'aapt2 链接资源 ...'
$aapt2Args = @('link', '-o', $baseApk, '-I', $androidJar,
    '--manifest', $manifest,
    '--min-sdk-version', '30', '--target-sdk-version', '34')
if (Test-Path -LiteralPath $assetsDir) { $aapt2Args += @('-A', $assetsDir) }
& "$bt\aapt2.exe" @aapt2Args 2>&1 | ForEach-Object { Write-Host ('  ' + $_) -ForegroundColor Gray }
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $baseApk)) { throw 'aapt2 link 失败。' }
Write-Ok 'aapt2 完成'

# ---------------------------------------------------------------- 4) 合并 dex

Write-Step '合并 classes.dex 进 APK ...'
Copy-Item -LiteralPath $baseApk -Destination $unsigned -Force
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::Open($unsigned, 'Update')
try {
    $dexBytes = [System.IO.File]::ReadAllBytes((Join-Path $dexDir 'classes.dex'))
    $entry = $zip.CreateEntry('classes.dex', [System.IO.Compression.CompressionLevel]::Optimal)
    $stream = $entry.Open()
    try { $stream.Write($dexBytes, 0, $dexBytes.Length) } finally { $stream.Dispose() }
} finally { $zip.Dispose() }
Write-Ok '已写入 classes.dex'

# ---------------------------------------------------------------- 5) zipalign

Write-Step 'zipalign ...'
& "$bt\zipalign.exe" -f 4 $unsigned $aligned
if ($LASTEXITCODE -ne 0) { throw 'zipalign 失败。' }
& "$bt\zipalign.exe" -c -p -v 4 $aligned 2>&1 | Select-Object -Last 1 | ForEach-Object { Write-Host ('  ' + $_) -ForegroundColor Gray }

# ---------------------------------------------------------------- 6) 签名

Write-Step '签名 ...'
$ksDir = Join-Path $projRoot 'dist'
New-Item -ItemType Directory -Path $ksDir -Force | Out-Null
$keystore = Join-Path $ksDir 'lockwall.keystore'
$ksPass = 'lockwall'
$alias = 'lockwall'

if (-not (Test-Path -LiteralPath $keystore)) {
    Write-Info "生成签名密钥：$keystore"
    $dn = 'CN=LockWall, O=ThemeTool, C=CN'
    # keytool 的输出是本地化的；只关心结果，不展示细节
    $ktOut = & $keytool -genkeypair -v -keystore $keystore -alias $alias -keyalg RSA -keysize 2048 `
        -validity 10950 -storepass $ksPass -keypass $ksPass -dname $dn 2>&1
    if ($LASTEXITCODE -ne 0) {
        $ktOut | ForEach-Object { Write-Host ('  ' + [string]$_) -ForegroundColor Gray }
    }
    if ($LASTEXITCODE -ne 0) { throw 'keytool 生成密钥失败。' }
}

$final = $Output
$finalDir = Split-Path $final -Parent
if ($finalDir -and -not (Test-Path -LiteralPath $finalDir)) {
    New-Item -ItemType Directory -Path $finalDir -Force | Out-Null
}
if (Test-Path -LiteralPath $final) { Remove-Item -LiteralPath $final -Force }

& "$bt\apksigner.bat" sign --ks $keystore --ks-pass "pass:$ksPass" --key-pass "pass:$ksPass" `
    --ks-key-alias $alias --v1-signing-enabled true --v2-signing-enabled true `
    --out $final $aligned 2>&1 |
    ForEach-Object { [string]$_ } |
    Where-Object { $_ -and $_ -notmatch 'WARNING|RemoteException|native-access' } |
    ForEach-Object { Write-Host ('  ' + $_) -ForegroundColor Gray }
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $final)) { throw 'apksigner 签名失败。' }

& "$bt\apksigner.bat" verify --print-certs $final 2>&1 |
    ForEach-Object { [string]$_ } |
    Where-Object { $_ -match 'certificate DN|SHA-256 digest' } |
    Select-Object -First 2 | ForEach-Object { Write-Info $_.Trim() }

Write-Host ''
Write-Ok ("构建完成：{0}  ({1:N0} bytes)" -f $final, (Get-Item -LiteralPath $final).Length)

# ---------------------------------------------------------------- 7) 可选安装

if ($Install) {
    Write-Step '安装到设备 ...'
    Select-Device | Out-Null
    $res = (Invoke-Adb @('install', '-r', $final)) | Out-String
    if ($res -match 'Success') { Write-Ok '安装成功' }
    else { Write-Bad ("安装失败：{0}" -f $res.Trim()) }
}
