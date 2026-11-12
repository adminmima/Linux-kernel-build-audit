#!/bin/bash
# 03_install_kernel_and_update_boot.sh
# EN: Install the compiled kernel, force btrfs into initramfs, regenerate initramfs,
#     and update GRUB. Run inside the sdb chroot after a successful build.
#     Usage: bash 03_install_kernel_and_update_boot.sh <ESP_mount_inside_chroot>
# ZH: 编译成功后，在 sdb 的 chroot 内安装内核、把 btrfs 强制加入 initramfs、
#     重新生成 initramfs、更新 GRUB。
#     用法：bash 03_install_kernel_and_update_boot.sh <chroot内ESP挂载点，如 /efi>
set -e
ESP_MOUNT="${1:?用法: $0 <ESP挂载点，如 /efi>}"
echo "===== 1. 安装编译好的包 ====="
makepkg -si --noconfirm
echo -e "\n===== 2. 确保 btrfs 进 initramfs（双保险）====="
if grep -q '^MODULES=()' /etc/mkinitcpio.conf; then
    sed -i 's/^MODULES=()/MODULES=(btrfs)/' /etc/mkinitcpio.conf
    echo "[修改] MODULES=() -> MODULES=(btrfs)"
fi
mkinitcpio -P
echo -e "\n===== 3. 更新 GRUB ====="
grub-mkconfig -o /boot/grub/grub.cfg
echo -e "\n===== 4. 完成 ====="
echo "ESP=$ESP_MOUNT；重启时在固件菜单选 sdb 的引导项"
