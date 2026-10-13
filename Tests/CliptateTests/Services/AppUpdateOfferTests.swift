import Foundation
import Sparkle
import Testing

@testable import Cliptate

@Suite("Available update reminder")
@MainActor
struct AppUpdateOfferTests {
  private let details = AppUpdateDetails(
    version: "0.65.1", contentLength: 77_600_000,
    releaseDate: Date(timeIntervalSince1970: 1_791_849_600),
    releaseNotesURL: URL(string: "https://example.com/notes"),
    informationURL: nil, isInformationOnly: false)

  @Test func discoveringAnUpdatePublishesAnActionableOffer() {
    var offered: AppUpdateOffer?
    var choices: [SPUUserUpdateChoice] = []
    let driver = AppUpdateUserDriver(hostBundle: .main) { offered = $0 }
    driver.offerUpdate(details: details) { choices.append($0) }
    #expect(offered?.details.version == "0.65.1")
    #expect(offered?.details.contentLength == 77_600_000)
    #expect(offered?.prompt.isActive == true)
    #expect(choices.isEmpty)
  }

  @Test(arguments: [SPUUserUpdateChoice.install, .skip, .dismiss])
  func respondingClearsTheReminderAndDeliversExactlyOneChoice(_ choice: SPUUserUpdateChoice) throws
  {
    var offered: AppUpdateOffer?
    var choices: [SPUUserUpdateChoice] = []
    let driver = AppUpdateUserDriver(hostBundle: .main) { offered = $0 }
    driver.offerUpdate(details: details) { choices.append($0) }
    let prompt = try #require(offered?.prompt)
    prompt.respond(choice)
    prompt.respond(.install)
    #expect(offered == nil)
    #expect(choices == [choice])
  }

  @Test func finishingTheSessionInvalidatesOldActions() throws {
    var offered: AppUpdateOffer?
    var choices: [SPUUserUpdateChoice] = []
    let driver = AppUpdateUserDriver(hostBundle: .main) { offered = $0 }
    driver.offerUpdate(details: details) { choices.append($0) }
    let prompt = try #require(offered?.prompt)
    driver.dismissUpdateInstallation()
    prompt.respond(.install)
    #expect(offered == nil)
    #expect(choices.isEmpty)
  }

  @Test func replacingAnOfferInvalidatesThePreviousReply() throws {
    var offered: AppUpdateOffer?
    var oldChoices: [SPUUserUpdateChoice] = []
    var newChoices: [SPUUserUpdateChoice] = []
    let driver = AppUpdateUserDriver(hostBundle: .main) { offered = $0 }
    driver.offerUpdate(details: details) { oldChoices.append($0) }
    let oldPrompt = try #require(offered?.prompt)
    driver.offerUpdate(details: details) { newChoices.append($0) }
    oldPrompt.respond(.skip)
    #expect(offered?.prompt.isActive == true)
    #expect(oldChoices.isEmpty)
    offered?.prompt.respond(.install)
    #expect(newChoices == [.install])
  }

  @Test func informationalUpdatesCannotStartInstallation() {
    var choices: [SPUUserUpdateChoice] = []
    let information = AppUpdateDetails(
      version: "2.0", contentLength: 0, releaseDate: nil, releaseNotesURL: nil,
      informationURL: URL(string: "https://example.com/upgrade"), isInformationOnly: true)
    let offer = AppUpdateOffer(details: information) { choices.append($0) }
    offer.prompt.respond(.install)
    #expect(choices == [.dismiss])
  }
}
