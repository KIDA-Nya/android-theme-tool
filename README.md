# Android 主题工具

把本地主题包装进手机：ColorOS 的 `.theme`、小米的 `.mtz`、华为的 `.hwt`、vivo 的 `.itz`。
不改包、不重签、不用装框架。

```powershell
.\tools\theme_cli.ps1 apply -Theme .\主题.theme
```

一条命令，它自己看机型选路子。

---

## 能做什么

**整包应用。** ColorOS 上直接调商店的投递服务，等于替你点了「应用」。应用前会先对齐模块声明——很多主题里有 `icons/` 却没在 `themeInfo.xml` 里声明，不补上图标就不会生效。

**混搭。** 从多个主题里各取一个模块，拼成一个包再应用：

```powershell
.\tools\theme_cli.ps1 apply -Theme .\底包.theme -Mix 'icons:D:\别的主题.theme'
```

**只应用部分模块。** 只要图标和壁纸，其余保持系统默认：

```powershell
.\tools\theme_cli.ps1 apply -Theme .\完整.theme -Only icons,wallpaper
```

**应用前体检。** `.theme` / `.mtz` / `.hwt` / `.itz` 都能查，看版本对不对、声明和内容一不一致：

```powershell
.\tools\theme_cli.ps1 check -Theme .\主题.theme
```

**快照与恢复。** 应用前把 `/data/theme` 备份一份，翻车了能退回去（需要 root）：

```powershell
.\tools\apply_local_theme.ps1 -Backup
.\tools\apply_local_theme.ps1 -Restore
```

**换 UUID。** 同一个主题再应用一次会没反应，因为系统按 UUID 判断"已经是这个了"。换个 UUID 就能强制重来：`tools/newuuid.py`。

**拆资源。** 把包里的壁纸、图标、字体、铃声拿出来。这个跟主题能不能装无关，拿到图就能直接设壁纸——任何品牌都行。

**看稳定性。** 应用完担心被系统改回去，可以挂着观察：

```powershell
.\tools\watch_theme.ps1 -Minutes 30
.\tools\watch_theme.ps1 -Reboot -Minutes 5
```

不会敲命令的话，双击 `主题工具.bat`，或者把主题文件拖到它图标上松手。

---

## 在你的手机上能用到哪一步

**ColorOS（OPPO / 一加 / realme）** 是真跑通的。一加 9 Pro，ColorOS 16，商店 17.11.7，uxdesign 16.1.3。反复应用过几次，重启三次、放着十三个小时，主题都还在。上面那些功能全都能用。

**小米 / 澎湃、华为、荣耀、vivo** 这四家没有对外开放的接口，做不到直接应用。工具能做的是探测、体检，然后把包放到商店能扫到的位置，剩下的由你在商店里点几下完成：

- 小米：放 `/sdcard/Download/`，商店里走「本地导入」
- 华为：放 `/sdcard/Huawei/Themes/`
- 荣耀：第三方主题要用鸿蒙的 `.hwt`，按 MagicOS 版本选
- vivo：放 Download，走 i主题 的「本地主题」

这四个平台的代码写了、单元测试有，**没在真机上跑过**。别当成"已支持"。

---

## 用之前值得知道

需要手机的 USB 调试打开、电脑上有 `adb`。对齐模块声明要用 Python 3.8+，没有也能跑，只是图标可能不生效。root 可选，有的话能自动解冻进程、能快照备份。

**小米用户先看这条。** 主题作者的官方教程里写着：MIUI 11/12/12.5 必须用 2026-01-11 之后出的主题包，否则可能开不了机；MIUI 12/12.5 用 MIUI 13 以上的主题会无限重启，作者标了 100% 复现。这条已经写进体检，`check_package.ps1` 会读你的 MIUI 版本和包内文件时间，命中就红字拦住。

只处理 ROM 主题包。商店下载下来的那种 `resources/ descriptions/ previews/` 结构的 inner 包走另一套通道，还不支持。只换字体或只换铃声也不行，那是独立入口。平板、折叠屏、海外版 ROM 没验过。

---

## 怎么实现的

ColorOS 的主题商店有个导出的服务 `ThemeApplyService`，用 `signature` 级权限保护——普通 App 拿不到，但 shell 和 root 天生就有。所以工具做的事就是：把包装到设备能读的位置，然后用 shell 身份调这个服务，剩下的交给系统。

真正写盘的是 `com.oplus.uxdesign`，它把模块解开落到 `/data/theme`，最后把 `applied_default_theme_package_name` 改成主题的 UUID。成功与否不看日志（日志会被系统刷屏冲掉），看 UUID 变没变。

另外几条常见做法走不通，简单说原因：重签会丢掉全部签名权限，装上也没用；直接往 `/data/theme` 拷文件，商店不认这是"已应用"；手写商店的数据库记录也没用，那记录在 App 私有库里。

其它平台没有等价的公开接口，所以只能走"把包交给商店"。每个平台的依据写在 `docs/BRANDS.md` 和 `docs/VENDOR-FINDINGS.md` 里。

代码分两层：`tools/adapters/` 下每个平台一个适配器，负责探测和包体检；`tools/theme_cli.ps1` 是统一入口，按探测结果选适配器。加新平台只需要新增一个适配器文件。

---

## 文档

- `docs/USAGE.md` — 怎么用，五种上手方式，排错，回滚
- `docs/BRANDS.md` — 各品牌和子品牌到底用哪套主题栈
- `docs/VENDOR-FINDINGS.md` — MIUI / 华为 / vivo 的真包分析结论
- `docs/ANALYSIS.md` — ColorOS 那条链路的完整逆向过程
- `docs/STABILITY.md` — 谁会把你的主题改回去
- `docs/ADB.md` — 只要 4 条 adb 命令的极简版

---

MIT 协议。如果它帮你省了几个小时，点个 star 就行。
