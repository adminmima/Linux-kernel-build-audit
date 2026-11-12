#!/bin/bash
# 04_system_monitor.sh
# EN: Monitor system status during kernel compilation: load, .o count, CPU,
#     memory/OOM, disk, temperature, sccache stats, and whether vmlinux exists.
# ZH: 编译期间监控系统状态：负载、.o 数量、CPU、内存/OOM、磁盘、
#     温度、sccache 统计、vmlinux 是否已生成。
SRC="/root/code/7.4rc1/linux-7.4-rc1"
echo "===== 负载与编译进度 ====="
cat /proc/loadavg
echo -n ".o 数量: "; find "$SRC" -name '*.o' 2>/dev/null | wc -l
echo -n "cc1 数量: "; pgrep -c cc1 2>/dev/null || echo 0
echo -e "\n===== CPU ====="
grep -E '^(cpu |model name)' /proc/cpuinfo | head -2
vmstat 1 2 | tail -1 | awk '{printf "us: %s%%  sy: %s%%  ni: %s%%  id: %s%%  wa: %s%%\n", $13, $14, $15, $16, $17}'
echo -e "\n===== 内存与 OOM ====="
free -h | awk 'NR==2{printf "内存: 总 %s / 可用 %s / 已用 %s\n", $2, $7, $3}'
echo -n "Swap: "; free -h | awk 'NR==3{print $2}'
if dmesg 2>/dev/null | grep -qi 'killed process.*cc1\|oom-killer'; then
    echo "⚠️ OOM Killer 痕迹:"; dmesg | grep -i 'killed process' | tail -3
else
    echo "OOM Killer: 未触发"
fi
echo -e "\n===== 磁盘 ====="
df -h / /efi 2>/dev/null | awk 'NR>1{print $6": 总"$2" 可用"$4" ("$5" used)"}'
echo -e "\n===== 温度（最高热区）====="
MAXT=$(for f in /sys/class/thermal/thermal_zone*/temp; do [ -r "$f" ] && cat "$f" 2>/dev/null; done | sort -n | tail -1)
[ -n "$MAXT" ] && echo "最高: $((MAXT/1000))°C" || echo "无 thermal_zone 可读"
echo -e "\n===== sccache 状态 ====="
sccache --show-stats 2>/dev/null | grep -E 'Compile requests |Cache hits |Cache misses |Cache size|Compilation failures' | head -8
echo -e "\n===== vmlinux（接近尾声标志）====="
[ -f "$SRC/vmlinux" ] && echo "vmlinux 已生成，接近链接阶段" || echo "vmlinux 尚未生成"
