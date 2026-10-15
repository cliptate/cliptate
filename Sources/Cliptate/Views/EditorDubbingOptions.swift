import CliptateCore
import SwiftUI
import UniformTypeIdentifiers

#if canImport(AppKit)
  import AppKit
#endif

struct EditorDubbingOptions: View {
  @EnvironmentObject private var config: AppConfiguration

  var body: some View {
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
                  .appInputSurface()
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
