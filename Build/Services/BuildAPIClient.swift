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
        let data = try await apiPost("/v1/q", body: ["text": url])
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.invalidResponse
        }

        let results = json["results"] as? [String: Any] ?? json["data"] as? [String: Any] ?? [:]
        var result = IngestResult()
        result.files = results["files"] as? [String] ?? []
        result.hiddenFiles = results["hidden_files"] as? [String] ?? []
        result.repoOwner = results["repo_owner"] as? String
        result.repoName = results["repo_name"] as? String

        if let report = results["report"] as? [String: Any] {
            result.totalFiles = report["total_files"] as? Int ?? result.files.count
            result.hasLicense = report["has_license"] as? Bool ?? false
        }
        return result
    }

    // MARK: - Project

    struct ProjectResult {
        var projectId: String
        var name: String
    }

    func createProject(name: String, repoURL: String) async throws -> ProjectResult {
        let data = try await apiPost("/v1/projects", body: [
            "name": name,
            "source_url": repoURL,
            "type": "pcb",
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
        let data = try await apiPost("/v1/bom", body: [
            "project_id": projectId,
            "parts": parts,
        ])
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let jobId = json["job_id"] as? String ?? json["bom_id"] as? String else {
            throw APIError.invalidResponse
        }
        return jobId
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
        let data = try await apiPost("/v1/parts/search", body: [
            "query": partNumber,
            "limit": 1,
        ])
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.invalidResponse
        }

        let results = json["results"] as? [[String: Any]] ?? json["data"] as? [[String: Any]] ?? []
        guard let first = results.first else {
            return PriceResult(partNumber: partNumber, unitPrice: 0, stock: 0, supplier: "N/A")
        }

        return PriceResult(
            partNumber: first["mpn"] as? String ?? partNumber,
            unitPrice: first["price"] as? Double ?? first["unit_price"] as? Double ?? 0,
            stock: first["stock_quantity"] as? Int ?? first["stock"] as? Int ?? 0,
            supplier: (first["metadata"] as? [String: Any])?["external_source"] as? String ?? "LCSC"
        )
    }

    // MARK: - DFM

    struct DFMResult {
        var jobId: String?
        var score: Int = 0
        var status: String = ""
    }

    func dfmEstimate(projectId: String) async throws -> DFMResult {
        let data = try await apiPost("/v1/manufacturing/dfm", body: [
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

    func createECN(projectId: String, title: String, type: String = "BOM Change") async throws -> String {
        let data = try await apiPost("/v1/projects/\(projectId)/ecns", body: [
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
    }

    func getCreditsBalance() async throws -> CreditsResult {
        let data = try await apiGet("/v1/credits/balance")
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.invalidResponse
        }
        let balanceData = json["data"] as? [String: Any] ?? json
        return CreditsResult(
            balance: balanceData["balance"] as? Int ?? balanceData["credits"] as? Int ?? 0,
            currency: balanceData["currency"] as? String ?? "USD"
        )
    }

    // MARK: - Fabrication Quote

    struct FabQuoteResult {
        var jobId: String?
        var unitPrice: Double = 0
        var totalPrice: Double = 0
        var leadTime: String = ""
        var factory: String = "JLCPCB"
    }

    func quoteFab(projectId: String, quantity: Int = 5, layers: Int = 2) async throws -> FabQuoteResult {
        let data = try await apiPost("/v1/manufacturing/fab", body: [
            "project_id": projectId,
            "quantity": quantity,
            "layers": layers,
            "thickness": 1.6,
            "surface_finish": "HASL",
            "color": "green",
            "priority": "normal",
        ])
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.invalidResponse
        }
        return FabQuoteResult(
            jobId: json["job_id"] as? String,
            unitPrice: json["unit_price"] as? Double ?? 0,
            totalPrice: json["total_price"] as? Double ?? 0,
            leadTime: json["lead_time"] as? String ?? "5-7 business days",
            factory: "JLCPCB"
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

    private func apiGet(_ path: String) async throws -> Data {
        guard let apiKey = APIKeychain.loadAPIKey() else { throw APIError.noAPIKey }
        guard let url = URL(string: "\(baseURL)\(path)") else { throw APIError.invalidURL }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("Build/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
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
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Build/1.0", forHTTPHeaderField: "User-Agent")
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
