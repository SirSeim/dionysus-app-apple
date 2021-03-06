import SwiftUI

struct LoginPayload: Codable {
    var username: String
    var password: String
}

struct LoginSuccess: Codable {
    var expiry: Date
    var token: String
}

enum DateError: String, Error {
    case invlidDate
}

struct EmptyPayload: Codable {}

class ApiManager {
    let host = "http://localhost:8000"
    
    func loggedIn() -> Bool {
        let token = token()
        if token == nil {
            return false
        }
        return token!.count > 0
    }
    
    func token() -> String? {
        return  KeychainHelper.standard.read(service: "dionysus", account: "auth-token", type: String.self)
    }
    
    func getData<T: Decodable>(urlString: String, ensureTokenSet: Bool = true, success: @escaping ((T) -> Void), fail: @escaping (() -> Void)) {
        guard let url = URL(string: "\(host)\(urlString)") else {
            print("error URL: \(urlString)")
            return
        }
        
        if ensureTokenSet && !loggedIn() {
            fail()
            return
        }
        
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.httpAdditionalHeaders = [
            "Accept": "application/json",
        ]
        if loggedIn() {
            sessionConfig.httpAdditionalHeaders!["Authorization"] = "Token \(token()!)"
        }
        let session = URLSession(configuration: sessionConfig)
        
        session.dataTask(with: url) { data, response, error in
            guard let httpResponse = response as? HTTPURLResponse else {
                print("could not format HttpResponse")
                fail()
                return
            }
            
            guard let data = data else { return }
            if httpResponse.statusCode != 200 {
                print("error statusCode \(httpResponse.statusCode):", String(data: data, encoding: .utf8) ?? "")
                fail()
                return
            }
            
            do {
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                let decodedData = try decoder.decode(T.self, from: data)
                DispatchQueue.main.async {
                    success(decodedData)
                }
            } catch let error {
                print(error)
                fail()
            }
        }.resume()
    }
    
    func postData<T: Decodable, Y: Encodable>(urlString: String, data: Y, ensureTokenSet: Bool = true, success: @escaping ((T) -> Void), fail: @escaping (() -> Void)) {
        guard let url = URL(string: "\(host)\(urlString)") else {
            print("error URL: \(urlString)")
            return
        }
        
        if ensureTokenSet && !loggedIn() {
            fail()
            return
        }
        
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.httpAdditionalHeaders = [
            "Accept": "application/json",
            "Content-Type": "application/json"
        ]
        if loggedIn() {
            sessionConfig.httpAdditionalHeaders!["Authorization"] = "Token \(token()!)"
        }
        let session = URLSession(configuration: sessionConfig)
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        do {
            let encoder = JSONEncoder()
            encoder.keyEncodingStrategy = .convertToSnakeCase
            request.httpBody = try encoder.encode(data)
        } catch let error {
            print("error json serialize:", error)
            return
        }
        
        session.dataTask(with: request) { data, response, error in
            guard let httpResponse = response as? HTTPURLResponse else {
                print("could not format HttpResponse")
                fail()
                return
            }
            
            guard let data = data else { return }
            if httpResponse.statusCode != 200 {
                print("error statusCode \(httpResponse.statusCode):", String(data: data, encoding: .utf8) ?? "")
                fail()
                return
            }
            
            do {
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
                    throw DateError.invlidDate
                })
                let decodedData = try decoder.decode(T.self, from: data)
                DispatchQueue.main.async {
                    success(decodedData)
                }
            } catch let error {
                print(error)
                fail()
            }
        }.resume()
    }
    
    func postDataWithoutResponse<T: Encodable>(urlString: String, data: T, ensureTokenSet: Bool = true, success: @escaping (() -> Void), fail: @escaping (() -> Void)) {
        guard let url = URL(string: "\(host)\(urlString)") else {
            print("error URL: \(urlString)")
            return
        }
        
        if ensureTokenSet && !loggedIn() {
            fail()
            return
        }
        
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.httpAdditionalHeaders = [
            "Accept": "application/json",
            "Content-Type": "application/json"
        ]
        if loggedIn() {
            sessionConfig.httpAdditionalHeaders!["Authorization"] = "Token \(token()!)"
        }
        let session = URLSession(configuration: sessionConfig)
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        do {
            let encoder = JSONEncoder()
            encoder.keyEncodingStrategy = .convertToSnakeCase
            request.httpBody = try encoder.encode(data)
        } catch let error {
            print("error json serialize:", error)
            return
        }
        
        session.dataTask(with: request) { data, response, error in
            guard let httpResponse = response as? HTTPURLResponse else {
                print("could not format HttpResponse")
                fail()
                return
            }
            
            guard let data = data else { return }
            if httpResponse.statusCode != 204 {
                print("error statusCode \(httpResponse.statusCode):", String(data: data, encoding: .utf8) ?? "")
                fail()
                return
            }
            
            success()
        }.resume()
    }
    
    func loadAdditions(success: @escaping ([Addition]) -> Void) {
        getData(urlString: "/api/v1/addition/") { (results: AdditionResults) in
            success(results.results)
        } fail: {
            print("failed to get additions")
        }
    }
    
    func loadProfile(success: @escaping (Profile) -> Void) {
        getData(urlString: "/api/v1/auth/account/") { (profile: Profile) in
            success(profile)
        } fail: {
            print("failed to get profile")
        }
    }
    
    func login(username: String, password: String, success: @escaping () -> Void) {
        let payload = LoginPayload(username: username, password: password)
        postData(urlString: "/api/v1/auth/login/", data: payload, ensureTokenSet: false) { (result: LoginSuccess) in
            KeychainHelper.standard.save(item: result.token, service: "dionysus", account: "auth-token")
            success()
        } fail: {
            print("failed to login")
        }
    }
    
    func logout(success: @escaping () -> Void) {
        postDataWithoutResponse(urlString: "/api/v1/auth/logout/", data: EmptyPayload()) {
            KeychainHelper.standard.delete(service: "dionysus", account: "auth-token")
            print("logged out")
            success()
        } fail: {
            print("failed to logout")
        }
    }
}
