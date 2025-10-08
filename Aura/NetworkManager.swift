// NetworkManager.swift

import Foundation

class NetworkManager {
    static let shared = NetworkManager()
    private let baseURL = "http://127.0.0.1:8000"

    // This function is required by CaptureManager to test the token
    func verifyUser(token: String) async -> Bool {
        guard let url = URL(string: "\(baseURL)/api/v1/me") else {
            print("Invalid URL for verifyUser")
            return false
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return false
            }
            return true
        } catch {
            print("Network request failed during verifyUser: \(error)")
            return false
        }
    }

    // This is the new function to fetch the meeting history
    func fetchMeetings(token: String) async throws -> [CompletedMeeting] {
        guard let url = URL(string: "\(baseURL)/api/v1/meetings") else {
            throw NSError(domain: "AuraNet", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            // It's helpful to print the server's response if it's not 200 OK
            let errorBody = String(data: data, encoding: .utf8) ?? "No response body"
            if let res = response as? HTTPURLResponse {
                print("Invalid server response: \(res.statusCode). Body: \(errorBody)")
            } else {
                print("Invalid server response. Body: \(errorBody)")
            }
            throw NSError(domain: "AuraNet", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid server response"])
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder -> Date in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)
            
            let formatters = [
                "yyyy-MM-dd'T'HH:mm:ss.SSSSSSZ",
                "yyyy-MM-dd'T'HH:mm:ssZ"
            ]
            
            for format in formatters {
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = format
                dateFormatter.locale = Locale(identifier: "en_US_POSIX")
                dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
                if let date = dateFormatter.date(from: dateString) {
                    return date
                }
            }
            
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode date string \(dateString)")
        }
        
        return try decoder.decode([CompletedMeeting].self, from: data)
    }
}
