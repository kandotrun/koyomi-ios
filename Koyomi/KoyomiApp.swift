import SwiftUI

@main
@MainActor
struct KoyomiApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model: CalendarViewModel

    init() {
        let dependencies = AppDependencies.make()
        _model = StateObject(
            wrappedValue: CalendarViewModel(
                source: dependencies.source,
                pinStore: dependencies.pinStore,
                calendarSelectionStore: dependencies.calendarSelectionStore
            )
        )
    }

    var body: some Scene {
        WindowGroup {
            KoyomiRootView(model: model)
                .onOpenURL { model.open($0) }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        model.refresh()
                    }
                }
        }
    }
}
