# MIUI / HyperOS 适配器（小米 / Redmi）
#
# 能力：探测 + 包体检（**.mtz 只读**）
# 写入未实现：需要写 /data/system/theme 或调用 com.android.thememanager 的受保护入口，
#            没有真机可验证，因此不提供 apply —— 不假装支持。

function Get-MiuiAdapter {
    return [pscustomobject]@{
        Name          = 'miui'
        DisplayName   = 'MIUI / HyperOS（小米 / Redmi）'
        SupportsApply = $false
        ThemeDir      = '/data/system/theme'
        Descriptor    = 'description.xml'
        Note          = '只读：平台探测与 .mtz 包体检；写入未实现'

        TestPlatform = {
            $evidence = New-Object System.Collections.ArrayList
            $result = @{ Present = $false; Package = ''; Evidence = @(); Reason = '未检测到 MIUI 主题管理器' }

            $pkgs = ((Invoke-Adb @('shell', 'pm list packages')) | Out-String)
            $hit = @()
            foreach ($p in @('com.android.thememanager', 'com.miui.themestore', 'com.merak')) {
                if ($pkgs -match ('package:' + [regex]::Escape($p) + '\s')) { $hit += $p }
            }

            $props = @{}
            foreach ($k in @('ro.miui.ui.version.name', 'ro.mi.os.version.name', 'ro.miui.ui.version.code')) {
                $v = ((Invoke-Adb @('shell', "getprop $k")) | Out-String).Trim()
                if ($v) { $props[$k] = $v }
            }

            if ($hit.Count -eq 0 -and $props.Count -eq 0) { return $result }

            foreach ($h in $hit) { [void]$evidence.Add("包: $h") }
            foreach ($k in $props.Keys) { [void]$evidence.Add("$k = $($props[$k])") }

            $dir = ((Invoke-Adb @('shell', 'ls -d /data/system/theme 2>/dev/null')) | Out-String).Trim()
            if ($dir) { [void]$evidence.Add('/data/system/theme: 存在') } else { [void]$evidence.Add('/data/system/theme: 不存在或不可读') }

            $result.Present = $true
            $result.Package = ($(if ($hit) { $hit[0] } else { '' }))
            $result.Evidence = @($evidence)
            $result.Reason = '检测到 MIUI/HyperOS 主题管理器'
            return $result
        }

        TestPackage = {
            param($Path, $DeviceVersion = '')

            $problems = New-Object System.Collections.ArrayList
            $info = @{}
            $fail = { param($msg) @{ Ok = $false; Kind = 'MIUI 主题包'; Problems = @($msg); Info = @{} } }

            if (-not (Test-Path -LiteralPath $Path)) { return (& $fail "文件不存在：$Path") }

            Add-Type -AssemblyName System.IO.Compression.FileSystem
            $full = (Get-Item -LiteralPath $Path).FullName
            $info['File'] = [System.IO.Path]::GetFileName($full)
            $info['Size'] = (Get-Item -LiteralPath $full).Length

            if ([System.IO.Path]::GetExtension($full).ToLowerInvariant() -ne '.mtz') {
                [void]$problems.Add('扩展名不是 .mtz —— MIUI 只识别 .mtz（本质是 zip）')
            }

            $zip = $null
            try { $zip = [System.IO.Compression.ZipFile]::OpenRead($full) }
            catch { return (& $fail "不是有效的 zip：$($_.Exception.Message)") }

            try {
                $entries = @($zip.Entries)
                $names = @($entries | ForEach-Object { $_.FullName })

                $desc = $entries | Where-Object { $_.FullName -eq 'description.xml' } | Select-Object -First 1
                if (-not $desc) {
                    [void]$problems.Add('缺少 description.xml（MIUI 主题包的描述文件）')
                }
                else {
                    $reader = New-Object System.IO.StreamReader($desc.Open())
                    try { $xmlText = $reader.ReadToEnd() } finally { $reader.Dispose() }
                    try {
                        [xml]$xml = $xmlText
                        $info['Root'] = $xml.DocumentElement.Name
                        # MIUI 的 description.xml 结构没有公开稳定规范，这里只报告不自称校验
                        $info['RootNote'] = 'MIUI 规范未公开，根节点仅作展示，未做断言'
                    }
                    catch {
                        # 有的包 description.xml 并非严格 XML，只记录不拦
                        $info['Root'] = '(无法解析为 XML)'
                    }
                }

                # 顶层模块目录
                $known = @('com.android.systemui', 'com.android.settings', 'com.android.contacts',
                    'com.android.mms', 'com.android.launcher', 'framework-res', 'icons',
                    'lockscreen', 'wallpaper', 'statusbar', 'boots', 'fonts', 'ringtones')
                $tops = @()
                foreach ($n in $names) {
                    if ($n -eq 'description.xml' -or $n -eq 'preview' -or $n.StartsWith('preview/')) { continue }
                    $tops += ($n -split '/')[0]
                }
                $tops = @($tops | Select-Object -Unique)
                $info['TopLevel'] = $tops
                $found = @($tops | Where-Object { $known -contains $_ })
                $info['KnownModules'] = $found

                if ($found.Count -eq 0) {
                    [void]$problems.Add('没识别出任何已知模块目录（icons / lockscreen / wallpaper / com.android.systemui …）')
                }

                return @{
                    Ok       = ($problems.Count -eq 0)
                    Kind     = 'MIUI 主题包（.mtz，只读体检）'
                    Problems = @($problems)
                    Info     = $info
                }
            }
            finally { $zip.Dispose() }
        }

        Apply = {
            param($Path)
            throw 'MIUI 适配器只实现了只读能力（探测 + 包体检），写入尚未实现。'
        }
    }
}
