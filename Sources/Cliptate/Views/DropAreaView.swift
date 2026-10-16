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
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var isTargeted = false
  @State private var isHovered = false

  var body: some View {
    let isHighlighted = isTargeted || (style == .hero && isHovered)

    VStack(spacing: style == .hero ? 14 : 10) {
      Image(systemName: "square.and.arrow.down.on.square")
        .font(.system(size: style == .hero ? 34 : 22, weight: .medium))
        .foregroundStyle(isHighlighted ? Color.accentColor : Color.secondary)
      Text(title)
        .font(style == .hero ? .headline : .caption)
        .foregroundColor(.secondary)
      if style == .hero {
        Text("Or click to choose one or more videos")
          .font(.callout)
          .foregroundStyle(.tertiary)
      }
    }
    .frame(maxWidth: .infinity)
    .frame(minHeight: style == .hero ? 180 : nil)
    .padding(style == .hero ? 24 : 12)
    .background(
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .strokeBorder(
          isHighlighted ? Color.accentColor : Color.secondary.opacity(0.3),
          style: StrokeStyle(lineWidth: 1, dash: [5])
        )
        .background(
          (isHighlighted ? AppSurface.selectedFill : AppSurface.settingsBackground)
            .clipShape(
              RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
        )
    )
    .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    .onTapGesture {
      onTap?()
    }
    .accessibilityElement(children: .combine)
    .accessibilityAddTraits(onTap == nil ? [] : [.isButton])
    .accessibilityAction { onTap?() }
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
    .animation(reduceMotion ? nil : .easeInOut(duration: 0.16), value: isHighlighted)
  }
}
