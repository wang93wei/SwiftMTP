#!/bin/bash

# SwiftMTP DMG 打包脚本
# 使用方法: ./Scripts/create_dmg.sh

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
ARCHIVE_PATH="$PROJECT_ROOT/build/$PROJECT_NAME.xcarchive"
EXPORT_PATH="$PROJECT_ROOT/build"
DMG_PATH="$PROJECT_ROOT/build"
APP_NAME="$PROJECT_NAME.app"
DMG_NAME="$PROJECT_NAME"

echo -e "${GREEN}开始打包 $PROJECT_NAME...${NC}"

# 清理旧的构建文件
echo -e "${YELLOW}清理旧的构建文件...${NC}"
rm -rf "$ARCHIVE_PATH"
mkdir -p "$ARCHIVE_PATH"

# 1. Archive 项目
echo -e "${YELLOW}正在 Archive 项目...${NC}"
xcodebuild -project "$WORKSPACE_PATH" \
           -scheme "$SCHEME_NAME" \
           -configuration "$CONFIGURATION" \
           -archivePath "$ARCHIVE_PATH" \
           archive

if [ $? -ne 0 ]; then
    echo -e "${RED}Archive 失败！${NC}"
    exit 1
fi

# 2. 导出 APP
echo -e "${YELLOW}正在导出 APP...${NC}"
xcodebuild -exportArchive \
           -archivePath "$ARCHIVE_PATH" \
           -exportPath "$EXPORT_PATH" \
           -exportOptionsPlist "$SCRIPT_DIR/ExportOptions.plist"

if [ $? -ne 0 ]; then
    echo -e "${RED}导出 APP 失败！${NC}"
    exit 1
fi

# 检查 APP 是否存在
APP_PATH="$EXPORT_PATH/$APP_NAME"
if [ ! -d "$APP_PATH" ]; then
    echo -e "${RED}找不到导出的 APP: $APP_PATH${NC}"
    exit 1
fi

# 从导出的 .app 包中读取版本号（已解析 Xcode 变量）
APP_INFO_PLIST="$APP_PATH/Contents/Info.plist"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_INFO_PLIST" 2>/dev/null || echo "1.0.0")
BUILD_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$APP_INFO_PLIST" 2>/dev/null || echo "1")

echo -e "${YELLOW}版本: $VERSION (Build $BUILD_VERSION)${NC}"

# 3. 创建 DMG
echo -e "${YELLOW}正在创建 DMG...${NC}"

# 创建临时文件夹
DMG_TEMP_DIR="$DMG_PATH/dmg_temp"
rm -rf "$DMG_TEMP_DIR"
mkdir -p "$DMG_TEMP_DIR"

# 复制 APP 到临时文件夹
cp -R "$APP_PATH" "$DMG_TEMP_DIR/"

# 创建 Applications 文件夹链接
ln -s /Applications "$DMG_TEMP_DIR/Applications"

# 创建 DMG
DMG_FILE="$DMG_PATH/${DMG_NAME}_${VERSION}.dmg"
hdiutil create -volname "$PROJECT_NAME" \
               -srcfolder "$DMG_TEMP_DIR" \
               -ov \
               -format UDZO \
               "$DMG_FILE"

if [ $? -ne 0 ]; then
    echo -e "${RED}创建 DMG 失败！${NC}"
    exit 1
fi

# 4. 美化 DMG（可选）
echo -e "${YELLOW}正在美化 DMG...${NC}"

# 挂载 DMG
MOUNT_DIR=$(hdiutil attach "$DMG_FILE" -readonly -nobrowse | grep -E '/Volumes/' | awk '{print $3}')

if [ ! -z "$MOUNT_DIR" ]; then
    # 设置 DMG 外观（简化版，不使用背景图片）
    echo '
    tell application "Finder"
        tell disk "'$PROJECT_NAME'"
            open
            set current view of container window to icon view
            set toolbar visible of container window to false
            set statusbar visible of container window to false
            set the bounds of container window to {400, 100, 920, 440}
            set viewOptions to the icon view options of container window
            set arrangement of viewOptions to not arranged
            set icon size of viewOptions to 96
            set position of item "'$APP_NAME'" of container window to {150, 200}
            set position of item "Applications" of container window to {350, 200}
            close
            open
            update without registering applications
            delay 2
        end tell
    end tell
    ' | osascript

    # 卸载 DMG
    hdiutil detach "$MOUNT_DIR" -quiet || true
fi

# 清理临时文件
rm -rf "$DMG_TEMP_DIR"

# 5. 输出结果
echo -e "${GREEN}✅ DMG 创建成功！${NC}"
echo -e "${GREEN}文件位置: $DMG_FILE${NC}"

# 显示文件大小
DMG_SIZE=$(du -h "$DMG_FILE" | cut -f1)
echo -e "${GREEN}文件大小: $DMG_SIZE${NC}"

# 6. 可选：上传到 GitHub Release（如果有 gh 命令）
if command -v gh &> /dev/null; then
    echo -e "${YELLOW}是否要上传到 GitHub Release? (y/n)${NC}"
    read -r response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}正在上传到 GitHub...${NC}"
        gh release create "v$VERSION" "$DMG_FILE" --title "Release $VERSION" --notes "自动发布的 DMG 包"
    fi
fi

echo -e "${GREEN}完成！${NC}"