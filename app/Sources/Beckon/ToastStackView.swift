import SwiftUI

// MARK: - Stack

struct ToastStackView: View {
    @ObservedObject var store: Store
    private let maxVisible = 4

    var body: some View {
        VStack(alignment: .trailing, spacing: 10) {
            ForEach(Array(store.items.prefix(maxVisible).enumerated()), id: \.element.id) { idx, item in
                CardView(item: item, isTop: idx == 0, focused: store.focused && idx == 0,
                         expanded: idx == 0 || store.hoveredItem == item.id)
                    .onHover { h in store.hoveredItem = h ? item.id : (store.hoveredItem == item.id ? nil : store.hoveredItem) }
                    .scaleEffect(idx == 0 || store.hoveredItem == item.id ? 1 : 0.955, anchor: .top)
                    .opacity(idx == 0 ? 1 : 0.94)
            }
            if store.items.count > maxVisible {
                Pill(text: "+\(store.items.count - maxVisible) waiting")
            }
            if let top = store.items.first { HintRow(item: top, focused: store.focused) }
        }
        .padding(.horizontal, 30).padding(.top, 10).padding(.bottom, 24)
        .frame(width: OverlayController.panelWidth, alignment: .trailing)
        .preferredColorScheme(.dark)
    }
}

// MARK: - Card

struct CardView: View {
    @ObservedObject var item: PendingItem
    let isTop: Bool
    let focused: Bool
    let expanded: Bool
    private var color: Color { Color(nsColor: item.session.color) }
    @FocusState private var replyFocused: Bool

    var body: some View {
        HStack(spacing: 0) {
            Rectangle().fill(color).frame(width: 4)
            VStack(alignment: .leading, spacing: 8) {
                header
                if expanded { body_ } else { compactLine }
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
        }
        .frame(width: 380, alignment: .leading)
        .background(Glass())
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(focused ? color : Color.white.opacity(0.12), lineWidth: focused ? 2 : 1))
        .shadow(color: .black.opacity(0.28), radius: 18, y: 10)
        .shadow(color: focused ? color.opacity(0.35) : .clear, radius: 14)
        .onChange(of: focused) { _, f in if f, case .finished = item.kind, item.session.canReceiveMessages { replyFocused = true } }
        .onAppear { if focused, case .finished = item.kind { replyFocused = true } }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(item.session.projectName).font(.system(size: 13, weight: .semibold)).lineLimit(1)
            HostChip(host: item.session.host)
            if item.session.isSubagentActive { Text("› subagent").font(.system(size: 11)).foregroundStyle(.secondary) }
            Spacer(minLength: 4)
            Text(timeLabel).font(.system(size: 11)).foregroundStyle(.secondary)
            if item.session.hostPid != nil || item.session.host.bundleId != nil {
                IconButton(symbol: "arrow.up.forward.square", help: "Take me to Claude (⌥J) — opens \(item.session.host.name) and hands this back to the terminal") { Store.shared.jump(to: item) }
            }
            if !item.kind.isBlocking {
                IconButton(symbol: "xmark", help: "Dismiss") { Store.shared.dismiss(item) }
            }
        }
    }

    private var compactLine: some View {
        HStack(spacing: 6) {
            Text(item.eyebrow).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary).tracking(0.8)
            Text(item.oneLine).font(.system(size: 12)).foregroundStyle(.primary.opacity(0.85)).lineLimit(1)
        }
    }

    @ViewBuilder private var body_: some View {
        Text(item.eyebrow).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary).tracking(0.8)
        switch item.kind {
        case .permission(let tool, let input, let suggestions): permissionBody(tool: tool, input: input, suggestions: suggestions)
        case .question(let qs, _): questionBody(qs)
        case .finished(let summary): finishedBody(summary)
        case .info(let text): infoBody(text)
        }
    }

    // Permission
    private func permissionBody(tool: String, input: [String: Any], suggestions: [[String: Any]]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(PermissionSummary.headline(tool: tool)).font(.system(size: 14))
            HStack(spacing: 8) {
                Text(tool).font(.system(size: 12, weight: .semibold, design: .monospaced)).foregroundStyle(color)
                Text("›").foregroundStyle(.secondary)
                Text(PermissionSummary.chip(tool: tool, input: input)).font(.system(size: 12, design: .monospaced)).lineLimit(3).textSelection(.enabled)
            }
            .padding(.horizontal, 10).padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.07)).clipShape(RoundedRectangle(cornerRadius: 9))
            Text(PermissionSummary.abbreviate(item.session.cwd)).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            HStack(spacing: 8) {
                ActionButton(title: "Allow", key: focused ? "⌥1" : nil, style: .primary(color)) { Store.shared.allow(item, always: false) }
                ActionButton(title: PermissionSummary.fileTools.contains(tool) ? "Always in project" : "Always", key: focused ? "⌥2" : nil, style: .neutral) { Store.shared.allow(item, always: true) }
                    .help(PermissionSummary.describeAlways(tool: tool, input: input, suggestions: suggestions, cwd: item.session.cwd))
                ActionButton(title: "Deny", key: focused ? "⌥3" : nil, style: .neutral) { Store.shared.deny(item) }
            }
            JumpRow(item: item, focused: focused)
        }
    }

    // Question
    private func questionBody(_ qs: [Question]) -> some View {
        let i = min(item.currentQuestion, qs.count - 1)
        let q = qs[i]
        return VStack(alignment: .leading, spacing: 10) {
            if qs.count > 1 { Text("Question \(i + 1) of \(qs.count)").font(.system(size: 11)).foregroundStyle(.secondary) }
            Text(q.text).font(.system(size: 14)).fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 4) {
                ForEach(Array(q.options.enumerated()), id: \.offset) { n, opt in
                    let selected = (item.answers[i] ?? []).contains(n)
                    Button { Store.shared.choose(item, option: n) } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Text("\(n + 1)").font(.system(size: 11, weight: .semibold, design: .rounded))
                                .frame(width: 20, height: 20).background(selected ? color : Color.white.opacity(0.1)).clipShape(RoundedRectangle(cornerRadius: 6))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(opt.label).font(.system(size: 13, weight: .medium))
                                if !opt.description.isEmpty { Text(opt.description).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                            }
                            Spacer(minLength: 0)
                            if q.multiSelect { Image(systemName: selected ? "checkmark.square.fill" : "square").foregroundStyle(selected ? color : .secondary) }
                        }
                        .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                        .background(selected ? color.opacity(0.18) : Color.white.opacity(0.05)).clipShape(RoundedRectangle(cornerRadius: 9))
                    }.buttonStyle(.plain)
                }
            }
            if q.multiSelect {
                HStack { Spacer(); ActionButton(title: i + 1 < qs.count ? "Next" : "Answer", key: focused ? "⏎" : nil, style: .primary(color)) { Store.shared.advanceQuestion(item) }
                        .disabled((item.answers[i] ?? []).isEmpty) }
            }
            JumpRow(item: item, focused: focused)
        }
    }

    // Finished
    private func finishedBody(_ summary: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(summary.isEmpty ? "Claude finished its turn." : summary).font(.system(size: 13)).lineLimit(4).fixedSize(horizontal: false, vertical: true)
            if item.sent {
                HStack(spacing: 6) { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green); Text("Sent → \(item.session.projectName)").font(.system(size: 12)) }
            } else if item.session.canReceiveMessages {
                HStack(spacing: 8) {
                    TextField("Reply to \(item.session.projectName)…", text: $item.replyText)
                        .textFieldStyle(.plain).font(.system(size: 13))
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .background(Color.white.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius: 9))
                        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(focused && replyFocused ? color : .clear, lineWidth: 1.5))
                        .focused($replyFocused)
                        .onSubmit { Store.shared.sendReply(item) }
                    ActionButton(title: "Done", key: focused ? "⌥1" : nil, style: .neutral) { Store.shared.dismiss(item) }
                }
                if let err = item.sendError {
                    HStack(spacing: 6) { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow); Text(err).font(.system(size: 11)).foregroundStyle(.secondary) }
                }
                JumpRow(item: item, focused: focused)
            } else {
                HStack(spacing: 8) {
                    ActionButton(title: "Open in \(item.session.host.name)", key: focused ? "⌥1" : nil, style: .primary(color)) { Store.shared.jump(to: item) }
                    ActionButton(title: "Dismiss", key: focused ? "⌥2" : nil, style: .neutral) { Store.shared.dismiss(item) }
                }
            }
        }
    }

    private func infoBody(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(text).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                ActionButton(title: "Open in \(item.session.host.name)", key: focused ? "⌥1" : nil, style: .primary(color)) { Store.shared.jump(to: item) }
                ActionButton(title: "Dismiss", key: focused ? "⌥2" : nil, style: .neutral) { Store.shared.dismiss(item) }
            }
        }
    }

    private var timeLabel: String {
        let s = Int(Date().timeIntervalSince(item.createdAt))
        if s < 5 { return "now" }; if s < 60 { return "\(s)s" }; return "\(s / 60)m"
    }
}

// MARK: - Bits

struct HostChip: View {
    let host: Host
    var body: some View {
        HStack(spacing: 4) { Image(systemName: host.glyph).font(.system(size: 9, weight: .semibold)); Text(host.name).font(.system(size: 10.5, weight: .medium)) }
            .foregroundStyle(.secondary).padding(.horizontal, 6).padding(.vertical, 2)
            .background(Color.white.opacity(0.08)).clipShape(Capsule())
    }
}

struct Pill: View {
    let text: String
    var body: some View {
        Text(text).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
            .padding(.horizontal, 10).padding(.vertical, 4).background(Glass()).clipShape(Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.12)))
    }
}

struct HintRow: View {
    @ObservedObject var item: PendingItem
    let focused: Bool
    var body: some View {
        HStack(spacing: 8) {
            if focused {
                switch item.kind {
                case .permission: Key("⌥1"); Text("Allow"); Dot(); Key("⌥2"); Text("Always"); Dot(); Key("⌥3"); Text("Deny"); Dot(); Key("⌥J"); Text("to Claude"); Dot(); Key("Esc"); Text("back")
                case .question(let qs, _):
                    Key("1–\(min(9, qs[min(item.currentQuestion, qs.count - 1)].options.count))"); Text("pick"); Dot(); Key("Esc"); Text("back")
                case .finished: Key("⏎"); Text("send"); Dot(); Key("⌥1"); Text("Done"); Dot(); Key("⌥J"); Text("to Claude"); Dot(); Key("Esc"); Text("back")
                case .info: Key("⌥1"); Text("Open"); Dot(); Key("Esc"); Text("back")
                }
            } else {
                Key("⌥Space"); Text("focus"); Dot(); Text("click to answer")
            }
        }
        .font(.system(size: 11)).foregroundStyle(.secondary)
        .padding(.horizontal, 12).padding(.vertical, 6).background(Glass()).clipShape(Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.1)))
        .padding(.trailing, 2)
    }
    private func Dot() -> some View { Text("·").foregroundStyle(.tertiary) }
}

/// Labelled "Take me to Claude" control shown under the actions of every card.
struct JumpRow: View {
    @ObservedObject var item: PendingItem
    let focused: Bool
    @State private var hover = false
    var body: some View {
        Button { Store.shared.jump(to: item) } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.up.forward.square").font(.system(size: 11, weight: .semibold))
                Text("Take me to Claude in \(item.session.host.name)").font(.system(size: 11.5, weight: .medium))
                if focused { Key("⌥J") }
            }
            .foregroundStyle(hover ? .primary : .secondary)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Color.white.opacity(hover ? 0.1 : 0.04)).clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain).onHover { hover = $0 }
        .help("Opens \(item.session.host.name) and hands this request back to the terminal prompt")
    }
}

struct IconButton: View {
    let symbol: String; let help: String; let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 10, weight: .bold))
                .foregroundStyle(hover ? .primary : .secondary)
                .frame(width: 20, height: 20)
                .background(Color.white.opacity(hover ? 0.14 : 0)).clipShape(RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain).onHover { hover = $0 }.help(help)
    }
}

struct Key: View {
    let s: String
    init(_ s: String) { self.s = s }
    var body: some View {
        Text(s).font(.system(size: 10.5, weight: .medium)).padding(.horizontal, 5).padding(.vertical, 1)
            .background(Color.white.opacity(0.1)).overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.white.opacity(0.18))).clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

struct ActionButton: View {
    enum Style { case primary(Color), neutral }
    let title: String; let key: String?; let style: Style; let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title).font(.system(size: 12.5, weight: .medium)).lineLimit(1)
                if let key { Key(key) }
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(background).clipShape(RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Color.white.opacity(hover ? 0.22 : 0.1)))
        }
        .buttonStyle(.plain).onHover { hover = $0 }
    }
    private var background: Color {
        switch style { case .primary(let c): return c.opacity(hover ? 1 : 0.9); case .neutral: return Color.white.opacity(hover ? 0.16 : 0.1) }
    }
}

/// Dark glass: vibrancy behind the window + a tint so text stays legible on any background.
struct Glass: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView(); v.material = .hudWindow; v.blendingMode = .behindWindow; v.state = .active
        v.appearance = NSAppearance(named: .darkAqua)
        let tint = NSView(); tint.wantsLayer = true; tint.layer?.backgroundColor = NSColor(white: 0.11, alpha: 0.72).cgColor
        tint.autoresizingMask = [.width, .height]; tint.frame = v.bounds; v.addSubview(tint)
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) {}
}
