// NetworkManager.swift

import Foundation

enum NetworkError: Error {
    case invalidURL
    case requestFailed(Error)
    case invalidResponse
    case unauthorized
}

class NetworkManager {
    // We use a singleton so there's only one instance of this manager in the app.
    static let shared = NetworkManager()
    
    // Set the base URL for your local backend server.
    private let baseURL = "http://127.0.0.1:8000"

    // This is our test function to verify we can talk to the backend.
    func verifyUser(token: String) async -> Bool {
        guard let url = URL(string: "\(baseURL)/api/v1/me") else {
            print("Invalid URL")
            return false
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        // Add the JWT to the Authorization header.
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                print("Invalid response from server.")
                return false
            }
            
            // We successfully received data from the secure endpoint.
            print("Successfully verified user with backend: \(String(data: data, encoding: .utf8) ?? "")")
            return true
            
        } catch {
            print("Network request failed: \(error)")
            return false
        }
    }
}
