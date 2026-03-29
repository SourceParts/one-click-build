import SwiftUI

struct BuildView: View {
    @EnvironmentObject var pipeline: BuildPipeline
    @State private var githubURL = "https://github.com/FugLong/OpenChord"

    private let neon = Color(red: 0.0, green: 1.0, blue: 0.0)
    private let dimGreen = Color(red: 0.0, green: 0.6, blue: 0.0)
    private let termBG = Color(red: 0.02, green: 0.02, blue: 0.02)

    var body: some View {
        VStack(spacing: 0) {
            // ASCII banner
            banner
                .padding(.top, 16)
                .padding(.bottom, 8)

            // URL input
            urlField
                .padding(.horizontal, 24)
                .padding(.bottom, 12)

            // BUILD button
            buildButton
                .padding(.horizontal, 24)
                .padding(.bottom, 12)

            // Step indicators
            stepStrip
                .padding(.horizontal, 24)
                .padding(.bottom, 8)

            // Divider
            Rectangle()
                .fill(dimGreen)
                .frame(height: 1)
                .padding(.horizontal, 24)

            // Terminal log
            terminalLog
                .padding(.horizontal, 24)
                .padding(.vertical, 8)

            // Bottom status bar
            statusBar
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
        }
        .background(termBG)
        .preferredColorScheme(.dark)
    }

    // MARK: - Banner

    private var banner: some View {
        Text("""
         ____  _   _ ___ _     ____
        | __ )| | | |_ _| |   |  _ \\
        |  _ \\| | | || || |   | | | |
        | |_) | |_| || || |___| |_| |
        |____/ \\___/|___|_____|____/
        """)
        .font(.system(size: 11, design: .monospaced))
        .foregroundColor(neon)
        .multilineTextAlignment(.center)
    }

    // MARK: - URL Field

    private var urlField: some View {
        HStack(spacing: 8) {
            Text(">")
                .font(.system(size: 14, design: .monospaced))
                .foregroundColor(neon)

            TextField("https://github.com/...", text: $githubURL)
                .textFieldStyle(.plain)
                .font(.system(size: 14, design: .monospaced))
                .foregroundColor(neon)
                .disabled(pipeline.isRunning)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .stroke(dimGreen, lineWidth: 1)
        )
    }

    // MARK: - BUILD Button

    private var buildButton: some View {
        Button(action: {
            guard !pipeline.isRunning, !githubURL.isEmpty else { return }
            Task {
                await pipeline.run(githubURL: githubURL)
            }
        }) {
            HStack {
                if pipeline.isRunning {
                    ProgressView()
                        .controlSize(.small)
                        .tint(neon)
                    Text("BUILDING...")
                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                } else if pipeline.isComplete {
                    Text("[ BUILD COMPLETE ]")
                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                } else {
                    Text("[ BUILD ]")
                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                }
            }
            .foregroundColor(pipeline.isRunning ? dimGreen : neon)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(pipeline.isRunning ? dimGreen : neon, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .disabled(pipeline.isRunning || githubURL.isEmpty)
    }

    // MARK: - Step Strip

    private var stepStrip: some View {
        HStack(spacing: 4) {
            ForEach(pipeline.steps) { step in
                VStack(spacing: 2) {
                    stepIndicator(step.state)
                    Text(step.id.rawValue)
                        .font(.system(size: 7, design: .monospaced))
                        .foregroundColor(colorForState(step.state))
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func stepIndicator(_ state: StepState) -> some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(colorForState(state))
            .frame(width: 12, height: 12)
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .stroke(dimGreen.opacity(0.5), lineWidth: 0.5)
            )
    }

    private func colorForState(_ state: StepState) -> Color {
        switch state {
        case .pending: return Color.gray.opacity(0.3)
        case .running: return Color.yellow
        case .success: return neon
        case .failed:  return Color.red
        case .skipped: return Color.gray.opacity(0.5)
        }
    }

    // MARK: - Terminal Log

    private var terminalLog: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(pipeline.logLines) { line in
                        logLineView(line)
                            .id(line.id)
                    }
                }
                .padding(8)
            }
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.black)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(dimGreen.opacity(0.3), lineWidth: 1)
                    )
            )
            .onChange(of: pipeline.logLines.count) { _, _ in
                if let last = pipeline.logLines.last {
                    withAnimation(.easeOut(duration: 0.1)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private func logLineView(_ line: LogLine) -> some View {
        HStack(alignment: .top, spacing: 0) {
            if !line.text.isEmpty {
                Text("[\(line.formattedTime)]")
                    .foregroundColor(dimGreen.opacity(0.6))

                if let step = line.step {
                    Text(" \(step.icon) ")
                        .foregroundColor(dimGreen)
                } else {
                    Text("   ")
                }

                Text(line.text)
                    .foregroundColor(
                        line.isError ? .red :
                        line.isHighlight ? neon :
                        dimGreen
                    )
            }
        }
        .font(.system(size: 11, design: .monospaced))
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack {
            if pipeline.isComplete || pipeline.isRunning {
                Text("FACTORY: \(pipeline.factory)")
                Spacer()
                if pipeline.totalBOMCost > 0 {
                    Text("BOM: $\(String(format: "%.2f", pipeline.totalBOMCost))")
                    Text("|")
                }
                if pipeline.creditBalance > 0 {
                    Text("CREDITS: \(pipeline.creditBalance)")
                }
            } else {
                Text("READY")
                Spacer()
                Text("source.parts")
            }
        }
        .font(.system(size: 10, design: .monospaced))
        .foregroundColor(dimGreen)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.black.opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: 2)
                        .stroke(dimGreen.opacity(0.2), lineWidth: 0.5)
                )
        )
    }
}
