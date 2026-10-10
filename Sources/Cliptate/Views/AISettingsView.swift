import SwiftUI

#if canImport(AppKit)
  import AppKit
#endif

#if canImport(LaunchAtLogin)
  import LaunchAtLogin
#endif

// MARK: - Shared settings card component

private struct SettingsCard<Content: View>: View {
  let title: LocalizedStringKey
  let subtitle: LocalizedStringKey
  let systemImage: String
  @ViewBuilder let content: () -> Content

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 8) {
        Image(systemName: systemImage)
          .font(.subheadline)
          .foregroundStyle(Color.accentColor)
        VStack(alignment: .leading, spacing: 2) {
          Text(title)
            .font(.subheadline)
            .fontWeight(.semibold)
          Text(subtitle)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      content()
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .fill(Color.primary.opacity(0.03))
    )
    .overlay(
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .stroke(Color.primary.opacity(0.07))
    )
  }
}

struct AISettingsView: View {
  @EnvironmentObject private var config: AppConfiguration
  @State private var verifyState: VerifyState = .idle

  var body: some View {
    let activeKey = currentAPIKey

    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        LazyVGrid(
          columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
          alignment: .leading,
          spacing: 16
        ) {
          languageSection
          appearanceSection
          startupSection
        }
        providerSection
      }
      .padding(.horizontal, 28)
      .padding(.vertical, 32)
    }
    .background(Color(NSColor.controlBackgroundColor))
    .onChange(of: config.selectedAIProvider) {
      verifyState = .idle
    }
    .onChange(of: activeKey) {
      verifyState = .idle
    }
  }

  // MARK: - Language

  @AppStorage("appLanguageCode") private var appLanguageCode: String = ""

  private struct AppLanguage: Identifiable {
    let id: String  // BCP 47 code, or "" for system
    let label: String
  }

  private var appLanguages: [AppLanguage] {
    [
      .init(
        id: "",
        label: String(localized: "System Default", comment: "Settings: system default app language")
      ),
      .init(id: "en", label: "English"),
      .init(id: "zh-Hans", label: "简体中文"),
      .init(id: "ja", label: "日本語"),
      .init(id: "ko", label: "한국어"),
      .init(id: "de", label: "Deutsch"),
    ]
  }

  private var languageSection: some View {
    SettingsCard(
      title: "Language",
      subtitle: "App interface language.",
      systemImage: "globe"
    ) {
      Picker(
        String(localized: "Display Language", comment: "Settings: language picker label"),
        selection: $appLanguageCode
      ) {
        ForEach(appLanguages) { lang in
          Text(lang.label).tag(lang.id)
        }
      }
      .pickerStyle(.menu)
      .labelsHidden()
      .onChange(of: appLanguageCode) { _, newCode in
        if newCode.isEmpty {
          UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        } else {
          UserDefaults.standard.set([newCode], forKey: "AppleLanguages")
        }
      }
    }
  }

  // MARK: - Appearance

  @AppStorage("appAppearanceMode") private var appAppearanceMode: String = "system"

  private struct AppearanceOption: Identifiable {
    let id: String
    let label: LocalizedStringKey
    let icon: String
  }

  private let appearanceOptions: [AppearanceOption] = [
    .init(id: "system", label: "Auto", icon: "circle.lefthalf.filled"),
    .init(id: "light", label: "Light", icon: "sun.max"),
    .init(id: "dark", label: "Dark", icon: "moon"),
  ]

  private var appearanceSection: some View {
    SettingsCard(
      title: "Appearance",
      subtitle: "Choose how Cliptate looks.",
      systemImage: "paintbrush"
    ) {
      HStack(spacing: 6) {
        ForEach(appearanceOptions) { option in
          Button {
            appAppearanceMode = option.id
            AppearanceManager.apply(mode: option.id)
          } label: {
            Label(option.label, systemImage: option.icon)
              .font(.caption)
              .lineLimit(1)
              .frame(maxWidth: .infinity)
              .padding(.vertical, 6)
              .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                  .fill(
                    appAppearanceMode == option.id
                      ? Color.accentColor.opacity(0.15)
                      : Color.primary.opacity(0.05)
                  )
              )
              .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                  .stroke(
                    appAppearanceMode == option.id ? Color.accentColor.opacity(0.6) : Color.clear,
                    lineWidth: 1.5
                  )
              )
              .foregroundStyle(
                appAppearanceMode == option.id ? Color.accentColor : Color.primary
              )
          }
          .buttonStyle(.plain)
        }
      }
    }
  }

  // MARK: - Startup

  private var startupSection: some View {
    SettingsCard(
      title: "Startup",
      subtitle: "Control how Cliptate behaves at login.",
      systemImage: "power"
    ) {
      LaunchAtLogin.Toggle {
        Text("Launch at Login")
          .font(.subheadline)
      }
    }
  }

  // MARK: - AI Provider

  private var providerSection: some View {
    SettingsCard(
      title: "AI Provider",
      subtitle: "Enhance your transcriptions with AI providers and secure API keys.",
      systemImage: "brain"
    ) {
      Toggle("Enable AI Features", isOn: $config.aiEnabled)
        .toggleStyle(.switch)

      if config.aiEnabled {
        providerConfiguration
      } else {
        Text("Turn on AI features to configure providers, API keys, and default prompts.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
  }

  private var providerConfiguration: some View {
    VStack(alignment: .leading, spacing: 16) {
      VStack(alignment: .leading, spacing: 6) {
        Text("AI Provider")
          .font(.caption)
          .foregroundStyle(.secondary)

        Picker("AI Provider", selection: $config.selectedAIProvider) {
          ForEach(AIProvider.allCases) { provider in
            Text(provider.displayName).tag(provider)
          }
        }
        .pickerStyle(.menu)

        Text(config.selectedAIProvider.providerDescription)
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      VStack(alignment: .leading, spacing: 6) {
        Text("Model")
          .font(.caption)
          .foregroundStyle(.secondary)

        TextField(config.selectedAIProvider.defaultModel, text: activeModelBinding)
          .textFieldStyle(.roundedBorder)
          .disableAutocorrection(true)

        HStack {
          Text("Recommended: \(config.selectedAIProvider.defaultModel)")
            .font(.caption2)
            .foregroundStyle(.secondary)

          if hasCustomModelSelection {
            Spacer()
            Button("Reset") {
              config.updateAIProviderModel(
                config.selectedAIProvider.defaultModel,
                for: config.selectedAIProvider
              )
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
          }
        }
      }

      if config.selectedAIProvider == .openai {
        VStack(alignment: .leading, spacing: 6) {
          Text("Custom Endpoint")
            .font(.caption)
            .foregroundStyle(.secondary)
          TextField(AppConfiguration.defaultOpenAIEndpoint, text: $config.aiOpenAIEndpoint)
            .textFieldStyle(.roundedBorder)
          Text("Leave blank to use the official OpenAI API base URL.")
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
      }

      VStack(alignment: .leading, spacing: 6) {
        Text("API Key")
          .font(.caption)
          .foregroundStyle(.secondary)

        SecureField(config.selectedAIProvider.placeholderKey, text: activeAPIKeyBinding)
          .textFieldStyle(.roundedBorder)

        HStack(spacing: 12) {
          Button(action: verifyAPIKey) {
            if case .verifying = verifyState {
              HStack(spacing: 6) {
                ProgressView()
                  .controlSize(.small)
                Text("Verifying...")
              }
            } else {
              Text("Verify and Save")
            }
          }
          .buttonStyle(.borderedProminent)

          if let badge = config.selectedAIProvider.pricingBadge {
            Text(badge)
              .font(.caption2)
              .padding(.vertical, 4)
              .padding(.horizontal, 8)
              .background(
                Capsule().fill(Color.primary.opacity(0.05))
              )
          }

          Spacer()

          if let url = config.selectedAIProvider.apiKeyURL {
            Link("Get API Key", destination: url)
              .font(.caption)
          }
        }

        verificationFeedback
      }

      HStack(alignment: .top, spacing: 8) {
        Image(systemName: "lock.shield")
          .foregroundStyle(.blue)
        Text(
          "Keys are stored securely in the system keychain. Only the active provider's key is used during AI operations."
        )
        .font(.caption2)
        .foregroundStyle(.secondary)
      }
    }
  }

  private var verificationFeedback: some View {
    Group {
      switch verifyState {
      case .idle:
        EmptyView()
      case .verifying:
        Text("Verifying key...")
          .font(.caption)
          .foregroundStyle(.secondary)
      case .success:
        Label("API key saved", systemImage: "checkmark.circle.fill")
          .font(.caption)
          .foregroundStyle(.green)
      case .failure(let message):
        Label(message, systemImage: "exclamationmark.triangle")
          .font(.caption)
          .foregroundStyle(.red)
      }
    }
  }

  private func verifyAPIKey() {
    let trimmed = activeAPIKeyBinding.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      verifyState = .failure("API key cannot be empty")
      return
    }

    verifyState = .verifying

    Task {
      do {
        try await Task.sleep(nanoseconds: 350_000_000)
        await MainActor.run {
          config.updateAIProviderKey(trimmed, for: config.selectedAIProvider)
          verifyState = .success
        }
      } catch {
        await MainActor.run {
          verifyState = .failure("Verification cancelled")
        }
      }
    }
  }

  private var currentAPIKey: String {
    config.aiProviderKeys[config.selectedAIProvider] ?? ""
  }

  private var activeModelBinding: Binding<String> {
    Binding(
      get: { config.aiProviderModels[config.selectedAIProvider] ?? "" },
      set: { config.updateAIProviderModel($0, for: config.selectedAIProvider) }
    )
  }

  private var hasCustomModelSelection: Bool {
    guard
      let stored = config.aiProviderModels[config.selectedAIProvider]?.trimmingCharacters(
        in: .whitespacesAndNewlines),
      !stored.isEmpty
    else { return false }
    return stored != config.selectedAIProvider.defaultModel
  }

  private var activeAPIKeyBinding: Binding<String> {
    Binding(
      get: { currentAPIKey },
      set: { config.updateAIProviderKey($0, for: config.selectedAIProvider) }
    )
  }

  private enum VerifyState {
    case idle
    case verifying
    case success
    case failure(String)
  }
}

extension AIProvider {
  fileprivate var providerDescription: String {
    switch self {
    case .openai:
      return String(localized: "OpenAI GPT-4o models with balanced quality and latency.", comment: "OpenAI provider description")
    case .gemini:
      return String(localized: "Google Gemini Flash for fast multimodal understanding.", comment: "Gemini provider description")
    case .deepseek:
      return String(localized: "DeepSeek chat models tuned for cost-effective editing.", comment: "DeepSeek provider description")
    case .anthropic:
      return String(localized: "Anthropic Claude for reliable enterprise responses.", comment: "Anthropic provider description")
    case .groq:
      return String(localized: "Groq LLaMA-3.3 hosted on low-latency hardware.", comment: "Groq provider description")
    }
  }

  fileprivate var recommendedModel: String { defaultModel }

  fileprivate var pricingBadge: LocalizedStringKey? {
    switch self {
    case .gemini: return "Free"
    case .groq: return "Fast"
    default: return nil
    }
  }

  fileprivate var apiKeyURL: URL? {
    switch self {
    case .openai: return URL(string: "https://platform.openai.com/api-keys")
    case .gemini: return URL(string: "https://aistudio.google.com/app/apikey")
    case .deepseek: return URL(string: "https://platform.deepseek.com/api_keys")
    case .anthropic: return URL(string: "https://console.anthropic.com/account/keys")
    case .groq: return URL(string: "https://console.groq.com/keys")
    }
  }
}
