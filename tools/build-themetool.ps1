<#
.SYNOPSIS
    构建手机端「主题工具」APK（Shizuku 用户服务版）。

.DESCRIPTION
    只用 SDK 自带命令行工具：aidl → javac → jar → d8 → aapt2 → zipalign → apksigner。
    依赖：app/ 下的 AndroidManifest.xml 与 src/；Shizuku 的 api.aar（从 shizuku-lib/ 解出 classes.jar）。

.EXAMPLE
    .\build-themetool.ps1
    .\build-themetool.ps1 -Install
#>
param(
    [switch]$Install,
    [string]$Device = ''
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

$repoRoot = Split-Path $PSScriptRoot -Parent
$appDir = Join-Path $repoRoot 'app'
$srcDir = Join-Path $appDir 'src'
$manifest = Join-Path $appDir 'AndroidManifest.xml'
$distDir = Join-Path $repoRoot 'dist'
$buildDir = Join-Path $repoRoot 'build\themetool'
$shizukuAar = Join-Path $repoRoot 'shizuku-lib\api.aar'

foreach ($p in @($srcDir, $manifest)) {
    if (-not (Test-Path -LiteralPath $p)) { throw "缺少：$p" }
}
if (-not (Test-Path -LiteralPath $shizukuAar)) { throw "缺少 Shizuku 依赖：$shizukuAar（应为 api.aar）" }

if (Test-Path -LiteralPath $buildDir) { Remove-Item -LiteralPath $buildDir -Recurse -Force }
New-Item -ItemType Directory -Path $buildDir -Force | Out-Null
if (-not (Test-Path -LiteralPath $distDir)) { New-Item -ItemType Directory -Path $distDir -Force | Out-Null }

Write-Step '探测构建工具'
$sdk = if ($env:ANDROID_SDK_ROOT) { $env:ANDROID_SDK_ROOT } elseif ($env:ANDROID_HOME) { $env:ANDROID_HOME } else {
    Join-Path $env:LOCALAPPDATA 'Android\Sdk'
}
if (-not (Test-Path -LiteralPath $sdk)) { throw "找不到 Android SDK：$sdk" }

$bt = Get-ChildItem (Join-Path $sdk 'build-tools') -Directory | Sort-Object { [version]($_.Name -replace '[^0-9.]','') } -Descending |
      Where-Object { Test-Path (Join-Path $_.FullName 'aapt2.exe') } | Select-Object -First 1
if (-not $bt) { throw '找不到 build-tools（需要 aapt2/zipalign/apksigner/d8/aidl）' }
$btPath = $bt.FullName
Write-Info "  build-tools: $($bt.Name)"

$androidJar = Get-ChildItem (Join-Path $sdk 'platforms') -Directory | Sort-Object Name -Descending |
              Where-Object { Test-Path (Join-Path $_.FullName 'android.jar') } | Select-Object -First 1
if (-not $androidJar) { throw '找不到 android.jar' }
$androidJarPath = Join-Path $androidJar.FullName 'android.jar'
Write-Info "  android.jar : $($androidJar.Name)"

$jdkBin = Get-ChildItem 'C:\Program Files\Java','C:\Program Files\Eclipse Adoptium','C:\Program Files\Microsoft' -Directory -ErrorAction SilentlyContinue |
    ForEach-Object { Join-Path $_.FullName 'bin' } |
    Where-Object { (Test-Path (Join-Path $_ 'javac.exe')) -and (Test-Path (Join-Path $_ 'jar.exe')) } |
    Select-Object -First 1
if (-not $jdkBin) { $jdkBin = (Split-Path (Get-Command javac.exe).Source -Parent) }
Write-Info "  javac       : $jdkBin"

# ---------------------------------------------------------------- 1) Shizuku classes.jar
Write-Step '解出 Shizuku api'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$shizukuJar = Join-Path $buildDir 'shizuku-api.jar'
$aar = [System.IO.Compression.ZipFile]::OpenRead($shizukuAar)
try {
    $entry = $aar.Entries | Where-Object { $_.FullName -eq 'classes.jar' } | Select-Object -First 1
    if (-not $entry) { throw 'api.aar 里没有 classes.jar' }
    [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $shizukuJar, $true)
}
finally { $aar.Dispose() }
Write-Ok "  $shizukuJar"

# ---------------------------------------------------------------- 2) aidl
Write-Step '生成 AIDL'
$aidl = Join-Path $btPath 'aidl.exe'
$genDir = Join-Path $buildDir 'gen'
New-Item -ItemType Directory -Path $genDir -Force | Out-Null
$aidlFiles = @(Get-ChildItem $srcDir -Recurse -Filter *.aidl)
if ($aidlFiles.Count -eq 0) { throw '没有找到 .aidl' }
foreach ($a in $aidlFiles) {
    & $aidl -I $srcDir -o $genDir $a.FullName
    if ($LASTEXITCODE -ne 0) { throw "aidl 失败：$($a.Name)" }
}
Write-Ok ("  生成 {0} 个" -f $aidlFiles.Count)

# ---------------------------------------------------------------- 3) javac
Write-Step '编译 Java'
$classesDir = Join-Path $buildDir 'classes'
New-Item -ItemType Directory -Path $classesDir -Force | Out-Null
$allSrc = Get-ChildItem $srcDir -Recurse -Filter *.java | ForEach-Object { $_.FullName }
$allSrc += Get-ChildItem $genDir -Recurse -Filter *.java | ForEach-Object { $_.FullName }
$srcList = Join-Path $buildDir 'sources.txt'
[System.IO.File]::WriteAllLines($srcList, $allSrc, (New-Object System.Text.UTF8Encoding($false)))

& (Join-Path $jdkBin 'javac.exe') -encoding UTF-8 -source 11 -target 11 `
    -classpath "$androidJarPath;$shizukuJar" -d $classesDir "@$srcList" 2>&1 |
    Where-Object { $_ -notmatch 'warning|警告|bootstrap class path|source value 11|target value 11' } |
    ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }
if ($LASTEXITCODE -ne 0) { throw 'javac 失败' }
Write-Ok '  javac 完成'

# ---------------------------------------------------------------- 4) jar + d8
Write-Step '打包并 dex'
$classesJar = Join-Path $buildDir 'classes.jar'
& (Join-Path $jdkBin 'jar.exe') --create --file $classesJar -C $classesDir . 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'jar 失败' }

$dexDir = Join-Path $buildDir 'dex'
New-Item -ItemType Directory -Path $dexDir -Force | Out-Null
& (Join-Path $btPath 'd8.bat') --min-api 30 --output $dexDir --lib $androidJarPath `
    --classpath $shizukuJar $classesJar 2>&1 | Where-Object { $_ -match 'Error|error|错误' } | ForEach-Object { Write-Host "  $_" }
if (-not (Test-Path (Join-Path $dexDir 'classes.dex'))) { throw 'd8 没有产出 classes.dex' }
Write-Ok '  d8 完成'

# ---------------------------------------------------------------- 5) aapt2 link
Write-Step 'aapt2 链接资源'
$baseApk = Join-Path $buildDir 'base.apk'
& (Join-Path $btPath 'aapt2.exe') link -o $baseApk -I $androidJarPath `
    --manifest $manifest --min-sdk-version 30 --target-sdk-version 34 --version-code 1 --version-name 1.0 2>&1 |
    ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }
if ($LASTEXITCODE -ne 0 -or -not (Test-Path $baseApk)) { throw 'aapt2 link 失败' }
Write-Ok '  aapt2 完成'

# ---------------------------------------------------------------- 6) 合并 dex
Write-Step '合并 classes.dex 进 APK'
Add-Type -AssemblyName System.IO.Compression
$zip = [System.IO.Compression.ZipFile]::Open($baseApk, [System.IO.Compression.ZipArchiveMode]::Update)
try {
    $existing = $zip.GetEntry('classes.dex')
    if ($existing) { $existing.Delete() }
    [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
        $zip, (Join-Path $dexDir 'classes.dex'), 'classes.dex',
        [System.IO.Compression.CompressionLevel]::Optimal) | Out-Null
}
finally { $zip.Dispose() }
Write-Ok '  已写入 classes.dex'

# ---------------------------------------------------------------- 7) zipalign + 签名
Write-Step 'zipalign'
$aligned = Join-Path $buildDir 'aligned.apk'
& (Join-Path $btPath 'zipalign.exe') -f 4 $baseApk $aligned
if ($LASTEXITCODE -ne 0) { throw 'zipalign 失败' }

$ks = Join-Path $distDir 'lockwall.keystore'
if (-not (Test-Path $ks)) {
    Write-Step '生成签名密钥'
    & (Join-Path $jdkBin 'keytool.exe') -genkeypair -v -keystore $ks -storepass lockwall `
        -keypass lockwall -alias lockwall -keyalg RSA -keysize 2048 -validity 10000 `
        -dname "CN=ThemeTool, O=ThemeTool, C=CN" 2>&1 | Where-Object { $_ -match 'Generating|已生成' } | ForEach-Object { Write-Host "  $_" }
}

$outApk = Join-Path $distDir 'themetool.apk'
if (Test-Path $outApk) { Remove-Item $outApk -Force }

Write-Step '签名'
& (Join-Path $btPath 'apksigner.bat') sign --ks $ks --ks-pass pass:lockwall --key-pass pass:lockwall `
    --out $outApk $aligned 2>&1 | Where-Object { $_ -match 'Signer|SHA-256|error' } | ForEach-Object { Write-Host "  $($_.ToString().Trim())" -ForegroundColor DarkGray }
if ($LASTEXITCODE -ne 0) { throw 'apksigner 失败' }

$cert = & (Join-Path $btPath 'apksigner.bat') verify --print-certs $outApk 2>&1
Write-Host ''
Write-Ok ("构建完成：{0}  ({1:N0} bytes)" -f $outApk, (Get-Item $outApk).Length)
$cert | Where-Object { $_ -match 'DN|SHA-256 digest' } | ForEach-Object { Write-Info "  $($_.ToString().Trim())" }

if ($Install) {
    Write-Step '安装到设备'
    Initialize-Device -Device $Device -Quiet | Out-Null
    $r = (Invoke-Adb @('install', '-r', $outApk)) | Out-String
    if ($r -match 'Success') { Write-Ok '  已安装' }
    else { Write-Bad ("  安装失败：" + $r.Trim()) }
}
