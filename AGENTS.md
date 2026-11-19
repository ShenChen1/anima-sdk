# ANIMA RK3576 SDK 开发指南

## 仓库边界

这是面向 ArmSoM CM5（RK3576）的 Linux SDK。根目录是 Git 主仓库，负责 CI、入口链接、`.gitmodules` 和九个子模块的提交指针。按根仓库记录的提交复现构建；`.gitmodules` 中的分支名不代表当前构建使用该分支的最新版本。

| 修改对象 | 源码位置 |
| --- | --- |
| CI、发布产物 | `.github/workflows/build-anima-ubuntu24.yml` |
| 构建目标、配置和钩子 | `device/rockchip/common/`。根目录的 `build.sh`、`Makefile`、`README.md`、`rkflash.sh` 均为链接 |
| CM5 板级配置、分区表、打包清单 | `device/rockchip/.chips/rk3576/` |
| 内核、驱动、设备树 | `kernel-6.1/`，根目录 `kernel` 指向此处 |
| 引导程序与固件 | `u-boot/`、`rkbin/`、`armsom-initrd/` |
| Ubuntu 用户空间、软件包和镜像构建 | `ubuntu24.04/`，板上文件主要来自 `overlay/` 和 `overlay-anima/`，制镜入口包括 `mk-base-ubuntu.sh`、`mk-ubuntu-rootfs.sh` 和 `mk-image.sh` |
| Rockchip 升级工具源码 | `external/recovery/update_engine/` |
| SDK 工具与交叉编译器 | `tools/`、`prebuilts/gcc/linux-x86/aarch64/` 下的 GCC 子模块 |

审查改动时先看根仓库，再检查相关子模块的暂存、未暂存和未跟踪文件。用 `git submodule status --recursive` 核对版本，用 `git -C <子模块> status --short` 查看内部改动。跨仓库交付时先提交子模块内容，再在主仓库更新对应指针；保留其他工作区改动。

## 构建 ANIMA Ubuntu 24.04 Server

从 SDK 根目录使用 Bash。CI 主机为 Ubuntu 24.04。完整依赖及 QEMU binfmt 检查见上述 workflow；构建 arm64 rootfs 需要能运行目标架构的 chroot。新克隆按以下顺序准备和构建：

```bash
git submodule update --init --recursive
git -C ubuntu24.04 lfs install --local
git -C ubuntu24.04 lfs pull
./build.sh armsom_cm5_rk3576_ubuntu24_server_defconfig
./build.sh kerneldeb
./build.sh
```

选用文件名含 `ubuntu24` 的 CM5 server defconfig。它选择 Noble、server、release。先运行 `kerneldeb`，因为 Ubuntu 制镜脚本按内核 release、Debian 包版本和架构选择配套的 headers 与 image 包。`./build.sh help` 列出目标；已配置的工作区可按范围运行 `uboot`、`kernel`、`ubuntu`、`firmware` 或 `updateimg`。

## 当前板型的启动和存储

- U-Boot 使用 `u-boot/configs/rk3576-fit-ab.config`。排查启动看门狗时，从 `u-boot/include/configs/evb_rk3576.h` 的启动命令跟到内核 WDT 驱动及用户空间接管逻辑。
- 内核使用 `armsom_linux_rk3576_defconfig` 并叠加 `rk3576_anima.config`，两者均在 `kernel-6.1/arch/arm64/configs/`。目标 DTS 是 `arch/arm64/boot/dts/rockchip/rk3576-armsom-cm5-io-f050008m01.dts`（相对于内核根目录）。板级配置选择 FIT、eMMC A/B 和空白 misc 镜像，关闭 extboot 和独立 recovery 镜像。
- 改动分区时同时核对板级 defconfig、`parameter-ab-minimal.txt` 和自定义整包清单 `package-file-ab-minimal`。整包将同一份 `boot.img` 写入两个 boot 槽，将 `rootfs.img` 写入两个 system 槽，另带 `overlay.img` 和 `data.img`。overlay 分区为 4 GiB，data 使用剩余空间；两个 ext4 初始镜像各为 128 MiB，容量与初始镜像大小要分别核对。
- Ubuntu 的 `overlay-anima/usr/sbin/anima-init` 在 systemd 前建立只读系统槽和 OverlayFS 根，持久化清单位于 `overlay-anima/etc/anima/persistent.conf`，关机卸载由 `overlay-anima/usr/sbin/anima-shutdown` 接管。共享分区挂到 `/overlay`，data 挂到 `/opt`。修改持久化时同时检查制镜、启动和关机路径，区分每次启动清空的可写层与跨槽保留的数据。
