import SwiftUI

struct ProviderConfigView: View {
    @ObservedObject var viewModel: ProviderManagementViewModel
    var config: ProviderConfig?
    var manifest: ProviderManifest?
    var isNew: Bool = false
    @Environment(\.dismiss) private var dismiss
    @State private var toastMessage: String?

    init(viewModel: ProviderManagementViewModel, config: ProviderConfig) {
        self.viewModel = viewModel
        self.config = config
        self.manifest = nil
        self.isNew = false
    }

    init(viewModel: ProviderManagementViewModel, manifest: ProviderManifest, isNew: Bool) {
        self.viewModel = viewModel
        self.manifest = manifest
        self.config = nil
        self.isNew = isNew
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.editingEntries.isEmpty {
                    VStack(spacing: 16) {
                        ProgressView()
                        Text("Loading configuration...")
                            .foregroundColor(.secondary)
                    }
                } else {
                    Form {
                        ForEach(visibleEntries) { entry in
                            configField(for: entry)
                        }

                        if !isNew {
                            Section {
                                Button("Reload Provider", role: .none) {
                                    if let config = config {
                                        Task { await viewModel.reloadProvider(instanceId: config.instanceId) }
                                        toastMessage = "Reloading..."
                                    }
                                }

                                Button("Remove Provider", role: .destructive) {
                                    if let config = config {
                                        Task {
                                            let success = await viewModel.removeProvider(instanceId: config.instanceId)
                                            if success { dismiss() }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(isNew ? (manifest?.name ?? "New Provider") : (config?.displayName ?? "Provider"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await save() }
                    }
                    .disabled(viewModel.isSaving)
                }
            }
            .task {
                if isNew, let domain = manifest?.domain {
                    await viewModel.loadNewProviderEntries(domain: domain)
                } else if let config = config {
                    await viewModel.loadProviderConfigEntries(providerConfig: config)
                }
            }
            .overlay(alignment: .bottom) {
                if viewModel.isSaving {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Saving...")
                    }
                    .padding()
                    .background(.regularMaterial)
                    .clipShape(Capsule())
                    .padding(.bottom, 8)
                }
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
                if let err = viewModel.saveError {
                    Text(err)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding()
                        .background(.regularMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.bottom, 8)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                                withAnimation { viewModel.saveError = nil }
                            }
                        }
                }
            }
        }
    }

    private var visibleEntries: [ConfigEntry] {
        viewModel.editingEntries.filter { entry in
            if entry.hidden == true { return false }
            if let dependsOn = entry.dependsOn,
               let dependsVal = entry.dependsOnValue {
                let currentVal = viewModel.editingValues[dependsOn]
                let matches: Bool
                switch dependsVal {
                case .bool(let v): matches = (currentVal as? Bool) == v
                case .string(let v): matches = (currentVal as? String) == v
                case .int(let v): matches = (currentVal as? Int) == v
                case .double(let v): matches = (currentVal as? Double) == v
                default: matches = false
                }
                if !matches { return false }
            }
            if let dependsOn = entry.dependsOn,
               let dependsValNot = entry.dependsOnValueNot {
                let currentVal = viewModel.editingValues[dependsOn]
                let matches: Bool
                switch dependsValNot {
                case .bool(let v): matches = (currentVal as? Bool) == v
                case .string(let v): matches = (currentVal as? String) == v
                case .int(let v): matches = (currentVal as? Int) == v
                case .double(let v): matches = (currentVal as? Double) == v
                default: matches = false
                }
                if matches { return false }
            }
            return true
        }
    }

    @ViewBuilder
    private func configField(for entry: ConfigEntry) -> some View {
        switch entry.type {
        case "boolean":
            Toggle(entry.label, isOn: Binding(
                get: { (viewModel.editingValues[entry.key] as? Bool) ?? (entry.defaultValue?.boolValue ?? false) },
                set: { viewModel.editingValues[entry.key] = $0 }
            ))

        case "string", "secure_string":
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.label)
                    .font(.subheadline.weight(.medium))
                if entry.isSecure {
                    SecureField(entry.label, text: Binding(
                        get: { viewModel.editingValues[entry.key] as? String ?? "" },
                        set: { viewModel.editingValues[entry.key] = $0 }
                    ))
                } else if let options = entry.options, !options.isEmpty {
                    Picker(entry.label, selection: Binding(
                        get: { viewModel.editingValues[entry.key] as? String ?? (entry.defaultValue?.stringValue ?? "") },
                        set: { viewModel.editingValues[entry.key] = $0 }
                    )) {
                        ForEach(options, id: \.title) { option in
                            Text(option.title).tag(option.value.stringValue ?? "")
                        }
                    }
                } else {
                    TextField(entry.label, text: Binding(
                        get: { viewModel.editingValues[entry.key] as? String ?? "" },
                        set: { viewModel.editingValues[entry.key] = $0 }
                    ))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                }
                if let desc = entry.description {
                    Text(desc)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

        case "integer":
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.label)
                    .font(.subheadline.weight(.medium))
                let binding = Binding(
                    get: { viewModel.editingValues[entry.key] as? Int ?? (entry.defaultValue?.intValue ?? 0) },
                    set: { viewModel.editingValues[entry.key] = $0 }
                )
                if let range = entry.range {
                    Slider(value: Binding(
                        get: { Double(binding.wrappedValue) },
                        set: { binding.wrappedValue = Int($0) }
                    ), in: Double(range.min)...Double(range.max), step: 1)
                    Text("\(binding.wrappedValue)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    TextField(entry.label, value: binding, format: .number)
                        .keyboardType(.numberPad)
                }
                if let desc = entry.description {
                    Text(desc)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

        case "float":
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.label)
                    .font(.subheadline.weight(.medium))
                let binding = Binding(
                    get: { viewModel.editingValues[entry.key] as? Double ?? (entry.defaultValue?.doubleValue ?? 0.0) },
                    set: { viewModel.editingValues[entry.key] = $0 }
                )
                TextField(entry.label, value: binding, format: .number)
                    .keyboardType(.decimalPad)
                if let desc = entry.description {
                    Text(desc)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

        case "label":
            Section {
                Text(entry.label)
                    .font(.body)
                if let desc = entry.description {
                    Text(desc)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

        case "divider":
            EmptyView()

        case "alert":
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text(entry.label)
                    .font(.subheadline)
            }

        case "action":
            Button(entry.actionLabel ?? entry.label) {
                Task {
                    if let config = config {
                        let entries = try? await XonoraClient.shared.getProviderConfigEntries(
                            domain: config.domain,
                            instanceId: config.instanceId,
                            action: entry.action,
                            values: viewModel.editingValues
                        )
                        if let entries = entries {
                            await MainActor.run {
                                viewModel.editingEntries = entries
                                for e in entries {
                                    if let v = e.value { viewModel.editingValues[e.key] = v.rawValueForSave }
                                }
                            }
                        }
                    }
                }
            }

        default:
            Text(entry.label)
        }
    }

    private func save() async {
        if isNew, let domain = manifest?.domain {
            let success = await viewModel.addProvider(domain: domain)
            if success { dismiss() }
        } else {
            let success = await viewModel.saveProvider()
            if success { dismiss() }
        }
    }
}
