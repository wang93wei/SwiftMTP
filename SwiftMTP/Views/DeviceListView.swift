//
//  DeviceListView.swift
//  SwiftMTP
//
//  Sidebar view showing connected MTP devices
//

import SwiftUI

struct DeviceListView: View {
    @EnvironmentObject private var deviceManager: DeviceManager
    
    var body: some View {
        List(deviceManager.devices, selection: $deviceManager.selectedDevice) { device in
            DeviceRowView(device: device)
                .tag(device)
                .listRowBackground(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.thinMaterial)
                        .padding(.horizontal, 4)
                )
        }
        .listStyle(.sidebar)
        .navigationTitle("设备")
        .toolbarBackground(.hidden, for: .windowToolbar)
        .scrollContentBackground(.hidden)
        .safeAreaInset(edge: .top, spacing: 0) {
            Color.clear.frame(height: 1)
        }
        .overlay {
            if deviceManager.devices.isEmpty {
                // Only show scanning indicator on first scan, not during periodic scans
                if deviceManager.isScanning && !deviceManager.hasScannedOnce {
                    ProgressView("正在扫描设备...")
                        .liquidGlass(style: .regular, cornerRadius: 12)
                } else {
                    ContentUnavailableView(
                        "无设备",
                        systemImage: "iphone.slash",
                        description: Text("请通过 USB 连接 Android 设备\n并确保设备已开启文件传输模式")
                    )
                }
            }
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
