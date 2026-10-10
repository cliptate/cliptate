import SwiftUI
import UniformTypeIdentifiers

#if canImport(AppKit)
  import AppKit
#endif

struct ControlPanelConfigurationView: View {
  @EnvironmentObject var config: AppConfiguration
  @Binding var selectedTab: ControlPanelView.ConfigTab
  @State private var selectedEnhanceModule: EnhanceModule = .timing
  @State private var selectedOutputModule: OutputModule = .fcpxml
  @State private var selectedSubtitleOrientation: SubtitleOrientation = .landscape
  @State private var fillerWordsDraft: String = ""
  @FocusState private var isFillerWordEditorFocused: Bool

  init(
    selectedTab: Binding<ControlPanelView.ConfigTab>
  ) {
    _selectedTab = selectedTab
  }

  private let numberFormatter: NumberFormatter = {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    return formatter
  }()

  var body: some View {
    VStack(spacing: 12) {
      Picker("Config Tab", selection: $selectedTab) {
        ForEach(ControlPanelView.ConfigTab.allCases) { tab in
          Label(tab.localizedTitle, systemImage: tab.icon).tag(tab)
        }
      }
      .pickerStyle(.segmented)
      .labelsHidden()

      Group {
        switch selectedTab {
        case .transcription:
          transcriptionContent
        case .translation:
          translationContent
        case .enhance:
          enhanceContent
        case .output:
          outputContent
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .animation(.easeInOut(duration: 0.2), value: selectedTab)
    }
    .padding(8)
    .background(
      Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}

extension ControlPanelConfigurationView {
  fileprivate var transcriptionContent: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Transcription model selection is managed from the Models page.")
        .font(.caption2)
        .foregroundColor(.secondary)

      VStack(alignment: .leading, spacing: 8) {
        HStack {
          Text("\(config.transcriberType.displayName) • \(config.modelVariant.displayName)")
            .font(.subheadline.weight(.medium))
          Spacer()
          Button {
            NotificationCenter.default.post(name: .openModelsLibrary, object: nil)
          } label: {
            Label("Open Models", systemImage: "square.and.arrow.up")
              .font(.caption)
          }
          .buttonStyle(.bordered)
          .accessibilityLabel("Open Models page")
        }

        Text("Language: \(config.language.displayName)")
          .font(.caption)
          .foregroundColor(.secondary)

        if let alignModel = config.alignModelVariant {
          Text("Align model: \(alignModel.displayName)")
            .font(.caption)
            .foregroundColor(.secondary)
        } else {
          Text(
            "Align model: \(String(localized: "Disabled", comment: "Align model state when not selected"))"
          )
          .font(.caption)
          .foregroundColor(.secondary)
        }
      }
      .padding(10)
      .background(
        Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous)
      )

      ModelAwareLanguageSelectionView(
        title: String(localized: "Transcription Language", comment: "Label for selecting transcription language"),
        selectedLanguage: $config.language,
        contextProvider: {
          .asr(type: config.transcriberType, model: config.modelVariant)
        },
        helpText: String(localized: "Available languages are filtered by the active ASR model.", comment: "Help text for transcription language")
      )
    }
  }

  fileprivate var translationContent: some View {
    VStack(spacing: 12) {
      Text("Configure source and target languages for translation, plus subtitle placement.")
        .font(.caption2)
        .foregroundColor(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)

      HStack(spacing: 12) {
        VStack(alignment: .leading, spacing: 8) {
          Text("Source Language")
            .font(.caption)
            .foregroundColor(.secondary)

          Picker("Source Language", selection: $config.translationSourceLanguage) {
            ForEach(Language.translationSupported) { language in
              Text(language.displayName).tag(language)
            }
          }
          .pickerStyle(.menu)
        }
        .padding(8)
        .background(
          Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )

        VStack(alignment: .leading, spacing: 8) {
          Text("Target Language")
            .font(.caption)
            .foregroundColor(.secondary)

          Picker("Target Language", selection: $config.translationTargetLanguage) {
            ForEach(Language.translationSupported) { language in
              Text(language.displayName).tag(language)
            }
          }
          .pickerStyle(.menu)
        }
        .padding(8)
        .background(
          Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
      }

      VStack(alignment: .leading, spacing: 8) {
        Text("Placement")
          .font(.caption)
          .foregroundColor(.secondary)

        Picker("Placement", selection: $config.translationPlacement) {
          ForEach(SubtitleTranslationPlacement.allCases) { placement in
            Text(placement.displayName).tag(placement)
          }
        }
        .pickerStyle(.segmented)
      }
      .padding(8)
      .background(
        Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous)
      )

      Text("Translations appear when enabled during export or playback overlays.")
        .font(.caption2)
        .foregroundColor(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  fileprivate var enhanceContent: some View {
    VStack(spacing: 12) {
      Text("Fine-tune AI Enhance effects by switching between focused modules.")
        .font(.caption2)
        .foregroundColor(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)

      Picker("Enhance Module", selection: $selectedEnhanceModule) {
        ForEach(EnhanceModule.allCases) { module in
          Text(module.label).tag(module)
        }
      }
      .pickerStyle(.segmented)
      .labelsHidden()

      Group {
        switch selectedEnhanceModule {
        case .timing:
          enhanceTimingContent
        case .highlight:
          enhanceHighlightContent
        case .zoom:
          enhanceZoomContent
        case .filter:
          enhanceFilterContent
        case .style:
          enhanceStyleContent
        case .dubbing:
          enhanceDubbingContent
        }
      }
      .animation(.easeInOut(duration: 0.2), value: selectedEnhanceModule)
      .onChange(of: selectedEnhanceModule) { oldValue, newValue in
        if oldValue == .filter, newValue != .filter {
          commitFillerWordsDraft()
        }
        if newValue == .filter {
          syncFillerWordsDraftFromConfig()
        }
      }
    }
  }

  private var enhanceTimingContent: some View {
    VStack(spacing: 8) {
      Text("Padding adds ms before/after each segment; auto-adjusts to avoid overlap.")
        .font(.caption2)
        .foregroundColor(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)

      VStack(spacing: 8) {
        HStack {
          Text("Left Pad")
            .font(.caption)
            .foregroundColor(.secondary)
          Spacer()
          TextField("0", value: $config.leftPadMs, formatter: numberFormatter)
            .textFieldStyle(.roundedBorder)
            .frame(width: 70)
            .multilineTextAlignment(.trailing)
          Text("ms")
            .font(.caption)
            .foregroundColor(.secondary)
        }
        HStack {
          Text("Right Pad")
            .font(.caption)
            .foregroundColor(.secondary)
          Spacer()
          TextField("0", value: $config.rightPadMs, formatter: numberFormatter)
            .textFieldStyle(.roundedBorder)
            .frame(width: 70)
            .multilineTextAlignment(.trailing)
          Text("ms")
            .font(.caption)
            .foregroundColor(.secondary)
        }
      }
      .padding(8)
      .background(
        Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous)
      )

      VStack(spacing: 8) {
        Toggle(isOn: $config.splitBySentence) {
          VStack(alignment: .leading, spacing: 2) {
            Text("Split By Sentence")
              .font(.caption)
            Text("Break segments on sentence-ending punctuation and commas before other rules.")
              .font(.caption2)
              .foregroundColor(.secondary)
          }
        }
        .toggleStyle(.switch)

        VStack(spacing: 6) {
          Text(
            "Control secondary splitting by character length (0 disables)."
          )
          .font(.caption2)
          .foregroundColor(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
          VStack(alignment: .leading, spacing: 6) {
            HStack {
              Text("Split By Chars")
                .font(.caption)
              Spacer()
              Text("\(Int(config.maxCharsPerSegment))")
                .font(.caption2)
                .foregroundColor(.secondary)
            }
            Slider(
              value: Binding(
                get: { Double(config.maxCharsPerSegment) },
                set: { config.maxCharsPerSegment = Int($0) }
              ),
              in: 0...100,
              step: 1
            )
          }
        }
        .help(
          "Set to 0 to skip character-based splitting. Applied after sentence splits if enabled.")
      }
      .padding(8)
      .background(
        Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous)
      )

      Text("Filter Silent hides empty segments in UI/export.")
        .font(.caption2)
        .foregroundColor(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)

      HStack {
        Text("Filter Silent")
          .font(.caption)
          .foregroundColor(.secondary)
        Spacer()
        Toggle("", isOn: $config.filterSilent)
          .labelsHidden()
      }
      .padding(8)
      .background(
        Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous)
      )
    }
  }

  private var enhanceHighlightContent: some View {
    VStack(spacing: 12) {
      VStack(alignment: .leading, spacing: 8) {
        Toggle(isOn: $config.effectExtractHighlights) {
          VStack(alignment: .leading, spacing: 2) {
            Text("Extract Highlight Keywords")
              .font(.caption)
            Text("Automatically identify keywords to emphasize in each segment.")
              .font(.caption2)
              .foregroundColor(.secondary)
          }
        }
        .toggleStyle(.switch)
      }
      .padding(8)
      .background(
        Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous)
      )

      VStack(alignment: .leading, spacing: 8) {
        Toggle(isOn: $config.effectEnableScaling) {
          VStack(alignment: .leading, spacing: 2) {
            Text("Enable Scaling")
              .font(.caption)
            Text("Increase keyword emphasis using the multiplier below.")
              .font(.caption2)
              .foregroundColor(.secondary)
          }
        }
        .toggleStyle(.switch)

        VStack(alignment: .leading, spacing: 6) {
          HStack {
            Text("Scale Multiplier")
              .font(.caption)
            Spacer()
            Text(String(format: "%.1fx", config.effectScaleMultiplier))
              .font(.caption2)
              .foregroundColor(.secondary)
          }
          Slider(value: $config.effectScaleMultiplier, in: 1.0...2.5, step: 0.1)
            .disabled(!config.effectEnableScaling)
          Text("Higher values make highlighted keywords larger in the Segments panel and exports.")
            .font(.caption2)
            .foregroundColor(.secondary)
        }
        .disabled(!config.effectEnableScaling)
        .opacity(config.effectEnableScaling ? 1 : 0.5)
      }
      .padding(8)
      .background(
        Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous)
      )
    }
  }

  private var enhanceZoomContent: some View {
    VStack(spacing: 12) {
      VStack(alignment: .leading, spacing: 8) {
        Toggle(isOn: $config.effectEnableZoom) {
          VStack(alignment: .leading, spacing: 2) {
            Text("Enable Zoom")
              .font(.caption)
            Text("Auto-zoom segments when highlights cover more than 50% of the text.")
              .font(.caption2)
              .foregroundColor(.secondary)
          }
        }
        .toggleStyle(.switch)

        VStack(alignment: .leading, spacing: 6) {
          HStack {
            Text("Zoom Multiplier")
              .font(.caption)
            Spacer()
            Text(String(format: "%.1fx", config.effectZoomMultiplier))
              .font(.caption2)
              .foregroundColor(.secondary)
          }
          Slider(value: $config.effectZoomMultiplier, in: 1.0...3.0, step: 0.1)
            .disabled(!config.effectEnableZoom)
          Text("Applies to the entire segment when highlight coverage exceeds 50%.")
            .font(.caption2)
            .foregroundColor(.secondary)
        }
        .disabled(!config.effectEnableZoom)
        .opacity(config.effectEnableZoom ? 1 : 0.5)
      }
      .padding(8)
      .background(
        Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous)
      )
    }
  }

  private var enhanceFilterContent: some View {
    let filterPunctuationBinding = Binding<Bool>(
      get: { !config.keepPunctuationOnExport },
      set: { config.keepPunctuationOnExport = !$0 }
    )

    return VStack(spacing: 12) {
      VStack(alignment: .leading, spacing: 8) {
        Toggle(isOn: $config.effectFilterFillerWords) {
          VStack(alignment: .leading, spacing: 2) {
            Text("Filter Filler Words")
              .font(.caption)
            Text("Remove speech fillers (e.g., uh, um, 嗯) from highlight analysis and keywords.")
              .font(.caption2)
              .foregroundColor(.secondary)
          }
        }
        .toggleStyle(.switch)
      }
      .padding(8)
      .background(
        Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous)
      )

      VStack(alignment: .leading, spacing: 6) {
        Toggle(isOn: filterPunctuationBinding) {
          VStack(alignment: .leading, spacing: 2) {
            Text("Filter punctuation")
              .font(.caption)
            Text("Only applied during export. When on, punctuation is removed in exported text.")
              .font(.caption2)
              .foregroundColor(.secondary)
          }
        }
        .toggleStyle(.switch)
      }
      .padding(8)
      .background(
        Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous)
      )

      VStack(alignment: .leading, spacing: 6) {
        HStack {
          Text("Filler Word List")
            .font(.caption)
          Spacer()
          Button("Reset") {
            config.effectFillerWords = SegmentEffectConfiguration.defaultFillerWords
            syncFillerWordsDraftFromConfig()
          }
          .buttonStyle(.borderless)
          .font(.caption2)
        }

        TextEditor(text: $fillerWordsDraft)
          .frame(minHeight: 76, idealHeight: 96)
          .font(.caption)
          .focused($isFillerWordEditorFocused)
          .padding(6)
          .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
              .fill(Color.primary.opacity(0.03))
          )
          .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
              .stroke(Color.primary.opacity(0.08))
          )
          .onAppear {
            syncFillerWordsDraftFromConfig()
          }
          .onChange(of: isFillerWordEditorFocused) { wasFocused, isFocused in
            if wasFocused && !isFocused {
              commitFillerWordsDraft()
            }
          }
          .onDisappear {
            commitFillerWordsDraft()
          }

        Text("Separate words by comma, space, or newline. Matching is case-insensitive.")
          .font(.caption2)
          .foregroundColor(.secondary)
      }
      .padding(8)
      .background(
        Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous)
      )
      .disabled(!config.effectFilterFillerWords)
      .opacity(config.effectFilterFillerWords ? 1 : 0.5)
    }
  }

  private func syncFillerWordsDraftFromConfig() {
    let current = config.effectFillerWords.joined(separator: "\n")
    if fillerWordsDraft != current {
      fillerWordsDraft = current
    }
  }

  private func commitFillerWordsDraft() {
    let parsed = SegmentEffectConfiguration.parseFillerWords(from: fillerWordsDraft)
    if parsed != config.effectFillerWords {
      config.effectFillerWords = parsed
    }
    let normalizedDraft = config.effectFillerWords.joined(separator: "\n")
    if fillerWordsDraft != normalizedDraft {
      fillerWordsDraft = normalizedDraft
    }
  }

  private var enhanceStyleContent: some View {
    let orientation = selectedSubtitleOrientation
    let defaultStyles = defaultSubtitleStyles[orientation]

    return VStack(alignment: .leading, spacing: 8) {
      Text("Subtitle Styles")
        .font(.caption)
      Text("Customize fonts, colors, and emphasis for the selected orientation.")
        .font(.caption2)
        .foregroundColor(.secondary)

      Picker("Subtitle Orientation", selection: $selectedSubtitleOrientation) {
        Text("Landscape").tag(SubtitleOrientation.landscape)
        Text("Portrait").tag(SubtitleOrientation.portrait)
      }
      .pickerStyle(.segmented)
      .labelsHidden()

      HStack {
        Text(orientation == .landscape ? "16:9 and wider videos" : "Vertical and square videos")
          .font(.caption2)
          .foregroundColor(.secondary)
        Spacer()
        Button("Reset Orientation") {
          config.updateSubtitleStyleSet(defaultStyles, for: orientation)
        }
        .buttonStyle(.borderless)
        .font(.caption2)
      }

      VStack(spacing: 12) {
        SubtitleStyleEditor(
          title: "Primary Line",
          subtitle: "Main transcription line shown in the Segments pane and exports.",
          kind: .primary,
          style: Binding(
            get: { config.subtitleStyleSet(for: orientation).primary },
            set: { newValue in
              var updated = config.subtitleStyleSet(for: orientation)
              updated.primary = newValue
              config.updateSubtitleStyleSet(updated, for: orientation)
            }
          ),
          defaultStyle: defaultStyles.primary
        )

        SubtitleStyleEditor(
          title: "Translation Line",
          subtitle: "Displayed when translated subtitles are enabled.",
          kind: .translation,
          style: Binding(
            get: { config.subtitleStyleSet(for: orientation).translation },
            set: { newValue in
              var updated = config.subtitleStyleSet(for: orientation)
              updated.translation = newValue
              config.updateSubtitleStyleSet(updated, for: orientation)
            }
          ),
          defaultStyle: defaultStyles.translation
        )

        SubtitleStyleEditor(
          title: "Highlight Emphasis",
          subtitle: "Applied to AI-highlighted keywords for emphasis.",
          kind: .highlight,
          style: Binding(
            get: { config.subtitleStyleSet(for: orientation).highlight },
            set: { newValue in
              var updated = config.subtitleStyleSet(for: orientation)
              updated.highlight = newValue
              config.updateSubtitleStyleSet(updated, for: orientation)
            }
          ),
          defaultStyle: defaultStyles.highlight
        )
      }
    }
    .padding(8)
    .background(
      Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous)
    )
  }

  fileprivate var outputContent: some View {
    VStack(spacing: 12) {
      Text("Configure export formats and related options.")
        .font(.caption2)
        .foregroundColor(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)

      Picker("Output Module", selection: $selectedOutputModule) {
        ForEach(OutputModule.allCases) { module in
          Text(module.label).tag(module)
        }
      }
      .pickerStyle(.segmented)
      .labelsHidden()
      .onAppear {
        if !OutputModule.allCases.contains(selectedOutputModule) {
          selectedOutputModule = OutputModule.allCases.first ?? .fcpxml
        }
      }
      .onChange(of: selectedOutputModule) { _, newValue in
        if !OutputModule.allCases.contains(newValue) {
          selectedOutputModule = OutputModule.allCases.first ?? .fcpxml
        }
      }

      Group {
        switch selectedOutputModule {
        case .fcpxml:
          fcpxmlModuleContent
        case .subtitleFiles:
          subtitleFilesModuleContent
        case .video:
          videoModuleContent
        case .audio:
          audioModuleContent
        }
      }
      .animation(.easeInOut(duration: 0.2), value: selectedOutputModule)
    }
  }

  private var fcpxmlModuleContent: some View {
    VStack(spacing: 8) {
      Text("Configure Final Cut Pro XML export settings.")
        .font(.caption2)
        .foregroundColor(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)

      VStack(alignment: .leading, spacing: 6) {
        Toggle(isOn: $config.fcpxmlEnabled) {
          VStack(alignment: .leading, spacing: 2) {
            Text("Enable FCPXML Export")
              .font(.caption)
            Text("When off, exports will only include selected subtitle files.")
              .font(.caption2)
              .foregroundColor(.secondary)
          }
        }
        .toggleStyle(.switch)

        if !config.fcpxmlEnabled {
          Text(
            "Re-enable to configure Final Cut Pro specific settings and per-video export button."
          )
          .font(.caption2)
          .foregroundColor(.secondary)
        }
      }
      .padding(8)
      .background(
        Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous)
      )

      VStack(spacing: 8) {
        VStack(alignment: .leading, spacing: 4) {
          Text("Project Prefix")
            .font(.caption)
            .foregroundColor(.secondary)
          TextField("Cliptate", text: $config.fcpxmlProjectName)
            .textFieldStyle(.roundedBorder)
          Text("Suffix will use today's date automatically.")
            .font(.caption2)
            .foregroundColor(.secondary)
        }

        HStack {
          Text("Frame Rate")
            .font(.caption)
            .foregroundColor(.secondary)
          Spacer()
          DecimalTextField(
            value: $config.fcpxmlFrameRate,
            clamp: FCPXMLSpeedParser.clampFrameRate
          )
          .frame(width: 70)
          Text("fps")
            .font(.caption)
            .foregroundColor(.secondary)
        }

        HStack {
          Text("Speed")
            .font(.caption)
            .foregroundColor(.secondary)
          Spacer()
          DecimalTextField(
            value: $config.fcpxmlSpeed,
            clamp: FCPXMLSpeedParser.clamp
          )
          .frame(width: 70)
          Text("×")
            .font(.caption)
            .foregroundColor(.secondary)
        }
      }
      .padding(8)
      .background(
        Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous)
      )
      .disabled(!config.fcpxmlEnabled)

      VStack(spacing: 8) {
        HStack {
          Text("Include Subtitles")
            .font(.caption)
            .foregroundColor(.secondary)
          Spacer()
          Toggle("", isOn: $config.fcpxmlIncludeSubtitles)
            .labelsHidden()
        }

        HStack {
          Text("DaVinci Resolve")
            .font(.caption)
            .foregroundColor(.secondary)
          Spacer()
          Toggle("", isOn: $config.fcpxmlIsResolveCompatible)
            .labelsHidden()
        }
      }
      .padding(8)
      .background(
        Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous)
      )
      .disabled(!config.fcpxmlEnabled)

      if config.fcpxmlEnabled {
        Text("DaVinci Resolve mode exports FCPXML 1.10 for better compatibility.")
          .font(.caption2)
          .foregroundColor(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
        Text("Choose Merge or Separate from the Export All button menu to control project layout.")
          .font(.caption2)
          .foregroundColor(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
  }

  private var subtitleFilesModuleContent: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Choose subtitle file formats to include with each export.")
        .font(.caption2)
        .foregroundColor(.secondary)

      ForEach(SubtitleExportFormat.allCases) { format in
        HStack {
          VStack(alignment: .leading, spacing: 2) {
            Text(format.displayName)
              .font(.caption)
              .fontWeight(.medium)
            Text(format.description)
              .font(.caption2)
              .foregroundColor(.secondary)
          }
          Spacer()
          Toggle(
            "",
            isOn: Binding(
              get: { config.subtitleExportFormats.contains(format) },
              set: { isOn in
                if isOn {
                  config.subtitleExportFormats.insert(format)
                } else {
                  config.subtitleExportFormats.remove(format)
                }
              }
            )
          )
          .labelsHidden()
        }
        .padding(8)
        .background(
          Color.primary.opacity(0.04),
          in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
      }

      Text("Selected formats will be exported alongside video and FCPXML outputs.")
        .font(.caption2)
        .foregroundColor(.secondary)
    }
  }

  private var videoModuleContent: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Choose default behaviour for exporting video files during batch export.")
        .font(.caption2)
        .foregroundColor(.secondary)

      GroupBox {
        Toggle(isOn: $config.videoExportEnabled) {
          VStack(alignment: .leading, spacing: 2) {
            Text("Enable Video Export")
              .font(.caption)
            Text(
              "When enabled, batch export can create rendered video files using the options below."
            )
            .font(.caption2)
            .foregroundColor(.secondary)
          }
        }
        .toggleStyle(.switch)
      } label: {
        Label("Video Export", systemImage: "play.rectangle")
      }

      VStack(spacing: 10) {
        HStack {
          Text("Format")
            .font(.caption)
            .foregroundColor(.secondary)
          Spacer()
          Picker("Format", selection: $config.videoExportFormat) {
            ForEach(VideoExportFormat.allCases) { format in
              Text(format.displayName).tag(format)
            }
          }
          .pickerStyle(.segmented)
          .disabled(!config.videoExportEnabled)
        }

        Toggle(isOn: $config.videoExportBurnInSubtitles) {
          VStack(alignment: .leading, spacing: 2) {
            Text("Burn Subtitles Into Video")
              .font(.caption)
            Text("If off, the export keeps a clean copy without rendered subtitles.")
              .font(.caption2)
              .foregroundColor(.secondary)
          }
        }
        .toggleStyle(.switch)
        .disabled(!config.videoExportEnabled)

        Divider()

        VStack(alignment: .leading, spacing: 2) {
          HStack {
            Text("Quality")
              .font(.caption)
              .foregroundColor(.secondary)
            Spacer()
            Picker("Quality", selection: $config.videoExportQuality) {
              ForEach(VideoExportQuality.allCases) { quality in
                Text(quality.displayName).tag(quality)
              }
            }
            .pickerStyle(.menu)
            .disabled(!config.videoExportEnabled)
          }

          Text(config.videoExportQuality.description)
            .font(.caption2)
            .foregroundColor(.secondary)
        }
      }
      .padding(8)
      .background(
        Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous)
      )
      .opacity(config.videoExportEnabled ? 1 : 0.5)

      Text("These settings become the defaults when opening the Export All dialog.")
        .font(.caption2)
        .foregroundColor(.secondary)
    }
  }

  private var audioModuleContent: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Configure standalone audio exports to accompany your subtitles and projects.")
        .font(.caption2)
        .foregroundColor(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)

      GroupBox {
        Toggle(isOn: $config.audioExportEnabled) {
          VStack(alignment: .leading, spacing: 2) {
            Text("Enable Audio Export")
              .font(.caption)
            Text("Create audio-only files during batch export using the selected format.")
              .font(.caption2)
              .foregroundColor(.secondary)
          }
        }
        .toggleStyle(.switch)
      } label: {
        Label("Audio Export", systemImage: "waveform.circle")
      }

      VStack(spacing: 10) {
        HStack {
          Text("Format")
            .font(.caption)
            .foregroundColor(.secondary)
          Spacer()
          Picker("Format", selection: $config.audioExportFormat) {
            ForEach(AudioExportFormat.allCases) { format in
              Text(format.displayName).tag(format)
            }
          }
          .pickerStyle(.segmented)
          .disabled(!config.audioExportEnabled)
        }

        Text("Audio files are exported alongside other assets when the option is enabled.")
          .font(.caption2)
          .foregroundColor(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .padding(8)
      .background(
        Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous)
      )
      .disabled(!config.audioExportEnabled)
      .opacity(config.audioExportEnabled ? 1 : 0.6)
    }
  }

  // MARK: - Dubbing Enhancement

  private var enhanceDubbingContent: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Configure voice dubbing to generate translated audio using TTS voice cloning.")
        .font(.caption2)
        .foregroundColor(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)

      GroupBox {
        Toggle(isOn: $config.audioDubbingEnabled) {
          VStack(alignment: .leading, spacing: 2) {
            Text("Enable Dubbing")
              .font(.caption)
            Text("Generate dubbed audio using TTS voice cloning with translated text during audio export.")
              .font(.caption2)
              .foregroundColor(.secondary)
          }
        }
        .toggleStyle(.switch)
      } label: {
        Label(
          String(localized: "Voice Dubbing", comment: "Dubbing enable toggle group box label"),
          systemImage: "person.wave.2"
        )
      }

      GroupBox {
        VStack(alignment: .leading, spacing: 8) {
          Picker(
            String(localized: "Voice Reference", comment: "Voice reference mode picker label"),
            selection: $config.dubbingVoiceReferenceMode
          ) {
            Text("Auto").tag(DubbingVoiceReferenceMode.automatic)
            Text("Custom").tag(DubbingVoiceReferenceMode.custom)
          }
          .pickerStyle(.segmented)

          if config.dubbingVoiceReferenceMode == .automatic {
            Text("Automatically extract voice reference from the source video for cloning.")
              .font(.caption2)
              .foregroundColor(.secondary)
          } else {
            Text("Provide a reference audio and its transcription for precise voice cloning.")
              .font(.caption2)
              .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 6) {
              HStack {
                Text("Reference Audio")
                  .font(.caption)
                  .foregroundColor(.secondary)
                Spacer()
                if !config.ttsReferenceAudioPath.isEmpty {
                  Text(URL(fileURLWithPath: config.ttsReferenceAudioPath).lastPathComponent)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                }
                Button {
                  pickReferenceAudioFile()
                } label: {
                  Label(
                    config.ttsReferenceAudioPath.isEmpty
                      ? String(localized: "Select", comment: "Select reference audio button")
                      : String(localized: "Change", comment: "Change reference audio button"),
                    systemImage: "waveform.badge.plus"
                  )
                  .font(.caption)
                }
                if !config.ttsReferenceAudioPath.isEmpty {
                  Button {
                    config.ttsReferenceAudioPath = ""
                    config.ttsReferenceAudioBookmark = nil
                  } label: {
                    Image(systemName: "xmark.circle.fill")
                      .foregroundColor(.secondary)
                  }
                  .buttonStyle(.plain)
                  .help(String(localized: "Clear reference audio", comment: "Clear reference audio tooltip"))
                }
              }

              VStack(alignment: .leading, spacing: 4) {
                Text("Reference Transcription")
                  .font(.caption)
                  .foregroundColor(.secondary)
                TextEditor(text: $config.ttsReferenceText)
                  .font(.caption)
                  .frame(height: 60)
                  .scrollContentBackground(.hidden)
                  .padding(4)
                  .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                      .fill(Color.primary.opacity(0.04))
                  )
                  .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                      .stroke(Color.primary.opacity(0.1))
                  )
                Text("Enter the exact transcription of the reference audio for accurate voice cloning.")
                  .font(.caption2)
                  .foregroundColor(.secondary)
              }
            }
            .padding(.top, 4)
          }
        }
      } label: {
        Label(
          String(localized: "Voice Clone", comment: "Voice clone settings group box label"),
          systemImage: "waveform.and.person.filled"
        )
      }
      .disabled(!config.audioDubbingEnabled)
      .opacity(config.audioDubbingEnabled ? 1 : 0.6)
    }
  }

  private func pickReferenceAudioFile() {
    #if canImport(AppKit)
      let panel = NSOpenPanel()
      panel.allowedContentTypes = [.audio]
      panel.allowsMultipleSelection = false
      panel.canChooseDirectories = false
      panel.message = String(localized: "Select a reference audio file for voice cloning", comment: "Reference audio picker message")
      panel.begin { response in
        guard response == .OK, let url = panel.url else { return }
        let needsStop = url.startAccessingSecurityScopedResource()
        defer { if needsStop { url.stopAccessingSecurityScopedResource() } }
        if let bookmark = try? url.bookmarkData(
          options: .withSecurityScope,
          includingResourceValuesForKeys: nil,
          relativeTo: nil
        ) {
          config.ttsReferenceAudioBookmark = bookmark
        }
        config.ttsReferenceAudioPath = url.path
      }
    #endif
  }

}

private enum EnhanceModule: String, CaseIterable, Identifiable {
  case timing
  case highlight
  case zoom
  case filter
  case style
  case dubbing

  var id: String { rawValue }

  var label: LocalizedStringKey {
    switch self {
    case .timing:   return "Timing"
    case .highlight: return "Highlight"
    case .zoom:     return "Zoom"
    case .filter:   return "Filter"
    case .style:    return "Style"
    case .dubbing:  return "Dubbing"
    }
  }
}

private enum OutputModule: String, CaseIterable, Identifiable {
  case fcpxml
  case subtitleFiles
  case video
  case audio

  var id: String { rawValue }

  static var allCases: [OutputModule] { [.fcpxml, .subtitleFiles, .video, .audio] }

  var label: LocalizedStringKey {
    switch self {
    case .fcpxml:        return "FCPXML"
    case .subtitleFiles: return "Subtitle Files"
    case .video:         return "Video"
    case .audio:         return "Audio"
    }
  }
}

extension ControlPanelConfigurationView {

private struct SubtitleStyleEditor: View {
  let title: String
  let subtitle: String
  let kind: SubtitleStyleKind
  @Binding var style: SubtitleStyle
  let defaultStyle: SubtitleStyle

  #if canImport(AppKit)
    private static let availableFonts: [String] = {
      let manager = NSFontManager.shared
      var names = Set(manager.availableFontFamilies.map { $0.trimmingCharacters(in: .whitespaces) })
      names.insert("Arial Unicode MS")
      return names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }()
  #else
    private static let availableFonts: [String] = ["Arial Unicode MS"]
  #endif

  private let fontRange: ClosedRange<Double> = 12...120

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      VStack(alignment: .leading, spacing: 4) {
        Text(title)
          .font(.subheadline)
          .fontWeight(.semibold)
        Text(subtitle)
          .font(.caption2)
          .foregroundColor(.secondary)
      }

      VStack(alignment: .leading, spacing: 6) {
        Text("Style Preset")
          .font(.caption)
          .foregroundColor(.secondary)

        Picker("Style Preset", selection: presetBinding) {
          ForEach(SubtitleStylePreset.allCases) { preset in
            Text(preset.displayName).tag(preset)
          }
        }
        .pickerStyle(.menu)

        Text(selectedPreset.description)
          .font(.caption2)
          .foregroundColor(.secondary)
      }

      Divider()

      fontControls

      Divider()

      emphasisControls

      Button(role: .destructive) {
        style = normalized(defaultStyle)
      } label: {
        Label("Reset to Default", systemImage: "arrow.clockwise")
          .font(.caption)
      }
      .buttonStyle(.borderless)
      .padding(.top, 4)
    }
    .padding(10)
    .background(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .fill(Color.primary.opacity(0.03))
    )
    .overlay(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .stroke(Color.primary.opacity(0.08))
    )
    .onAppear {
      style = normalized(style)
    }
  }

  private var selectedPreset: SubtitleStylePreset {
    style.matchedPreset() ?? SubtitleStylePreset.default(for: kind)
  }

  private var presetBinding: Binding<SubtitleStylePreset> {
    Binding(
      get: { selectedPreset },
      set: { newPreset in
        let fontSize = style.fontSize
        var updated = style.applyingPreset(newPreset, kind: kind)
        updated.fontSize = clamp(fontSize, within: fontRange)
        style = updated
      }
    )
  }

  private var fontControls: some View {
    VStack(alignment: .leading, spacing: 8) {
      #if canImport(AppKit)
        Picker(
          "Font",
          selection: Binding(
            get: { style.fontName },
            set: { style.fontName = $0 }
          )
        ) {
          ForEach(Self.availableFonts, id: \.self) { name in
            Text(name).tag(name)
          }
        }
        .pickerStyle(.menu)
      #else
        TextField(
          "Font",
          text: Binding(
            get: { style.fontName },
            set: { style.fontName = $0 }
          )
        )
        .textFieldStyle(.roundedBorder)
      #endif

      VStack(alignment: .leading, spacing: 6) {
        HStack {
          Text("Font Size")
            .font(.caption)
          Spacer()
          Text("\(Int(round(style.fontSize))) pt")
            .font(.caption2)
            .foregroundColor(.secondary)
        }
        Slider(
          value: Binding(
            get: { style.fontSize },
            set: { style.fontSize = clamp($0, within: fontRange) }
          ),
          in: fontRange,
          step: 1
        )
      }
    }
  }

  private var emphasisControls: some View {
    VStack(alignment: .leading, spacing: 6) {
      if kind == .highlight {
        HStack(spacing: 4) {
          Image(systemName: "bolt.fill")
            .foregroundColor(.yellow)
          Text("Highlight lines stay bold for emphasis.")
            .font(.caption2)
            .foregroundColor(.secondary)
        }
        .padding(.vertical, 2)
      } else {
        Toggle(
          "Bold",
          isOn: Binding(
            get: { style.bold },
            set: { style.bold = $0 }
          )
        )
        .toggleStyle(.switch)
        .font(.caption)
      }

      Toggle(
        "Italic",
        isOn: Binding(
          get: { style.italic },
          set: { style.italic = $0 }
        )
      )
      .toggleStyle(.switch)
      .font(.caption)
    }
  }

  private func normalized(_ incoming: SubtitleStyle) -> SubtitleStyle {
    var next = incoming
    if next.matchedPreset() == nil {
      next = next.applyingPreset(.default(for: kind), kind: kind)
    }
    if kind == .highlight {
      next.bold = true
    }
    next.fontSize = clamp(next.fontSize, within: fontRange)
    return next
  }

  private func clamp(_ value: Double, within range: ClosedRange<Double>) -> Double {
    min(max(value, range.lowerBound), range.upperBound)
  }
}
}
