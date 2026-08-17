import SwiftUI

struct SettingsView: View {
    @ObservedObject var appState: AppState
    @State private var route: Route = .main

    enum Route: Hashable { case main, eqPicker }

    var body: some View {
        Group {
            #if os(macOS)
            switch route {
            case .main:
                macMainContent
            case .eqPicker:
                EQPickerView(appState: appState, onBack: { route = .main })
            }
            #else
            iosMainContent
                .navigationDestination(for: Route.self) { dest in
                    switch dest {
                    case .main: EmptyView()
                    case .eqPicker: EQPickerView(appState: appState)
                    }
                }
            #endif
        }
        .padding(.vertical, 4)
    }

    // MARK: - iOS

    #if os(iOS)
    private var iosMainContent: some View {
        Form {
            if appState.isConfigured {
                connectionSection
                if appState.supportsEQ {
                    audioSection
                }
                playbackSection
                Section {
                    Button("Disconnect", role: .destructive) {
                        appState.disconnect()
                    }
                }
            } else {
                Section {
                    VStack(spacing: 6) {
                        Text("Not connected")
                            .font(.headline)
                        Text("Connect to Plex from the main screen to get started.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
            }
        }
        .scrollDismissesKeyboard(.immediately)
    }

    private var connectionSection: some View {
        Section("Connection") {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Connected")
                        .font(.body.weight(.medium))
                    if !appState.serverName.isEmpty {
                        Text(appState.serverName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(appState.serverURL)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var audioSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { appState.eqEnabled },
                set: { appState.setEQEnabled($0) }
            )) {
                Label("Equalizer", systemImage: "waveform")
            }

            NavigationLink(value: Route.eqPicker) {
                presetLabel
            }
            .disabled(!appState.eqEnabled)
        } header: {
            Text("Audio")
        } footer: {
            Text(appState.eqEnabled
                ? "Applying \"\(appState.currentEQPreset.name)\" correction."
                : "Apply a headphone correction preset from the bundled AutoEQ catalog.")
        }
    }

    private var presetLabel: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(appState.currentEQPreset.name)
                .font(.body)
            if !appState.currentEQPreset.author.isEmpty {
                Text("\(appState.currentEQPreset.author) · \(appState.currentEQPreset.category)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var playbackSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label("Variety", systemImage: "shuffle")
                    Spacer()
                    Text("\(Int(appState.variety * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Slider(value: Binding(
                    get: { appState.variety },
                    set: { appState.setVariety($0) }
                ), in: 0...1)
                HStack {
                    Text("Similar")
                    Spacer()
                    Text("Eclectic")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        } header: {
            Text("Playback")
        } footer: {
            Text("How closely packed tracks stick to your seeds. Lower favours sonically similar matches; higher roams further afield.")
        }
    }
    #endif

    // MARK: - macOS

    #if os(macOS)
    private var macMainContent: some View {
        VStack(spacing: 12) {
            if appState.isConfigured {
                VStack(spacing: 6) {
                    Label("Connected", systemImage: "checkmark.circle.fill")
                        .foregroundColor(.green)

                    if !appState.serverName.isEmpty {
                        Text(appState.serverName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Text(appState.serverURL)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Divider()

                if appState.supportsEQ {
                    macEQSection

                    Divider()
                }

                macVarietySection

                Divider()

                Button("Disconnect", role: .destructive) {
                    appState.disconnect()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else {
                Text("Connect to Plex from the main screen")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var macEQSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "waveform")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text("Equalizer")
                    .font(.subheadline.weight(.medium))

                Spacer()

                Toggle("", isOn: Binding(
                    get: { appState.eqEnabled },
                    set: { appState.setEQEnabled($0) }
                ))
                .labelsHidden()
                .controlSize(.small)
            }

            Button {
                route = .eqPicker
            } label: {
                macPresetLabel
            }
            .buttonStyle(.plain)
            .disabled(!appState.eqEnabled)
        }
    }

    private var macPresetLabel: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(appState.currentEQPreset.name)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if !appState.currentEQPreset.author.isEmpty {
                    Text("\(appState.currentEQPreset.author) · \(appState.currentEQPreset.category)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }

    private var macVarietySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "shuffle")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("Variety")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text("\(Int(appState.variety * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
            }
            Slider(value: Binding(
                get: { appState.variety },
                set: { appState.setVariety($0) }
            ), in: 0...1)
            HStack {
                Text("Similar")
                Spacer()
                Text("Eclectic")
            }
            .font(.caption2)
            .foregroundColor(.secondary)
            Text("How closely packed tracks stick to your seeds.")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
    #endif
}
