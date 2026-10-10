import Testing

@testable import Cliptate

@Suite("AIPrompts.languageOutputRule")
struct AIPromptsLanguageRuleTests {

  @Test("auto language preserves transcript language (not forced English)")
  func autoLanguage() {
    let rule = AIPrompts.languageOutputRule(for: .auto)
    #expect(rule.contains("same language"))
    #expect(!rule.contains("MUST be entirely in"))
  }

  @Test("english returns English output rule")
  func englishLanguage() {
    let rule = AIPrompts.languageOutputRule(for: .english)
    #expect(rule.contains("English"))
    #expect(rule.contains("MUST"))
  }

  @Test("chinese returns Chinese output rule with translation instruction")
  func chineseLanguage() {
    let rule = AIPrompts.languageOutputRule(for: .chinese)
    #expect(rule.contains("Chinese"))
    #expect(rule.contains("translate"))
  }

  @Test("japanese returns Japanese output rule")
  func japaneseLanguage() {
    let rule = AIPrompts.languageOutputRule(for: .japanese)
    #expect(rule.contains("Japanese"))
  }

  @Test("dictation system prompt contains format placeholder")
  func dictationPromptHasPlaceholder() {
    #expect(AIPrompts.dictationSystemPrompt.contains("%@"))
  }

  @Test("formatted dictation prompt replaces placeholder with language rule")
  func formattedDictationPrompt() {
    let rule = AIPrompts.languageOutputRule(for: .chinese)
    let formatted = String(format: AIPrompts.dictationSystemPrompt, rule)
    #expect(!formatted.contains("%@"))
    #expect(formatted.contains("Chinese"))
  }

  @Test("assistant prompt with language rule appended")
  func assistantPromptWithLanguage() {
    let rule = AIPrompts.languageOutputRule(for: .korean)
    let full = AIPrompts.assistantMode + "\n\n" + rule
    #expect(full.contains("Korean"))
    #expect(full.contains("voice-command assistant"))
  }
}
