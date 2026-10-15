import Foundation
import Testing

import CliptateCore

@Suite("Development app isolation")
struct AppIdentityTests {
  @Test func storageAndMigrationKeepProductionDataSeparate() {
    let production = AppIdentity.production
    let development = AppIdentity(bundleIdentifier: "com.cliptate.dev")
    #expect(development == .development)
    #expect(production.rawValue == "com.voicepink.voicepinkpro")
    #expect(production.applicationSupportDirectory().lastPathComponent == "Cliptate")
    #expect(development.applicationSupportDirectory().lastPathComponent == "Cliptate Dev")
    #expect(production.applicationSupportDirectory() != development.applicationSupportDirectory())
    #expect(production.sandboxDataDirectoryNames == ["Cliptate", "VoiceFlowPro"])
    #expect(development.sandboxDataDirectoryNames == ["Cliptate Dev"])
    #expect(production.sandboxPreferencesMigrationMarker != development.sandboxPreferencesMigrationMarker)
  }

  @Test func cliLaunchCredentialsCannotCrossAppIdentities() throws {
    let endpoint = CLIEndpoint(identity: .development)
    let restored = try #require(CLIEndpoint(url: endpoint.url, identity: .development))
    #expect(restored.id == endpoint.id)
    #expect(restored.proof(for: "server") == endpoint.proof(for: "server"))
    #expect(CLIEndpoint(url: endpoint.url, identity: .production) == nil)
    #expect(CLIEndpoint(url: CLIEndpoint(identity: .production).url, identity: .development) == nil)
  }

  @Test func cliPortsDoNotOverlapAndProductionProtocolStaysCompatible() {
    for userID in [UInt32(0), 501, 15999, 16000, UInt32.max] {
      #expect(AppIdentity.production.cliPort(userID: userID) == UInt16(49152 + userID % 16000))
      #expect(AppIdentity.development.cliPort(userID: userID) < 49152)
      #expect(AppIdentity.production.cliPort(userID: userID) >= 49152)
    }
  }
}
