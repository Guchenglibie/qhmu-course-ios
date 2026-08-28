import SwiftUI

@main
struct QHMUCourseApp: App {
    @StateObject private var store = ScheduleStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .task {
                    await store.bootstrap()
                }
        }
    }
}
