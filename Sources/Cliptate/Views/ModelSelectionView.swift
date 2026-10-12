import SwiftUI

struct ModelSelectionView: View {
  @Binding var selectedTranscriberType: TranscriberType
  @Binding var selectedModel: ModelVariant
  @Binding var selectedLanguage: Language
  var isInteractionDisabled = false

  @StateObject private var paywallManager = PaywallManager.shared
  @State private var modelDownloadStatuses: [ModelVariant: ModelDownloadStatus] = [:]
  @State private var permissionMap: [ModelVariant: ModelDownloadPermission] = [:]
  @State private var lastSelectedModelByTranscriber: [TranscriberType: ModelVariant] = [:]

  var body: some View {
    GroupBox("Transcription Model") {
      VStack(alignment: .leading, spacing: 12) {
        // Engine Selection
        VStack(alignment: .leading, spacing: 8) {
          Text("Engine")
            .font(.headline)

          Picker("Engine", selection: $selectedTranscriberType) {
            ForEach(TranscriberType.selectableCases) { type in
              Text(type.displayName).tag(type)
            }
          }
          .pickerStyle(SegmentedPickerStyle())

          Text(selectedTranscriberType.description)
            .font(.caption)
            .foregroundColor(.secondary)
            .padding(.top, 2)
        }

        // Model Selection (Whisper or Parakeet)
        if !selectedTranscriberType.supportedModels.isEmpty {
          Divider()
            .padding(.vertical, 4)

          VStack(alignment: .leading, spacing: 8) {
            HStack {
              Text(selectedEngineModelLabel)
                .font(.headline)
            }

            if downloadedModels.isEmpty {
              VStack(alignment: .leading, spacing: 6) {
                Text(noDownloadedModelsMessage)
                  .font(.caption)
                  .foregroundColor(.secondary)
                Button("Open Models Library") {
                  NotificationCenter.default.post(name: .openModelsLibrary, object: nil)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
              }
            } else {
              Picker(selectedEngineModelLabel, selection: $selectedModel) {
                ForEach(downloadedModels, id: \.self) { model in
                  HStack {
                    Text(model.displayName)
                    Spacer()
                    Text("(\(model.fileSize)MB, \(model.accuracy))")
                      .font(.caption)
                      .foregroundColor(.secondary)
                  }
                  .tag(model)
                }
              }
              .pickerStyle(MenuPickerStyle())
            }

            if !premiumShortcutModelsForSelection.isEmpty {
              premiumShortcutSection
            }

            if let status = modelDownloadStatuses[selectedModel] {
              HStack(spacing: 6) {
                ModelDownloadStatusView(
                  status: status,
                  showLabel: true,
                  textFont: .caption,
                  textColor: .secondary
                )

                if status == .checking {
                  ProgressView()
                    .controlSize(.small)
                } else if status == .notDownloaded {
                  Text("Model is not downloaded. Download it from the Models page before use.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                } else {
                  Text("Model is ready for use.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                }
              }
              .padding(.top, 2)
            } else {
              HStack(spacing: 6) {
                ProgressView()
                  .controlSize(.small)
                Text("Checking model status...")
                  .font(.caption2)
                  .foregroundColor(.secondary)
              }
              .padding(.top, 2)
            }

            // Model details
            HStack {
              Label("\(selectedModel.fileSize)MB", systemImage: "doc.circle")
              Label(selectedModel.accuracy, systemImage: "checkmark.circle")
            }
            .font(.caption)
            .foregroundColor(.secondary)
            .padding(.top, 2)
          }
        }

        // Language Selection
        Divider()
          .padding(.vertical, 4)

        VStack(alignment: .leading, spacing: 8) {
          Text("Language")
            .font(.headline)

          Picker("Language", selection: $selectedLanguage) {
            ForEach(orderedLanguages(for: selectedModel), id: \.self) { language in
              Text(language.displayName).tag(language)
            }
          }
          .pickerStyle(MenuPickerStyle())

          if let languageNotice = languageRestrictionNotice {
            HStack(alignment: .top, spacing: 6) {
              Image(systemName: "info.circle")
                .foregroundColor(.blue)
              Text(languageNotice)
            }
            .font(.caption)
            .foregroundColor(.secondary)
            .padding(.top, 2)
          }
        }

        // Additional Features Information
        if !modelHighlightItems.isEmpty {
          Divider()
            .padding(.vertical, 4)

          VStack(alignment: .leading, spacing: 8) {
            Text("Model Highlights")
              .font(.headline)

            ForEach(modelHighlightItems, id: \.self) { item in
              HStack(alignment: .top, spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                  .foregroundColor(.green)
                Text(item)
              }
              .font(.caption)
              .foregroundColor(.secondary)
            }
          }
        }
      }
      .padding()
      .onAppear {
        lastSelectedModelByTranscriber[selectedTranscriberType] = selectedModel
        ensureModelIsValid(for: selectedTranscriberType)
        ensureLanguageIsValid(for: selectedModel)

        Task {
          await loadModelDownloadStatuses()
          await loadPremiumPermissions()
        }
      }
      .onReceive(NotificationCenter.default.publisher(for: .modelArtifactsDidChange)) { _ in
        Task {
          await loadModelDownloadStatuses()
        }
      }
      .onChange(of: selectedTranscriberType) { newType, previousType in
        handleTranscriberTypeChange(newType, previousType: previousType)
      }
      .onChange(of: selectedModel) { newModel, _ in
        lastSelectedModelByTranscriber[selectedTranscriberType] = newModel
        ensureLanguageIsValid(for: newModel)
      }
    }
    .disabled(isInteractionDisabled)
    .preference(key: ModelSelectionStatusesPreferenceKey.self, value: modelDownloadStatuses)
    .sheet(isPresented: paywallPresentationBinding) {
      PaywallView()
        .environmentObject(paywallManager)
    }
    .onChange(of: paywallManager.latestPurchaseEvent) { _, event in
      guard event != nil else { return }
      Task {
        await loadPremiumPermissions()
        await loadModelDownloadStatuses()
      }
    }
  }

  private func loadModelDownloadStatuses() async {
    let checker = ModelDownloadStatusChecker.shared
    let currentType = selectedTranscriberType
    let models = orderedModels(for: currentType)

    await MainActor.run {
      for model in models {
        modelDownloadStatuses[model] = .checking
      }
      // 清理其他模型的状态，避免跨引擎的残留显示
      let validKeys = Set(models)
      modelDownloadStatuses = modelDownloadStatuses.filter { validKeys.contains($0.key) }
    }

    let fetchedStatuses = await checker.getStatuses(for: models)

    await MainActor.run {
      guard selectedTranscriberType == currentType else { return }
      for model in models {
        if let isDownloaded = fetchedStatuses[model] {
          modelDownloadStatuses[model] = isDownloaded ? .downloaded : .notDownloaded
        } else {
          modelDownloadStatuses[model] = .notDownloaded
        }
      }
      enforceDownloadedSelection(for: models)
    }
  }

  private func handleTranscriberTypeChange(
    _ newType: TranscriberType, previousType: TranscriberType
  ) {
    lastSelectedModelByTranscriber[previousType] = selectedModel

    if let rememberedModel = lastSelectedModelByTranscriber[newType],
      newType.supportedModels.contains(rememberedModel)
    {
      selectedModel = rememberedModel
    } else {
      ensureModelIsValid(for: newType)
    }

    ensureLanguageIsValid(for: selectedModel)

    Task {
      await loadModelDownloadStatuses()
      await loadPremiumPermissions()
    }
  }

  private func loadPremiumPermissions() async {
    let currentType = selectedTranscriberType
    let models = orderedModels(for: currentType).filter(\.requiresProSubscription)

    await MainActor.run {
      for model in models {
        permissionMap[model] = ModelDownloadPermission(
          model: model,
          isAllowed: false,
          reason: .loading
        )
      }

      let validKeys = Set(models)
      permissionMap = permissionMap.filter { validKeys.contains($0.key) }
    }

    var permissions: [ModelVariant: ModelDownloadPermission] = [:]
    for model in models {
      do {
        permissions[model] = try await ModelAccessController.shared.checkPermission(for: model)
      } catch {
        permissions[model] = ModelDownloadPermission(
          model: model,
          isAllowed: false,
          reason: .offline
        )
      }
    }

    await MainActor.run {
      guard selectedTranscriberType == currentType else { return }
      permissionMap = permissions
    }
  }

  private func ensureModelIsValid(for type: TranscriberType) {
    let ordered = orderedModels(for: type)
    guard !ordered.isEmpty else { return }

    if !type.supportedModels.contains(selectedModel),
      let fallback = ordered.first(where: { downloadedModels.contains($0) }) ?? ordered.first
    {
      selectedModel = fallback
    }
  }

  private func ensureLanguageIsValid(for model: ModelVariant) {
    let supportedLanguages = orderedLanguages(for: model)
    guard !supportedLanguages.isEmpty else { return }

    if !supportedLanguages.contains(selectedLanguage) {
      selectedLanguage = supportedLanguages.first ?? selectedLanguage
    }
  }

  private var selectedEngineModelLabel: String {
    String(
      format: NSLocalizedString("%@ Model", comment: "Model label format including engine name"),
      selectedTranscriberType.displayName
    )
  }

  private var noDownloadedModelsMessage: String {
    String(
      format: NSLocalizedString("No downloaded models found for %@.", comment: "Missing downloaded models message for selected engine"),
      selectedTranscriberType.displayName
    )
  }

  private var premiumShortcutModelsForSelection: [ModelVariant] {
    Self.premiumShortcutModels(
      for: selectedTranscriberType,
      downloadStatuses: modelDownloadStatuses,
      permissions: permissionMap
    )
  }

  private var premiumShortcutSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Unlock Professional Models")
        .font(.subheadline.weight(.semibold))

      Text("Tap a premium model to open plans and continue.")
        .font(.caption)
        .foregroundColor(.secondary)

      ForEach(premiumShortcutModelsForSelection, id: \.self) { model in
        Button {
          presentPaywall(for: model)
        } label: {
          HStack(spacing: 8) {
            Image(systemName: "lock.fill")
            Text(model.displayName)
            Spacer()
            Text("Unlock Pro")
              .font(.caption.weight(.semibold))
          }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
      }
    }
    .padding(.top, 4)
  }

  private var languageRestrictionNotice: String? {
    switch selectedModel {
    case _ where selectedModel.isWhisperModel:
      return String(localized: "Whisper requires a selected language. Enable forced alignment for precise word timestamps.")
    case .fireRedASR2:
      return NSLocalizedString(
        "Supports Mandarin, 20+ Chinese dialects and accents, English, mixed Chinese-English speech, and lyrics recognition.",
        comment: "FireRed language support notice"
      )
    case .parakeetV2:
      return String(localized: "Parakeet v2 is English-only.", comment: "Warning: Parakeet v2 model only supports English")
    case .parakeetV3:
      return String(localized: "Parakeet v3 supports 25 European languages.", comment: "Info: Parakeet v3 language support")
    default:
      return nil
    }
  }

  private var modelHighlightItems: [String] {
    selectedModel.featureHighlights
  }

  private var downloadedModels: [ModelVariant] {
    orderedModels(for: selectedTranscriberType).filter {
      modelDownloadStatuses[$0] == .downloaded
    }
  }

  private func presentPaywall(
    for model: ModelVariant,
    reason: PaywallContext.PaywallReason = .attemptedPaidModelDownload
  ) {
    Task {
      _ = await paywallManager.showPaywall(for: model, reason: reason)
    }
  }

  static func premiumShortcutModels(
    for type: TranscriberType,
    downloadStatuses: [ModelVariant: ModelDownloadStatus],
    permissions: [ModelVariant: ModelDownloadPermission]
  ) -> [ModelVariant] {
    type.supportedModels.filter { model in
      guard model.requiresProSubscription else { return false }
      guard downloadStatuses[model] != .downloaded else { return false }
      guard let permission = permissions[model] else { return false }
      return !permission.isAllowed
    }
  }

  private var paywallPresentationBinding: Binding<Bool> {
    Binding(
      get: { paywallManager.isPresented },
      set: { isPresented in
        if !isPresented {
          paywallManager.dismissPaywall()
        }
      }
    )
  }

  @MainActor
  private func enforceDownloadedSelection(for models: [ModelVariant]) {
    guard Set(selectedTranscriberType.supportedModels) == Set(models) else { return }
    if modelDownloadStatuses[selectedModel] != .downloaded {
      if let fallback = downloadedModels.first {
        selectedModel = fallback
      }
    }
  }

  private func orderedModels(for type: TranscriberType) -> [ModelVariant] {
    Array(type.supportedModels.reversed())
  }

  private func orderedLanguages(for model: ModelVariant) -> [Language] {
    let languages = model.supportedLanguages
    guard model.isParakeetModel else { return languages }

    let priority: [Language] = [.english, .chinese]
    let prioritized = priority.filter { languages.contains($0) }
    let remaining = languages.filter { !priority.contains($0) }
      .sorted { $0.displayName < $1.displayName }
    return prioritized + remaining
  }
}

struct ModelDownloadStatusView: View {
  let status: ModelDownloadStatus
  var showLabel: Bool = false
  var textFont: Font = .caption2
  var textColor: Color = .secondary

  var body: some View {
    HStack(spacing: 4) {
      Image(systemName: status.icon)
        .font(.caption)
        .foregroundColor(status.iconColor)

      if showLabel || status != .checking {
        Text(status.displayText)
          .font(textFont)
          .foregroundColor(textColor)
      }
    }
  }
}

private struct ModelSelectionStatusesPreferenceKey: PreferenceKey {
  static var defaultValue: [ModelVariant: ModelDownloadStatus] { [:] }

  static func reduce(
    value: inout [ModelVariant: ModelDownloadStatus],
    nextValue: () -> [ModelVariant: ModelDownloadStatus]
  ) {
    value = nextValue()
  }
}

extension View {
  func onModelSelectionStatusesChange(
    _ action: @escaping ([ModelVariant: ModelDownloadStatus]) -> Void
  ) -> some View {
    onPreferenceChange(ModelSelectionStatusesPreferenceKey.self, perform: action)
  }
}

#Preview {
  ModelSelectionView(
    selectedTranscriberType: .constant(.parakeet),
    selectedModel: .constant(.parakeetV3),
    selectedLanguage: .constant(.english)
  )
  .padding()
}
