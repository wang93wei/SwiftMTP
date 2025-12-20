//
//  DeviceRowView.swift
//  SwiftMTP
//
//  Individual device row in the device list
//

import SwiftUI

struct DeviceRowView: View {
    let device: Device
    
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
                    .background(.ultraThinMaterial, in: Capsule())
                }
            }
            
            if !device.storageInfo.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(device.storageInfo) { storage in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(storage.description)
                                    .font(.caption2)
                                    .fontWeight(.medium)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(ByteCountFormatter.string(fromByteCount: Int64(storage.freeSpace), countStyle: .file))
                                    .font(.caption2)
                                    .fontWeight(.medium)
                                    .foregroundStyle(.primary)
                            }
                            
                            GeometryReader { geometry in
                                ZStack(alignment: .leading) {
                                    // Background
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(.quaternary)
                                        .frame(height: 4)
                                    
                                    // Progress
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(storageColor(for: storage.usagePercentage))
                                        .frame(width: geometry.size.width * (storage.usagePercentage / 100), height: 4)
                                        .animation(.easeInOut(duration: 0.3), value: storage.usagePercentage)
                                }
                            }
                            .frame(height: 4)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
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

#Preview {
    List {
        DeviceRowView(device: Device(
            deviceIndex: 0,
            name: "Pixel 7",
            manufacturer: "Google",
            model: "Pixel 7",
            serialNumber: "ABC123",
            batteryLevel: nil,
            storageInfo: [
                StorageInfo(storageId: 1, maxCapacity: 128_000_000_000, freeSpace: 32_000_000_000, description: "内部存储")
            ]
        ))
    }
    .frame(width: 250)
}
