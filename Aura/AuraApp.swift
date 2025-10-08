// AuraApp.swift

import SwiftUI
import Supabase

@main
struct AuraApp: App {
    // We only need the capture manager here as the single source of truth for recording state.
    @StateObject private var captureManager = CaptureManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(captureManager)
                .onOpenURL { url in
                    Task {
                        try? await supabase.auth.session(from: url)
                    }
                }
        }
    }
}
