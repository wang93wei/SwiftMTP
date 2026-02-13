//
//  MainWindowView.swift
//  SwiftMTP
//
//  Main application window with navigation split view
//

import SwiftUI

struct MainWindowView: View {
    @StateObject private var deviceManager = DeviceManager.shared
    @ObservedObject var languageManager = LanguageManager.shared
    @State private var showDisconnectionAlert = false
    @State private var refreshID = UUID()
    
    var body: some View {
        NavigationSplitView {
            DeviceListView()
                .environmentObject(deviceManager)
                .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 300)
                .navigationSubtitle(L10n.MainWindow.deviceList)
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
        .toastContainer()
    }
}

#Preview {
    MainWindowView()
        .frame(width: 1200, height: 800)
}
