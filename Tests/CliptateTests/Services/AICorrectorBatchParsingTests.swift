import Foundation
import Testing

@testable import Cliptate

@Suite("AICorrector diff-based correction parsing")
struct AICorrectorBatchParsingTests {

  // MARK: - New diff-based format

  @Test("parses JSON corrections array")
  func jsonCorrectionsArray() {
    let response = """
      [{"index":2,"original":"昌学卡","corrected":"畅学卡"}]
      """
    let corrections = AICorrector.parseCorrectionResponse(response)
    #expect(corrections.count == 1)
    #expect(corrections[0].index == 2)
    #expect(corrections[0].original == "昌学卡")
    #expect(corrections[0].corrected == "畅学卡")
  }

  @Test("parses multiple corrections")
  func multipleCorrections() {
    let response = """
      [
        {"index": 1, "original": "试错", "corrected": "思索"},
        {"index": 3, "original": "报名昌学", "corrected": "报名畅学"}
      ]
      """
    let corrections = AICorrector.parseCorrectionResponse(response)
    #expect(corrections.count == 2)
    #expect(corrections[0].index == 1)
    #expect(corrections[0].original == "试错")
    #expect(corrections[0].corrected == "思索")
    #expect(corrections[1].index == 3)
    #expect(corrections[1].original == "报名昌学")
    #expect(corrections[1].corrected == "报名畅学")
  }

  @Test("returns empty array when no corrections needed")
  func noCorrections() {
    let response = "[]"
    let corrections = AICorrector.parseCorrectionResponse(response)
    #expect(corrections.isEmpty)
  }

  @Test("strips markdown code fences from JSON")
  func jsonWithCodeFences() {
    let response = """
      ```json
      [{"index":1,"original":"错误","corrected":"正确"}]
      ```
      """
    let corrections = AICorrector.parseCorrectionResponse(response)
    #expect(corrections.count == 1)
    #expect(corrections[0].original == "错误")
    #expect(corrections[0].corrected == "正确")
  }

  @Test("handles preamble text before JSON")
  func jsonWithPreamble() {
    let response = """
      Here are the corrections I found:
      [{"index":2,"original":"recieve","corrected":"receive"}]
      """
    let corrections = AICorrector.parseCorrectionResponse(response)
    #expect(corrections.count == 1)
    #expect(corrections[0].corrected == "receive")
  }

  @Test("applies corrections to segment texts")
  func applyCorrections() {
    let texts = ["试错的过程很简单。", "这是正确的。", "报名昌学卡的同学，"]
    let corrections: [AICorrector.CorrectionItem] = [
      .init(index: 3, original: "昌学卡", corrected: "畅学卡")
    ]
    let result = AICorrector.applyCorrections(corrections, to: texts)
    #expect(result[0] == "试错的过程很简单。")  // unchanged
    #expect(result[1] == "这是正确的。")  // unchanged
    #expect(result[2] == "报名畅学卡的同学，")  // corrected
  }

  @Test("applies multiple corrections to same segment")
  func multipleCorrectionsOnSameSegment() {
    let texts = ["他说recieve不是正确的拼法"]
    let corrections: [AICorrector.CorrectionItem] = [
      .init(index: 1, original: "recieve", corrected: "receive"),
      .init(index: 1, original: "拼法", corrected: "拼写"),
    ]
    let result = AICorrector.applyCorrections(corrections, to: texts)
    #expect(result[0] == "他说receive不是正确的拼写")
  }

  @Test("out-of-range index is ignored")
  func outOfRangeIndex() {
    let texts = ["hello"]
    let corrections: [AICorrector.CorrectionItem] = [
      .init(index: 5, original: "x", corrected: "y")
    ]
    let result = AICorrector.applyCorrections(corrections, to: texts)
    #expect(result[0] == "hello")
  }

  // MARK: - Legacy format fallback

  @Test("parses [N]. text format (legacy fallback)")
  func legacyBracketDotFormat() {
    let response = """
      [1]. 你好世界
      [2]. 这是测试
      """
    let results = AICorrector.parseBatchResponse(response, expectedCount: 2)
    #expect(results == ["你好世界", "这是测试"])
  }

  @Test("parses N. text format (legacy fallback)")
  func legacyPlainNumberDotFormat() {
    let response = """
      1. Hello world
      2. This is a test
      3. Third line
      """
    let results = AICorrector.parseBatchResponse(response, expectedCount: 3)
    #expect(results == ["Hello world", "This is a test", "Third line"])
  }
}
