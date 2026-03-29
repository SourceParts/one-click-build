import Foundation

/// HTTP client for the Source Parts API. Drives the one-click build pipeline.
class BuildAPIClient {
    private let baseURL = "https://api.source.parts"

    enum APIError: LocalizedError {
        case noAPIKey
        case invalidURL
        case invalidResponse
        case httpError(Int, String)

        var errorDescription: String? {
            switch self {
            case .noAPIKey: return "No API key found. Run `parts auth login` first."
            case .invalidURL: return "Invalid URL"
            case .invalidResponse: return "Invalid API response"
            case .httpError(let code, let msg): return "HTTP \(code): \(msg)"
            }
        }
    }

    // MARK: - Ingest (QuarterMaster)

    struct IngestResult {
        var files: [String] = []
        var hiddenFiles: [String] = []
        var repoOwner: String?
        var repoName: String?
        var totalFiles: Int = 0
        var hasLicense: Bool = false
    }

    func ingestGitHub(url: String) async throws -> IngestResult {
        // Try QuarterMaster first
        let data = try await apiPost("/v1/q", body: ["text": url])
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.invalidResponse
        }

        // Response shape: {"status": "success", "data": {"type": "github", "results": {...}}}
        let dataObj = json["data"] as? [String: Any] ?? json
        let results = dataObj["results"] as? [String: Any] ?? dataObj
        var result = IngestResult()
        result.files = results["files"] as? [String] ?? []
        result.hiddenFiles = results["hidden_files"] as? [String] ?? []
        result.repoOwner = results["repo_owner"] as? String
        result.repoName = results["repo_name"] as? String

        if let report = results["report"] as? [String: Any] {
            result.totalFiles = report["total_files"] as? Int ?? result.files.count
            result.hasLicense = report["has_license"] as? Bool ?? false
        }

        // If Q returned 0 files (private repo), try GitHub API directly
        if result.files.isEmpty, let (owner, repo) = Self.parseGitHubURL(url) {
            result.repoOwner = owner
            result.repoName = repo
            if let ghFiles = try? await fetchGitHubTree(owner: owner, repo: repo) {
                result.files = ghFiles.filter { !$0.hasPrefix(".") }
                result.hiddenFiles = ghFiles.filter { $0.hasPrefix(".") }
                result.totalFiles = ghFiles.count
                result.hasLicense = ghFiles.contains { $0.lowercased().hasPrefix("license") }
            }
        }

        return result
    }

    /// Parse "https://github.com/owner/repo" into (owner, repo)
    static func parseGitHubURL(_ url: String) -> (String, String)? {
        let cleaned = url.replacingOccurrences(of: "https://github.com/", with: "")
            .split(separator: "/").map(String.init)
        guard cleaned.count >= 2 else { return nil }
        return (cleaned[0], cleaned[1])
    }

    /// Fetch file tree from GitHub API using gh CLI auth
    private func fetchGitHubTree(owner: String, repo: String) async throws -> [String] {
        let ghURL = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/git/trees/main?recursive=1")!
        var request = URLRequest(url: ghURL)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.setValue("PartsCLI/1.0", forHTTPHeaderField: "User-Agent")

        // Use GitHub token from environment if available
        if let ghToken = ProcessInfo.processInfo.environment["GITHUB_TOKEN"]
            ?? ProcessInfo.processInfo.environment["GH_TOKEN"] {
            request.setValue("Bearer \(ghToken)", forHTTPHeaderField: "Authorization")
        } else {
            // Try to get token from gh CLI
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            proc.arguments = ["gh", "auth", "token"]
            let pipe = Pipe()
            proc.standardOutput = pipe
            proc.standardError = Pipe()
            try? proc.run()
            proc.waitUntilExit()
            let tokenData = pipe.fileHandleForReading.readDataToEndOfFile()
            if let token = String(data: tokenData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !token.isEmpty {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
        }

        let (data, _) = try await URLSession.shared.data(for: request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tree = json["tree"] as? [[String: Any]] else {
            return []
        }
        return tree.compactMap { $0["path"] as? String }
    }

    // MARK: - Project

    struct ProjectResult {
        var projectId: String
        var name: String
    }

    func createProject(name: String, repoURL: String) async throws -> ProjectResult {
        let data = try await apiPost("/v1/projects", body: [
            "name": name,
            "repo_url": repoURL,
            "description": "One-click build from \(repoURL)",
        ])
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let projData = json["data"] as? [String: Any] ?? json as [String: Any]?,
              let id = projData["project_id"] as? String ?? projData["id"] as? String else {
            throw APIError.invalidResponse
        }
        return ProjectResult(projectId: id, name: name)
    }

    // MARK: - BOM

    func uploadBOM(projectId: String, parts: [[String: Any]]) async throws -> String {
        // Build CSV in memory
        var csv = "Reference,Part Number,Quantity,Description\n"
        for (i, part) in parts.enumerated() {
            let pn = part["part_number"] as? String ?? ""
            let qty = part["quantity"] as? Int ?? 1
            let desc = part["description"] as? String ?? ""
            csv += "U\(i + 1),\(pn),\(qty),\(desc)\n"
        }

        let data = try await apiMultipart("/v1/bom", fileName: "bom.csv", fileData: Data(csv.utf8), fields: [
            "project_id": projectId,
        ])
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.invalidResponse
        }
        return json["job_id"] as? String ?? json["bom_id"] as? String ?? json["id"] as? String ?? "submitted"
    }

    struct BOMCostResult {
        var totalCost: Double = 0
        var matchedParts: Int = 0
        var lineItems: [(partNumber: String, unitPrice: Double, quantity: Int)] = []
    }

    func calculateBOMCost(parts: [[String: Any]], quantity: Int) async throws -> BOMCostResult {
        let data = try await apiPost("/v1/costs/estimate", body: [
            "parts": parts,
            "quantity": quantity,
        ])
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.invalidResponse
        }

        var result = BOMCostResult()
        if let items = json["data"] as? [[String: Any]] {
            for item in items {
                let pn = item["part_number"] as? String ?? "?"
                let price = item["unit_price"] as? Double ?? 0
                let qty = item["quantity"] as? Int ?? 1
                result.lineItems.append((pn, price, qty))
                result.totalCost += price * Double(qty)
                if price > 0 { result.matchedParts += 1 }
            }
        }
        return result
    }

    // MARK: - Search / Price

    struct PriceResult {
        var partNumber: String
        var unitPrice: Double
        var stock: Int
        var supplier: String
    }

    func searchAndPrice(partNumber: String, quantity: Int = 1) async throws -> PriceResult {
        // Try LCSC SKU format first (lcsc-C12345), then raw search
        let isLCSC = partNumber.hasPrefix("C") && partNumber.dropFirst().allSatisfy(\.isNumber)
        let query = isLCSC ? "lcsc-\(partNumber)" : partNumber
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let data = try await apiGet("/v1/parts/search?q=\(encoded)&limit=3", timeout: 3)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.invalidResponse
        }

        let dataObj = json["data"] as? [String: Any] ?? json
        let results = dataObj["parts"] as? [[String: Any]]
            ?? dataObj["results"] as? [[String: Any]]
            ?? json["results"] as? [[String: Any]] ?? []

        // Find best match with a price
        for item in results {
            let price: Double
            if let p = item["price"] as? Double {
                price = p
            } else if let s = item["price"] as? String, let p = Double(s), p > 0 {
                price = p
            } else if let p = item["unit_price"] as? Double {
                price = p
            } else {
                continue
            }
            if price > 0 {
                return PriceResult(
                    partNumber: item["mpn"] as? String ?? item["sku"] as? String ?? partNumber,
                    unitPrice: price,
                    stock: item["stock_quantity"] as? Int ?? item["stock"] as? Int ?? 0,
                    supplier: (item["metadata"] as? [String: Any])?["external_source"] as? String ?? "LCSC"
                )
            }
        }

        // Return first result even without price
        if let first = results.first {
            return PriceResult(
                partNumber: first["mpn"] as? String ?? first["sku"] as? String ?? partNumber,
                unitPrice: 0,
                stock: first["stock_quantity"] as? Int ?? 0,
                supplier: "LCSC"
            )
        }
        return PriceResult(partNumber: partNumber, unitPrice: 0, stock: 0, supplier: "N/A")
    }

    // MARK: - DFM

    struct DFMResult {
        var jobId: String?
        var score: Int = 0
        var status: String = ""
    }

    func dfmEstimate(projectId: String) async throws -> DFMResult {
        let data = try await apiPost("/v1/dfm/estimate", body: [
            "project_id": projectId,
            "priority": "normal",
        ])
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.invalidResponse
        }
        return DFMResult(
            jobId: json["job_id"] as? String,
            score: json["score"] as? Int ?? 0,
            status: json["status"] as? String ?? "submitted"
        )
    }

    // MARK: - ECN / ECO

    func createECN(projectId: String, ecnId: String, title: String, type: String = "BOM Change") async throws -> String {
        let data = try await apiPost("/v1/projects/\(projectId)/ecns", body: [
            "id": ecnId,
            "title": title,
            "type": type,
            "severity": "MEDIUM",
            "disposition": "REQUIRED",
        ])
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let ecnId = json["ecn_id"] as? String ?? json["id"] as? String else {
            throw APIError.invalidResponse
        }
        return ecnId
    }

    func createECO(projectId: String, title: String, ecnIds: [String]) async throws -> String {
        let data = try await apiPost("/v1/projects/\(projectId)/eco", body: [
            "title": title,
            "revision": "EVT1",
            "ecn_ids": ecnIds,
        ])
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let ecoId = json["eco_id"] as? String ?? json["id"] as? String else {
            throw APIError.invalidResponse
        }
        return ecoId
    }

    // MARK: - Credits

    struct CreditsResult {
        var balance: Int = 0
        var currency: String = "USD"
        var isAdmin: Bool = false
        var tier: String = ""
    }

    func getCreditsBalance() async throws -> CreditsResult {
        let data = try await apiGet("/v1/credits/balance")
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.invalidResponse
        }
        let balanceData = json["data"] as? [String: Any] ?? json
        let tier = balanceData["tier"] as? String ?? ""
        let role = balanceData["role"] as? String ?? ""
        let isAdmin = role == "super_admin" || role == "admin"
            || (balanceData["unlimited"] as? Bool ?? false)
        return CreditsResult(
            balance: balanceData["balance"] as? Int ?? balanceData["credits"] as? Int ?? 0,
            currency: balanceData["currency"] as? String ?? "USD",
            isAdmin: isAdmin,
            tier: tier
        )
    }

    // MARK: - Fabrication Quote

    struct FabQuoteResult {
        var jobId: String?
        var unitPrice: Double = 0
        var totalPrice: Double = 0
        var leadTime: String = ""
        var factory: String = "JLCPCB via Source Parts"
    }

    func quoteFab(projectId: String, quantity: Int = 5, layers: Int = 4) async throws -> FabQuoteResult {
        let data = try await apiPost("/v1/dfm/estimate", body: [
            "project_id": projectId,
            "quantity": quantity,
            "layers": layers,
        ])
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.invalidResponse
        }
        return FabQuoteResult(
            jobId: json["job_id"] as? String,
            unitPrice: json["unit_price"] as? Double ?? 0,
            totalPrice: json["total_price"] as? Double ?? 0,
            leadTime: json["lead_time"] as? String ?? "5-7 business days",
            factory: "JLCPCB via Source Parts"
        )
    }

    // MARK: - Order

    func placeOrder(projectId: String, factory: String = "JLCPCB") async throws -> String {
        let data = try await apiPost("/v1/orders", body: [
            "project_id": projectId,
            "factory": factory,
            "quantity": 5,
        ])
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let orderId = json["order_id"] as? String ?? json["id"] as? String else {
            throw APIError.invalidResponse
        }
        return orderId
    }

    // MARK: - HTTP Helpers

    private func setAuth(_ request: inout URLRequest, apiKey: String) {
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        request.setValue("PartsCLI/1.0", forHTTPHeaderField: "User-Agent")
    }

    private func apiGet(_ path: String, timeout: TimeInterval = 10) async throws -> Data {
        guard let apiKey = APIKeychain.loadAPIKey() else { throw APIError.noAPIKey }
        guard let url = URL(string: "\(baseURL)\(path)") else { throw APIError.invalidURL }

        var request = URLRequest(url: url)
        setAuth(&request, apiKey: apiKey)
        request.timeoutInterval = timeout

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            let msg = String(data: data, encoding: .utf8) ?? ""
            throw APIError.httpError(http.statusCode, msg)
        }
        return data
    }

    private func apiMultipart(_ path: String, fileName: String, fileData: Data, fields: [String: String] = [:]) async throws -> Data {
        guard let apiKey = APIKeychain.loadAPIKey() else { throw APIError.noAPIKey }
        guard let url = URL(string: "\(baseURL)\(path)") else { throw APIError.invalidURL }

        let boundary = "Build-\(UUID().uuidString)"
        var body = Data()

        // Add form fields
        for (key, value) in fields {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }

        // Add file
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: text/csv\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        setAuth(&request, apiKey: apiKey)
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        request.timeoutInterval = 60

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let msg = String(data: data, encoding: .utf8) ?? ""
            throw APIError.httpError(http.statusCode, msg)
        }
        return data
    }

    private func apiPost(_ path: String, body: [String: Any]) async throws -> Data {
        guard let apiKey = APIKeychain.loadAPIKey() else { throw APIError.noAPIKey }
        guard let url = URL(string: "\(baseURL)\(path)") else { throw APIError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        setAuth(&request, apiKey: apiKey)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 60

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let msg = String(data: data, encoding: .utf8) ?? ""
            throw APIError.httpError(http.statusCode, msg)
        }
        return data
    }
}
