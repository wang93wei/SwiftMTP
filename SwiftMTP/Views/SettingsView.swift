//
//  SettingsView.swift
//  SwiftMTP
//
//  Application settings view
//

import SwiftUI

struct SettingsView: View {
    @AppStorage("defaultDownloadPath") private var downloadPath = NSHomeDirectory() + "/Downloads"
    @AppStorage("scanInterval") private var scanInterval = 3.0
    @AppStorage("enableNotifications") private var enableNotifications = true

    var body: some View {
        TabView {
            GeneralSettingsView(downloadPath: $downloadPath)
                .tabItem {
                    Label("通用", systemImage: "gear")
                }

            TransferSettingsView(enableNotifications: $enableNotifications)
                .tabItem {
                    Label("传输", systemImage: "arrow.up.arrow.down")
                }

            AdvancedSettingsView(scanInterval: $scanInterval)
                .tabItem {
                    Label("高级", systemImage: "slider.horizontal.3")
                }

            AboutView()
                .tabItem {
                    Label("关于", systemImage: "info.circle")
                }
        }
        .frame(width: 500, height: 400)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

struct GeneralSettingsView: View {
    @Binding var downloadPath: String

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("下载设置")
                .font(.headline)

            HStack {
                Text("默认下载位置:")
                TextField("路径", text: $downloadPath)
                    .textFieldStyle(.roundedBorder)

                Button("选择...") {
                    selectDownloadFolder()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(20)
    }

    private func selectDownloadFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true

        panel.begin { response in
            if response == .OK, let url = panel.url {
                downloadPath = url.path
            }
        }
    }
}

struct TransferSettingsView: View {
    @Binding var enableNotifications: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("通知")
                .font(.headline)

            Toggle("传输完成时显示通知", isOn: $enableNotifications)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(20)
    }
}

struct AdvancedSettingsView: View {
    @Binding var scanInterval: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("设备检测")
                .font(.headline)

            HStack {
                Text("扫描间隔:")
                Slider(value: $scanInterval, in: 1...10, step: 1)
                Text("\(Int(scanInterval)) 秒")
                    .frame(width: 50)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(20)
    }
}

struct AboutView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "smartphone")
                .font(.system(size: 60))
                .foregroundStyle(.blue)

            Text("SwiftMTP")
                .font(.title)
                .fontWeight(.bold)

            Text("版本 1.0.0")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("macOS Android MTP 文件传输工具")
                .font(.body)
                .multilineTextAlignment(.center)

            Divider()
                .padding(.horizontal, 40)

            VStack(alignment: .leading, spacing: 8) {
                Text("基于 libusb-1.0 + go-mtpx 构建")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("© 2025 SwiftMTP")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    SettingsView()
}
