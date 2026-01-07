//
//  DeviceListView.swift
//  SwiftMTP
//
//  Sidebar view showing connected MTP devices
//

import SwiftUI

struct DeviceListView: View {
    @EnvironmentObject private var deviceManager: DeviceManager
    @State private var refreshID = UUID()
    @State private var title = ""
    
    var body: some View {
        List(deviceManager.devices, selection: $deviceManager.selectedDevice) { device in
            DeviceRowView(device: device)
                .tag(device)
        }
        .id(refreshID)
        .listStyle(.sidebar)
        .safeAreaPadding(.top,5)
        .scrollEdgeEffectStyle(.hard, for: .all)
        .overlay {
            if deviceManager.isScanning && !deviceManager.hasScannedOnce {
                ProgressView(L10n.DeviceList.scanningDevices)

            } else if deviceManager.devices.isEmpty {
                if deviceManager.showManualRefreshButton {
                    VStack(spacing: 16) {
                        ContentUnavailableView(
                            L10n.DeviceList.noDevices,
                            systemImage: "iphone.slash",
                            description: Text(L10n.DeviceList.connectDeviceViaUSB)
                        )
                        
                        Button(action: {
                            deviceManager.manualRefresh()
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.clockwise")
                                Text(L10n.MainWindow.refresh)
                            }
                            .font(.system(size: 14, weight: .medium))
                        }
                        .glassEffect()
                        .scaleEffect(deviceManager.isScanning ? 0.95 : 1.0)
                        .animation(.easeInOut(duration: 0.2), value: deviceManager.isScanning)
                        .disabled(deviceManager.isScanning)
                    }
                    .padding()
                } else {
                    ContentUnavailableView(
                        L10n.DeviceList.noDevices,
                        systemImage: "iphone.slash",
                        description: Text(L10n.DeviceList.connectDeviceViaUSB)
                    )
                }
            }
        }
        .onAppear {
            // 在视图出现时初始化 title，确保 LanguageManager 已初始化
            if title.isEmpty {
                title = L10n.DeviceList.devices
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .languageDidChange)) { _ in
            refreshID = UUID()
            title = L10n.DeviceList.devices
        }
    }
}

#Preview {
    NavigationStack {
        DeviceListView()
            .environmentObject(DeviceManager.shared)
    }
    .frame(width: 250, height: 600)
}
