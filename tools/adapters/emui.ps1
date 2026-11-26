# EMUI / HarmonyOS 适配器（华为 / 荣耀）
#
# 能力：探测 + 包体检（**.hwt 只读**）
# 写入未实现：`.hwt` 的落点是 /data/themes/<id>/，部分机型文件管理器可直接访问，
#            但没有真机可验证，因此不提供 apply —— 不假装支持。

function Get-EmuiAdapter {
    return [pscustomobject]@{
        Name          = 'emui'
        DisplayName   = 'EMUI / HarmonyOS / MagicOS（华为 / 荣耀）'
        SupportsApply = $false
        # 华为：/data/themes/<id>/；荣耀（新）：/sdcard/Android/data/com.hihonor.android.thememanager/files/Download/Honor/Themes
        ThemeDir      = '/data/themes'
        Descriptor    = 'description.xml'
        Note          = '只读：平台探测与 .hwt 包体检；写入未实现'

        TestPlatform = {
            $evidence = New-Object System.Collections.ArrayList
            $result = @{ Present = $false; Package = ''; Evidence = @(); Reason = '未检测到华为主题管理器' }

            $pkgs = ((Invoke-Adb @('shell', 'pm list packages')) | Out-String)
            $hit = @()
            foreach ($p in @('com.huawei.android.thememanager', 'com.hihonor.android.thememanager')) {
                if ($pkgs -match ('package:' + [regex]::Escape($p) + '\s')) { $hit += $p }
            }

            $props = @{}
            foreach ($k in @('ro.build.version.emui', 'hw_sc.build.platform.version')) {
                $v = ((Invoke-Adb @('shell', "getprop $k")) | Out-String).Trim()
                if ($v) { $props[$k] = $v }
            }

            if ($hit.Count -eq 0 -and $props.Count -eq 0) { return $result }

            foreach ($h in $hit) { [void]$evidence.Add("包: $h") }
            foreach ($k in $props.Keys) { [void]$evidence.Add("$k = $($props[$k])") }

            $dir = ((Invoke-Adb @('shell', 'ls -d /data/themes 2>/dev/null')) | Out-String).Trim()
            if ($dir) { [void]$evidence.Add('/data/themes: 存在') } else { [void]$evidence.Add('/data/themes: 不存在或不可读') }

            # 新荣耀走自己的主题 App 与目录
            $honor = '/sdcard/Android/data/com.hihonor.android.thememanager/files/Download/Honor/Themes'
            $hdir = ((Invoke-Adb @('shell', "ls -d $honor 2>/dev/null")) | Out-String).Trim()
            if ($hdir) { [void]$evidence.Add("荣耀主题目录: $honor") }

            $magic = ((Invoke-Adb @('shell', 'getprop ro.build.version.magic')) | Out-String).Trim()
            if ($magic) { [void]$evidence.Add("ro.build.version.magic = $magic") }

            $result.Present = $true
            $result.Package = ($(if ($hit) { $hit[0] } else { '' }))
            $result.Evidence = @($evidence)
            $result.Reason = '检测到 EMUI/HarmonyOS 主题管理器'
            return $result
        }

        TestPackage = {
            param($Path, $DeviceVersion = '')

            $problems = New-Object System.Collections.ArrayList
            $info = @{}
            $fail = { param($msg) @{ Ok = $false; Kind = '华为主题包'; Problems = @($msg); Info = @{} } }

            if (-not (Test-Path -LiteralPath $Path)) { return (& $fail "文件不存在：$Path") }

            Add-Type -AssemblyName System.IO.Compression.FileSystem
            $full = (Get-Item -LiteralPath $Path).FullName
            $info['File'] = [System.IO.Path]::GetFileName($full)
            $info['Size'] = (Get-Item -LiteralPath $full).Length

            $ext = [System.IO.Path]::GetExtension($full).ToLowerInvariant()
            if ($ext -notin @('.hwt', '.hnt')) {
                [void]$problems.Add('扩展名不是 .hwt / .hnt —— 华为要 .hwt，新荣耀（2023-11 之后）用 .hnt')
            }
            elseif ($ext -eq '.hnt') {
                $info['Edition'] = 'Honor (.hnt)'
                # 依据 theme 作者的官方教程：.hnt 是荣耀主题编辑器的导出格式，
                # 第三方主题应当用鸿蒙 .hwt 并按 MagicOS 版本选
                $info['Hint'] = '荣耀第三方主题建议用鸿蒙 .hwt 并按 MagicOS 版本选择；.hnt 是官方编辑器导出格式'
            }
            elseif ($ext -eq '.hwt') {
                $info['Edition'] = 'Huawei (.hwt)'
            }

            $zip = $null
            try { $zip = [System.IO.Compression.ZipFile]::OpenRead($full) }
            catch { return (& $fail "不是有效的 zip：$($_.Exception.Message)") }

            try {
                $entries = @($zip.Entries)
                $names = @($entries | ForEach-Object { $_.FullName })

                $desc = $entries | Where-Object { $_.FullName -eq 'description.xml' } | Select-Object -First 1
                if (-not $desc) { return (& $fail '缺少 description.xml（华为主题包的描述文件）') }

                $reader = New-Object System.IO.StreamReader($desc.Open())
                try { $xmlText = $reader.ReadToEnd() } finally { $reader.Dispose() }

                try { [xml]$xml = $xmlText }
                catch { return (& $fail "description.xml 不是合法 XML：$($_.Exception.Message)") }

                $rootName = $xml.DocumentElement.Name
                $info['Root'] = $rootName
                if ($rootName -ne 'HwTheme') {
                    [void]$problems.Add("根节点是 $rootName，华为规范应为 HwTheme")
                }

                foreach ($tag in @('title', 'title-cn', 'author', 'screen', 'version')) {
                    $n = $xml.SelectSingleNode("//$tag")
                    if ($n -and $n.InnerText.Trim()) { $info[$tag] = $n.InnerText.Trim() }
                }

                # 顶层目录
                $tops = @()
                foreach ($n in $names) {
                    if ($n -eq 'description.xml') { continue }
                    $tops += ($n -split '/')[0]
                }
                $tops = @($tops | Select-Object -Unique)
                $info['TopLevel'] = $tops

                # 真实样本实测顶层：description.xml / preview / wallpaper / unlock /
                #   icons / com.android.systemui / com.huawei.android.launcher
                $known = @('wallpaper', 'icons', 'lockscreen', 'unlock', 'fonts',
                    'com.android.systemui', 'framework-res', 'com.android.settings',
                    'com.huawei.android.launcher', 'com.huawei.android.mms',
                    'contacts', 'mms')
                $found = @($tops | Where-Object { $known -contains $_ })
                $info['KnownModules'] = $found
                if ($found.Count -eq 0) {
                    [void]$problems.Add('没识别出任何已知模块目录（wallpaper / icons / lockscreen / fonts …）')
                }

                # 锁屏是一套 MAML 表达式，真实样本为 unlock/lockscreen/manifest.xml
                $locks = @($names | Where-Object { $_ -match '^unlock/.+\.xml$' })
                if ($locks.Count -gt 0) { $info['LockscreenXml'] = @($locks | Select-Object -First 3) }

                # 华为 / 荣耀 / 鸿蒙 的版本对应关系（来自 theme 作者教程）
                $map = @{
                    'MagicUI' = '鸿蒙 2'; 'MagicOS 7' = '鸿蒙 2'; 'MagicOS 8' = '鸿蒙 3'
                    'MagicOS 9' = '鸿蒙 4'; 'MagicOS 10' = '鸿蒙 4'; 'MagicOS 11' = '待确认'
                }
                $info['VersionMap'] = 'MagicUI/MagicOS7→鸿蒙2；MagicOS8→鸿蒙3；MagicOS9/10→鸿蒙4'

                return @{
                    Ok       = ($problems.Count -eq 0)
                    Kind     = '华为 / 荣耀主题包（.hwt / .hnt，只读体检）'
                    Problems = @($problems)
                    Info     = $info
                }
            }
            finally { $zip.Dispose() }
        }

        Apply = {
            param($Path)
            throw 'EMUI 适配器只实现了只读能力（探测 + 包体检），写入尚未实现。'
        }
    }
}
