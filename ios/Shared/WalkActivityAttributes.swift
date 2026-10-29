import ActivityKit
import Foundation

struct WalkActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var distance: Double
        var paused: Bool
    }
    var start: Date
    var sessionID: String
}
