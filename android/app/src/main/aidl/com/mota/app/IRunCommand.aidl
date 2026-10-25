package com.mota.app;

/** Shizuku UserService AIDL：执行一条 shell 命令并回传输出 */
interface IRunCommand {
    String runCommand(String cmd);
}
