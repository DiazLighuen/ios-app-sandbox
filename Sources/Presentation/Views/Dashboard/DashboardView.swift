import SwiftUI

// MARK: - Main View

struct DashboardView: View {
    @StateObject private var viewModel = DashboardViewModel()

    private let columns = [GridItem(.adaptive(minimum: 300), spacing: 16)]

    var body: some View {
        NavigationStack {
            ScrollView {
                if let dashboard = viewModel.dashboard {
                    VStack(alignment: .leading, spacing: 20) {
                        SummarySection(dashboard: dashboard)
                        if let quota = dashboard.youtubeQuota {
                            YoutubeQuotaCard(quota: quota)
                        }
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(dashboard.containers.items) { container in
                                ContainerCard(
                                    container: container,
                                    isToggling: viewModel.togglingContainers.contains(container.name)
                                ) {
                                    Task { await viewModel.toggleContainer(container) }
                                }
                            }
                        }
                    }
                    .padding()
                } else if !viewModel.isLoading {
                    ContentUnavailableView(
                        "dashboard.noData.title".loc,
                        systemImage: "exclamationmark.triangle",
                        description: Text("dashboard.noData.desc".loc)
                    )
                    .padding(.top, 80)
                }
            }
            .overlay {
                if viewModel.isLoading {
                    ProgressView("loading".loc)
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .navigationTitle("tab.dashboard".loc)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await viewModel.load() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(viewModel.isLoading)
                }
            }
            .alert("error".loc, isPresented: .constant(viewModel.error != nil)) {
                Button("ok".loc) { viewModel.error = nil }
            } message: {
                Text(viewModel.error?.localizedDescription ?? "")
            }
        }
        .task { await viewModel.load() }
    }
}

// MARK: - Summary Section

private struct SummarySection: View {
    let dashboard: DashboardData

    private var containers: [ContainerInfo] { dashboard.containers.items }
    private var running: Int       { containers.filter(\.running).count }
    private var totalCPU: Double   { containers.reduce(0) { $0 + $1.cpuPct } }
    private var totalMemRSS: Int   { containers.reduce(0) { $0 + $1.memRss } }
    private var totalMemLimit: Int { containers.reduce(0) { $0 + $1.memLimit } }
    private var memPct: Double     { totalMemLimit > 0 ? Double(totalMemRSS) / Double(totalMemLimit) : 0 }
    private var totalNetRx: Int    { containers.reduce(0) { $0 + $1.netRx } }
    private var totalNetTx: Int    { containers.reduce(0) { $0 + $1.netTx } }
    private var totalBlkR: Int     { containers.reduce(0) { $0 + $1.blkRead } }
    private var totalBlkW: Int     { containers.reduce(0) { $0 + $1.blkWrite } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Row 1: Containers · CPU · Memory
            HStack(spacing: 0) {
                SummaryStat(
                    label: "dashboard.summary.containers".loc,
                    value: "\(running)/\(containers.count)",
                    sub: "status.running".loc
                )
                Divider().padding(.vertical, 10)
                SummaryStat(
                    label: "dashboard.summary.cpu".loc,
                    value: String(format: "%.1f%%", totalCPU),
                    bar: min(totalCPU / 100, 1),
                    barColor: cpuBarColor(totalCPU)
                )
                Divider().padding(.vertical, 10)
                SummaryStat(
                    label: "dashboard.summary.memory".loc,
                    value: formatBytes(totalMemRSS),
                    sub: "\("dashboard.of".loc) \(formatBytes(totalMemLimit))",
                    bar: memPct,
                    barColor: memBarColor(memPct)
                )
            }

            Divider().padding(.horizontal, 14)

            // Row 2: Network · Disk I/O
            HStack(spacing: 0) {
                SummaryStat(
                    label: "dashboard.summary.network".loc,
                    value: "↓ \(formatBytes(totalNetRx))",
                    sub: "↑ \(formatBytes(totalNetTx))"
                )
                Divider().padding(.vertical, 10)
                SummaryStat(
                    label: "dashboard.summary.disk".loc,
                    value: "R: \(formatBytes(totalBlkR))",
                    sub: "W: \(formatBytes(totalBlkW))"
                )
            }
        }
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color(.separator).opacity(0.4), lineWidth: 0.5)
        )
    }
}

private struct SummaryStat: View {
    let label: String
    let value: String
    var sub: String?       = nil
    var bar: Double?       = nil
    var barColor: Color    = .blue

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(0.8)
                .textCase(.uppercase)
            Text(value)
                .font(.system(.callout, design: .monospaced, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let sub {
                Text(sub)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            if let bar {
                MetricBar(fraction: bar, color: barColor)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

// MARK: - Container Card

private struct ContainerCard: View {
    let container: ContainerInfo
    let isToggling: Bool
    let onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(container.name)
                        .font(.headline)
                    Text(container.image)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if container.controllable {
                    ToggleButton(running: container.running, isToggling: isToggling, onToggle: onToggle)
                        .padding(.trailing, 6)
                }
                StatusBadge(running: container.running)
            }
            .padding([.horizontal, .top], 14)
            .padding(.bottom, 12)

            Divider()
                .padding(.horizontal, 14)

            VStack(spacing: 12) {
                // CPU
                MetricSection(label: "dashboard.card.cpu".loc) {
                    HStack {
                        MetricBar(fraction: min(container.cpuPct / 100, 1), color: cpuBarColor(container.cpuPct))
                        Text(container.cpuFormatted)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 40, alignment: .trailing)
                    }
                }

                // MEMORY
                MetricSection(label: "dashboard.card.memory".loc) {
                    HStack {
                        MetricBar(fraction: min(container.memPct / 100, 1), color: memBarColor(container.memPct / 100))
                        Text(String(format: "%.1f%%", container.memPct))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 40, alignment: .trailing)
                    }
                    Text("\(formatBytes(container.memRss)) \("dashboard.of".loc) \(formatBytes(container.memLimit))")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }

                // NETWORK
                MetricSection(label: "dashboard.card.network".loc) {
                    HStack(spacing: 8) {
                        StatBox(label: "↓ IN",  value: formatBytes(container.netRx))
                        StatBox(label: "↑ OUT", value: formatBytes(container.netTx))
                    }
                }

                // DISK I/O
                MetricSection(label: "dashboard.card.disk".loc) {
                    HStack(spacing: 8) {
                        StatBox(label: "READ",  value: formatBytes(container.blkRead))
                        StatBox(label: "WRITE", value: formatBytes(container.blkWrite))
                    }
                }

                // PROCESSES
                HStack {
                    Text("dashboard.card.processes".loc)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .tracking(1)
                    Spacer()
                    Text("\(container.pids)")
                        .font(.system(.callout, design: .monospaced, weight: .medium))
                }
            }
            .padding(14)
        }
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color(.separator).opacity(0.4), lineWidth: 0.5)
        )
    }
}

// MARK: - Reusable Components

private struct ToggleButton: View {
    let running: Bool
    let isToggling: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            if isToggling {
                ProgressView()
                    .frame(width: 28, height: 28)
            } else {
                Image(systemName: running ? "stop.fill" : "play.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(running ? Color.red : Color.green)
                    .frame(width: 28, height: 28)
                    .background((running ? Color.red : Color.green).opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
            }
        }
        .disabled(isToggling)
        .buttonStyle(.plain)
    }
}

private struct StatusBadge: View {
    let running: Bool

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(running ? Color.green : Color.red)
                .frame(width: 7, height: 7)
            Text(running ? "status.running".loc : "status.stopped".loc)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(running ? Color.green : Color.red)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background((running ? Color.green : Color.red).opacity(0.12), in: Capsule())
    }
}

private struct MetricSection<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(1)
            content
        }
    }
}

private struct MetricBar: View {
    let fraction: Double
    let color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(.systemFill))
                RoundedRectangle(cornerRadius: 2)
                    .fill(color)
                    .frame(width: max(4, geo.size.width * fraction))
            }
        }
        .frame(height: 5)
    }
}

private struct StatBox: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .tracking(0.5)
            Text(value)
                .font(.system(.caption, design: .monospaced, weight: .medium))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - YouTube Quota Card

private struct YoutubeQuotaCard: View {
    let quota: DashboardData.YoutubeQuota

    private var barColor: Color {
        switch quota.percent {
        case ..<60:  return .blue
        case ..<85:  return .orange
        default:     return .red
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("dashboard.quota.title".loc, systemImage: "play.tv")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .tracking(0.6)
                Spacer()
                Text("dashboard.quota.reset".loc + " \(quota.resetDate)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            MetricBar(fraction: min(quota.percent / 100, 1), color: barColor)
                .frame(height: 6)

            HStack {
                Text(String(format: "%.1f%%", quota.percent))
                    .font(.system(.callout, design: .monospaced, weight: .bold))
                Spacer()
                Text("\(quota.used) / \(quota.limit) units")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color(.separator).opacity(0.4), lineWidth: 0.5)
        )
    }
}

// MARK: - Color helpers

private func cpuBarColor(_ pct: Double) -> Color {
    switch pct {
    case ..<50: return .blue
    case ..<80: return .orange
    default:    return .red
    }
}

private func memBarColor(_ fraction: Double) -> Color {
    switch fraction {
    case ..<0.6: return .blue
    case ..<0.85: return .orange
    default:     return .red
    }
}
