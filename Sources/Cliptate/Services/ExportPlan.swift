import Foundation

struct ExportPlan: Equatable, Sendable {
  enum Phase: String, CaseIterable, Sendable {
    case fcpxml
    case subtitle
    case video
    case audio
  }

  let urls: [URL]
  let phases: [Phase]
  let request: ExportAllRequest

  static func aiCut(request: ExportAllRequest, urls: [URL]) -> ExportPlan {
    var phases: [Phase] = []
    if request.includeFCPXML { phases.append(.fcpxml) }
    if request.includeSubtitleFiles { phases.append(.subtitle) }
    if request.includeVideos { phases.append(.video) }
    if request.includeAudio { phases.append(.audio) }
    return ExportPlan(urls: urls, phases: phases, request: request)
  }

  func includes(_ phase: Phase) -> Bool {
    phases.contains(phase)
  }
}
