import SwiftUI

struct BuildView: View {
    @EnvironmentObject var pipeline: BuildPipeline
    @State private var githubURL = "https://github.com/SourceParts/NerdEKO-Gamma"
    @State private var isHovering = false
    @State private var showConsole = false
    @State private var selectedStep: BuildStep? = nil

    private let accent = Color(red: 0.9, green: 0.2, blue: 0.5)
    private let accentDim = Color(red: 0.7, green: 0.15, blue: 0.4)
    private let successGreen = Color(red: 0.15, green: 0.75, blue: 0.4)
    private let errorRed = Color(red: 0.9, green: 0.2, blue: 0.2)
    private let warnYellow = Color(red: 0.95, green: 0.7, blue: 0.1)
    private let bg = Color(red: 0.97, green: 0.97, blue: 0.98)
    private let cardBG = Color.white
    private let subtleText = Color(red: 0.5, green: 0.5, blue: 0.55)
    private let darkText = Color(red: 0.1, green: 0.1, blue: 0.12)

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                header
                    .padding(.top, 20)
                    .padding(.bottom, 16)
                    .padding(.horizontal, 28)

                urlField
                    .padding(.horizontal, 28)
                    .padding(.bottom, 14)

                buildButton
                    .padding(.horizontal, 28)
                    .padding(.bottom, 14)

                // Timeline strip (horizontal)
                timelineStrip
                    .padding(.horizontal, 28)
                    .padding(.bottom, 10)

                Divider().padding(.horizontal, 28)

                // Card detail area (replaces terminal)
                cardDetail
                    .padding(.horizontal, 28)
                    .padding(.top, 10)

                Spacer(minLength: 0)

                statusBar
                    .padding(.horizontal, 28)
                    .padding(.bottom, 12)
            }

            if showConsole {
                consoleOverlay
                    .transition(.move(edge: .bottom))
            }
        }
        .background(bg)
        .onAppear {
            NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                if event.characters == "`" {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        showConsole.toggle()
                    }
                    return nil
                }
                return event
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Parts Build")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(darkText)
                Text("One-click hardware manufacturing")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(subtleText)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("source.parts")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(accent)
                Text("powered by Source Parts API")
                    .font(.system(size: 10))
                    .foregroundColor(subtleText)
            }
        }
    }

    // MARK: - URL Field

    private var urlField: some View {
        HStack(spacing: 10) {
            Image(systemName: "link")
                .foregroundColor(subtleText)
                .font(.system(size: 14))
            TextField("Paste a GitHub repository URL...", text: $githubURL)
                .textFieldStyle(.plain)
                .font(.system(size: 14, design: .monospaced))
                .foregroundColor(darkText)
                .tint(accent)
                .disabled(pipeline.isRunning)
                .onSubmit {
                    guard !pipeline.isRunning, !githubURL.isEmpty else { return }
                    Task { await pipeline.run(githubURL: githubURL) }
                }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(cardBG)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(accent.opacity(0.3), lineWidth: 1))
        .contentShape(Rectangle())
    }

    // MARK: - BUILD Button

    private var buildButton: some View {
        Button(action: {
            guard !pipeline.isRunning, !githubURL.isEmpty else { return }
            Task { await pipeline.run(githubURL: githubURL) }
        }) {
            HStack(spacing: 10) {
                if pipeline.isRunning {
                    ProgressView().controlSize(.small).tint(.white)
                    Text("Building...").font(.system(size: 16, weight: .semibold))
                } else if pipeline.isComplete {
                    Image(systemName: "arrow.clockwise").font(.system(size: 16))
                    Text("Build Again").font(.system(size: 16, weight: .semibold))
                } else {
                    Image(systemName: "hammer.fill").font(.system(size: 16))
                    Text("Build").font(.system(size: 16, weight: .semibold))
                }
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(RoundedRectangle(cornerRadius: 10).fill(pipeline.isRunning ? accentDim : accent))
            .shadow(color: accent.opacity(pipeline.isRunning ? 0 : 0.3), radius: 8, y: 2)
        }
        .buttonStyle(.plain)
        .disabled(pipeline.isRunning || githubURL.isEmpty)
        .onHover { hovering in isHovering = hovering }
        .scaleEffect(isHovering && !pipeline.isRunning ? 1.01 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isHovering)
    }

    // MARK: - Timeline Strip

    private var timelineStrip: some View {
        HStack(spacing: 0) {
            ForEach(Array(pipeline.steps.enumerated()), id: \.element.id) { idx, step in
                // Step pill
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedStep = selectedStep == step.id ? nil : step.id
                    }
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: iconForStep(step.id))
                            .font(.system(size: 10))
                        Text(step.id.rawValue)
                            .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    }
                    .foregroundColor(selectedStep == step.id ? .white : labelForState(step.state))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(selectedStep == step.id ? fillForState(step.state) : fillForState(step.state).opacity(0.12))
                    )
                }
                .buttonStyle(.plain)

                // Connector line
                if idx < pipeline.steps.count - 1 {
                    let nextState = pipeline.steps[idx + 1].state
                    Rectangle()
                        .fill(step.state == .success ? successGreen.opacity(0.4) :
                              nextState == .pending ? subtleText.opacity(0.15) : subtleText.opacity(0.25))
                        .frame(height: 1.5)
                        .frame(maxWidth: 12)
                }
            }
        }
    }

    // MARK: - Card Detail Area

    private var cardDetail: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 10) {
                    if let selected = selectedStep,
                       let step = pipeline.steps.first(where: { $0.id == selected }) {
                        stepDetailCard(step)
                    } else if pipeline.steps.contains(where: { $0.state != .pending }) {
                        if pipeline.isComplete && pipeline.orderReady {
                            orderCard
                        }
                        ForEach(pipeline.steps.filter { $0.state != .pending }) { step in
                            stepDetailCard(step)
                                .id(step.id)
                        }
                    } else {
                        VStack(spacing: 8) {
                            Image(systemName: "hammer")
                                .font(.system(size: 28))
                                .foregroundColor(subtleText.opacity(0.3))
                            Text("Click Build to start")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(subtleText.opacity(0.5))
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.top, 40)
                    }
                }
            }
            .onChange(of: pipeline.logLines.count) { _, _ in
                if let latest = pipeline.steps.last(where: { $0.state != .pending }) {
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo(latest.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    // MARK: - Order Card

    private var orderCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            if pipeline.orderPlaced {
                // Congratulations state
                VStack(spacing: 12) {
                    Text("\u{1F389}")
                        .font(.system(size: 48))
                    Text("Congratulations!")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundColor(successGreen)
                    Text("Your order has been placed.")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(darkText)
                    Text(pipeline.orderId)
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundColor(subtleText)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 6).fill(successGreen.opacity(0.1)))
                    Text("Your board is on its way to the factory.")
                        .font(.system(size: 12))
                        .foregroundColor(subtleText)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            } else {
                // Ready to order
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("\u{2728}")
                            .font(.system(size: 22))
                        Text("Your board has been digitally forged.")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundColor(darkText)
                    }
                    Text("Review your order and place it with one click.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(subtleText)
                }

                Divider()

                // Summary
                VStack(spacing: 8) {
                    orderSummaryRow(label: "BOM Cost", value: String(format: "$%.2f", pipeline.totalBOMCost))
                    orderSummaryRow(label: "Fab Cost (5 boards)", value: String(format: "$%.2f", pipeline.fabQuoteTotal))
                    Divider()
                    HStack {
                        Text("Grand Total")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(darkText)
                        Spacer()
                        Text(String(format: "$%.2f", pipeline.totalBOMCost + pipeline.fabQuoteTotal))
                            .font(.system(size: 17, weight: .bold, design: .monospaced))
                            .foregroundColor(darkText)
                    }
                    HStack {
                        Text("Factory")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(subtleText)
                        Spacer()
                        Text(pipeline.factory)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(subtleText)
                    }
                }

                // Place Order button
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        pipeline.placeOrderConfirmed()
                    }
                }) {
                    HStack(spacing: 10) {
                        Image(systemName: "cart.fill").font(.system(size: 16))
                        Text("Place Order").font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(RoundedRectangle(cornerRadius: 10).fill(accent))
                    .shadow(color: accent.opacity(0.3), radius: 8, y: 2)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(cardBG)
                .shadow(color: Color.black.opacity(0.06), radius: 6, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(pipeline.orderPlaced ? successGreen.opacity(0.4) : accent.opacity(0.3), lineWidth: 1.5)
        )
    }

    private func orderSummaryRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(subtleText)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundColor(darkText)
        }
    }

    private func stepDetailCard(_ step: StepStatus) -> some View {
        let stepLogs = pipeline.logLines.filter { $0.step == step.id }

        return VStack(alignment: .leading, spacing: 8) {
            // Card header
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(fillForState(step.state).opacity(0.15))
                        .frame(width: 28, height: 28)
                    Image(systemName: iconForStep(step.id))
                        .font(.system(size: 12))
                        .foregroundColor(fillForState(step.state))
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(step.id.rawValue)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(darkText)
                    Text(stateLabel(step.state))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(labelForState(step.state))
                }

                Spacer()

                if let dur = step.duration {
                    Text(String(format: "%.1fs", dur))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(subtleText)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: 4).fill(bg))
                } else if step.state == .running {
                    ProgressView().controlSize(.small)
                }
            }

            // Log lines as selectable text block
            if !stepLogs.isEmpty {
                let filtered = stepLogs.filter { line in
                    let t = line.text
                    return !t.isEmpty && !t.hasPrefix("---") && !t.hasPrefix("OK (") && !t.hasPrefix("SKIP:")
                }
                if !filtered.isEmpty {
                    cardLogText(filtered)
                        .font(.system(size: 11))
                        .textSelection(.enabled)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 6).fill(bg))
                }
            }

            // Error message
            if step.state == .failed && !step.message.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(errorRed)
                        .font(.system(size: 11))
                    Text(step.message)
                        .font(.system(size: 11))
                        .foregroundColor(errorRed)
                        .textSelection(.enabled)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 6).fill(errorRed.opacity(0.08)))
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(cardBG)
                .shadow(color: Color.black.opacity(0.04), radius: 3, y: 1)
        )
    }

    private func cardLogText(_ lines: [LogLine]) -> Text {
        var result = Text("")
        for (i, line) in lines.enumerated() {
            if i > 0 { result = result + Text("\n") }

            let t = line.text
            if t.hasPrefix("  >>") {
                // File path
                let path = String(t.dropFirst(4)).trimmingCharacters(in: .whitespaces)
                result = result + Text("\u{1F4C4} ").foregroundColor(subtleText) + Text(path).foregroundColor(darkText).font(.system(size: 11, design: .monospaced))
            } else if t.contains(": $") && t.contains(" x") {
                // Price line
                result = result + Text(t).foregroundColor(successGreen).font(.system(size: 11, design: .monospaced))
            } else if line.isHighlight {
                result = result + Text(t).foregroundColor(darkText).bold()
            } else if line.isError {
                result = result + Text("\u{26A0} ").foregroundColor(errorRed) + Text(t).foregroundColor(errorRed).font(.system(size: 11, design: .monospaced))
            } else if t.hasPrefix("  [") {
                // BOM quantity line
                result = result + Text(t).foregroundColor(darkText).font(.system(size: 11, design: .monospaced))
            } else {
                result = result + Text(t).foregroundColor(subtleText)
            }
        }
        return result
    }

    private func stateLabel(_ state: StepState) -> String {
        switch state {
        case .pending: return "Pending"
        case .running: return "Running..."
        case .success: return "Complete"
        case .failed:  return "Failed"
        case .skipped: return "Skipped"
        }
    }

    private func iconForStep(_ step: BuildStep) -> String {
        switch step {
        case .ingest:  return "arrow.down.doc"
        case .store:   return "externaldrive"
        case .convert: return "arrow.triangle.2.circlepath"
        case .analyze: return "magnifyingglass"
        case .bom:     return "list.clipboard"
        case .price:   return "dollarsign.circle"
        case .ecn:     return "doc.badge.gearshape"
        case .credits: return "creditcard"
        case .quote:   return "building.2"
        case .order:   return "cart.fill"
        }
    }

    private func fillForState(_ state: StepState) -> Color {
        switch state {
        case .pending: return subtleText.opacity(0.3)
        case .running: return warnYellow
        case .success: return successGreen
        case .failed:  return errorRed
        case .skipped: return subtleText.opacity(0.5)
        }
    }

    private func labelForState(_ state: StepState) -> Color {
        switch state {
        case .pending: return subtleText.opacity(0.5)
        case .running: return warnYellow
        case .success: return successGreen
        case .failed:  return errorRed
        case .skipped: return subtleText
        }
    }

    // MARK: - Console Overlay

    private var consoleOverlay: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                RoundedRectangle(cornerRadius: 2).fill(Color.white.opacity(0.3)).frame(width: 40, height: 4)
                Spacer()
            }
            .padding(.top, 8).padding(.bottom, 4)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        coloredLogText
                            .font(.system(size: 11, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id("log-text")
                    }
                    .padding(10)
                }
                .onChange(of: pipeline.logLines.count) { _, _ in
                    withAnimation(.easeOut(duration: 0.1)) {
                        proxy.scrollTo("log-text", anchor: .bottom)
                    }
                }
            }

            HStack {
                Text("Press ` to close").font(.system(size: 10, design: .monospaced)).foregroundColor(Color.white.opacity(0.4))
                Spacer()
                Text("\(pipeline.logLines.count) lines").font(.system(size: 10, design: .monospaced)).foregroundColor(Color.white.opacity(0.4))
            }
            .padding(.horizontal, 12).padding(.bottom, 8)
        }
        .frame(height: 280)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(red: 0.12, green: 0.12, blue: 0.15))
                .shadow(color: Color.black.opacity(0.3), radius: 20, y: -5)
        )
        .padding(.horizontal, 12).padding(.bottom, 4)
    }

    private var coloredLogText: Text {
        var result = Text("")
        for (i, line) in pipeline.logLines.enumerated() {
            guard !line.text.isEmpty else { continue }
            if i > 0 { result = result + Text("\n") }
            let ts = Text("[\(line.formattedTime)] ").foregroundColor(Color.white.opacity(0.35))
            let color: Color = line.isError ? errorRed : line.isHighlight ? successGreen : Color(red: 0.72, green: 0.72, blue: 0.76)
            result = result + ts + Text(line.text).foregroundColor(color)
        }
        return result
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack(spacing: 12) {
            if pipeline.isComplete {
                let passed = pipeline.steps.filter { $0.state == .success }.count
                let failed = pipeline.steps.filter { $0.state == .failed }.count
                Label("\(passed) passed", systemImage: "checkmark.circle").foregroundColor(successGreen)
                if failed > 0 {
                    Label("\(failed) failed", systemImage: "xmark.circle").foregroundColor(errorRed)
                }
                Spacer()
                if pipeline.totalBOMCost > 0 {
                    Label("$\(String(format: "%.2f", pipeline.totalBOMCost))", systemImage: "cart")
                }
            } else if pipeline.isRunning {
                if let current = pipeline.steps.first(where: { $0.state == .running }) {
                    Label(current.id.rawValue, systemImage: "bolt.fill").foregroundColor(accent)
                }
                Spacer()
            } else {
                Label("Ready", systemImage: "bolt.fill").foregroundColor(accent)
                Spacer()
                Text("Press ` for console").foregroundColor(subtleText.opacity(0.6))
            }
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundColor(subtleText)
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 6).fill(cardBG))
    }
}
