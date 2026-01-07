//
//  LiquidGlassView.swift
//  SwiftMTP
//
//  基于 Apple 官方 Liquid Glass 最佳实践实现的玻璃效果组件
//  参考: https://developer.apple.com/documentation/swiftui/landmarks-building-an-app-with-liquid-glass
//

import SwiftUI

enum LiquidGlassStyle {
    case ultraThin
    case thin
    case regular
    case thick
    case ultraThick

    var material: Material {
        switch self {
        case .ultraThin:
            return .ultraThinMaterial
        case .thin:
            return .thinMaterial
        case .regular:
            return .regularMaterial
        case .thick:
            return .thickMaterial
        case .ultraThick:
            return .ultraThickMaterial
        }
    }
}

struct LiquidGlassView: ViewModifier {
    let style: LiquidGlassStyle
    let cornerRadius: CGFloat
    let padding: EdgeInsets

    init(
        style: LiquidGlassStyle = .regular,
        cornerRadius: CGFloat = 12,
        padding: EdgeInsets = EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16)
    ) {
        self.style = style
        self.cornerRadius = cornerRadius
        self.padding = padding
    }

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(style.material, in: RoundedRectangle(cornerRadius: cornerRadius))
            .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
    }
}

struct BackgroundExtensionImage: View {
    let image: Image
    let extendsToEdges: Bool

    var body: some View {
        image
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .background(
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            )
            .backgroundExtensionEffect()
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct LiquidGlassContainer<Content: View>: View {
    let material: Material
    let content: Content

    init(
        material: Material = .ultraThinMaterial,
        @ViewBuilder content: () -> Content
    ) {
        self.material = material
        self.content = content()
    }

    var body: some View {
        content
            .background(material, in: RoundedRectangle(cornerRadius: 12))
    }
}

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
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))

            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .opacity(isActive ? 1.0 : 0.6)
        .scaleEffect(isActive ? 1.0 : 0.9)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isActive)
    }
}

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

struct ToolbarGlassGroup<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 4) {
            content
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial, in: Capsule())
    }
}

extension View {
    func liquidGlass(
        style: LiquidGlassStyle = .ultraThin,
        cornerRadius: CGFloat = 12,
        padding: EdgeInsets = EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16)
    ) -> some View {
        self.modifier(LiquidGlassView(style: style, cornerRadius: cornerRadius, padding: padding))
    }

    func toolbarLiquidGlass() -> some View {
        self
            .toolbarBackgroundVisibility(.visible, for: .windowToolbar)
            .toolbarBackground(.ultraThinMaterial, for: .windowToolbar)
    }

    func globalLiquidGlass() -> some View {
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

#Preview {
    ScrollView {
        VStack(spacing: 40) {
            VStack(spacing: 16) {
                Text("Liquid Glass 样式展示")
                    .font(.title2)
                    .bold()

                HStack(spacing: 20) {
                    Text("Ultra Thin")
                        .font(.headline)
                        .liquidGlass(style: .ultraThin)
                        .glassEffect()

                    Text("Thin")
                        .font(.headline)
                        .liquidGlass(style: .thin)
                        .glassEffect()

                    Text("Regular")
                        .font(.headline)
                        .liquidGlass(style: .regular)
                        .glassEffect()

                    Text("Thick")
                        .font(.headline)
                        .liquidGlass(style: .thick)
                        .glassEffect()

                    Text("Ultra Thick")
                        .font(.headline)
                        .liquidGlass(style: .ultraThick)
                        .glassEffect()
                }
            }
            .padding()

            VStack(spacing: 16) {
                Text("背景扩展效果")
                    .font(.title2)
                    .bold()

                BackgroundExtensionImage(
                    image: Image(systemName: "photo"),
                    extendsToEdges: true
                )
                .frame(height: 200)
                .overlay(alignment: .bottomLeading) {
                    VStack(alignment: .leading) {
                        Text("扩展到边缘的标题")
                            .font(.title)
                            .bold()
                            .foregroundStyle(.white)

                        Button("操作按钮") {}
                            .buttonStyle(.borderedProminent)
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
                    .liquidGlass(style: .thin, cornerRadius: 10)

                    Button(action: {}) {
                        Label("上传文件", systemImage: "arrow.up.circle.fill")
                    }
                    .liquidGlass(style: .regular, cornerRadius: 10)

                    Button(action: {}) {
                        Label("下载文件", systemImage: "arrow.down.circle.fill")
                    }
                    .liquidGlass(style: .thick, cornerRadius: 10)
                }
            }
            .padding()
        }
        .padding()
    }
    .scrollEdgeEffectStyle(.hard, for: .all)
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
