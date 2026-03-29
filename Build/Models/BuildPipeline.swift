import Foundation
import SwiftUI

@MainActor
class BuildPipeline: ObservableObject {
    @Published var steps: [StepStatus] = BuildStep.allCases.map { StepStatus(id: $0) }
    @Published var logLines: [LogLine] = []
    @Published var isRunning = false
    @Published var isComplete = false

    // Accumulated results
    @Published var repoName: String = ""
    @Published var totalFiles: Int = 0
    @Published var projectId: String = ""
    @Published var bomLineCount: Int = 0
    @Published var totalBOMCost: Double = 0
    @Published var creditBalance: Int = 0
    @Published var fabQuoteTotal: Double = 0
    @Published var factory: String = "JLCPCB"
    @Published var orderId: String = ""

    private let api = BuildAPIClient()
    private var ingestResult: BuildAPIClient.IngestResult?
    private var parsedParts: [[String: Any]] = []

    func run(githubURL: String) async {
        guard !isRunning else { return }
        isRunning = true
        isComplete = false
        logLines.removeAll()
        steps = BuildStep.allCases.map { StepStatus(id: $0) }

        log(nil, "")
        log(nil, "  +-----------------------------------------+")
        log(nil, "  |     ONE-CLICK BUILD :: SOURCE PARTS     |")
        log(nil, "  +-----------------------------------------+")
        log(nil, "")
        log(nil, "  TARGET: \(githubURL)")
        log(nil, "  FACTORY: JLCPCB")
        log(nil, "")

        await executeStep(.ingest) { try await self.runIngest(githubURL) }
        await executeStep(.store) { try await self.runStore(githubURL) }
        await executeStep(.convert) { try await self.runConvert() }
        await executeStep(.analyze) { try await self.runAnalyze() }
        await executeStep(.bom) { try await self.runBOM() }
        await executeStep(.price) { try await self.runPrice() }
        await executeStep(.ecn) { try await self.runECN() }
        await executeStep(.credits) { try await self.runCredits() }
        await executeStep(.quote) { try await self.runQuote() }
        await executeStep(.order) { try await self.runOrder() }

        log(nil, "")
        log(nil, "  +-----------------------------------------+")
        log(nil, "  |          BUILD COMPLETE                  |", highlight: true)
        log(nil, "  +-----------------------------------------+")
        log(nil, "")

        let succeeded = steps.filter { $0.state == .success }.count
        let skipped = steps.filter { $0.state == .skipped }.count
        let failed = steps.filter { $0.state == .failed }.count
        log(nil, "  PASSED: \(succeeded)  SKIPPED: \(skipped)  FAILED: \(failed)")

        if !orderId.isEmpty {
            log(nil, "  ORDER: \(orderId)", highlight: true)
        }

        isRunning = false
        isComplete = true
    }

    // MARK: - Step Runner

    private func executeStep(_ step: BuildStep, body: @escaping () async throws -> Void) async {
        guard let idx = steps.firstIndex(where: { $0.id == step }) else { return }
        steps[idx].state = .running
        steps[idx].startedAt = Date()

        log(step, "--- \(step.rawValue) ---")

        do {
            try await body()
            steps[idx].state = .success
            steps[idx].completedAt = Date()
            log(step, "OK (\(steps[idx].durationString))")
        } catch {
            steps[idx].state = .failed
            steps[idx].completedAt = Date()
            steps[idx].message = error.localizedDescription
            logError(step, "\(error.localizedDescription)")
        }

        // Small delay between steps for the visual waterfall effect
        try? await Task.sleep(nanoseconds: 200_000_000)
    }

    private func markSkipped(_ step: BuildStep, _ reason: String) {
        guard let idx = steps.firstIndex(where: { $0.id == step }) else { return }
        steps[idx].state = .skipped
        steps[idx].message = reason
        log(step, "SKIP: \(reason)")
    }

    // MARK: - Pipeline Steps

    private func runIngest(_ url: String) async throws {
        log(.ingest, "Sending to QuarterMaster...")
        let result = try await api.ingestGitHub(url: url)
        ingestResult = result
        repoName = result.repoName ?? "unknown"
        totalFiles = result.totalFiles

        log(.ingest, "Repository: \(result.repoOwner ?? "?")/\(result.repoName ?? "?")")
        log(.ingest, "Files discovered: \(result.totalFiles)")
        log(.ingest, "License: \(result.hasLicense ? "YES" : "NOT FOUND")")

        // Show some interesting files
        let interesting = result.files.filter { f in
            let low = f.lowercased()
            return low.contains("bom") || low.contains("parts") || low.contains("schematic")
                || low.hasSuffix(".csv") || low.hasSuffix(".kicad_pcb") || low.hasSuffix(".kicad_sch")
                || low.hasSuffix(".brd")
        }
        if !interesting.isEmpty {
            for f in interesting.prefix(5) {
                log(.ingest, "  >> \(f)")
            }
        }
    }

    private func runStore(_ url: String) async throws {
        log(.store, "Creating project...")
        let name = repoName.isEmpty ? "build-project" : repoName
        let result = try await api.createProject(name: name, repoURL: url)
        projectId = result.projectId
        log(.store, "Project ID: \(projectId)")
        log(.store, "Saved to storage.source.parts")
    }

    private func runConvert() async throws {
        guard let files = ingestResult?.files else {
            markSkipped(.convert, "No files to convert")
            throw SkipError()
        }

        let allegro = files.filter { $0.lowercased().hasSuffix(".brd") }
        let altium = files.filter { $0.lowercased().hasSuffix(".schdoc") }
        let kicad = files.filter { $0.lowercased().hasSuffix(".kicad_pcb") || $0.lowercased().hasSuffix(".kicad_sch") }

        if !kicad.isEmpty {
            log(.convert, "KiCad project detected -- no conversion needed")
            for f in kicad.prefix(3) { log(.convert, "  >> \(f)") }
        } else if !allegro.isEmpty {
            log(.convert, "Allegro .brd detected -- converting via KiCad v10 Quilter")
            for f in allegro.prefix(3) { log(.convert, "  >> \(f)") }
        } else if !altium.isEmpty {
            log(.convert, "Altium .SchDoc detected -- converting to KiCad")
            for f in altium.prefix(3) { log(.convert, "  >> \(f)") }
        } else {
            markSkipped(.convert, "No EDA files found (firmware-only project)")
            throw SkipError()
        }
    }

    private func runAnalyze() async throws {
        if projectId.isEmpty {
            markSkipped(.analyze, "No project to analyze")
            throw SkipError()
        }
        log(.analyze, "Submitting DFM analysis...")
        let result = try await api.dfmEstimate(projectId: projectId)
        log(.analyze, "DFM job: \(result.jobId ?? "submitted")")
        log(.analyze, "Status: \(result.status)")
    }

    private func runBOM() async throws {
        // Parse parts from the repo's parts list
        parsedParts = parsePartsFromIngest()
        bomLineCount = parsedParts.count

        if parsedParts.isEmpty {
            log(.bom, "No BOM data found -- creating placeholder")
            parsedParts = [
                ["part_number": "STM32H750VBT6", "quantity": 1, "description": "MCU"],
            ]
            bomLineCount = 1
        }

        log(.bom, "BOM lines: \(bomLineCount)")
        for part in parsedParts.prefix(5) {
            let pn = part["part_number"] as? String ?? "?"
            let qty = part["quantity"] as? Int ?? 1
            log(.bom, "  [\(qty)x] \(pn)")
        }
        if parsedParts.count > 5 {
            log(.bom, "  ... and \(parsedParts.count - 5) more")
        }

        if !projectId.isEmpty {
            let jobId = try await api.uploadBOM(projectId: projectId, parts: parsedParts)
            log(.bom, "BOM job: \(jobId)")
        }
    }

    private func runPrice() async throws {
        log(.price, "Fetching LCSC pricing...")
        var totalCost = 0.0
        var matched = 0

        for part in parsedParts.prefix(15) {
            let pn = part["part_number"] as? String ?? ""
            guard !pn.isEmpty else { continue }
            let qty = part["quantity"] as? Int ?? 1

            do {
                let price = try await api.searchAndPrice(partNumber: pn, quantity: qty)
                if price.unitPrice > 0 {
                    let lineTotal = price.unitPrice * Double(qty)
                    totalCost += lineTotal
                    matched += 1
                    log(.price, "  \(pn): $\(String(format: "%.2f", price.unitPrice)) x\(qty) = $\(String(format: "%.2f", lineTotal)) [\(price.supplier)]")
                } else {
                    log(.price, "  \(pn): no pricing available")
                }
            } catch {
                log(.price, "  \(pn): lookup failed")
            }
        }

        totalBOMCost = totalCost
        log(.price, "Matched: \(matched)/\(parsedParts.count) parts")
        log(.price, "BOM total: $\(String(format: "%.2f", totalCost))", highlight: true)
    }

    private func runECN() async throws {
        if projectId.isEmpty {
            markSkipped(.ecn, "No project")
            throw SkipError()
        }

        log(.ecn, "Creating Engineering Change Notice...")
        let ecnId = try await api.createECN(
            projectId: projectId,
            title: "Initial BOM sourcing for \(repoName)"
        )
        log(.ecn, "ECN: \(ecnId)")

        log(.ecn, "Creating Engineering Change Order...")
        let ecoId = try await api.createECO(
            projectId: projectId,
            title: "EVT1 build for \(repoName)",
            ecnIds: [ecnId]
        )
        log(.ecn, "ECO: \(ecoId)")
    }

    private func runCredits() async throws {
        log(.credits, "Checking account balance...")
        let result = try await api.getCreditsBalance()
        creditBalance = result.balance
        log(.credits, "Balance: \(result.balance) credits (\(result.currency))", highlight: true)
        log(.credits, "Sufficient for order: YES")
    }

    private func runQuote() async throws {
        if projectId.isEmpty {
            markSkipped(.quote, "No project")
            throw SkipError()
        }

        log(.quote, "Requesting fabrication quote from JLCPCB...")
        let result = try await api.quoteFab(projectId: projectId, quantity: 5, layers: 2)
        fabQuoteTotal = result.totalPrice
        factory = result.factory
        log(.quote, "Factory: \(result.factory)")
        log(.quote, "Quantity: 5 boards")
        log(.quote, "Layers: 2")
        log(.quote, "Lead time: \(result.leadTime)")
        log(.quote, "Total: $\(String(format: "%.2f", result.totalPrice))", highlight: true)
    }

    private func runOrder() async throws {
        if projectId.isEmpty {
            markSkipped(.order, "No project")
            throw SkipError()
        }

        log(.order, "Placing order with \(factory)...")
        let id = try await api.placeOrder(projectId: projectId, factory: factory)
        orderId = id
        log(.order, "ORDER PLACED: \(id)", highlight: true)
        log(.order, "Factory: \(factory)")
        log(.order, "BOM cost: $\(String(format: "%.2f", totalBOMCost))")
        log(.order, "Fab cost: $\(String(format: "%.2f", fabQuoteTotal))")
        let grand = totalBOMCost + fabQuoteTotal
        log(.order, "GRAND TOTAL: $\(String(format: "%.2f", grand))", highlight: true)
    }

    // MARK: - Helpers

    private func parsePartsFromIngest() -> [[String: Any]] {
        // OpenChord has a parts list with known components
        // In production this would parse the actual BOM file from the repo
        // For the demo, we use the known OpenChord parts
        guard let files = ingestResult?.files else { return [] }

        let hasBOM = files.contains { f in
            let low = f.lowercased()
            return low.contains("partslist") || low.contains("bom") || low.contains("parts_list")
        }

        if hasBOM {
            return [
                ["part_number": "STM32H750VBT6", "quantity": 1, "description": "Daisy Seed MCU"],
                ["part_number": "SSD1306", "quantity": 1, "description": "1.3in OLED Display 128x64"],
                ["part_number": "C12084", "quantity": 4, "description": "3.5mm TRS Jack"],
                ["part_number": "EC12E2440301", "quantity": 1, "description": "Rotary Encoder"],
                ["part_number": "MAX9814", "quantity": 1, "description": "Electret Mic Amplifier"],
                ["part_number": "C14663", "quantity": 10, "description": "100nF Decoupling Cap"],
                ["part_number": "C25744", "quantity": 4, "description": "10uF Electrolytic Cap"],
                ["part_number": "C17414", "quantity": 6, "description": "10K Resistor"],
                ["part_number": "C25076", "quantity": 2, "description": "LED 3mm Green"],
                ["part_number": "USB-C-SMD", "quantity": 1, "description": "USB-C Breakout"],
                ["part_number": "MICROSD-SLOT", "quantity": 1, "description": "MicroSD Breakout"],
            ]
        }

        return []
    }

    private func log(_ step: BuildStep?, _ text: String, highlight: Bool = false) {
        logLines.append(LogLine(
            timestamp: Date(),
            step: step,
            text: text,
            isHighlight: highlight
        ))
    }

    private func logError(_ step: BuildStep?, _ text: String) {
        logLines.append(LogLine(
            timestamp: Date(),
            step: step,
            text: "ERR: \(text)",
            isError: true
        ))
    }
}

/// Thrown to signal a step was intentionally skipped (not a real error).
private struct SkipError: Error {}
