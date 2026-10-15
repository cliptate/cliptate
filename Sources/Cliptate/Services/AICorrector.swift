import CliptateCore
import Foundation
import os.log

/// AI-powered text correction service
actor AICorrector {
  private static let logger = Logger(subsystem: "com.Cliptate", category: "AICorrector")
  private static var fallbackCorrectionSystemPrompt: String {
    AppConfiguration.defaultSystemCorrectionPrompt
  }
  private static var fallbackKeywordSystemPrompt: String {
    AppConfiguration.defaultSystemKeywordPrompt
  }
  private static var fallbackAssistantSystemPrompt: String {
    "You are a helpful assistant that replies concisely using the same language as the provided transcript."
  }
  private static let defaultOpenAIBaseURL = "https://api.openai.com/v1"

  private static func normalizedModel(_ model: String?, for provider: AIProvider) -> String {
    let trimmed = model?.trimmingCharacters(in: .whitespacesAndNewlines)
    if let trimmed, !trimmed.isEmpty {
      return trimmed
    }
    return provider.defaultModel
  }

  private static func normalizedSystemPrompt(_ prompt: String?, fallback: String) -> String {
    let trimmed = prompt?.trimmingCharacters(in: .whitespacesAndNewlines)
    if let trimmed, !trimmed.isEmpty {
      return trimmed
    }
    return fallback
  }

  enum AIError: Error, LocalizedError {
    case noAPIKey
    case invalidProvider
    case networkError(String)
    case invalidResponse
    case apiError(String)
    case parsingError(String)

    var errorDescription: String? {
      switch self {
      case .noAPIKey:
        return "No API key configured for the selected provider"
      case .invalidProvider:
        return "Invalid AI provider selected"
      case .networkError(let msg):
        return "Network error: \(msg)"
      case .invalidResponse:
        return "Invalid response from AI provider"
      case .apiError(let msg):
        return "API error: \(msg)"
      case .parsingError(let msg):
        return "Parsing error: \(msg)"
      }
    }
  }

  /// A single word/phrase correction identified by the AI.
  struct CorrectionItem: Codable, Equatable, Sendable {
    let index: Int
    let original: String
    let corrected: String
  }

  /// Correct text using AI
  static func correctText(
    _ text: String,
    provider: AIProvider,
    model: String?,
    systemPrompt: String?,
    apiKey: String,
    language: Language,
    customPrompt: String? = nil,  // 新增:自定义提示词
    openAIBaseURL: String? = nil
  ) async throws -> String {
    guard !apiKey.isEmpty else {
      throw AIError.noAPIKey
    }

    let resolvedModel = normalizedModel(model, for: provider)
    let resolvedSystemPrompt = normalizedSystemPrompt(
      systemPrompt,
      fallback: fallbackCorrectionSystemPrompt
    )

    let prompt = buildCorrectionPrompt(
      text: text,
      language: language,
      referenceScript: customPrompt
    )

    return try await sendCorrectionRequest(
      provider: provider,
      model: resolvedModel,
      prompt: prompt,
      apiKey: apiKey,
      systemPrompt: resolvedSystemPrompt,
      openAIBaseURL: openAIBaseURL
    )
  }

  /// Send a free-form prompt to the configured AI provider and return the response.
  static func askAssistant(
    prompt: String,
    provider: AIProvider,
    model: String?,
    systemPrompt: String?,
    apiKey: String,
    openAIBaseURL: String? = nil
  ) async throws -> String {
    guard !apiKey.isEmpty else {
      throw AIError.noAPIKey
    }

    let resolvedModel = normalizedModel(model, for: provider)
    let resolvedSystemPrompt = normalizedSystemPrompt(
      systemPrompt,
      fallback: fallbackAssistantSystemPrompt
    )

    return try await sendCorrectionRequest(
      provider: provider,
      model: resolvedModel,
      prompt: prompt,
      apiKey: apiKey,
      systemPrompt: resolvedSystemPrompt,
      openAIBaseURL: openAIBaseURL
    )
  }

  /// Correct multiple texts in a single batch request (more efficient, avoids rate limits)
  static func correctBatch(
    _ texts: [String],
    provider: AIProvider,
    model: String?,
    systemPrompt: String?,
    apiKey: String,
    language: Language,
    customPrompt: String? = nil,  // 新增:自定义提示词
    openAIBaseURL: String? = nil
  ) async throws -> [String] {
    guard !apiKey.isEmpty else {
      throw AIError.noAPIKey
    }

    guard !texts.isEmpty else {
      return []
    }

    let resolvedModel = normalizedModel(model, for: provider)
    let resolvedSystemPrompt = normalizedSystemPrompt(
      systemPrompt,
      fallback: fallbackCorrectionSystemPrompt
    )

    // 构建统一的批量纠错 prompt
    let prompt = buildBatchCorrectionPrompt(
      texts: texts, language: language, referenceScript: customPrompt)

    // 根据不同 provider 构建请求
    let response = try await sendCorrectionRequest(
      provider: provider,
      model: resolvedModel,
      prompt: prompt,
      apiKey: apiKey,
      systemPrompt: resolvedSystemPrompt,
      openAIBaseURL: openAIBaseURL
    )

    return parseBatchResponse(response, expectedCount: texts.count)
  }

  /// Correct multiple texts using a diff-based approach: the LLM returns only the
  /// changed words/phrases with their subtitle index, saving tokens and making
  /// parsing more reliable. Returns corrected full texts (corrections applied).
  static func correctBatchDiff(
    _ texts: [String],
    provider: AIProvider,
    model: String?,
    systemPrompt: String?,
    apiKey: String,
    language: Language,
    customPrompt: String? = nil,
    openAIBaseURL: String? = nil
  ) async throws -> (correctedTexts: [String], corrections: [CorrectionItem]) {
    guard !apiKey.isEmpty else {
      throw AIError.noAPIKey
    }

    guard !texts.isEmpty else {
      return ([], [])
    }

    let resolvedModel = normalizedModel(model, for: provider)
    let resolvedSystemPrompt = normalizedSystemPrompt(
      systemPrompt,
      fallback: fallbackCorrectionSystemPrompt
    )

    let prompt = buildDiffCorrectionPrompt(
      texts: texts, language: language, referenceScript: customPrompt)

    let response = try await sendCorrectionRequest(
      provider: provider,
      model: resolvedModel,
      prompt: prompt,
      apiKey: apiKey,
      systemPrompt: resolvedSystemPrompt,
      openAIBaseURL: openAIBaseURL
    )

    return applyCorrectionsWithEvidence(parseCorrectionResponse(response), to: texts)
  }

  /// Parse a diff-based correction response (JSON array of CorrectionItem).
  static func parseCorrectionResponse(_ response: String) -> [CorrectionItem] {
    let cleaned = stripMarkdownCodeFences(response)

    // Find the JSON array in the response (skip any preamble text)
    guard let startIndex = cleaned.firstIndex(of: "["),
      let endIndex = cleaned.lastIndex(of: "]")
    else {
      return []
    }

    let jsonString = String(cleaned[startIndex...endIndex])
    guard let data = jsonString.data(using: .utf8) else { return [] }

    do {
      return try JSONDecoder().decode([CorrectionItem].self, from: data)
    } catch {
      print("⚠️ Failed to parse correction JSON: \(error.localizedDescription)")
      return []
    }
  }

  /// Apply diff corrections to original texts, producing corrected texts.
  static func applyCorrections(_ corrections: [CorrectionItem], to texts: [String]) -> [String] {
    applyCorrectionsWithEvidence(corrections, to: texts).correctedTexts
  }

  /// Discard proposals that did not change text. The returned pairs are safe to audit.
  static func applyCorrectionsWithEvidence(
    _ corrections: [CorrectionItem], to texts: [String]
  ) -> (correctedTexts: [String], corrections: [CorrectionItem]) {
    var result = texts
    var applied: [CorrectionItem] = []
    for correction in corrections {
      guard correction.index > 0, correction.index <= result.count,
        !correction.original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
        !correction.corrected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
        correction.original != correction.corrected
      else { continue }
      let index = correction.index - 1
      let replacement = result[index].replacingOccurrences(of: correction.original, with: correction.corrected)
      guard replacement != result[index] else { continue }
      result[index] = replacement
      applied.append(correction)
    }
    return (result, applied)
  }
  static func extractKeywords(
    from texts: [String],
    provider: AIProvider,
    model: String?,
    systemPrompt: String?,
    apiKey: String,
    language: Language,
    maxKeywords: Int = 4,
    openAIBaseURL: String? = nil
  ) async throws -> [[String]] {
    guard !apiKey.isEmpty else {
      throw AIError.noAPIKey
    }

    guard !texts.isEmpty else {
      return []
    }

    let resolvedModel = normalizedModel(model, for: provider)
    let resolvedSystemPrompt = normalizedSystemPrompt(
      systemPrompt,
      fallback: fallbackKeywordSystemPrompt
    )

    let prompt = buildKeywordExtractionPrompt(
      texts: texts,
      language: language,
      maxKeywords: maxKeywords
    )

    let response: String
    switch provider {
    case .openai:
      response = try await sendChatCompletionRequest(
        url: resolveOpenAIURL(base: openAIBaseURL, route: "/chat/completions").absoluteString,
        model: resolvedModel,
        prompt: prompt,
        apiKey: apiKey,
        authType: .bearer,
        systemPrompt: resolvedSystemPrompt,
        includeGenerationParameters: false
      )
    case .gemini:
      response = try await sendGeminiRequest(
        apiKey: apiKey,
        prompt: prompt,
        model: resolvedModel,
        systemPrompt: resolvedSystemPrompt
      )
    case .deepseek:
      response = try await sendChatCompletionRequest(
        url: "https://api.deepseek.com/v1/chat/completions",
        model: resolvedModel,
        prompt: prompt,
        apiKey: apiKey,
        authType: .bearer,
        systemPrompt: resolvedSystemPrompt
      )
    case .anthropic:
      response = try await sendAnthropicRequest(
        apiKey: apiKey,
        prompt: prompt,
        model: resolvedModel,
        systemPrompt: resolvedSystemPrompt
      )
    case .groq:
      response = try await sendChatCompletionRequest(
        url: "https://api.groq.com/openai/v1/chat/completions",
        model: resolvedModel,
        prompt: prompt,
        apiKey: apiKey,
        authType: .bearer,
        systemPrompt: resolvedSystemPrompt
      )
    }

    return try parseKeywordExtractionResponse(
      response,
      expectedCount: texts.count,
      maxKeywords: maxKeywords
    )
  }

  // MARK: - HTTP Request Helpers

  enum AuthType {
    case bearer
    case apiKey
  }

  private static func sendCorrectionRequest(
    provider: AIProvider,
    model: String,
    prompt: String,
    apiKey: String,
    systemPrompt: String,
    openAIBaseURL: String?
  ) async throws -> String {
    logger.debug("🤖 AI Request — provider: \(provider.displayName), model: \(model)")
    logger.debug("🤖 System prompt: \(systemPrompt.prefix(500))")
    logger.debug("🤖 User prompt: \(prompt.prefix(500))")

    let response: String
    switch provider {
    case .openai:
      response = try await sendChatCompletionRequest(
        url: resolveOpenAIURL(base: openAIBaseURL, route: "/chat/completions").absoluteString,
        model: model,
        prompt: prompt,
        apiKey: apiKey,
        authType: .bearer,
        systemPrompt: systemPrompt,
        includeGenerationParameters: false
      )
    case .gemini:
      response = try await sendGeminiRequest(
        apiKey: apiKey,
        prompt: prompt,
        model: model,
        systemPrompt: systemPrompt
      )
    case .deepseek:
      response = try await sendChatCompletionRequest(
        url: "https://api.deepseek.com/v1/chat/completions",
        model: model,
        prompt: prompt,
        apiKey: apiKey,
        authType: .bearer,
        systemPrompt: systemPrompt
      )
    case .anthropic:
      response = try await sendAnthropicRequest(
        apiKey: apiKey,
        prompt: prompt,
        model: model,
        systemPrompt: systemPrompt
      )
    case .groq:
      response = try await sendChatCompletionRequest(
        url: "https://api.groq.com/openai/v1/chat/completions",
        model: model,
        prompt: prompt,
        apiKey: apiKey,
        authType: .bearer,
        systemPrompt: systemPrompt
      )
    }

    logger.debug("🤖 AI Response (\(response.count) chars): \(response.prefix(500))")
    return response
  }

  /// 通用的 Chat Completion API 请求 (OpenAI 兼容格式)
  private static func sendChatCompletionRequest(
    url: String,
    model: String,
    prompt: String,
    apiKey: String,
    authType: AuthType,
    systemPrompt: String = fallbackCorrectionSystemPrompt,
    includeGenerationParameters: Bool = true
  ) async throws -> String {
    let requestURL = URL(string: url)!
    var request = URLRequest(url: requestURL)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

    switch authType {
    case .bearer:
      request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    case .apiKey:
      request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
    }

    var requestBody: [String: Any] = [
      "model": model,
      "messages": [
        ["role": "system", "content": systemPrompt],
        ["role": "user", "content": prompt],
      ],
    ]

    if includeGenerationParameters {
      requestBody["temperature"] = 0.3
      requestBody["max_tokens"] = 4000
    }

    request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

    let (data, response) = try await URLSession.shared.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse else {
      throw AIError.invalidResponse
    }

    if httpResponse.statusCode != 200 {
      let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown error"
      throw AIError.apiError("HTTP \(httpResponse.statusCode): \(errorMsg)")
    }

    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
      let choices = json["choices"] as? [[String: Any]],
      let firstChoice = choices.first,
      let message = firstChoice["message"] as? [String: Any],
      let content = message["content"] as? String
    else {
      throw AIError.invalidResponse
    }

    return content.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  /// Gemini API 请求
  private static func sendGeminiRequest(
    apiKey: String,
    prompt: String,
    model: String,
    systemPrompt: String
  ) async throws -> String {
    let encodedModel = model.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? model
    let urlString =
      "https://generativelanguage.googleapis.com/v1beta/models/\(encodedModel):generateContent?key=\(apiKey)"
    guard let url = URL(string: urlString) else {
      throw AIError.invalidResponse
    }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

    var requestBody: [String: Any] = [
      "contents": [
        [
          "parts": [
            ["text": prompt]
          ]
        ]
      ],
      "generationConfig": [
        "temperature": 0.3,
        "maxOutputTokens": 4000,
      ],
    ]

    let trimmedSystemPrompt = systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmedSystemPrompt.isEmpty {
      requestBody["systemInstruction"] = [
        "parts": [
          ["text": trimmedSystemPrompt]
        ]
      ]
    }

    request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

    let (data, response) = try await URLSession.shared.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse else {
      throw AIError.invalidResponse
    }

    if httpResponse.statusCode != 200 {
      let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown error"
      throw AIError.apiError("HTTP \(httpResponse.statusCode): \(errorMsg)")
    }

    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
      let candidates = json["candidates"] as? [[String: Any]],
      let firstCandidate = candidates.first,
      let content = firstCandidate["content"] as? [String: Any],
      let parts = content["parts"] as? [[String: Any]],
      let firstPart = parts.first,
      let text = firstPart["text"] as? String
    else {
      throw AIError.invalidResponse
    }

    return text.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  /// Anthropic API 请求
  private static func sendAnthropicRequest(
    apiKey: String,
    prompt: String,
    model: String,
    systemPrompt: String
  ) async throws -> String {
    let url = URL(string: "https://api.anthropic.com/v1/messages")!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
    request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

    var requestBody: [String: Any] = [
      "model": model,
      "max_tokens": 4000,
      "temperature": 0.3,
      "messages": [
        ["role": "user", "content": prompt]
      ],
    ]

    let trimmedSystemPrompt = systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmedSystemPrompt.isEmpty {
      requestBody["system"] = trimmedSystemPrompt
    }

    request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

    let (data, response) = try await URLSession.shared.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse else {
      throw AIError.invalidResponse
    }

    if httpResponse.statusCode != 200 {
      let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown error"
      throw AIError.apiError("HTTP \(httpResponse.statusCode): \(errorMsg)")
    }

    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
      let content = json["content"] as? [[String: Any]],
      let firstContent = content.first,
      let text = firstContent["text"] as? String
    else {
      throw AIError.invalidResponse
    }

    return text.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  // MARK: - OpenAI

  private static func resolveOpenAIURL(base: String?, route: String) -> URL {
    let trimmedBase = base?.trimmingCharacters(in: .whitespacesAndNewlines)
    let baseURLString: String
    if let trimmedBase, !trimmedBase.isEmpty {
      baseURLString = trimmedBase
    } else {
      baseURLString = defaultOpenAIBaseURL
    }

    let sanitizedBase =
      baseURLString.hasSuffix("/")
      ? String(baseURLString.dropLast())
      : baseURLString
    let sanitizedRoute = route.hasPrefix("/") ? route : "/\(route)"

    if let url = URL(string: sanitizedBase + sanitizedRoute) {
      return url
    }

    return URL(string: defaultOpenAIBaseURL + sanitizedRoute)!  // Guaranteed valid fallback
  }

  // MARK: - Prompt Builder
  private static func buildCorrectionPrompt(
    text: String, language: Language, referenceScript: String? = nil
  ) -> String {
    let languageName = language.displayName

    if let reference = referenceScript,
      !reference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    {
      // 使用参考文案引导纠错
      return """
        You are correcting a video transcription. The user has provided the original video script as a reference.

        Instructions:
        1. Correct the transcribed text to match the reference script as closely as possible
        2. Fix spelling, grammar, and punctuation errors
        3. Keep the original meaning and don't add or remove content.
        4. Keep timestamps-related pauses or breaks if present

        Return ONLY the corrected text without any explanations or additional content.

        Reference Script (the intended content):
        \(reference)

        Transcribed Text (may contain errors, \(languageName)):
        \(text)
        """
    } else {
      // 默认 prompt
      return """
        Please correct any spelling, grammar, or transcription errors in the following \(languageName) text.
        Keep the original meaning and don't add or remove content.
        Only return the corrected text without any explanations or additional formatting.

        Text to correct:
        \(text)
        """
    }
  }

  private static func buildBatchCorrectionPrompt(
    texts: [String], language: Language, referenceScript: String? = nil
  ) -> String {
    let languageName = language.displayName

    var baseInstruction: String
    if let reference = referenceScript,
      !reference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    {
      // 使用参考文案引导纠错
      baseInstruction = """
        You are correcting a video transcription. The user has provided the original video script as a reference.

        Reference Script (the intended content):
        \(reference)

        Transcribed Texts (may contain errors, \(languageName), each numbered):

        Instructions:
        1. Correct each transcribed text to match the reference script as closely as possible
        2. Fix spelling, grammar, and punctuation errors
        3. Preserve the language: \(languageName)
        4. Keep timestamps-related pauses or breaks if present
        5. Return ONLY the corrected texts in the same numbered format, one per line

        Format: [number]. [corrected text]
        """
    } else {
      // 默认 prompt
      baseInstruction = """
        Please correct any spelling, grammar, or transcription errors in the following \(languageName) texts.
        Each text is numbered. Keep the original meaning and don't add or remove content.
        Return ONLY the corrected texts in the same numbered format, one per line.
        Format: [number]. [corrected text]
        """
    }

    var prompt = baseInstruction + "\n\nTexts to correct:\n\n"

    for (index, text) in texts.enumerated() {
      prompt += "[\(index + 1)]. \(text)\n"
    }

    return prompt
  }

  /// Build a diff-based correction prompt that asks the LLM to return only
  /// the specific words/phrases that need correction, saving tokens.
  private static func buildDiffCorrectionPrompt(
    texts: [String], language: Language, referenceScript: String? = nil
  ) -> String {
    let languageName = language.displayName

    var instruction: String
    if let reference = referenceScript,
      !reference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    {
      instruction = """
        You are correcting a video transcription in \(languageName). The user provided the original script as reference.

        Reference Script:
        \(reference)

        Compare each numbered subtitle against the reference and identify ONLY the words or phrases that differ.
        Return a JSON array of corrections. Each correction has:
        - "index": the subtitle number (1-based)
        - "original": the exact wrong word/phrase in the subtitle
        - "corrected": the correct word/phrase from the reference

        If a subtitle is already correct, do NOT include it.
        If all subtitles are correct, return an empty array: []

        Respond with ONLY the JSON array, no explanation.
        """
    } else {
      instruction = """
        Find and fix spelling, grammar, or transcription errors in the following \(languageName) subtitles.
        Return ONLY a JSON array of corrections. Each correction has:
        - "index": the subtitle number (1-based)
        - "original": the exact wrong word/phrase as it appears in the subtitle
        - "corrected": the correct word/phrase to replace it

        Rules:
        - Only include subtitles that have actual errors
        - Keep corrections minimal: capture the complete word or phrase that contains the error, not the entire sentence, and never truncate to a single character
        - Preserve original meaning; do not add or remove content
        - If no errors are found, return: []

        Respond with ONLY valid JSON, no explanation.

        Example response: [{"index":2,"original":"错字","corrected":"正字"}]
        """
    }

    var prompt = instruction + "\n\nSubtitles:\n"

    for (index, text) in texts.enumerated() {
      prompt += "[\(index + 1)]. \(text)\n"
    }

    return prompt
  }

  private static func buildKeywordExtractionPrompt(
    texts: [String],
    language: Language,
    maxKeywords: Int
  ) -> String {
    let languageName = language.displayName
    var prompt = """
      You are analyzing a sequence of short speech transcription segments in \(languageName).
      For each segment, extract up to \(maxKeywords) concise keywords or short phrases that best capture the meaning.
      Use only words or phrases that appear in the segment and avoid filler words.

      Return the result as a JSON array. Each item must contain:
      - "index": the 1-based index of the segment
      - "keywords": an array of strings with at most \(maxKeywords) items

      Respond with valid JSON only. Do not include explanations or code fences.
      Segments:
      """

    for (index, text) in texts.enumerated() {
      prompt += "\n\(index + 1). \(text)"
    }

    prompt += "\n"
    return prompt
  }

  private static func parseKeywordExtractionResponse(
    _ response: String,
    expectedCount: Int,
    maxKeywords: Int
  ) throws -> [[String]] {
    let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
    var candidates: [String] = [trimmed]

    if let jsonFenceRange = trimmed.range(of: "```json") {
      let suffix = trimmed[jsonFenceRange.upperBound...]
      if let fenceEnd = suffix.range(of: "```") {
        let content = suffix[..<fenceEnd.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        candidates.append(String(content))
      }
    } else if let genericFenceRange = trimmed.range(of: "```") {
      let suffix = trimmed[genericFenceRange.upperBound...]
      if let fenceEnd = suffix.range(of: "```") {
        let content = suffix[..<fenceEnd.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        candidates.append(String(content))
      }
    }

    if let firstBracket = trimmed.firstIndex(of: "["),
      let lastBracket = trimmed.lastIndex(of: "]"),
      firstBracket < lastBracket
    {
      let jsonSubstring = trimmed[firstBracket...lastBracket]
      candidates.append(String(jsonSubstring))
    }

    var uniqueCandidates: [String] = []
    for candidate in candidates {
      if !uniqueCandidates.contains(candidate) {
        uniqueCandidates.append(candidate)
      }
    }

    for candidate in uniqueCandidates {
      if let parsed = try attemptParseKeywordJSON(
        candidate,
        expectedCount: expectedCount,
        maxKeywords: maxKeywords
      ) {
        return parsed
      }
    }

    let regex = try NSRegularExpression(pattern: #"^(\d+)[\.\)]\s*(.+)$"#, options: [])
    var fallbackResults = Array(repeating: [String](), count: expectedCount)
    var matchedCount = 0

    let lines = trimmed.components(separatedBy: .newlines)
    for line in lines {
      let rawLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !rawLine.isEmpty else { continue }

      if let match = regex.firstMatch(
        in: rawLine,
        options: [],
        range: NSRange(rawLine.startIndex..., in: rawLine)
      ),
        match.numberOfRanges >= 3,
        let indexRange = Range(match.range(at: 1), in: rawLine),
        let textRange = Range(match.range(at: 2), in: rawLine)
      {
        let indexValue = rawLine[indexRange]
        let listValue = rawLine[textRange]
        guard let numericIndex = Int(indexValue),
          numericIndex >= 1,
          numericIndex <= expectedCount
        else { continue }

        let tokens = listValue.components(separatedBy: CharacterSet(charactersIn: ",;|/"))
          .map { $0.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters)) }
          .filter { !$0.isEmpty }

        let normalized = normalizeKeywords(tokens, maxKeywords: maxKeywords)
        if !normalized.isEmpty {
          fallbackResults[numericIndex - 1] = normalized
          matchedCount += 1
        }
      }
    }

    if matchedCount > 0 {
      return fallbackResults
    }

    throw AIError.parsingError("Unable to interpret keyword extraction response.")
  }

  private static func attemptParseKeywordJSON(
    _ candidate: String,
    expectedCount: Int,
    maxKeywords: Int
  ) throws -> [[String]]? {
    guard let data = candidate.data(using: .utf8) else {
      return nil
    }

    let jsonObject: Any
    do {
      jsonObject = try JSONSerialization.jsonObject(with: data)
    } catch {
      return nil
    }

    var results = Array(repeating: [String](), count: expectedCount)

    if let array = jsonObject as? [[String: Any]] {
      for item in array {
        let indexValue = item["index"] ?? item["segment"] ?? item["id"]
        guard let index = parseIndex(indexValue),
          index >= 1,
          index <= expectedCount
        else { continue }

        let keywordsValue = item["keywords"] ?? item["keyword"]
        let extracted = extractKeywords(from: keywordsValue)
        let normalized = normalizeKeywords(extracted, maxKeywords: maxKeywords)
        if !normalized.isEmpty {
          results[index - 1] = normalized
        }
      }
      return results
    }

    if let dict = jsonObject as? [String: Any] {
      for (key, value) in dict {
        guard let index = parseIndex(key),
          index >= 1,
          index <= expectedCount
        else { continue }
        let extracted = extractKeywords(from: value)
        let normalized = normalizeKeywords(extracted, maxKeywords: maxKeywords)
        if !normalized.isEmpty {
          results[index - 1] = normalized
        }
      }
      return results
    }

    return nil
  }

  private static func extractKeywords(from value: Any?) -> [String] {
    if let keywords = value as? [String] {
      return keywords
    }
    if let keywords = value as? [Any] {
      return keywords.compactMap { element in
        if let string = element as? String {
          return string
        }
        return nil
      }
    }
    if let single = value as? String {
      return single.components(separatedBy: CharacterSet(charactersIn: ",;|/")).map {
        $0.trimmingCharacters(in: .whitespacesAndNewlines)
      }
    }
    return []
  }

  private static func parseIndex(_ value: Any?) -> Int? {
    if let intValue = value as? Int {
      return intValue
    }
    if let stringValue = value as? String {
      return Int(stringValue.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    if let doubleValue = value as? Double {
      return Int(doubleValue)
    }
    return nil
  }

  private static func normalizeKeywords(_ keywords: [String], maxKeywords: Int) -> [String] {
    var seen: Set<String> = []
    var result: [String] = []
    result.reserveCapacity(min(keywords.count, maxKeywords))

    for keyword in keywords {
      let trimmed = keyword.trimmingCharacters(
        in: .whitespacesAndNewlines.union(.punctuationCharacters))
      guard !trimmed.isEmpty else { continue }
      let lower = trimmed.lowercased()
      if !seen.contains(lower) {
        seen.insert(lower)
        result.append(trimmed)
        if result.count >= maxKeywords {
          break
        }
      }
    }

    return result
  }

  static func parseBatchResponse(_ response: String, expectedCount: Int) -> [String] {
    // Strip markdown code fences if present
    let cleaned = stripMarkdownCodeFences(response)
    let lines = cleaned.components(separatedBy: .newlines)

    // Numbered-line patterns in priority order
    let patterns: [NSRegularExpression] = [
      // [N]. text
      try! NSRegularExpression(pattern: #"^\[(\d+)\]\.\s*(.+)$"#),
      // [N] text (no dot)
      try! NSRegularExpression(pattern: #"^\[(\d+)\]\s+(.+)$"#),
      // N. text
      try! NSRegularExpression(pattern: #"^(\d+)\.\s+(.+)$"#),
      // N) text
      try! NSRegularExpression(pattern: #"^(\d+)\)\s*(.+)$"#),
    ]

    for pattern in patterns {
      var results: [String] = []
      for line in lines {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if let match = pattern.firstMatch(
          in: trimmed, options: [], range: NSRange(trimmed.startIndex..., in: trimmed)),
          match.numberOfRanges >= 3,
          let textRange = Range(match.range(at: 2), in: trimmed)
        {
          results.append(String(trimmed[textRange]))
        }
      }
      if results.count == expectedCount {
        return results
      }
    }

    // Fallback: collect non-empty content lines (skip preamble/explanation)
    print("⚠️ Batch response parsing: no numbered format matched for expectedCount=\(expectedCount)")
    let contentLines = lines
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .filter { line in
        !line.isEmpty
          && !line.hasPrefix("#")
          && !line.hasPrefix("//")
          && !line.hasPrefix("```")
          && !line.lowercased().hasPrefix("here")
          && !line.lowercased().hasPrefix("below")
          && !line.lowercased().hasPrefix("corrected")
          && !line.lowercased().hasPrefix("the corrected")
          && !line.lowercased().hasPrefix("i've")
          && !line.lowercased().hasPrefix("i have")
      }

    // Try stripping any remaining number prefixes from content lines
    let strippedLines = contentLines.compactMap { line -> String? in
      // Strip leading "N. " or "[N]. " or "N) " prefixes
      if let regex = try? NSRegularExpression(pattern: #"^(?:\[?\d+\]?[.)]\s*)"#),
        let match = regex.firstMatch(
          in: line, options: [], range: NSRange(line.startIndex..., in: line)),
        let range = Range(match.range, in: line)
      {
        let stripped = String(line[range.upperBound...])
        return stripped.isEmpty ? nil : stripped
      }
      return line
    }

    if strippedLines.count >= expectedCount {
      return Array(strippedLines.prefix(expectedCount))
    } else if !strippedLines.isEmpty {
      print("⚠️ Using partially parsed results: \(strippedLines.count) of \(expectedCount) items")
      return strippedLines
    }

    return contentLines
  }

  /// Remove markdown code fences (```...```) from AI response text.
  private static func stripMarkdownCodeFences(_ text: String) -> String {
    var result = text
    // Remove opening ```json, ```text, ``` etc.
    if let range = result.range(of: #"^```\w*\s*\n"#, options: .regularExpression) {
      result.removeSubrange(range)
    }
    // Remove closing ```
    if let range = result.range(of: #"\n```\s*$"#, options: .regularExpression) {
      result.removeSubrange(range)
    }
    return result
  }
}

// MARK: - Dictionary Analysis

extension AICorrector {

  /// Assemble a single text block from history sessions for dictionary analysis.
  /// Sessions are ordered newest-first; text accumulation stops at `maxLength` characters.
  static func buildDictionaryAnalysisText(
    from sessions: [TranscriptSession],
    maxLength: Int = 12_000
  ) -> String {
    var result = ""
    let separator = "\n---\n"
    var uniqueEvidence: [UUID: TranscriptCorrection] = [:]
    for event in sessions.flatMap({ $0.corrections ?? [] }) {
      if let existing = uniqueEvidence[event.id], existing.status != .applied { continue }
      uniqueEvidence[event.id] = event
    }
    let evidence = uniqueEvidence.values.filter { $0.status == .applied }
      .sorted { $0.recordedAt > $1.recordedAt }
    for event in evidence {
      let text = "AI correction (\(event.kind.rawValue)): \(event.original) → \(event.corrected)\nCorrected context: \(event.correctedContext)"
      let prefix = result.isEmpty ? "" : separator
      let available = maxLength - result.count - prefix.count
      guard available > 0 else { return result }
      result += prefix + String(text.prefix(available))
    }
    for session in sessions.sorted(by: { $0.startTime > $1.startTime }) {
      let text = session.combinedText.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !text.isEmpty else { continue }
      let prefix = result.isEmpty ? "" : separator
      let available = maxLength - result.count - prefix.count
      if available <= 0 { break }
      if text.count <= available {
        result += prefix + text
      } else {
        result += prefix + String(text.prefix(available))
        break
      }
    }
    return result
  }

  /// Extract domain-specific terms from multilingual transcript text for the ASR custom dictionary.
  /// The AI model auto-detects the language(s) present and may return terms across multiple languages.
  static func extractDictionaryTerms(
    from text: String,
    provider: AIProvider,
    model: String?,
    apiKey: String,
    openAIBaseURL: String? = nil,
    maxTerms: Int = 30
  ) async throws -> [String] {
    guard !apiKey.isEmpty else { throw AIError.noAPIKey }
    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }

    let resolvedModel = normalizedModel(model, for: provider)
    let systemPrompt =
      "You are an expert linguist analyzing speech transcription text to identify domain-specific vocabulary for an ASR custom dictionary."
    let prompt = buildDictionaryTermsPrompt(text: text, maxTerms: maxTerms)

    let response: String
    switch provider {
    case .openai:
      response = try await sendChatCompletionRequest(
        url: resolveOpenAIURL(base: openAIBaseURL, route: "/chat/completions").absoluteString,
        model: resolvedModel,
        prompt: prompt,
        apiKey: apiKey,
        authType: .bearer,
        systemPrompt: systemPrompt,
        includeGenerationParameters: false
      )
    case .gemini:
      response = try await sendGeminiRequest(
        apiKey: apiKey,
        prompt: prompt,
        model: resolvedModel,
        systemPrompt: systemPrompt
      )
    case .deepseek:
      response = try await sendChatCompletionRequest(
        url: "https://api.deepseek.com/v1/chat/completions",
        model: resolvedModel,
        prompt: prompt,
        apiKey: apiKey,
        authType: .bearer,
        systemPrompt: systemPrompt
      )
    case .anthropic:
      response = try await sendAnthropicRequest(
        apiKey: apiKey,
        prompt: prompt,
        model: resolvedModel,
        systemPrompt: systemPrompt
      )
    case .groq:
      response = try await sendChatCompletionRequest(
        url: "https://api.groq.com/openai/v1/chat/completions",
        model: resolvedModel,
        prompt: prompt,
        apiKey: apiKey,
        authType: .bearer,
        systemPrompt: systemPrompt
      )
    }

    return parseDictionaryTermsResponse(response, maxTerms: maxTerms)
  }

  private static func buildDictionaryTermsPrompt(text: String, maxTerms: Int) -> String {
    """
    Analyze the following speech transcription text and identify up to \(maxTerms) domain-specific words or short phrases that would benefit from being added to an ASR custom dictionary.

    Focus on:
    - Proper nouns (people names, places, product names, brand names)
    - Technical terms, jargon, or industry-specific vocabulary
    - Uncommon words, abbreviations, or acronyms
    - Words that a speech recognition system is likely to mispronounce or misrecognize

    The text may contain multiple languages. Include terms from all languages present.
    Exclude common everyday words, filler words, grammatical particles, and punctuation.
    AI correction records identify past applied edits. Prefer corrected vocabulary and its context;
    never suggest the original erroneous spelling simply because it appears in a correction record.
    Full dictation rewrites may include grammar/style edits: extract proper nouns and terms, not entire sentences.

    Return the result as a flat JSON array of strings. Example: ["Term1", "Term2", "Term3"]
    Respond with valid JSON only. Do not include explanations or markdown code fences.

    Transcription text:
    \(text)
    """
  }

  static func parseDictionaryTermsResponse(_ response: String, maxTerms: Int) -> [String] {
    let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
    var candidates = [trimmed]

    if let range = trimmed.range(of: "```json") {
      let suffix = trimmed[range.upperBound...]
      if let end = suffix.range(of: "```") {
        candidates.append(
          String(suffix[..<end.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)))
      }
    } else if let range = trimmed.range(of: "```") {
      let suffix = trimmed[range.upperBound...]
      if let end = suffix.range(of: "```") {
        candidates.append(
          String(suffix[..<end.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)))
      }
    }

    if let first = trimmed.firstIndex(of: "["), let last = trimmed.lastIndex(of: "]"),
      first < last
    {
      candidates.append(String(trimmed[first...last]))
    }

    for candidate in candidates {
      if let data = candidate.data(using: .utf8),
        let array = try? JSONSerialization.jsonObject(with: data) as? [String]
      {
        return normalizeKeywords(array, maxKeywords: maxTerms)
      }
    }

    // Fallback: extract one term per non-empty line, strip leading bullets/numbers
    let bulletPattern = try? NSRegularExpression(pattern: #"^[\d\-\*\•\.]+\s*"#)
    let terms = trimmed.components(separatedBy: .newlines).compactMap { line -> String? in
      var s = line.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !s.isEmpty else { return nil }
      if let r = bulletPattern?.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
        let range = Range(r.range, in: s)
      {
        s = String(s[range.upperBound...]).trimmingCharacters(in: .whitespaces)
      }
      s = s.trimmingCharacters(in: CharacterSet.punctuationCharacters.subtracting(.init(charactersIn: "-'")))
      return s.isEmpty ? nil : s
    }
    return normalizeKeywords(terms, maxKeywords: maxTerms)
  }
}
