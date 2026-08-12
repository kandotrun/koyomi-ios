import Foundation

@MainActor
struct AppDependencies {
    let source: CalendarEventSource
    let pinStore: PinnedEventsStore
    let legacyPinStore: PinnedEventsStore?
    let calendarSelectionStore: CalendarSelectionStore

    static func make() -> AppDependencies {
        if ProcessInfo.processInfo.arguments.contains("-ui-testing") {
            let suiteName = "run.kan.koyomi.ui-testing"
            let defaults = UserDefaults(suiteName: suiteName) ?? .standard
            defaults.removePersistentDomain(forName: suiteName)
            let source = DemoCalendarSource(
                shouldFailMutations: ProcessInfo.processInfo.arguments.contains(
                    "-ui-testing-fail-mutations"
                ),
                hasReadOnlyPinnedEvent: ProcessInfo.processInfo.arguments.contains(
                    "-ui-testing-read-only-pin"
                ),
                hasRecurringPinnedEvent: ProcessInfo.processInfo.arguments.contains(
                    "-ui-testing-recurring-pin"
                )
            )
            let store = PinnedEventsStore(defaults: defaults)
            try? store.save([source.seededPin])
            return AppDependencies(
                source: source,
                pinStore: store,
                legacyPinStore: nil,
                calendarSelectionStore: CalendarSelectionStore(defaults: defaults)
            )
        }

        return AppDependencies(
            source: EventKitCalendarSource(),
            pinStore: PinnedEventsStore(storage: KeychainPinnedEventsDataStorage()),
            legacyPinStore: PinnedEventsStore(
                storage: KeychainPinnedEventsDataStorage(
                    account: KoyomiSharedStorage.legacyPinnedEventsKey
                ),
                migrationStorage: UserDefaultsPinnedEventsDataStorage(
                    defaults: .standard,
                    key: KoyomiSharedStorage.legacyPinnedEventsKey
                )
            ),
            calendarSelectionStore: CalendarSelectionStore()
        )
    }
}
