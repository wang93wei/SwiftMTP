//
//  LiquidGlassView.swift
//  SwiftMTP
//
//  基于 Apple 官方 Liquid Glass 最佳实践实现的玻璃效果组件
//  参考: https://developer.apple.com/documentation/swiftui/landmarks-building-an-app-with-liquid-glass
//

import SwiftUI

// 确保最低支持 macOS 26
#if !os(macOS)
#error("Liquid Glass 仅支持 macOS 26+")
#endif

@available(macOS 26, *)
struct BackgroundExtensionImage: View {
    let image: Image
    let extendsToLeading: Bool
    let extendsToTrailing: Bool

    init(
        image: Image,
        extendsToLeading: Bool = true,
        extendsToTrailing: Bool = true
    ) {
        self.image = image
        self.extendsToLeading = extendsToLeading
        self.extendsToTrailing = extendsToTrailing
    }

    var body: some View {
        image
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .glassEffect()
            .backgroundExtensionEffect()
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

@available(macOS 26, *)
struct GlassEffectBadge: View {
    let icon: String
    let label: String
    let isActive: Bool
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(color.gradient)
                    .frame(width: 44, height: 44)

                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.white)
            }
            .glassEffect()

            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .opacity(isActive ? 1.0 : 0.6)
        .scaleEffect(isActive ? 1.0 : 0.9)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isActive)
    }
}

@available(macOS 26, *)
struct ScrollExtensionContainer<Content: View>: View {
    let extendsToLeading: Bool
    let extendsToTrailing: Bool
    let content: Content

    init(
        extendsToLeading: Bool = true,
        extendsToTrailing: Bool = true,
        @ViewBuilder content: () -> Content
    ) {
        self.extendsToLeading = extendsToLeading
        self.extendsToTrailing = extendsToTrailing
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 0) {
            if extendsToLeading {
                Spacer()
                    .frame(maxWidth: .infinity)
            }

            content
                .frame(maxWidth: .infinity)

            if extendsToTrailing {
                Spacer()
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

@available(macOS 26, *)
extension View {
    func toolbarLiquidGlass() -> some View {
        self
            .toolbarBackgroundVisibility(.visible, for: .windowToolbar)
            .toolbarBackground(.ultraThinMaterial, for: .windowToolbar)
    }

    func scrollExtension(leading: Bool = true, trailing: Bool = true) -> some View {
        ScrollExtensionContainer(
            extendsToLeading: leading,
            extendsToTrailing: trailing
        ) {
            self
        }
    }
}

@available(macOS 26, *)
#Preview {
    ScrollView {
        VStack(spacing: 40) {
            VStack(spacing: 16) {
                Text("Liquid Glass 样式展示")
                    .font(.title2)
                    .bold()

                HStack(spacing: 20) {
                    Text("Regular")
                        .font(.headline)
                        .padding()
                        .glassEffect()
                        .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
                }
            }
            .padding()

            VStack(spacing: 16) {
                Text("背景扩展效果")
                    .font(.title2)
                    .bold()

                BackgroundExtensionImage(
                    image: Image(systemName: "photo"),
                    extendsToLeading: true,
                    extendsToTrailing: true
                )
                .frame(height: 200)
                .overlay(alignment: .bottomLeading) {
                    VStack(alignment: .leading) {
                        Text("扩展到边缘的标题")
                            .font(.title)
                            .bold()
                            .foregroundStyle(.white)

                        Button("操作按钮") {}
                            .buttonStyle(.glassProminent)
                    }
                    .padding()
                }
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .padding()

            VStack(spacing: 16) {
                Text("自定义 Liquid Glass 徽章")
                    .font(.title2)
                    .bold()

                HStack(spacing: 30) {
                    GlassEffectBadge(
                        icon: "star.fill",
                        label: "收藏",
                        isActive: true,
                        color: .yellow
                    )

                    GlassEffectBadge(
                        icon: "heart.fill",
                        label: "喜欢",
                        isActive: false,
                        color: .red
                    )

                    GlassEffectBadge(
                        icon: "folder.fill",
                        label: L10n.FileBrowser.folder,
                        isActive: true,
                        color: .blue
                    )

                    GlassEffectBadge(
                        icon: "square.and.arrow.down.fill",
                        label: L10n.FileBrowser.download,
                        isActive: false,
                        color: .green
                    )
                }
                .padding()
            }
            .padding()

            VStack(spacing: 16) {
                Text("按钮样式")
                    .font(.title2)
                    .bold()

                HStack(spacing: 16) {
                    Button(action: {}) {
                        Label("扫描设备", systemImage: "antenna.radiowaves.left.and.right")
                    }
                    .buttonStyle(.glass)

                    Button(action: {}) {
                        Label("上传文件", systemImage: "arrow.up.circle.fill")
                    }
                    .buttonStyle(.glassProminent)

                    Button(action: {}) {
                        Label("下载文件", systemImage: "arrow.down.circle.fill")
                    }
                    .buttonStyle(.glass)
                }
            }
            .padding()
        }
        .padding()
    }
    .background(
        LinearGradient(
            colors: [
                Color(red: 0.1, green: 0.1, blue: 0.3),
                Color(red: 0.2, green: 0.1, blue: 0.4),
                Color(red: 0.3, green: 0.1, blue: 0.5)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

    )
}