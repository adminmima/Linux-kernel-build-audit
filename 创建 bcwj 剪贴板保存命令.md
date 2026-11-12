# 装剪贴板工具（X11 用 xclip，Wayland 用 wl-clipboard，两个都装最稳）
pacman -S --needed xclip wl-clipboard

# 创建 bcwj 命令
cat > /usr/local/bin/bcwj << 'EOF'
#!/bin/bash
# bcwj - 保存剪贴板内容到文件
# 用法: bcwj [目标文件]
#   不带参数: 保存到 /root/code/7.4rc1/execution_report_2026-11-06_linux-7.4rc1_build_and_boot.md
#   带参数:   保存到指定文件
DEFAULT="/root/code/7.4rc1/execution_report_2026-11-06_linux-7.4rc1_build_and_boot.md"
FILE="${1:-$DEFAULT}"
if [ -n "$WAYLAND_DISPLAY" ] && command -v wl-paste &>/dev/null; then
    wl-paste > "$FILE"
elif command -v xclip &>/dev/null; then
    xclip -selection clipboard -o > "$FILE"
else
    echo "错误: 需要安装 xclip 或 wl-clipboard"
    exit 1
fi
echo "已保存到: $FILE"
echo "大小: $(wc -c < "$FILE") 字节, 行数: $(wc -l < "$FILE") 行"
EOF
chmod +x /usr/local/bin/bcwj
which bcwj