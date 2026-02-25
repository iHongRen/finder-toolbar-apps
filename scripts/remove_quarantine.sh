#!/usr/bin/env bash

# remove_quarantine.sh
# 从指定 .app 包或目录（递归）中移除 com.apple.quarantine 属性
# 用法:
#   1. 对当前目录内所有 .app 执行:
#        ./remove_quarantine.sh
#   2. 对指定的一个或多个 .app 或目录执行:
#        ./remove_quarantine.sh /path/to/MyApp.app /path/to/SomeDir
# 注意: 脚本会直接修改文件属性，请在运行前确认路径。

set -euo pipefail

usage() {
  echo "用法: $0 [<path1.app|dir> <path2.app|dir> ...]"
  echo "若不传参数，脚本将在当前目录递归查找 .app 并处理它们。"
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage
  exit 0
fi

# 收集目标（传参或当前目录）
TARGETS=()
if [ "$#" -eq 0 ]; then
  TARGETS=(".")
else
  TARGETS=("$@")
fi

found_apps=()
for t in "${TARGETS[@]}"; do
  if [ -d "$t" ] && [[ "$t" == *.app ]]; then
    # 规范化为绝对路径
    found_apps+=("$(cd "$(dirname "$t")" && pwd)/$(basename "$t")")
  elif [ -d "$t" ]; then
    # 在目录中查找 .app
    while IFS= read -r -d $'\0' p; do
      found_apps+=("$p")
    done < <(find "$t" -type d -name "*.app" -print0)
  else
    echo "警告: 路径不存在或不是目录/.app，跳过: $t" >&2
  fi
done

# 去重（保守做法：按行并保持顺序）
unique_apps=()
if [ ${#found_apps[@]} -gt 0 ]; then
  # 使用 awk 去重，避免依赖 bash 高级特性
  while IFS= read -r line; do
    unique_apps+=("$line")
  done < <(printf '%s
' "${found_apps[@]}" | awk '!seen[$0]++')
fi

if [ ${#unique_apps[@]} -eq 0 ]; then
  echo "未找到任何 .app 要处理。" >&2
  exit 0
fi

if ! command -v xattr >/dev/null 2>&1; then
  echo "错误: 未找到 xattr 工具（该脚本仅适用于 macOS）。" >&2
  exit 1
fi

count=0
for app in "${unique_apps[@]}"; do
  echo "处理: $app"
  # 尝试显示是否存在 quarantine 属性（若无权限也继续尝试删除）
  if xattr -p com.apple.quarantine "$app" >/dev/null 2>&1; then
    echo "  检测到 com.apple.quarantine，正在移除..."
  else
    echo "  未检测到 com.apple.quarantine（仍尝试递归移除以确保清理）。"
  fi

  # 递归删除属性（忽略错误）
  xattr -r -d com.apple.quarantine "$app" 2>/dev/null || true

  # 同时也尝试在 .app 本体上移除（有时资源在包外层）
  xattr -d com.apple.quarantine "$app" 2>/dev/null || true

  echo "  完成: $app"
  count=$((count+1))
done

echo "\n完成：共处理 $count 个 .app。"

exit 0
