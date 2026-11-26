# 可移植性与健壮性

结论先说：**同属 ColorOS 主题栈的机型大概率可用，其它品牌不适用。**
换机型前先跑 `tools/probe.ps1`（或手机端 `theme.sh --probe`），它会给出「完全可用 / 有降级 / 不可用」的判定。

---

## 一、硬依赖（缺一不可）

| # | 依赖 | 说明 | 缺了会怎样 |
|---|---|---|---|
| 1 | 主题商店的 `ThemeApplyService` | 必须 `exported`，且用签名级权限保护 | 无法投递，直接不可用 |
| 2 | 调用方具备 shell 或 root 身份 | 该权限是 `signature` 级，只有 shell/root 天然持有 | `SecurityException` |
| 3 | `com.oplus.uxdesign` 的 `UXTHEME_APPLY_SERVICE` | ColorOS 12+ 的实际执行者 | 旧版走另一条本地落盘逻辑，行为不同 |
| 4 | `/data/theme` 资源目录 | 模块最终落盘位置 | 换肤不生效 |
| 5 | `settings global applied_default_theme_package_name` | 判定「当前主题」 | 无法判断是否成功 |

这五项都是 **OPPO 系（ColorOS / realmeUI）专有**实现。

---

> 各品牌与**子品牌**（realme / Redmi / POCO / iQOO / 荣耀 / 魅族 / 三星 / 努比亚）的归属见
> [BRANDS.md](BRANDS.md)。

## 二、机型适配判断

| 范围 | 判断 | 依据 |
|---|---|---|
| **已验证** | 一加 LE2123 · ColorOS 16（V16.1.0）· `theme.version=16000` | 本文所有实测均来自该机 |
| **大概率可用** | OPPO / 一加 / realme 的 ColorOS 12–16、realmeUI 3+ | 服务、uxdesign、`/data/theme` 结构一致 |
| **需要试** | ColorOS 12/13/14 更早的小版本 | uxdesign 的 AIDL 版本可能不同，config 语义可能变 |
| **不适用** | ColorOS 11 及更早 | 那时没有 uxdesign，走 `/data/system/theme` 本地解包，完全是另一套 |
| **仅探测与体检** | vivo / iQOO（`.itz`） | 写入需私有 Binder，详见 [VENDOR-FINDINGS.md](VENDOR-FINDINGS.md) 第十节 |
| **不适用** | 华为 / 荣耀（`.hwt`） | 主题引擎与包格式都不同 |
| **不适用** | 小米 / Redmi（`.mtz`）、三星、原生 Android | 没有该服务与目录 |
| **不适用** | 海外 OxygenOS / 部分国际版 | 主题实现不同，多数无该服务 |

> 一句话：**这不是通用换主题工具，是 ColorOS 主题栈的调用器。**

---

## 三、换机型时会变的东西（工具已做自动探测）

| 变量 | 本机值 | 工具怎么处理 |
|---|---|---|
| 商店包名 | `com.heytap.themestore` | 在 `com.heytap.themestore` / `com.oplus.themestore` / `com.nearme.themestore` / `com.oppo.themestore` / `com.coloros.themestore` 中探测**已安装且确有该服务**的那个 |
| 服务组件全名 | `com.heytap.themestore/com.nearme.themespace.services.ThemeApplyService` | 从 `dumpsys package` 提取，兼容 `.services.ThemeApplyService` 这类简写 |
| 服务权限名 | `oppo.permission.OPPO_COMPONENT_SAFE` | 探测时同时报告 `oplus.permission.OPLUS_COMPONENT_SAFE` |
| root 实现 | KernelSU（`adb shell` 本身即 root） | 依次尝试 `su` → `/data/adb/ksud` → 已是 root |
| 冻结控制 | cgroup v2（`/sys/fs/cgroup/apps`） | 探测存在性；不可用时降级为"亮屏 + 失败重试" |
| 图片可读位置 | 应用私有目录 | 私有目录 → 外部私有目录 → `/sdcard/Pictures`+appops 三级降级 |
| adb / python 路径 | 硬编码过（已修） | 自动探测 + `THEME_ADB` / `THEME_PYTHON` 覆盖 |
| 主题版本 | `16000` | 从 `ro.oplus.theme.version` 读取并强制比对 |

> 实测过：本机同时存在 `com.heytap.themestore` 与 `com.oplus.themestore` 两个商店，
> **服务类名不同**（`com.nearme.themespace.services.ThemeApplyService` vs `.services.ThemeApplyService`）。
> 早期版本硬编码，换到这个 ROM 上就会投递错目标——现已改为自动探测。

---

## 四、健壮性弱点（如实列出）

1. **主题版本必须精确相等**
   `EditorVersion` ≠ `ro.oplus.theme.version` 就中止。跨版本主题大多要改字段重打包，
   而改完**不保证渲染正确**（资源命名可能已变）。

2. **uxdesign 的 AIDL 协议只到调用层**
   我们只确认了 `IApplyManager.apply(uri, config)` 与回调 code；
   `config` 里各字段语义未逐项逆向。大版本若改语义，可能**静默不生效**。

3. **成功判定是间接的**
   靠「UUID 变化」+ 日志 `apply success`。极少数 ROM 若两者都不变，只能靠肉眼看效果。

4. **只能整包应用**
   「只换图标 / 只换锁屏样式 / 字体 / 铃声」需要 `ThemeConfigInfo` 的 DTO 通道，尚未实现。

5. **主题包质量由作者决定**
   本机这份主题：400 个图标映射有 2 个缺文件；声明了 4 个模块但包里没有。
   工具能报告问题，不能替作者补齐素材。

6. **依赖原版商店**
   重签改包会丢签名权限（已验证），所以商店必须保持官方签名安装。

7. **未支持多用户 / 工作资料**
   所有路径与 settings 都按 `userId=0` 处理。

8. **OTA 会打断**
   系统升级后 `ro.oplus.theme.version` 变化，老主题需重新适配。

---

## 五、在陌生设备上怎么判断

```powershell
# 电脑端
.\tools\probe.ps1
```

```bash
# 手机端（Termux）
theme --probe
```

输出示例（本机）：

```
  ✓ 主题商店包         com.heytap.themestore
  ✓ 服务组件           com.heytap.themestore/com.nearme.themespace.services.ThemeApplyService
  ✓ 服务权限要求        oppo.permission.OPPO_COMPONENT_SAFE
  ✓ ro.oplus.theme.version  16000
  ✓ uxdesign          已安装（OS12+ 应用通道）
  ✓ /data/theme       存在（9 项）
  ✓ 冻结控制(cgroup v2)  可用，失败时能自动解冻
  ✓ LockWall          已安装
  ✓ Python            C:\...\python.exe

  结论：完全可用
```

判定规则：

- 有 **FAIL** → 不可用（多半是没这个服务，或没有 shell/root 身份）
- 只有 **WARN** → 可用但降级（例如没有 root 无法解冻、没有 Python 无法对齐）
- 全 **✓** → 完全可用

---

## 六、要支持其它品牌需要做什么

> 跨品牌的可行性分析、各家机制对照与适配器接口设计，见 [UNIVERSAL.md](UNIVERSAL.md)。

不同品牌的换肤机制互不兼容，需要各自实现：

| 品牌 | 包格式 | 落点 | 可行路径 |
|---|---|---|---|
| 华为 / 荣耀 | `.hwt` | `/data/themes` + 主题 App | 需逆向华为主题引擎，与本项目无共用代码 |
| 小米 / Redmi | `.mtz` | `/data/system/theme` | MIUI 有 `ThemeManager` 系统服务，思路类似但接口不同 |
| 三星 | 自有格式 | OneUI 主题商店 | 需三星 SDK / 系统服务 |
| 原生 Android | 无 | — | 只有壁纸/图标包（Launcher 层面） |

可以复用的是**方法论**：先找「谁真正写资源」（uxdesign / ThemeManager），
再用有特权的身份调它，而不是自己重写一套。
