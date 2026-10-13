import Foundation
import Sparkle

/// Display metadata from the update Sparkle selected; discovery is not installation validation.
struct AppUpdateDetails: Sendable {
  let version: String
  let contentLength: UInt64
  let releaseDate: Date?
  let releaseNotesURL: URL?
  let informationURL: URL?
  let isInformationOnly: Bool

  init(
    version: String, contentLength: UInt64, releaseDate: Date?, releaseNotesURL: URL?,
    informationURL: URL?, isInformationOnly: Bool
  ) {
    self.version = version
    self.contentLength = contentLength
    self.releaseDate = releaseDate
    self.releaseNotesURL = releaseNotesURL
    self.informationURL = informationURL
    self.isInformationOnly = isInformationOnly
  }

  init(item: SUAppcastItem) {
    self.init(
      version: item.displayVersionString, contentLength: item.contentLength,
      releaseDate: item.date, releaseNotesURL: item.releaseNotesURL,
      informationURL: item.infoURL, isInformationOnly: item.isInformationOnlyUpdate)
  }

  var notesURL: URL {
    releaseNotesURL ?? informationURL ?? URL(
      string: "https://github.com/cliptate/cliptate/releases")!
  }

  var formattedSize: String? {
    guard contentLength > 0, let size = Int64(exactly: contentLength) else { return nil }
    return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
  }
}

/// Holds one actionable Sparkle update session until the user chooses or it is invalidated.
@MainActor
struct AppUpdateOffer: Identifiable {
  let id = UUID()
  let details: AppUpdateDetails
  let prompt: AppUpdateInstallationPrompt

  init(details: AppUpdateDetails, reply: @escaping (SPUUserUpdateChoice) -> Void) {
    self.details = details
    prompt = AppUpdateInstallationPrompt { choice in
      // An informational update can open its website, but must never be installed by Sparkle.
      reply(details.isInformationOnly && choice == .install ? .dismiss : choice)
    }
  }
}
