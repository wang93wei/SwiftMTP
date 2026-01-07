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
    @ObservedObject var languageManager = LanguageManager.shared
    @State private var showTransferPanel = false
    @State private var showDisconnectionAlert = false
    @State private var refreshID = UUID()
    
    var body: some View {
        NavigationSplitView {
            DeviceListView()
                .environmentObject(deviceManager)
                .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 300)
                .navigationSubtitle(L10n.MainWindow.deviceList)
                .safeAreaPadding(.top,5)
        } detail: {
            if let selectedDevice = deviceManager.selectedDevice {
                FileBrowserView(device: selectedDevice)
            } else {
                ContentUnavailableView(
                    L10n.MainWindow.noDeviceSelected,
                    systemImage: "iphone.slash",
                    description: Text(L10n.MainWindow.selectDeviceFromList)
                )
            }
        }
        .id(refreshID)
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Button {
                    if deviceManager.selectedDevice != nil {
                        NotificationCenter.default.post(name: NSNotification.Name("RefreshFileList"), object: nil)
                    } else {
                        deviceManager.scanDevices()
                    }
                } label: {
                    Label(L10n.MainWindow.refresh, systemImage: "arrow.clockwise")
                }
                .disabled(deviceManager.isScanning)
                .help(deviceManager.selectedDevice != nil ? L10n.MainWindow.refreshFileList : L10n.MainWindow.refreshDeviceList)
                
                Divider()
                
                Button {
                    showTransferPanel.toggle()
                } label: {
                    Label(L10n.MainWindow.transferTasks, systemImage: "arrow.up.arrow.down.circle")
                }
                .badge(transferManager.activeTasks.count)
                .help(L10n.MainWindow.viewTransferTasks)
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
        .alert(L10n.MainWindow.deviceDisconnected, isPresented: $showDisconnectionAlert) {
            Button(L10n.MainWindow.ok, role: .cancel) {}
        } message: {
            Text(L10n.MainWindow.deviceDisconnectedMessage)
        }
        .onReceive(NotificationCenter.default.publisher(for: .languageDidChange)) { _ in
            refreshID = UUID()
        }
    }
}

#Preview {
    MainWindowView()
        .frame(width: 1200, height: 800)
}
