import SwiftUI

fileprivate let configKeyZH: [String: String] = [
    "log_level": "日志级别",
    "global": "全局",
    "debug": "调试",
    "verbose": "详细",
    "warning": "警告",
    "info": "信息",
    "error": "错误",
    "username": "用户名",
    "password": "密码",
    "email": "邮箱",
    "host": "主机地址",
    "port": "端口",
    "quality": "音质",
    "language": "语言",
    "country_code": "国家代码",
    "region": "地区",
    "path": "路径",
    "token": "令牌",
    "client_id": "客户端 ID",
    "client_secret": "客户端密钥",
    "access_token": "访问令牌",
    "server": "服务器地址",
    "rate_limit": "请求频率",
    "update_interval": "更新间隔",
    "base_url": "基础地址",
    "api_base_url": "接口地址",
    "api_url": "接口地址",
    "database_path": "数据库路径",
    "audio_format": "音频格式",
    "sample_rate": "采样率",
    "device_name": "设备名称",
    "device_id": "设备 ID",
    "http_port": "HTTP 端口",
    "sync_interval": "同步间隔",
    "max_retries": "最大重试",
    "timeout": "超时",
    "cookie": "登录 Cookie",
    "login_cookie": "登录 Cookie",
    "po_token_server_url": "PO Token 服务器地址",
    "po_token_url": "PO Token 服务器地址",
    "uid": "用户 ID",
    "qr_key": "二维码 Key",
    "qr_page_url": "二维码页面地址",
    "library_sync_artists": "将来源的艺人同步到 Music Assistant",
    "sync_artists": "将来源的艺人同步到 Music Assistant",
    "library_sync_albums": "将来源的专辑同步到 Music Assistant",
    "sync_albums": "将来源的专辑同步到 Music Assistant",
    "library_sync_tracks": "将来源的歌曲同步到 Music Assistant",
    "sync_tracks": "将来源的歌曲同步到 Music Assistant",
    "library_sync_playlists": "将来源的播放列表同步到 Music Assistant",
    "sync_playlists": "将来源的播放列表同步到 Music Assistant",
    "library_sync_podcasts": "将来源的播客同步到 Music Assistant",
    "sync_podcasts": "将来源的播客同步到 Music Assistant",
    "library_sync_back": "同步增删",
    "sync_adjust": "同步增删",
    "unofficial_provider_note": "此为第三方集成，非官方支持，可能随时失效。使用需遵守服务条款。",
    "library_sync_deletions": "同步删除",
    "two_way_sync": "双向同步",
    "start_qr_auth": "开始认证",
    "qr_login": "二维码登录",
    "qq_login": "QQ 登录",
    "wechat_login": "微信登录",
    "authenticate": "认证",
    "enabled": "启用",
]

fileprivate func localizedConfigText(_ key: String, _ text: String) -> String {
    if let zh = configKeyZH[key] { return zh }
    if let zh = configKeyZH[key.lowercased()] { return zh }
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

    private func zzLabel(_ key: String, _ text: String) -> String { localizedConfigText(key, text) }
    private func zzDesc(_ key: String, _ text: String?) -> String? { text.flatMap { localizedConfigText(key, $0) } ?? text }

    @ViewBuilder
    private func configField(for entry: ConfigEntry) -> some View {
        let label = zzLabel(entry.key, entry.label)
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
                            Text(localizedConfigText(option.title, option.title)).tag(option.value.stringValue ?? "")
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
                if let desc = zzDesc(entry.key, entry.description) {
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
                if let desc = zzDesc(entry.key, entry.description) {
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
                if let desc = zzDesc(entry.key, entry.description) {
                    Text(desc)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

        case "label":
            Section {
                Text(label)
                    .font(.body)
                if let desc = zzDesc(entry.key, entry.description) {
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
                Task { await handleAction(entry) }
            }

        default:
            Text(label)
        }
    }

    private func handleAction(_ entry: ConfigEntry) async {
        let domain: String
        let instanceId: String?
        if let config = config {
            domain = config.domain
            instanceId = config.instanceId
        } else if let manifest = manifest {
            domain = manifest.domain
            instanceId = nil
        } else {
            return
        }
        let sessionId = UUID().uuidString
        var values = viewModel.editingValues
        values["session_id"] = sessionId

        viewModel.isSaving = true
        var observer: NSObjectProtocol?
        observer = NotificationCenter.default.addObserver(forName: .authSession, object: nil, queue: .main) { n in
            guard let sid = n.userInfo?["session_id"] as? String, sid == sessionId,
                  let urlString = n.userInfo?["auth_url"] as? String,
                  let url = URL(string: urlString) else { return }
            UIApplication.shared.open(url)
        }

        defer {
            if let o = observer { NotificationCenter.default.removeObserver(o) }
            viewModel.isSaving = false
        }

        let entries = try? await XonoraClient.shared.getProviderConfigEntries(
            domain: domain,
            instanceId: instanceId,
            action: entry.action,
            values: values,
            timeout: 90
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
