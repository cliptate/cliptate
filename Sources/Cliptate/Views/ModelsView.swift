import SwiftUI

struct ModelsView: View {
  enum ModelCategory: String, CaseIterable, Identifiable {
    case vad
    case asr
    case align
    case tts

    var id: String { rawValue }

    var displayName: String {
      switch self {
      case .asr:   return String(localized: "ASR",   comment: "Model category: Automatic Speech Recognition")
      case .align: return String(localized: "Align", comment: "Model category: Forced alignment")
      case .vad:   return String(localized: "VAD",   comment: "Model category: Voice Activity Detection")
      case .tts:   return String(localized: "TTS",   comment: "Model category: Text To Speech")
      }
    }

    var icon: String {
      switch self {
      case .asr: return "waveform"
      case .align: return "text.alignleft"
      case .vad: return "waveform.badge.magnifyingglass"
      case .tts: return "waveform.badge.mic"
      }
    }
  }

  enum ASRProvider: String, CaseIterable, Identifiable {
    case all
    case whisper
    case parakeet
    case qwen3
    case fireRed
    case nemotron
    case cohere

    var id: String { rawValue }

    var displayName: String {
      switch self {
      case .all:      return String(localized: "All",      comment: "ASR provider filter: show all providers")
      case .whisper: return String(localized: "Whisper")
      case .parakeet: return String(localized: "Parakeet", comment: "ASR provider name: Parakeet")
      case .qwen3:    return String(localized: "Qwen3",    comment: "ASR provider name: Qwen3 ASR")
      case .fireRed:
        return NSLocalizedString("FireRed", comment: "FireRed ASR provider filter label")
      case .nemotron: return String(localized: "Nemotron ASR")
      case .cohere:
        return NSLocalizedString("Cohere", comment: "Cohere ASR provider filter label")
      }
    }
  }

  static func asrModels(for provider: ASRProvider) -> [ModelVariant] {
    switch provider {
    case .all:
      TranscriberType.whisper.supportedModels
        + TranscriberType.parakeet.supportedModels
        + TranscriberType.qwen3.supportedModels
        + TranscriberType.fireRed.supportedModels
        + TranscriberType.cohere.supportedModels
        + TranscriberType.nemotron.supportedModels
    case .whisper:
      TranscriberType.whisper.supportedModels
    case .parakeet:
      TranscriberType.parakeet.supportedModels
    case .qwen3:
      TranscriberType.qwen3.supportedModels
    case .fireRed:
      TranscriberType.fireRed.supportedModels
    case .nemotron:
      TranscriberType.nemotron.supportedModels
    case .cohere:
      TranscriberType.cohere.supportedModels
    }
  }

  fileprivate enum TTSProvider: String, CaseIterable, Identifiable {
    case all
    case qwen3

    var id: String { rawValue }

    var displayName: String {
      switch self {
      case .all:   return String(localized: "All",   comment: "TTS provider filter: show all providers")
      case .qwen3: return String(localized: "Qwen3", comment: "TTS provider name: Qwen3 TTS")
      }
    }
  }

  @EnvironmentObject private var config: AppConfiguration
  @EnvironmentObject private var downloadState: ModelDownloadStateStore

  @SceneStorage("ModelsView.selectedCategory") private var selectedCategoryStorage: String = "asr"
  @SceneStorage("ModelsView.asrProvider") private var asrProviderStorage: String = "all"
  @SceneStorage("ModelsView.ttsProvider") private var ttsProviderStorage: String = "all"
  @SceneStorage("ModelsView.searchText") private var searchText: String = ""
  @State private var showDownloadedOnly: Bool = false
  @State private var isRefreshing = false
  @State private var mlxModelDiskMB: [String: Int] = [:]
  @StateObject private var paywallManager = PaywallManager.shared
  @State private var subscriptionStatus: SubscriptionStatus?
  @State private var permissionMap: [ModelVariant: ModelDownloadPermission] = [:]
  @State private var subscriptionMonitorTask: Task<Void, Never>?
  @State private var purchaseBanner: PurchaseBanner?
  @State private var bannerTask: Task<Void, Never>?
  @State private var isPreloadingAlignModel = false
  @State private var isPreloadingTTSModel = false
  @State private var isClearingModelCache = false
  @State private var showClearCacheConfirmation = false
  @State private var cacheActionErrorMessage: String?
  @State private var showHeaderToolsPopover = false
  @AppStorage("ModelsView.dismissedProPromo") private var hasDismissedProPromo: Bool = false

  var body: some View {
    mainContent
      .animation(.spring(response: 0.35, dampingFraction: 0.85), value: shouldShowProPromo)
      .overlay(alignment: .top) {
        if let banner = purchaseBanner {
          PurchaseBannerView(banner: banner)
            .padding(.top, 12)
            .padding(.horizontal, 32)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
      }
      .task {
        await refreshStatuses()
      }
      .onReceive(NotificationCenter.default.publisher(for: .modelArtifactsDidChange)) { _ in
        Task { await refreshStatuses(force: true) }
      }
      .onChange(of: selectedCategoryStorage) { _, _ in
        Task { await refreshStatuses() }
      }
      .onChange(of: config.transcriberType) { _, _ in
        Task { await config.refreshModelLifecycleState() }
      }
      .onChange(of: config.modelVariant) { _, _ in
        Task { await config.refreshModelLifecycleState() }
      }
      .onChange(of: config.alignModelVariant) { _, _ in
        Task { await config.refreshModelLifecycleState() }
      }
      .onChange(of: config.ttsEngine) { _, _ in
        Task { await config.refreshModelLifecycleState() }
      }
      .onChange(of: config.ttsMLXModelId) { _, _ in
        Task { await config.refreshModelLifecycleState() }
      }
      .onAppear {
        startSubscriptionMonitoringIfNeeded()
      }
      .onDisappear {
        stopSubscriptionMonitoring()
        bannerTask?.cancel()
        bannerTask = nil
        purchaseBanner = nil
      }
      .onChange(of: paywallManager.latestPurchaseEvent) { _, event in
        guard let event else { return }
        handlePurchaseEvent(event)
        paywallManager.consumeLatestPurchaseEvent(event.id)
      }
      .sheet(isPresented: paywallPresentationBinding) {
        PaywallView()
          .environmentObject(paywallManager)
      }
      .confirmationDialog(
        "Clear cached models?",
        isPresented: $showClearCacheConfirmation,
        titleVisibility: .visible
      ) {
        Button("Clear Cache", role: .destructive) {
          clearModelCache()
        }
        Button("Cancel", role: .cancel) {}
      } message: {
        Text(
          "This preserves the selected ASR model until its idle timeout expires; other cached models may be cleared immediately."
        )
      }
      .alert(
        "Model Cache",
        isPresented: Binding(
          get: { cacheActionErrorMessage != nil },
          set: { if !$0 { cacheActionErrorMessage = nil } }
        )
      ) {
        Button("OK", role: .cancel) { cacheActionErrorMessage = nil }
      } message: {
        Text(cacheActionErrorMessage ?? "")
      }
  }

  private var mainContent: some View {
    VStack(alignment: .leading, spacing: 0) {
      // ── Dashboard Header ─────────────────────────────────────────
      dashboardHeader

      if shouldShowProPromo {
        proPromoBanner
          .padding(.horizontal, 28)
          .padding(.bottom, 14)
          .transition(.move(edge: .top).combined(with: .opacity))
      }

      // ── Filter Bar ───────────────────────────────────────────────
      filterBar

      // ── Model List ───────────────────────────────────────────────
      ScrollView {
        if selectedCategory == .tts {
          LazyVStack(alignment: .leading, spacing: 10) {
            ttsActiveSummaryCard
              .padding(.bottom, 2)

            ttsProviderPicker
              .padding(.bottom, 2)

            ttsLibrarySection
          }
          .padding(.horizontal, 28)
          .padding(.vertical, 16)
        } else {
          LazyVStack(spacing: 10) {
            if selectedCategory == .asr {
              asrSelectionHeader
                .padding(.bottom, 2)

              asrProviderPicker
                .padding(.bottom, 2)

              let models = filteredModels
              if models.isEmpty {
                emptyState
              } else {
                ForEach(models, id: \.self) { model in
                  modelCard(for: model)
                }
              }
            } else if selectedCategory == .align {
              alignSelectionHeader
                .padding(.bottom, 2)

              let models = filteredModels
              if models.isEmpty {
                emptyState
              } else {
                ForEach(models, id: \.self) { model in
                  modelCard(for: model)
                }
              }
            } else {
              vadSelectionHeader
                .padding(.bottom, 2)

              let models = filteredModels
              if models.isEmpty {
                emptyState
              } else {
                ForEach(models, id: \.self) { model in
                  modelCard(for: model)
                }
              }
            }
          }
          .padding(.horizontal, 28)
          .padding(.vertical, 16)
        }
      }
    }
    .background(AppSurface.pageBackground)
  }

  // MARK: - Dashboard Header

  private var dashboardHeader: some View {
    VStack(alignment: .leading, spacing: 0) {
      AppPageHeader {
        HStack(spacing: 16) {
          // Title block
          VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
              Image(systemName: "square.stack.3d.down.right.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.accentColor)
              Text("Models Library")
                .font(.title2.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            }
            Text("Manage local AI models, download status and active selections")
              .font(.system(size: 12))
              .foregroundStyle(.secondary)
          }

          Spacer()

          // Stat pills
          HStack(spacing: 10) {
            let stats = summaryStats ?? (0, 0)
            ModelsStatPill(
              icon: "checkmark.circle.fill",
              value: "\(stats.downloadedCount)",
              label: String(localized: "Downloaded"),
              color: .green
            )
            ModelsStatPill(
              icon: "externaldrive.fill",
              value: "\(stats.totalDiskUsage) MB",
              label: String(localized: "Disk Usage"),
              color: Color.accentColor
            )
            ModelsStatPill(
              icon: "memorychip.fill",
              value: "\(config.modelLifecycleTotalMemoryMB) MB",
              label: String(localized: "Cache Memory"),
              color: Color.accentColor
            )
          }

          // Action buttons
          HStack(spacing: 8) {
            Button(action: { Task { await refreshStatuses(force: true) } }) {
              Label("Refresh", systemImage: "arrow.clockwise")
                .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(isRefreshing)
            .accessibilityLabel("Refresh model statuses")

            Button {
              showHeaderToolsPopover.toggle()
            } label: {
              Image(systemName: "ellipsis.circle")
                .font(.system(size: 14, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .popover(isPresented: $showHeaderToolsPopover, arrowEdge: .top) {
              VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                  Button(action: preloadSelectedAlignModel) {
                    if isPreloadingAlignModel {
                      Label("Preloading Align...", systemImage: "hourglass")
                    } else {
                      Label("Preload Align", systemImage: "text.alignleft")
                    }
                  }
                  .buttonStyle(.bordered)
                  .controlSize(.small)
                  .disabled(isPreloadingAlignModel || config.alignModelVariant == nil)

                  Button(action: preloadSelectedTTSModel) {
                    if isPreloadingTTSModel {
                      Label("Preloading TTS...", systemImage: "hourglass")
                    } else {
                      Label("Preload TTS", systemImage: "waveform.badge.mic")
                    }
                  }
                  .buttonStyle(.bordered)
                  .controlSize(.small)
                  .disabled(isPreloadingTTSModel)
                }

                Button(role: .destructive) {
                  showClearCacheConfirmation = true
                  showHeaderToolsPopover = false
                } label: {
                  if isClearingModelCache {
                    Label("Clearing...", systemImage: "trash")
                  } else {
                    Label("Clear Cache", systemImage: "trash")
                  }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isClearingModelCache)

                Divider()
                cacheStatusOverview
                Divider()
                asrIdleTimeoutControl
              }
              .padding(16)
              .frame(width: 360)
            }
          }
        }
      }

      // Error strip
      if let cacheErrorStatus = cacheErrorStatuses.first,
        case .error(let message) = cacheErrorStatus.state
      {
        HStack(spacing: 8) {
          Image(systemName: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundStyle(.red)
          Text(message)
            .font(.caption)
            .foregroundStyle(.red)
            .lineLimit(2)
          Spacer()
          Button("Retry") {
            retryFailedCacheLoads()
          }
          .buttonStyle(.bordered)
          .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.red.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(.horizontal, 24)
        .padding(.bottom, 10)
      }
    }
  }

  // MARK: - Filter Bar

  private var filterBar: some View {
    HStack(spacing: 12) {
      // Category chips
      HStack(spacing: 6) {
        ForEach(ModelCategory.allCases) { category in
          let style = Self.categoryStyle(for: category)
          let isSelected = selectedCategory == category
          Button {
            selectedCategoryBinding.wrappedValue = category
          } label: {
            HStack(spacing: 5) {
              Image(systemName: category.icon)
                .font(.system(size: 11, weight: .semibold))
              Text(category.displayName)
                .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
            }
            .foregroundStyle(isSelected ? style.accent.color : Color.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
              Capsule()
                .fill(isSelected ? style.accent.color.opacity(0.13) : Color.clear)
            )
            .overlay(
              Capsule()
                .stroke(
                  isSelected ? style.accent.color.opacity(0.35) : Color.secondary.opacity(0.18),
                  lineWidth: 1
                )
            )
          }
          .buttonStyle(.plain)
        }
      }

      Spacer()

      // Search
      searchField

      // Downloaded filter
      Button {
        showDownloadedOnly.toggle()
      } label: {
        HStack(spacing: 5) {
          Image(systemName: showDownloadedOnly ? "checkmark.circle.fill" : "arrow.down.circle")
            .font(.system(size: 11, weight: .semibold))
          Text("Downloaded")
            .font(.system(size: 13, weight: .medium))
        }
        .foregroundStyle(showDownloadedOnly ? Color.accentColor : Color.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
          Capsule()
            .fill(showDownloadedOnly ? Color.accentColor.opacity(0.12) : Color.clear)
        )
        .overlay(
          Capsule()
            .stroke(
              showDownloadedOnly ? Color.accentColor.opacity(0.35) : Color.secondary.opacity(0.18),
              lineWidth: 1
            )
        )
      }
      .buttonStyle(.plain)
    }
    .padding(.horizontal, 24)
    .padding(.vertical, 10)
    .background(AppSurface.pageBackground)
    .overlay(alignment: .bottom) {
      Divider()
    }
  }


  private var cacheStatusOverview: some View {
    HStack(spacing: 10) {
      cacheStatusBadge(
        title: "ASR",
        key: ModelLifecycleKey(
          kind: .asr,
          identifier: "\(config.transcriberType.rawValue):\(config.modelVariant.rawValue)"
        )
      )

      if let alignModel = config.alignModelVariant {
        cacheStatusBadge(
          title: "Align",
          key: ModelLifecycleKey(kind: .align, identifier: alignModel.rawValue)
        )
      }

      cacheStatusBadge(
        title: "TTS",
        key: ModelLifecycleKey(
          kind: .tts,
          identifier: "\(config.ttsEngine.rawValue):\(selectedTTSModelIdentifier)"
        )
      )
    }
    .padding(.top, 4)
  }

  private var asrIdleTimeoutControl: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("ASR Idle Timeout")
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)

      HStack(spacing: 12) {
        Slider(
          value: Binding(
            get: { config.asrIdleTimeoutSeconds },
            set: { config.asrIdleTimeoutSeconds = $0.rounded() }
          ),
          in: 60...3600,
          step: 60
        )
        Text("\(Int(config.asrIdleTimeoutSeconds / 60)) min")
          .font(.caption.monospacedDigit())
          .foregroundStyle(.secondary)
          .frame(width: 56, alignment: .trailing)
      }

      Text(
        "Shared ASR models used by AI Cut and Voice To Text are released after this idle period."
      )
      .font(.caption)
      .foregroundStyle(.secondary)
    }
    .frame(maxWidth: 320, alignment: .leading)
  }

  private var cacheErrorStatuses: [ModelLifecycleStatus] {
    config.modelLifecycleStatuses.filter {
      if case .error = $0.state {
        return true
      }
      return false
    }
  }

  private func cacheStatusBadge(title: String, key: ModelLifecycleKey) -> some View {
    let status = config.modelLifecycleStatuses.first(where: { $0.key == key })
    let state = status?.state ?? .notLoaded
    let color: Color
    let label: String

    switch state {
    case .notLoaded:
      color = .secondary
      label = "Not Loaded"
    case .loading:
      color = .blue
      label = "Loading"
    case .loaded:
      color = .green
      label = "Loaded"
    case .error:
      color = .red
      label = "Error"
    }

    return HStack(spacing: 6) {
      if case .loading = state {
        ProgressView()
          .controlSize(.small)
      } else {
        Circle()
          .fill(color)
          .frame(width: 8, height: 8)
      }

      Text("\(title): \(label)")
        .font(.caption)
        .foregroundStyle(.secondary)

      if let status, status.memoryUsageMB > 0 {
        Text("\(status.memoryUsageMB)MB")
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel(String(localized: "\(title) cache status: \(label)", comment: "Accessibility: model cache status pill"))
    .padding(.horizontal, 10)
    .padding(.vertical, 6)
    .background(
      Capsule()
        .fill(color.opacity(0.12))
    )
  }

  private var proPromoBanner: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .firstTextBaseline) {
        Label("Unlock Pro Accuracy", systemImage: "sparkles")
          .font(.headline)
        Spacer()
        Button(role: .cancel) {
          withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            hasDismissedProPromo = true
          }
        } label: {
          Image(systemName: "xmark")
            .font(.system(size: 12, weight: .bold))
            .foregroundColor(.secondary)
            .padding(6)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Dismiss Pro promotion")
      }

      Text(
        "Install premium Whisper and Parakeet variants for faster, more accurate transcription. Cliptate keeps your downloads unlimited."
      )
      .font(.subheadline)
      .foregroundStyle(.secondary)

      HStack(spacing: 12) {
        Button {
          presentPaywall(
            for: ModelVariant.proModels.first ?? .parakeetV3, reason: .userInitiated)
        } label: {
          Text("View Plans")
            .font(.system(size: 13, weight: .semibold))
        }
        .buttonStyle(.borderedProminent)

        Button {
          withAnimation(.easeInOut(duration: 0.2)) {
            hasDismissedProPromo = true
          }
        } label: {
          Text("Maybe Later")
            .font(.system(size: 13, weight: .medium))
        }
        .buttonStyle(.bordered)
      }
    }
    .padding(.vertical, 18)
    .padding(.horizontal, 20)
    .background(
      RoundedRectangle(cornerRadius: 18, style: .continuous)
        .fill(Color.accentColor.opacity(0.12))
    )
    .overlay(
      RoundedRectangle(cornerRadius: 18, style: .continuous)
        .stroke(Color.accentColor.opacity(0.2))
    )
  }

  private var categoryPicker: some View {
    HStack(spacing: 8) {
      ForEach(ModelCategory.allCases) { category in
        let style = Self.categoryStyle(for: category)
        let isSelected = selectedCategory == category
        Button {
          selectedCategoryBinding.wrappedValue = category
        } label: {
          HStack(spacing: 6) {
            Image(systemName: category.icon)
            Text(category.displayName)
          }
          .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
          .padding(.horizontal, 12)
          .padding(.vertical, 7)
          .background(
            Capsule()
              .fill(isSelected ? style.accent.color.opacity(0.14) : Color.clear)
          )
          .overlay(
            Capsule()
              .stroke(
                isSelected ? style.accent.color.opacity(0.28) : Color.secondary.opacity(0.2),
                lineWidth: 1
              )
          )
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? style.accent.color : Color.secondary)
      }
    }
    .accessibilityLabel("Model category")
  }

  private var asrProviderPicker: some View {
    let accentColor = Self.categoryStyle(for: .asr).accent.color
    return HStack(spacing: 6) {
      ForEach(ASRProvider.allCases) { provider in
        Button {
          asrProviderStorage = provider.rawValue
        } label: {
          Text(provider.displayName)
            .font(.system(size: 12, weight: selectedASRProvider == provider ? .semibold : .medium))
            .foregroundStyle(selectedASRProvider == provider ? accentColor : Color.secondary)
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .background(
              Capsule()
                .fill(
                  selectedASRProvider == provider
                    ? accentColor.opacity(0.12) : Color.secondary.opacity(0.07))
            )
            .overlay(
              Capsule()
                .stroke(
                  selectedASRProvider == provider
                    ? accentColor.opacity(0.3) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
      }
      Spacer()
    }
  }

  private var ttsProviderPicker: some View {
    let accentColor = Self.categoryStyle(for: .tts).accent.color
    return HStack(spacing: 6) {
      ForEach(TTSProvider.allCases) { provider in
        Button {
          ttsProviderStorage = provider.rawValue
        } label: {
          Text(provider.displayName)
            .font(.system(size: 12, weight: selectedTTSProvider == provider ? .semibold : .medium))
            .foregroundStyle(selectedTTSProvider == provider ? accentColor : Color.secondary)
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .background(
              Capsule()
                .fill(
                  selectedTTSProvider == provider
                    ? accentColor.opacity(0.12) : Color.secondary.opacity(0.07))
            )
            .overlay(
              Capsule()
                .stroke(
                  selectedTTSProvider == provider
                    ? accentColor.opacity(0.3) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
      }
      Spacer()
    }
  }

  private var alignSelectionHeader: some View {
    HStack(spacing: 10) {
      Image(systemName: "text.alignleft")
        .font(.system(size: 16, weight: .semibold))
        .foregroundStyle(Self.categoryStyle(for: .align).accent.color)
      Text("Forced Alignment Models")
        .font(.system(size: 15, weight: .bold))
      if let selected = config.alignModelVariant {
        CompactStatusBadge(
          title: String(localized: "Active"),
          color: Self.statusStyle(for: .active).tone.color
        )
        CompactInfoBadge(text: selected.displayName)
      } else {
        CompactInfoBadge(text: String(localized: "No align model selected"))
      }
      Spacer()
      if config.alignModelVariant != nil {
        Button {
          config.alignModelVariant = nil
        } label: {
          Label("Deselect", systemImage: "xmark.circle")
            .font(.system(size: 12, weight: .medium))
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
      }
    }
    .padding(.vertical, 4)
  }

  private var asrSelectionHeader: some View {
    HStack(spacing: 10) {
      Image(systemName: "waveform")
        .font(.system(size: 16, weight: .semibold))
        .foregroundStyle(Self.categoryStyle(for: .asr).accent.color)
      Text("ASR Models")
        .font(.system(size: 15, weight: .bold))
      CompactStatusBadge(
        title: String(localized: "Active"),
        color: Self.statusStyle(for: .active).tone.color
      )
      CompactInfoBadge(text: config.modelVariant.displayName)
      CompactInfoBadge(text: config.transcriberType.displayName)
      Spacer()
    }
    .padding(.vertical, 4)
  }

  private var vadSelectionHeader: some View {
    HStack(spacing: 10) {
      Image(systemName: "waveform.badge.magnifyingglass")
        .font(.system(size: 16, weight: .semibold))
        .foregroundStyle(Self.categoryStyle(for: .vad).accent.color)
      Text("VAD Models")
        .font(.system(size: 15, weight: .bold))
      CompactStatusBadge(
        title: String(localized: "Active"),
        color: Self.statusStyle(for: .active).tone.color
      )
      CompactInfoBadge(text: config.vadModelVariant.displayName)
      Spacer()
    }
    .padding(.vertical, 4)
  }

  private var searchField: some View {
    HStack(spacing: 8) {
      Image(systemName: "magnifyingglass")
        .foregroundColor(.secondary)
        .font(.system(size: 13))
      TextField("Search models...", text: $searchText)
        .textFieldStyle(.plain)
        .font(.system(size: 13))
      if !searchText.isEmpty {
        Button(action: { searchText = "" }) {
          Image(systemName: "xmark.circle.fill")
            .foregroundColor(.secondary)
        }
        .buttonStyle(.plain)
      }
    }
    .padding(.horizontal, 11)
    .padding(.vertical, 7)
    .background(
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .fill(Color(NSColor.textBackgroundColor))
    )
    .overlay(
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
    )
    .frame(width: 220)
  }

  private var emptyState: some View {
    VStack(spacing: 16) {
      Image(systemName: showDownloadedOnly ? "tray" : "magnifyingglass")
        .font(.system(size: 56))
        .foregroundStyle(
          LinearGradient(
            colors: [.secondary.opacity(0.6), .secondary.opacity(0.3)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          )
        )
      Text(emptyStateMessage)
        .font(.title3)
        .fontWeight(.medium)
        .foregroundColor(.secondary)
      if showDownloadedOnly {
        Button("Show All Models") {
          showDownloadedOnly = false
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.regular)
      }
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 80)
  }

  private var emptyStateMessage: String {
    if showDownloadedOnly {
      return String(localized: "No models downloaded yet", comment: "Empty state when no models are installed")
    }
    if !searchText.isEmpty {
      return String(localized: "No models match '\(searchText)'", comment: "Empty state when search returns no results; %@ is the search query")
    }
    return String(localized: "No models available", comment: "Empty state when model list is empty")
  }

  // MARK: - Actions

  private func startDownload(for model: ModelVariant) {
    let downloadState = downloadState
    Task {
      if let permission = permissionMap[model], !permission.isAllowed {
        _ = await paywallManager.showPaywall(for: model)
        return
      }

      await MainActor.run {
        downloadState.setProgress(
          ModelDownloadProgress(currentStep: "Preparing...", progress: 0.0),
          for: model
        )
        downloadState.setError(nil, for: model)
      }

      do {
        try await ModelDownloadManager.shared.download(model: model) { progress in
          await MainActor.run {
            downloadState.setProgress(progress, for: model)
          }
        }

        await MainActor.run {
          downloadState.clearProgress(for: model)
          downloadState.setDownloaded(true, for: model)
        }

        await refreshStatuses()
      } catch is CancellationError {
        await MainActor.run {
          downloadState.clearProgress(for: model)
          downloadState.setError(nil, for: model)
        }
        await refreshStatuses()
      } catch {
        await MainActor.run {
          downloadState.clearProgress(for: model)
          downloadState.setDownloaded(false, for: model)
          downloadState.setError(error.localizedDescription, for: model)
        }
      }
    }
  }

  private func cancelDownload(for model: ModelVariant) {
    let downloadState = downloadState
    Task {
      let shouldCancel = await MainActor.run { () -> Bool in
        guard let currentStatus = downloadState.progress(for: model) else { return false }
        downloadState.setProgress(
          ModelDownloadProgress(
            currentStep: "Cancelling...",
            progress: currentStatus.progress,
            estimatedTimeRemaining: currentStatus.estimatedTimeRemaining,
            attemptNumber: currentStatus.attemptNumber,
            maxAttempts: currentStatus.maxAttempts
          ),
          for: model
        )
        return true
      }

      guard shouldCancel else { return }
      await ModelDownloadManager.shared.cancelDownload(for: model)
    }
  }

  private func deleteModel(_ model: ModelVariant) {
    let downloadState = downloadState
    Task {
      do {
        try await ModelDownloadManager.shared.delete(model: model)
        let provider = model.provider
        await MainActor.run {
          downloadState.setDownloaded(false, for: model)
          if model.isVADModel && config.vadModelVariant == model {
            config.vadModelVariant = .sileroVAD
          } else if isCurrentSelection(model) {
            let fallback = preferredFallback(for: provider)
            config.transcriberType = fallback.provider
            config.modelVariant = fallback
          } else if model.isQwen3AlignerModel && config.alignModelVariant == model {
            config.alignModelVariant = nil
          }
        }
        await refreshStatuses()
      } catch {
        await MainActor.run {
          downloadState.setError(error.localizedDescription, for: model)
        }
      }
    }
  }

  private func openModelFolder(for model: ModelVariant) {
    Task {
      if let url = await ModelDownloadManager.shared.getModelDirectory(for: model) {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: url.path)
      }
    }
  }

  // MARK: - Helpers

  private func modelCard(for model: ModelVariant) -> some View {
    CompactModelRowView(
      model: model,
      isDownloaded: downloadState.downloadedMap[model] ?? false,
      progress: downloadState.progressMap[model],
      errorMessage: downloadState.errorMap[model],
      isDefaultSelection: isCurrentSelection(model),
      isAlignSelection: model.isQwen3AlignerModel && config.alignModelVariant == model,
      isVADSelection: model.isVADModel && config.vadModelVariant == model,
      permission: permissionMap[model],
      onDownload: { startDownload(for: model) },
      onDelete: { deleteModel(model) },
      onProTap: { presentPaywall(for: model) },
      onOpenFolder: { openModelFolder(for: model) },
      onCancel: { cancelDownload(for: model) },
      onSetAsDefault: model.isQwen3AlignerModel
        || model.isVADModel
        ? nil
        : {
          config.transcriberType = model.provider
          config.modelVariant = model
        },
      onSetAsAligner: model.isQwen3AlignerModel
        ? {
          config.alignModelVariant = (config.alignModelVariant == model) ? nil : model
        } : nil,
      onSetAsVAD: model.isVADModel
        ? {
          config.vadModelVariant = model
        } : nil
    )
  }

  private func providerSectionHeader(_ title: String, icon: String) -> some View {
    HStack(spacing: 8) {
      Image(systemName: icon)
        .font(.system(size: 14))
        .foregroundStyle(.secondary)
      Text(title)
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(.secondary)
      Rectangle()
        .fill(Color.secondary.opacity(0.2))
        .frame(height: 1)
    }
    .padding(.top, 8)
    .padding(.bottom, 4)
  }

  private func isCurrentSelection(_ model: ModelVariant) -> Bool {
    config.modelVariant == model && config.transcriberType == model.provider
  }

  private func preferredFallback(for provider: TranscriberType) -> ModelVariant {
    if let downloaded = provider.supportedModels.first(where: { downloadState.downloadedMap[$0] == true }) {
      return downloaded
    }
    if let first = provider.supportedModels.first {
      return first
    }
    return config.modelVariant
  }

  private var filteredModels: [ModelVariant] {
    let allModels: [ModelVariant]
    switch selectedCategory {
    case .asr:
      allModels = Self.asrModels(for: selectedASRProvider)
    case .align:
      allModels = ModelVariant.alignerModels
    case .vad:
      allModels = ModelVariant.vadModels
    case .tts:
      allModels = []
    }

    var filtered = allModels

    // Apply download filter
    if showDownloadedOnly {
      filtered = filtered.filter { downloadState.downloadedMap[$0] == true }
    }

    // Apply search filter
    if !searchText.isEmpty {
      filtered = filtered.filter {
        $0.displayName.localizedCaseInsensitiveContains(searchText)
          || $0.summary.localizedCaseInsensitiveContains(searchText)
      }
    }

    return filtered
  }

  private var summaryStats: (downloadedCount: Int, totalDiskUsage: Int)? {
    let downloadedModels = downloadState.downloadedMap.filter { $0.value }
    let count = downloadedModels.count
    let totalSize = downloadedModels.keys.reduce(0) { $0 + $1.fileSize }
    return (count, totalSize)
  }

  private var headerMetrics: [HeaderMetric] {
    let stats = summaryStats ?? (0, 0)
    return Self.headerMetrics(
      downloadedCount: stats.downloadedCount,
      totalDiskUsageMB: stats.totalDiskUsage,
      cacheMemoryMB: config.modelLifecycleTotalMemoryMB
    )
  }

  private var ttsActiveSummaryCard: some View {
    let activeModel = MLXTTSModelDefinition.availableModels.first(where: {
      $0.huggingFaceRepo == config.ttsMLXModelId
    })
    let activeName = activeModel?.displayName ?? config.ttsMLXModelId

    return HStack(spacing: 10) {
      Image(systemName: "waveform.badge.mic")
        .font(.system(size: 16, weight: .semibold))
        .foregroundStyle(Self.categoryStyle(for: .tts).accent.color)
      Text("TTS Models")
        .font(.system(size: 15, weight: .bold))
      CompactStatusBadge(
        title: String(localized: "Active"),
        color: Self.statusStyle(for: .active).tone.color
      )
      CompactInfoBadge(text: activeName)
      CompactInfoBadge(text: config.ttsEngine.displayName)
      if let model = activeModel, model.supportsVoiceClone {
        CompactInfoBadge(text: String(localized: "Voice Clone"))
      }
      if let model = activeModel, model.supportsVoiceDesign {
        CompactInfoBadge(text: String(localized: "Voice Design"))
      }
      Spacer()
    }
    .padding(.vertical, 4)
  }

  private var ttsLibrarySection: some View {
    VStack(alignment: .leading, spacing: 12) {
      // Qwen3 TTS section
      if showQwen3Section {

        VStack(alignment: .leading, spacing: 8) {
          HStack(spacing: 10) {
            Image(systemName: "sparkles")
              .font(.system(size: 18))
              .foregroundStyle(Self.categoryStyle(for: .tts).accent.color)
            VStack(alignment: .leading, spacing: 4) {
              Text("Qwen3 TTS Models")
                .font(.subheadline.weight(.semibold))
              Text("MLX-powered speech synthesis with voice design & cloning")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
          }

          let models = filteredMLXModels
          if models.isEmpty {
            emptyState
          } else {
            ForEach(models) { definition in
              CompactMLXTTSRowView(
                definition: definition,
                isActive: config.ttsEngine == .qwen3TTS
                  && config.ttsMLXModelId == definition.huggingFaceRepo,
                isCached: downloadState.downloadedMap[definition.modelVariant] ?? false,
                progress: downloadState.progressMap[definition.modelVariant],
                diskUsageMB: mlxModelDiskMB[definition.huggingFaceRepo] ?? 0,
                errorMessage: downloadState.errorMap[definition.modelVariant],
                onSetActive: { setActiveTTSModel(definition) },
                onDownload: { startMLXDownload(definition) },
                onDelete: { deleteMLXModel(definition) },
                onCancel: { cancelMLXDownload(definition) },
                onOpenFolder: { openMLXModelFolder(definition) }
              )
            }
          }
        }
      }
    }
    .padding(.top, 4)
  }

  private var shouldShowProPromo: Bool {
    guard SubscriptionPolicy.isBillingEnabled else { return false }
    let isProActive = subscriptionStatus?.isActive ?? false
    return !isProActive && !hasDismissedProPromo
  }

  private func refreshStatuses(force: Bool = false) async {
    if isRefreshing && !force { return }
    await MainActor.run { isRefreshing = true }
    let allModels =
      Array(
        Set(
          TranscriberType.allCases.flatMap { $0.supportedModels }
            + ModelVariant.alignerModels
            + ModelVariant.vadModels
        )
      )

    async let statusesTask = ModelDownloadManager.shared.getStatuses(for: allModels)
    async let permissionsTask = fetchPermissions(for: allModels)
    async let subscriptionTask = fetchSubscriptionStatus(forceRefresh: force)


    let statuses = await statusesTask
    let permissions = await permissionsTask
    let subscription = await subscriptionTask

    // Refresh MLX TTS model statuses
    var mlxStatuses: [String: Bool] = [:]
    var mlxSizes: [String: Int] = [:]
    for def in MLXTTSModelDefinition.availableModels {
      mlxStatuses[def.huggingFaceRepo] = await ModelDownloadManager.shared.hasLocalArtifacts(for: def.modelVariant)
      mlxSizes[def.huggingFaceRepo] = await ModelDownloadManager.shared.modelSizeInMB(for: def.modelVariant)
    }

    await MainActor.run {
      for (model, isDownloaded) in statuses {
        downloadState.setDownloaded(isDownloaded, for: model)
      }
      for def in MLXTTSModelDefinition.availableModels {
        downloadState.setDownloaded(mlxStatuses[def.huggingFaceRepo] ?? false, for: def.modelVariant)
      }
      permissionMap = permissions
      subscriptionStatus = subscription
      mlxModelDiskMB = mlxSizes
      isRefreshing = false
    }
    await config.refreshModelLifecycleState()
  }





  private func startMLXDownload(_ definition: MLXTTSModelDefinition) {
    let model = definition.modelVariant
    let downloadState = downloadState
    Task {
      await MainActor.run {
        downloadState.setProgress(
          ModelDownloadProgress(currentStep: "Preparing...", progress: 0.0),
          for: model
        )
        downloadState.setError(nil, for: model)
      }
      do {
        try await ModelDownloadManager.shared.download(model: model) { progress in
          await MainActor.run {
            downloadState.setProgress(progress, for: model)
          }
        }
        await MainActor.run {
          downloadState.clearProgress(for: model)
          downloadState.setDownloaded(true, for: model)
        }
      } catch is CancellationError {
        await MainActor.run {
          downloadState.clearProgress(for: model)
          downloadState.setError(nil, for: model)
        }
      } catch {
        await MainActor.run {
          downloadState.clearProgress(for: model)
          downloadState.setDownloaded(false, for: model)
          downloadState.setError(error.localizedDescription, for: model)
        }
      }
      await refreshStatuses(force: true)
    }
  }

  private func cancelMLXDownload(_ definition: MLXTTSModelDefinition) {
    let downloadState = downloadState
    Task {
      await ModelDownloadManager.shared.cancelDownload(for: definition.modelVariant)
      await MainActor.run {
        downloadState.clearProgress(for: definition.modelVariant)
      }
    }
  }

  private func deleteMLXModel(_ definition: MLXTTSModelDefinition) {
    let repoId = definition.huggingFaceRepo
    let model = definition.modelVariant
    let downloadState = downloadState
    downloadState.setError(nil, for: model)
    Task {
      do {
        try await ModelDownloadManager.shared.delete(model: model)
        await MainActor.run {
          if config.ttsEngine == .qwen3TTS && config.ttsMLXModelId == repoId {
            let fallback = MLXTTSModelDefinition.availableModels.first(where: {
              $0.huggingFaceRepo != repoId && (downloadState.downloadedMap[$0.modelVariant] == true)
            })
            if let fallback {
              config.ttsMLXModelId = fallback.huggingFaceRepo
            }
          }
          downloadState.clearProgress(for: model)
          downloadState.setDownloaded(false, for: model)
        }
        await refreshStatuses(force: true)
      } catch {
        await MainActor.run {
          downloadState.setError(error.localizedDescription, for: model)
        }
      }
    }
  }

  private func openMLXModelFolder(_ definition: MLXTTSModelDefinition) {
    Task {
      let cacheDir = await ModelDownloadManager.shared.getModelDirectory(for: definition.modelVariant)
      _ = await MainActor.run {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: cacheDir?.path ?? "")
      }
    }
  }

  private func setActiveTTSModel(_ definition: MLXTTSModelDefinition) {
    guard downloadState.downloadedMap[definition.modelVariant] == true else { return }
    config.ttsEngine = .qwen3TTS
    config.ttsMLXModelId = definition.huggingFaceRepo
  }

  private var selectedTTSModelIdentifier: String {
    config.ttsMLXModelId
  }

  private func preloadSelectedAlignModel() {
    guard let alignModel = config.alignModelVariant else {
      cacheActionErrorMessage = "No align model selected. Choose one first."
      return
    }

    let downloadState = downloadState
    Task {
      await MainActor.run {
        isPreloadingAlignModel = true
        cacheActionErrorMessage = nil
      }

      do {
        try await ModelCacheManager.shared.preloadAlignModel(model: alignModel) { progress in
          Task { @MainActor in
            downloadState.setProgress(progress, for: alignModel)
          }
        }
      } catch {
        await MainActor.run {
          cacheActionErrorMessage = error.localizedDescription
        }
      }

      await MainActor.run {
        downloadState.clearProgress(for: alignModel)
        isPreloadingAlignModel = false
      }
      await refreshStatuses(force: true)
    }
  }

  private func preloadSelectedTTSModel() {
    let engine = config.ttsEngine
    let modelID = selectedTTSModelIdentifier

    Task {
      await MainActor.run {
        isPreloadingTTSModel = true
        cacheActionErrorMessage = nil
      }

      do {
        try await ModelCacheManager.shared.preloadTTSModel(
          engine: engine,
          modelID: modelID
        )
      } catch {
        await MainActor.run {
          cacheActionErrorMessage = error.localizedDescription
        }
      }

      await MainActor.run {
        isPreloadingTTSModel = false
      }
      await refreshStatuses(force: true)
    }
  }

  private func retryFailedCacheLoads() {
    if let asrError = cacheErrorStatuses.first(where: { $0.key.kind == .asr }),
      asrError.key.identifier
        == "\(config.transcriberType.rawValue):\(config.modelVariant.rawValue)"
    {
      Task {
        do {
          try await ModelCacheManager.shared.preloadASRModel(
            type: config.transcriberType,
            model: config.modelVariant
          )
        } catch {
          await MainActor.run {
            cacheActionErrorMessage = error.localizedDescription
          }
        }
        await refreshStatuses(force: true)
      }
    }

    if cacheErrorStatuses.contains(where: { $0.key.kind == .align }) {
      preloadSelectedAlignModel()
    }
    if cacheErrorStatuses.contains(where: { $0.key.kind == .tts }) {
      preloadSelectedTTSModel()
    }
  }

  private func clearModelCache() {
    Task {
      await MainActor.run {
        isClearingModelCache = true
        cacheActionErrorMessage = nil
      }
      await ModelCacheManager.shared.clearCache(
        keepASR: config.transcriberType,
        model: config.modelVariant
      )
      await refreshStatuses(force: true)
      await MainActor.run {
        isClearingModelCache = false
      }
    }
  }

  private func fetchPermissions(for models: [ModelVariant]) async
    -> [ModelVariant: ModelDownloadPermission]
  {
    var results: [ModelVariant: ModelDownloadPermission] = [:]
    for model in models {
      do {
        let permission = try await ModelAccessController.shared.checkPermission(for: model)
        results[model] = permission
      } catch {
        if model.requiresProSubscription {
          results[model] = ModelDownloadPermission(
            model: model,
            isAllowed: false,
            reason: .offline
          )
        } else {
          results[model] = ModelDownloadPermission(model: model, isAllowed: true, reason: nil)
        }
      }
    }
    return results
  }

  private func fetchSubscriptionStatus(forceRefresh: Bool) async -> SubscriptionStatus? {
    guard SubscriptionPolicy.isBillingEnabled else { return nil }
    do {
      return try await ModelAccessController.shared.getCurrentSubscriptionStatus(
        forceRefresh: forceRefresh
      )
    } catch {
      return await MainActor.run { subscriptionStatus }
    }
  }

  private func refreshPermissionsCache() async {
    let models = Array(
      Set(
        TranscriberType.allCases.flatMap { $0.supportedModels }
          + ModelVariant.alignerModels
          + ModelVariant.vadModels
      )
    )
    let permissions = await fetchPermissions(for: models)
    await MainActor.run {
      permissionMap = permissions
    }
  }

  private func handlePurchaseEvent(_ event: PaywallManager.PurchaseEvent) {
    switch event.outcome {
    case .success:
      hasDismissedProPromo = true
      let message = String(
        format: NSLocalizedString(
          "Subscription successful, %@ unlocked.", comment: "purchase success banner"),
        event.model.displayName
      )
      showPurchaseBanner(
        PurchaseBanner(
          message: message,
          detail: String(
            format: NSLocalizedString(
              "%@ plan activated. Use the Download button on this page to install the model.",
              comment: "purchase success follow-up with plan"
            ),
            event.plan.name
          ),
          style: .success
        )
      )
      Task { await refreshStatuses(force: true) }
    case .cancelled:
      showPurchaseBanner(
        PurchaseBanner(
          message: NSLocalizedString("Purchase cancelled.", comment: "purchase cancelled banner"),
          detail: nil,
          style: .info
        )
      )
    case .failure(let message):
      showPurchaseBanner(
        PurchaseBanner(
          message: NSLocalizedString("Purchase Failed", comment: "purchase failure banner"),
          detail: message,
          style: .error
        )
      )
    }
  }

  private func showPurchaseBanner(_ banner: PurchaseBanner) {
    bannerTask?.cancel()
    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
      purchaseBanner = banner
    }
    bannerTask = Task {
      try? await Task.sleep(nanoseconds: 4_000_000_000)
      await MainActor.run {
        if purchaseBanner?.id == banner.id {
          withAnimation(.easeInOut) {
            purchaseBanner = nil
          }
        }
        bannerTask = nil
      }
    }
  }

  private func presentPaywall(
    for model: ModelVariant, reason: PaywallContext.PaywallReason = .attemptedPaidModelDownload
  ) {
    Task { _ = await paywallManager.showPaywall(for: model, reason: reason) }
  }

  private func startSubscriptionMonitoringIfNeeded() {
    guard SubscriptionPolicy.isBillingEnabled else { return }
    guard subscriptionMonitorTask == nil else { return }
    subscriptionMonitorTask = Task {
      let stream = await ModelAccessController.shared.subscriptionStatusStream()
      for await status in stream {
        if Task.isCancelled { break }
        await MainActor.run {
          subscriptionStatus = status
        }
        await refreshPermissionsCache()
      }
    }
  }

  private func stopSubscriptionMonitoring() {
    subscriptionMonitorTask?.cancel()
    subscriptionMonitorTask = nil
  }

  private var paywallPresentationBinding: Binding<Bool> {
    Binding(
      get: { paywallManager.isPresented },
      set: { newValue in
        if !newValue {
          paywallManager.dismissPaywall()
        }
      }
    )
  }
}

extension ModelsView {
  enum VisualTone: String, Equatable {
    case asrAccent
    case alignAccent
    case vadAccent
    case ttsAccent
    case success
    case neutral
    case warning
    case danger

    var color: Color {
      switch self {
      case .asrAccent:
        return .accentColor
      case .alignAccent:
        return .indigo
      case .vadAccent:
        return .purple
      case .ttsAccent:
        return .teal
      case .success:
        return .green
      case .neutral:
        return .secondary
      case .warning:
        return .orange
      case .danger:
        return .red
      }
    }
  }

  struct CategoryStyle: Equatable {
    let accent: VisualTone
    let usesNeutralSurface: Bool
  }

  enum SharedStatus: Equatable {
    case active
    case downloaded
    case pro
    case error
  }

  struct StatusStyle: Equatable {
    let tone: VisualTone
  }

  static func categoryStyle(for category: ModelCategory) -> CategoryStyle {
    switch category {
    case .asr:
      return CategoryStyle(accent: .asrAccent, usesNeutralSurface: true)
    case .align:
      return CategoryStyle(accent: .asrAccent, usesNeutralSurface: true)
    case .vad:
      return CategoryStyle(accent: .asrAccent, usesNeutralSurface: true)
    case .tts:
      return CategoryStyle(accent: .asrAccent, usesNeutralSurface: true)
    }
  }

  static func categoryStyle(for model: ModelVariant) -> CategoryStyle {
    if model.isQwen3AlignerModel {
      return categoryStyle(for: .align)
    }
    if model.isVADModel {
      return categoryStyle(for: .vad)
    }
    return categoryStyle(for: .asr)
  }

  static func categoryStyle(for definition: MLXTTSModelDefinition) -> CategoryStyle {
    categoryStyle(for: .tts)
  }

  static func statusStyle(for status: SharedStatus) -> StatusStyle {
    switch status {
    case .active:
      return StatusStyle(tone: .success)
    case .downloaded:
      return StatusStyle(tone: .neutral)
    case .pro:
      return StatusStyle(tone: .warning)
    case .error:
      return StatusStyle(tone: .danger)
    }
  }

  static func filteredTTSModels(
    from models: [MLXTTSModelDefinition],
    searchText: String,
    showDownloadedOnly: Bool,
    downloadedModelVariants: Set<ModelVariant>
  ) -> [MLXTTSModelDefinition] {
    var filtered = models

    if showDownloadedOnly {
      filtered = filtered.filter { downloadedModelVariants.contains($0.modelVariant) }
    }

    if !searchText.isEmpty {
      filtered = filtered.filter {
        $0.displayName.localizedCaseInsensitiveContains(searchText)
          || $0.huggingFaceRepo.localizedCaseInsensitiveContains(searchText)
          || $0.description.localizedCaseInsensitiveContains(searchText)
      }
    }

    return filtered
  }

  struct HeaderMetric: Equatable {
    enum Emphasis: Equatable {
      case primary
      case secondary
    }

    let title: String
    let value: String
    let emphasis: Emphasis

    var icon: String {
      switch title {
      case "Downloaded":
        return "checkmark.circle.fill"
      case "Disk Usage":
        return "externaldrive.fill"
      case "Cache Memory":
        return "memorychip.fill"
      default:
        return "circle.fill"
      }
    }

    var color: Color {
      switch title {
      case "Downloaded":
        return .green
      case "Disk Usage":
        return .blue
      case "Cache Memory":
        return .blue
      default:
        return .secondary
      }
    }
  }

  static func headerMetrics(
    downloadedCount: Int,
    totalDiskUsageMB: Int,
    cacheMemoryMB: Int
  ) -> [HeaderMetric] {
    [
      HeaderMetric(
        title: String(localized: "Downloaded"),
        value: "\(downloadedCount)",
        emphasis: .primary
      ),
      HeaderMetric(
        title: String(localized: "Disk Usage"),
        value: "\(totalDiskUsageMB) MB",
        emphasis: .primary
      ),
      HeaderMetric(
        title: String(localized: "Cache Memory"),
        value: "\(cacheMemoryMB) MB",
        emphasis: .secondary
      ),
    ]
  }

  enum DenseRowPrimaryAction: Equatable {
    case active
    case activeAligner
    case activeVAD
    case setActive
    case setAligner
    case setVAD
    case download
    case unlockPro
    case checkingAccess
  }

  enum DenseRowOverflowAction: Equatable {
    case openFolder
    case remove
    case deselectAligner
  }

  struct DenseRowPresentation: Equatable {
    let status: String
    let statusKind: SharedStatus?
    let metadata: [String]
    let primaryAction: DenseRowPrimaryAction
    let overflowActions: [DenseRowOverflowAction]
  }

  static func denseRowPresentation(
    for model: ModelVariant,
    isDownloaded: Bool,
    progress: ModelDownloadProgress?,
    permission: ModelDownloadPermission?,
    isDefaultSelection: Bool,
    isAlignSelection: Bool,
    isVADSelection: Bool
  ) -> DenseRowPresentation {
    let metadata = ["\(model.fileSize) MB", model.languageSummary]

    if progress != nil {
      return DenseRowPresentation(
        status: String(localized: "Downloading"),
        statusKind: nil,
        metadata: metadata,
        primaryAction: .checkingAccess,
        overflowActions: []
      )
    }

    if isDownloaded {
      if isDefaultSelection {
        return DenseRowPresentation(
          status: String(localized: "Active"),
          statusKind: .active,
          metadata: metadata,
          primaryAction: .active,
          overflowActions: [.openFolder, .remove]
        )
      }

      if isAlignSelection {
        return DenseRowPresentation(
          status: String(localized: "Active"),
          statusKind: .active,
          metadata: metadata,
          primaryAction: .activeAligner,
          overflowActions: [.deselectAligner, .openFolder, .remove]
        )
      }

      if isVADSelection {
        return DenseRowPresentation(
          status: String(localized: "Active"),
          statusKind: .active,
          metadata: metadata,
          primaryAction: .activeVAD,
          overflowActions: [.openFolder, .remove]
        )
      }

      if model.isQwen3AlignerModel {
        return DenseRowPresentation(
          status: String(localized: "Downloaded"),
          statusKind: .downloaded,
          metadata: metadata,
          primaryAction: .setAligner,
          overflowActions: [.openFolder, .remove]
        )
      }

      if model.isVADModel {
        return DenseRowPresentation(
          status: String(localized: "Downloaded"),
          statusKind: .downloaded,
          metadata: metadata,
          primaryAction: .setVAD,
          overflowActions: [.openFolder, .remove]
        )
      }

      return DenseRowPresentation(
        status: String(localized: "Downloaded"),
        statusKind: .downloaded,
        metadata: metadata,
        primaryAction: .setActive,
        overflowActions: [.openFolder, .remove]
      )
    }

    if let permission {
      if permission.isAllowed {
        return DenseRowPresentation(
          status: String(localized: "Not Downloaded"),
          statusKind: nil,
          metadata: metadata,
          primaryAction: .download,
          overflowActions: []
        )
      }

      if permission.reason == .loading {
        return DenseRowPresentation(
          status: String(localized: "Checking access..."),
          statusKind: nil,
          metadata: metadata,
          primaryAction: .checkingAccess,
          overflowActions: []
        )
      }

      return DenseRowPresentation(
        status: String(localized: "Pro"),
        statusKind: .pro,
        metadata: metadata,
        primaryAction: .unlockPro,
        overflowActions: []
      )
    }

    return DenseRowPresentation(
      status: model.requiresProSubscription
        ? String(localized: "Checking access...")
        : String(localized: "Not Downloaded"),
      statusKind: model.requiresProSubscription ? .pro : nil,
      metadata: metadata,
      primaryAction: model.requiresProSubscription ? .checkingAccess : .download,
      overflowActions: []
    )
  }

  fileprivate var selectedCategory: ModelCategory {
    ModelCategory(rawValue: selectedCategoryStorage) ?? .asr
  }

  fileprivate var selectedCategoryBinding: Binding<ModelCategory> {
    Binding(
      get: { ModelCategory(rawValue: selectedCategoryStorage) ?? .asr },
      set: { newValue in selectedCategoryStorage = newValue.rawValue }
    )
  }

  fileprivate var selectedASRProvider: ASRProvider {
    ASRProvider(rawValue: asrProviderStorage) ?? .all
  }

  private var selectedTTSProvider: TTSProvider {
    TTSProvider(rawValue: ttsProviderStorage) ?? .all
  }


  private var showQwen3Section: Bool {
    selectedTTSProvider == .all || selectedTTSProvider == .qwen3
  }

  private var filteredMLXModels: [MLXTTSModelDefinition] {
    Self.filteredTTSModels(
      from: MLXTTSModelDefinition.availableModels,
      searchText: searchText,
      showDownloadedOnly: showDownloadedOnly,
      downloadedModelVariants: Set(
        downloadState.downloadedMap.compactMap { entry in
          entry.value ? entry.key : nil
        }
      )
    )
  }
}

// MARK: - Stat Badge

private struct StatBadge: View {
  let icon: String
  let value: String
  let label: String
  let color: Color
  var isCompact: Bool = false

  var body: some View {
    HStack(spacing: isCompact ? 6 : 8) {
      Image(systemName: icon)
        .foregroundColor(color)
        .font(.system(size: isCompact ? 13 : 16))

      VStack(alignment: .leading, spacing: 2) {
        Text(value)
          .font(.system(size: isCompact ? 13 : 15, weight: .semibold))
        Text(label)
          .font(.caption2)
          .foregroundColor(.secondary)
      }
    }
    .padding(.horizontal, isCompact ? 10 : 14)
    .padding(.vertical, isCompact ? 6 : 10)
    .background(
      RoundedRectangle(cornerRadius: 10)
        .fill(color.opacity(0.12))
    )
  }
}

// MARK: - Dashboard Stat Pill

/// A compact metric pill used in the ModelsView dashboard header.
private struct ModelsStatPill: View {
  let icon: String
  let value: String
  let label: String
  let color: Color

  var body: some View {
    HStack(spacing: 7) {
      Image(systemName: icon)
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(color)

      VStack(alignment: .leading, spacing: 1) {
        Text(value)
          .font(.system(size: 13, weight: .bold).monospacedDigit())

        Text(label)
          .font(.system(size: 10))
          .foregroundStyle(.secondary)
      }
    }
    .padding(.horizontal, 11)
    .padding(.vertical, 7)
    .background(
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .fill(color.opacity(0.09))
    )
    .overlay(
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .stroke(color.opacity(0.18), lineWidth: 1)
    )
    .accessibilityElement(children: .combine)
    .accessibilityLabel("\(label): \(value)")
  }
}

private struct CompactInfoBadge: View {
  let text: String

  var body: some View {
    Text(text)
      .font(.caption2.weight(.medium))
      .foregroundStyle(.secondary)
      .padding(.horizontal, 8)
      .padding(.vertical, 4)
      .background(
        Capsule()
          .fill(Color.secondary.opacity(0.10))
      )
  }
}

private struct CompactStatusBadge: View {
  let title: String
  let color: Color

  var body: some View {
    HStack(spacing: 4) {
      Image(systemName: "circle.fill")
        .font(.system(size: 6))
      Text(title)
        .font(.caption.weight(.semibold))
    }
    .foregroundStyle(color)
    .padding(.horizontal, 8)
    .padding(.vertical, 4)
    .background(
      Capsule()
        .fill(color.opacity(0.12))
    )
  }
}

private struct CompactModelRowView: View {
  let model: ModelVariant
  let isDownloaded: Bool
  let progress: ModelDownloadProgress?
  let errorMessage: String?
  let isDefaultSelection: Bool
  let isAlignSelection: Bool
  let isVADSelection: Bool
  let permission: ModelDownloadPermission?
  let onDownload: () -> Void
  let onDelete: () -> Void
  let onProTap: () -> Void
  let onOpenFolder: () -> Void
  let onCancel: () -> Void
  let onSetAsDefault: (() -> Void)?
  let onSetAsAligner: (() -> Void)?
  let onSetAsVAD: (() -> Void)?

  private var presentation: ModelsView.DenseRowPresentation {
    ModelsView.denseRowPresentation(
      for: model,
      isDownloaded: isDownloaded,
      progress: progress,
      permission: permission,
      isDefaultSelection: isDefaultSelection,
      isAlignSelection: isAlignSelection,
      isVADSelection: isVADSelection
    )
  }

  private var categoryAccentColor: Color {
    ModelsView.categoryStyle(for: model).accent.color
  }

  private var statusColor: Color {
    if let kind = presentation.statusKind {
      return ModelsView.statusStyle(for: kind).tone.color
    }
    return ModelsView.VisualTone.neutral.color
  }

  @ViewBuilder
  private var primaryActionView: some View {
    switch presentation.primaryAction {
    case .active, .activeAligner, .activeVAD:
      CompactStatusBadge(title: presentation.status, color: statusColor)
    case .setActive:
      Button(action: { onSetAsDefault?() }) {
        Label("Set Active", systemImage: "checkmark.circle")
      }
      .buttonStyle(.bordered)
      .tint(categoryAccentColor)
      .controlSize(.small)
    case .setAligner:
      Button(action: { onSetAsAligner?() }) {
        Label("Set as Aligner", systemImage: "text.alignleft")
      }
      .buttonStyle(.bordered)
      .tint(categoryAccentColor)
      .controlSize(.small)
    case .setVAD:
      Button(action: { onSetAsVAD?() }) {
        Label("Set as VAD", systemImage: "waveform.badge.magnifyingglass")
      }
      .buttonStyle(.bordered)
      .tint(categoryAccentColor)
      .controlSize(.small)
    case .download:
      Button(action: onDownload) {
        Label("Download", systemImage: "arrow.down.circle.fill")
      }
      .buttonStyle(.borderedProminent)
      .tint(categoryAccentColor)
      .controlSize(.small)
    case .unlockPro:
      Button(action: onProTap) {
        Label("Unlock Pro", systemImage: "lock.fill")
      }
      .buttonStyle(.borderedProminent)
      .tint(.orange)
      .controlSize(.small)
    case .checkingAccess:
      HStack(spacing: 6) {
        ProgressView()
          .controlSize(.small)
        Text("Checking access...")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
  }

  @ViewBuilder
  private var overflowMenu: some View {
    if !presentation.overflowActions.isEmpty {
      Menu {
        ForEach(presentation.overflowActions, id: \.self) { action in
          switch action {
          case .openFolder:
            Button("Folder", action: onOpenFolder)
          case .remove:
            Button("Remove", role: .destructive, action: onDelete)
          case .deselectAligner:
            Button("Deselect", action: { onSetAsAligner?() })
          }
        }
      } label: {
        Image(systemName: "ellipsis.circle")
      }
      .menuStyle(.borderlessButton)
      .fixedSize()
    }
  }

  @State private var isHovering = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .center, spacing: 16) {
        // Model icon
        ZStack {
          RoundedRectangle(cornerRadius: 13, style: .continuous)
            .fill(categoryAccentColor.opacity(0.12))
            .frame(width: 44, height: 44)

          Image(systemName: model.isVADModel ? "waveform.badge.magnifyingglass" : "mic.circle.fill")
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(categoryAccentColor)
        }

        // Name + status + meta
        VStack(alignment: .leading, spacing: 7) {
          HStack(spacing: 8) {
            Text(model.displayName)
              .font(.system(size: 15, weight: .semibold))
            CompactStatusBadge(title: presentation.status, color: statusColor)
          }

          HStack(spacing: 6) {
            ForEach(presentation.metadata, id: \.self) { item in
              CompactInfoBadge(text: item)
            }
          }

          if let progress {
            VStack(alignment: .leading, spacing: 5) {
              Text(progress.currentStep)
                .font(.caption)
                .foregroundStyle(.secondary)
              ProgressView(value: Double(progress.progress), total: 1.0)
                .progressViewStyle(.linear)
                .frame(maxWidth: 200)
            }
          }
        }

        Spacer(minLength: 8)

        // Actions
        if let progress {
          VStack(alignment: .trailing, spacing: 6) {
            Text("\(Int(progress.progress * 100))%")
              .font(.system(size: 13, weight: .semibold).monospacedDigit())
              .foregroundStyle(.secondary)
            Button(role: .cancel, action: onCancel) {
              Label("Cancel", systemImage: "xmark.circle")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
          }
        } else {
          HStack(spacing: 8) {
            primaryActionView
            overflowMenu
          }
        }
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 13)

      if let errorMessage, !errorMessage.isEmpty {
        Divider()
        HStack(spacing: 6) {
          Image(systemName: "exclamationmark.triangle.fill")
            .foregroundStyle(.red)
          Text(errorMessage)
            .font(.caption)
            .foregroundStyle(.red)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
      }
    }
    .background(
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .fill(isHovering
          ? AppSurface.cardBackground.opacity(0.95)
          : AppSurface.cardBackground)
    )
    .overlay(
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .strokeBorder(
          presentation.statusKind == .active
            ? categoryAccentColor.opacity(0.40)
            : Color.secondary.opacity(0.12),
          lineWidth: presentation.statusKind == .active ? 1.2 : 1
        )
    )
    .shadow(
      color: presentation.statusKind == .active
        ? categoryAccentColor.opacity(0.10)
        : .black.opacity(0.04),
      radius: presentation.statusKind == .active ? 10 : 4,
      x: 0, y: 3
    )
    .onHover { hovering in
      withAnimation(.easeOut(duration: 0.14)) {
        isHovering = hovering
      }
    }
  }
}

private struct CompactMLXTTSRowView: View {
  let definition: MLXTTSModelDefinition
  let isActive: Bool
  let isCached: Bool
  let progress: ModelDownloadProgress?
  let diskUsageMB: Int
  let errorMessage: String?
  let onSetActive: () -> Void
  let onDownload: () -> Void
  let onDelete: () -> Void
  let onCancel: () -> Void
  let onOpenFolder: () -> Void

  private var categoryAccentColor: Color {
    ModelsView.categoryStyle(for: definition).accent.color
  }

  private var statusText: String {
    if isActive { return String(localized: "Active") }
    if isCached { return String(localized: "Downloaded") }
    return String(localized: "Not Downloaded")
  }

  private var metadata: [String] {
    let size = diskUsageMB > 0 ? diskUsageMB : definition.estimatedSizeMB
    return ["\(size) MB", definition.family.displayName]
  }

  @State private var isHovering = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .center, spacing: 16) {
        // Model icon
        ZStack {
          RoundedRectangle(cornerRadius: 13, style: .continuous)
            .fill(categoryAccentColor.opacity(0.12))
            .frame(width: 44, height: 44)

          Image(systemName: definition.familyVisual.icon)
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(categoryAccentColor)
        }

        // Name + status + meta
        VStack(alignment: .leading, spacing: 7) {
          HStack(spacing: 8) {
            Text(definition.displayName)
              .font(.system(size: 15, weight: .semibold))
            CompactStatusBadge(
              title: statusText,
              color: isActive
                ? ModelsView.statusStyle(for: .active).tone.color
                : ModelsView.VisualTone.neutral.color
            )
          }

          HStack(spacing: 6) {
            ForEach(metadata, id: \.self) { item in
              CompactInfoBadge(text: item)
            }
          }

          if let progress {
            VStack(alignment: .leading, spacing: 5) {
              Text(progress.currentStep)
                .font(.caption)
                .foregroundStyle(.secondary)
              ProgressView(value: Double(progress.progress), total: 1.0)
                .progressViewStyle(.linear)
                .frame(maxWidth: 200)
            }
          }
        }

        Spacer(minLength: 8)

        // Actions
        if let progress {
          VStack(alignment: .trailing, spacing: 6) {
            Text("\(Int(progress.progress * 100))%")
              .font(.system(size: 13, weight: .semibold).monospacedDigit())
              .foregroundStyle(.secondary)
            Button(role: .cancel, action: onCancel) {
              Label("Cancel", systemImage: "xmark.circle")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
          }
        } else {
          HStack(spacing: 8) {
            if isCached {
              if isActive {
                CompactStatusBadge(
                  title: String(localized: "Active"),
                  color: ModelsView.statusStyle(for: .active).tone.color
                )
              } else {
                Button(action: onSetActive) {
                  Label("Set Active", systemImage: "checkmark.circle")
                }
                .buttonStyle(.bordered)
                .tint(categoryAccentColor)
                .controlSize(.small)
              }

              Menu {
                Button("Folder", action: onOpenFolder)
                Button("Remove", role: .destructive, action: onDelete)
              } label: {
                Image(systemName: "ellipsis.circle")
              }
              .menuStyle(.borderlessButton)
              .fixedSize()
            } else {
              Button(action: onDownload) {
                Label("Download", systemImage: "arrow.down.circle.fill")
              }
              .buttonStyle(.borderedProminent)
              .tint(categoryAccentColor)
              .controlSize(.small)
            }
          }
        }
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 13)

      if let errorMessage, !errorMessage.isEmpty {
        Divider()
        HStack(spacing: 6) {
          Image(systemName: "exclamationmark.triangle.fill")
            .foregroundStyle(.red)
          Text(errorMessage)
            .font(.caption)
            .foregroundStyle(.red)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
      }
    }
    .background(
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .fill(isHovering
          ? AppSurface.cardBackground.opacity(0.95)
          : AppSurface.cardBackground)
    )
    .overlay(
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .strokeBorder(
          isActive
            ? categoryAccentColor.opacity(0.40)
            : Color.secondary.opacity(0.12),
          lineWidth: isActive ? 1.2 : 1
        )
    )
    .shadow(
      color: isActive
        ? categoryAccentColor.opacity(0.10)
        : .black.opacity(0.04),
      radius: isActive ? 10 : 4,
      x: 0, y: 3
    )
    .onHover { hovering in
      withAnimation(.easeOut(duration: 0.14)) {
        isHovering = hovering
      }
    }
  }
}

// MARK: - Purchase Banner

private struct PurchaseBanner: Identifiable, Equatable {
  enum Style: Equatable {
    case success
    case info
    case error

    var foreground: Color {
      switch self {
      case .success: return .green
      case .info: return .blue
      case .error: return .red
      }
    }

    var background: Color {
      switch self {
      case .success: return Color.green.opacity(0.12)
      case .info: return Color.blue.opacity(0.12)
      case .error: return Color.red.opacity(0.12)
      }
    }

    var icon: String {
      switch self {
      case .success: return "checkmark.seal.fill"
      case .info: return "info.circle.fill"
      case .error: return "exclamationmark.triangle.fill"
      }
    }
  }

  let id = UUID()
  let message: String
  let detail: String?
  let style: Style
}

private struct PurchaseBannerView: View {
  let banner: PurchaseBanner

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: banner.style.icon)
        .foregroundColor(banner.style.foreground)
        .font(.title2)
      VStack(alignment: .leading, spacing: 4) {
        Text(banner.message)
          .font(.headline)
          .foregroundColor(.primary)
        if let detail = banner.detail, !detail.isEmpty {
          Text(detail)
            .font(.subheadline)
            .foregroundColor(.secondary)
        }
      }
      Spacer()
    }
    .padding(14)
    .background(
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .fill(banner.style.background)
    )
    .overlay(
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .stroke(banner.style.foreground.opacity(0.35), lineWidth: 1)
    )
  }
}
