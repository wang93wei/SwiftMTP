//
//  FileTransferView.swift
//  SwiftMTP
//
//  View showing active and completed file transfers
//

import SwiftUI

struct FileTransferView: View {
    @EnvironmentObject private var transferManager: FileTransferManager
    @Environment(\.dismiss) private var dismiss
    
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
    }
    
    private var headerView: some View {
        HStack {
            Text("文件传输")
                .font(.headline)
            
            Spacer()
            
            Button("完成") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .liquidGlass(style: .thin, cornerRadius: 8)
            .help("关闭传输窗口")
        }
        .padding()
        .background(.ultraThinMaterial)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.up.arrow.down")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            
            Text("无传输任务")
                .font(.title2)
                .fontWeight(.medium)
            
            Text("当前没有文件传输任务")
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
        }
    }
    
    private var activeTasksSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("进行中")
                .font(.headline)
                .foregroundStyle(.secondary)
            
            VStack(spacing: 8) {
                ForEach(transferManager.activeTasks) { task in
                    TransferTaskRowView(task: task)
                        .padding(12)
                        .background(.ultraThinMaterial)
                        .cornerRadius(8)
                }
            }
        }
    }
    
    private var completedTasksSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("已完成")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                Button("清空") {
                    transferManager.clearCompletedTasks()
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.blue)
                .help("清空已完成的传输任务")
            }
            
            VStack(spacing: 8) {
                ForEach(transferManager.completedTasks) { task in
                    TransferTaskRowView(task: task)
                        .padding(12)
                        .background(.ultraThinMaterial)
                        .cornerRadius(8)
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
