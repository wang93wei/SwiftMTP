#!/bin/bash

# SwiftMTP Xcode 项目配置向导
# 此脚本帮助检查配置是否正确

echo "======================================"
echo "SwiftMTP Xcode 项目配置检查"
echo "======================================"
echo ""

# 检查 libusb-1.0 安装
echo "1. 检查 libusb-1.0 安装..."
if brew list libusb-1.0 &>/dev/null; then
    echo "   ✓ libusb-1.0 已安装"
    LIBUSB_VERSION=$(brew list --versions libusb-1.0 | awk '{print $2}')
    echo "   版本: $LIBUSB_VERSION"

    # 获取路径
    LIBUSB_PREFIX=$(brew --prefix libusb-1.0)

    echo "   libusb-1.0 路径: $LIBUSB_PREFIX"
else
    echo "   ✗ libusb-1.0 未安装"
    echo "   请运行: brew install libusb-1.0"
    exit 1
fi

echo ""
echo "2. 检查源文件..."
if [ -d "SwiftMTP" ]; then
    echo "   ✓ SwiftMTP 源代码目录存在"

    # 检查关键文件
    REQUIRED_FILES=(
        "SwiftMTP/App/SwiftMTPApp.swift"
        "SwiftMTP/SwiftMTP-Bridging-Header.h"
        "SwiftMTP/Services/MTP/DeviceManager.swift"
        "SwiftMTP/Services/MTP/FileSystemManager.swift"
        "SwiftMTP/Services/MTP/FileTransferManager.swift"
    )

    for file in "${REQUIRED_FILES[@]}"; do
        if [ -f "$file" ]; then
            echo "   ✓ $file"
        else
            echo "   ✗ 缺少文件: $file"
        fi
    done
else
    echo "   ✗ SwiftMTP 目录不存在"
    exit 1
fi

echo ""
echo "======================================"
echo "Xcode 项目配置说明"
echo "======================================"
echo ""
echo "请在 Xcode 中进行以下配置："
echo ""
echo "1. 桥接头文件:"
echo "   Build Settings > Objective-C Bridging Header"
echo "   设置为: SwiftMTP/SwiftMTP-Bridging-Header.h"
echo ""
echo "2. 头文件搜索路径:"
echo "   Build Settings > Header Search Paths"
echo "   添加:"
echo "   - $LIBUSB_PREFIX/include"
echo ""
echo "3. 部署目标:"
echo "   设置为 macOS 13.0 或更高"
echo ""
echo "4. 禁用沙盒:"
echo "   Target > Signing & Capabilities"
echo "   移除 App Sandbox (如果存在)"
echo ""
echo "======================================"
echo "配置完成后，按 Cmd+R 构建并运行"
echo "======================================"
