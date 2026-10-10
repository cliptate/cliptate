import Combine
import CoreGraphics
import Foundation

/// 播放控制命令
enum PlaybackCommand {
  case seek(TimeInterval)
  case play
  case pause
  case seekAndPlay(TimeInterval)
}

/// 协调播放器跳转 / 外部控制的对象
final class VideoPlaybackCoordinator: ObservableObject {
  // Published 状态用于 UI 显示
  @Published var currentTime: TimeInterval = 0
  @Published var duration: TimeInterval = 0
  @Published var isPlaying: Bool = false
  @Published var isCompressedTimeline: Bool = false
  @Published var waveformSnapshot: WaveformSnapshot?
  @Published var waveformState: WaveformLoadingState = .idle

  private var waveformTask: Task<Void, Never>?
  private var lastWaveformRequest: WaveformRequest?

  // Combine Subject 用于即时命令传递
  let commandSubject = PassthroughSubject<PlaybackCommand, Never>()

  // MARK: - Waveform

  @MainActor
  func requestWaveform(
    for url: URL,
    targetPointCount: Int,
    mixToMono: Bool,
    force: Bool = false
  ) {
    let request = WaveformRequest(
      url: url.standardizedFileURL, targetPointCount: targetPointCount, mixToMono: mixToMono)
    if !force,
      let last = lastWaveformRequest,
      last == request,
      waveformSnapshot != nil
    {
      return
    }

    waveformTask?.cancel()
    waveformState = .loading
    lastWaveformRequest = request

    waveformTask = Task(priority: .utility) { [weak self] in
      do {
        let snapshot = try await WaveformRepository.shared.loadWaveform(
          for: request.url,
          targetPointCount: request.targetPointCount,
          mixToMono: request.mixToMono
        )
        guard let coordinator = self else { return }
        await MainActor.run {
          guard coordinator.lastWaveformRequest == request else { return }
          coordinator.waveformSnapshot = snapshot
          coordinator.waveformState = .ready
        }
      } catch {
        guard let coordinator = self else { return }
        await MainActor.run {
          guard coordinator.lastWaveformRequest == request else { return }
          coordinator.waveformSnapshot = nil
          coordinator.waveformState = .failed(error.localizedDescription)
        }
      }
    }
  }

  @MainActor
  func cancelWaveformLoad() {
    waveformTask?.cancel()
    waveformTask = nil
  }

  // MARK: - Public API

  func seek(to time: TimeInterval) {
    commandSubject.send(.seek(time))
  }

  func play() {
    commandSubject.send(.play)
  }

  func pause() {
    commandSubject.send(.pause)
  }

  func seekAndPlay(to time: TimeInterval) {
    commandSubject.send(.seekAndPlay(time))
  }

  // MARK: - Internal Updates

  func _updateTime(_ t: TimeInterval) {
    // Throttle: only publish when change exceeds 100ms to reduce SwiftUI re-renders
    guard abs(t - currentTime) > 0.1 else { return }
    currentTime = t
  }

  func _updateDuration(_ d: TimeInterval) {
    duration = d
  }

  func _updatePlaying(_ playing: Bool) {
    if isPlaying != playing {
      isPlaying = playing
    }
  }

  func _updateCompressedTimeline(_ compressed: Bool) {
    if isCompressedTimeline != compressed {
      isCompressedTimeline = compressed
    }
  }

  func reset() {
    currentTime = 0
    duration = 0
    isPlaying = false
    isCompressedTimeline = false
    waveformTask?.cancel()
    waveformTask = nil
    waveformSnapshot = nil
    waveformState = .idle
    lastWaveformRequest = nil
  }
}

enum WaveformLoadingState: Equatable {
  case idle
  case loading
  case ready
  case failed(String)
}

private struct WaveformRequest: Equatable {
  let url: URL
  let targetPointCount: Int
  let mixToMono: Bool
}
