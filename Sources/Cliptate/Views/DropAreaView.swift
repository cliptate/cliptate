import SwiftUI
import UniformTypeIdentifiers

private final class URLCollector: @unchecked Sendable {
  private let queue = DispatchQueue(label: "com.voicepink.urlcollector")
  private var urls: [URL] = []

  func add(_ url: URL) {
    queue.sync {
      urls.append(url)
    }
  }

  func getURLs() -> [URL] {
    queue.sync {
      urls
    }
  }
}

struct DropAreaView: View {
  enum Style {
    case compact
    case hero
  }

  var title: String
  var onDropURLs: ([URL]) -> Void
  var style: Style = .compact
  var onTap: (() -> Void)? = nil
  @State private var isTargeted = false
  @State private var isHovered = false

  var body: some View {
    let isHighlighted = isTargeted || (style == .hero && isHovered)

    VStack(spacing: style == .hero ? 14 : 10) {
      Image(systemName: "square.and.arrow.down.on.square")
        .font(.system(size: style == .hero ? 34 : 22, weight: .medium))
        .foregroundColor(.accentColor)
      Text(title)
        .font(style == .hero ? .headline : .caption)
        .foregroundColor(.secondary)
      if style == .hero {
        Text("Drag and drop files or click to choose from Finder")
          .font(.callout)
          .foregroundStyle(.tertiary)
      }
    }
    .frame(maxWidth: .infinity)
    .frame(minHeight: style == .hero ? 260 : nil)
    .padding(style == .hero ? 40 : 12)
    .background(
      RoundedRectangle(cornerRadius: style == .hero ? 18 : 10, style: .continuous)
        .strokeBorder(
          isHighlighted ? Color.accentColor : Color.secondary.opacity(0.3),
          style: StrokeStyle(lineWidth: style == .hero ? 2 : 1, dash: [5])
        )
        .background(
          (isHighlighted ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.03))
            .clipShape(
              RoundedRectangle(cornerRadius: style == .hero ? 18 : 10, style: .continuous)
            )
        )
    )
    .shadow(
      color: isHighlighted ? Color.accentColor.opacity(0.18) : Color.clear,
      radius: style == .hero ? 16 : 0,
      y: style == .hero ? 8 : 0
    )
    .scaleEffect(style == .hero && isHighlighted ? 1.01 : 1)
    .contentShape(RoundedRectangle(cornerRadius: style == .hero ? 18 : 10, style: .continuous))
    .onTapGesture {
      onTap?()
    }
    .onHover { hovering in
      isHovered = hovering
    }
    .onDrop(
      of: [UTType.fileURL.identifier, UTType.movie.identifier, "public.file-url"],
      isTargeted: $isTargeted
    ) { providers in
      let collector = URLCollector()
      let group = DispatchGroup()

      for provider in providers {
        // Prefer to load directly as NSURL
        if provider.canLoadObject(ofClass: NSURL.self) {
          group.enter()
          _ = provider.loadObject(ofClass: NSURL.self) { obj, _ in
            if let nsurl = obj as? NSURL {
              let url = nsurl as URL
              collector.add(url)
            }
            group.leave()
          }
          continue
        }
        // Fallback: load by specifying type identifier
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
          group.enter()
          provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            if let url = item as? URL {
              collector.add(url)
            } else if let data = item as? Data, let str = String(data: data, encoding: .utf8),
              let u = URL(string: str.trimmingCharacters(in: .whitespacesAndNewlines))
            {
              collector.add(u)
            }
            group.leave()
          }
        } else if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
          group.enter()
          provider.loadItem(forTypeIdentifier: UTType.movie.identifier, options: nil) { item, _ in
            if let url = item as? URL {
              collector.add(url)
            }
            group.leave()
          }
        }
      }

      group.notify(queue: .main) {
        let collected = collector.getURLs()
        // Filter to keep only local file URLs
        let fileURLs = collected.filter { $0.isFileURL }
        if !fileURLs.isEmpty {
          onDropURLs(fileURLs)
        }
      }
      return true
    }
    .animation(.easeInOut(duration: 0.16), value: isHighlighted)
  }
}
