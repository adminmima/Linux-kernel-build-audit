#!/bin/bash
# 06_post_boot_hw_check.sh
# EN: Post-boot hardware acceptance check under the newly booted kernel:
#     network, Bluetooth, storage, sound, input, GPU, temperature,
#     key driver load status, and dmesg errors/warnings.
#     Saves report to post_boot_report_YYYYMMDD_HHMM.txt.
# ZH: 新内核启动后的硬件验收：网卡、蓝牙、存储、声卡、输入设备、显卡、
#     温度、关键驱动加载状态、dmesg 错误/警告。
#     报告保存到 post_boot_report_YYYYMMDD_HHMM.txt。
OUT="/root/code/7.4rc1/post_boot_report_$(date +%Y%m%d_%H%M).txt"
exec > >(tee "$OUT") 2>&1
echo "===== 0. 内核与系统 ====="
uname -a
echo "启动时间: $(uptime -p)"
echo "运行时长: $(uptime -s)"
echo -e "\n===== 1. 网卡（有线 + 无线）====="
for iface in $(ls /sys/class/net | grep -v lo); do
    echo "--- $iface ---"
    ethtool "$iface" 2>/dev/null | grep -E 'Speed|Duplex|Link detected' || echo "ethtool 不可用或无此信息"
    ip -brief addr show "$iface" 2>/dev/null
done
echo -e "\n===== 2. 蓝牙 ====="
rfkill list bluetooth 2>/dev/null || echo "rfkill 不可用"
hciconfig 2>/dev/null || echo "hciconfig 不可用（可选）"
echo -e "\n===== 3. 存储设备（USB / NVMe / SATA）====="
lsblk -o NAME,SIZE,MODEL,TRAN,MOUNTPOINTS
echo "--- USB 树 ---"; lsusb -t 2>/dev/null
echo -e "\n===== 4. 声卡 ====="
if command -v aplay &>/dev/null; then aplay -l; else echo "[aplay 未安装，跳过。可 pacman -S alsa-utils]"; fi
echo -e "\n===== 5. 输入设备（触摸板/键盘/鼠标）====="
if command -v libinput &>/dev/null; then
    libinput list-devices | grep -A3 -E 'Touchpad|Keyboard|Mouse'
else
    echo "[libinput 未安装，跳过。可 pacman -S libinput]"
fi
echo "--- /proc/bus/input/devices 摘要 ---"
grep -E '^N:|^H:' /proc/bus/input/devices | head -20
echo -e "\n===== 6. 显卡 ====="
lspci -k | grep -A3 -E 'VGA|3D|Display'
echo "--- DRM 模块 ---"; lsmod | grep -E 'amdgpu|drm' | head -10
echo -e "\n===== 7. 温度 ====="
MAXT=$(for f in /sys/class/thermal/thermal_zone*/temp; do [ -r "$f" ] && cat "$f" 2>/dev/null; done | sort -n | tail -1)
[ -n "$MAXT" ] && echo "最高热区: $((MAXT/1000))°C" || echo "无 thermal_zone 可读"
echo -e "\n===== 8. 关键驱动加载情况 ====="
for mod in amdgpu rtw89_8852ae btusb ax88179_178a uas usb_storage nvme snd_hda_intel i2c_hid hid_multitouch ideapad_laptop; do
    if lsmod | grep -q "^${mod} "; then echo "[加载] $mod"
    elif modinfo "$mod" &>/dev/null; then echo "[存在未加载] $mod"
    else echo "[缺失] $mod"; fi
done
echo -e "\n===== 9. dmesg 中的错误/警告（最近 50 条）====="
dmesg --level=err,warn 2>/dev/null | tail -50 || dmesg | grep -iE 'error|warn|fail' | tail -50
echo -e "\n===== 10. 报告位置 ====="
echo "$OUT"
