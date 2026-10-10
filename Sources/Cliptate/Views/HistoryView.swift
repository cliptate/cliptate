import AppKit
import AVFoundation
import SwiftUI

struct HistoryView: View {
  @EnvironmentObject private var config: AppConfiguration
  @ObservedObject private var historyRuntime = HistoryRuntime.shared

  @State private var filter: SourceFilter = .all
  @State private var selectedSessionID: UUID?
  @State private var showingDeleteConfirmation = false
  @State private var sessionToDelete: TranscriptSession?
  @State private var searchText = ""
  @State private var isDictionaryAnalyzing = false
  @State private var showDictionaryTermsReview = false
  @State private var dictionaryAnalysisTerms: [String] = []
  @State private var dictionaryAnalysisError: String?

  enum SourceFilter: String, CaseIterable {
    case all = "All"
    case dictation = "Dictation"
    case fileTranscription = "File"
    case ttsSynthesis = "Text To Sound"

    var systemImage: String {
      switch self {
      case .all: return "tray.full"
      case .dictation: return "mic"
      case .fileTranscription: return "doc.text"
      case .ttsSynthesis: return "waveform"
      }
    }

    var accentColor: Color {
      switch self {
      case .all: return .accentColor
      case .dictation: return .blue
      case .fileTranscription: return .orange
      case .ttsSynthesis: return .purple
      }
    }
  }

  private var filteredSessions: [TranscriptSession] {
    let all = historyRuntime.allSortedSessions
    let bySource: [TranscriptSession]
    switch filter {
    case .all:
      bySource = all
    case .dictation:
      bySource = all.filter { ($0.source ?? .voiceDictation) == .voiceDictation }
    case .fileTranscription:
      bySource = all.filter { ($0.source ?? .voiceDictation) == .fileTranscription }
    case .ttsSynthesis:
      bySource = all.filter { ($0.source ?? .voiceDictation) == .ttsSynthesis }
    }
    guard !searchText.trimmingCharacters(in: .whitespaces).isEmpty else { return bySource }
    let q = searchText.lowercased()
    return bySource.filter {
      $0.combinedText.lowercased().contains(q)
        || ($0.sourceFileName?.lowercased().contains(q) ?? false)
    }
  }

  private var groupedSessions: [(label: String, sessions: [TranscriptSession])] {
    let calendar = Calendar.current
    let now = Date()
    var today: [TranscriptSession] = []
    var yesterday: [TranscriptSession] = []
    var thisWeek: [TranscriptSession] = []
    var older: [TranscriptSession] = []

    for session in filteredSessions {
      if calendar.isDateInToday(session.startTime) {
        today.append(session)
      } else if calendar.isDateInYesterday(session.startTime) {
        yesterday.append(session)
      } else if let days = calendar.dateComponents([.day], from: session.startTime, to: now).day,
        days < 7
      {
        thisWeek.append(session)
      } else {
        older.append(session)
      }
    }

    return [
      (String(localized: "Today", comment: "History group: sessions from today"), today),
      (String(localized: "Yesterday", comment: "History group: sessions from yesterday"), yesterday),
      (String(localized: "This Week", comment: "History group: sessions from this week"), thisWeek),
      (String(localized: "Older", comment: "History group: older sessions"), older),
    ].filter { !$0.sessions.isEmpty }
  }

  var body: some View {
    GeometryReader { proxy in
      if proxy.size.width >= 700 {
        splitLayout
      } else {
        compactLayout
      }
    }
    .background(Color(NSColor.windowBackgroundColor))
    .confirmationDialog(
      String(localized: "Delete this record?", comment: "History: delete confirmation title"),
      isPresented: $showingDeleteConfirmation,
      titleVisibility: .visible
    ) {
      Button(String(localized: "Delete", comment: "History: delete confirm button"), role: .destructive) {
        if let session = sessionToDelete {
          if session.id == selectedSessionID { selectedSessionID = nil }
          historyRuntime.remove(id: session.id)
        }
        sessionToDelete = nil
      }
      Button(String(localized: "Cancel", comment: "History: delete cancel button"), role: .cancel) { sessionToDelete = nil }
    } message: {
      Text("This will permanently remove the transcript entry.")
    }
    .sheet(isPresented: $showDictionaryTermsReview) {
      DictionaryTermsReviewSheet(
        terms: dictionaryAnalysisTerms,
        existingTerms: Set(config.voiceToTextCustomDictionary.map { $0.lowercased() }),
        onAdd: { terms in
          config.replaceDictionaryEntries(with: config.voiceToTextCustomDictionary + terms)
          showDictionaryTermsReview = false
        },
        onDismiss: { showDictionaryTermsReview = false }
      )
    }
    .alert(
      String(localized: "Analysis Failed", comment: "History: dictionary analysis error title"),
      isPresented: Binding(
        get: { dictionaryAnalysisError != nil },
        set: { if !$0 { dictionaryAnalysisError = nil } }
      )
    ) {
      Button(String(localized: "OK", comment: "History: dismiss error"), role: .cancel) {
        dictionaryAnalysisError = nil
      }
    } message: {
      Text(dictionaryAnalysisError ?? "")
    }
  }

  // MARK: - Layouts

  private var splitLayout: some View {
    HSplitView {
      listPanel
        .frame(minWidth: 280, idealWidth: 340, maxWidth: 420)
      detailPanel
        .frame(minWidth: 320, maxWidth: .infinity)
    }
  }

  private var compactLayout: some View {
    listPanel
  }

  // MARK: - List panel

  private var listPanel: some View {
    VStack(spacing: 0) {
      listHeader
      Divider()
      if filteredSessions.isEmpty {
        emptyState
      } else {
        sessionList
      }
    }
  }

  private var listHeader: some View {
    VStack(alignment: .leading, spacing: 12) {
      // Title row
      HStack(alignment: .center, spacing: 0) {
        VStack(alignment: .leading, spacing: 2) {
          Text("History")
            .font(.title2.weight(.bold))
          Text(
            historyRuntime.allSortedSessions.count == 1
              ? String(localized: "1 record", comment: "History: single record count")
              : String(localized: "\(historyRuntime.allSortedSessions.count) records", comment: "History: record count")
          )
          .font(.caption)
          .foregroundStyle(.secondary)
        }
        Spacer()
        if !historyRuntime.allSortedSessions.isEmpty {
          Menu {
            Button(role: .destructive) {
              historyRuntime.removeAll(source: .voiceDictation)
              pruneSelectedIfNeeded()
            } label: {
              Label("Clear Dictation History", systemImage: "mic.slash")
            }
            Button(role: .destructive) {
              historyRuntime.removeAll(source: .fileTranscription)
              pruneSelectedIfNeeded()
            } label: {
              Label("Clear File Transcription History", systemImage: "trash")
            }
            Button(role: .destructive) {
              historyRuntime.removeAll(source: .ttsSynthesis)
              pruneSelectedIfNeeded()
            } label: {
              Label("Clear Text To Sound History", systemImage: "waveform.slash")
            }
            Divider()
            Button(role: .destructive) {
              historyRuntime.removeAll()
              selectedSessionID = nil
            } label: {
              Label("Clear All History", systemImage: "trash")
            }
            if config.aiEnabled {
              Divider()
              Button {
                analyzeForDictionary()
              } label: {
                if isDictionaryAnalyzing {
                  Label("Analyzing…", systemImage: "sparkles")
                } else {
                  Label("Analyze for Dictionary", systemImage: "text.badge.plus")
                }
              }
              .disabled(filteredSessions.isEmpty || isDictionaryAnalyzing)
            }
          } label: {
            Image(systemName: "ellipsis.circle")
              .font(.body)
              .foregroundStyle(.secondary)
          }
          .menuStyle(.borderlessButton)
          .fixedSize()
          .help(String(localized: "Manage history", comment: "History: manage button tooltip"))
        }
      }

      // Filter chips
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 6) {
          ForEach(SourceFilter.allCases, id: \.self) { f in
            FilterChip(
              label: LocalizedStringKey(f.rawValue),
              icon: f.systemImage,
              accent: f.accentColor,
              isSelected: filter == f
            ) {
              withAnimation(.easeInOut(duration: 0.15)) {
                filter = f
              }
            }
          }
        }
        .padding(.horizontal, 1) // avoid clip
      }

      // Search bar
      HStack(spacing: 7) {
        Image(systemName: "magnifyingglass")
          .foregroundStyle(.tertiary)
          .font(.caption)
        TextField(
          String(localized: "Search transcripts…", comment: "History: search placeholder"),
          text: $searchText
        )
        .textFieldStyle(.plain)
        .font(.callout)
        if !searchText.isEmpty {
          Button { searchText = "" } label: {
            Image(systemName: "xmark.circle.fill")
              .foregroundStyle(.secondary)
              .font(.caption)
          }
          .buttonStyle(.plain)
        }
      }
      .padding(.horizontal, 9)
      .padding(.vertical, 6)
      .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
    }
    .padding(.horizontal, 14)
    .padding(.top, 16)
    .padding(.bottom, 12)
  }

  private var sessionList: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
        ForEach(groupedSessions, id: \.label) { group in
          Section {
            ForEach(group.sessions) { session in
              HistoryRowView(
                session: session,
                isSelected: session.id == selectedSessionID,
                onSelect: { selectedSessionID = session.id },
                onCopy: { copySession(session) },
                onDelete: {
                  sessionToDelete = session
                  showingDeleteConfirmation = true
                }
              )
              .padding(.horizontal, 10)
              .padding(.vertical, 3)
            }
          } header: {
            Text(group.label)
              .font(.caption2.weight(.semibold))
              .foregroundStyle(.tertiary)
              .textCase(.uppercase)
              .tracking(0.5)
              .padding(.horizontal, 14)
              .padding(.vertical, 5)
              .frame(maxWidth: .infinity, alignment: .leading)
              .background(.ultraThinMaterial)
          }
        }
      }
      .padding(.bottom, 16)
    }
  }

  // MARK: - Detail panel

  private var detailPanel: some View {
    Group {
      if let id = selectedSessionID,
        let session = historyRuntime.sessions.first(where: { $0.id == id })
      {
        HistoryDetailView(
          session: session,
          onCopy: { copySession(session) },
          onDelete: {
            sessionToDelete = session
            showingDeleteConfirmation = true
          }
        )
      } else {
        detailPlaceholder
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var detailPlaceholder: some View {
    VStack(spacing: 12) {
      ZStack {
        Circle()
          .fill(.secondary.opacity(0.08))
          .frame(width: 64, height: 64)
        Image(systemName: "clock.badge.questionmark")
          .font(.system(size: 28, weight: .light))
          .foregroundStyle(.secondary)
      }
      VStack(spacing: 4) {
        Text("No Record Selected")
          .font(.headline)
          .foregroundStyle(.secondary)
        Text("Click any session on the left to view its full transcript.")
          .font(.caption)
          .foregroundStyle(.tertiary)
          .multilineTextAlignment(.center)
          .frame(maxWidth: 200)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(NSColor.controlBackgroundColor))
  }

  // MARK: - Empty state

  private var emptyState: some View {
    VStack(spacing: 14) {
      ZStack {
        Circle()
          .fill(.secondary.opacity(0.08))
          .frame(width: 64, height: 64)
        Image(systemName: searchText.isEmpty ? "clock" : "magnifyingglass")
          .font(.system(size: 26, weight: .light))
          .foregroundStyle(.secondary)
      }
      VStack(spacing: 4) {
        Text(searchText.isEmpty ? "No Records" : "No Results")
          .font(.headline)
          .foregroundStyle(.primary)
        Text(
          searchText.isEmpty
            ? "Dictation sessions, file transcriptions and TTS synthesis will appear here."
            : "Try a different search term."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .frame(maxWidth: 220)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding()
  }

  // MARK: - Actions

  private func copySession(_ session: TranscriptSession) {
    let pb = NSPasteboard.general
    pb.clearContents()
    pb.setString(session.combinedText, forType: .string)
  }

  private func analyzeForDictionary() {
    let sessions = filteredSessions
    guard !sessions.isEmpty else { return }
    isDictionaryAnalyzing = true
    dictionaryAnalysisError = nil
    Task {
      let text = AICorrector.buildDictionaryAnalysisText(from: sessions)
      guard !text.isEmpty else {
        await MainActor.run { isDictionaryAnalyzing = false }
        return
      }
      do {
        let provider = config.selectedAIProvider
        let apiKey = config.aiProviderKeys[provider] ?? ""
        let terms = try await AICorrector.extractDictionaryTerms(
          from: text,
          provider: provider,
          model: config.aiModel(for: provider),
          apiKey: apiKey,
          openAIBaseURL: config.resolvedOpenAIEndpoint
        )
        await MainActor.run {
          dictionaryAnalysisTerms = terms
          isDictionaryAnalyzing = false
          showDictionaryTermsReview = true
        }
      } catch {
        await MainActor.run {
          dictionaryAnalysisError = error.localizedDescription
          isDictionaryAnalyzing = false
        }
      }
    }
  }

  private func pruneSelectedIfNeeded() {
    if let id = selectedSessionID {
      let stillExists = historyRuntime.sessions.contains { $0.id == id }
      if !stillExists { selectedSessionID = nil }
    }
  }
}

// MARK: - Filter Chip

private struct FilterChip: View {
  let label: LocalizedStringKey
  let icon: String
  let accent: Color
  let isSelected: Bool
  let action: () -> Void

  @State private var isHovered = false

  var body: some View {
    Button(action: action) {
      HStack(spacing: 5) {
        Image(systemName: icon)
          .font(.caption2.weight(.semibold))
        Text(label)
          .font(.caption.weight(.medium))
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 5)
      .background(
        isSelected ? accent.opacity(0.15) : (isHovered ? Color.primary.opacity(0.06) : Color.clear),
        in: Capsule()
      )
      .overlay(
        Capsule()
          .stroke(isSelected ? accent.opacity(0.4) : Color.secondary.opacity(0.2), lineWidth: 1)
      )
      .foregroundStyle(isSelected ? accent : Color.secondary)
    }
    .buttonStyle(.plain)
    .onHover { isHovered = $0 }
  }
}

// MARK: - Row view

private struct HistoryRowView: View {
  let session: TranscriptSession
  let isSelected: Bool
  let onSelect: () -> Void
  let onCopy: () -> Void
  let onDelete: () -> Void

  @State private var isHovered = false

  private var effectiveSource: SessionSource { session.source ?? .voiceDictation }

  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      sourceIcon
      VStack(alignment: .leading, spacing: 3) {
        titleRow
        previewText
        metaRow
      }
      Spacer(minLength: 0)
      if isHovered || isSelected {
        actionButtons
          .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .trailing)))
      }
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 9)
    .background(rowBackground)
    .overlay(rowBorder)
    .contentShape(RoundedRectangle(cornerRadius: 10))
    .onTapGesture(perform: onSelect)
    .onHover { isHovered = $0 }
    .animation(.easeInOut(duration: 0.12), value: isHovered)
  }

  @ViewBuilder
  private var rowBackground: some View {
    RoundedRectangle(cornerRadius: 10)
      .fill(
        isSelected
          ? sourceAccentColor.opacity(0.1)
          : (isHovered ? Color.primary.opacity(0.04) : Color(NSColor.textBackgroundColor))
      )
  }

  private var rowBorder: some View {
    RoundedRectangle(cornerRadius: 10)
      .stroke(
        isSelected ? sourceAccentColor.opacity(0.35) : Color.secondary.opacity(0.1),
        lineWidth: isSelected ? 1.2 : 1
      )
  }

  private var sourceAccentColor: Color {
    switch effectiveSource {
    case .voiceDictation: return .blue
    case .fileTranscription: return .orange
    case .ttsSynthesis: return .purple
    }
  }

  private var sourceIcon: some View {
    let (icon, tint): (String, Color) = {
      switch effectiveSource {
      case .voiceDictation: return ("mic.fill", .blue)
      case .fileTranscription: return ("doc.text.fill", .orange)
      case .ttsSynthesis: return ("waveform", .purple)
      }
    }()
    return Image(systemName: icon)
      .font(.caption.weight(.semibold))
      .foregroundStyle(tint)
      .frame(width: 28, height: 28)
      .background(tint.opacity(0.12))
      .clipShape(RoundedRectangle(cornerRadius: 7))
  }

  private var titleRow: some View {
    HStack(spacing: 5) {
      // Primary label
      Group {
        switch effectiveSource {
        case .fileTranscription:
          if let name = session.sourceFileName {
            Text(name)
              .font(.caption.weight(.semibold))
              .lineLimit(1)
          }
        case .ttsSynthesis:
          if let modelName = session.sourceFileName {
            Text(modelName)
              .font(.caption.weight(.semibold))
              .foregroundStyle(.purple)
              .lineLimit(1)
          } else {
            Text("TTS Synthesis")
              .font(.caption.weight(.semibold))
          }
        case .voiceDictation:
          Text(session.startTime.formatted(.dateTime.hour().minute()))
            .font(.caption.weight(.semibold))
        }
      }

      Text("·")
        .font(.caption2)
        .foregroundStyle(.quaternary)

      Text(session.startTime.formatted(.dateTime.month(.abbreviated).day()))
        .font(.caption2)
        .foregroundStyle(.secondary)

      if let duration = formattedSessionDuration(session) {
        Text("·")
          .font(.caption2)
          .foregroundStyle(.quaternary)
        Text(duration)
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
    }
  }

  private var previewText: some View {
    Text(session.combinedText)
      .font(.caption)
      .foregroundStyle(.secondary)
      .lineLimit(2)
      .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var metaRow: some View {
    HStack(spacing: 5) {
      if let type = session.transcriberType {
        badge(type.displayName, tint: .purple)
      }
      if let lang = session.language {
        badge(lang.displayName, tint: .green)
      }
      let words = voiceTextWordCount(in: session.combinedText)
      if words > 0 {
        badge("\(words)w", tint: .secondary)
      }
    }
  }

  private func badge(_ text: String, tint: Color) -> some View {
    Text(text)
      .font(.caption2.weight(.medium))
      .padding(.horizontal, 5)
      .padding(.vertical, 2)
      .background(tint.opacity(0.09))
      .foregroundStyle(tint)
      .clipShape(Capsule())
  }

  private var actionButtons: some View {
    VStack(spacing: 4) {
      Button(action: onCopy) {
        Image(systemName: "doc.on.doc")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
      }
      .buttonStyle(.plain)
      .help(String(localized: "Copy transcript", comment: "History: copy row button tooltip"))

      Button(role: .destructive, action: onDelete) {
        Image(systemName: "trash")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.red)
      }
      .buttonStyle(.plain)
      .help(String(localized: "Delete record", comment: "History: delete row button tooltip"))
    }
    .padding(.leading, 4)
  }
}

// MARK: - Detail view

private struct HistoryDetailView: View {
  @EnvironmentObject private var config: AppConfiguration

  let session: TranscriptSession
  let onCopy: () -> Void
  let onDelete: () -> Void

  @State private var isCopied = false
  @State private var audioPlayer: AVAudioPlayer?
  @State private var isPlayingAudio = false
  @State private var playbackProgress: Double = 0.0
  @State private var playbackDuration: Double = 0.0
  @State private var playbackTimer: Timer?
  @State private var isRetranscribing = false
  @State private var retranscribeProgress: Double = 0.0
  @State private var historyErrorMessage: String?

  // Display toggles for file transcription detail
  @State private var showSpeaker = true
  @State private var showOriginalText = true
  @State private var showTranslation = true
  @State private var showTimestamps = true

  private var effectiveSource: SessionSource { session.source ?? .voiceDictation }

  private var sourceAccentColor: Color {
    switch effectiveSource {
    case .voiceDictation: return .blue
    case .fileTranscription: return .orange
    case .ttsSynthesis: return .purple
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      detailHeader
      Divider()
      if effectiveSource == .voiceDictation, let url = session.recordingURL,
        FileManager.default.fileExists(atPath: url.path)
      {
        dictationPlaybackBar
        Divider()
      }
      if isRetranscribing {
        retranscribeProgressBar
        Divider()
      }
      if effectiveSource == .fileTranscription, let segments = session.aiCutSegments, !segments.isEmpty {
        fileTranscriptionToggles
        Divider()
        ScrollView {
          fileTranscriptionContent(segments: filteredSegments(segments))
            .padding(20)
        }
      } else if effectiveSource == .voiceDictation, session.lines.count > 1 {
        dictationDisplayToggles
        Divider()
        ScrollView {
          dictationLinesContent
            .padding(20)
        }
      } else {
        ScrollView {
          Text(session.combinedText)
            .font(.body)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
      }
    }
    .background(Color(NSColor.controlBackgroundColor))
    .onDisappear {
      stopPlayback()
    }
    .onChange(of: session.id) {
      stopPlayback()
    }
    .alert(
      "Error",
      isPresented: Binding(
        get: { historyErrorMessage != nil },
        set: { if !$0 { historyErrorMessage = nil } }
      )
    ) {
      Button("OK") { historyErrorMessage = nil }
    } message: {
      Text(historyErrorMessage ?? "")
    }
  }

  // MARK: - Detail Header

  private var detailHeader: some View {
    VStack(alignment: .leading, spacing: 12) {
      // Source + title
      HStack(alignment: .top, spacing: 0) {
        HStack(spacing: 10) {
          // Accent icon
          ZStack {
            RoundedRectangle(cornerRadius: 9)
              .fill(sourceAccentColor.opacity(0.12))
              .frame(width: 36, height: 36)
            Image(systemName: sourceIconName)
              .font(.system(size: 15, weight: .semibold))
              .foregroundStyle(sourceAccentColor)
          }

          VStack(alignment: .leading, spacing: 2) {
            sourceLabel
            HStack(spacing: 6) {
              Text(
                session.startTime.formatted(
                  .dateTime.month(.wide).day().year().hour().minute().second()
                )
              )
              .font(.caption)
              .foregroundStyle(.secondary)
              if let duration = formattedSessionDuration(session) {
                Text("·")
                  .font(.caption2)
                  .foregroundStyle(.quaternary)
                Text(duration)
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
            }
          }
        }
        Spacer(minLength: 8)
        actionRow
      }

      // Meta badges
      metaBadges
    }
    .padding(.horizontal, 16)
    .padding(.top, 16)
    .padding(.bottom, 12)
  }

  private var sourceIconName: String {
    switch effectiveSource {
    case .voiceDictation: return "mic.fill"
    case .fileTranscription: return "doc.text.fill"
    case .ttsSynthesis: return "waveform"
    }
  }

  private var sourceLabel: some View {
    Group {
      switch effectiveSource {
      case .fileTranscription:
        Text(session.sourceFileName ?? "File Transcription")
          .font(.subheadline.weight(.semibold))
          .lineLimit(1)
      case .ttsSynthesis:
        Text(session.sourceFileName.map { "TTS · \($0)" } ?? "TTS Synthesis")
          .font(.subheadline.weight(.semibold))
          .lineLimit(1)
      case .voiceDictation:
        Text("Voice Dictation")
          .font(.subheadline.weight(.semibold))
      }
    }
  }

  private var actionRow: some View {
    HStack(spacing: 6) {
      if effectiveSource == .fileTranscription {
        Button {
          openInAICut()
        } label: {
          Label("Open in AI Cut", systemImage: "film.stack")
            .font(.caption.weight(.medium))
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .help("Re-open the source video in AI Cut editor")

        Button {
          retranscribeFile()
        } label: {
          Label(
            String(localized: "Re-transcribe", comment: "History: re-transcribe file button"),
            systemImage: "arrow.clockwise"
          )
          .font(.caption.weight(.medium))
        }
        .buttonStyle(.bordered)
        .tint(.orange)
        .controlSize(.small)
        .disabled(isRetranscribing)
        .help(String(localized: "Re-transcribe with current model settings", comment: "History: re-transcribe button help"))

        Button {
          revealSourceFileInFinder()
        } label: {
          Image(systemName: "arrow.up.forward.square")
            .font(.caption.weight(.medium))
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .help(String(localized: "Reveal source file in Finder", comment: "History: reveal file button help"))
      }

      if effectiveSource == .voiceDictation, session.recordingURL != nil {
        Button {
          revealDictationRecordingInFinder()
        } label: {
          Image(systemName: "arrow.up.forward.square")
            .font(.caption.weight(.medium))
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .help(String(localized: "Reveal recording file in Finder", comment: "History: reveal recording button help"))
      }

      if effectiveSource == .ttsSynthesis, session.ttsAudioBookmark != nil {
        Button {
          toggleTTSPlayback()
        } label: {
          Label(
            isPlayingAudio ? "Stop" : "Play Audio",
            systemImage: isPlayingAudio ? "stop.fill" : "play.fill"
          )
          .font(.caption.weight(.medium))
        }
        .buttonStyle(.bordered)
        .tint(.purple)
        .controlSize(.small)
        .help(isPlayingAudio ? "Stop audio playback" : "Play synthesized audio")

        Button {
          revealTTSAudioInFinder()
        } label: {
          Image(systemName: "arrow.up.forward.square")
            .font(.caption.weight(.medium))
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .help("Reveal audio file in Finder")
      }

      Button {
        copyWithToggles()
        isCopied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { isCopied = false }
      } label: {
        Label(isCopied ? "Copied!" : "Copy", systemImage: isCopied ? "checkmark" : "doc.on.doc")
          .font(.caption.weight(.medium))
      }
      .buttonStyle(.bordered)
      .tint(isCopied ? .green : .accentColor)
      .controlSize(.small)
      .animation(.easeInOut(duration: 0.2), value: isCopied)

      Button(role: .destructive, action: onDelete) {
        Image(systemName: "trash")
          .font(.caption.weight(.medium))
      }
      .buttonStyle(.bordered)
      .controlSize(.small)
      .help(String(localized: "Delete this record", comment: "History: delete detail button tooltip"))
    }
  }

  private var metaBadges: some View {
    HStack(spacing: 6) {
      if let type = session.transcriberType {
        detailBadge(type.displayName, icon: "waveform", tint: .purple)
      }
      if let model = session.modelVariant {
        detailBadge(model.displayName, icon: "cpu", tint: .blue)
      }
      if let lang = session.language {
        detailBadge(lang.displayName, icon: "globe", tint: .green)
      }
      let words = voiceTextWordCount(in: session.combinedText)
      let chars = session.combinedText.filter { !$0.isWhitespace }.count
      detailBadge("\(words)w · \(chars)c", icon: "text.alignleft", tint: .secondary)
    }
    .flexWrap()
  }

  private func detailBadge(_ text: String, icon: String, tint: Color) -> some View {
    Label(text, systemImage: icon)
      .font(.caption2.weight(.semibold))
      .padding(.horizontal, 8)
      .padding(.vertical, 4)
      .background(tint.opacity(0.10))
      .foregroundStyle(tint)
      .clipShape(Capsule())
  }

  // MARK: - File Transcription Display Toggles

  private var fileTranscriptionToggles: some View {
    HStack(spacing: 10) {
      toggleChip(
        String(localized: "Timestamps", comment: "History toggle: show timestamps"),
        icon: "clock",
        isOn: $showTimestamps
      )
      toggleChip(
        String(localized: "Speaker", comment: "History toggle: show speaker"),
        icon: "person.wave.2",
        isOn: $showSpeaker
      )
      toggleChip(
        String(localized: "Original", comment: "History toggle: show original text"),
        icon: "text.alignleft",
        isOn: $showOriginalText
      )
      toggleChip(
        String(localized: "Translation", comment: "History toggle: show translation"),
        icon: "character.book.closed",
        isOn: $showTranslation
      )
      Spacer()
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 8)
    .background(Color(NSColor.controlBackgroundColor))
  }

  // MARK: - Dictation Display Toggles

  private var dictationDisplayToggles: some View {
    HStack(spacing: 10) {
      toggleChip(
        String(localized: "Timestamps", comment: "History toggle: show timestamps"),
        icon: "clock",
        isOn: $showTimestamps
      )
      toggleChip(
        String(localized: "Speaker", comment: "History toggle: show speaker"),
        icon: "person.wave.2",
        isOn: $showSpeaker
      )
      Spacer()
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 8)
    .background(Color(NSColor.controlBackgroundColor))
  }

  @ViewBuilder
  private func toggleChip(_ label: String, icon: String, isOn: Binding<Bool>) -> some View {
    Button {
      withAnimation(.easeInOut(duration: 0.12)) {
        isOn.wrappedValue.toggle()
      }
    } label: {
      HStack(spacing: 4) {
        Image(systemName: icon)
          .font(.caption2)
        Text(label)
          .font(.caption2.weight(.medium))
      }
      .padding(.horizontal, 8)
      .padding(.vertical, 4)
      .background(
        isOn.wrappedValue
          ? Color.accentColor.opacity(0.12)
          : Color.secondary.opacity(0.08),
        in: Capsule()
      )
      .foregroundStyle(isOn.wrappedValue ? Color.accentColor : Color.secondary)
    }
    .buttonStyle(.plain)
  }

  private var dictationLinesContent: some View {
    let hasSpeakers = session.lines.contains { $0.speakerId != nil }

    return VStack(alignment: .leading, spacing: 8) {
      ForEach(session.lines) { line in
        VStack(alignment: .leading, spacing: 3) {
          HStack(spacing: 6) {
            if showTimestamps {
              let minutes = Int(line.timestamp) / 60
              let seconds = Int(line.timestamp) % 60
              Text(String(format: "%d:%02d", minutes, seconds))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
                .frame(minWidth: 44, alignment: .leading)
            }
            if showSpeaker, hasSpeakers, let speaker = line.speakerId {
              Text(String(localized: "Speaker \(speaker + 1)", comment: "History: speaker label"))
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(speakerColor(for: speaker).opacity(0.15))
                .foregroundStyle(speakerColor(for: speaker))
                .clipShape(Capsule())
            }
          }

          Text(line.text)
            .font(.body)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)

        if line.id != session.lines.last?.id {
          Divider().opacity(0.5)
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func filteredSegments(_ segments: [Segment]) -> [Segment] {
    guard let removedIDs = session.aiCutRemovedSegmentIDs, !removedIDs.isEmpty else {
      return segments
    }
    return segments.filter { !removedIDs.contains(SegmentIdentifier(segment: $0)) }
  }

  private func fileTranscriptionContent(segments: [Segment]) -> some View {
    let translations = session.aiCutProcessedTranslations
    let hasSpeakers = segments.contains { $0.speakerId != nil }
    let hasTranslations = (translations != nil && !translations!.isEmpty)
      || segments.contains { $0.translation != nil }

    return VStack(alignment: .leading, spacing: 8) {
      ForEach(segments, id: \.id) { segment in
        VStack(alignment: .leading, spacing: 3) {
          HStack(spacing: 6) {
            if showTimestamps {
              Text(formatTimestamp(segment.startTime))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
                .frame(minWidth: 44, alignment: .leading)
            }
            if showSpeaker, hasSpeakers, let speaker = segment.speakerId {
              Text(String(localized: "Speaker \(speaker + 1)", comment: "History: speaker label"))
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(speakerColor(for: speaker).opacity(0.15))
                .foregroundStyle(speakerColor(for: speaker))
                .clipShape(Capsule())
            }
          }

          if showOriginalText {
            Text(segment.text)
              .font(.body)
              .textSelection(.enabled)
              .frame(maxWidth: .infinity, alignment: .leading)
          }

          if showTranslation, hasTranslations {
            let translation = translationText(for: segment, translations: translations)
            if let translation, !translation.isEmpty {
              Text(translation)
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
          }
        }
        .padding(.vertical, 4)

        if segment.id != segments.last?.id {
          Divider().opacity(0.5)
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func translationText(
    for segment: Segment,
    translations: [String: SegmentTranslation]?
  ) -> String? {
    if let translations, let t = translations[segment.id] {
      return t.text
    }
    return segment.translation?.text
  }

  private func speakerColor(for speakerId: Int) -> Color {
    let colors: [Color] = [.blue, .orange, .green, .purple, .pink, .cyan, .mint, .indigo]
    return colors[speakerId % colors.count]
  }

  private func formatTimestamp(_ time: TimeInterval) -> String {
    let totalSeconds = Int(time)
    let minutes = totalSeconds / 60
    let seconds = totalSeconds % 60
    return String(format: "%d:%02d", minutes, seconds)
  }

  private func openInAICut() {
    guard let bookmarkData = session.sourceURLBookmark else { return }
    var isStale = false
    guard
      let url = try? URL(
        resolvingBookmarkData: bookmarkData,
        options: .withSecurityScope,
        relativeTo: nil,
        bookmarkDataIsStale: &isStale
      ), !isStale
    else { return }

    var preloaded: [URL: VideoState] = [:]
    if let segments = session.aiCutSegments, !segments.isEmpty {
      let state = VideoState(segments: segments)
      let maxEnd = segments.map(\.endTime).max() ?? 0
      state.audioDuration = maxEnd
      state.lastTranslatedLanguage = session.aiCutLastTranslatedLanguage
      state.translationSignature = segments.isEmpty ? nil : SegmentSignature.compute(for: segments)
      state.historySessionID = session.id
      if let persisted = session.aiCutProcessedTranslations, !persisted.isEmpty {
        state.processedTranslations = persisted
      } else {
        state.extractTranslationsFromSegments()
      }
      if let removedIDs = session.aiCutRemovedSegmentIDs, !removedIDs.isEmpty {
        state.removedProcessedSegmentIDs = removedIDs
      }
      preloaded[url] = state
    }

    AICutDetachedSessionWindowManager.shared.openSession(
      urls: [url],
      preloadedVideoStates: preloaded,
      config: config
    )
  }

  // MARK: - Dictation Audio Playback

  private var dictationPlaybackBar: some View {
    HStack(spacing: 12) {
      Button {
        toggleDictationPlayback()
      } label: {
        ZStack {
          Circle()
            .fill(.blue.opacity(0.12))
            .frame(width: 30, height: 30)
          Image(systemName: isPlayingAudio ? "pause.fill" : "play.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.blue)
        }
      }
      .buttonStyle(.plain)
      .help(isPlayingAudio
        ? String(localized: "Pause", comment: "History: pause audio playback")
        : String(localized: "Play", comment: "History: play audio playback"))

      Slider(
        value: Binding(
          get: { playbackProgress },
          set: { newValue in
            playbackProgress = newValue
            audioPlayer?.currentTime = newValue * playbackDuration
          }
        ),
        in: 0...1
      )
      .tint(.blue)

      Text(formatPlaybackTime(playbackProgress * playbackDuration) + " / " + formatPlaybackTime(playbackDuration))
        .font(.caption.monospacedDigit())
        .foregroundStyle(.secondary)
        .frame(minWidth: 80, alignment: .trailing)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
  }

  private var retranscribeProgressBar: some View {
    HStack(spacing: 10) {
      ProgressView(value: retranscribeProgress)
        .progressViewStyle(.linear)
        .tint(.orange)
      Text(String(localized: "Re-transcribing…", comment: "History: re-transcription in progress"))
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 8)
  }

  private func toggleDictationPlayback() {
    if isPlayingAudio {
      audioPlayer?.pause()
      isPlayingAudio = false
      playbackTimer?.invalidate()
      playbackTimer = nil
      return
    }

    if let player = audioPlayer {
      player.play()
      isPlayingAudio = true
      startPlaybackTimer()
      return
    }

    guard let url = session.recordingURL,
      FileManager.default.fileExists(atPath: url.path),
      let player = try? AVAudioPlayer(contentsOf: url)
    else { return }

    player.prepareToPlay()
    playbackDuration = player.duration
    playbackProgress = 0
    audioPlayer = player
    isPlayingAudio = true
    player.play()
    startPlaybackTimer()
  }

  private func startPlaybackTimer() {
    playbackTimer?.invalidate()
    playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
      Task { @MainActor in
        guard let player = self.audioPlayer else {
          self.playbackTimer?.invalidate()
          self.playbackTimer = nil
          return
        }
        if !player.isPlaying && player.currentTime >= player.duration - 0.1 {
          self.isPlayingAudio = false
          self.playbackProgress = 0
          self.audioPlayer = nil
          self.playbackTimer?.invalidate()
          self.playbackTimer = nil
        } else {
          self.playbackProgress = player.duration > 0 ? player.currentTime / player.duration : 0
        }
      }
    }
  }

  private func stopPlayback() {
    audioPlayer?.stop()
    audioPlayer = nil
    isPlayingAudio = false
    playbackProgress = 0
    playbackDuration = 0
    playbackTimer?.invalidate()
    playbackTimer = nil
  }

  private func formatPlaybackTime(_ seconds: Double) -> String {
    let totalSec = Int(max(0, seconds))
    let min = totalSec / 60
    let sec = totalSec % 60
    return String(format: "%d:%02d", min, sec)
  }

  // MARK: - TTS Audio Playback

  private func toggleTTSPlayback() {
    if isPlayingAudio {
      audioPlayer?.stop()
      audioPlayer = nil
      isPlayingAudio = false
      return
    }
    guard let bookmarkData = session.ttsAudioBookmark else { return }
    var isStale = false
    guard
      let url = try? URL(
        resolvingBookmarkData: bookmarkData,
        options: [],
        relativeTo: nil,
        bookmarkDataIsStale: &isStale
      ), !isStale,
      let player = try? AVAudioPlayer(contentsOf: url)
    else { return }

    player.prepareToPlay()
    let duration = player.duration
    audioPlayer = player
    isPlayingAudio = true
    player.play()

    let capturedPlayer = player
    DispatchQueue.main.asyncAfter(deadline: .now() + max(duration, 0) + 0.1) {
      guard self.audioPlayer === capturedPlayer else { return }
      self.isPlayingAudio = false
      self.audioPlayer = nil
    }
  }

  // MARK: - File Transcription Actions

  private func copyWithToggles() {
    if effectiveSource == .fileTranscription,
       let segments = session.aiCutSegments, !segments.isEmpty
    {
      let filtered = filteredSegments(segments)
      let translations = session.aiCutProcessedTranslations
      let hasSpeakers = filtered.contains { $0.speakerId != nil }
      let hasTranslations = (translations != nil && !translations!.isEmpty)
        || filtered.contains { $0.translation != nil }

      var lines: [String] = []
      for segment in filtered {
        var parts: [String] = []

        if showTimestamps {
          parts.append("[\(formatTimestamp(segment.startTime))]")
        }

        if showSpeaker, hasSpeakers, let speaker = segment.speakerId {
          parts.append(String(localized: "Speaker \(speaker + 1)", comment: "History: speaker label"))
        }

        if showOriginalText {
          parts.append(segment.text)
        }

        if showTranslation, hasTranslations {
          if let translation = translationText(for: segment, translations: translations),
             !translation.isEmpty
          {
            parts.append(translation)
          }
        }

        if !parts.isEmpty {
          lines.append(parts.joined(separator: " "))
        }
      }

      let text = lines.joined(separator: "\n")
      let pb = NSPasteboard.general
      pb.clearContents()
      pb.setString(text, forType: .string)
    } else if effectiveSource == .voiceDictation, session.lines.count > 1 {
      let text = session.formattedText(showSpeaker: showSpeaker, showTimestamp: showTimestamps)
      let pb = NSPasteboard.general
      pb.clearContents()
      pb.setString(text, forType: .string)
    } else {
      onCopy()
    }
  }

  private func retranscribeFile() {
    guard let bookmarkData = session.sourceURLBookmark else {
      historyErrorMessage = String(localized: "This session has no source file bookmark.", comment: "History: missing bookmark error")
      return
    }
    var isStale = false
    guard
      let url = try? URL(
        resolvingBookmarkData: bookmarkData,
        options: .withSecurityScope,
        relativeTo: nil,
        bookmarkDataIsStale: &isStale
      ), !isStale
    else {
      historyErrorMessage = String(localized: "The source file could not be accessed. It may have been moved or deleted.", comment: "History: stale bookmark error")
      return
    }

    guard url.startAccessingSecurityScopedResource() else {
      historyErrorMessage = String(localized: "Cannot access the source file. Permission denied.", comment: "History: permission error")
      return
    }

    isRetranscribing = true
    retranscribeProgress = 0

    AICutDetachedSessionWindowManager.shared.openSession(
      urls: [url],
      preloadedVideoStates: [:],
      config: config
    )

    url.stopAccessingSecurityScopedResource()
    isRetranscribing = false
  }

  private func revealSourceFileInFinder() {
    guard let bookmarkData = session.sourceURLBookmark else {
      historyErrorMessage = String(localized: "This session has no source file bookmark.", comment: "History: missing bookmark error")
      return
    }
    var isStale = false
    guard
      let url = try? URL(
        resolvingBookmarkData: bookmarkData,
        options: .withSecurityScope,
        relativeTo: nil,
        bookmarkDataIsStale: &isStale
      ), !isStale
    else {
      historyErrorMessage = String(localized: "The source file could not be found. It may have been moved or deleted.", comment: "History: file not found error")
      return
    }
    NSWorkspace.shared.activateFileViewerSelecting([url])
  }

  private func revealTTSAudioInFinder() {
    guard let bookmarkData = session.ttsAudioBookmark else { return }
    var isStale = false
    guard
      let url = try? URL(
        resolvingBookmarkData: bookmarkData,
        options: [],
        relativeTo: nil,
        bookmarkDataIsStale: &isStale
      ), !isStale
    else { return }
    NSWorkspace.shared.activateFileViewerSelecting([url])
  }

  private func revealDictationRecordingInFinder() {
    guard let url = session.recordingURL,
      FileManager.default.fileExists(atPath: url.path)
    else {
      historyErrorMessage = String(localized: "Recording file not found.", comment: "History: recording not found error")
      return
    }
    NSWorkspace.shared.activateFileViewerSelecting([url])
  }
}

// MARK: - Helpers

private func formattedSessionDuration(_ session: TranscriptSession) -> String? {
  guard let end = session.endTime else { return nil }
  let interval = max(0, end.timeIntervalSince(session.startTime))
  guard interval > 0 else { return nil }
  let formatter = DateComponentsFormatter()
  formatter.allowedUnits = interval >= 60 ? [.minute, .second] : [.second]
  formatter.unitsStyle = .abbreviated
  return formatter.string(from: interval)
}

// MARK: - FlexWrap layout modifier (wraps badges onto multiple lines)

private struct FlexWrapLayout: Layout {
  var spacing: CGFloat = 6

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let width = proposal.width ?? .infinity
    var height: CGFloat = 0
    var x: CGFloat = 0
    var rowHeight: CGFloat = 0

    for subview in subviews {
      let size = subview.sizeThatFits(.unspecified)
      if x + size.width > width && x > 0 {
        height += rowHeight + spacing
        x = 0
        rowHeight = 0
      }
      x += size.width + spacing
      rowHeight = max(rowHeight, size.height)
    }
    height += rowHeight
    return CGSize(width: width, height: height)
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    var x = bounds.minX
    var y = bounds.minY
    var rowHeight: CGFloat = 0

    for subview in subviews {
      let size = subview.sizeThatFits(.unspecified)
      if x + size.width > bounds.maxX && x > bounds.minX {
        y += rowHeight + spacing
        x = bounds.minX
        rowHeight = 0
      }
      subview.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
      x += size.width + spacing
      rowHeight = max(rowHeight, size.height)
    }
  }
}

extension View {
  fileprivate func flexWrap() -> some View {
    FlexWrapLayout { self }
  }
}


#Preview {
  HistoryView()
    .frame(width: 900, height: 600)
}
