import SwiftUI

/// Searchable picker for the bundled EQ preset catalog.
///
/// Renders inline inside `SettingsView` (the macOS menu-bar popover is too
/// narrow to host a sheet, so we swap content rather than push).
struct EQPickerView: View {
    @ObservedObject var appState: AppState
    let onBack: () -> Void

    @State private var searchText = ""
    @State private var authorFilter: String? = nil

    private let authors: [String] = EQPreset.byAuthor.keys.sorted()

    var body: some View {
        VStack(spacing: 10) {
            header

            searchBar

            authorScroller

            Divider()

            list
        }
    }

    // MARK: - Subviews

    private var header: some View {
        HStack(spacing: 8) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")

            Text("EQ Presets")
                .font(.headline)
            Spacer()
            Text("\(filteredPresets.count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search headphones…", text: $searchText)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .submitLabel(.done)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var authorScroller: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                chip(title: "All", selected: authorFilter == nil) { authorFilter = nil }
                ForEach(authors, id: \.self) { author in
                    chip(title: author, selected: authorFilter == author) {
                        authorFilter = authorFilter == author ? nil : author
                    }
                }
            }
        }
    }

    private func chip(title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(selected ? .semibold : .regular))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    selected ? Theme.accent.opacity(0.85) : Color.secondary.opacity(0.15),
                    in: Capsule()
                )
                .foregroundStyle(selected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(filteredPresets) { preset in
                    row(for: preset)
                }
            }
            .padding(.horizontal, 2)
            .padding(.bottom, 8)
        }
        .frame(minHeight: 240)
    }

    private func row(for preset: EQPreset) -> some View {
        let isSelected = preset.id == appState.currentEQPreset.id
        return Button {
            appState.applyEQ(preset: preset)
            onBack()
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(preset.name)
                        .font(.subheadline.weight(isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? Theme.accent : .primary)
                        .lineLimit(1)
                    if !preset.author.isEmpty {
                        Text("\(preset.author) · \(preset.category)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.accent)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Filtering

    private var filteredPresets: [EQPreset] {
        var result = EQPreset.all
        if let authorFilter {
            result = result.filter { $0.author == authorFilter }
        }
        let query = searchText.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty {
            let lowered = query.lowercased()
            result = result.filter { preset in
                preset.name.lowercased().contains(lowered)
                    || preset.author.lowercased().contains(lowered)
                    || preset.category.lowercased().contains(lowered)
            }
        }
        return result
    }
}
