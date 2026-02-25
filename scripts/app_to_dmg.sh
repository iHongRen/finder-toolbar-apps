#!/usr/bin/env bash

# app_to_dmg.sh
# 将多个 .app/指定目录（展开内容）/任意文件打包为 .dmg 文件（适用于 macOS）
# 核心特性：输入目录时自动读取目录内所有内容作为打包对象，而非打包目录本身
# Usage:
#   1. 打包单个App: ./app_to_dmg.sh /path/to/MyApp.app [output.dmg]
#   2. 打包目录内容: ./app_to_dmg.sh /path/to/folder [output.dmg]
#   3. 混合打包: ./app_to_dmg.sh /path/to/folder /path/to/App.app [output.dmg]
# Example:
#   ./app_to_dmg.sh "./MyAppsFolder" "./AllApps.dmg"  # 打包文件夹内所有内容
#   ./app_to_dmg.sh "./MixedDir" "./App1.app" "./Final.dmg"

set -euo pipefail

# 显示用法说明
usage() {
  echo "用法: $0 <输入路径1> [输入路径2 ...] [输出.dmg]"
  echo "核心特性: 输入目录时，自动打包目录内所有内容（而非目录本身）"
  echo "支持的输入类型: .app 包、目录（自动展开）、单个文件（可传多个）"
  echo "示例:"
  echo "  1. 单个App: $0 ./MyApp.app ./MyApp.dmg"
  echo "  2. 打包目录内容: $0 ./MyAppsFolder ./AllApps.dmg"
  echo "  3. 混合打包: $0 ./MixedDir ./App1.app ./Mixed.dmg"
}

# 递归解析输入路径：目录则展开内容，文件则保留
expand_paths() {
  local input_paths=("$@")
  local expanded_paths=()
  
  for path in "${input_paths[@]}"; do
    # 转换为绝对路径并去掉末尾斜杠
    local abs_path=$(cd "$(dirname "$path")" && pwd)/$(basename "$path")
    local path_no_slash="${abs_path%/}"

    # 如果是目录且不是 .app 包，则展开目录内容；.app 包视为单个对象直接加入
    if [ -d "$abs_path" ] && [[ "$path_no_slash" != *.app ]]; then
      echo "检测到目录，自动展开内容: $abs_path" >&2
      local dir_contents=("$abs_path"/*)
      # 过滤空目录（避免添加无效路径）
      if [ -e "${dir_contents[0]}" ]; then
        for item in "${dir_contents[@]}"; do
          # 跳过隐藏文件（以 . 开头）
          if [[ $(basename "$item") != .* ]]; then
            expanded_paths+=("$item")
            echo "  ✅ 加入打包: $(basename "$item")" >&2
          fi
        done
      else
        echo "⚠️  目录为空，跳过: $abs_path" >&2
      fi
    elif [ -e "$abs_path" ]; then
      # 文件或 .app 包：直接加入（.app 不会被展开）
      expanded_paths+=("$abs_path")
      echo "✅ 加入打包: $(basename "$abs_path")" >&2
    else
      echo "⚠️  路径无效，跳过: $abs_path" >&2
    fi
  done
  
  # 返回展开后的路径列表
    # 每行输出一个路径（便于安全读取，不做 word-splitting）
    for p in "${expanded_paths[@]}"; do
      printf '%s\n' "$p"
    done
}

# 检查参数数量（至少1个输入路径）
if [ "$#" -lt 1 ]; then
  usage
  exit 1
fi

# 分离输入路径和输出DMG路径
INPUT_PATHS=()
OUTPUT_DMG=""
OUTPUT_SPECIFIED=false
for arg in "$@"; do
  if [[ "$arg" == *.dmg && -z "$OUTPUT_DMG" ]]; then
    OUTPUT_DMG="$arg"
    OUTPUT_SPECIFIED=true
  else
    INPUT_PATHS+=("$arg")
  fi
done

# 递归展开输入路径（核心：目录自动展开内容）
EXPANDED_PATHS=()
while IFS= read -r line; do
  if [ -n "$line" ]; then
    EXPANDED_PATHS+=("$line")
  fi
done < <(expand_paths "${INPUT_PATHS[@]}")

# 检查展开后是否有有效内容
if [ ${#EXPANDED_PATHS[@]} -eq 0 ]; then
  echo "错误: 无有效文件/目录可打包（输入路径为空或无效）" >&2
  exit 1
fi

# 检查 hdiutil（macOS 专属工具）
if ! command -v hdiutil >/dev/null 2>&1; then
  echo "错误: 未找到 hdiutil（仅适用于 macOS 系统）" >&2
  exit 1
fi

# 处理默认输出文件名（优先取第一个有效输入路径的名称）
if [ -z "$OUTPUT_DMG" ]; then
  # 优先使用原始输入的目录名或文件名来命名 DMG（若无法判断则使用 output.dmg）
  raw_first="${INPUT_PATHS[0]}"
  # 转为绝对路径并去掉末尾斜杠
  abs_first=$(cd "$(dirname "$raw_first")" && pwd)/$(basename "$raw_first")
  first_no_slash="${abs_first%/}"

  if [[ "$first_no_slash" == *.app ]]; then
    base_name=$(basename "$first_no_slash" .app)
  elif [ -d "$first_no_slash" ]; then
    base_name=$(basename "$first_no_slash")
  elif [ -f "$first_no_slash" ]; then
    base_name=$(basename "$first_no_slash")
    base_name=${base_name%.*}
  else
    base_name="output"
  fi

  OUTPUT_DMG="${base_name}.dmg"
fi
# 如果用户未指定输出路径，则将 DMG 放在第一个输入路径所在目录
if [ "$OUTPUT_SPECIFIED" = false ]; then
  # abs_first 已在上面计算
  OUTPUT_DMG_ABS="$(cd "$(dirname "$abs_first")" && pwd)/$(basename "$OUTPUT_DMG")"
else
  # 用户指定了输出路径，按原逻辑转为绝对路径
  OUTPUT_DMG_ABS=$(cd "$(dirname "$OUTPUT_DMG")" && pwd)/$(basename "$OUTPUT_DMG")
fi
# 覆盖已存在的输出文件
if [ -f "$OUTPUT_DMG_ABS" ]; then
  echo "提示: 输出文件已存在，将覆盖: $OUTPUT_DMG_ABS"
  rm -f "$OUTPUT_DMG_ABS"
fi

# 创建临时工作目录（自动清理）
TMPDIR=$(mktemp -d -t dmg-pack-XXXXXX)
trap 'rm -rf "$TMPDIR"' EXIT
echo -e "\n临时工作目录: $TMPDIR"

# 复制所有展开后的路径到临时目录
echo -e "\n开始复制文件/目录到临时目录..."
for path in "${EXPANDED_PATHS[@]}"; do
  cp -R "$path" "$TMPDIR/"
  echo "  ✅ 已复制: $(basename "$path")"
done

# 添加 Applications 快捷方式
ln -s /Applications "$TMPDIR/Applications" 2>/dev/null || echo "提示: 无法创建 Applications 快捷方式（非必需）"

# 设置DMG卷名（修复特殊字符）
VOLNAME=$(basename "$OUTPUT_DMG" .dmg)
VOLNAME=${VOLNAME// /_}
VOLNAME=${VOLNAME//\//-}

# 修复权限
chmod -R go-w "$TMPDIR/" 2>/dev/null || true

# 创建最高压缩的只读DMG
echo -e "\n开始创建 DMG 镜像: $OUTPUT_DMG_ABS"
hdiutil create \
  -volname "$VOLNAME" \
  -srcfolder "$TMPDIR" \
  -ov \
  -format UDZO \
  -imagekey zlib-level=9 \
  "$OUTPUT_DMG_ABS"

# 检查创建结果
ret=$?
if [ $ret -ne 0 ]; then
  echo "错误: DMG 创建失败 (hdiutil 返回 $ret)" >&2
  exit $ret
fi

# 设置最终权限
chmod 644 "$OUTPUT_DMG_ABS" || true

# 输出完成信息
echo -e "\n🎉 打包完成！"
echo "输出文件: $OUTPUT_DMG_ABS"
echo "文件大小: $(du -h "$OUTPUT_DMG_ABS" | awk '{print $1}')"
echo "打包内容: ${#EXPANDED_PATHS[@]} 个文件/目录"
echo -e "\n提示: 用户打开DMG后，可将App拖入Applications文件夹完成安装。"

exit 0