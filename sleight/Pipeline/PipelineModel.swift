import Foundation
import SwiftUI

/// UI-facing handle to the shared PipelineModel (kept separate so the UI layer
/// never imports the capture-queue side of the pipeline).
@MainActor
final class PipelineViewModel: ObservableObject {
    let model: PipelineModel

    init(model: PipelineModel) {
        self.model = model
    }
}