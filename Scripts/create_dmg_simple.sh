#!/bin/bash

# SwiftMTP 简化 DMG 打包脚本（无需开发者证书）
# 使用方法: ./Scripts/create_dmg_simple.sh

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 获取脚本所在目录的父目录（项目根目录）
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$SCRIPT_DIR/.."

# 项目配置
PROJECT_NAME="SwiftMTP"
SCHEME_NAME="SwiftMTP"
WORKSPACE_PATH="$PROJECT_ROOT/SwiftMTP.xcodeproj"
CONFIGURATION="Release"
BUILD_PATH="$PROJECT_ROOT/build"
DMG_PATH="$PROJECT_ROOT/build"
APP_NAME="$PROJECT_NAME.app"
DMG_NAME="$PROJECT_NAME"
VERSION=$(cd "$PROJECT_ROOT" && git describe --tags --always --dirty 2>/dev/null || echo "1.0.0")

echo -e "${GREEN}开始打包 $PROJECT_NAME (简化版)...${NC}"
echo -e "${YELLOW}版本: $VERSION${NC}"

# 清理旧的构建文件
echo -e "${YELLOW}清理旧的构建文件...${NC}"
rm -rf "$BUILD_PATH"
mkdir -p "$BUILD_PATH"

# 1. 构建 APP
echo -e "${YELLOW}正在构建 APP...${NC}"
xcodebuild -project "$WORKSPACE_PATH" \
           -scheme "$SCHEME_NAME" \
           -configuration "$CONFIGURATION" \
           -derivedDataPath "$BUILD_PATH/DerivedData" \
           build

if [ $? -ne 0 ]; then
    echo -e "${RED}构建失败！${NC}"
    exit 1
fi

# 查找构建的 APP
APP_PATH=$(find "$BUILD_PATH/DerivedData" -name "$APP_NAME" -type d | head -n 1)

if [ ! -d "$APP_PATH" ]; then
    echo -e "${RED}找不到构建的 APP${NC}"
    exit 1
fi

echo -e "${GREEN}找到 APP: $APP_PATH${NC}"

# 2. 创建 DMG
echo -e "${YELLOW}正在创建 DMG...${NC}"

# 创建临时文件夹
DMG_TEMP_DIR="$DMG_PATH/dmg_temp"
rm -rf "$DMG_TEMP_DIR"
mkdir -p "$DMG_TEMP_DIR"

# 复制 APP 到临时文件夹
cp -R "$APP_PATH" "$DMG_TEMP_DIR/"

# 创建 Applications 文件夹链接
ln -s /Applications "$DMG_TEMP_DIR/Applications"

# 创建一个简单的背景文件夹（可选）
mkdir -p "$DMG_TEMP_DIR/.background"

# 创建 DMG
DMG_FILE="$DMG_PATH/${DMG_NAME}_${VERSION}.dmg"
hdiutil create -volname "$PROJECT_NAME" \
               -srcfolder "$DMG_TEMP_DIR" \
               -ov \
               -format UDZO \
               -imagekey zlib-level=9 \
               "$DMG_FILE"

if [ $? -ne 0 ]; then
    echo -e "${RED}创建 DMG 失败！${NC}"
    exit 1
fi

# 清理临时文件
rm -rf "$DMG_TEMP_DIR"

# 3. 输出结果
echo -e "${GREEN}✅ DMG 创建成功！${NC}"
echo -e "${GREEN}文件位置: $DMG_FILE${NC}"

# 显示文件大小
DMG_SIZE=$(du -h "$DMG_FILE" | cut -f1)
echo -e "${GREEN}文件大小: $DMG_SIZE${NC}"

# 4. 自动打开 DMG 文件夹
echo -e "${YELLOW}是否要打开 DMG 所在文件夹? (y/n)${NC}"
read -r response
if [[ "$response" =~ ^[Yy]$ ]]; then
    open "$DMG_PATH"
fi

echo -e "${GREEN}完成！${NC}"
echo -e "${YELLOW}提示: 由于没有开发者证书，安装时可能需要在系统偏好设置中允许运行${NC}"