//
//  ToastView.swift
//  SwiftMTP
//
//  Toast notification component for displaying brief messages
//

import SwiftUI
import Combine

/// Toast 消息类型
enum ToastType {
    case success
    case error
    case warning
    case info
    
    var icon: String {
        switch self {
        case .success: return "checkmark.circle.fill"
        case .error: return "xmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .success: return .green
        case .error: return .red
        case .warning: return .orange
        case .info: return .blue
        }
    }
}

/// Toast 消息模型
struct ToastMessage: Identifiable {
    let id = UUID()
    let title: String
    let message: String?
    let type: ToastType
    let duration: TimeInterval
}

/// Toast 视图组件
struct ToastView: View {
    let message: ToastMessage
    let onDismiss: () -> Void
    
    @State private var isShowing = false
    
    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 12) {
                Image(systemName: message.type.icon)
                    .font(.system(size: 20))
                    .foregroundStyle(message.type.color)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(message.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                    
                    if let msg = message.message {
                        Text(msg)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                
                Spacer()
                
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(.ultraThinMaterial)
        .background(message.type.color.opacity(0.1))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
        .frame(maxWidth: 400)
        .opacity(isShowing ? 1 : 0)
        .offset(y: isShowing ? 0 : -20)
        .onAppear {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isShowing = true
            }
            
            // 自动消失 - 使用 Swift 6 结构化并发
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(message.duration))
                await dismiss()
            }
        }
    }
    
    private func dismiss() async {
        withAnimation(.easeOut(duration: 0.2)) {
            isShowing = false
        }
        try? await Task.sleep(for: .milliseconds(200))
        onDismiss()
    }
}

/// Toast 管理器 - 用于全局显示 Toast
@MainActor
class ToastManager: ObservableObject {
    static let shared = ToastManager()
    
    @Published var toasts: [ToastMessage] = []
    
    private init() {}
    
    /// 显示成功 Toast
    func showSuccess(title: String, message: String? = nil, duration: TimeInterval = 3.0) {
        show(title: title, message: message, type: .success, duration: duration)
    }
    
    /// 显示错误 Toast
    func showError(title: String, message: String? = nil, duration: TimeInterval = 4.0) {
        show(title: title, message: message, type: .error, duration: duration)
    }
    
    /// 显示警告 Toast
    func showWarning(title: String, message: String? = nil, duration: TimeInterval = 3.0) {
        show(title: title, message: message, type: .warning, duration: duration)
    }
    
    /// 显示信息 Toast
    func showInfo(title: String, message: String? = nil, duration: TimeInterval = 3.0) {
        show(title: title, message: message, type: .info, duration: duration)
    }
    
    /// 显示 Toast
    func show(title: String, message: String? = nil, type: ToastType, duration: TimeInterval = 3.0) {
        let toast = ToastMessage(
            title: title,
            message: message,
            type: type,
            duration: duration
        )
        toasts.append(toast)
    }
    
    /// 移除 Toast
    func dismiss(_ toast: ToastMessage) {
        toasts.removeAll { $0.id == toast.id }
    }
}

/// Toast 容器视图修饰符
struct ToastContainerModifier: ViewModifier {
    @StateObject private var toastManager = ToastManager.shared
    
    func body(content: Content) -> some View {
        ZStack {
            content
            
            // Toast 层
            VStack {
                if !toastManager.toasts.isEmpty {
                    VStack(spacing: 8) {
                        ForEach(toastManager.toasts) { toast in
                            ToastView(message: toast) {
                                toastManager.dismiss(toast)
                            }
                        }
                    }
                    .padding(.top, 16)
                    .padding(.horizontal, 16)
                }
                Spacer()
            }
            .animation(.easeInOut(duration: 0.2), value: toastManager.toasts.count)
        }
    }
}

extension View {
    /// 添加 Toast 容器支持
    func toastContainer() -> some View {
        modifier(ToastContainerModifier())
    }
}

#Preview {
    VStack {
        Text("Toast Preview")
            .padding()
        
        Button("Show Success Toast") {
            ToastManager.shared.showSuccess(
                title: "上传成功",
                message: "已成功上传 5 个文件到设备"
            )
        }
        
        Button("Show Error Toast") {
            ToastManager.shared.showError(
                title: "上传失败",
                message: "部分文件未能成功上传"
            )
        }
        
        Button("Show Warning Toast") {
            ToastManager.shared.showWarning(
                title: "部分成功",
                message: "3/5 个文件上传成功"
            )
        }
    }
    .frame(width: 400, height: 300)
    .toastContainer()
}