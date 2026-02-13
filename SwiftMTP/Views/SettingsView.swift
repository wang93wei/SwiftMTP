//
//  SettingsView.swift
//  SwiftMTP
//
//  Application settings view
//

import SwiftUI
import AppKit

struct SettingsView: View {
    @AppStorage("defaultDownloadPath") private var downloadPath = NSHomeDirectory() + "/Downloads"
    @AppStorage("scanInterval") private var scanInterval = 3.0
    @AppStorage("enableNotifications") private var enableNotifications = true
    @ObservedObject var languageManager = LanguageManager.shared

    var body: some View {
        TabView {
            GeneralSettingsView(downloadPath: $downloadPath, languageManager: languageManager)
                .tabItem {
                    Label(L10n.Settings.general, systemImage: "gear")
                }

            TransferSettingsView(enableNotifications: $enableNotifications)
                .tabItem {
                    Label(L10n.Settings.transfer, systemImage: "arrow.up.arrow.down")
                }

            AdvancedSettingsView(scanInterval: $scanInterval)
                .tabItem {
                    Label(L10n.Settings.advanced, systemImage: "slider.horizontal.3")
                }

            AboutView()
                .tabItem {
                    Label(L10n.Settings.about, systemImage: "info.circle")
                }
        }
        .frame(width: 500, height: 400)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

struct GeneralSettingsView: View {
    @Binding var downloadPath: String
    @ObservedObject var languageManager: LanguageManager
    @State private var showingRestartAlert = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 12) {
                Text(L10n.Common.languageSettings)
                    .font(.headline)

                HStack {
                    Text(L10n.Common.selectLanguage)
                        .frame(width: 100, alignment: .leading)

                    Picker("", selection: $languageManager.currentLanguage) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(language.displayName)
                                .tag(language)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                Text(L10n.Settings.downloadSettings)
                    .font(.headline)

                HStack {
                    Text(L10n.Settings.defaultDownloadLocation)
                    TextField(L10n.Common.path, text: $downloadPath)
                        .textFieldStyle(.roundedBorder)

                    Button(L10n.Settings.select) {
                        selectDownloadFolder()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(20)
        .onChange(of: languageManager.currentLanguage) { oldValue, newValue in
            if oldValue != newValue {
                showingRestartAlert = true
            }
        }
        .alert(L10n.Common.restartRequired, isPresented: $showingRestartAlert) {
            Button(L10n.Common.restartLater, role: .cancel) {}
            Button(L10n.Common.restartNow) {
                restartApplication()
            }
        } message: {
            Text(L10n.Common.restartMessage)
        }
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

    private func restartApplication() {
        // 获取应用包路径
        let bundleURL = Bundle.main.bundleURL
        let bundlePath = bundleURL.path
        
        print("[SettingsView] Restarting application from: \(bundlePath)")
        
        // 检查路径是否存在
        guard FileManager.default.fileExists(atPath: bundlePath) else {
            print("[SettingsView] Error: Bundle path does not exist: \(bundlePath)")
            return
        }
        
        // 使用 /usr/bin/open 重新打开应用
        let task = Process()
        task.launchPath = "/usr/bin/open"
        task.arguments = [bundlePath]
        
        do {
            try task.run()
            print("[SettingsView] Open command launched successfully")
            
            // 等待足够的时间让 open 命令执行
            // 在 Xcode 调试环境下可能需要更长的时间
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                print("[SettingsView] Terminating current application")
                NSApp.terminate(nil)
            }
        } catch {
            print("[SettingsView] Failed to restart application: \(error)")
        }
    }
}

struct TransferSettingsView: View {
    @Binding var enableNotifications: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(L10n.Settings.notifications)
                .font(.headline)

            Toggle(L10n.Settings.showNotificationOnTransferComplete, isOn: $enableNotifications)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(20)
    }
}

struct AdvancedSettingsView: View {
    @Binding var scanInterval: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(L10n.Settings.deviceDetection)
                .font(.headline)

            HStack {
                Text(L10n.Settings.scanInterval)
                Slider(value: $scanInterval, in: 1...10, step: 1)
                Text(String(format: L10n.Settings.seconds, Int(scanInterval)))
                    .frame(width: 50)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(20)
    }
}

struct AboutView: View {
    @StateObject private var updateChecker = UpdateChecker.shared
    @State private var showingAlert = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var updateURL: URL?

    private var appIcon: NSImage {
        NSImage(named: "AppIcon") ?? NSImage()
    }

    private var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: appIcon)
                .resizable()
                .scaledToFit()
                .frame(width: 60, height: 60)

            Text(L10n.Settings.appName)
                .font(.title)
                .fontWeight(.bold)

            Text(String(format: L10n.Settings.version, currentVersion))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(L10n.Settings.author)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(L10n.Settings.mtpFileTransferTool)
                .font(.body)
                .multilineTextAlignment(.center)

            // Update check section
            VStack(spacing: 12) {
                if updateChecker.isChecking {
                    ProgressView()
                        .scaleEffect(0.8)
                        .frame(height: 20)
                    Text(L10n.Settings.checkingForUpdates)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let update = updateChecker.latestUpdate {
                    VStack(spacing: 4) {
                        Text(String(format: L10n.Settings.updateAvailable, update.version))
                            .font(.subheadline)
                            .foregroundStyle(.green)
                        Button(L10n.Settings.downloadUpdate) {
                            updateChecker.openDownloadPage()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                } else {
                    Button(L10n.Settings.checkForUpdates) {
                        Task {
                            await performUpdateCheck()
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(updateChecker.isChecking)
                }

                // Auto-check toggle
                Toggle(L10n.Settings.autoCheckUpdates, isOn: $updateChecker.autoCheckEnabled)
                    .font(.caption)
                    .controlSize(.small)
            }
            .padding(.top, 8)

            Divider()
                .padding(.horizontal, 40)

            Text(L10n.Settings.copyright)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)

            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.Settings.builtWith)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 16)
        .alert(alertTitle, isPresented: $showingAlert) {
            if updateURL != nil {
                Button(L10n.Common.cancel, role: .cancel) {}
                Button(L10n.Settings.downloadUpdate) {
                    if let url = updateURL {
                        NSWorkspace.shared.open(url)
                    }
                }
            } else {
                Button(L10n.Common.ok, role: .cancel) {}
            }
        } message: {
            Text(alertMessage)
        }
    }

    private func performUpdateCheck() async {
        let result = await updateChecker.checkForUpdatesWithResult()
        alertTitle = result.title
        alertMessage = result.message
        updateURL = result.updateURL
        showingAlert = true
    }
}

#Preview {
    SettingsView()
}
