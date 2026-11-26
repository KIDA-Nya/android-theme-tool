# 品牌与子品牌支持矩阵

同一个集团的不同品牌，主题栈**不一定相同**。这张表说明各家实际用的是什么，以及本项目做到哪一步。

---

## 一、主矩阵

| 品牌 / 子品牌 | 主题栈 | 商店包名 | 包格式 | 本项目 |
|---|---|---|---|---|
| **OPPO** | ColorOS | `com.heytap.themestore` / `com.oplus.themestore` … | `.theme` | ✅ 整包应用（真机验证） |
| **一加 OnePlus** | 国行 ColorOS；海外 OxygenOS | 国行同 OPPO | `.theme` | ✅ 同 OPPO（本机就是一加） |
| **真我 realme** | realmeUI（基于 ColorOS） | 同 OPPO 系 | `.theme` | ✅ 大概率可用（同一套 `.theme`） |
| **小米 / Redmi / POCO** | HyperOS / MIUI | `com.android.thememanager` | `.mtz` | ⚠️ 探测 + 体检 + 免 root 注入 Theme backup（未真机验证） |
| **华为** | EMUI / HarmonyOS | `com.huawei.android.thememanager` | `.hwt` | ✅ 探测 + 体检 + 放 `Huawei/Themes` |
| **荣耀（新，2023-11 之后出厂）** | MagicOS | `com.hihonor.android.thememanager` | **`.hnt`** | ✅ 探测 + 体检 + 放荣耀主题目录 |
| **荣耀（老机型）** | 仍用华为主题 App | `com.huawei.android.thememanager` | `.hwt` | ✅ 同华为 |
| **vivo / iQOO** | OriginOS / Funtouch | `com.bbk.theme` | `.itz` | ✅ 探测 + 体检 + 放 Download 交 i主题 |
| **魅族** | Flyme | 未确认 | zip（社区称内部结构与华为类似） | ❌ 无适配器（probe 会识别出品牌并说明） |
| **三星** | One UI | 主题商店 | **APK**（主题就是安装包） | ❌ 无第三方路径，见下 |
| **努比亚 / 红魔** | MyOS / RedMagic OS | 未确认 | 自有格式 | ❌ 无适配器（有第三方转换工具） |

---

## 二、几个需要特别注意的点

### 荣耀已经从华为里"分家"了

- 2023-11-23 之后出厂的荣耀机型，用**自己的主题 App**（`com.hihonor.android.thememanager`）
  与**`.hnt`** 格式；更早的机型仍走华为的 App 与 `.hwt`。
  依据：荣耀社区里客服口径的转述 + 用户实测路径
  [`/sdcard/Android/data/com.hihonor.android.thememanager/files/Download/Honor/Themes`](https://club-api.c.hihonor.com/cn/thread-29030963-1-1.html)
- 有人把 `.hwt` 直接改名 `.hnt` 能用、也有人失败——**机型相关**，本项目不假设能用。
- MagicOS 6+ 起对第三方主题的识别普遍变差（社区普遍反馈），必要时重启或降级主题 App。

### 三星是另一种模式：主题 = APK

三星的主题包**本身就是 APK**（由 Samsung Mobile Theme Editor 生成）。
系统会校验 APK 的**安装来源**，不是从主题商店/应用商店装的就不认。

- One UI 3.0 之前：改写安装来源还能让主题/字体生效
- **One UI 3.0 及之后：来源改写基本失效**（[Sam Helper 文档](https://github.com/alipymanbu/Android/blob/master/%e5%ae%98%e7%bd%91%e7%89%88APP%e4%b8%8b%e8%bd%bd/sam%20helper/%e5%ae%89%e8%a3%85%e8%87%aa%e5%ae%9a%e4%b9%89%e4%b8%bb%e9%a2%98%e5%ad%97%e4%bd%93.md)）

所以三星没有"塞文件"这条路，本项目不提供适配器。

### 真我 / 一加 与 OPPO 同栈

- 黑厂系（OPPO / 一加 / 真我）主题包**后缀都是 `.theme`**，结构一致
  （[酷安：关于主题的基础知识](https://www.coolapk.com/feed/62343446)，作者用的是真我 GT Neo5 SE）
- 一加本机已验证；realme 大概率可用但**本项目没有在 realme 上实测**

### 努比亚 / 红魔：有人做了跨品牌转换

社区工具 [主题工坊](https://nubia.icu/index.html) 能把
澎湃 `.mtz` / ColorOS `.theme` / OriginOS `.itz` / 鸿蒙 `.hwt` / MagicOS `.hnt`
**按努比亚规则重新打包**成能装进努比亚/红魔的格式，红魔与努比亚认同一套结构。

这说明努比亚栈是独立的，但格式可转换——如果以后要支持，思路是"转包"而不是"投递"。

---

## 三、未适配品牌的处境

`probe.ps1` 会读这些属性来**至少认出品牌**，并明确说明"没有适配器"，而不是让你以为工具坏了：

| 品牌 | 探测属性 |
|---|---|
| 魅族 | `ro.meizu.product.model`、`ro.build.flyme.version` |
| 三星 | `ro.build.version.oneui`、`ro.build.version.sem` |
| 努比亚 / 红魔 | `ro.nubia.version`、`ro.build.nubia.rom.name`、`ro.redmagic.version` |
| 摩托罗拉 | `ro.mot.build.product`、`ro.mot.build.version.sdk` |

要支持一个新品牌，需要的是三样东西：**包格式**、**商店写入通道（或可投递目录）**、**真机验证**。
前两样可以靠逆向和资料补，第三样只能靠设备。
