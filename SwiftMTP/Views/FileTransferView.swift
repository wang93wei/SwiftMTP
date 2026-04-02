//
//  FileTransferView.swift
//  SwiftMTP
//
//  View showing active and completed file transfers
//

import SwiftUI
import UniformTypeIdentifiers

struct FileTransferView: View {
    @EnvironmentObject private var transferManager: FileTransferManager
    @Environment(\.dismiss) private var dismiss
    @State private var refreshID = UUID()

    private var activeTaskCount: Int {
        transferManager.activeTasks.count
    }

    private var completedTaskCount: Int {
        transferManager.completedTasks.count
    }

    private var failedTaskCount: Int {
        transferManager.completedTasks.filter {
            if case .failed = $0.status {
                return true
            }
            return false
        }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            headerView

            Divider()
                .opacity(0.15)

            if transferManager.activeTasks.isEmpty && transferManager.completedTasks.isEmpty {
                emptyStateView
            } else {
                transferListView
            }
        }
        .frame(minWidth: 500, minHeight: 300)
        .toolbarLiquidGlass()
        .background(.ultraThinMaterial)
        .id(refreshID)
        .onReceive(NotificationCenter.default.publisher(for: .languageDidChange)) { _ in
            refreshID = UUID()
        }
        .onDrop(of: [.fileURL], delegate: RejectDropDelegate())
    }

    // MARK: - Drop Delegates

    /// 拒绝拖放的委托，用于防止拖放事件冒泡
    private struct RejectDropDelegate: DropDelegate {
        func validateDrop(info: DropInfo) -> Bool {
            return false
        }

        func performDrop(info: DropInfo) -> Bool {
            return false
        }
    }

    private var headerView: some View {
        VStack(spacing: 16) {
            HStack {
                Text(L10n.FileTransfer.fileTransferTitle)
                    .font(.headline)
                    .glassEffect()

                Spacer()

                Button(L10n.FileTransfer.done) {
                    dismiss()
                }
                .buttonStyle(.glass)
                .help(L10n.FileTransfer.closeTransferWindow)
            }

            HStack(spacing: 12) {
                transferSummaryCard(
                    title: L10n.FileTransfer.inProgress,
                    value: activeTaskCount,
                    systemImage: "arrow.triangle.2.circlepath.circle.fill",
                    tint: .blue
                )

                transferSummaryCard(
                    title: L10n.FileTransfer.completed,
                    value: completedTaskCount,
                    systemImage: "checkmark.circle.fill",
                    tint: .green
                )

                transferSummaryCard(
                    title: L10n.FileTransfer.statusFailed,
                    value: failedTaskCount,
                    systemImage: "exclamationmark.triangle.fill",
                    tint: .orange
                )
            }
        }
        .padding()
    }

    private func transferSummaryCard(title: String, value: Int, systemImage: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
            Text(String(value))
                .font(.title3.weight(.semibold))
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.up.arrow.down")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text(L10n.FileTransfer.noTransferTasks)
                .font(.title2)
                .fontWeight(.medium)

            Text(L10n.FileTransfer.noActiveTransfers)
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var transferListView: some View {
        ScrollView {
            VStack(spacing: 16) {
                if !transferManager.activeTasks.isEmpty {
                    activeTasksSection
                }

                if !transferManager.completedTasks.isEmpty {
                    completedTasksSection
                }
            }
            .padding()
            .scrollEdgeEffectStyle(.soft, for: .all)
        }
    }

    private var activeTasksSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.FileTransfer.inProgress)
                .font(.headline)
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                ForEach(transferManager.activeTasks) { task in
                    TransferTaskRowView(task: task)
                }
            }
        }
    }

    private var completedTasksSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L10n.FileTransfer.completed)
                    .font(.headline)
                    .foregroundStyle(.secondary)

                Spacer()

                Button(L10n.FileTransfer.clear) {
                    transferManager.clearCompletedTasks()
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.blue)
                .help(L10n.FileTransfer.clearCompletedTasks)
            }

            VStack(spacing: 8) {
                ForEach(transferManager.completedTasks) { task in
                    TransferTaskRowView(task: task)
                }
            }
        }
    }
}

#Preview {
    FileTransferView()
        .environmentObject(FileTransferManager.shared)
        .frame(width: 600, height: 400)
}
