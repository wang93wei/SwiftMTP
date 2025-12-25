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
        .navigationTitle(title)
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(.ultraThickMaterial)
        .backgroundExtensionEffect()
        .overlay(alignment: .top) {
            Divider()
                .opacity(0.2)
        }
        .overlay {
            if deviceManager.devices.isEmpty {
                if deviceManager.isScanning && !deviceManager.hasScannedOnce {
                    ProgressView(L10n.DeviceList.scanningDevices)
                        .liquidGlass(style: .regular, cornerRadius: 12)
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
