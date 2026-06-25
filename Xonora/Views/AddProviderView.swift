import SwiftUI

struct AddProviderView: View {
    @ObservedObject var viewModel: ProviderManagementViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            List {
                if !filtered(.music).isEmpty {
                    Section("Music Sources") {
                        ForEach(filtered(.music)) { manifest in
                            manifestRow(manifest)
                        }
                    }
                }

                if !filtered(.player).isEmpty {
                    Section("Players") {
                        ForEach(filtered(.player)) { manifest in
                            manifestRow(manifest)
                        }
                    }
                }

                if !filtered(.metadata).isEmpty {
                    Section("Metadata") {
                        ForEach(filtered(.metadata)) { manifest in
                            manifestRow(manifest)
                        }
                    }
                }

                if !filtered(.plugin).isEmpty {
                    Section("Plugins") {
                        ForEach(filtered(.plugin)) { manifest in
                            manifestRow(manifest)
                        }
                    }
                }
            }
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search providers...")
            .navigationTitle("Add Provider")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func filtered(_ type: ProviderTypeFilter) -> [ProviderManifest] {
        let list: [ProviderManifest]
        switch type {
        case .music: list = viewModel.musicProviderManifests
        case .player: list = viewModel.playerProviderManifests
        case .metadata: list = viewModel.metadataProviderManifests
        case .plugin: list = viewModel.pluginProviderManifests
        }
        if searchText.isEmpty { return list }
        return list.filter { $0.name.localizedCaseInsensitiveContains(searchText) || $0.domain.localizedCaseInsensitiveContains(searchText) }
    }

    private func manifestRow(_ manifest: ProviderManifest) -> some View {
        NavigationLink {
            ProviderConfigView(viewModel: viewModel, manifest: manifest, isNew: true)
        } label: {
            HStack {
                Image(systemName: ProviderBrand(provider: manifest.domain).icon)
                    .foregroundColor(ProviderBrand(provider: manifest.domain).color)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(manifest.name)
                        .font(.body)
                    Text(manifest.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                if manifest.isBeta {
                    Text("Beta")
                        .font(.caption2.weight(.medium))
                        .foregroundColor(.orange)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.12))
                        .clipShape(Capsule())
                }
            }
        }
    }
}

private enum ProviderTypeFilter {
    case music, player, metadata, plugin
}
