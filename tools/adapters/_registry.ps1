# 适配器注册表：负责加载、探测与选择
#
# 用法：
#   . .\tools\adapters\_registry.ps1
#   $all = Get-AdapterCatalog          # 全部适配器及其是否命中
#   $ad  = Resolve-Adapter             # 第一个命中的适配器（没命中返回 $null）
#   $ad  = Get-Adapter -Name miui      # 按名字取（不看是否命中）

$script:AdapterDir = $PSScriptRoot

# 新增品牌只需在这里加一行，并在同目录放 <name>.ps1（导出 Get-<Prefix>Adapter）
$script:AdapterSpecs = @(
    @{ Name = 'coloros'; Prefix = 'Coloros'; File = 'coloros.ps1'; Order = 1 }
    @{ Name = 'miui'; Prefix = 'Miui'; File = 'miui.ps1'; Order = 2 }
    @{ Name = 'emui'; Prefix = 'Emui'; File = 'emui.ps1'; Order = 3 }
    @{ Name = 'vivo'; Prefix = 'Vivo'; File = 'vivo.ps1'; Order = 4 }
)

# 注意：必须在**脚本作用域**里 dot-source，否则函数定义会随函数返回而丢失
foreach ($spec in $script:AdapterSpecs) {
    $file = Join-Path $script:AdapterDir $spec.File
    if (Test-Path -LiteralPath $file) { . $file }
}

function Get-Adapter {
    param([Parameter(Mandatory = $true)][string]$Name)

    $spec = $script:AdapterSpecs | Where-Object { $_.Name -eq $Name } | Select-Object -First 1
    if (-not $spec) { throw "未知适配器：$Name（可用：$($script:AdapterSpecs.Name -join ', ')）" }

    $fn = "Get-$($spec.Prefix)Adapter"
    if (-not (Get-Command $fn -ErrorAction SilentlyContinue)) {
        throw "适配器文件缺失或未导出 ${fn}：$($spec.File)"
    }

    $adapter = & (Get-Command $fn)
    $adapter | Add-Member -NotePropertyName Prefix -NotePropertyValue $spec.Prefix -Force
    return $adapter
}

function Get-AdapterCatalog {
    <#
      逐个探测各平台。
      返回数组，每项包含适配器摘要 + 探测结果（Present / Evidence / Reason）。
    #>
    $out = @()
    foreach ($spec in ($script:AdapterSpecs | Sort-Object Order)) {
        try {
            $adapter = Get-Adapter -Name $spec.Name
            $probe = & $adapter.TestPlatform
            $out += [pscustomobject]@{
                Name          = $adapter.Name
                DisplayName   = $adapter.DisplayName
                SupportsApply = $adapter.SupportsApply
                Present       = [bool]$probe.Present
                Package       = $probe.Package
                Evidence      = @($probe.Evidence)
                Reason        = $probe.Reason
            }
        }
        catch {
            $out += [pscustomobject]@{
                Name = $spec.Name; DisplayName = $spec.Name; SupportsApply = $false
                Present = $false; Package = ''; Evidence = @()
                Reason = "加载失败：$($_.Exception.Message)"
            }
        }
    }
    return $out
}

function Resolve-Adapter {
    <# 返回第一个命中的适配器；都不命中返回 $null #>
    $hit = Get-AdapterCatalog | Where-Object { $_.Present } | Select-Object -First 1
    if (-not $hit) { return $null }
    return Get-Adapter -Name $hit.Name
}

function Get-AdapterForPackage {
    <# 按扩展名挑适配器；不认识则按包内描述文件猜 #>
    param([Parameter(Mandatory = $true)][string]$Path)

    $ext = [System.IO.Path]::GetExtension($Path).ToLowerInvariant()
    switch ($ext) {
        '.theme' { return Get-Adapter -Name 'coloros' }
        '.mtz' { return Get-Adapter -Name 'miui' }
        '.hwt' { return Get-Adapter -Name 'emui' }
        '.hnt' { return Get-Adapter -Name 'emui' }   # 新荣耀 MagicOS 的格式
        '.itz' { return Get-Adapter -Name 'vivo' }
    }

    try {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $zip = [System.IO.Compression.ZipFile]::OpenRead((Get-Item -LiteralPath $Path).FullName)
        try { $names = @($zip.Entries | ForEach-Object { $_.FullName }) } finally { $zip.Dispose() }
        if ($names -contains 'themeInfo.xml') { return Get-Adapter -Name 'coloros' }
        if ($names -contains 'description.xml') {
            # 华为与 vivo 都用 description.xml，只能看根节点
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            $zip2 = [System.IO.Compression.ZipFile]::OpenRead((Get-Item -LiteralPath $Path).FullName)
            try {
                $e = $zip2.Entries | Where-Object { $_.FullName -eq 'description.xml' } | Select-Object -First 1
                $sr = New-Object System.IO.StreamReader($e.Open())
                try { $head = $sr.ReadToEnd() } finally { $sr.Dispose() }
            }
            finally { $zip2.Dispose() }
            if ($head -match '<HwTheme') { return Get-Adapter -Name 'emui' }
            return Get-Adapter -Name 'vivo'
        }
    }
    catch { }
    return $null
}
