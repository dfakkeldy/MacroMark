import SwiftUI
import MacroMarkKit

struct DirectSendSettingsView: View {
    private struct HeaderField: Identifiable {
        let id = UUID()
        var name: String
        var value: String
    }

    @State private var mode: WatchDeliveryMode = .phone
    @State private var useGitHub = false
    @State private var owner = ""
    @State private var repository = ""
    @State private var branch = "main"
    @State private var folder = ""
    @State private var token = ""
    @State private var useWebhook = false
    @State private var webhookURL = ""
    @State private var headers = [HeaderField(name: "Authorization", value: "")]
    @State private var savedID: UUID?
    @State private var loaded = false
    @State private var loadFailed = false
    @State private var status: String?
    @State private var showingSignIn = false
    @AppStorage(DirectSendSharedState.configurationAcknowledgedKey) private var acknowledgedID = ""

    private var clientID: String {
        let value = Bundle.main.object(forInfoDictionaryKey: "MacroMarkGitHubClientID") as? String ?? ""
        return value.contains("$(") ? "" : value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        Form {
            Section {
                Picker("Watch text delivery", selection: $mode) {
                    Text("Phone and iCloud").tag(WatchDeliveryMode.phone)
                    Text("Direct Send").tag(WatchDeliveryMode.direct)
                }
            } footer: {
                Text("Direct Send delivers watch text over Wi-Fi or cellular after setup. Audio recordings always go to your iPhone for transcription. Direct text uses your captured wording without macro expansion.")
            }

            Section("GitHub") {
                Toggle("Send to a daily Markdown file", isOn: $useGitHub)
                if useGitHub {
                    TextField("Owner or organization", text: $owner)
                    TextField("Repository", text: $repository)
                    TextField("Branch", text: $branch)
                    TextField("Folder (optional)", text: $folder)
                    SecureField("Repository token", text: $token)
                    Text("Choose a token with Contents read and write access to this repository. GitHub files stay separate from iCloud daily notes.")
                        .font(.footnote).foregroundStyle(.secondary)
                    if !clientID.isEmpty {
                        Button("Sign in to GitHub") { showingSignIn = true }
                        Text("GitHub sign-in requests repository access. A repository token can limit access to one repository.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }

            Section("Webhook") {
                Toggle("Send to an HTTPS webhook", isOn: $useWebhook)
                if useWebhook {
                    TextField("HTTPS URL", text: $webhookURL)
                        .keyboardType(.URL)
                    ForEach($headers) { $header in
                        VStack(alignment: .leading) {
                            TextField("Header name", text: $header.name)
                            SecureField("Header value", text: $header.value)
                        }
                    }
                    .onDelete { headers.remove(atOffsets: $0) }
                    Button("Add header") { headers.append(HeaderField(name: "", value: "")) }
                    Text("For a bearer key, use Authorization as the header name and Bearer followed by your key as the value. Your webhook must deduplicate note IDs so retries do not repeat an action.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }

            Section {
                Button("Save and send setup to watch", action: save)
                    .disabled(!loaded || loadFailed)
                if let savedID {
                    Label(acknowledgedID == savedID.uuidString ? "Setup saved on watch" : "Waiting for watch to save setup",
                          systemImage: acknowledgedID == savedID.uuidString ? "checkmark.circle" : "clock")
                }
                if let status { Text(status).font(.footnote) }
            } footer: {
                Text("Changes apply after the watch saves setup. Queued notes keep their original destinations. Credentials are stored in each device's Keychain.")
            }
        }
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .navigationTitle("Direct Send")
        .task { load() }
        .sheet(isPresented: $showingSignIn) {
            GitHubSignInView(clientID: clientID) { token = $0 }
        }
    }

    private func load() {
        guard !loaded else { return }
        defer { loaded = true }
        do {
            guard let configuration = try DirectSendSettingsStore().current() else { return }
            savedID = configuration.id
            mode = configuration.mode
            if let github = configuration.github {
                useGitHub = true
                owner = github.owner
                repository = github.repository
                branch = github.branch
                folder = github.folder
                token = github.token
            }
            if let webhook = configuration.webhook {
                useWebhook = true
                webhookURL = webhook.url.absoluteString
                headers = webhook.headers.sorted { $0.key < $1.key }.map { HeaderField(name: $0.key, value: $0.value) }
            }
        } catch {
            loadFailed = true
            status = "Secure settings could not be read. Unlock your iPhone and reopen this screen."
        }
    }

    private func save() {
        do {
            let settings = DirectSendSettingsStore()
            let github = useGitHub ? GitHubDestination(owner: owner, repository: repository,
                branch: branch, folder: folder, token: token) : nil
            var webhook: WebhookDestination?
            if useWebhook {
                guard let url = URL(string: webhookURL.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                    throw DirectSendError.invalidConfiguration("Enter the HTTPS webhook URL.")
                }
                var values: [String: String] = [:]
                var names: Set<String> = []
                for header in headers where !header.value.isEmpty {
                    let name = header.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard names.insert(name.lowercased()).inserted else {
                        throw DirectSendError.invalidConfiguration("Each webhook header needs a unique name.")
                    }
                    values[name] = header.value
                }
                webhook = WebhookDestination(url: url, headers: values)
            }
            let configuration = try settings.makeConfiguration(mode: mode, github: github, webhook: webhook)
            try settings.save(configuration)
            savedID = configuration.id
            let sent = WatchConnectivityProvider.shared.updateDirectSendSettings()
            status = sent ? "Setup sent. Keep the watch unlocked until its confirmation arrives."
                : "Saved on iPhone. Setup will send when WatchConnectivity activates; you can also tap Save again."
        } catch {
            status = (error as? DirectSendError)?.errorDescription ?? "Setup could not be saved. Try again."
        }
    }
}

private struct GitHubSignInView: View {
    let clientID: String
    let onAuthorized: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var authorization: GitHubDeviceFlow.Authorization?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if let authorization {
                    Text("Enter this code on GitHub")
                    Text(authorization.userCode).font(.title.monospaced()).textSelection(.enabled)
                    Link("Open GitHub", destination: authorization.verificationURL)
                    ProgressView("Waiting for sign-in…")
                } else if let errorMessage {
                    Text(errorMessage)
                } else {
                    ProgressView("Requesting a sign-in code…")
                }
            }
            .padding()
            .navigationTitle("GitHub sign-in")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .task {
                do {
                    let flow = GitHubDeviceFlow(clientID: clientID)
                    let code = try await flow.start()
                    authorization = code
                    var interval = code.interval
                    while Date() < code.expiresAt {
                        try await Task.sleep(for: .seconds(interval))
                        switch try await flow.poll(code, interval: interval) {
                        case let .pending(next): interval = next
                        case let .authorized(token):
                            try Task.checkCancellation()
                            onAuthorized(token)
                            dismiss()
                            return
                        }
                    }
                    throw DirectSendError.authorizationExpired
                } catch is CancellationError {
                    return
                } catch {
                    authorization = nil
                    errorMessage = (error as? DirectSendError)?.errorDescription ?? "GitHub sign-in could not finish. Try again."
                }
            }
        }
    }
}
