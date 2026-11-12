# Linux 7.4-rc1 内核编译与启动执行报告

- 日期：2026-11-06

> ⚠️ **部分结论已被 rc2 实践修正（2026-11-12）**：
> 1. "编译不要放 chroot 里" → rc2 证明 chroot 可编译，条件是 sccache server 命名空间正确 + `TMPDIR=/var/tmp` + PATH 干净
> 2. `LDFLAGS="-fuse-ld=mold"` 是无效命令，rc1 实际用 GNU ld；mold 不能链接内核（`SECTIONS` 不支持）
> 3. "在 sdb 原生启动后跑 mkinitcpio 会缩回 20~30M" → rc2 仍在 chroot 跑，initramfs 204M，不影响启动
>
> 详见 `7.4-rc2_增量编译_过程经验教训.md`。

- 目标：在 sdb（第二块磁盘，ARCH-ROOT）上编译 Linux 7.4-rc1，不影响 sda 日常系统
- 结果：**成功**。sdb 已用 `7.4.0-rc1-mainline` 启动，关键硬件驱动全部加载

---

## 一、环境

| 项目 | 值 |
|---|---|
| CPU | AMD Ryzen 5 5500U（6C/12T） |
| 内存 | 14 GiB，无 Swap |
| sda（日常系统） | btrfs，`/dev/sda3`，内核 7.2.14-arch1-1 |
| sdb（目标盘） | btrfs，`/dev/sdb4`，ESP `/dev/sdb3`，fstab 挂载点 `/efi` |
| sdb 原内核 | 7.2.14-arch1-1 |
| 编译内核 | 7.4.0-rc1-mainline（源码来自清华 git 镜像 `v7.4-rc1` tag） |
| 编译工具 | gcc 16.2.1、mold 3.0.0、sccache 0.19.0 |
| 编译方式 | `taskset -c 0-8 nice -n 19 make -j9 LDFLAGS="-fuse-ld=mold" LOCALVERSION=-mainline` |

---

## 二、执行时间线

1. **只读检查 sdb**：确认分区、fstab、mkinitcpio、Secure Boot、`/boot` 结构、剩余空间。
2. **挂载 sdb 并进入 chroot**：`/dev/sdb4` → `/mnt`，`/dev/sdb3` → `/mnt/efi`，`arch-chroot /mnt`。
3. **修复 sdb 的 `pacman.conf`**：第一行裸 `SigLevel = Never` 导致 pacman 无法启动，用 sda 的正常配置覆盖。
4. **复用 sda 的 pacman 缓存**：只读 bind mount `/var/cache/pacman/pkg` 到 `/mnt/sda_cache`，`CacheDir` 可写在前后只读在后。
5. **升级 sdb 并安装工具链**：`pacman -Syu` + `base-devel bc bison flex libelf openssl ncurses pahole cpio zstd mold`。
6. **获取 7.4-rc1 源码**：所有 HTTP 镜像的 tarball 都返回错误页，改用清华 git 浅克隆 `--depth 1 --branch v7.4-rc1`。
7. **裁剪内核**：`make localmodconfig`，确认 `CONFIG_BTRFS_FS=y`、`CONFIG_BLK_DEV_SD=y`、`CONFIG_SATA_AHCI=y`。
8. **编译**：`taskset -c 0-8 nice -n 19 make -j9 LDFLAGS="-fuse-ld=mold" LOCALVERSION=-mainline`，约 1 小时。
9. **手动安装内核**：`cp bzImage /boot/vmlinuz-linux-mainline`，创建 `/etc/mkinitcpio.d/linux-mainline.preset`，`mkinitcpio -P linux-mainline`，`grub-mkconfig`。
10. **重启验证**：`uname -a` 显示 `7.4.0-rc1-mainline`，网卡 1000Mb/s 全双工，`uas` 加载，触摸板/声卡/蓝牙/显卡全部正常。

---

## 三、踩坑与错误清单（重点）

### 错误 1：`makepkg` 不能以 root 运行
- **现象**：`ERROR: Running makepkg as root is not allowed`
- **原因**：`makepkg` 硬性禁止 root，防止损坏系统。
- **解决**：创建非特权用户 `builder`，`su - builder` 后再编译。

### 错误 2：`arch-chroot` 命令不存在
- **现象**：`bash: arch-chroot: command not found`
- **原因**：`arch-chroot` 属于 `arch-install-scripts` 包，sda 上未安装。
- **解决**：`pacman -S arch-install-scripts`。

### 错误 3：sdb 的 `pacman.conf` 第一行非法
- **现象**：`error: config file /etc/pacman.conf, line 1: All directives must belong to a section.`
- **原因**：第一行是裸的 `SigLevel = Never`，不在 `[options]` 段内。
- **解决**：在 sda 上 `cp /etc/pacman.conf /mnt/etc/pacman.conf` 覆盖。

### 错误 4：`dwarves` 包不存在
- **现象**：`error: target not found: dwarves`
- **原因**：Arch 中提供 `pahole` 的包名是 **`pahole`**，不是 `dwarves`。
- **解决**：安装命令里用 `pahole`。

### 错误 5：`mirrors.cernet.edu.cn` 返回 403
- **现象**：`failed retrieving file 'extra.db' ... 403`
- **原因**：该 CDN 对部分路径限制访问。
- **解决**：换清华 + 中科大，或 `reflector --sort rate` 自动排序。

### 错误 6：`CacheDir` 顺序写反
- **现象**：如果只读的 `/sda_cache/` 写在前面，sdb 独有的包会尝试下载到只读目录而失败。
- **原因**：pacman 只向**第一个** `CacheDir` 下载，但会按顺序搜索所有目录。
- **解决**：可写的 `/var/cache/pacman/pkg/` 在前，只读的 `/sda_cache/` 在后。

### 错误 7：fstab 里 bind mount 写错源路径
- **现象**：`mount -a` 后 `/sda_cache` 指向 `sdb4` 而不是 `sda3`。
- **原因**：在 chroot 里写 `/var/cache/pacman/pkg`，解析到的是 sdb 自己的路径。
- **解决**：**不要写进 fstab**。手动在 sda 上 `mount --bind -o ro /var/cache/pacman/pkg /mnt/sda_cache`，进 chroot 后验证 `findmnt /sda_cache` 只来自 sda3。

### 错误 8：`systemd-run` 在 chroot 里不可用
- **现象**：`Failed to connect to system scope bus via local transport`
- **原因**：chroot 里没有运行 systemd 和 D-Bus。
- **解决**：放弃 `systemd-run`，改用 `taskset -c 0-8 nice -n 19` 做核心隔离和优先级控制。

### 错误 9：`cpulimit` 在 Arch 上不可用
- **现象**：`error: target not found: cpulimit`
- **原因**：该包已从 Arch 仓库移除，AUR 版本也陈旧。
- **解决**：不用 `cpulimit`。`taskset` 限定核心数 + `nice 19` 足够控制笔记本负载。

### 错误 10：`localmodconfig` 裁掉无线网卡驱动
- **现象**：`# CONFIG_RTW89_8852AE is not set`
- **原因**：运行 `localmodconfig` 时无线网卡模块未加载，被判定“不需要”。
- **解决**：`menuconfig` 里手动把 `CONFIG_RTW89_8852AE` 设为 `m`。更稳妥的做法是先用 `modprobed-db` 积累使用记录，或用 `hwdetect --show-modules` 对照 `.config` 审计。

### 错误 11：`localmodconfig` 裁掉有线网卡驱动
- **现象**：`# CONFIG_R8169 is not set`、`# CONFIG_E1000E is not set` 等。
- **原因**：当前用的是 USB 网卡，板载有线网卡未加载，被裁掉。
- **解决**：如果可移植性重要，在 `menuconfig` 里把 `R8169`、`E1000E`、`IGB` 等常见网卡设为 `m`。

### 错误 12：sccache 在 chroot 里的路径陷阱
- **现象**：`/usr/lib/sccache/bin/rustc -vV` 全部 CPU 0.0%，`make` 卡住无输出。
- **原因**：sccache server 在宿主机上运行，看不到 chroot 内的路径，hash 阶段卡死。
- **解决**：**编译不要放在 chroot 里**。下次在 sdb 原生启动的环境里编，`SCCACHE_BASEDIRS` 和实际路径一致，不会卡。

### 错误 13：错误地建议跳过 sccache
- **现象**：用户需要 sccache 为 Rust 和下次编译准备，我却因为 chroot 卡顿建议全去掉。
- **原因**：把“rustc 探测卡住”误判为“sccache 整体不可用”。
- **解决**：sccache 对 C/C++ 的缓存是正常工作的，卡住的只是 Rust 探测。正确做法是让 Rust 探测绕过 sccache，C 编译继续用缓存。

### 错误 14：`CONFIG_RUST` 被自动禁用
- **现象**：`CONFIG_RUSTC_VERSION=0`，Rust 支持没开。
- **原因**：`rustc -vV` 探测被 sccache 包装器卡住超时，`scripts/rust_is_available.sh` 判定工具链不可用，自动关掉 `CONFIG_RUST`。
- **解决**：下次编译前用 `/usr/bin/rustc --version` 确认原始 rustc 可用，再 `./scripts/config --enable RUST`，并让 rustc 探测不经过 sccache。

### 错误 15：`make install` 没生成 `vmlinuz-linux-mainline`
- **现象**：`/boot` 里只有 `vmlinuz-linux`，没有 `vmlinuz-linux-mainline`。
- **原因**：Arch 上 `make install` 的命名规则和预期不一致。
- **解决**：手动 `cp arch/x86/boot/bzImage /boot/vmlinuz-linux-mainline`，复制 `linux.preset` 为 `linux-mainline.preset` 并改路径，再 `mkinitcpio -P linux-mainline`。

### 错误 16：initramfs 222M 过大
- **现象**：`initramfs-linux-mainline.img` 有 222M，正常应 20~30M。
- **原因**：在 chroot 里跑 `mkinitcpio`，`autodetect` hook 看到的是 sda 的硬件，但模块在 sdb 的 `/lib/modules` 里，无法精简。
- **解决**：**不影响启动**。下次在 sdb 原生启动的环境里跑 `mkinitcpio -P linux-mainline`，initramfs 会自动缩回正常大小。

### 错误 17：`CONFIG_DRM_PANIC_SCREEN="qr_code"` 非法
- **现象**：`Unsupported value for CONFIG_DRM_PANIC_SCREEN ('qr_code'), falling back to 'user'`
- **原因**：`localmodconfig` 继承了一个旧值，当前内核不认。
- **解决**：`./scripts/config --set-str DRM_PANIC_SCREEN "user"` + `make olddefconfig`，增量编译后消失。

### 错误 18：`regulatory.db` 固件缺失
- **现象**：`Direct firmware load for regulatory.db failed with error -2`
- **原因**：未安装 `wireless-regdb`。
- **解决**：`pacman -S wireless-regdb`。

### 错误 19：所有 tarball 镜像返回错误页
- **现象**：`linux-7.4-rc1.tar.xz` 只有 146/153 字节。
- **原因**：RC 版本的 tarball 尚未同步到常规 `/v7.x/` 归档路径。
- **解决**：改用 **git 浅克隆** `--depth 1 --branch v7.4-rc1`，从清华 git 镜像拉源码树。

### 错误 20：`git clone` 的 annotated tag 警告
- **现象**：`warning: refs/tags/v7.4-rc1 ... is not a commit!`
- **原因**：annotated tag 指向一个 tag 对象，再指向 commit，这是正常现象。
- **解决**：无需处理，`git` 已自动 checkout 到正确 commit，`Updating files: 100% (97348/97348)` 就是证据。

### 错误 21：`reflector` 输出没有速度注释
- **现象**：`--save` 生成的 mirrorlist 只有 `Server =` 行，看不到测速数值。
- **原因**：`--save` 设计就是输出纯净列表，测速信息只打到 stderr。
- **解决**：测速结果看终端日志即可；如果希望文件里带速度注释，用 `reflector ... > mirrorlist`（不写 `--save`）。

### 错误 22：建议清理缓存（严重错误）
- **现象**：我建议 `pacman -Scc` 清理本地包缓存。
- **原因**：完全忽略了用户反复强调“缓存很难才配好、不要清”。
- **解决**：**永远不要动 `/var/cache/pacman/pkg`**。安装失败时用 `pacman -Sw` 只下载、`pacman -U` 本地安装，或 `curl` 直接下包到 `/tmp`。

### 错误 23：建议手动重定向（多余）
- **现象**：我建议用 `reflector ... > mirrorlist` 手动重定向。
- **原因**：`reflector --save` 本身就是自动保存并排序，不需要手动重定向。
- **解决**：直接用 `reflector --verbose --latest 10 --sort rate --save /etc/pacman.d/mirrorlist`。

### 错误 24：`pkill -9` 报“进程不存在”但 `/proc` 里能看到
- **现象**：新 SSH 会话里 `kill -9 <PID>` 报 `No such process`，但 `ls /proc/<PID>` 能看到进程。
- **原因**：新会话和原 tmux 会话的 PID namespace 或 `/proc` 视图不一致。
- **解决**：**回原 tmux 窗口按 `Ctrl+C`**，不要在另一个会话里远程杀。

### 错误 25：误判“不能裁剪内核”
- **现象**：我一开始说“不可能只编译需要的部分”。
- **原因**：忽略了 `localmodconfig` 和 `menuconfig` 可以关闭未用驱动。
- **解决**：`make localmodconfig` 可以大幅裁剪，但必须手动确认关键驱动（btrfs、磁盘控制器、网卡、输入设备）没被裁掉。

### 错误 26：`CONFIG_DRM_AMDGPU_SI/CIK/HSA` 未关，编译慢
- **现象**：amdgpu 编译持续十几二十分钟。
- **原因**：`localmodconfig` 保留了 SI（GFX6）、CIK（GFX7）、HSA（ROCm）等 Renoir 用不到的代际支持。
- **解决**：下次增量编译前 `./scripts/config --disable DRM_AMDGPU_SI --disable DRM_AMDGPU_CIK --disable DRM_AMD_DC_FP --disable DRM_AMD_DC_SI --disable HSA_AMD`。

---

## 四、经验教训

1. **编译绝不在 chroot 里做**：`autodetect` 失效导致 initramfs 膨胀，sccache 路径陷阱导致卡死。下次在 sdb 原生启动的系统里编。
2. **`localmodconfig` 之后必须用 `hwdetect --show-modules` 对照审计**，不能只 grep 几个关键项就放行。
3. **sccache 对 Rust 是原生支持**，通过 `RUSTC_WRAPPER`，不要因为 C 侧的一次卡顿就全盘否定。
4. **缓存目录永远不清**。安装失败时用 `pacman -Sw` + `pacman -U` 绕过仓库问题。
5. **`taskset -c 0-8 nice -n 19`** 是笔记本编译最实用的限速组合，比 `cpulimit` 和 `systemd-run` 都可靠。
6. **`/boot` 是 vfat，不能用符号链接**，内核和 initramfs 必须 `cp` 真实文件。
7. **Arch 上 `make install` 的命名不可靠**，手动 `cp` + 自定义 preset 更可控。

---

## 五、下周 7.4-rc2 操作预案

```bash
# 1. 在 sdb 原生启动的系统里（不是 chroot）
cd /root/code/7.4rc1

# 2. 浅克隆 rc2 源码
git clone --depth 1 --branch v7.4-rc2 https://mirrors.tuna.tsinghua.edu.cn/git/linux.git linux-7.4-rc2
cd linux-7.4-rc2

# 3. 基于 rc1 的 .config 起步（保留已验证的驱动）
cp ../linux-7.4-rc1/.config .config

# 4. 修掉 rc1 遗留的非法值，补上可移植性驱动
./scripts/config --set-str DRM_PANIC_SCREEN "user"
./scripts/config --module R8169
./scripts/config --module E1000E
./scripts/config --module IGB
./scripts/config --module EXFAT_FS
./scripts/config --module NTFS3_FS
make olddefconfig

# 5. 用 sdb 原生环境的 sccache（路径一致，不会卡 rustc 探测）
export SCCACHE_DIR=/var/cache/sccache
export SCCACHE_BASEDIRS="/root/code/7.4rc1"
export PATH="/usr/lib/sccache/bin:${PATH}"
export RUSTC_WRAPPER="sccache"

# 6. 确认 rustc 原始可用后再开 Rust
/usr/bin/rustc --version
./scripts/config --enable RUST
make olddefconfig
grep CONFIG_RUST .config

# 7. 编译（限核 + 低优先级）
taskset -c 0-8 nice -n 19 make -j9 LDFLAGS="-fuse-ld=mold" LOCALVERSION=-mainline

# 8. 安装（手动 cp + preset，不依赖 make install）
cp arch/x86/boot/bzImage /boot/vmlinuz-linux-mainline
cp System.map /boot/System.map-linux-mainline
mkinitcpio -P linux-mainline   # 这次在原生环境跑，initramfs 会缩回 20~30M
grub-mkconfig -o /boot/grub/grub.cfg

## 六、附录：脚本清单
脚本	用途
01_check_target_disk_sdb_from_sda.sh	在 sda 上只读检查 sdb 分区、fstab、mkinitcpio、Secure Boot
02_check_chroot_build_environment.sh	进 chroot 后检查 makepkg 配置、mold、磁盘空间
03_install_kernel_and_update_bootloader.sh	编译成功后安装内核、修 initramfs、更新 GRUB
04_monitor_system_during_compile.sh	编译期间监控负载、CPU、内存/OOM、温度、sccache
05_deep_hardware_scan_and_config_audit.sh	hwdetect 模块清单 + PCI/USB 驱动 + .config 审计
06_post_boot_hardware_acceptance_check.sh	新内核启动后验收网卡/蓝牙/存储/声卡/输入/显卡/驱动加载
## 七、当前硬件验收结果（7.4.0-rc1-mainline）
硬件	状态
有线网卡（ASIX AX88179 USB）	1000Mb/s 全双工，ax88179_178a 已加载
无线网卡（RTL8852AE）	rtw89_8852ae 已加载，rfkill 未阻止
蓝牙	btusb 已加载，hci0 存在
USB 移动硬盘（JMicron JMS567）	走 uas，5000M
NVMe（SK Hynix）	nvme 已加载，nvme0n1 识别
声卡（ALC257 + HDMI）	snd_hda_intel 已加载，aplay -l 列出 card 0/1
触摸板（SYNA2BA6）	i2c_hid + hid_multitouch 已加载
显卡（Renoir / Lucienne）	amdgpu 已加载
温度	32°C（空闲）

已知非致命警告：

    amdgpu psp gfx command LOAD_TA(0x1) failed：PSP 固件加载失败，不影响日常显示，下周 rc2 再看。

    GPT:Primary header thinks Alt. header is not at the end of the disk：sda 分区表备份头位置问题，不影响启动，可用 gdisk 修复。

    i8042: PS/2 appears to have AUX port disabled：现代笔记本触摸板走 I2C，正常。

报告结束。