// ContentView.swift

import SwiftUI
import Supabase

struct ContentView: View {
    @StateObject private var authManager = AuthManager()
    @EnvironmentObject var captureManager: CaptureManager // Get this from AuraApp

    var body: some View {
        if authManager.session == nil {
            LoginView()
                .environmentObject(authManager)
        } else {
            // MainTabView is the new top-level view for logged-in users
            MainTabView()
                .environmentObject(authManager)
                .environmentObject(captureManager)
        }
    }
}

struct MainTabView: View {
    var body: some View {
        TabView {
            MainView()
                .tabItem {
                    Label("Today", systemImage: "calendar")
                }
            
            MeetingHistoryView()
                .tabItem {
                    Label("History", systemImage: "clock.arrow.circlepath")
                }
        }
    }
}

struct LoginView: View {
    @EnvironmentObject var authManager: AuthManager
    var body: some View {
        VStack(spacing: 20) {
            Text("Welcome to Aura").font(.largeTitle).fontWeight(.bold)
            Text("Your intelligent meeting assistant.").font(.title3).foregroundStyle(.secondary)
            Spacer().frame(height: 40)
            Button { Task { await authManager.signInWithGoogle() } } label: {
                HStack { Image(systemName: "g.circle.fill"); Text("Sign in with Google").fontWeight(.medium) }
                .frame(maxWidth: .infinity)
            }.buttonStyle(.borderedProminent).controlSize(.large)
            Button { Task { await authManager.signInWithMicrosoft() } } label: {
                HStack { Image(systemName: "square.fill").foregroundStyle(Color.blue); Text("Sign in with Microsoft").fontWeight(.medium) }
                .frame(maxWidth: .infinity)
            }.buttonStyle(.bordered).controlSize(.large)
        }.padding(40).frame(width: 400, height: 300)
    }
}
