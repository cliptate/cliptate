import Foundation
import Testing
@testable import Cliptate

@Suite("FCPXML Speed Decimal Parsing")
struct FCPXMLSpeedDecimalTests {

  @Test func parseDecimalSpeed_validDecimal() {
    #expect(FCPXMLSpeedParser.parse("1.5") == 1.5)
  }

  @Test func parseDecimalSpeed_integerInput() {
    #expect(FCPXMLSpeedParser.parse("2") == 2.0)
  }

  @Test func parseDecimalSpeed_trailingDot() {
    // During editing "1." should be treated as 1.0
    #expect(FCPXMLSpeedParser.parse("1.") == 1.0)
  }

  @Test func parseDecimalSpeed_leadingDot() {
    #expect(FCPXMLSpeedParser.parse(".5") == 0.5)
  }

  @Test func parseDecimalSpeed_emptyString() {
    #expect(FCPXMLSpeedParser.parse("") == nil)
  }

  @Test func parseDecimalSpeed_invalidText() {
    #expect(FCPXMLSpeedParser.parse("abc") == nil)
  }

  @Test func parseDecimalSpeed_commaDecimalSeparator() {
    // Support comma-based locale
    #expect(FCPXMLSpeedParser.parse("1,5") == 1.5)
  }

  @Test func clampSpeed_belowMinimum() {
    #expect(FCPXMLSpeedParser.clamp(0.05) == 0.1)
  }

  @Test func clampSpeed_aboveMaximum() {
    #expect(FCPXMLSpeedParser.clamp(15.0) == 10.0)
  }

  @Test func clampSpeed_withinRange() {
    #expect(FCPXMLSpeedParser.clamp(2.5) == 2.5)
  }

  @Test func clampFrameRate_belowMinimum() {
    #expect(FCPXMLSpeedParser.clampFrameRate(0) == 1.0)
  }

  @Test func clampFrameRate_aboveMaximum() {
    #expect(FCPXMLSpeedParser.clampFrameRate(500) == 240.0)
  }

  @Test func clampFrameRate_withinRange() {
    #expect(FCPXMLSpeedParser.clampFrameRate(29.97) == 29.97)
  }
}
