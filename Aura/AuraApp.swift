// AuraApp.swift

import SwiftUI
import Supabase

@main
struct AuraApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    // This is the crucial part:
                    // When the app is opened by the callback URL,
                    // we pass it to the Supabase client to finish authentication.
                    Task {
                        do {
                            try await supabase.auth.session(from: url)
                        } catch {
                            print("Error handling redirect URL: \(error)")
                        }
                    }
                }
        }
    }
}
