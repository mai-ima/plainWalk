import Foundation
import ActivityKit

@MainActor final class LiveActivityService {
    private struct Snapshot: Equatable {
        var id: String
        var start: Double
        var distance: Double
        var paused: Bool
    }
    private var activity: Activity<WalkActivityAttributes>?
    private var lastSubmitted: Snapshot?
    private var lastUpdate: Date = .distantPast
    private var pendingTask: Task<Void, Never>?
    private(set) var lastError: String?

    func update(_ session: NativeSession?) {
        // Keep only scalars: queued activity updates must not retain entire route arrays.
        let snapshot = session.map { Snapshot(id: $0.id, start: $0.start, distance: $0.distance, paused: !$0.recording) }
        if let snapshot, let previous = lastSubmitted,
           snapshot.id == previous.id, snapshot.paused == previous.paused {
            if snapshot == previous || Date().timeIntervalSince(lastUpdate) < 5 { return }
        }
        lastSubmitted = snapshot
        lastUpdate = Date()
        // Pauses, resumes, ends and new sessions arrive in the same order as recording changes.
        let preceding = pendingTask
        pendingTask = Task { [weak self] in
            await preceding?.value
            guard let self else { return }
            await self.apply(snapshot)
        }
    }

    private func apply(_ snapshot: Snapshot?) async {
        let existing = Activity<WalkActivityAttributes>.activities
        guard let snapshot else {
            // Permission may have been revoked; ending old activities still needs to run.
            for old in existing { await old.end(nil, dismissalPolicy: .immediate) }
            activity = nil
            return
        }
        for old in existing where old.attributes.sessionID != snapshot.id {
            await old.end(nil, dismissalPolicy: .immediate)
        }
        activity = existing.first { $0.attributes.sessionID == snapshot.id }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let state = WalkActivityAttributes.ContentState(distance: snapshot.distance, paused: snapshot.paused)
        let content = ActivityContent(state: state, staleDate: nil)
        if let current = activity {
            await current.update(content)
            lastError = nil
        } else if !snapshot.paused {
            // Restoring a paused journal must not create a fresh Lock Screen activity.
            let attributes = WalkActivityAttributes(start: Date(timeIntervalSince1970: snapshot.start / 1000), sessionID: snapshot.id)
            do {
                activity = try Activity.request(attributes: attributes, content: content, pushType: nil)
                lastError = nil
            } catch { lastError = error.localizedDescription }
        }
    }
}
