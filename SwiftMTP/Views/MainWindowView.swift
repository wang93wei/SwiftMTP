//
//  MainWindowView.swift
//  SwiftMTP
//
//  Main application window with navigation split view
//

import SwiftUI

struct MainWindowView: View {
    @StateObject private var deviceManager = DeviceManager.shared
    @StateObject private var transferManager = FileTransferManager.shared
    @State private var showTransferPanel = false
    @State private var showDisconnectionAlert = false
    
    var body: some View {
        NavigationSplitView {
            // Sidebar: Device List
            DeviceListView()
                .environmentObject(deviceManager)
                .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 300)
        } detail: {
            // Main content: File Browser
            if let selectedDevice = deviceManager.selectedDevice {
                FileBrowserView(device: selectedDevice)
            } else {
                ContentUnavailableView(
                    "未选择设备",
                    systemImage: "iphone.slash",
                    description: Text("请从左侧列表选择一个 Android 设备")
                )
            }
        }
        .background()
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Button {
                    if deviceManager.selectedDevice != nil {
                        // Refresh file list by posting notification
                        NotificationCenter.default.post(name: NSNotification.Name("RefreshFileList"), object: nil)
                    } else {
                        deviceManager.scanDevices()
                    }
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
                .disabled(deviceManager.isScanning)
                .help(deviceManager.selectedDevice != nil ? "刷新文件列表" : "刷新设备列表")
                
                Divider()
                
                Button {
                    showTransferPanel.toggle()
                } label: {
                    Label("传输任务", systemImage: "arrow.up.arrow.down.circle")
                }
                .badge(transferManager.activeTasks.count)
                .help("查看文件传输任务")
            }
        }
        .toolbarLiquidGlass()
        .sheet(isPresented: $showTransferPanel) {
            FileTransferView()
                .environmentObject(transferManager)
                .frame(minWidth: 600, minHeight: 400)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("DeviceDisconnected"))) { _ in
            showDisconnectionAlert = true
        }
        .alert("设备已断开", isPresented: $showDisconnectionAlert) {
            Button("确定", role: .cancel) {}
        } message: {
            Text("Android 设备已断开连接，请重新连接设备。")
        }
    }
}

#Preview {
    MainWindowView()
        .frame(width: 1200, height: 800)
}
