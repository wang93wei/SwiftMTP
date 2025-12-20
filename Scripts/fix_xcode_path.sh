#!/bin/bash

# 修复 Xcode 路径配置脚本

echo "SwiftMTP - Xcode 路径修复工具"
echo "==============================="

# 检查当前路径
CURRENT_PATH=$(xcode-select --print-path)
echo "当前 Xcode 开发者目录: $CURRENT_PATH"

# 检查 Xcode 是否安装
if [ -d "/Applications/Xcode.app" ]; then
    echo "✅ Xcode 已安装在 /Applications/Xcode.app"
    
    # 检查是否需要切换路径
    if [[ "$CURRENT_PATH" == "/Library/Developer/CommandLineTools" ]]; then
        echo ""
        echo "⚠️  检测到问题：开发者目录指向 Command Line Tools"
        echo "需要运行以下命令修复："
        echo ""
        echo "sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer"
        echo ""
        echo "请在终端中运行上述命令，然后重新运行打包脚本。"
        echo ""
        echo "或者，我可以帮你修复（需要输入密码）："
        read -p "是否现在修复？(y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            echo "正在修复 Xcode 路径..."
            sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
            
            # 验证修复
            NEW_PATH=$(xcode-select --print-path)
            if [[ "$NEW_PATH" == "/Applications/Xcode.app/Contents/Developer" ]]; then
                echo "✅ Xcode 路径已成功修复！"
                echo "现在可以运行打包脚本了："
                echo "./Scripts/create_dmg_simple.sh"
            else
                echo "❌ 修复失败，请手动运行命令"
            fi
        fi
    else
        echo "✅ Xcode 路径配置正确"
    fi
else
    echo "❌ 未找到 Xcode 应用"
    echo "请从 App Store 安装 Xcode"
fi

echo ""
echo "当前可用的 xcodebuild 位置："
which xcodebuild || echo "xcodebuild 未在 PATH 中找到"

echo ""
echo "修复完成后，可以尝试运行："
echo "xcodebuild -version"