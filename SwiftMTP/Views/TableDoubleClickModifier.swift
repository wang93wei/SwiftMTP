import SwiftUI
import AppKit

struct TableDoubleClickModifier: NSViewRepresentable {
    let onDoubleClick: (FileItem?) -> Void

    func makeNSView(context: Context) -> DoubleClickHelperView {
        let view = DoubleClickHelperView()
        view.onDoubleClick = onDoubleClick
        return view
    }

    func updateNSView(_ nsView: DoubleClickHelperView, context: Context) {
        nsView.onDoubleClick = onDoubleClick
    }

    final class DoubleClickHelperView: NSView {
        var onDoubleClick: ((FileItem?) -> Void)?
        private weak var tableView: NSTableView?
        private var retryCount = 0
        private let maxRetries = 30

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            setupDoubleClick()
        }

        private func setupDoubleClick() {
            guard tableView == nil else { return }
            guard retryCount < maxRetries else { return }

            retryCount += 1

            if let window = self.window,
               let table = findTableView(in: window.contentView) {
                self.tableView = table
                table.doubleAction = #selector(handleDoubleClick)
                table.target = self
                return
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.setupDoubleClick()
            }
        }

        private func findTableView(in view: NSView?) -> NSTableView? {
            guard let view else { return nil }
            if let tableView = view as? NSTableView { return tableView }

            for subview in view.subviews {
                if let found = findTableView(in: subview) {
                    return found
                }
            }

            return nil
        }

        @objc private func handleDoubleClick() {
            guard tableView != nil else {
                onDoubleClick?(nil)
                return
            }

            onDoubleClick?(nil)
        }
    }
}
