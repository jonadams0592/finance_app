import SwiftUI
import TapeCore

@main
struct TapeApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .preferredColorScheme(.dark)
                .tint(Theme.text)
        }
        .onChange(of: scenePhase) { _, phase in
            model.scenePhaseChanged(phase)
        }
    }
}

@MainActor
struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            WatchlistView()
        }
        .sheet(isPresented: Binding(get: { model.showSettings }, set: { model.showSettings = $0 })) {
            SettingsView()
                .presentationDetents([.large])
        }
        .sheet(isPresented: Binding(get: { model.showStatusInfo }, set: { model.showStatusInfo = $0 })) {
            StatusInfoView()
                .presentationDetents([.medium, .large])
        }
        .onAppear { model.boot() }
    }
}
