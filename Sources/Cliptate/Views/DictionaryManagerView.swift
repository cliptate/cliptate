import SwiftUI

struct DictionaryManagerView: View {
    @EnvironmentObject private var config: AppConfiguration
    @State private var editorText: String = ""
    @State private var isFocused = false

    private var normalizedEditorEntries: [String] {
        AppConfiguration.normalizeDictionaryEntries(
            editorText.components(separatedBy: CharacterSet.newlines)
        )
    }

    private var activeEntries: [String] {
        config.voiceToTextCustomDictionary
    }

    var body: some View {
        VStack(spacing: 0) {
            AppPageHeader {
                headerBar
            }
            HSplitView {
                editorPanel
                    .frame(minWidth: 260, idealWidth: 340, maxWidth: 480)
                tagsPanel
                    .frame(minWidth: 260, maxWidth: .infinity)
            }
        }
        .background(AppSurface.pageBackground)
        .navigationTitle("Dictionary")
        .onAppear(perform: loadFromConfiguration)
        .onChange(of: config.voiceToTextCustomDictionary) { _, entries in
            // Keep an open editor in sync with CLI mutations without discarding its formatting.
            if normalizedEditorEntries != entries {
                editorText = entries.joined(separator: "\n")
            }
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Custom Dictionary")
                    .font(.title2.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Text("Words and phrases that guide transcription accuracy")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            statsRow
        }
    }

    private var statsRow: some View {
        HStack(spacing: 12) {
            statPill(
                label: "\(activeEntries.count)",
                icon: "text.badge.checkmark",
                tint: .green,
                subtitle: "active"
            )
            statPill(
                label: "\(normalizedEditorEntries.count)",
                icon: "pencil",
                tint: .accentColor,
                subtitle: "pending"
            )
        }
    }

    private func statPill(label: String, icon: String, tint: Color, subtitle: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 0) {
                Text(label)
                    .font(.callout.weight(.bold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(tint.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Editor panel

    private var editorPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            editorPanelHeader
            Divider()
            TextEditor(text: $editorText)
                .font(.body.monospaced())
                .scrollContentBackground(.hidden)
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AppSurface.inputBackground)
                .onChange(of: editorText) { _, _ in saveChanges() }
        }
        .background(AppSurface.cardBackground)
    }

    private var editorPanelHeader: some View {
        HStack {
            Label("Editor", systemImage: "pencil.line")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Text("One entry per line")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Tags panel

    private var tagsPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            tagsPanelHeader
            Divider()
            if activeEntries.isEmpty {
                tagsEmptyState
            } else {
                ScrollView {
                    tagsGrid
                        .padding(16)
                }
            }
        }
        .background(AppSurface.pageBackground)
    }

    private var tagsPanelHeader: some View {
        HStack {
            Label("Active Entries", systemImage: "checkmark.circle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.green)
            Spacer()
            if !activeEntries.isEmpty {
                Button {
                    editorText = ""
                    saveChanges()
                } label: {
                    Label("Clear All", systemImage: "trash")
                        .font(.caption2)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.red)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var tagsGrid: some View {
        DictionaryTagsLayout(spacing: 8) {
            ForEach(activeEntries, id: \.self) { entry in
                entryChip(entry)
            }
        }
    }

    private func entryChip(_ entry: String) -> some View {
        HStack(spacing: 4) {
            Text(entry)
                .font(.callout)
                .lineLimit(1)
            Button {
                removeEntry(entry)
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.accentColor.opacity(0.10))
        .foregroundStyle(.primary)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.accentColor.opacity(0.20), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var tagsEmptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "text.badge.plus")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text("No entries yet")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Type vocabulary in the editor on the left, one word or phrase per line.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 220)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Logic

    private func loadFromConfiguration() {
        editorText = config.voiceToTextCustomDictionary.joined(separator: "\n")
    }

    private func saveChanges() {
        config.replaceDictionaryEntries(with: normalizedEditorEntries)
    }

    private func removeEntry(_ entry: String) {
        var current = config.voiceToTextCustomDictionary
        current.removeAll { $0 == entry }
        config.replaceDictionaryEntries(with: current)
        editorText = current.joined(separator: "\n")
    }
}

// MARK: - Tag wrap layout

private struct DictionaryTagsLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var height: CGFloat = 0
        var x: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width && x > 0 {
                height += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        height += rowHeight
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

#Preview {
    DictionaryManagerView()
        .environmentObject(AppConfiguration.shared)
        .frame(width: 800, height: 500)
}
