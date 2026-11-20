import Foundation

enum OllamaError: LocalizedError {
    case notRunning
    case modelMissing(String)
    case bad(String)

    var errorDescription: String? {
        switch self {
        case .notRunning: return "Ollama isn't running. Start it and try again."
        case .modelMissing(let m): return "Model \(m) isn't installed. Run: ollama pull \(m)"
        case .bad(let s): return s
        }
    }
}

struct OllamaClient {
    var base = URL(string: "http://127.0.0.1:11434")!

    private func jsonRequest(_ path: String, _ body: [String: Any], timeout: TimeInterval) throws -> URLRequest {
        var req = URLRequest(url: base.appendingPathComponent(path))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = timeout
        return req
    }

    func post(
        _ path: String, _ body: [String: Any], model: String, timeout: TimeInterval = 120
    ) async throws -> Data {
        let req = try jsonRequest(path, body, timeout: timeout)
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if code == 404 { throw OllamaError.modelMissing(model) }
            if code != 200 { throw OllamaError.bad("Ollama returned HTTP \(code).") }
            return data
        } catch let e as URLError where e.code == .cannotConnectToHost || e.code == .networkConnectionLost {
            throw OllamaError.notRunning
        }
    }

    /// Warm-up and chat must send the same num_ctx, or Ollama reloads the model.
    func chat(
        model: String, system: String?, user: String, keepAlive: String?,
        numCtx: Int? = nil, numPredict: Int? = nil
    ) async throws -> String {
        var messages: [[String: String]] = []
        if let system { messages.append(["role": "system", "content": system]) }
        messages.append(["role": "user", "content": user])
        var options: [String: Any] = ["temperature": 0]
        if let numCtx { options["num_ctx"] = numCtx }
        if let numPredict { options["num_predict"] = numPredict }
        var body: [String: Any] = [
            "model": model, "messages": messages, "stream": false, "think": false,
            "options": options,
        ]
        if let keepAlive { body["keep_alive"] = keepAlive }
        let data = try await post("api/chat", body, model: model)
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let msg = obj["message"] as? [String: Any], let text = msg["content"] as? String
        else { throw OllamaError.bad("Unexpected response from Ollama.") }
        return text
    }

    func warm(model: String, keepAlive: String, numCtx: Int? = nil) async throws {
        var body: [String: Any] = ["model": model, "keep_alive": keepAlive]
        if let numCtx { body["options"] = ["num_ctx": numCtx] }
        _ = try await post("api/generate", body, model: model)
    }

    func unload(model: String) async {
        _ = try? await post(
            "api/generate", ["model": model, "keep_alive": 0], model: model, timeout: 3)
    }

    /// Installed text models. Decision models like Tev1 are left out.
    func chatModels() async -> [String] {
        guard let (data, _) = try? await URLSession.shared.data(
            for: URLRequest(url: base.appendingPathComponent("api/tags"), timeoutInterval: 5)),
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let names = (obj["models"] as? [[String: Any]])?.compactMap({ $0["name"] as? String })
        else { return [] }
        var found: [String] = []
        for name in names.sorted() {
            guard let req = try? jsonRequest("api/show", ["model": name], timeout: 5),
                let (d, _) = try? await URLSession.shared.data(for: req),
                let info = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                (info["capabilities"] as? [String])?.contains("completion") == true
            else { continue }
            found.append(name)
        }
        return found
    }

    func expiresAt(model: String) async -> Date? {
        guard let (data, _) = try? await URLSession.shared.data(for: psRequest()) else { return nil }
        return Self.parseExpiry(data, model: model)
    }

    /// Quit-time release. Blocks for a few seconds at most, since the main queue stops during
    /// termination. Skips a model another client has touched.
    func unloadAtQuit(model: String, ourExpiry: Date?) {
        if let ourExpiry, let data = Self.send(psRequest()),
            let server = Self.parseExpiry(data, model: model), server > ourExpiry.addingTimeInterval(5)
        {
            return
        }
        guard let req = try? jsonRequest(
            "api/generate", ["model": model, "keep_alive": 0], timeout: 3)
        else { return }
        _ = Self.send(req)
    }

    private func psRequest() -> URLRequest {
        var req = URLRequest(url: base.appendingPathComponent("api/ps"))
        req.timeoutInterval = 3
        return req
    }

    private static func send(_ req: URLRequest) -> Data? {
        var result: Data?
        let done = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: req) { data, _, _ in
            result = data
            done.signal()
        }.resume()
        _ = done.wait(timeout: .now() + 4)
        return result
    }

    private static func parseExpiry(_ data: Data, model: String) -> Date? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let models = obj["models"] as? [[String: Any]],
            let entry = models.first(where: { ($0["name"] as? String) == model }),
            let raw = entry["expires_at"] as? String
        else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: raw) ?? ISO8601DateFormatter().date(from: raw)
    }
}
