import SwiftUI
import RosieCore

@main
struct RosieGassiApp: App {
    @State private var runtime: RosieRuntime?
    @State private var loadingError: String?

    init() {
        // Ein einziger Ausführungspfad für Live-Activity-Intents. Fehlt der Handler,
        // bleibt ein Intent wirkungslos statt ungeprüft zu schreiben.
        WalkActivityIntentHandler.perform = { request in
            guard let runtime = try? RosieRuntime.shared() else { return }
            await runtime.liveActivity.perform(request)
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if let runtime {
                    RootView(store: runtime.store)
                        .environment(runtime.gps)
                        .environment(runtime.weather)
                } else if let loadingError {
                    ContentUnavailableView {
                        Label("Tagebuch nicht geöffnet", systemImage: "externaldrive.badge.exclamationmark")
                    } description: {
                        Text(loadingError + "\nDeine Daten wurden nicht gelöscht. Bitte die App nicht deinstallieren.")
                    } actions: {
                        Button("Erneut versuchen", action: loadStore)
                    }
                } else {
                    ProgressView("Tagebuch öffnen …")
                }
            }
            .tint(Color("AccentColor"))
            #if DEBUG
            .preferredColorScheme(uiTestColorScheme)
            #endif
            .task { if runtime == nil && loadingError == nil { loadStore() } }
        }
    }

    #if DEBUG
    private var uiTestColorScheme: ColorScheme? {
        let args = ProcessInfo.processInfo.arguments
        guard let storeIndex = args.firstIndex(of: "--uitest-store"),
              args.indices.contains(storeIndex + 1),
              UUID(uuidString: args[storeIndex + 1]) != nil,
              let appearanceIndex = args.firstIndex(of: "--uitest-appearance"),
              args.indices.contains(appearanceIndex + 1) else { return nil }
        switch args[appearanceIndex + 1] {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }
    #endif

    private func loadStore() {
        do {
            runtime = try RosieRuntime.shared()
            loadingError = nil
        } catch {
            loadingError = error.localizedDescription
        }
    }
}
