## rc3 交接报告初稿



# Linux 7.4-rc3 交接报告（从 rc2 到 rc3）

- 日期：2026-11-12
- 上一版：`handover_2026-11-06_linux-7.4rc1.md`（已作废，见"过时断言"节）
- 本文目的：让下一个接手的人（或未来的你）能在**不重踩 rc1/rc2 的坑**的前提下，
  完成 7.4-rc3 的编译、部署、启动验证
- 阅读顺序：先看"一、环境事实"→"四、编译命令模板"→"五、部署步骤"→"六、验证清单"，
  遇到问题再查"七、已知坑清单"

---

## 一、环境事实（2026-11-12 确认）

### 1.1 磁盘布局

| 设备 | 文件系统 | 标签 | UUID | 挂载点（sda 视角） | 用途 |
|---|---|---|---|---|---|
| `/dev/sda3` | btrfs | — | — | `/` | sda 日常系统（7.2.14-arch1-1） |
| `/dev/sdb1` | vfat FAT16 | `kernel` | `1234-ABCD` | 未挂载 | 用途不明，**不要动** |
| `/dev/sdb2` | ext4 | `rootfs` | `ff313567-...` | 未挂载 | 用途不明，**不要动** |
| `/dev/sdb3` | vfat FAT32 | — | `96DA-48BB` | `/run/media/root/ARCH-ROOT/efi`（按需挂载） | **ESP**，GRUB 的 `BOOTX64.EFI` 在这 |
| `/dev/sdb4` | btrfs | `ARCH-ROOT` | `73ccb201-973d-4772-b09f-b1be308458f0` | `/run/media/root/ARCH-ROOT` | sdb 根分区，55.7G 可用 |
| `/dev/sdb128` | — | — | — | — | 可能是 GPT 备份头，**不要动** |

**sdb 上另有 sda 的镜像？** 不，sda/sdb 是两块独立盘。sda 通过 USB 转 SATA 接 Samsung 750 EVO 120G，sdb 是 Kston 128GB（也走 USB）。

### 1.2 启动方式

- **UEFI**，Secure Boot **关闭**（efivars 最后字节 `0`）
- ESP：`/dev/sdb3`，fstab 挂载点 `/efi`，`UUID=96DA-48BB vfat defaults,umask=0077 0 2`
- GRUB 的 EFI 文件：`/efi/EFI/BOOT/BOOTX64.EFI`（**已确认是 GRUB**，`strings` 含 `grub_efidisk_*` 函数名）
- **没有** `/efi/EFI/GRUB/` 或 `/efi/EFI/Arch/` 目录，GRUB 走 UEFI 回退路径
- `efibootmgr` 显示当前从 `Boot0002`（USB Samsung 750 EVO 120G）启动，路径 `\EFI\BOOT\BOOTX64.EFI`

### 1.3 GRUB 配置

- `GRUB_DEFAULT=0`，指向第一个 `menuentry 'Arch Linux'`
- `GRUB_TIMEOUT=5`，`GRUB_TIMEOUT_STYLE=menu`
- `GRUB_DISTRIBUTOR="Arch"`
- `GRUB_CMDLINE_LINUX_DEFAULT="loglevel=3 quiet"`，`GRUB_CMDLINE_LINUX=""`
- `grub.cfg` 里三条启动路径：
  1. `Arch Linux`（默认，`GRUB_DEFAULT=0`）→ `vmlinuz-linux-mainline` + `initramfs-linux-mainline.img`
  2. `Advanced > Arch Linux, with Linux linux-mainline` → 同上
  3. **`Advanced > Arch Linux, with Linux linux`** → `vmlinuz-linux` + `initramfs-linux.img`（**回退路径**，sdb 自带 7.2.14）

### 1.4 mkinitcpio

- `/etc/mkinitcpio.conf`：`MODULES=(btrfs)`，`HOOKS=(base systemd autodetect microcode modconf kms keyboard sd-vconsole block filesystems fsck)`
- preset：`/etc/mkinitcpio.d/linux-mainline.preset`
  - `ALL_kver="/boot/vmlinuz-linux-mainline"`
  - `default_image="/boot/initramfs-linux-mainline.img"`
  - `PRESETS=('default')`

### 1.5 工具链（sda 与 sdb 的版本一致）

| 工具 | 版本 | 路径 |
|---|---|---|
| gcc | 16.2.1 20260810 | `/usr/bin/gcc`（sda/sdb 同 sha256） |
| mold | 3.0.0 | `/usr/bin/mold`，`/usr/bin/ld.mold -> mold` |
| GNU ld | 2.47 | `/usr/bin/ld`（**内核链接用这个**） |
| sccache | 0.19.0 | `/usr/bin/sccache`，sda/sdb 同版本 |
| arch-chroot | — | `/usr/bin/arch-chroot` |

### 1.6 sccache 缓存

- 位置：`/var/cache/sccache`（chroot 内视角）= `/run/media/root/ARCH-ROOT/var/cache/sccache`（sda 视角）
- 大小：**1.1G**（rc1 遗留 782M + rc2 新增约 300M）
- 权限：`drwxr-x--- root root`，chroot 内 root 可读写
- **rc3 直接复用**，不要清

### 1.7 备份

- 位置：`/root/backup_20261112_7.4rc1_to_rc2_部署前备份/`
- 大小：249M
- 内容：
  - `boot_引导文件备份/`：rc1 的 `vmlinuz-linux-mainline`、`System.map-linux-mainline`、`initramfs-linux-mainline.img`
  - `grub_引导配置备份/`：rc1 的 `grub.cfg`
  - `mkinitcpio_preset_预设备份/`：`linux-mainline.preset`

### 1.8 当前内核状态

- **rc1**：`7.4.0-rc1-mainline`，已启动验证，硬件验收通过（见 `post_boot_report_20261106_0813.txt`）
- **rc2**：`7.4.0-rc2-mainline`，编译成功、部署完成、六项验证通过，**启动验证待明天完成**
- **sdb 自带**：`7.2.14-arch1-1`，`vmlinuz-linux` + `initramfs-linux.img`，作为回退路径

---

## 二、rc1 → rc2 的关键变化

### 2.1 配置调整（rc2 已做，rc3 继承）

| 项 | rc1 | rc2 | 原因 |
|---|---|---|---|
| `DRM_AMDGPU_SI` | `y` | **`n`** | Renoir 用不到 GFX6 |
| `DRM_AMDGPU_CIK` | `y` | **`n`** | Renoir 用不到 GFX7 |
| `DRM_AMD_DC_SI` | `y` | **整行消失** | 依赖 `DRM_AMDGPU_SI`，已关 |
| `HSA_AMD` | `y` | **`n`** | Renoir 不用 ROCm |
| `HSA_AMD_SVM` / `HSA_AMD_P2P` | `y` | **整行消失** | 依赖 `HSA_AMD` |
| `NTFS3_FS` | `n` | **`m`** | 可移植性 |
| `EXFAT_FS` | `n` | **`m`** | 可移植性 |
| `R8169` / `E1000E` / `IGB` | `n` | **`m`** | 常见有线网卡 |
| `DRM_AMD_DC_FP` | `y` | **`y`（关不掉）** | 被 `display/Kconfig:15` 的 `select` 强制拉回 |
| `DRM_PANIC_SCREEN` | `"qr_code"`（非法） | **`"user"`** | 合法值 |
| `CONFIG_RUST` | 整行不存在 | 整行不存在 | 未启用，不需要 bindgen |

**rc3 直接继承 rc2 的 `.config`，不需要重新调整。**

### 2.2 编译方案的变化（核心）

| 项 | rc1（错误） | rc2（正确） |
|---|---|---|
| 链接器 | `LDFLAGS="-fuse-ld=mold"`（**无效**，实际 GNU ld） | **不 wrapper ld**，直接用 `/usr/bin/ld`（GNU ld 2.47） |
| gcc | 普通 gcc | **`/usr/local/bin/gcc` wrapper**：探测参数透传真 gcc，编译参数走 `sccache /usr/bin/gcc` |
| sccache | `PATH=/usr/lib/sccache/bin:$PATH`（**递归死锁**） | 只在 wrapper 里显式调 `sccache`，PATH 不含 shim |
| `TMPDIR` | 默认 `/tmp`（**tmpfs 叠加，`cc*.s` 读不到**） | **`TMPDIR=/var/tmp`**（btrfs，持久） |
| rustc 探测 | `RUSTC_WRAPPER=sccache`（**递归**） | `CONFIG_RUST` 不存在，`Makefile:744` 的 `$(shell rustc --version)` 返回空，不触发 |
| 日志 | 无持久日志 | `/root/code/7.4rc1/build-*.log`（持久路径，chroot 退出可读） |
| 限核 | `taskset -c 0-8 nice -n 19` | **同左**（正确） |

### 2.3 部署方案的变化

| 项 | rc1 | rc2 |
|---|---|---|
| `mkinitcpio` | `mkinitcpio -P linux-mainline`（**`-P` 处理所有 preset**） | **`mkinitcpio -p linux-mainline`**（小写，只处理指定 preset） |
| 备份 | 无 | **部署前备份到 `backup_20261112_.../`** |
| ESP 挂载 | 未明确记录 | **部署前 `mount /dev/sdb3 /efi`，部署后 `umount`** |
| 验证 | 启动后 `uname` | **六项验证清单**（见第六节） |

---

## 三、编译命令模板（rc3 直接用）

### 3.1 前置：确保 gcc wrapper 存在

```bash
# 检查 wrapper
ls -l /run/media/root/ARCH-ROOT/usr/local/bin/gcc
# 若不存在，创建：
cat > /run/media/root/ARCH-ROOT/usr/local/bin/gcc <<'EOF'
#!/bin/bash
case " $* " in
    *" -Wa,--version "*|*" -x assembler-with-cpp "*)
        exec /usr/bin/gcc "$@"
        ;;
esac
exec /usr/bin/sccache /usr/bin/gcc "$@"
EOF
chmod +x /run/media/root/ARCH-ROOT/usr/local/bin/gcc

# 确认 /usr/local/bin/ld 不存在（只用 GNU ld）
ls /run/media/root/ARCH-ROOT/usr/local/bin/ld 2>&1 || echo "ld wrapper 不存在（正确）"
```

### 3.2 清场：杀 sccache + 清叠加 tmpfs

```bash
pkill -9 -x sccache 2>/dev/null
pkill -9 -f 'make -j9' 2>/dev/null
pkill -9 -f 'arch-chroot' 2>/dev/null
sleep 2
while findmnt -t tmpfs /run/media/root/ARCH-ROOT/tmp >/dev/null 2>&1; do
    umount -l /run/media/root/ARCH-ROOT/tmp 2>/dev/null || break
    sleep 1
done
```

### 3.3 拉 rc3 源码（增量，不重新 clone）

```bash
cd /run/media/root/ARCH-ROOT/root/code/7.4rc1/linux-7.4-rc1
git fetch --depth 1 https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git \
    refs/tags/v7.4-rc3:refs/tags/v7.4-rc3
git checkout v7.4-rc3
head -5 Makefile   # 确认 EXTRAVERSION = -rc3
git status --short --branch   # 应干净
```

**若 kernel.org 慢，用清华**：
```bash
git fetch --depth 1 origin refs/tags/v7.4-rc3:refs/tags/v7.4-rc3
```

### 3.4 配置：继承 rc2，olddefconfig

```bash
cd /run/media/root/ARCH-ROOT/root/code/7.4rc1/linux-7.4-rc1
cp .config .config.rc2-backup-$(date +%Y%m%d_%H%M%S)
make olddefconfig
```

**验证关键项**（应与 rc2 一致）：
```bash
grep -E '^CONFIG_(LOCALVERSION|BTRFS_FS|NTFS3_FS|EXFAT_FS|R8169|E1000E|IGB|DRM_AMD_DC_FP|DRM_PANIC_SCREEN)=' .config
grep -E '# CONFIG_(DRM_AMDGPU_SI|DRM_AMDGPU_CIK|HSA_AMD) is not set' .config
```

### 3.5 编译（一个 chroot 会话内完成）

```bash
arch-chroot /run/media/root/ARCH-ROOT bash -c '
set -e
export PATH=/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export SCCACHE_DIR=/var/cache/sccache
export TMPDIR=/var/tmp
mkdir -p /var/tmp
cd /root/code/7.4rc1/linux-7.4-rc1

# 先用普通 gcc 跑 prepare（避免 syncconfig 在 sccache 下探测汇编器失败）
make prepare

# 再编（auto.conf 已比 .config 新，syncconfig 不重跑）
taskset -c 0-8 nice -n 19 make -j9 LOCALVERSION=-mainline \
    > /root/code/7.4rc1/build-rc3-$(date +%Y%m%d_%H%M).log 2>&1
echo "exit=$?"
'
```

**关键参数**：

| 参数 | 作用 |
|---|---|
| `PATH=/usr/local/bin:...` | gcc 走 wrapper，ld 走 `/usr/sbin/ld`（GNU ld） |
| `SCCACHE_DIR=/var/cache/sccache` | 1.1G 缓存 |
| `TMPDIR=/var/tmp` | 避开 chroot 的 `/tmp` tmpfs |
| `taskset -c 0-8` | 9 核，留 3 核给系统 |
| `nice -n 19` | 最低优先级 |
| `-j9` | 与 9 核匹配 |
| `LOCALVERSION=-mainline` | 内核版本后缀 |

**预期**：
- sccache 命中率比 rc2 高（rc2→rc3 变更文件更少）
- 若 rc3 变更文件少（rc 阶段通常比 merge window 小），编译时间 15–45 分钟

### 3.6 编译完成后验证

```bash
cd /run/media/root/ARCH-ROOT/root/code/7.4rc1/linux-7.4-rc1
ls -lh arch/x86/boot/bzImage vmlinux System.map
strings arch/x86/boot/bzImage | grep -m1 '7\.4\.0-rc3-mainline'
SCCACHE_DIR=/run/media/root/ARCH-ROOT/var/cache/sccache \
    /run/media/root/ARCH-ROOT/usr/bin/sccache --show-stats | \
    grep -E 'Compile requests|Cache hits|Cache misses|Compilations'
```

---

## 四、部署步骤（覆盖式，rc2 已验证）

### 4.1 前置：备份（rc3 部署前再做一次）

```bash
BK=/run/media/root/ARCH-ROOT/root/backup_$(date +%Y%m%d)_7.4rc2_to_rc3_部署前备份
mkdir -p "$BK/boot_引导文件备份" "$BK/grub_引导配置备份" "$BK/mkinitcpio_preset_预设备份"
cp -av /run/media/root/ARCH-ROOT/boot/vmlinuz-linux-mainline \
       /run/media/root/ARCH-ROOT/boot/System.map-linux-mainline \
       /run/media/root/ARCH-ROOT/boot/initramfs-linux-mainline.img \
       "$BK/boot_引导文件备份/"
cp -av /run/media/root/ARCH-ROOT/boot/grub/grub.cfg "$BK/grub_引导配置备份/"
cp -av /run/media/root/ARCH-ROOT/etc/mkinitcpio.d/linux-mainline.preset \
       "$BK/mkinitcpio_preset_预设备份/"
du -sh "$BK"
```

### 4.2 挂 ESP

```bash
mount /dev/sdb3 /run/media/root/ARCH-ROOT/efi
findmnt -T /run/media/root/ARCH-ROOT/efi
```

**预期**：`/dev/sdb3 vfat`。

### 4.3 装模块 + 拷内核

```bash
arch-chroot /run/media/root/ARCH-ROOT bash -c '
set -e
export TMPDIR=/var/tmp
cd /root/code/7.4rc1/linux-7.4-rc1
make modules_install 2>&1 | tail -5
cp -v arch/x86/boot/bzImage /boot/vmlinuz-linux-mainline
cp -v System.map /boot/System.map-linux-mainline
'
```

**成功标志**：`DEPMOD /lib/modules/7.4.0-rc3-mainline`，两条 `cp -v` 输出。

### 4.4 生成 initramfs（**`-p` 小写**）

```bash
arch-chroot /run/media/root/ARCH-ROOT bash -c '
set -e
export TMPDIR=/var/tmp
mkinitcpio -p linux-mainline 2>&1 | tail -12
'
```

**成功标志**：最后一行 `==> Image generation successful`。

**预期大小**：约 **204M**（chroot 里 `autodetect` 看到 sda 硬件，不会缩回 20–30M，不影响启动）。

### 4.5 更新 GRUB

```bash
arch-chroot /run/media/root/ARCH-ROOT bash -c '
set -e
grub-mkconfig -o /boot/grub/grub.cfg 2>&1 | tail -15
'
```

**成功标志**：输出含 `Found linux image: /boot/vmlinuz-linux-mainline`、`Found initrd image: /boot/initramfs-linux-mainline.img`，最后 `done`。

**输出尾部可能被 EFI BootNext 条目淹没，不要依赖尾部，直接查 `grub.cfg` 验证**（见第六节）。

### 4.6 卸载 ESP

```bash
umount /run/media/root/ARCH-ROOT/efi
findmnt -T /run/media/root/ARCH-ROOT/efi   # 应显示 btrfs
```

---

## 五、验证清单（六项全对才重启）

| # | 检查项 | 命令 | 预期 |
|---|---|---|---|
| 1 | 新内核文件 | `ls -lh /boot/vmlinuz-linux-mainline` | 15M，mtime 刚才 |
| 2 | 新 initramfs | `ls -lh /boot/initramfs-linux-mainline.img` | 约 204M，mtime 刚才 |
| 3 | 模块目录 | `ls -d /usr/lib/modules/7.4.0-rc3-mainline` | 存在 |
| 4 | 默认项指向新内核 | `grep -A15 "menuentry 'Arch Linux'" grub.cfg \| grep vmlinuz` | `vmlinuz-linux-mainline` |
| 5 | **回退项存在** | `grep -nE "menuentry 'Arch Linux, with Linux linux'" grub.cfg` | 有输出，且含 `linux /boot/vmlinuz-linux` |
| 6 | Secure Boot 关闭 | `od -An -t u1 /sys/firmware/efi/efivars/SecureBoot-*` | 最后字节 `0` |

**验证命令（一次跑完）**：
```bash
echo "===== [1] 新内核 ====="
ls -lh --time-style=+%H:%M /run/media/root/ARCH-ROOT/boot/vmlinuz-linux-mainline
echo "===== [2] 新 initramfs ====="
ls -lh --time-style=+%H:%M /run/media/root/ARCH-ROOT/boot/initramfs-linux-mainline.img
echo "===== [3] 模块目录 ====="
ls -d /run/media/root/ARCH-ROOT/usr/lib/modules/7.4.0-rc3-mainline
echo "===== [4] 默认项 ====="
grep -A15 "menuentry 'Arch Linux'" /run/media/root/ARCH-ROOT/boot/grub/grub.cfg | grep vmlinuz
echo "===== [5] 回退项 ====="
grep -nE "menuentry 'Arch Linux, with Linux linux'|linux[[:space:]]+/boot/vmlinuz-linux[[:space:]]" /run/media/root/ARCH-ROOT/boot/grub/grub.cfg
echo "===== [6] Secure Boot ====="
od -An -t u1 /sys/firmware/efi/efivars/SecureBoot-* 2>&1 | tail -1
```

**六项全对，才 `reboot`。任一不对，停，修。**

---

## 六、启动后验收

### 6.1 基础验收

```bash
uname -r
# 预期：7.4.0-rc3-mainline

dmesg | grep -iE 'error|fail' | head -20
# 预期：无致命错误。rc1 已知的 amdgpu psp 警告可能仍在，不影响

ip link show | head -10
# 预期：网卡起来
```

### 6.2 硬件验收（用 rc1 的 `06_post_boot_hardware_acceptance_check.sh`）

```bash
bash /root/code/7.4rc1/06_post_boot_hardware_acceptance_check_启动后硬件验收.sh
```

**验收基线**（rc1 数据，rc3 应不低于此）：

| 硬件 | rc1 状态 |
|---|---|
| 有线网卡（ASIX AX88179 USB） | 1000Mb/s 全双工，`ax88179_178a` 已加载 |
| 无线网卡（RTL8852AE） | `rtw89_8852ae` 已加载，rfkill 未阻止 |
| 蓝牙 | `btusb` 已加载，hci0 存在 |
| USB 移动硬盘（JMicron JMS567） | 走 `uas`，5000M |
| NVMe（SK Hynix） | `nvme` 已加载，nvme0n1 识别 |
| 声卡（ALC257 + HDMI） | `snd_hda_intel` 已加载，aplay -l 列出 card 0/1 |
| 触摸板（SYNA2BA6） | `i2c_hid` + `hid_multitouch` 已加载 |
| 显卡（Renoir / Lucienne） | `amdgpu` 已加载 |
| 温度 | 32°C（空闲） |

**rc1 已知非致命警告**（rc3 可能仍在）：
- `amdgpu psp gfx command LOAD_TA(0x1) failed`：PSP 固件加载失败，不影响日常显示
- `GPT:Primary header thinks Alt. header is not at the end of the disk`：sda 分区表备份头位置问题，不影响启动
- `i8042: PS/2 appears to have AUX port disabled`：现代笔记本触摸板走 I2C，正常

### 6.3 若 rc2/rc3 启动失败

1. 重启 → GRUB → `Advanced options for Arch Linux` → `Arch Linux, with Linux linux`（sdb 自带 7.2.14）
2. 进系统后，用备份恢复：
   ```bash
   BK=/run/media/root/ARCH-ROOT/root/backup_<日期>_..._部署前备份
   cp "$BK/boot_引导文件备份/vmlinuz-linux-mainline" /run/media/root/ARCH-ROOT/boot/
   cp "$BK/boot_引导文件备份/System.map-linux-mainline" /run/media/root/ARCH-ROOT/boot/
   cp "$BK/boot_引导文件备份/initramfs-linux-mainline.img" /run/media/root/ARCH-ROOT/boot/
   cp "$BK/grub_引导配置备份/grub.cfg" /run/media/root/ARCH-ROOT/boot/grub/
   ```
3. 贴回错误信息

---

## 七、已知坑清单（rc3 直接复用）

### 7.1 编译阶段

| # | 坑 | 现象 | 正确做法 |
|---|---|---|---|
| 1 | `LDFLAGS="-fuse-ld=mold"` **无效** | rc1 以为用了 mold，实际 GNU ld | 不要写 `LDFLAGS`，ld 不 wrapper，直接用 `/usr/bin/ld` |
| 2 | mold **不能链接内核** | `mold: fatal: SECTIONS unknown linker script token`、`unknown command line option: --no-warn-rwx-segments` | 内核链接用 GNU ld，mold 只用于用户态 |
| 3 | sccache shim **自递归** | `PATH=/usr/lib/sccache/bin:$PATH`，`rustc -vV` 卡死 | 不用 shim，用 gcc wrapper 显式调 `sccache` |
| 4 | `CC="sccache gcc"` **触发 syncconfig 死循环** | `auto.conf.cmd` 检测 `CC` 字面量变了，重跑 syncconfig，sccache 探测汇编器失败 | `CC` 字面量保持 `gcc`，用 PATH 前置 wrapper |
| 5 | chroot 的 `/tmp` 是 **tmpfs，会叠加** | `can't open /tmp/cc*.s`，文件存在但读不到 | `TMPDIR=/var/tmp` |
| 6 | sccache server 在 **host 命名空间** | `cd /root/code/...` 在 host 不存在，spawn 失败 | 先 `pkill -9 -x sccache`，再 chroot 内启动 |
| 7 | `mkinitcpio -P` **处理所有 preset** | 不只生成目标内核的 initramfs | 用 `-p linux-mainline`（小写） |
| 8 | `Kconfig select` **撤销 `--disable`** | `DRM_AMD_DC_FP` 关不掉 | `olddefconfig` 后再 grep 确认实际值 |

### 7.2 部署阶段

| # | 坑 | 现象 | 正确做法 |
|---|---|---|---|
| 9 | `grub-mkconfig` 输出被 **EFI BootNext 淹没** | `tail` 看不到 `Found linux image` | 直接 grep `grub.cfg` 验证 |
| 10 | `vmlinuz-linux` 的 mtime 是旧值 | 正常，包管理器没更新内核二进制 | 只看存在性，不看 mtime |
| 11 | ESP **未挂载**就 `grub-mkconfig` | UEFI 模式下可能警告 | 先 `mount /dev/sdb3 /efi`，部署后 `umount` |
| 12 | grep 模式写错 → **误判"不存在"** | `grep "vmlinuz-linux'"` 匹配不到（实际是空格分隔） | 用 `grep -E "linux[[:space:]]+/boot/vmlinuz-linux[[:space:]]"` |

### 7.3 流程原则

| # | 原则 | 说明 |
|---|---|---|
| 13 | **信息不完整之前，不写后续步骤** | 没查清就写步骤，基于错误信息做决策 |
| 14 | **批量查询，不挤牙膏** | 同一主题 5–8 条命令一批，一次贴回 |
| 15 | **单一事实来源** | 同一信息只存一处，引用用关键词不用编号 |
| 16 | **每步验证、每步可回退** | 部署步骤每步有成功标志、失败处理、回退动作 |
| 17 | **root 编译能不用就不用** | `make` 不需要 root，只有 `modules_install`/`mkinitcpio`/`grub-mkconfig`/`cp 到 /boot` 需要 |

---

## 八、过时断言（rc1 报告中已被 rc2 证伪，不要照抄）

| rc1 报告断言 | rc2 实际 |
|---|---|
| "编译不要放 chroot 里" | **可以放 chroot**，条件是 sccache server 命名空间正确 + `TMPDIR=/var/tmp` + PATH 干净 |
| `LDFLAGS="-fuse-ld=mold"` | **无效命令**，rc1 实际用 GNU ld；mold 不能链接内核 |
| "在 sdb 原生启动后跑 mkinitcpio 会缩回 20~30M" | rc2 仍在 chroot 跑，initramfs **204M**，不影响启动 |
| "sccache 对 Rust 是原生支持，用 `RUSTC_WRAPPER`" | rc2 证明 **`RUSTC_WRAPPER=sccache` 会递归**，`CONFIG_RUST` 未启用时不需要 |
| "下次用 `PATH=/usr/lib/sccache/bin:$PATH`" | **会递归死锁**，不要用 |

**rc1 的 `execution_report` 已加修正标注，rc3 以本文为准。**

---

## 九、附录

### 9.1 脚本清单（`/root/code/7.4rc1/`）

| 脚本 | 用途 |
|---|---|
| `01_check_target_disk_sdb_from_sda_在sda上只读检查sdb.sh` | 只读检查 sdb |
| `02_check_chroot_build_environment_进chroot后检查编译环境.sh` | chroot 内检查 |
| `03_install_kernel_and_update_bootloader_安装内核并更新引导.sh` | **rc1 旧脚本，参考但不照抄**（`makepkg -si` 不适用于本方案） |
| `04_monitor_system_during_compile_编译期间系统监控.sh` | 编译监控 |
| `05_deep_hardware_scan_and_config_audit_硬件深度扫描.sh` | 硬件扫描 |
| `06_post_boot_hardware_acceptance_check_启动后硬件验收.sh` | **启动后验收**，rc3 直接用 |

### 9.2 文档清单（`/root/code/7.4rc1/`）

| 文件 | 内容 |
|---|---|
| `README.md` | 项目说明（**关键经验第 1 条"编译不要在 chroot"已过时**） |
| `7.4-rc2_增量编译_过程经验教训.md` | rc2 全过程教训，37 节 |
| `7.4-rc2_编译_sccache探索过程记录与教训_补充篇.md` | sccache 早期探索 |
| `execution_report_2026-11-06_linux-7.4rc1_build_and_boot.md` | rc1 报告（**已加修正标注**） |
| `post_boot_report_20261106_0813.txt` | rc1 启动后硬件验收 |
| `hwdetect_rc1_working.txt` | rc1 硬件模块基线 |
| `build-rc2-*.log` | rc2 编译日志（**已被 `.gitignore` 排除**） |

### 9.3 关键路径速查

| 项 | 路径 |
|---|---|
| sdb 根分区 | `/run/media/root/ARCH-ROOT` |
| sdb 源码 | `/run/media/root/ARCH-ROOT/root/code/7.4rc1/linux-7.4-rc1` |
| chroot 内源码 | `/root/code/7.4rc1/linux-7.4-rc1` |
| sccache 缓存（sda 视角） | `/run/media/root/ARCH-ROOT/var/cache/sccache` |
| sccache 缓存（chroot 内） | `/var/cache/sccache` |
| sdb `/boot` | `/run/media/root/ARCH-ROOT/boot` |
| ESP | `/dev/sdb3`，挂载点 `/efi`（按需） |
| 备份 | `/run/media/root/ARCH-ROOT/root/backup_*` |
| rc2 编译日志 | `/run/media/root/ARCH-ROOT/root/code/7.4rc1/build-rc2-*.log` |

### 9.4 rc3 待填（明天重启后补）

- [ ] rc2 启动后 `uname -r`（预期 `7.4.0-rc2-mainline`）
- [ ] rc2 启动后 `dmesg | grep -iE 'error|fail'`
- [ ] rc2 硬件验收报告（`post_boot_report_20261112_*.txt`）
- [ ] rc2 initramfs 是否在原生环境缩回 20–30M（可选）
- [ ] rc3 编译实际耗时、sccache 命中率（编译后填）

---

**报告结束。rc3 按"三、编译命令模板"→"四、部署步骤"→"五、验证清单"执行。遇到问题查"七、已知坑清单"。**

---

## 说明：这份报告与你已有文档的关系

| 本文节 | 来源 | 不重复的内容 |
|---|---|---|
| 一、环境事实 | 你的 [A]–[G] 查询结果 | 不重复 rc1 报告里的环境表 |
| 二、关键变化 | rc2 教训文件第二至六节 | 不重复逐条教训 |
| 三、编译命令 | 教训文件第十六节 + 十七至三十节 | 不重复踩坑过程 |
| 四、部署步骤 | 教训文件第二十一、二十九、三十、三十一、三十二、三十三节 | 不重复每步回退命令的详细解释 |
| 五、验证清单 | 教训文件第三十二、三十三节 | — |
| 六、启动验收 | `06_*` 脚本 + `post_boot_report_20261106_0813.txt` | 不重复脚本源码 |
| 七、已知坑 | 教训文件全部标题的提炼 | 不重复每条教训的"现象/根因"细节 |
| 八、过时断言 | `execution_report` 修正标注 + 教训文件第十五节 | — |

**教训文件 1247 行是"过程"，本报告约 400 行是"结论"。rc3 读本报告即可，需要细节再查教训文件对应节。**

---
---

交接报告：有 4 处是"基于推理写的，未实测"，明天需要确认

报告已存，但下面这些点是没实测过、凭逻辑推的，明天 rc2 启动后或 rc3 编译前要验证：
待确认 1：v7.4-rc3 tag 是否存在、名字是否准确

报告 3.3 节写 refs/tags/v7.4-rc3:refs/tags/v7.4-rc3。我没查过 rc3 是否已发布、tag 名是否就是 v7.4-rc3。rc2 是 v7.4-rc2，rc3 大概率同格式，但未验证。

明天/rc3 前先跑：
```bash
git ls-remote --tags https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git 'v7.4-rc3'
```

无输出 = tag 不存在，rc3 还没发，报告 3.3 节整节作废，等 tag 出来再改。
待确认 2：make prepare 在 wrapper PATH 下的行为

报告 3.5 节：
```bash
export PATH=/usr/local/bin:...
make prepare
taskset ... make -j9 ...
```

make prepare 时 PATH 已含 wrapper。如果 prepare 触发 syncconfig，它会用 wrapper 的 gcc 探测汇编器。wrapper 对 -Wa,--version 和 -x assembler-with-cpp 透传真 gcc，逻辑上能过，但 rc2 当时是先用普通 gcc 跑 make syncconfig 再编译，没在 wrapper PATH 下跑过 make prepare。

明天 rc3 编译时，如果 make prepare 报 unknown assembler，改成分两步：
```bash
# 先用普通 PATH 跑 syncconfig
arch-chroot ... bash -c 'cd ...; make syncconfig'
# 再在 wrapper PATH 下编译
arch-chroot ... bash -c 'export PATH=/usr/local/bin:...; make -j9 ...'
```

报告里应加一句"若 prepare 失败，拆两步"，明天实测后补。
待确认 3：wrapper 的探测参数覆盖是否完整

报告 3.1 节的 wrapper 只对两种参数透传真 gcc：
```bash
*" -Wa,--version "*|*" -x assembler-with-cpp "*)
    exec /usr/bin/gcc "$@"
```

没处理：-dumpversion、-dumpmachine、-print-*、--help 等探测参数。rc2 的 Makefile 恰好没触发这些（或触发了但 sccache 能透传），rc3 若 Makefile 加了新的探测参数，可能失败。

明天编译时若报奇怪的 gcc 探测错误，先 bash -x /usr/local/bin/gcc --dumpversion 看 wrapper 走了哪个分支，再决定是否补参数。
待确认 4：rc3 变更规模、编译耗时

报告 2.2 节末尾、3.5 节末尾写了"rc2→rc3 变更文件更少""15–45 分钟"，纯推测。rc 阶段通常比 merge window 小，但 rc3 具体多少没数据。

明天 rc3 拉下来后先跑：
```bash
git diff --stat v7.4-rc2 v7.4-rc3 | tail -3
git diff --name-only v7.4-rc2 v7.4-rc3 | sed 's/.*\.//' | sort | uniq -c | sort -rn | head
```

把实际变更规模填进报告，替换"推测"。
3. 补充：报告里可以加一节"rc3 增量起点"（可选）

现有报告没有明确写"rc3 从哪里增量"。可以加一句在 3.3 节后：
```markdown
### 3.3.1 rc3 增量起点
```

- `.config`：继承 rc2 的，`make olddefconfig` 后 grep 确认关键项不变
- `.o`：rc2 的 5628 个 `.o` **保留**，不 `make clean`
- sccache 缓存：1.1G，`SCCACHE_DIR=/var/cache/sccache` 指过去
- 备份：rc3 部署前再做一次 `backup_<日期>_7.4rc2_to_rc3_部署前备份`