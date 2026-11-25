<#
    适配器契约（新品牌照这个写）
    ================================

    每个适配器文件（tools/adapters/<name>.ps1）只需导出一个函数：

        function Get-<Prefix>Adapter { ... }        # 返回一个对象

    注册表（_registry.ps1）通过 `Get-<Prefix>Adapter` 找到它，所以命名必须一致。

    返回对象字段：
        Name          适配器标识（小写，如 'coloros'）
        DisplayName   展示名
        SupportsApply $true / $false —— 是否实现了写入（投递）
        ThemeDir      资源落点目录（没有就写 $null）
        Descriptor    包内描述文件名（如 themeInfo.xml）
        Note          一句话说明（未实现写入时要写清楚）

        TestPlatform  脚本块，签名 { }，返回：
                        @{ Present=bool; Package=string; Evidence=string[] ; Reason=string }
        TestPackage   脚本块，签名 { param($Path, $DeviceVersion) }，返回：
                        @{ Ok=bool; Kind=string; Problems=string[]; Info=hashtable }
        Apply         脚本块，签名 { param($Path) } —— 未实现就 throw

    约定：
        · 适配器被 dot-source 进已经加载了 tools/common.ps1 的会话，
          所以可以直接用 Invoke-Adb / Get-Setting / Resolve-Python 等
        · TestPlatform 必须只读，任何情况下不能改设备状态
        · TestPackage 只读本地文件，不碰设备
        · 未实现的写入能力必须 SupportsApply=$false 且 Apply 抛异常，
          不允许"假装支持"
#>
