// MeetingHistoryViewModel.swift

import Foundation
import Supabase

@MainActor
class MeetingHistoryViewModel: ObservableObject {
    @Published var meetings: [CompletedMeeting] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    func fetchMeetings() async {
        isLoading = true
        errorMessage = nil
        
        print("Fetching meetings from Supabase...")
        
        do {
            // This will now work because the Swift models match the database JSON
            let response: [CompletedMeeting] = try await supabase
                .from("meetings")
                .select()
                .order("created_at", ascending: false)
                .execute()
                .value
            
            self.meetings = response
            
            print("✅ Successfully fetched and decoded \(meetings.count) meetings.")
            
        } catch {
            print("❌ Error fetching meetings: \(error.localizedDescription)")
            // It's helpful to print the full decoding error if it happens
            if let decodingError = error as? DecodingError {
                print("Decoding Error Details: \(decodingError)")
            }
            self.errorMessage = "Failed to load meeting history. See Xcode console for details."
        }
        
        isLoading = false
    }
}
