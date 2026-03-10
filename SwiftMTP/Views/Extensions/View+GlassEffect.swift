//
//  View+GlassEffect.swift
//  SwiftMTP
//
//  Liquid Glass 兼容层 - 在 macOS 26 以下版本提供替代效果
//

import SwiftUI

// MARK: - Glass Effect 兼容扩展

extension View {
    /// 兼容版本的 glassEffect 修饰符
    /// - macOS 26+: 使用系统原生的 glassEffect
    /// - macOS 26以下: 使用 ultraThinMaterial 作为替代
    @ViewBuilder
    func glassEffectCompat() -> some View {
        if #available(macOS 26, *) {
            self.glassEffect()
        } else {
            self.background(.ultraThinMaterial)
        }
    }

    /// 兼容版本的 glassEffect 修饰符（带形状参数）
    /// - macOS 26+: 使用系统原生的 glassEffect
    /// - macOS 26以下: 使用 ultraThinMaterial 作为替代
    @available(macOS 26, *)
    func glassEffectCompat(_ style: Glass, in shape: some Shape) -> some View {
        self.glassEffect(style, in: shape)
    }

    /// 兼容版本的 toolbarLiquidGlass 修饰符
    /// - macOS 26+: 使用原生的 toolbarLiquidGlass
    /// - macOS 26以下: 无操作
    @ViewBuilder
    func toolbarLiquidGlassCompat() -> some View {
        if #available(macOS 26, *) {
            self.toolbarBackgroundVisibility(.visible, for: .windowToolbar)
                .toolbarBackground(.ultraThinMaterial, for: .windowToolbar)
        } else {
            self
        }
    }
}

// MARK: - Glass Effect Union 兼容（仅 macOS 26+）

@available(macOS 26, *)
extension View {
    /// glassEffectUnion 修饰符（仅 macOS 26+）
    func glassEffectUnionCompat(id: String, namespace: Namespace.ID) -> some View {
        self.glassEffectUnion(id: id, namespace: namespace)
    }
}

// MARK: - Glass Effect Container 兼容

/// 在 macOS 26+ 使用 GlassEffectContainer，在低版本使用 HStack
@available(macOS 26, *)
typealias GlassEffectContainerCompat = GlassEffectContainer

/// 低版本的容器替代
@available(macOS, introduced: 15.0, deprecated: 26.0, message: "Use GlassEffectContainer on macOS 26+")
struct GlassEffectContainerFallback<Content: View>: View {
    let spacing: CGFloat?
    let content: Content

    init(spacing: CGFloat? = nil, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        HStack(spacing: spacing) {
            content
        }
    }
}
