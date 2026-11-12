# Linux 7.4-rc1 内核编译与启动实战

在第二块磁盘（sdb）上编译 Linux 7.4-rc1，不影响日常系统（sda），并成功启动进入 COSMIC 桌面。

## 环境
- CPU: AMD Ryzen 5 5500U (6C/12T)
- 内存: 14 GiB，无 Swap
- sda: 日常系统（btrfs，archroot）
- sdb: 目标盘（btrfs，ARCH-ROOT），编译 7.4.0-rc1-mainline
- 编译工具: gcc 16.2.1, mold 3.0.0, sccache 0.19.0

## 脚本清单
| 脚本 | 用途 |
|---|---|
| `01_check_target_disk_sdb_from_sda.sh` | 在 sda 上只读检查 sdb |
| `02_check_chroot_build_environment.sh` | 进 chroot 后检查编译环境 |
| `03_install_kernel_and_update_bootloader.sh` | 安装内核并更新引导 |
| `04_monitor_system_during_compile.sh` | 编译期间系统监控 |
| `05_deep_hardware_scan_and_config_audit.sh` | 硬件深度扫描 |
| `06_post_boot_hardware_acceptance_check.sh` | 启动后硬件验收 |

## 执行报告
完整踩坑记录见 `execution_report_2026-11-06_linux-7.4rc1_build_and_boot.md`。

## 关键经验
1. chroot 可编译，但有三个前提：sccache server 在 chroot 命名空间（`root=sdb`）、`TMPDIR=/var/tmp` 避开 chroot 的 tmpfs、PATH 前置 gcc wrapper 而非 sccache shim。详见 `handover_2026-11-12_linux-7.4rc2_to_rc3_交接报告.md`。
2. chroot 里 `mkinitcpio` 的 `autodetect` 看到的是 sda 硬件，initramfs 会膨胀到 200M+（正常 20~30M），**但不影响启动**，要缩回需在 sdb 原生启动后跑 `mkinitcpio -p linux-mainline`。
3. `taskset -c 0-8 nice -n 19` 是笔记本编译最实用的限速组合。
4. 缓存目录永远不清，安装失败用 `pacman -Sw` + `pacman -U`。
5. `/boot` 是 vfat，不能用符号链接，内核必须 `cp` 真实文件。
