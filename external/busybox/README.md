# AArch64 BusyBox 重建

此目录保存 SDK 中 `device/rockchip/common/tools/aarch64/busybox` 的源码配方，由 SDK 主仓库管理。目标保持 BusyBox 1.36.1、SDK 的 applet 配置和 Rockchip 补丁，只补上强制重启的参数传递。

## 来源

- BusyBox 1.36.1：`https://busybox.net/downloads/busybox-1.36.1.tar.bz2`，GPL-2.0；归档中的 `LICENSE` 和各源码许可保留。
- libtirpc 1.3.4：Buildroot 下载镜像，BSD-3-Clause；用于保留 SDK 的 NFS/RPC 功能。
- `build.sh` 固定校验两个源码归档的 SHA-256，拒绝损坏或不匹配的缓存。
- `0001`—`0012` 复制自本地旧 Rockchip SDK 快照提交 `c6fa72fd95b2c98371778f783156545c5b44c76b` 的 `buildroot/package/busybox/`，保留原始作者信息。该提交属于整个旧 SDK 仓库，不是 Rockchip 官方 Buildroot 上游提交。
- `sdk.config` 是相对应用上述补丁后的 1.36.1 `defconfig` 的差异，由旧工具的 `bbconfig` 提取。旧二进制 SHA-256：`d5b3d2d690138211cb43ba56005515203fede743757563316c114eedb6db0a9d`。静态链接 SDK GCC 10.3 的 libtirpc 还需显式链接 pthread。
- `0013` 仅修复 `reboot -f`：无参数继续普通重启；一个非空、至多 255 字节参数通过 `RESTART2` 传递；多参数或给 halt/poweroff 传参报错。系统调用失败返回错误，不在 BusyBox 内悄悄降级。

## 构建

在 SDK 根目录执行：

```bash
external/busybox/build.sh /tmp/busybox-build
```

需要 Bash、Python 3、curl、tar/bzip2、patch、make、宿主 C 编译器，以及 SDK GCC 10.3 AArch64 工具链。可用 `CROSS_COMPILE` 指定其他 AArch64 Linux 工具链，`JOBS` 控制并行数。归档可预先放入输出目录，校验通过后离线使用。

脚本在输出目录生成 `busybox`、完整 `busybox.config` 和保留源码的 `work.*` 目录，不自动覆盖 SDK 工具。它验证静态 AArch64 ELF；功能验证通过后再替换预置工具：

```bash
install -m 0755 /tmp/busybox-build/busybox device/rockchip/common/tools/aarch64/busybox
sudo -n env PYTHONDONTWRITEBYTECODE=1 PYTHONPATH=ubuntu24.04/tests \
  python3 -m unittest test_busybox_reboot test_anima_shutdown -v
```

x86 主机需要启用 AArch64 binfmt/QEMU（解释器带 `F` 标志，能在 chroot 中运行），测试只重启独立 PID namespace。它同时检查真实 reboot 系统调用参数和临时 ext4 离线状态，不代表 RK3576 下载模式的硬件验收。

## 使用边界

正常系统继续由 `/sbin/reboot`（systemd）处理 `reboot loader`。`anima-shutdown` 在内存根完成 overlay 卸载后才调用 `busybox reboot -nf -- loader`。不要在正常运行期用 `-f` 绕过正常卸载流程。

ARMHF 预置工具未替换；仅更新脚本而仍使用旧 BusyBox 不构成完整修复。发布时应同时包含此 AArch64 工具和更新后的 `anima-shutdown`，由原工具安装流程及 `anima-init` 复制到关机内存根。
