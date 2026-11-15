import SwiftUI

extension Color {
    static let appAccent = Color(red: 244 / 255, green: 89 / 255, blue: 203 / 255)
}

struct BarView: View {
    @ObservedObject var vm: BarViewModel
    @ObservedObject var store: ProfileStore
    var onEditProfiles: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                ZStack(alignment: .topLeading) {
                    if vm.input.isEmpty {
                        Text("Type or paste a message to fix")
                            .foregroundStyle(.secondary)
                            .allowsHitTesting(false)
                    }
                    GrowingTextView(
                        text: $vm.input, height: $vm.inputHeight, focusTick: vm.openCount,
                        onSubmit: { vm.fix() })
                }
                .frame(height: vm.inputHeight)
                if !vm.input.isEmpty {
                    Button { vm.clear() } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help("Clear")
                }
                styleMenu
                sendButton
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            if showsStatus {
                Divider()
                statusView.padding(14)
            }
        }
        .frame(width: 720)
        .tint(Color.appAccent)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.08)))
    }

    private var styleLabel: String {
        if vm.selection == BarViewModel.auto { return "Auto" }
        return store.profile(id: vm.selection)?.name ?? "Auto"
    }

    /// Grey line under "Auto" showing which profile was picked.
    private var autoCaption: String? {
        guard vm.selection == BarViewModel.auto else { return nil }
        return vm.autoLabel ?? (vm.isWorking || vm.classifying ? "Detecting…" : nil)
    }

    private var styleMenu: some View {
        Menu {
            Picker("Style", selection: $vm.selection) {
                Text("Auto").tag(BarViewModel.auto)
                ForEach(store.profiles) { Text($0.name).tag($0.id) }
            }
            .pickerStyle(.inline)
            Divider()
            Button("Edit profiles…", action: onEditProfiles)
        } label: {
            Text(styleLabel)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .overlay(alignment: .bottom) {
            if let caption = autoCaption {
                Text(caption)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize()
                    .offset(y: 14)
            }
        }
    }

    private var sendButton: some View {
        Button {
            if vm.isWorking { vm.cancel() } else { vm.fix() }
        } label: {
            Image(systemName: vm.isWorking ? "stop.fill" : "arrow.up")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.appAccent))
        }
        .buttonStyle(.plain)
        .help(vm.isWorking ? "Cancel" : "Fix (Return)")
    }

    private var showsStatus: Bool {
        if case .idle = vm.state { return false }
        return true
    }

    @ViewBuilder private var statusView: some View {
        switch vm.state {
        case .idle:
            EmptyView()
        case .gettingReady:
            progress("Getting ready…")
        case .rewriting:
            progress("Rewriting…")
        case .failed(let message):
            Text(message).foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .done(let r):
            ResultView(result: r, vm: vm)
        }
    }

    private func progress(_ text: String) -> some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(text).foregroundStyle(.secondary)
            Spacer()
        }
    }
}

struct ResultView: View {
    let result: FixResult
    @ObservedObject var vm: BarViewModel

    var body: some View {
        if result.unchanged {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text("No changes needed").font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(result.flags, id: \.self) {
                    Label($0, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                }
                HStack(alignment: .top, spacing: 10) {
                    Text(TextDiff.attributed(old: result.original, new: result.revised))
                        .textSelection(.enabled)
                        .lineLimit(24)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button { vm.copyRevised() } label: {
                        Image(systemName: vm.justCopied ? "checkmark" : "square.on.square")
                    }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.appAccent)
                        .keyboardShortcut("c", modifiers: [.command, .shift])
                        .help("Copy revised text (Shift+Cmd+C)")
                }
            }
        }
    }
}

final class ProfileSelection: ObservableObject {
    @Published var id: String?
}

/// Label and help text on the left, control on the right, hairline below.
private struct SettingRow<Control: View>: View {
    let title: String
    let detail: String
    @ViewBuilder var control: () -> Control

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 24) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 14, weight: .medium))
                    Text(detail).font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                control()
            }
            .padding(.vertical, 14)
            Divider()
        }
    }
}

private extension View {
    func fieldBackground() -> some View {
        self.padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.08)))
    }
}

struct SettingsView: View {
    static let modelsPage = "models"

    @ObservedObject var store: ProfileStore
    @ObservedObject var settings: ModelSettings
    @ObservedObject var selection: ProfileSelection

    private var index: Int? {
        store.profiles.firstIndex { $0.id == selection.id }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 240)
                .background(Color.primary.opacity(0.03))
            Divider()
            detail
        }
        .frame(width: 900, height: 620)
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(Color.appAccent)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("General")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 44)
                .padding(.bottom, 4)
            sidebarRow(id: Self.modelsPage, icon: "cpu", title: "Models")
            Text("Profiles")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 14)
                .padding(.bottom, 4)
            ForEach(store.profiles) { p in
                sidebarRow(id: p.id, icon: "text.bubble", title: p.name)
            }
            Spacer()
            Divider().padding(.vertical, 6)
            Button {
                let p = Profile(
                    id: UUID().uuidString, name: "New profile", style: "message",
                    prompt: Profile.basePrompt)
                store.profiles.append(p)
                selection.id = p.id
            } label: {
                Label("Add profile", systemImage: "plus")
                    .padding(.horizontal, 12).padding(.vertical, 6)
            }
            .buttonStyle(.plain)
            Button {
                store.resetToDefaults()
                selection.id = store.profiles.first?.id
            } label: {
                Label("Reset to defaults", systemImage: "arrow.counterclockwise")
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(10)
    }

    private func sidebarRow(id: String, icon: String, title: String) -> some View {
        Button { selection.id = id } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .frame(width: 18)
                    .foregroundStyle(selection.id == id ? Color.appAccent : .secondary)
                Text(title).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(selection.id == id ? Color.primary.opacity(0.1) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var modelsPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Models")
                    .font(.system(size: 20, weight: .semibold))
                    .padding(.bottom, 10)
                SettingRow(
                    title: "Rewriting model",
                    detail: "Any text model installed in Ollama. Switching unloads the previous one. A bigger model follows your prompt better but uses more RAM and is slower."
                ) {
                    Picker("", selection: $settings.rewriterModel) {
                        ForEach(settings.modelOptions, id: \.self) {
                            Text(settings.isMissing($0) ? "\($0) (not installed)" : $0).tag($0)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 200)
                }
                SettingRow(
                    title: "Unload after idle",
                    detail: "How long Ollama keeps the rewriting model in memory after you last used it. Longer makes the next fix faster, shorter frees RAM sooner."
                ) {
                    Picker("", selection: $settings.idleTimeout) {
                        ForEach(settings.idleOptions, id: \.value) { Text($0.title).tag($0.value) }
                    }
                    .labelsHidden()
                    .frame(width: 160)
                }
                SettingRow(
                    title: "Context window",
                    detail: "How much text the rewriting model can hold at once. It also sets the longest message you can fix. Larger uses more RAM, and changing it reloads the model on the next fix."
                ) {
                    Picker("", selection: $settings.numCtx) {
                        ForEach(ModelSettings.contextChoices, id: \.value) { Text($0.title).tag($0.value) }
                    }
                    .labelsHidden()
                    .frame(width: 260)
                }
                SettingRow(
                    title: "Warm up when the bar opens",
                    detail: "Loads the rewriting model in the background as soon as the bar opens. If off, it loads the first time you press Fix."
                ) {
                    Toggle("", isOn: $settings.warmOnOpen).labelsHidden().toggleStyle(.switch)
                }
                SettingRow(
                    title: "Unload when macOS is low on memory",
                    detail: "Frees the rewriting model when macOS reports memory pressure, after any running rewrite finishes. It stays unloaded until pressure eases and you ask for a fix."
                ) {
                    Toggle("", isOn: $settings.unloadOnPressure).labelsHidden().toggleStyle(.switch)
                }
                SettingRow(
                    title: "Unload when Tidy Fixer quits",
                    detail: "Off by default, because the idle timeout already frees the model and another app may be using it."
                ) {
                    Toggle("", isOn: $settings.unloadOnQuit).labelsHidden().toggleStyle(.switch)
                }
                Text("The style model (Tev1) is shared with other apps, so Tidy Fixer never unloads it. Ollama's own timeout applies to it.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 14)
            }
            .padding(.horizontal, 28)
            .padding(.top, 40)
            .padding(.bottom, 24)
        }
        .task {
            while !Task.isCancelled {
                await settings.refreshModels()
                try? await Task.sleep(nanoseconds: 4_000_000_000)
            }
        }
    }

    @ViewBuilder private var detail: some View {
        if selection.id == Self.modelsPage {
            modelsPane
        } else if let i = index {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(store.profiles[i].name)
                        .font(.system(size: 20, weight: .semibold))
                        .padding(.bottom, 10)
                    SettingRow(
                        title: "Name", detail: "Shown in the style menu under the bar."
                    ) {
                        TextField("Name", text: $store.profiles[i].name)
                            .textFieldStyle(.plain)
                            .fieldBackground()
                            .frame(width: 280)
                    }
                    SettingRow(
                        title: "Style phrase",
                        detail: "Describe the kind of message, for example \"casual message to a coworker\". Tev1 reads it to decide which profile fits in Auto, and it is added above your message as \"Style: …\" for the rewriting model."
                    ) {
                        TextField("For example: casual message to a coworker", text: $store.profiles[i].style)
                            .textFieldStyle(.plain)
                            .fieldBackground()
                            .frame(width: 280)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("System prompt").font(.system(size: 14, weight: .medium))
                        Text(
                            "Instructions for the rewriting model. Keep the line about the <text> tags, or the model may treat your message as instructions."
                        )
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        TextEditor(text: $store.profiles[i].prompt)
                            .font(.system(size: 12, design: .monospaced))
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 260)
                            .fieldBackground()
                    }
                    .padding(.vertical, 14)
                    HStack {
                        Spacer()
                        Button(role: .destructive) {
                            store.profiles.remove(at: i)
                            selection.id = store.profiles.first?.id
                        } label: {
                            Label("Delete profile", systemImage: "trash")
                        }
                        .disabled(store.profiles.count <= 1)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, 40)
                .padding(.bottom, 24)
            }
        } else {
            Text("Select a profile")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
