//
//  LiquidGlassView.swift
//  SwiftMTP
//
//  Custom liquid glass effect component for modern macOS UI
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
            .glassEffect(.regular)
            .background(style.material, in: RoundedRectangle(cornerRadius: cornerRadius))
            .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
    }
}

// MARK: - Convenience Modifiers

extension View {
    func liquidGlass(
        style: LiquidGlassStyle = .regular,
        cornerRadius: CGFloat = 12,
        padding: EdgeInsets = EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16)
    ) -> some View {
        self.modifier(LiquidGlassView(style: style, cornerRadius: cornerRadius, padding: padding))
    }
    
    func toolbarLiquidGlass() -> some View {
        self
            .toolbarBackground(.visible, for: .windowToolbar)
            .toolbarBackground(.ultraThinMaterial, for: .windowToolbar)
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 30) {
        Text("Ultra Thin Glass")
            .font(.headline)
            .liquidGlass(style: .ultraThin)
        
        Text("Regular Glass")
            .font(.headline)
            .liquidGlass(style: .regular)
        
        Text("Thick Glass")
            .font(.headline)
            .liquidGlass(style: .thick)
        
        HStack {
            Button("Button 1") {}
                .liquidGlass(style: .thin, cornerRadius: 8)
            
            Button("Button 2") {}
                .liquidGlass(style: .regular, cornerRadius: 8)
        }
    }
    .padding()
    .background(
        LinearGradient(
            colors: [.blue, .purple, .pink],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    )
}