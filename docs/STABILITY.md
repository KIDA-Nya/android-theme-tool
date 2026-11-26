# 长期稳定性评估

"应用成功"不等于"长期稳定"。这份文档说明**每个平台可能把主题改回去的机制**、
**我们实测到什么程度**，以及**你怎么自己验证**。

---

## 一、结论速览

| 平台 | 稳定性证据等级 | 主要风险 |
|---|---|---|
| **ColorOS** | **实测**：13 小时静置无变化；扛过一次重启 | 商店/系统更新、OTA 改 `ro.oplus.theme.version` |
| **MIUI / HyperOS** | 静态分析：无开机广播、DRM 在应用时校验 | 商店更新、澎湃大版本与主题版本绑定、目录重扫 |
| **华为 / 荣耀** | 目录扫描模型推断 | MagicOS 6+ 识别变差、鸿蒙 5+ 不支持 |
| **vivo** | 依赖降级 i主题 | OriginOS 6+ 关闭、旧版 i主题装不上 |

---

## 二、ColorOS：有实测数据

### 实测记录

| 项 | 结果 |
|---|---|
| 应用后静置 13 小时 | `/data/theme` 全部文件时间戳未变，UUID 未变 |
| 重启设备 | 开机后 UUID 仍为目标值，8 个模块仍在，`config` 时间戳未变 |
| 用像素比对核对壁纸 | 系统里的壁纸与主题内图片一致（差值 0.00） |

### 系统里确实有"定期校验"，但对象是图标

`dumpsys jobscheduler` 里有两个 **PERSISTED 任务**：

```
com.oplus.uxdesign/.icon.autocheck.AutoCheckService
com.oplus.uxdesign/.icon.autocheck.UxMorphCheckService
  Requires: charging=true  connectivity
  Minimum latency: +1d0h0m0s   （每天一次，需充电 + 联网）
```

需要注意的地方：

- 它们是 **uxdesign 的图标自检**，不是"主题回滚"
- 但图标主题正好是它们的作用域——**理论上存在"主题图标被系统图标覆盖"的可能**
- 触发条件苛刻（充电 + 联网 + 满一天），日常难复现

### 真正的风险不在系统，而在更新

| 风险 | 后果 | 缓解 |
|---|---|---|
| 主题商店/uxdesign 更新 | 服务名、AIDL、包格式可能变 → 投递失效 | 投递前先跑 `probe`；必要时保留旧版本 APK |
| 系统 OTA | `ro.oplus.theme.version` 变化 → 老主题被 `ThemeOSVersion is diff` 拒绝 | 用 `theme_align.py`/改 `EditorVersion` 重新打包 |
| 商店后台把主题判为未授权 | 主题被回滚（社区称"掉主题"） | 按社区做法停用/冻结商店（见 GUIDE-COMPARISON.md） |

---

## 三、MIUI / HyperOS：静态分析结论

对 `com.android.thememanager` 11.5.3.1 的 APK 做的检查：

| 检查项 | 结果 |
|---|---|
| 是否注册开机广播接收器 | **没有**（manifest 里只有 `RECEIVE_BOOT_COMPLETED` 权限声明，无 `BOOT_COMPLETED` action） |
| 是否有主题相关的 JobService | 只有推送用的 `com.xiaomi.push.service.XMJobService` |
| DRM 校验在哪 | 应用时：`CheckRightsTask` / `ResourceRightsHelper$CheckRightsTask` |
| 回滚相关类 | `RestoreDefault` / `restoreDefaultTheme`（用户主动"恢复默认"用的） |

**推论**：MIUI 不会开机后自动复查并回滚；**掉主题主要发生在商店重新读库/更新之后**。
社区的经验也印证这点——他们的做法是"冻结商店防止回滚"。

### MIUI 特有的稳定性要求（来自主题作者教程）

- 澎湃OS 期间**关掉**软件商店自动更新，且**不要更新主题壁纸 / 主题商店 / 桌面**，否则可能开不了机
- 澎湃OS 3 必须用 3.0 版本的主题；澎湃 4 用对应版本，别套用旧规则
- MIUI 11 / 12 / 12.5 不推荐使用第三方主题

---

## 四、华为 / 荣耀 / vivo：能说的和不能说的

这三个平台**没有真机**，只能给结构性判断，不能给"稳定/不稳定"的结论。

### 华为 / 荣耀

- 模型是**目录扫描**：把 `.hwt`（荣耀用鸿蒙主题）放进指定目录，主题 App 自己列出
- 所以"稳定性"取决于：**商店每次启动重扫目录时还认不认这个文件**
- 已知风险：MagicOS 6+ 对第三方主题识别变差；鸿蒙 5.0（纯血）起不再支持

### vivo / iQOO

- 必须能**卸载/降级 i主题**才能用旧版导入路径；2026-01-01 之后安全更新的机型装不上旧版
- OriginOS 6 起不支持第三方主题，作者本人已停止维护

---

## 五、自己验证：`watch_theme.ps1`

```powershell
# 观察 30 分钟，每 30 秒采样
.\tools\watch_theme.ps1 -Minutes 30

# 先重启再对比（最硬的测试）
.\tools\watch_theme.ps1 -Reboot -Minutes 5 -Csv .\watch.csv
```

各平台采样的字段不同：

| 平台 | 采集内容 |
|---|---|
| ColorOS | UUID、`/data/theme` 模块清单、`config`/`icons` 时间戳 |
| MIUI | 商店库条目数与最新文件、`/data/system/theme`（有 root） |
| 华为/荣耀 | `/data/themes`、`Huawei/Themes`、荣耀主题目录 |
| vivo | `/sdcard/Android/data/com.bbk.theme`、`/data/bbkcore/theme`（有 root） |

判定：字段变化即标记；设备短暂离线会自动跳过该次采样，不算变化。

---

## 六、加固建议（按代价排序）

1. **投递前先备份**：`apply_local_theme.ps1 -Backup`（ColorOS，需 root）
2. **别让商店自动更新**：至少在一次验证周期内保持版本不变
3. **投递后用 `watch_theme.ps1 -Minutes 30` 观察一次**，确认没被改回
4. **系统 OTA 后先跑 `probe`**：版本变了就说明主题可能需要重新适配
5. **必要时冻结商店**：这是社区验证过的"防掉主题"手段

---

## 七、诚实的边界

- ColorOS：有静置 + 重启的实测数据，但**没有跨 OTA、跨商店版本**的长周期数据
- MIUI：只有静态分析与社区报告，**没有真机**
- 华为 / vivo：**连静态分析都没有**（拿不到 APK），结论来自公开资料
- 所以"长期稳定"这四个字：**ColorOS 可以说"目前稳定"；其余三个只能说到"设计上可行，未验证"**
