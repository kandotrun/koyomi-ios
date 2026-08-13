@preconcurrency import ActivityKit
import Foundation

private enum PinnedLiveActivityManagerError: Error {
    case payloadTooLarge
}

@MainActor
protocol PinnedLiveActivitySynchronizing: AnyObject {
    func synchronize(_ events: [PinnedEvent], at referenceDate: Date)
}

@MainActor
final class NoopPinnedLiveActivitySynchronizer: PinnedLiveActivitySynchronizing {
    func synchronize(_ events: [PinnedEvent], at referenceDate: Date) {}
}

@MainActor
final class PinnedLiveActivityManager: PinnedLiveActivitySynchronizing {
    static let shared = PinnedLiveActivityManager()

    private var synchronizationTask: Task<Void, Never>?

    private init() {}

    func synchronize(_ events: [PinnedEvent], at referenceDate: Date) {
        let plans = PinnedLiveActivityPolicy.plans(from: events, at: referenceDate)
        let previousTask = synchronizationTask
        previousTask?.cancel()
        synchronizationTask = Task { [weak self] in
            await previousTask?.value
            guard !Task.isCancelled else { return }
            await self?.reconcile(plans, at: referenceDate)
        }
    }

    private func reconcile(_ plans: [PinnedLiveActivityPlan], at referenceDate: Date) async {
        let desiredByKey = Dictionary(
            uniqueKeysWithValues: plans.map { plan in
                (
                    ActivityKey(eventID: plan.event.id, startDate: plan.event.startDate),
                    plan
                )
            }
        )
        let priorityByKey = Dictionary(
            uniqueKeysWithValues: plans.enumerated().map { index, plan in
                (
                    ActivityKey(eventID: plan.event.id, startDate: plan.event.startDate),
                    index
                )
            }
        )
        let existing = Activity<PinnedEventActivityAttributes>.activities.sorted { $0.id < $1.id }
        var retainedActivities: [
            ActivityKey: Activity<PinnedEventActivityAttributes>
        ] = [:]

        for activity in existing {
            guard !Task.isCancelled else { return }
            let attributes = activity.attributes
            let key = ActivityKey(
                eventID: attributes.eventID,
                startDate: attributes.scheduledStartDate
            )
            let plan = desiredByKey[key]
            let state = activity.activityState
            let canRetain = (state == .active || state == .pending)
                && plan != nil
                && retainedActivities[key] == nil

            if canRetain, let plan {
                retainedActivities[key] = activity
                await activity.update(activityContent(for: plan.event, at: referenceDate))
            } else if state != .dismissed {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }

        guard !Task.isCancelled, ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        for (candidatePriority, plan) in plans.enumerated() {
            guard !Task.isCancelled else { return }
            let key = ActivityKey(eventID: plan.event.id, startDate: plan.event.startDate)
            guard retainedActivities[key] == nil else { continue }

            do {
                retainedActivities[key] = try requestActivity(for: plan, at: referenceDate)
            } catch let error as ActivityAuthorizationError {
                guard isMaximumExceeded(error) else { continue }
                guard
                    let replacementKey = lowestPriorityKey(
                        in: retainedActivities,
                        priorityByKey: priorityByKey
                    ),
                    let replacementPriority = priorityByKey[replacementKey],
                    replacementPriority > candidatePriority,
                    let replacement = retainedActivities.removeValue(forKey: replacementKey)
                else {
                    return
                }

                await replacement.end(nil, dismissalPolicy: .immediate)
                do {
                    retainedActivities[key] = try requestActivity(for: plan, at: referenceDate)
                } catch let retryError as ActivityAuthorizationError {
                    if isMaximumExceeded(retryError) { return }
                } catch {
                    continue
                }
            } catch {
                continue
            }
        }
    }

    private func requestActivity(
        for plan: PinnedLiveActivityPlan,
        at referenceDate: Date
    ) throws -> Activity<PinnedEventActivityAttributes> {
        let attributes = PinnedEventActivityAttributes(
            eventID: plan.event.id,
            scheduledStartDate: plan.event.startDate
        )
        let content = activityContent(for: plan.event, at: referenceDate)
        guard payloadSize(attributes: attributes, state: content.state) <= 3_500 else {
            throw PinnedLiveActivityManagerError.payloadTooLarge
        }

        if plan.startsImmediately {
            return try Activity.request(
                attributes: attributes,
                content: content,
                pushType: nil,
                style: .standard
            )
        } else {
            let alert = AlertConfiguration(
                title: "ピン留め予定まで12時間",
                body: "カウントダウンをLive Activityに表示します。",
                sound: .named("KoyomiLiveActivitySilent.caf")
            )
            return try Activity.request(
                attributes: attributes,
                content: content,
                pushType: nil,
                style: .standard,
                alertConfiguration: alert,
                start: plan.activationDate
            )
        }
    }

    private func payloadSize(
        attributes: PinnedEventActivityAttributes,
        state: PinnedEventActivityAttributes.ContentState
    ) -> Int {
        let encoder = JSONEncoder()
        guard let encodedAttributes = try? encoder.encode(attributes),
              let encodedState = try? encoder.encode(state) else {
            return .max
        }
        return encodedAttributes.count + encodedState.count
    }

    private func isMaximumExceeded(_ error: ActivityAuthorizationError) -> Bool {
        switch error {
        case .globalMaximumExceeded, .targetMaximumExceeded:
            return true
        default:
            return false
        }
    }

    private func lowestPriorityKey(
        in activities: [ActivityKey: Activity<PinnedEventActivityAttributes>],
        priorityByKey: [ActivityKey: Int]
    ) -> ActivityKey? {
        activities.keys.max { lhs, rhs in
            (priorityByKey[lhs] ?? .max) < (priorityByKey[rhs] ?? .max)
        }
    }

    private func activityContent(
        for event: PinnedEvent,
        at referenceDate: Date
    ) -> ActivityContent<PinnedEventActivityAttributes.ContentState> {
        let state = PinnedEventActivityAttributes.ContentState(
            title: PinnedLiveActivityPolicy.displayTitle(for: event),
            calendarName: PinnedLiveActivityPolicy.calendarName(for: event),
            calendarColorHex: event.calendarColorHex,
            startDate: event.startDate,
            isAllDay: event.isAllDay,
            isEstimatedDateWindow: event.isEstimatedDateWindow
        )
        let remaining = max(event.startDate.timeIntervalSince(referenceDate), 0)
        let relevanceScore = max(
            0,
            min(1, 1 - remaining / PinnedLiveActivityPolicy.countdownWindow)
        )
        return ActivityContent(
            state: state,
            staleDate: event.startDate,
            relevanceScore: relevanceScore
        )
    }

    private struct ActivityKey: Hashable {
        let eventID: String
        let startDate: Date
    }
}
