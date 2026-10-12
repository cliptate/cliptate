import Sparkle
import Testing
@testable import Cliptate

@Suite("Verified update installation prompt")
@MainActor
struct AppUpdateInstallationPromptTests {
  @Test func installChoiceIsDeliveredOnlyOnce() {
    var choices: [SPUUserUpdateChoice] = []
    let prompt = AppUpdateInstallationPrompt { choices.append($0) }
    prompt.respond(.install)
    prompt.respond(.dismiss)
    #expect(choices == [.install])
    #expect(!prompt.isActive)
  }

  @Test func closingThePromptDefersInstallation() {
    var choices: [SPUUserUpdateChoice] = []
    let prompt = AppUpdateInstallationPrompt { choices.append($0) }
    prompt.respond(.dismiss)
    #expect(choices == [.dismiss])
    #expect(!prompt.isActive)
  }

  @Test func abortingTheUpdateDiscardsTheInstallationHandler() {
    var choices: [SPUUserUpdateChoice] = []
    let prompt = AppUpdateInstallationPrompt { choices.append($0) }
    prompt.invalidate()
    prompt.respond(.install)
    #expect(choices.isEmpty)
    #expect(!prompt.isActive)
  }
}
