import Foundation
import Testing
@testable import Cliptate

@Suite("Microphone input feedback")
struct MicrophoneInputMonitorTests {
  @Test("Missing buffers and silent buffers produce different recovery hints")
  func missingAndSilentInput() {
    let start = Date(timeIntervalSince1970: 100)
    var monitor = MicrophoneInputMonitor()
    monitor.start(at: start)
    #expect(monitor.issue(at: start.addingTimeInterval(2)) == nil)
    #expect(monitor.issue(at: start.addingTimeInterval(3)) == .noInput)
    monitor.receive(level: 0, at: start.addingTimeInterval(3))
    #expect(monitor.issue(at: start.addingTimeInterval(3)) == .quietInput)
    monitor.receive(level: 0.3, at: start.addingTimeInterval(4))
    #expect(monitor.issue(at: start.addingTimeInterval(4)) == nil)
  }

  @Test("A stalled microphone is detected even after earlier speech")
  func stalledInputAndRestart() {
    let start = Date(timeIntervalSince1970: 100)
    var monitor = MicrophoneInputMonitor()
    monitor.start(at: start)
    monitor.receive(level: 0.4, at: start.addingTimeInterval(1))
    #expect(monitor.issue(at: start.addingTimeInterval(4)) == .noInput)
    monitor.receive(level: 0.4, at: start.addingTimeInterval(4))
    #expect(monitor.issue(at: start.addingTimeInterval(4)) == nil)
    monitor.start(at: start.addingTimeInterval(5))
    #expect(monitor.issue(at: start.addingTimeInterval(8)) == .noInput)
  }
}
