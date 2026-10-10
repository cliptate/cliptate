import Foundation

@MainActor
final class SecurityScopedURLAccessManager: ObservableObject {
        private var activeURLs: Set<URL> = []

        func startAccess(for url: URL) {
            guard !activeURLs.contains(url) else { return }
            if url.startAccessingSecurityScopedResource() {
                activeURLs.insert(url)
            }
        }

        func stopAccess(for url: URL) {
            guard activeURLs.contains(url) else { return }
            url.stopAccessingSecurityScopedResource()
            activeURLs.remove(url)
        }

        func sync(with urls: [URL]) {
            let incoming = Set(urls)
            for url in incoming where !activeURLs.contains(url) {
                startAccess(for: url)
            }

            let stale = activeURLs.filter { !incoming.contains($0) }
            for url in stale {
                stopAccess(for: url)
            }
        }

        func revokeAll() {
            for url in activeURLs {
                url.stopAccessingSecurityScopedResource()
            }
            activeURLs.removeAll()
        }

        @MainActor deinit {
            revokeAll()
        }
    }
