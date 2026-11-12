#!/bin/bash
# 01_check_sdb_target_disk.sh
# EN: Read-only check of the target sdb disk from the running sda system.
#     Verifies partition identity, fstab mount points, mkinitcpio MODULES/HOOKS,
#     Secure Boot tooling, boot directory layout, and free space.
#     Does NOT modify sda or sdb.
# ZH: 在当前运行的 sda 系统上，只读检查目标 sdb 磁盘。
#     确认分区身份、fstab 挂载点、mkinitcpio 的 MODULES/HOOKS、
#     Secure Boot 工具、/boot 目录结构、剩余空间。
#     不修改 sda，也不修改 sdb，纯只读。
SDB_ROOT="/dev/sdb4"; SDB_ESP="/dev/sdb3"
echo "===== 1. 目标盘身份 ====="
lsblk -o NAME,SIZE,FSTYPE,LABEL,UUID "$SDB_ROOT" "$SDB_ESP" 2>/dev/null
echo -e "\n===== 2. 只读挂载 sdb 根 ====="
mkdir -p /mnt/sdb_check
mount -o ro "$SDB_ROOT" /mnt/sdb_check || { echo "[FAIL] 挂载失败"; exit 1; }
echo -e "\n===== 3. sdb fstab（ESP挂载点）====="
cat /mnt/sdb_check/etc/fstab
echo -e "\n===== 4. sdb mkinitcpio MODULES / HOOKS ====="
grep -E '^(MODULES|HOOKS)' /mnt/sdb_check/etc/mkinitcpio.conf
echo -e "\n===== 5. sdb 是否装 sbctl（Secure Boot）====="
[ -x /mnt/sdb_check/usr/bin/sbctl ] && echo "[有] 进chroot后跑 sbctl status" || echo "[无] 若固件开SecureBoot需处理"
echo -e "\n===== 6. sdb boot 目录结构 ====="
ls /mnt/sdb_check/boot/ 2>/dev/null | head -20
echo -e "\n===== 7. sdb 剩余空间 ====="
df -h /mnt/sdb_check
echo -e "\n===== 8. sdb 是否装 linux-firmware ====="
[ -d /mnt/sdb_check/usr/lib/firmware ] && echo "[有]" || echo "[无] 新内核可能缺固件"
umount /mnt/sdb_check && echo "[OK] 已卸载，sda 未被修改"
