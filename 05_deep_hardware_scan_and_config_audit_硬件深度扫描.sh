#!/bin/bash
# 05_hardware_deep_scan.sh
# EN: Deep hardware scan: hwdetect module list, PCI/USB driver mapping,
#     loaded modules, firmware load records, and .config driver audit.
#     Saves report to hardware_report_YYYYMMDD_HHMM.txt.
# ZH: 硬件深度扫描：hwdetect 模块清单、PCI/USB 驱动映射、已加载模块、
#     固件加载记录、.config 关键驱动审计。
#     报告保存到 hardware_report_YYYYMMDD_HHMM.txt。
OUT="/root/code/7.4rc1/hardware_report_$(date +%Y%m%d_%H%M).txt"
CFG="/root/code/7.4rc1/linux-7.4-rc1/.config"
exec > >(tee "$OUT") 2>&1
echo "===== 0. 基本信息 ====="
echo "日期: $(date)"
echo "内核: $(uname -r)"
echo "CPU: $(grep 'model name' /proc/cpuinfo | head -1 | cut -d: -f2 | xargs)"
echo "内存: $(free -h | awk 'NR==2{print $2}')"
echo -e "\n===== 1. hwdetect 官方模块清单 ====="
if command -v hwdetect &>/dev/null; then hwdetect --show-modules; else echo "[hwdetect 未安装，降级为 lspci/lsusb]"; fi
echo -e "\n===== 2. PCI 设备与驱动映射 ====="
lspci -k 2>/dev/null | grep -E '^[0-9a-f]|Kernel driver in use|Kernel modules' | paste - - - 2>/dev/null || lspci -k 2>/dev/null || echo "lspci 不可用"
echo -e "\n===== 3. USB 设备与驱动 ====="
lsusb -t 2>/dev/null || echo "lsusb 不可用"; echo "---"; lsusb 2>/dev/null
echo -e "\n===== 4. 当前已加载模块（基线）====="
lsmod | awk 'NR>1{print $1}' | sort
echo -e "\n===== 5. 固件加载记录 ====="
dmesg 2>/dev/null | grep -iE 'loading firmware|failed to load' | tail -20 || echo "无固件加载记录"
echo -e "\n===== 6. .config 关键驱动状态（可移植性审计）====="
if [ -f "$CFG" ]; then
    for opt in CONFIG_DRM_AMDGPU CONFIG_DRM_AMDGPU_SI CONFIG_DRM_AMDGPU_CIK \
               CONFIG_HSA_AMD CONFIG_RTW89_8852AE CONFIG_SND_HDA_INTEL \
               CONFIG_R8169 CONFIG_E1000 CONFIG_E1000E CONFIG_IGB \
               CONFIG_USB_XHCI_HCD CONFIG_USB_EHCI_HCD CONFIG_BTRFS_FS \
               CONFIG_VFAT_FS CONFIG_EXFAT_FS CONFIG_NTFS3_FS; do
        grep -E "^${opt}=|^# ${opt} is not set" "$CFG" 2>/dev/null || echo "$opt: 未找到"
    done
else
    echo "[.config 不存在，检查路径: $CFG]"
fi
echo -e "\n===== 7. 报告位置 ====="
echo "$OUT"
