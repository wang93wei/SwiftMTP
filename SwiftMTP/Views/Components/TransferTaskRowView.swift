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
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: task.type == .download ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                    .foregroundStyle(task.type == .download ? .blue : .green)
                    .font(.title2)

                VStack(alignment: .leading, spacing: 4) {
                    Text(task.fileName)
                        .font(.headline)
                        .lineLimit(1)

                    Text(task.type.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                statusBadge
            }

            if task.status.isActive {
                VStack(alignment: .leading, spacing: 8) {
                    ProgressView(value: task.progress)
                        .tint(task.type == .download ? .blue : .green)

                    HStack {
                        Text(task.formattedProgress)
                        Spacer()
                        Text(task.formattedSpeed)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            } else if case .failed(let message) = task.status {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var statusBadge: some View {
        if task.status.isActive {
            HStack(spacing: 8) {
                Text(task.status.displayName)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.blue)

                Button {
                    FileTransferManager.shared.cancelTask(task)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }
        } else {
            Text(task.status.displayName)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(statusColor.opacity(0.14), in: Capsule())
                .foregroundStyle(statusColor)
        }
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
            task.updateProgress(transferred: 2_500_000, speed: 512_000)
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
            task.updateStatus(.failed("Device connection lost"))
            return task
        }())
    }
}
