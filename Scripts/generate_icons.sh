#!/bin/bash

# SwiftMTP 图标生成脚本
# 用法: ./generate_icons.sh

SVG_FILE="SwiftMTP/App/Resources/SwiftMTP_Logo.svg"
OUTPUT_DIR="SwiftMTP/App/Assets.xcassets/AppIcon.appiconset"

echo "🎨 开始生成 App 图标..."

# 检查 SVG 文件是否存在
if [ ! -f "$SVG_FILE" ]; then
    echo "❌ 错误: 未找到 SVG 文件: $SVG_FILE"
    exit 1
fi

# 创建输出目录
mkdir -p "$OUTPUT_DIR"

# 检查 rsvg-convert 是否可用
if ! command -v rsvg-convert &> /dev/null; then
    echo "📦 未安装 rsvg-convert，正在安装..."
    brew install librsvg
fi

# 定义所需尺寸（iOS + macOS）
declare -a SIZES=(
    "1024,1024,App Store"
    "1024,1024,macOS 512pt @2x"
)

# 生成各尺寸图标
for size_info in "${SIZES[@]}"; do
    IFS=',' read -r width height idiom <<< "$size_info"
    filename="icon-${width}x${height}.png"
    
    echo "  📐 生成: $filename ($width x $height)"
    rsvg-convert -w "$width" -h "$height" "$SVG_FILE" -o "$OUTPUT_DIR/$filename"
done

# 生成 @2x 版本（复制并重命名）
for size_info in "${SIZES[@]}"; do
    IFS=',' read -r width height idiom <<< "$size_info"
    
    # 跳过已经是 @2x 的尺寸
    if [[ $width -ge 1024 ]] || [[ $height -ge 1024 ]]; then
        continue
    fi
    
    src_file="icon-${width}x${height}.png"
    dst_file="icon-$((${width}*2))x$((${height}*2))@2x.png"
    
    if [ -f "$OUTPUT_DIR/$src_file" ]; then
        echo "  📐 生成: $dst_file"
        cp "$OUTPUT_DIR/$src_file" "$OUTPUT_DIR/$dst_file"
    fi
done

# 生成 Contents.json
cat > "$OUTPUT_DIR/Contents.json" << 'EOF'
{
  "images" : [
    {
      "idiom" : "universal",
      "platform" : "ios",
      "scale" : "2x",
      "size" : "20x20"
    },
    {
      "idiom" : "universal",
      "platform" : "ios",
      "scale" : "3x",
      "size" : "20x20"
    },
    {
      "idiom" : "universal",
      "platform" : "ios",
      "scale" : "2x",
      "size" : "29x29"
    },
    {
      "idiom" : "universal",
      "platform" : "ios",
      "scale" : "3x",
      "size" : "29x29"
    },
    {
      "idiom" : "universal",
      "platform" : "ios",
      "scale" : "2x",
      "size" : "38x38"
    },
    {
      "idiom" : "universal",
      "platform" : "ios",
      "scale" : "3x",
      "size" : "38x38"
    },
    {
      "idiom" : "universal",
      "platform" : "ios",
      "scale" : "2x",
      "size" : "40x40"
    },
    {
      "idiom" : "universal",
      "platform" : "ios",
      "scale" : "3x",
      "size" : "40x40"
    },
    {
      "idiom" : "universal",
      "platform" : "ios",
      "scale" : "2x",
      "size" : "60x60"
    },
    {
      "idiom" : "universal",
      "platform" : "ios",
      "scale" : "3x",
      "size" : "60x60"
    },
    {
      "idiom" : "universal",
      "platform" : "ios",
      "scale" : "2x",
      "size" : "64x64"
    },
    {
      "idiom" : "universal",
      "platform" : "ios",
      "scale" : "3x",
      "size" : "64x64"
    },
    {
      "idiom" : "universal",
      "platform" : "ios",
      "scale" : "2x",
      "size" : "68x68"
    },
    {
      "idiom" : "universal",
      "platform" : "ios",
      "scale" : "2x",
      "size" : "76x76"
    },
    {
      "idiom" : "universal",
      "platform" : "ios",
      "scale" : "2x",
      "size" : "83.5x83.5"
    },
    {
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    },
    {
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "16x16"
    },
    {
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "16x16"
    },
    {
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "32x32"
    },
    {
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "32x32"
    },
    {
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "128x128"
    },
    {
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "128x128"
    },
    {
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "256x256"
    },
    {
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "256x256"
    },
    {
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "512x512"
    },
    {
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "512x512"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
EOF

echo ""
echo "✅ 图标生成完成！"
echo "📁 输出目录: $OUTPUT_DIR"
echo ""
echo "📋 下一步:"
echo "   1. 打开 Xcode 项目"
echo "   2. 确保 Assets.xcassets 包含 AppIcon"
echo "   3. 在项目设置中验证 App Icon Set Name"
echo "   4. 清理并重新构建项目 (Cmd+Shift+K, Cmd+B)"
