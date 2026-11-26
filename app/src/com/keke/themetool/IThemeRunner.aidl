package com.keke.themetool;

/**
 * 运行在 Shizuku（shell uid）进程里的执行器。
 * 应用侧通过它执行 shell 命令 —— 权限来自 Shizuku，不来自我们自己。
 */
interface IThemeRunner {
    /** 执行脚本，返回 stdout+stderr。 */
    String run(String script);
    /** 当前身份，形如 uid=2000(shell)。 */
    String whoami();
}
