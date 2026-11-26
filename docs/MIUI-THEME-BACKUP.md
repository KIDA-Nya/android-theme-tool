# MIUI / HyperOS 换主题：还有哪些路（含一条免 root 的新路）

结论先说：找到 **4 条可用的第三方方案**，其中 **1 条免 root**（利用商店自己信任的
"Theme backup"），本项目已把它实现成工具。

---

## 一、方案对照

| 方案 | 需要 | 能做什么 | 来源 |
|---|---|---|---|
| **① Theme backup 注入** | **Shizuku / shell**（免 root） | 替换 backup 里的组件（图标已验证可行；其它组件理论上同机制） | [SonderIcons](https://github.com/Verisonder/SonderIcons) 的实作 + 本项目实现 |
| ② HyperOS Theme Manager V7 | Magisk / KernelSU（root） | **直接替换主题商店**：多服务器、付费主题、**第三方 .mtz 导入**、超级图标 | [Magisk Hub](https://magisk.yssn.tech/modules/hyperos-theme-manager/) ★221 |
| ③ Xposed 模块 `themeimport` | root + LSPosed（libxposed API 102） | 恢复「本地 MTZ 导入」与「主题混搭」入口 | [Xposed-Modules-Repo](https://github.com/Xposed-Modules-Repo/io.github.gkeyes.themeimport) |
| ④ ThemeStore (`com.merak`) | Shizuku 或 root | 把 `.mtz` 写进系统主题目录 | [说明文档](https://github.com/alipymanbu/Android/blob/master/%E5%AE%98%E7%BD%91%E7%89%88APP%E4%B8%8B%E8%BD%BD/ThemeStore%E5%AE%98%E7%BD%91%E7%89%88%E6%9C%AC/%E4%B8%8B%E8%BD%BD%E4%B8%8E%E5%AE%89%E8%A3%85%E6%95%99%E7%A8%8B.md) |
| ⑤ 降版本 / 清模块 | 无 | 主题商店卸载更新；从 `.mtz` 里删掉不兼容模块（如 `com.mi.androidglobalmanager`） | [XDA 讨论](https://xdaforums.com/t/unable-to-apply-mtz-themes-in-chinese-rom.4795568/) |

> 注：②③ 都是 root 方案；④ 与 ① 同为 Shizuku 级，但 ④ 是"写系统主题目录"，
> 而 ① 是"让商店自己写"——权限始终在商店手里。

---

## 二、① 的原理：商店信任它自己造的 backup

来自 [SonderIcons 的 `ThemeStore.kt`](https://github.com/Verisonder/SonderIcons/blob/main/app/src/main/java/com/verisonder/sondericons/ThemeStore.kt)（带源码注释，可信度高）：

```
/sdcard/Android/data/com.android.thememanager/files/MIUI/theme/.data/
    content/<code>/<id>.mrc      组件本体（一个 zip）
    meta/<code>/<id>.mrm         组件元数据 JSON：hash = SHA-1(.mrc)，size = 长度
    meta/theme/<themeId>.mrm     主题元数据：列出 components（resourceCode + localId）
```

关键事实（逐条来自该文件注释）：

1. **`hash` 就是 `.mrc` 的 SHA-1，`size` 就是长度，没有任何签名**。
2. **"Theme backup"（商店「定制主题」生成的）没有 rights 记录，应用时不问服务器**；
   而**手动加进去的主题会去请求授权并失败**。
3. 所以正解不是新建主题，而是：**把已有 backup 的组件 `localId` 指向我们的文件**。
4. **这个目录 shell(uid 2000) 可读写**，而 `/data/system/theme` 不行——
   应用时由商店自己把内容拷过去，权限一直在商店手里。

这正好印证了之前的判断：手写 catalogue 记录没用（那个测试是在 `Android/data` 里造新记录），
而"改已有 backup"是另一条路，因为它复用了商店自己认可的对象。

---

## 三、本项目的实现

```powershell
# 1) 看设备上有哪些 backup（会自动从设备拉取库）
.\tools\miui_theme_backup.ps1 -List

# 2) 把某主题的 icons 模块注入指定 backup
.\tools\miui_theme_backup.ps1 -Mtz '.\某主题.mtz' -Theme <localId> -Component icons

# 3) 先看计划不回推
.\tools\miui_theme_backup.ps1 -Mtz x.mtz -Theme <id> -DryRun
```

流程：`adb pull` 商店库 → 本地改（`tools/miui_backup_inject.py`）→ **只回推改动的 3 个文件**
→ `am force-stop com.android.thememanager` → 手机上去应用那个 "Theme backup"。

改的东西：

```
content/<code>/<新id>.mrc        由 .mtz 的 <code>/ 模块重新打包
meta/<code>/<新id>.mrm           继承原组件字段，更新 hash / size / 显示名
meta/theme/<themeId>.mrm         该组件的 localId 指向新 id
```

### 前提条件（重要）

手机上必须先**生成一个 Theme backup**：主题应用 → 定制主题/混搭 → 改任意一项 → 应用。
没有这个对象，注入无处可落。

### 验证到什么程度

- **有单元测试**：`tests/mk_miui_data_fixture.py` 造出与真实结构一致的库，
  `tests/check_miui_inject.py` 校验 hash/size/localId/内容（8 项），已进 `run_tests.ps1`
- **没有真机验证**：我手上没有小米设备，无法确认商店在应用时是否还会做别的检查
- 组件代码目前默认 `icons`；其它组件（`wallpaper` / `com.android.systemui` …）走同一机制，
  但**是否被商店接受未知**，建议先在 icons 上试

### 风险与回退

- 注入只新增文件 + 改一处 `localId`，不动原组件文件 → 想回退就把 `localId` 改回原值
- 若商店版本结构不同（`components` 字段名不一样），工具会打印现有组件列表并退出，
  不会盲写
- 最坏情况：主题应用读库异常 → 清除主题应用数据即可恢复（会丢失已下载主题记录）

---

## 四、为什么这条路比之前几条都强

| 之前的尝试 | 结果 | 为什么 |
|---|---|---|
| 调 `ThemeService` | ❌ | 只有 4 个方法（壁纸/图标），没有整包应用 |
| 写 `/data/system/theme` | ❌ | 要 root；且 DRM 检查在应用前 |
| 手写 catalogue 记录 | ❌ | 目录在 App 私有数据库，`Android/data` 只是镜像 |
| **改已有 Theme backup** | ✅ 免 root | 复用了商店**自己造的、免 DRM 的**对象 |

---

## 五、如果这条路在真机上失败

按代价从小到大试：

1. **降版本**：设置里卸载主题应用更新，回到旧版再试（XDA 上最常奏效的一招）
2. **ThemeStore (`com.merak`)**：Shizuku 授权后由它写系统主题目录
3. **HyperOS Theme Manager V7**（Magisk/KSU）：直接换成支持第三方导入的商店
4. **Xposed `themeimport`**（root + LSPosed）：恢复官方导入入口
