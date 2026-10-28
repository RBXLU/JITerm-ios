//
//  LogView.swift
//  JITerm
//

import SwiftUI

/// Журнал stdout/stderr QEMU (ошибки запуска, предупреждения).
struct LogView: View {
    @State private var text = ""

    var body: some View {
        ScrollView {
            Text(text.isEmpty ? "Журнал пуст." : text)
                .font(.system(size: 12, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .navigationTitle("Журнал QEMU")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    load()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                ShareLink(item: text) {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
        .onAppear(perform: load)
    }

    private func load() {
        fflush(stdout)
        fflush(stderr)
        let content = (try? String(contentsOf: GuestStorage.logURL, encoding: .utf8)) ?? ""
        text = content.count > 200_000 ? String(content.suffix(200_000)) : content
    }
}
