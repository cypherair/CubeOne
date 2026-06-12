import CubeKit
import SwiftUI

/// Solving method choice plus optimal-table management.
struct SolvingSettingsView: View {
    @Bindable var settings: SettingsStore
    let model: AppModel

    var body: some View {
        Form {
            Section("Method") {
                ForEach(SettingsStore.SolvingMethod.allCases) { method in
                    Button {
                        settings.solvingMethod = method
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(method.label)
                                    .foregroundStyle(.primary)
                                Text(method.detail)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if settings.solvingMethod == method {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            Section {
                tierRow(.sevenEdge, title: "Standard tables",
                        subtitle: "7-edge · 0.5 GB installed")
                tierRow(.eightEdge, title: "Deep tables",
                        subtitle: "8-edge · 4.8 GB installed · fastest searches")
            } header: {
                Text("Optimal solver tables")
            } footer: {
                Text(footerText)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Solving")
        .onAppear { model.optimalTables.refresh() }
    }

    private var footerText: String {
        var text = "The optimal solver uses the largest installed tier. Generating runs once and is kept on disk; deep tables take roughly half an hour to build."
        #if os(iOS)
        text += " Deep-table searches are experimental on iPhone and far slower than on a Mac."
        #endif
        return text
    }

    @ViewBuilder
    private func tierRow(_ tier: OptimalTableTier, title: String, subtitle: String) -> some View {
        let manager = model.optimalTables
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            switch manager.status[tier] ?? .absent(seedAvailable: false) {
            case .installed(let bytes):
                Text(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
                Button(role: .destructive) {
                    manager.delete(tier)
                } label: {
                    Image(systemName: "trash")
                        .accessibilityLabel("Delete \(title)")
                }
                .buttonStyle(.borderless)
                .disabled(manager.busyTier != nil)
            case .installingSeed(let fraction):
                ProgressView(value: fraction)
                    .frame(width: 90)
                Text("Installing…")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            case .generating(let tableIndex, let tableCount, let fraction):
                ProgressView(value: fraction)
                    .frame(width: 90)
                Text("Table \(tableIndex + 1)/\(tableCount)")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
                Button("Cancel") {
                    manager.cancelPreparation()
                }
                .buttonStyle(.borderless)
            case .absent(let seedAvailable):
                Button(seedAvailable ? "Install" : "Prepare") {
                    manager.prepare(tier)
                }
                .buttonStyle(.bordered)
                .disabled(manager.busyTier != nil)
            }
        }
    }
}
