import CliptateCore
import Foundation

enum ModelPreparationError: LocalizedError, Equatable {
    case modelNotDownloaded(ModelVariant)

    var errorDescription: String? {
        switch self {
        case .modelNotDownloaded(let model):
            return
                "\(model.displayName) is not downloaded. Download it from the Models page before using it."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .modelNotDownloaded:
            return "Open the Models tab and download the model manually, then retry the operation."
        }
    }
}
