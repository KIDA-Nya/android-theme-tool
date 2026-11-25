# ColorOS 适配器（OPPO / 一加 / realme）
#
# 能力：探测 + 包体检 + **写入投递**（本适配器是唯一实现了写入的）
# 写入方式：向主题商店导出的 ThemeApplyService 投递 THEME_PATH，
#          实际执行者为 com.oplus.uxdesign。详见 docs/ANALYSIS.md。

$adapterDir = $PSScriptRoot
$repoRoot = Split-Path $adapterDir -Parent | Split-Path -Parent

function Get-ColorosAdapter {
    return [pscustomobject]@{
        Name          = 'coloros'
        DisplayName   = 'ColorOS（OPPO / 一加 / realme）'
        SupportsApply = $true
        ThemeDir      = '/data/theme'
        Descriptor    = 'themeInfo.xml'
        Note          = '已实现写入；需要 shell 或 root 身份'

        # ---------------------------------------------------------- 平台探测
        TestPlatform = {
            $evidence = New-Object System.Collections.ArrayList
            $result = @{ Present = $false; Package = ''; Evidence = @(); Reason = '' }

            $store = $null
            try { $store = Resolve-ThemeStore } catch { $result.Reason = $_.Exception.Message }
            if (-not $store) {
                $result.Evidence = @()
                return $result
            }
            [void]$evidence.Add("商店包: $($store.Package)")
            [void]$evidence.Add("服务组件: $($store.Service)")

            $ux = ((Invoke-Adb @('shell', 'pm list packages com.oplus.uxdesign')) | Out-String)
            if ($ux -match 'com\.oplus\.uxdesign') { [void]$evidence.Add('uxdesign: 已安装（OS12+ 通道）') }
            else { [void]$evidence.Add('uxdesign: 未安装（可能走旧版通道）') }

            $ver = ((Invoke-Adb @('shell', 'getprop ro.oplus.theme.version')) | Out-String).Trim()
            if ($ver) { [void]$evidence.Add("theme.version: $ver") }

            $dir = ((Invoke-Adb @('shell', 'ls -1 /data/theme 2>/dev/null')) | Out-String).Trim()
            if ($dir) { [void]$evidence.Add("/data/theme: 存在（$(($dir -split "`n").Count) 项）") }
            else { [void]$evidence.Add('/data/theme: 不存在或不可读') }

            $result.Present = $true
            $result.Package = $store.Package
            $result.Evidence = @($evidence)
            return $result
        }

        # ---------------------------------------------------------- 包体检
        TestPackage = {
            param($Path, $DeviceVersion = '')

            $problems = New-Object System.Collections.ArrayList
            $info = @{}
            $fail = { param($msg) @{ Ok = $false; Kind = 'ColorOS 主题包'; Problems = @($msg); Info = @{} } }

            if (-not (Test-Path -LiteralPath $Path)) { return (& $fail "文件不存在：$Path") }

            Add-Type -AssemblyName System.IO.Compression.FileSystem
            $full = (Get-Item -LiteralPath $Path).FullName
            $info['File'] = [System.IO.Path]::GetFileName($full)
            $info['Size'] = (Get-Item -LiteralPath $full).Length

            $zip = $null
            try { $zip = [System.IO.Compression.ZipFile]::OpenRead($full) }
            catch { return (& $fail "不是有效的 zip：$($_.Exception.Message)") }

            try {
                $entries = @($zip.Entries | Where-Object { -not $_.FullName.EndsWith('/') })
                $names = @($entries | ForEach-Object { $_.FullName })

                $desc = $entries | Where-Object { $_.FullName -eq 'themeInfo.xml' } | Select-Object -First 1
                if (-not $desc) {
                    return (& $fail '缺少根级 themeInfo.xml（商店 inner 格式不被此通道接受）')
                }

                $reader = New-Object System.IO.StreamReader($desc.Open())
                try { $xmlText = $reader.ReadToEnd() } finally { $reader.Dispose() }

                try { [xml]$xml = $xmlText } catch { return (& $fail "themeInfo.xml 不是合法 XML：$($_.Exception.Message)") }

                $rootName = $xml.DocumentElement.Name
                $info['Root'] = $rootName
                if ($rootName -ne 'OplusSmartPhoneThemeInfo') {
                    [void]$problems.Add("根节点是 $rootName，通常应为 OplusSmartPhoneThemeInfo")
                }

                $node = $xml.OplusSmartPhoneThemeInfo
                $editor = "$($node.EditorVersion)".Trim()
                $info['Uuid'] = "$($node.UUID)".Trim()
                $info['EditorVersion'] = $editor
                $info['Summary'] = "$($node.Summary)".Trim()

                if ($DeviceVersion -and $editor -ne $DeviceVersion) {
                    [void]$problems.Add("EditorVersion=$editor 与设备 $DeviceVersion 不一致，应用会被 ThemeOSVersion 检查中止")
                }

                # 声明 vs 实际
                $declared = @()
                foreach ($p in @($node.packageInfo.package)) {
                    if ($p -and $p.name) { $declared += $p.name }
                }
                $info['Declared'] = $declared

                $mods = @()
                foreach ($n in $names) {
                    if ($n -eq 'themeInfo.xml') { continue }
                    if ($n -eq 'themeinfo.xml') { continue }
                    if ($n.StartsWith('picture/') -or $n.StartsWith('previews/') -or
                        $n.StartsWith('descriptions/') -or $n.StartsWith('resources/')) { continue }
                    $mods += [regex]::Replace($n, '_\d{2,3}$', '')
                }
                $mods = @($mods | Select-Object -Unique)
                $info['Modules'] = $mods

                $undeclared = @($mods | Where-Object { $declared -notcontains $_ })
                if ($undeclared.Count -gt 0) {
                    [void]$problems.Add("有内容但未声明（应用时会被跳过）：$($undeclared -join ', ')")
                }
                $absent = @($declared | Where-Object { $mods -notcontains ([regex]::Replace($_, '_\d{2,3}$', '')) })
                if ($absent.Count -gt 0) {
                    $info['DeclaredButAbsent'] = $absent
                }

                return @{
                    Ok      = ($problems.Count -eq 0)
                    Kind    = 'ColorOS 主题包（.theme）'
                    Problems = @($problems)
                    Info    = $info
                }
            }
            finally { $zip.Dispose() }
        }

        # ---------------------------------------------------------- 写入
        Apply = {
            param($Path)
            $apply = Join-Path $repoRoot 'tools\apply_local_theme.ps1'
            if (-not (Test-Path -LiteralPath $apply)) { throw "找不到 apply_local_theme.ps1：$apply" }
            & $apply -Theme $Path
        }
    }
}
