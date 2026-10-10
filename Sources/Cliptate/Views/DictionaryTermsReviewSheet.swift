import SwiftUI

// MARK: - Dictionary Terms Review Sheet

struct DictionaryTermsReviewSheet: View {
  let terms: [String]
  let existingTerms: Set<String>
  let onAdd: ([String]) -> Void
  let onDismiss: () -> Void

  @State private var selected: Set<String>

  init(
    terms: [String],
    existingTerms: Set<String>,
    onAdd: @escaping ([String]) -> Void,
    onDismiss: @escaping () -> Void
  ) {
    self.terms = terms
    self.existingTerms = existingTerms
    self.onAdd = onAdd
    self.onDismiss = onDismiss
    _selected = State(
      initialValue: Set(terms.filter { !existingTerms.contains($0.lowercased()) }))
  }

  private func isExisting(_ term: String) -> Bool {
    existingTerms.contains(term.lowercased())
  }

  private var newTermCount: Int { selected.filter { !isExisting($0) }.count }
  private var alreadyCount: Int { terms.filter { isExisting($0) }.count }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      // Header
      HStack(alignment: .center, spacing: 12) {
        Image(systemName: "text.badge.plus")
          .font(.title2)
          .foregroundStyle(Color.accentColor)
        VStack(alignment: .leading, spacing: 3) {
          Text("Dictionary Suggestions")
            .font(.headline)
          Text(
            alreadyCount > 0
              ? String(
                localized:
                  "\(terms.count) terms found · \(alreadyCount) already in dictionary",
                comment:
                  "History: dictionary analysis subtitle with already-added count; first %lld is total, second %lld is existing"
              )
              : String(
                localized: "\(terms.count) terms found",
                comment: "History: dictionary analysis subtitle; %lld is total term count"
              )
          )
          .font(.caption)
          .foregroundStyle(.secondary)
        }
        Spacer()
        Button(action: onDismiss) {
          Image(systemName: "xmark.circle.fill")
            .font(.title3)
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
          String(localized: "Dismiss", comment: "Accessibility: dismiss sheet button"))
      }
      .padding(16)

      Divider()

      // Terms list
      if terms.isEmpty {
        VStack(spacing: 10) {
          Image(systemName: "text.badge.xmark")
            .font(.system(size: 36, weight: .light))
            .foregroundStyle(.secondary)
          Text("No terms found")
            .font(.headline)
            .foregroundStyle(.secondary)
          Text("Try including more transcript sessions or using a different AI model.")
            .font(.caption)
            .foregroundStyle(.tertiary)
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
      } else {
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 2) {
            ForEach(terms, id: \.self) { term in
              let existing = isExisting(term)
              HStack(spacing: 10) {
                Button {
                  guard !existing else { return }
                  if selected.contains(term) { selected.remove(term) }
                  else { selected.insert(term) }
                } label: {
                  Image(
                    systemName: existing
                      ? "checkmark.circle.fill"
                      : (selected.contains(term) ? "checkmark.circle.fill" : "circle")
                  )
                  .font(.system(size: 16))
                  .foregroundStyle(
                    existing
                      ? Color.secondary
                      : (selected.contains(term) ? Color.accentColor : Color.secondary))
                }
                .buttonStyle(.plain)
                .disabled(existing)

                Text(term)
                  .font(.system(size: 13))
                  .foregroundStyle(existing ? Color.secondary : Color.primary)

                if existing {
                  Text("Already added")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.secondary.opacity(0.10)))
                }
                Spacer()
              }
              .padding(.horizontal, 16)
              .padding(.vertical, 7)
              .contentShape(Rectangle())
              .onTapGesture {
                guard !existing else { return }
                if selected.contains(term) { selected.remove(term) }
                else { selected.insert(term) }
              }
            }
          }
          .padding(.vertical, 6)
        }
        .background(Color(NSColor.controlBackgroundColor))
      }

      Divider()

      // Footer
      HStack {
        Button(action: onDismiss) {
          Text("Cancel")
        }
        .buttonStyle(.bordered)

        Spacer()

        Button {
          onAdd(Array(selected.filter { !isExisting($0) }))
        } label: {
          Text(
            newTermCount == 1
              ? String(
                localized: "Add 1 Term",
                comment: "History: add single dictionary term button")
              : String(
                localized: "Add \(newTermCount) Terms",
                comment:
                  "History: add multiple dictionary terms button; %lld is the count of terms to add"
              )
          )
        }
        .buttonStyle(.borderedProminent)
        .disabled(newTermCount == 0)
      }
      .padding(16)
    }
    .frame(width: 440, height: 480)
  }
}
