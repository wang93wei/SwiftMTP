//
//  TransferTaskRowView.swift
//  SwiftMTP
//
//  Individual transfer task row showing progress
//

import SwiftUI

struct TransferTaskRowView: View {
    @ObservedObject var task: TransferTask
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: task.type == .download ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                .foregroundStyle(task.type == .download ? .blue : .green)
                .font(.title2)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(task.fileName)
                    .font(.headline)
                    .lineLimit(1)
                
                Text(task.type.rawValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            // Status text on the right
            HStack(spacing: 8) {
                if task.status.isActive {
                    // For active transfers, show simple status
                    Text(task.status.displayName)
                        .font(.caption)
                        .foregroundStyle(.blue)
                    
                    Button {
                        FileTransferManager.shared.cancelTask(task)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                } else {
                    // For completed/failed tasks, show status with appropriate color
                    Text(task.status.displayName)
                        .font(.caption)
                        .foregroundStyle(statusColor)
                }
            }
        }
        .padding(.vertical, 8)
    }
    
    private var statusColor: Color {
        switch task.status {
        case .completed:
            return .green
        case .failed:
            return .red
        case .cancelled:
            return .orange
        default:
            return .secondary
        }
    }
}

#Preview {
    List {
        TransferTaskRowView(task: {
            let task = TransferTask(
                type: .download,
                fileName: "IMG_1234.jpg",
                sourceURL: URL(fileURLWithPath: "/device/1234"),
                destinationPath: "/Users/test/Downloads/IMG_1234.jpg",
                totalSize: 5_000_000
            )
            task.updateStatus(.transferring)
            return task
        }())
        
        TransferTaskRowView(task: {
            let task = TransferTask(
                type: .upload,
                fileName: "video.mp4",
                sourceURL: URL(fileURLWithPath: "/Users/test/video.mp4"),
                destinationPath: "/device/DCIM",
                totalSize: 100_000_000
            )
            task.updateStatus(.completed)
            return task
        }())
        
        TransferTaskRowView(task: {
            let task = TransferTask(
                type: .download,
                fileName: "large_file.zip",
                sourceURL: URL(fileURLWithPath: "/device/large_file"),
                destinationPath: "/Users/test/Downloads/large_file.zip",
                totalSize: 500_000_000
            )
            task.updateStatus(.failed("设备连接已断开"))
            return task
        }())
    }
}
