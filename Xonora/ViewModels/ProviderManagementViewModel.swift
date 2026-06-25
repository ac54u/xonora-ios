import Foundation
import Combine

@MainActor
class ProviderManagementViewModel: ObservableObject {
    @Published var manifests: [ProviderManifest] = []
    @Published var configs: [ProviderConfig] = []
    @Published var instances: [ProviderInstance] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    // Editing state
    @Published var editingConfig: ProviderConfig?
    @Published var editingEntries: [ConfigEntry] = []
    @Published var editingValues: [String: Any] = [:]
    @Published var isSaving = false
    @Published var saveError: String?

    func loadAll() async {
        isLoading = true
        errorMessage = nil
        do {
            async let manifestsTask = XonoraClient.shared.getProviderManifests()
            async let configsTask = XonoraClient.shared.getProviderConfigs()
            async let instancesTask = XonoraClient.shared.getProviderInstances()
            let (m, c, i) = try await (manifestsTask, configsTask, instancesTask)
            manifests = m
            configs = c
            instances = i
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func loadProviderConfigEntries(providerConfig: ProviderConfig) async {
        editingConfig = providerConfig
        editingEntries = []
        editingValues = [:]
        do {
            let entries = try await XonoraClient.shared.getProviderConfigEntries(
                domain: providerConfig.domain,
                instanceId: providerConfig.instanceId
            )
            editingEntries = entries
            for entry in entries {
                if let val = entry.value {
                    editingValues[entry.key] = val.rawValueForSave
                } else if let defaultVal = entry.defaultValue {
                    editingValues[entry.key] = defaultVal.rawValueForSave
                }
            }
        } catch {
            saveError = error.localizedDescription
        }
    }

    func loadNewProviderEntries(domain: String) async {
        editingConfig = nil
        editingEntries = []
        editingValues = [:]
        do {
            let entries = try await XonoraClient.shared.getProviderConfigEntries(domain: domain, instanceId: nil)
            editingEntries = entries
            for entry in entries {
                if let val = entry.value {
                    editingValues[entry.key] = val.rawValueForSave
                } else if let defaultVal = entry.defaultValue {
                    editingValues[entry.key] = defaultVal.rawValueForSave
                }
            }
        } catch {
            saveError = error.localizedDescription
        }
    }

    func saveProvider() async -> Bool {
        guard let config = editingConfig else { return false }
        isSaving = true
        saveError = nil
        do {
            try await XonoraClient.shared.saveProviderConfig(
                domain: config.domain,
                values: editingValues,
                instanceId: config.instanceId
            )
            isSaving = false
            return true
        } catch {
            saveError = error.localizedDescription
            isSaving = false
            return false
        }
    }

    func addProvider(domain: String) async -> Bool {
        isSaving = true
        saveError = nil
        do {
            try await XonoraClient.shared.saveProviderConfig(
                domain: domain,
                values: editingValues,
                instanceId: nil
            )
            isSaving = false
            return true
        } catch {
            saveError = error.localizedDescription
            isSaving = false
            return false
        }
    }

    func removeProvider(instanceId: String) async -> Bool {
        do {
            try await XonoraClient.shared.removeProviderConfig(instanceId: instanceId)
            await loadAll()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func reloadProvider(instanceId: String) async {
        do {
            try await XonoraClient.shared.reloadProvider(instanceId: instanceId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    var musicProviderManifests: [ProviderManifest] {
        manifests.filter { $0.type == "music" && !$0.builtin }
    }

    var playerProviderManifests: [ProviderManifest] {
        manifests.filter { $0.type == "player" && !$0.builtin }
    }

    var metadataProviderManifests: [ProviderManifest] {
        manifests.filter { $0.type == "metadata" && !$0.builtin }
    }

    var pluginProviderManifests: [ProviderManifest] {
        manifests.filter { $0.type == "plugin" && !$0.builtin }
    }

    var installedProviders: [ProviderConfig] {
        configs.filter { $0.enabled }
    }

    var disabledProviders: [ProviderConfig] {
        configs.filter { !$0.enabled }
    }
}

// MARK: - ConfigValue helpers for form submission

extension ConfigValue {
    var rawValueForSave: Any {
        switch self {
        case .string(let v): return v
        case .bool(let v): return v
        case .int(let v): return v
        case .double(let v): return v
        case .stringArray(let v): return v
        }
    }
}
