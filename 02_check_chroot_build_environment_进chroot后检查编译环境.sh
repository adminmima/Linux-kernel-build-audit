#!/bin/bash
# 02_check_chroot_build_env.sh
# EN: Check the build environment inside the sdb chroot, as the non-root builder user.
#     Verifies makepkg options, mold, modprobed-db, loaded module count,
#     and BUILDDIR disk space.
# ZH: 进入 sdb 的 chroot 后，以非 root 的 builder 用户检查编译环境。
#     确认 makepkg 的 OPTIONS/LDFLAGS/BUILDDIR、mold 是否可用、
#     modprobed-db 是否安装、当前已加载模块数、BUILDDIR 所在分区空间。
echo "===== 1. 用户检查 ====="
[ "$(id -u)" -ne 0 ] && echo "[OK] 非root: $(whoami)" || echo "[FAIL] 必须切到builder"
echo -e "\n===== 2. makepkg 关键配置 ====="
grep -E '^(OPTIONS|LDFLAGS|BUILDDIR|PKGEXT)' /etc/makepkg.conf
echo -e "\n===== 3. mold 可用性 ====="
command -v mold &>/dev/null && echo "[OK] mold" || echo "[缺] pacman -S mold"
echo -e "\n===== 4. modprobed-db（可选，比裸localmodconfig更准）====="
command -v modprobed-db &>/dev/null && echo "[OK]" || echo "[缺] 可选安装"
echo -e "\n===== 5. 当前加载模块数（裁剪基线）====="
lsmod | wc -l
echo -e "\n===== 6. BUILDDIR 所在分区空间 ====="
df -h / /boot /efi 2>/dev/null | grep -v tmpfs
