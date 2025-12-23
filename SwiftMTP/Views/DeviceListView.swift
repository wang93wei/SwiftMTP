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
        }
        .listStyle(.sidebar)
        .navigationTitle("设备")
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
