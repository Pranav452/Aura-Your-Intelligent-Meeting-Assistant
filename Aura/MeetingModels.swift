// MeetingModels.swift

import Foundation

struct CompletedMeeting: Codable, Identifiable {
    let id: Int
    let createdAt: Date
    let title: String
    let summary: String?
    let transcript: [Utterance]?
    let actionItems: [ActionItem]?

    // We need to tell Swift how to map the snake_case names from the database
    // to our camelCase property names.
    enum CodingKeys: String, CodingKey {
        case id
        case createdAt = "created_at"
        case title
        case summary
        case transcript
        case actionItems = "action_items"
    }
}

struct Utterance: Codable, Hashable {
    let speaker: String?
    let text: String
}

struct ActionItem: Codable, Hashable, Identifiable {
    // We add a unique ID here so we can use it in SwiftUI Lists.
    var id = UUID()
    let assignee: String?
    let task: String

    enum CodingKeys: String, CodingKey {
        case assignee
        case task
    }
}
```*(Self-correction: I've added a UUID to `ActionItem` to make it `Identifiable`, which is a best practice for SwiftUI lists.)*

#### **2. Add a `SELECT` Policy in Supabase**

Your `meetings` table is currently protected. No one can read from it. We need to add a Row-Level Security (RLS) policy that says: **"A user can only see their own meetings."**

1.  Go to your Supabase dashboard.
2.  Navigate to **Authentication > Policies**.
3.  Find the `meetings` table and click **"New policy"**.
4.  Select the template **"Enable read access to everyone"**.
5.  **Change the Policy Name** to `Allow individual read access`.
6.  **IMPORTANT:** In the `USING expression` box, change `true` to the following condition:
    ```sql
    auth.uid() = user_id
    ```
7.  Click **"Review"** and **"Save policy"**.

#### **3. Create the `MeetingHistoryViewModel`**

This new class will be responsible for fetching the list of completed meetings from the database.

1.  Create a new **Swift File** named `MeetingHistoryViewModel.swift`.
2.  Paste the following code into it.

```swift
// MeetingHistoryViewModel.swift

import Foundation

@MainActor
class MeetingHistoryViewModel: ObservableObject {
    @Published var meetings: [CompletedMeeting] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    func fetchMeetings() async {
        isLoading = true
        errorMessage = nil
        
        do {
            let meetings: [CompletedMeeting] = try await supabase
                .from("meetings")
                .select()
                // Order by most recent first
                .order("created_at", ascending: false)
                .execute()
                .value
            
            self.meetings = meetings
            print("Successfully fetched \(meetings.count) completed meetings.")
        } catch {
            print("❌ Error fetching meetings: \(error.localizedDescription)")
            self.errorMessage = "Failed to load meeting history."
        }
        
        isLoading = false
    }
}
