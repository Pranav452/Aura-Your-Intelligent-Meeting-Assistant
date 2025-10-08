// MeetingModels.swift

import Foundation

struct CompletedMeeting: Codable, Identifiable, Hashable {
    let id: Int
    let createdAt: String
    let title: String
    let summary: String?
    let transcript: [Utterance]? // We will always decode into an array of Utterances
    let actionItems: [ActionItem]?

    enum CodingKeys: String, CodingKey {
        case id, title, summary, transcript
        case createdAt = "created_at"
        case actionItems = "action_items"
    }
    
    // Custom decoder to handle both dictionary and array for 'transcript'
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        createdAt = try container.decode(String.self, forKey: .createdAt)
        title = try container.decode(String.self, forKey: .title)
        summary = try container.decodeIfPresent(String.self, forKey: .summary)
        actionItems = try container.decodeIfPresent([ActionItem].self, forKey: .actionItems)
        
        // This is the robust logic for the transcript
        if let dict = try? container.decodeIfPresent(TranscriptData.self, forKey: .transcript) {
            // It's a dictionary like {"full_text": "..."}
            if let text = dict.fullText {
                transcript = [Utterance(speaker: "A", text: text)]
            } else {
                transcript = []
            }
        } else if let array = try? container.decodeIfPresent([Utterance].self, forKey: .transcript) {
            // It's already an array like [{"speaker": ..., "text": ...}]
            transcript = array
        } else {
            transcript = nil
        }
    }
}

// This struct is now just a helper for decoding the dictionary case
struct TranscriptData: Codable, Hashable {
    let fullText: String?
    enum CodingKeys: String, CodingKey {
        case fullText = "full_text"
    }
}

struct Utterance: Codable, Hashable, Identifiable {
    var id = UUID()
    let speaker: String?
    let text: String
    
    enum CodingKeys: String, CodingKey {
        case speaker, text
    }
}

struct ActionItem: Codable, Hashable, Identifiable {
    var id = UUID()
    let assignee: String?
    let task: String

    enum CodingKeys: String, CodingKey {
        case assignee, task
    }
}
