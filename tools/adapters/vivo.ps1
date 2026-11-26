# vivo / iQOO 适配器（OriginOS / Funtouch OS）
#
# 能力：探测 + 包体检（.itz 只读）
# 写入未实现：需要与 vivo 主题引擎的私有 Binder 交互（VFont 的做法是从已装框架里
#            反查 backup 接口的签名与 transaction id，再以 system uid 1000 派发），
#            没有真机无法验证，因此不提供 apply —— 不假装支持。
#
# 事实来源（详见 docs/VENDOR-FINDINGS.md 第十节）：
#   · 主题包格式 .itz = zip + 根级 description.xml（VFont docs/themes.md）
#   · 主题商店包名 com.bbk.theme；外部数据 /sdcard/Android/data/com.bbk.theme/
#   · 核心存储在 /data/bbkcore/theme/（需 root）
#   · VFont 明确拒绝「包内自带字体」的主题

function Get-VivoAdapter {
    return [pscustomobject]@{
        Name          = 'vivo'
        DisplayName   = 'OriginOS / Funtouch OS（vivo / iQOO）'
        SupportsApply = $false
        ThemeDir      = '/data/bbkcore/theme'
        Descriptor    = 'description.xml'
        Note          = '只读：探测 + .itz 体检。写入需 vivo 私有 Binder，未实现'

        TestPlatform = {
            $evidence = New-Object System.Collections.ArrayList
            $result = @{ Present = $false; Package = ''; Evidence = @(); Reason = '未检测到 vivo 主题商店' }

            $pkgs = ((Invoke-Adb @('shell', 'pm list packages')) | Out-String)
            $hit = @()
            foreach ($p in @('com.bbk.theme', 'com.vivo.themestore', 'com.bbk.thememanager')) {
                if ($pkgs -match ('package:' + [regex]::Escape($p) + '\s')) { $hit += $p }
            }

            $props = @{}
            foreach ($k in @('ro.vivo.os.version', 'ro.vivo.os.build.display.id', 'ro.vivo.product.version')) {
                $v = ((Invoke-Adb @('shell', "getprop $k")) | Out-String).Trim()
                if ($v) { $props[$k] = $v }
            }

            if ($hit.Count -eq 0 -and $props.Count -eq 0) { return $result }

            foreach ($h in $hit) { [void]$evidence.Add("包: $h") }
            foreach ($k in $props.Keys) { [void]$evidence.Add("$k = $($props[$k])") }

            $ext = ((Invoke-Adb @('shell', 'ls -d /sdcard/Android/data/com.bbk.theme 2>/dev/null')) | Out-String).Trim()
            if ($ext) { [void]$evidence.Add('外部数据目录: /sdcard/Android/data/com.bbk.theme') }
            else { [void]$evidence.Add('外部数据目录: 未发现') }

            $core = ((Invoke-Adb @('shell', 'ls -d /data/bbkcore/theme 2>/dev/null')) | Out-String).Trim()
            if ($core) { [void]$evidence.Add('核心存储: /data/bbkcore/theme（需 root）') }

            $result.Present = $true
            $result.Package = ($(if ($hit) { $hit[0] } else { '' }))
            $result.Evidence = @($evidence)
            $result.Reason = '检测到 vivo 主题商店'
            return $result
        }

        TestPackage = {
            param($Path, $DeviceVersion = '')

            $problems = New-Object System.Collections.ArrayList
            $info = @{}
            $fail = { param($msg) @{ Ok = $false; Kind = 'vivo 主题包'; Problems = @($msg); Info = @{} } }

            if (-not (Test-Path -LiteralPath $Path)) { return (& $fail "文件不存在：$Path") }

            Add-Type -AssemblyName System.IO.Compression.FileSystem
            $full = (Get-Item -LiteralPath $Path).FullName
            $info['File'] = [System.IO.Path]::GetFileName($full)
            $info['Size'] = (Get-Item -LiteralPath $full).Length

            if ([System.IO.Path]::GetExtension($full).ToLowerInvariant() -ne '.itz') {
                [void]$problems.Add('扩展名不是 .itz —— vivo 主题包使用 .itz')
            }

            $zip = $null
            try { $zip = [System.IO.Compression.ZipFile]::OpenRead($full) }
            catch { return (& $fail "不是有效的 zip：$($_.Exception.Message)") }

            try {
                $entries = @($zip.Entries | Where-Object { -not $_.FullName.EndsWith('/') })
                $names = @($entries | ForEach-Object { $_.FullName })

                $desc = $entries | Where-Object { $_.FullName -eq 'description.xml' } | Select-Object -First 1
                if (-not $desc) { return (& $fail '缺少根级 description.xml（vivo 主题包需要它）') }

                $reader = New-Object System.IO.StreamReader($desc.Open())
                try { $xmlText = $reader.ReadToEnd() } finally { $reader.Dispose() }

                try { [xml]$xml = $xmlText }
                catch { return (& $fail "description.xml 不是合法 XML：$($_.Exception.Message)") }

                $rootName = $xml.DocumentElement.Name
                $info['Root'] = $rootName
                if ($rootName -eq 'HwTheme') {
                    [void]$problems.Add('根节点是 HwTheme —— 这是华为主题包，vivo 不认')
                }

                foreach ($tag in @('title', 'title-cn', 'author', 'version', 'screen', 'designer')) {
                    $n = $xml.SelectSingleNode("//$tag")
                    if ($n -and $n.InnerText.Trim()) { $info[$tag] = $n.InnerText.Trim() }
                }

                $tops = @()
                foreach ($n in $names) {
                    if ($n -eq 'description.xml') { continue }
                    $tops += ($n -split '/')[0]
                }
                $tops = @($tops | Select-Object -Unique)
                $info['TopLevel'] = $tops

                # VFont 的说明里明确：自带字体的主题会被拒绝
                $fonts = @($names | Where-Object { $_ -match '(?i)\.(ttf|otf|ttc)$' -or $_ -match '(?i)^fonts/' })
                if ($fonts.Count -gt 0) {
                    $info['BundledFonts'] = @($fonts | Select-Object -First 5)
                    [void]$problems.Add("包内自带字体（$($fonts.Count) 个文件）。已知参考实现会拒绝这类主题，建议单独用字体功能")
                }

                $known = @('wallpaper', 'lockscreen', 'icons', 'fonts', 'framework-res',
                    'com.android.systemui', 'com.vivo.launcher', 'com.bbk.launcher2',
                    'com.android.settings', 'com.android.contacts', 'com.android.mms')
                $found = @($tops | Where-Object { $known -contains $_ })
                $info['KnownModules'] = $found
                if ($found.Count -eq 0 -and $tops.Count -gt 0) {
                    [void]$problems.Add("没识别出已知模块目录（实际顶层：$($tops -join ', ')）—— 结构可能与已知版本不同")
                }

                return @{
                    Ok       = ($problems.Count -eq 0)
                    Kind     = 'vivo 主题包（.itz，只读体检）'
                    Problems = @($problems)
                    Info     = $info
                }
            }
            finally { $zip.Dispose() }
        }

        Apply = {
            param($Path)
            $why = @(
                'vivo 的主题写入需要与自家主题引擎的私有 Binder 交互：'
                '参考实现（VFont）是从已装框架里反查 backup 接口签名与 transaction id，'
                '再以 system uid 1000 派发，并且只支持特定机型/ROM。'
                '本项目没有 vivo 真机，无法验证，因此不提供写入。'
                '可行替代：把 .itz 交给 i主题 的「本地主题」导入（见 route_to_store.ps1）。'
            ) -join [Environment]::NewLine
            throw $why
        }
    }
}
