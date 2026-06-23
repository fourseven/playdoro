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
                mainContent
            case .eqPicker:
                EQPickerView(appState: appState, onBack: { route = .main })
            }
            #else
            mainContent
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

    private var mainContent: some View {
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

                eqSection

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

    private var eqSection: some View {
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

            #if os(iOS)
            NavigationLink(value: Route.eqPicker) {
                eqPickerEntryLabel
            }
            .buttonStyle(.plain)
            .disabled(!appState.eqEnabled)
            #else
            Button {
                route = .eqPicker
            } label: {
                eqPickerEntryLabel
            }
            .buttonStyle(.plain)
            .disabled(!appState.eqEnabled)
            #endif
        }
    }

    private var eqPickerEntryLabel: some View {
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
}
