import SwiftUI

struct LoginPayload: Codable {
    var username: String
    var password: String
}

struct LoginSuccess: Codable {
    var expiry: Date
    var token: String
}

struct ErrorResponse: Codable {
    var detail: String
}

enum CallErrorType {
    case unknown
    case notLoggedIn
    case unexpectedRequest
    case unexpectedResponse
    case badRequest
    case unauthorized
    case serverError
}

struct CallError {
    var type: CallErrorType
    var detail: String
}

enum DateError: String, Error {
    case invalidDate
}

struct EmptyPayload: Codable {}

class ApiManager {
    let host = "https://dionysus.seim.io"
    
    func loggedIn() -> Bool {
        guard let token = token() else {
            return false
        }
        return token.count > 0
    }
    
    func token() -> String? {
        return  KeychainHelper.standard.read(service: "dionysus", account: "auth-token", type: String.self)
    }
    
    func getURLSession() -> URLSession {
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.httpAdditionalHeaders = [
            "Accept": "application/json",
            "Content-Type": "application/json",
        ]
        if loggedIn() {
            sessionConfig.httpAdditionalHeaders!["Authorization"] = "Token \(token()!)"
        }
        return URLSession(configuration: sessionConfig)
    }
    
    func getResponseData<T: Decodable>(_ type: T.Type, from: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom({ (decoder) -> Date in
            let container = try decoder.singleValueContainer()
            let dateStr = try container.decode(String.self)
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX"
            if let date = formatter.date(from: dateStr) {
                return date
            }
            throw DateError.invalidDate
        })
        return try decoder.decode(type, from: from)
    }
    
    func formatError(response: HTTPURLResponse, data: Data) -> CallError {
        print("error statusCode \(response.statusCode):", String(data: data, encoding: .utf8) ?? "")
        let decodedError: ErrorResponse
        do {
            decodedError = try self.getResponseData(ErrorResponse.self, from: data)
        } catch let error {
            print("error decoding error response \(error)")
            return CallError(type: .unexpectedResponse, detail: "error decoding error response")
        }
        
        let errorType: CallErrorType
        switch response.statusCode {
        case 400:
            errorType = .badRequest
        case 401:
            errorType = .unauthorized
        case 500:
            errorType = .serverError
        default:
            errorType = .unknown
        }
        return CallError(type: errorType, detail: decodedError.detail)
    }
    
    func getData<T: Decodable>(urlString: String, ensureTokenSet: Bool = true, success: @escaping ((T) -> Void), fail: @escaping ((CallError) -> Void)) {
        guard let url = URL(string: "\(host)\(urlString)") else {
            print("error URL: \(urlString)")
            return
        }
        
        if ensureTokenSet && !loggedIn() {
            fail(CallError(type: .notLoggedIn, detail: "not logged in when required for call"))
            return
        }
        
        let session = getURLSession()
        session.dataTask(with: url) { data, response, error in
            guard let httpResponse = response as? HTTPURLResponse else {
                print("could not format HttpResponse")
                fail(CallError(type: .unexpectedResponse, detail: "could not format HttpResponse"))
                return
            }
            
            guard let data = data else {
                fail(CallError(type: .unexpectedResponse, detail: "no data returned from server"))
                return
            }
            if httpResponse.statusCode != 200 {
                fail(self.formatError(response: httpResponse, data: data))
                return
            }
            
            do {
                let decodedData = try self.getResponseData(T.self, from: data)
                DispatchQueue.main.async {
                    success(decodedData)
                }
            } catch let error {
                print(error)
                fail(CallError(type: .unexpectedResponse, detail: "error decoding successful response"))
            }
        }.resume()
    }
    
    func createPostRequest<T: Encodable>(url: URL, data: T) -> URLRequest? {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        do {
            let encoder = JSONEncoder()
            encoder.keyEncodingStrategy = .convertToSnakeCase
            request.httpBody = try encoder.encode(data)
        } catch let error {
            print("error json serialize:", error)
            return nil
        }
        return request
    }
    
    func postData<T: Decodable, Y: Encodable>(urlString: String, data: Y, ensureTokenSet: Bool = true, success: @escaping ((T) -> Void), fail: @escaping ((CallError) -> Void)) {
        guard let url = URL(string: "\(host)\(urlString)") else {
            print("error URL: \(urlString)")
            return
        }
        if ensureTokenSet && !loggedIn() {
            fail(CallError(type: .notLoggedIn, detail: "not logged in when required for call"))
            return
        }
        
        let session = getURLSession()
        guard let request = createPostRequest(url: url, data: data) else {
            fail(CallError(type: .unexpectedRequest, detail: "error encoding payload"))
            return
        }
        session.dataTask(with: request) { data, response, error in
            guard let httpResponse = response as? HTTPURLResponse else {
                print("could not format HttpResponse")
                fail(CallError(type: .unexpectedResponse, detail: "could not format HttpResponse"))
                return
            }
            
            guard let data = data else {
                fail(CallError(type: .unexpectedResponse, detail: "no data returned from server"))
                return
            }
            if httpResponse.statusCode != 200 {
                fail(self.formatError(response: httpResponse, data: data))
                return
            }
            
            do {
                let decodedData = try self.getResponseData(T.self, from: data)
                DispatchQueue.main.async {
                    success(decodedData)
                }
            } catch let error {
                print(error)
                fail(CallError(type: .unexpectedResponse, detail: "error decoding successful response"))
            }
        }.resume()
    }
    
    func postDataWithoutResponse<T: Encodable>(urlString: String, data: T, ensureTokenSet: Bool = true, success: @escaping (() -> Void), fail: @escaping ((CallError) -> Void)) {
        guard let url = URL(string: "\(host)\(urlString)") else {
            print("error URL: \(urlString)")
            return
        }
        if ensureTokenSet && !loggedIn() {
            fail(CallError(type: .notLoggedIn, detail: "not logged in when required for call"))
            return
        }
        
        let session = getURLSession()
        guard let request = createPostRequest(url: url, data: data) else {
            fail(CallError(type: .unexpectedRequest, detail: "error encoding payload"))
            return
        }
        session.dataTask(with: request) { data, response, error in
            guard let httpResponse = response as? HTTPURLResponse else {
                print("could not format HttpResponse")
                fail(CallError(type: .unexpectedResponse, detail: "could not format HttpResponse"))
                return
            }
            
            if httpResponse.statusCode != 204 {
                guard let data = data else {
                    fail(CallError(type: .unexpectedResponse, detail: "no data returned from server"))
                    return
                }
                fail(self.formatError(response: httpResponse, data: data))
                return
            }
            
            DispatchQueue.main.async {
                success()
            }
        }.resume()
    }
    
    func loadAdditions(success: @escaping ([Addition]) -> Void) {
        getData(urlString: "/api/v1/addition/") { (results: AdditionResults) in
            success(results.results)
        } fail: { error in
            print("failed to get additions \(error)")
        }
    }
    
    func loadProfile(success: @escaping (Profile) -> Void) {
        getData(urlString: "/api/v1/auth/account/") { (profile: Profile) in
            success(profile)
        } fail: { error in
            print("failed to get profile: \(error)")
        }
    }
    
    func login(username: String, password: String, success: @escaping () -> Void) {
        let payload = LoginPayload(username: username, password: password)
        postData(urlString: "/api/v1/auth/login/", data: payload, ensureTokenSet: false) { (result: LoginSuccess) in
            KeychainHelper.standard.save(item: result.token, service: "dionysus", account: "auth-token")
            success()
        } fail: { error in
            print("failed to login: \(error)")
        }
    }
    
    func logout(success: @escaping () -> Void) {
        postDataWithoutResponse(urlString: "/api/v1/auth/logout/", data: EmptyPayload()) {
            KeychainHelper.standard.delete(service: "dionysus", account: "auth-token")
            print("logged out")
            success()
        } fail: { error in
            KeychainHelper.standard.delete(service: "dionysus", account: "auth-token")
            print("failed to logout: \(error)")
            // allow caller code to proceed since token is gone
            success()
        }
    }
}
