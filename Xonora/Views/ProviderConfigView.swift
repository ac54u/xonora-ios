import SwiftUI

fileprivate let configLabelZH: [String: String] = [
    "Log level": "日志级别",
    "API URL": "接口地址",
    "Username": "用户名",
    "Password": "密码",
    "Email": "邮箱",
    "Host": "主机地址",
    "Port": "端口",
    "Quality": "音质",
    "Language": "语言",
    "Country code": "国家代码",
    "Region": "地区",
    "Path": "路径",
    "Token": "令牌",
    "Client ID": "客户端 ID",
    "Client Secret": "客户端密钥",
    "Access token": "访问令牌",
    "Server": "服务器地址",
    "Rate limit": "请求频率",
    "Update interval": "更新间隔",
    "Base URL": "基础地址",
    "Database path": "数据库路径",
    "Audio format": "音频格式",
    "Sample rate": "采样率",
    "Device name": "设备名称",
    "Device ID": "设备 ID",
    "HTTP port": "HTTP 端口",
    "Sync interval": "同步间隔",
    "Max retries": "最大重试",
    "Timeout": "超时",
    "global": "全局",
    "Login Cookie": "登录 Cookie",
    "PO Token Server URL": "PO Token 服务器地址",
    "Sync Library Artists from this source to Music Assistant": "将来源的艺人同步到 Music Assistant",
    "Sync Library Albums from this source to Music Assistant": "将来源的专辑同步到 Music Assistant",
    "Sync Library Tracks from this source to Music Assistant": "将来源的歌曲同步到 Music Assistant",
    "Sync Library Playlists from this source to Music Assistant": "将来源的播放列表同步到 Music Assistant",
    "Sync Library Podcasts from this source to Music Assistant": "将来源的播客同步到 Music Assistant",
    "Sync back library additions/removals": "同步音乐库的增删",
    "(2-way sync)": "（双向同步）",
    "Authenticate with Spotify": "通过 Spotify 认证",
    "This is an unofficial integration that is not affiliated with, supported by, or endorsed by the music service.": "这是一个非官方集成，与音乐服务无关，未获其支持或认可。",
    "It relies on interfaces that are not officially supported and may stop working at any time. Use of this provider may also be subject to the service's terms of use.": "依赖非官方接口，可能随时停止工作。使用此来源可能需遵守该服务的使用条款。",
    "You need to authenticate to Spotify. Click the authenticate button below to start the authentication process which will open in a new (popup) window, so make sure to disable any popup blockers.": "你需要认证 Spotify。点击下方认证按钮启动认证流程，该流程将在新窗口打开，请确保禁用弹出窗口拦截。",
    "Also make sure to perform this action from your local network.": "请确保在本地网络中执行此操作。",
]

fileprivate func localizedConfigLabel(_ text: String) -> String {
    if let zh = configLabelZH[text] { return zh }
    if let zh = configLabelZH[text.trimmingCharacters(in: .whitespaces).capitalized] { return zh }
    return text
}

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
                                Button("Reload Provider") {
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

    private func zzLabel(_ text: String) -> String { localizedConfigLabel(text) }
    private func zzDesc(_ text: String?) -> String? { text.flatMap { localizedConfigLabel($0) } ?? text }

    @ViewBuilder
    private func configField(for entry: ConfigEntry) -> some View {
        let label = zzLabel(entry.label)
        switch entry.type {
        case "boolean":
            Toggle(label, isOn: Binding(
                get: { (viewModel.editingValues[entry.key] as? Bool) ?? (entry.defaultValue?.boolValue ?? false) },
                set: { viewModel.editingValues[entry.key] = $0 }
            ))

        case "string", "secure_string":
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(.subheadline.weight(.medium))
                if entry.isSecure {
                    SecureField(label, text: Binding(
                        get: { viewModel.editingValues[entry.key] as? String ?? "" },
                        set: { viewModel.editingValues[entry.key] = $0 }
                    ))
                } else if let options = entry.options, !options.isEmpty {
                    Picker(label, selection: Binding(
                        get: { viewModel.editingValues[entry.key] as? String ?? (entry.defaultValue?.stringValue ?? "") },
                        set: { viewModel.editingValues[entry.key] = $0 }
                    )) {
                        ForEach(options, id: \.title) { option in
                            Text(option.title).tag(option.value.stringValue ?? "")
                        }
                    }
                } else {
                    TextField(label, text: Binding(
                        get: { viewModel.editingValues[entry.key] as? String ?? "" },
                        set: { viewModel.editingValues[entry.key] = $0 }
                    ))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                }
                if let desc = zzDesc(entry.description) {
                    Text(desc)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

        case "integer":
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
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
                    TextField(label, value: binding, format: .number)
                        .keyboardType(.numberPad)
                }
                if let desc = zzDesc(entry.description) {
                    Text(desc)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

        case "float":
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(.subheadline.weight(.medium))
                let binding = Binding(
                    get: { viewModel.editingValues[entry.key] as? Double ?? (entry.defaultValue?.doubleValue ?? 0.0) },
                    set: { viewModel.editingValues[entry.key] = $0 }
                )
                TextField(label, value: binding, format: .number)
                    .keyboardType(.decimalPad)
                if let desc = zzDesc(entry.description) {
                    Text(desc)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

        case "label":
            Section {
                Text(label)
                    .font(.body)
                if let desc = zzDesc(entry.description) {
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
                Text(label)
                    .font(.subheadline)
            }

        case "action":
            Button(entry.actionLabel ?? label) {
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
            Text(label)
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
