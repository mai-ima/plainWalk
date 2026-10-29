import Foundation
import ActivityKit

@MainActor final class LiveActivityService {
    private var activity: Activity<WalkActivityAttributes>?
    private var lastUpdate: Date = .distantPast
    func update(_ session: NativeSession?) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        if activity == nil { activity = Activity<WalkActivityAttributes>.activities.first }
        guard let session else {
            if let old = activity { Task { await old.end(nil, dismissalPolicy: .immediate) } }
            activity = nil; return
        }
        let state = WalkActivityAttributes.ContentState(distance: session.distance, paused: !session.recording)
        if let current = activity, current.attributes.sessionID != session.id {
            Task { await current.end(nil, dismissalPolicy: .immediate) }; activity = nil
        }
        if activity == nil {
            let attributes = WalkActivityAttributes(start: Date(timeIntervalSince1970: session.start / 1000), sessionID: session.id)
            activity = try? Activity.request(attributes: attributes, content: ActivityContent(state: state, staleDate: nil), pushType: nil)
            lastUpdate = Date()
        } else if Date().timeIntervalSince(lastUpdate) >= 5 || !session.recording {
            if let current = activity { Task { await current.update(ActivityContent(state: state, staleDate: nil)) } }; lastUpdate = Date()
        }
    }
}
