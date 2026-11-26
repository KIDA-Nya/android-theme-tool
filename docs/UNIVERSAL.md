# 能不能做成通用策略？

**结论：能做成「通用框架 + 每品牌驱动」，不能做成「一套流程通吃」。**

调研后确认：三大厂商的换肤机制在**结构上同构**，但**执行层（谁来写系统资源）完全不通用**。
所以正确的抽象是适配器架构，而不是统一流程。

---

## 一、调研：各家机制对照

| 维度 | ColorOS（OPPO/一加/realme） | MIUI / HyperOS（小米） | EMUI / HarmonyOS（华为） |
|---|---|---|---|
| 包后缀 | `.theme` | `.mtz` | `.hwt` |
| 本质 | zip | zip（可直接改名 .zip） | zip（可直接改名 .zip） |
| 描述文件 | `themeInfo.xml`，根节点 `OplusSmartPhoneThemeInfo` | 包内 `description.xml` | `description.xml`，根节点 `HwTheme` |
| 版本门禁 | `EditorVersion` = `ro.oplus.theme.version` | 主题名里的 V 号（V15/V17…）对应系统代次 | `<version>` / `<screen>` 等字段 |
| 系统执行者 | `com.oplus.uxdesign`（`UxThemeService`，AIDL） | `com.android.thememanager` | `com.huawei.android.thememanager` |
| 资源落点 | `/data/theme/` | `/data/system/theme`（历史上）、商店内部管理 | `/data/themes/<id>/` |
| 模块单位 | 每模块一个内嵌 zip（`icons`/`systemui`/`settings`…） | 包内目录（com.android.systemui、icons、lockscreen…） | 包内目录（wallpaper、icons、lockscreen…） |
| 无 root 可行？ | 可行（shell 身份调商店服务） | 可行（第三方工具用 Shizuku 写入） | 部分机型可行（官方允许访问 `/data/themes/0`） |

依据：

- ColorOS 主题包结构与模块划分 — [酷安：关于主题的基础知识](https://www.coolapk.com/feed/62343446)
- ColorOS 官方适配教程（改 `themeInfo.xml` 的 `UUID`/`PackageName`/版本号）— [OPPO 开发者论坛](https://open.oppomobile.com/bbs/forum.php?mod=viewthread&tid=3298&extra=&ordertype=2)
- `com.oplus.uxdesign` 就是「个性化定制」，负责图标/壁纸/字体/控制中心 — [9K9K 应用信息](https://www.9k9k.com/app/78047.html)
- uxdesign 的 uid **因机型而异**（该文引用 10232，本机实测 10307）— [ColorOS-Font-Injector](https://github.com/Beicxxxx/ColorOS-Font-Injector)
- MTZ 是 zip、系统自动解压覆盖 — [百度百科 MTZ](https://baike.baidu.com/item/MTZ/22157822)
- 华为 `.hwt` 走 `/data/themes/0/`、改 `description.xml` — [华为付费主题实践](https://blog.devintom.top/2025/11/29/%E5%85%8D%E8%B4%B9%E4%BD%BF%E7%94%A8%E5%8D%8E%E4%B8%BA%E4%BB%98%E8%B4%B9%E4%B8%BB%E9%A2%98/)
- 华为主题包规范（`description.xml`）— [HUAWEI Themes 测试规范](https://developer.huawei.com/consumer/jp/doc/content/tablet-theme-test-0000001079369956)

---

## 二、哪些能抽象，哪些不能

```
┌─────────────────────────────────────────────────────┐
│ L1 平台识别   detect()          ← 可通用（本仓库已实现）│
│   · 存在哪个商店包 / 哪个执行者 / 哪个资源目录        │
├─────────────────────────────────────────────────────┤
│ L2 包体检     validate()        ← 可通用（换描述文件解析）│
│   · 是不是该平台的包、版本门禁、声明与内容是否一致     │
├─────────────────────────────────────────────────────┤
│ L3 包预处理   prepare()         ← 可通用（换字段名）    │
│   · 补声明 / 换 UUID / 调版本号                       │
├─────────────────────────────────────────────────────┤
│ L4 投递       apply()           ← ✗ 必须每品牌实现     │
│   · ColorOS：调 ThemeApplyService（签名权限）          │
│   · MIUI：写 /data/system/theme 或调 thememanager      │
│   · EMUI：放 /data/themes/<id> 或调 thememanager       │
├─────────────────────────────────────────────────────┤
│ L5 校验       verify()          ← 半通用（判据不同）    │
│   · ColorOS：UUID + /data/theme 落盘                   │
│   · 其它：资源目录 mtime / 商店当前主题 id             │
└─────────────────────────────────────────────────────┘
```

**L1–L3 约占工作量 60%，且已经写成品牌无关的形态**（`check_theme.py` / `theme_align.py` / `newuuid.py`
只依赖"zip + 描述文件"这个共识）。真正需要重写的是 **L4/L5**。

---

## 三、适配器契约（建议接口）

```
detect(device) -> { stack, package, service, themeDir, versionProp, ok, reason }
validate(themePath) -> { ok, problems[], descriptor{...} }
prepare(themePath, outPath) -> { changed, added[], versionFixed }
apply(themePath) -> { ok, code, message }
verify(expectedId) -> { ok, evidence{} }
```

本仓库的 `tools/probe.ps1` 已实现 `detect()` 的雏形，并在输出里标注
「平台识别 / 适配器」两行（ColorOS 显示已实现，MIUI/EMUI 显示未实现）。

---

## 四、各平台移植要点

### ColorOS — 已实现

见 [PORTABILITY.md](PORTABILITY.md)。要点：签名级权限只能靠 shell/root；
进程会被冻结；成功判据是 UUID 切换。

### MIUI / HyperOS — 未实现写入，但已拿到真实 APK 的证据

实测 `com.android.thememanager` 11.5.3.1（详见 [VENDOR-FINDINGS.md](VENDOR-FINDINGS.md)）：

- 包：`.mtz`（zip），**dex 中确有 `description.xml`**，校验器的假设成立
- 资源落点：`/data/system/theme/`，配置 `/data/system/theme/config.config`，
  子目录 `fonts/ lockscreen/ ai_icon/ aod/ large_icons/ rights/ rearScreen/ player_exo/`
- **有一个 exported 服务**：`com.android.thememanager.service.ThemeService`
  （action `com.miui.service.THEMESERVICE`，权限 `miui.permission.USE_INTERNAL_GENERAL_API`），
  实现框架 AIDL `miui.content.res.IThemeService`
- 另有 `ThemePCService`（`IThemePCService`），是电脑端工具接口
- 应用流程是 **应用内** 的（`ApplyThemeTask` / `ProvisionApplyTheme`），
  没有公开的「按路径应用」API
- 社区做法是 **Zygisk hook**（在主题管理器进程内注入桥接），不是调服务

**结论（已查到接口定义）**：`miui.content.res.IThemeService` 只有 4 个方法，
全部是「按路径设置单项资源」——

```java
boolean saveWallpaper(String path)
boolean saveLockWallpaper(String path)
boolean saveIcon(String path)
boolean saveCustomizedIcon(String name, Bitmap icon)
```

**没有任何接受主题包的方法。** 所以 MIUI 上「免 root 应用整包主题」在接口层就不存在，
不是没实现，是没接口。免 root 能做到的是壁纸 + 图标（partial apply）。

社区真机报告的原话：无 root 设备上 "wallpapers and icons yes, a whole theme no"。

### EMUI / HarmonyOS — 未实现，部分机型甚至无需特权

- 包：`.hwt`（zip），`description.xml` 根节点 `HwTheme`
- **真实样本实测**顶层：`description.xml` / `preview/` / `wallpaper/` / `unlock/` /
  `icons/` / `com.android.systemui/` / `com.huawei.android.launcher/`
- 锁屏是 MAML 脚本，实测文件名 `unlock/theme.xml`
- 资源落点：`/data/themes/<id>/`（公开资料，未真机验证）
- 社区做法：直接在文件管理器里访问 `/data/themes/0/` 复制/放回（部分机型开放访问）
- 移植工作：`detect()`（认 thememanager）、`apply()`（放目录 + 触发商店刷新）
- 注意：HarmonyOS NEXT 起不再兼容 Android 应用，方案需重做

---

## 五、实现进度（v2.1.0）

> 厂商实测记录（含 APK 获取途径、组件、路径、仍然未知的部分）见
> [VENDOR-FINDINGS.md](VENDOR-FINDINGS.md)。

适配器契约已落到代码，不再只是设想：

| 文件 | 作用 |
|---|---|
| `tools/adapters/_registry.ps1` | 注册表：加载、探测、选择适配器 |
| `tools/adapters/coloros.ps1` | 探测 + 包体检 + **写入**（委托给 apply_local_theme.ps1） |
| `tools/adapters/miui.ps1` | 探测 + `.mtz` 包体检（**只读**） |
| `tools/adapters/emui.ps1` | 探测 + `.hwt` 包体检（**只读**） |
| `tools/adapters/_template.ps1` | 新品牌模板（契约说明） |
| `tools/check_package.ps1` | 统一入口：按扩展名/描述文件选适配器做体检 |
| `tests/run_tests.ps1` | 无真机回归：合成 mtz/hwt 夹具 + 真实 .theme |

`probe.ps1` 现在是适配器选择器，输出形如：

```
[OK] 平台识别   coloros
[OK] 适配器    coloros（可写入）
```

未实现写入的平台会明确显示「只读」，`Apply` 脚本块直接抛错，不会假装成功。

**验证情况**：ColorOS 侧在真机端到端验证；MIUI / EMUI 侧只有合成夹具验证
（`tests/run_tests.ps1` 6 项全过），**没有真机** —— 所以那两个 `TestPlatform`
只保证"不误报"，不保证真机命中。

---

## 六、已有社区工具（避免重复造轮子）

| 项目 | 作用 | 与本项目的关系 |
|---|---|---|
| [ShizuTools](https://github.com/legendsayantan/ShizuTools) | 通过 Shizuku 做系统级操作，含 ThemePatcher | **同路线**（Shizuku + 商店），但它解决"付费内容解锁"，不处理本地 `.theme` 投递 |
| [ThemePatcher](https://github.com/legendsayantan/ThemePatcher) | 解锁 Oppo/Realme/OnePlus 主题商店付费主题 | 同上，功能互补而非重叠 |
| [ColorOS-Font-Injector](https://github.com/Beicxxxx/ColorOS-Font-Injector) | 免 root 注入字体（TOCTOU 竞态） | 佐证 uxdesign 是高权限执行者，且 uid 需动态获取 |
| [CrossPro / Mtzeditor](https://github.com/Alisuuu/Mtzeditor) | MIUI/HyperOS MTZ 解包/编辑/重打包 | MIUI 适配器可参考其包处理 |
| 社区「冻结法」 | 冻结主题商店防止主题被回滚 | 与本项目的"解冻以完成应用"是**相反用途**，可共存 |

---

## 七、可行性结论

| 问题 | 回答 |
|---|---|
| 能不能一套代码跑通所有品牌？ | **不能**。执行层与权限模型完全不同 |
| 能不能做成统一框架 + 插件？ | **能**，且 L1–L3 已有 60% 可复用 |
| 工作量估计 | ColorOS 已完成；MIUI 约需新增 1 个 `detect+apply+verify` 与 mtz 解析（中等）；EMUI 更简单（低） |
| 最大风险 | ① 各厂商随时改服务名/协议（本项目已用探测缓解）② 主题版本门禁导致老包不可用（改字段可绕，但渲染不保证） |
| 建议的产品形态 | 一个 `probe` + 一个 `apply`，内部按 `detect()` 结果选适配器；未支持平台明确报"无适配器"而不是假装能跑 |

**不建议**把不同品牌的逻辑揉进同一份脚本里用 if/else 分叉——那会重蹈硬编码的覆辙
（本项目就吃过一次亏：写死了商店包名与服务类名）。

---

## 八、下一步（如果要继续）

1. 把现有 ColorOS 逻辑抽成 `adapters/coloros.ps1`，`apply_local_theme.ps1` 只做参数与调度
2. 加 `adapters/_template.ps1` 作为新品牌模板
3. MIUI 适配器：先只做 `detect + validate`（只读，安全），跑通再实现 `apply`
4. 把 `probe.ps1` 升级为"适配器选择器"，输出 `建议适配器: xxx`
