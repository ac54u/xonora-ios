import SwiftUI

struct ProviderManagementView: View {
    @StateObject private var viewModel = ProviderManagementViewModel()
    @State private var showingAddProvider = false
    @State private var selectedConfig: ProviderConfig?
    @State private var showRemoveConfirmation = false
    @State private var removeTarget: ProviderConfig?
    @State private var toastMessage: String?

    var body: some View {
        List {
            if viewModel.isLoading {
                HStack {
                    Spacer()
                    ProgressView("Loading providers...")
                    Spacer()
                }
            } else if let error = viewModel.errorMessage {
                ContentUnavailableView(
                    "Failed to Load",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
            } else if viewModel.configs.isEmpty && viewModel.manifests.isEmpty {
                ContentUnavailableView(
                    "No Providers",
                    systemImage: "square.3.layers.3d",
                    description: Text("Tap + to add a music source.")
                )
            } else {
                if !viewModel.installedProviders.isEmpty {
                    Section("Active Providers") {
                        ForEach(viewModel.installedProviders) { config in
                            providerRow(config)
                        }
                    }
                }

                if !viewModel.disabledProviders.isEmpty {
                    Section("Disabled") {
                        ForEach(viewModel.disabledProviders) { config in
                            providerRow(config)
                        }
                    }
                }
            }
        }
        .navigationTitle("Providers")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    showingAddProvider = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(String(localized: "Add Provider"))
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    Task { await viewModel.loadAll() }
                } label: {
                    if viewModel.isLoading {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .disabled(viewModel.isLoading)
                .accessibilityLabel(String(localized: "Refresh"))
            }
        }
        .sheet(isPresented: $showingAddProvider) {
            AddProviderView(viewModel: viewModel)
        }
        .sheet(item: $selectedConfig) { config in
            ProviderConfigView(viewModel: viewModel, config: config)
        }
        .alert("Remove Provider", isPresented: $showRemoveConfirmation, presenting: removeTarget) { config in
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) {
                Task {
                    let success = await viewModel.removeProvider(instanceId: config.instanceId)
                    if success {
                        toastMessage = String(format: NSLocalizedString("%@ removed", comment: ""), config.displayName)
                    }
                }
            }
        } message: { config in
            Text(String(format: NSLocalizedString("Remove \"%@\"? This cannot be undone.", comment: ""), config.displayName))
        }
        .task { await viewModel.loadAll() }
        .overlay(alignment: .bottom) {
            if let msg = toastMessage {
                Text(msg)
                    .font(.subheadline)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.regularMaterial)
                    .clipShape(Capsule())
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            withAnimation { toastMessage = nil }
                        }
                    }
            }
        }
    }

    private func providerRow(_ config: ProviderConfig) -> some View {
        HStack {
            Image(systemName: ProviderBrand(provider: config.domain).icon)
                .foregroundColor(ProviderBrand(provider: config.domain).color)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(config.displayName)
                    .font(.body)
                Text(ProviderBrand(provider: config.domain).displayName)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if let status = config.status {
                statusBadge(status)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            selectedConfig = config
        }
        .swipeActions(edge: .trailing) {
            Button("Remove", role: .destructive) {
                removeTarget = config
                showRemoveConfirmation = true
            }
            Button("Reload") {
                Task { await viewModel.reloadProvider(instanceId: config.instanceId) }
            }
            .tint(.orange)
        }
    }

    private func statusBadge(_ status: String) -> some View {
        let (key, color): (String, Color) = switch status {
        case "loaded": ("On", .green)
        case "loading": ("...", .orange)
        case "disabled": ("Off", .gray)
        case "auth_required": ("Auth", .red)
        case "error": ("Error", .red)
        default: (status, .secondary)
        }
        return Text(LocalizedStringKey(key))
            .font(.caption.weight(.medium))
            .foregroundColor(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
            .accessibilityLabel(String(localized: "Status: \(key)"))
    }
}
