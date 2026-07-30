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
    @State private var selectedDeviceID: Device.ID?
    
    var body: some View {
        List(deviceManager.devices, selection: $selectedDeviceID) { device in
            DeviceRowView(device: device)
                .tag(device.id)
        }
        .id(refreshID)
        .listStyle(.sidebar)
        .safeAreaPadding(.top,5)
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
                        }){
                           HStack(spacing: 4) {
                                Image(systemName: "arrow.clockwise")
                                Text(L10n.MainWindow.refresh) 
                            }
                        }
                        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 8))
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
            selectedDeviceID = deviceManager.selectedDevice?.id
        }
        .onChange(of: selectedDeviceID) { _, deviceID in
            guard let deviceID,
                  deviceManager.selectedDevice?.id != deviceID else {
                return
            }

            // List selection is emitted during a SwiftUI update. Yield before
            // opening the session and publishing the application selection.
            Task { @MainActor in
                await Task.yield()
                guard selectedDeviceID == deviceID,
                      deviceManager.selectedDevice?.id != deviceID,
                      let device = deviceManager.devices.first(where: { $0.id == deviceID }) else {
                    return
                }
                deviceManager.selectDevice(device)
                if deviceManager.selectedDevice?.id != deviceID {
                    selectedDeviceID = deviceManager.selectedDevice?.id
                }
            }
        }
        .onChange(of: deviceManager.selectedDevice?.id) { _, deviceID in
            if selectedDeviceID != deviceID {
                selectedDeviceID = deviceID
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
