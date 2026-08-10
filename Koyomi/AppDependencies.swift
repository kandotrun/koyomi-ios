import Foundation

@MainActor
struct AppDependencies {
    let source: CalendarEventSource
    let pinStore: PinnedEventsStore
    let calendarSelectionStore: CalendarSelectionStore

    static func make() -> AppDependencies {
        if ProcessInfo.processInfo.arguments.contains("-ui-testing") {
            let suiteName = "run.kan.koyomi.ui-testing"
            let defaults = UserDefaults(suiteName: suiteName) ?? .standard
            defaults.removePersistentDomain(forName: suiteName)
            let source = DemoCalendarSource()
            let store = PinnedEventsStore(defaults: defaults)
            try? store.save([source.seededPin])
            return AppDependencies(
                source: source,
                pinStore: store,
                calendarSelectionStore: CalendarSelectionStore(defaults: defaults)
            )
        }

        return AppDependencies(
            source: EventKitCalendarSource(),
            pinStore: PinnedEventsStore(
                storage: KeychainPinnedEventsDataStorage(),
                migrationStorage: UserDefaultsPinnedEventsDataStorage(defaults: .standard)
            ),
            calendarSelectionStore: CalendarSelectionStore()
        )
    }
}
