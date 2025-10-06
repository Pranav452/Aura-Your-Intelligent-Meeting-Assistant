// AuthManager.swift

import Foundation
import SwiftUI
import Supabase

@MainActor
class AuthManager: ObservableObject {

    @Published var session: Session?
    private var authTask: Task<Void, Never>?

    init() {
        listenForAuthStateChanges()
    }
    
    deinit {
        authTask?.cancel()
    }

    func listenForAuthStateChanges() {
        authTask = Task {
            for await (event, session) in supabase.auth.authStateChanges {
                // DEBUG: This should print SIGNED_OUT when you sign out.
                print("Auth event: \(event), Session: \(session?.user.email ?? "nil")")
                self.session = session
            }
        }
    }

    func signInWithGoogle() async {
        do {
            try await supabase.auth.signInWithOAuth(
                provider: .google,
                redirectTo: URL(string: "io.supabase.aura://callback")!
            )
        } catch {
            print("Error signing in with Google: \(error)")
        }
    }

    func signInWithMicrosoft() async {
        do {
            try await supabase.auth.signInWithOAuth(
                provider: .azure,
                redirectTo: URL(string: "io.supabase.aura://callback")!
            )
        } catch {
            print("Error signing in with Microsoft: \(error)")
        }
    }
    
    // Make sure this function exists and is correct
    func signOut() async {
        // DEBUG: Make sure this prints
        print("AuthManager's signOut function called")
        do {
            try await supabase.auth.signOut()
        } catch {
            print("Error signing out: \(error)")
        }
    }
}
