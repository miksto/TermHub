import Foundation
import Observation

@Observable
@MainActor
final class SessionDisplayState {
    var title: String

    init(title: String) {
        self.title = title
    }
}
