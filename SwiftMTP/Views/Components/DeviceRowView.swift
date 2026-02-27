//
//  DeviceRowView.swift
//  SwiftMTP
//
//  Individual device row in the device list
//

import SwiftUI

struct DeviceRowView: View {
    let device: Device
    @State private var showMtpDetails = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "smartphone")
                    .font(.title2)
                    .tint(.blue)
                    .symbolEffect(.pulse.byLayer, isActive: device.batteryLevel != nil)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(device.displayName)
                        .font(.headline)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    
                    Text(device.displayModel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                if let batteryLevel = device.batteryLevel {
                    HStack(spacing: 4) {
                        Image(systemName: batteryIcon(for: batteryLevel))
                            .tint(batteryColor(for: batteryLevel))
                            .font(.caption)
                        Text("\(batteryLevel)%")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.ultraThickMaterial, in: Capsule())
                }
            }
            
            if !device.storageInfo.isEmpty {
                HStack(spacing: 4) {
                    ForEach(device.storageInfo) { storage in
                        StorageIndicatorView(storage: storage)
                    }
                }
                .padding(.top, 4)
            }
            
            if let mtpInfo = device.mtpSupportInfo {
                MtpSupportIndicatorView(mtpInfo: mtpInfo)
                    .padding(.top, 4)
            }
        }
        .padding(.vertical, 8)
    }
    
    private func batteryIcon(for level: Int) -> String {
        switch level {
        case 0...20: return "battery.0"
        case 21...50: return "battery.25"
        case 51...75: return "battery.50"
        case 76...95: return "battery.75"
        default: return "battery.100"
        }
    }
    
    private func batteryColor(for level: Int) -> Color {
        level < 20 ? .red : .green
    }
}

struct StorageIndicatorView: View {
    let storage: StorageInfo
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(storage.description)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(ByteCountFormatter.string(fromByteCount: Int64(storage.freeSpace), countStyle: .file))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(.quaternary.opacity(0.5))
                        .frame(height: 3)
                    
                    RoundedRectangle(cornerRadius: 2)
                        .fill(storageColor(for: storage.usagePercentage))
                        .frame(width: geometry.size.width * (storage.usagePercentage / 100), height: 3)
                        .animation(.easeInOut(duration: 0.3), value: storage.usagePercentage)
                }
            }
            .frame(height: 3)
        }
    }
    
    private func storageColor(for percentage: Double) -> Color {
        if percentage > 90 {
            return .red
        } else if percentage > 70 {
            return .orange
        } else {
            return .blue
        }
    }
}

struct MtpSupportIndicatorView: View {
    let mtpInfo: MTPSupportInfo
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                HStack(spacing: 2) {
                    Image(systemName: "cable.connector")
                        .font(.caption2)
                        .tint(.green)
                    Text("MTP \(mtpInfo.mtpVersion)")
                        .font(.caption2)
                        .fontWeight(.medium)
                }
                
                if !mtpInfo.vendorExtension.isEmpty {
                    Text("|")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text(mtpInfo.vendorExtension)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
            }
        }
        .padding(.top, 2)
    }
}

#Preview {
    List {
        DeviceRowView(device: .preview)
    }
    .frame(width: 250)
}
