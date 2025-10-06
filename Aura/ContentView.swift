// ContentView.swift

import SwiftUI
import Supabase

struct ContentView: View {
    // Create an instance of our AuthManager to observe.
    @StateObject private var authManager = AuthManager()
    
    var body: some View {
        if authManager.session == nil {
            LoginView()
                .environmentObject(authManager)
        } else {
            // Show the MainView when logged in
            MainView()
                .environmentObject(authManager)
        }
    }
}

struct LoginView: View {
    // Grab the AuthManager from the environment.
    @EnvironmentObject var authManager: AuthManager

    var body: some View {
        VStack(spacing: 20) {
            Text("Welcome to Aura")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Your intelligent meeting assistant.")
                .font(.title3)
                .foregroundStyle(.secondary)

            Spacer()
                .frame(height: 40)

            // Sign in with Google Button
            Button {
                // Use a Task to call our async sign-in function.
                Task {
                    await authManager.signInWithGoogle()
                }
            } label: {
                HStack {
                    Image(systemName: "g.circle.fill")
                    Text("Sign in with Google")
                        .fontWeight(.medium)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            // Sign in with Microsoft Button
            Button {
                Task {
                    await authManager.signInWithMicrosoft()
                }
            } label: {
                HStack {
                    Image(systemName: "square.fill")
                        .foregroundStyle(Color(red: 0.94, green: 0.35, blue: 0.15)) // A more Microsoft-like color
                    Text("Sign in with Microsoft")
                        .fontWeight(.medium)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
        .padding(40)
        .frame(width: 400, height: 300)
    }
}

#Preview {
    ContentView()
}
