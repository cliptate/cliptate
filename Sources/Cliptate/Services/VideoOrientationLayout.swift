import CoreGraphics

struct VideoOrientationLayout {
  struct Result {
    let originalSize: CGSize
    let canvasSize: CGSize
    let scaledVideoSize: CGSize
    let scale: CGFloat
    let offset: CGPoint
    let aspectRatio: CGFloat
  }

  private static let defaultLandscapeAspect: CGFloat = 16.0 / 9.0
  private static let defaultPortraitAspect: CGFloat = 9.0 / 16.0
  private static let epsilon: CGFloat = 0.0001

  static func layout(
    for videoSize: CGSize,
    targetOrientation: SubtitleOrientation
  ) -> Result {
    let sanitizedSize = sanitize(size: videoSize)
    let videoAspect = aspectRatio(for: sanitizedSize)
    let actualOrientation = orientation(for: sanitizedSize)

    let canonicalAspect: CGFloat
    if actualOrientation == targetOrientation {
      if videoAspect.isFinite, videoAspect > 0 {
        canonicalAspect = videoAspect
      } else {
        canonicalAspect =
          targetOrientation == .landscape
          ? defaultLandscapeAspect : defaultPortraitAspect
      }
    } else {
      canonicalAspect =
        targetOrientation == .landscape
        ? defaultLandscapeAspect : defaultPortraitAspect
    }

    let canvasSize = makeCanvasSize(
      for: sanitizedSize,
      canvasAspect: canonicalAspect,
      targetOrientation: targetOrientation
    )
    let scale = resolveScale(for: sanitizedSize, canvasSize: canvasSize)
    let scaledVideoSize = CGSize(
      width: sanitizedSize.width * scale, height: sanitizedSize.height * scale)
    let offset = CGPoint(
      x: (canvasSize.width - scaledVideoSize.width) / 2,
      y: (canvasSize.height - scaledVideoSize.height) / 2
    )

    return .init(
      originalSize: sanitizedSize,
      canvasSize: canvasSize,
      scaledVideoSize: scaledVideoSize,
      scale: scale,
      offset: offset,
      aspectRatio: aspectRatio(for: canvasSize)
    )
  }

  static func letterboxTransform(
    baseTransform: CGAffineTransform,
    naturalSize: CGSize,
    displaySize: CGSize,
    targetOrientation: SubtitleOrientation
  ) -> (transform: CGAffineTransform, canvasSize: CGSize) {
    let layoutResult = layout(for: displaySize, targetOrientation: targetOrientation)
    let scaleTransform = CGAffineTransform(scaleX: layoutResult.scale, y: layoutResult.scale)
    let scaledBaseTransform = baseTransform.concatenating(scaleTransform)

    let sanitizedNaturalSize = sanitize(size: naturalSize)
    let naturalRect = CGRect(origin: .zero, size: sanitizedNaturalSize)
    let transformedRect = naturalRect.applying(scaledBaseTransform)

    let desiredCenter = CGPoint(
      x: layoutResult.canvasSize.width / 2,
      y: layoutResult.canvasSize.height / 2
    )
    let transformedCenter = CGPoint(x: transformedRect.midX, y: transformedRect.midY)
    let translationAdjustment = CGAffineTransform(
      translationX: desiredCenter.x - transformedCenter.x,
      y: desiredCenter.y - transformedCenter.y
    )

    let finalTransform = scaledBaseTransform.concatenating(translationAdjustment)
    return (finalTransform, layoutResult.canvasSize)
  }

  private static func sanitize(size: CGSize) -> CGSize {
    let width = max(size.width, 1)
    let height = max(size.height, 1)
    return CGSize(width: width, height: height)
  }

  private static func aspectRatio(for size: CGSize) -> CGFloat {
    guard size.width > epsilon, size.height > epsilon else { return 1 }
    return size.width / size.height
  }

  private static func orientation(for size: CGSize) -> SubtitleOrientation {
    size.height >= size.width ? .portrait : .landscape
  }

  private static func makeCanvasSize(
    for videoSize: CGSize,
    canvasAspect: CGFloat,
    targetOrientation: SubtitleOrientation
  ) -> CGSize {
    guard canvasAspect.isFinite, canvasAspect > epsilon else {
      return defaultSize(for: targetOrientation, reference: videoSize)
    }
    let maxDimension = max(videoSize.width, videoSize.height)

    switch targetOrientation {
    case .landscape:
      let width = max(maxDimension, videoSize.width)
      let height = width / canvasAspect
      return CGSize(width: width, height: height)
    case .portrait:
      let height = max(maxDimension, videoSize.height)
      let width = height * canvasAspect
      return CGSize(width: width, height: height)
    }
  }

  private static func defaultSize(for orientation: SubtitleOrientation, reference: CGSize) -> CGSize
  {
    let maxDimension = max(reference.width, reference.height)
    switch orientation {
    case .landscape:
      let width = max(maxDimension, 1920)
      return CGSize(width: width, height: width / defaultLandscapeAspect)
    case .portrait:
      let height = max(maxDimension, 1920)
      return CGSize(width: height * defaultPortraitAspect, height: height)
    }
  }

  private static func resolveScale(for videoSize: CGSize, canvasSize: CGSize) -> CGFloat {
    let scaleX = canvasSize.width / videoSize.width
    let scaleY = canvasSize.height / videoSize.height
    return min(scaleX, scaleY)
  }
}
