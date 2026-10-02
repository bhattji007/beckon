import AppKit
import CoreText
import SwiftUI

// MARK: - Brand (direction 2b, "Smoked glass")

enum Brand {
    static let mint = Color(red: 61/255, green: 220/255, blue: 151/255)      // #3DDC97 — the only accent
    static let mintHover = Color(red: 91/255, green: 230/255, blue: 169/255)
    static let smoke = Color(red: 15/255, green: 17/255, blue: 20/255)      // #0F1114
    static let ink = Color(red: 242/255, green: 239/255, blue: 232/255)     // #F2EFE8
    static let ink2 = Color(red: 181/255, green: 179/255, blue: 173/255)    // #B5B3AD secondary
    static let ink3 = Color(red: 217/255, green: 214/255, blue: 207/255)    // #D9D6CF body
    static let denyBg = Color(red: 229/255, green: 72/255, blue: 77/255).opacity(0.22)
    static let denyText = Color(red: 1, green: 138/255, blue: 141/255)

    private static var registered = false
    private static var haveUI = false, haveMono = false
    static func registerFonts() {
        guard !registered else { return }; registered = true
        if let urls = Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: "Fonts") {
            for u in urls { CTFontManagerRegisterFontsForURL(u as CFURL, .process, nil) }
        }
        haveUI = NSFont(name: "FamiljenGrotesk-Regular", size: 12) != nil || NSFont(name: "Familjen Grotesk", size: 12) != nil
        haveMono = NSFont(name: "JetBrainsMono-Regular", size: 12) != nil
    }
    /// UI face: Familjen Grotesk (400/600/700), falling back to the system font.
    static func ui(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        guard haveUI else { return .system(size: size, weight: weight) }
        let name: String
        switch weight { case .bold, .heavy, .black: name = "FamiljenGrotesk-Bold"; case .semibold, .medium: name = "FamiljenGrotesk-SemiBold"; default: name = "FamiljenGrotesk-Regular" }
        if NSFont(name: name, size: size) != nil { return .custom(name, size: size) }
        return .custom("Familjen Grotesk", size: size).weight(weight)
    }
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        guard haveMono else { return .system(size: size, weight: weight, design: .monospaced) }
        return .custom(weight == .regular ? "JetBrainsMono-Regular" : "JetBrainsMono-Medium", size: size)
    }
}

/// The return-key mark: M46 14 V34 H18 M27 25 L18 34 L27 43 in a 64-unit box.
struct ReturnMark: Shape {
    func path(in r: CGRect) -> Path {
        let s = r.width / 64
        var p = Path()
        p.move(to: CGPoint(x: 46 * s, y: 14 * s)); p.addLine(to: CGPoint(x: 46 * s, y: 34 * s)); p.addLine(to: CGPoint(x: 18 * s, y: 34 * s))
        p.move(to: CGPoint(x: 27 * s, y: 25 * s)); p.addLine(to: CGPoint(x: 18 * s, y: 34 * s)); p.addLine(to: CGPoint(x: 27 * s, y: 43 * s))
        return p
    }
}
struct ReturnGlyph: View {
    var size: CGFloat = 14; var color: Color = Brand.mint; var glow = false; var lineWidth: CGFloat = 6.5
    var body: some View {
        ReturnMark().stroke(color, style: StrokeStyle(lineWidth: lineWidth * size / 64, lineCap: .round, lineJoin: .round))
            .frame(width: size, height: size)
            .shadow(color: glow ? Brand.mint.opacity(0.7) : .clear, radius: glow ? 5 : 0)
    }
}

// MARK: - Root

struct ToastStackView: View {
    @ObservedObject var store: Store
    private let maxRows = 5

    var body: some View {
        VStack(spacing: 0) {
            if let active = store.items.first {
                ActiveSection(item: active, total: store.items.count, focused: store.focused)
                let waiting = Array(store.items.dropFirst())
                if !waiting.isEmpty {
                    SectionLabel(text: "Waiting · \(waiting.count)")
                    ForEach(waiting.prefix(maxRows)) { item in
                        WaitingRow(item: item, expanded: store.hoveredItem == item.id)
                            .onHover { h in if h { store.hoveredItem = item.id } else if store.hoveredItem == item.id { store.hoveredItem = nil } }
                    }
                }
                FooterBar(item: active, focused: store.focused, more: max(0, waiting.count - maxRows))
            }
        }
        .frame(width: 440)
        .background(GlassPanel())
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
        .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.25)).frame(height: 1).padding(.horizontal, 14).blendMode(.plusLighter) }
        .shadow(color: .black.opacity(0.4), radius: 15, y: 12)
        .padding(16)
        .frame(width: OverlayController.panelWidth, alignment: .trailing)
        .foregroundStyle(Brand.ink)
        .preferredColorScheme(.dark)
    }
}

/// The card carries its own gradient (the mock's green→violet wash) under the smoked-glass tint,
/// so it looks the same over a dark terminal, a white page or a wallpaper. Blur behind keeps the glass feel.
struct GlassPanel: View {
    var body: some View {
        ZStack {
            VibrancyBlur()
            Color(red: 21/255, green: 19/255, blue: 30/255).opacity(0.72)                       // #15131E base
            Ellipse().fill(RadialGradient(colors: [Color(red: 46/255, green: 140/255, blue: 100/255).opacity(0.55), .clear], center: .center, startRadius: 0, endRadius: 260))
                .frame(width: 560, height: 420).position(x: 440 * 0.08, y: 760 * 0.06)         // 60% 45% at 8% 6%
            Ellipse().fill(RadialGradient(colors: [Color(red: 72/255, green: 52/255, blue: 150/255).opacity(0.70), .clear], center: .center, startRadius: 0, endRadius: 280))
                .frame(width: 560, height: 560).position(x: 440 * 0.92, y: 760 * 0.70)         // 55% 50% at 92% 70%
            Ellipse().fill(RadialGradient(colors: [Color(red: 30/255, green: 110/255, blue: 80/255).opacity(0.35), .clear], center: .center, startRadius: 0, endRadius: 200))
                .frame(width: 400, height: 340).position(x: 440 * 0.20, y: 760 * 0.95)         // 40% 35% at 20% 95%
            Color(red: 28/255, green: 30/255, blue: 34/255).opacity(0.45)                       // the glass tint from the spec
        }
        .clipped()
    }
}

/// Behind-window blur so the gradient still reads as glass over moving content.
struct VibrancyBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView(); v.material = .popover; v.blendingMode = .behindWindow; v.state = .active
        v.appearance = NSAppearance(named: .darkAqua)
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) {}
}

// MARK: - Active item

struct ActiveSection: View {
    @ObservedObject var item: PendingItem
    let total: Int
    let focused: Bool
    @FocusState private var replyFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HeaderRow(item: item, trailing: AnyView(HStack(spacing: 8) {
                Text(timeLabel(item)).font(Brand.ui(12))
                Text("1 of \(total)").font(Brand.mono(11))
            }))
            switch item.kind {
            case .permission(let tool, let input, let suggestions): permission(tool: tool, input: input, suggestions: suggestions)
            case .question(let qs, _): QuestionBody(item: item, questions: qs, focused: focused, compact: false)
            case .finished(let summary): FinishedBody(item: item, summary: summary, focused: focused, replyFocused: $replyFocused)
            case .info(let text): InfoBody(item: item, text: text, focused: focused)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .leading) {
            if focused {
                UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 0, bottomTrailingRadius: 2, topTrailingRadius: 2)
                    .fill(Brand.mint).frame(width: 2).padding(.vertical, 14)
                    .shadow(color: Brand.mint.opacity(0.7), radius: 5)
            }
        }
        .onChange(of: focused) { _, f in if f, case .finished = item.kind, item.session.canReceiveMessages { replyFocused = true } }
    }

    private func permission(tool: String, input: [String: Any], suggestions: [[String: Any]]) -> some View {
        let cwd = item.session.cwd
        let hint = PermissionSummary.alwaysHint(tool: tool, input: input, suggestions: suggestions, cwd: cwd)
        let foot = PermissionSummary.alwaysFootnote(tool: tool, input: input, suggestions: suggestions, cwd: cwd)
        return VStack(alignment: .leading, spacing: 10) {
            Text(PermissionSummary.title(tool: tool)).font(Brand.ui(15, .semibold)).tracking(-0.15)
            Text(PermissionSummary.chip(tool: tool, input: input, cwd: cwd).replacingOccurrences(of: " ⏎ ", with: "\n"))
                .font(Brand.mono(13)).lineSpacing(5).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                BButton(.primary, "Allow", trailing: AnyView(ReturnGlyph(size: 14, color: Brand.smoke, lineWidth: 7.5)), focused: focused) { Store.shared.allow(item, always: false) }
                BButton(.secondary, "Always", hint: hint) { Store.shared.allow(item, always: true) }
                    .help("Allow and add the rule \(foot.rule) \(foot.where_)")
                BButton(.deny, "Deny") { Store.shared.deny(item) }
                Spacer(minLength: 0)
                BButton(.ghost, "Claude ↗") { Store.shared.jump(to: item) }
            }
            HStack(spacing: 0) {
                Text("Always writes ").font(Brand.ui(12)).foregroundStyle(Brand.ink2)
                Text(foot.rule).font(Brand.mono(12)).foregroundStyle(Brand.ink).lineLimit(1).truncationMode(.middle)
                Text(" \(foot.where_)").font(Brand.ui(12)).foregroundStyle(Brand.ink2)
            }
        }
    }
}

// MARK: - Waiting rows

struct SectionLabel: View {
    let text: String
    var body: some View {
        HStack { Text(text.uppercased()).font(Brand.ui(11, .semibold)).tracking(0.45).foregroundStyle(Brand.ink2); Spacer() }
            .padding(.horizontal, 14).frame(height: 26)
            .overlay(alignment: .top) { Divider().overlay(Color.white.opacity(0.08)) }
    }
}

struct WaitingRow: View {
    @ObservedObject var item: PendingItem
    let expanded: Bool
    @State private var hover = false
    @FocusState private var replyFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Circle().fill(Color(nsColor: item.session.color)).frame(width: 7, height: 7)
                Text(item.session.projectName).font(Brand.ui(13, .semibold)).foregroundStyle(Brand.ink).lineLimit(1)
                HostGlyph(host: item.session.host, small: true)
                Text(item.oneLine).font(Brand.ui(13)).foregroundStyle(Brand.ink2).lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 4)
                Text(timeLabel(item)).font(Brand.ui(12)).foregroundStyle(Brand.ink2)
            }
            .frame(height: 36).contentShape(Rectangle())
            .onTapGesture { Store.shared.promote(item) }
            .help("Click to make this the active card")
            if expanded {
                VStack(alignment: .leading, spacing: 10) {
                    switch item.kind {
                    case .permission(let tool, let input, let suggestions):
                        Text(PermissionSummary.chip(tool: tool, input: input, cwd: item.session.cwd).replacingOccurrences(of: " ⏎ ", with: "\n"))
                            .font(Brand.mono(13)).lineSpacing(4).padding(.horizontal, 11).padding(.vertical, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.black.opacity(0.3)).clipShape(RoundedRectangle(cornerRadius: 9))
                        HStack(spacing: 6) {
                            BButton(.primary, "Allow") { Store.shared.allow(item, always: false) }
                            BButton(.secondary, "Always", hint: PermissionSummary.alwaysHint(tool: tool, input: input, suggestions: suggestions, cwd: item.session.cwd)) { Store.shared.allow(item, always: true) }
                            BButton(.deny, "Deny") { Store.shared.deny(item) }
                        }
                    case .question(let qs, _): QuestionBody(item: item, questions: qs, focused: false, compact: true)
                    case .finished(let summary): FinishedBody(item: item, summary: summary, focused: false, replyFocused: $replyFocused)
                    case .info(let text): InfoBody(item: item, text: text, focused: false)
                    }
                }
                .padding(.leading, 15).padding(.bottom, 14)
            }
        }
        .padding(.horizontal, 14)
        .background(hover ? Color.white.opacity(0.04) : .clear)
        .overlay(alignment: .top) { Divider().overlay(Color.white.opacity(0.06)) }
        .onHover { hover = $0 }
    }
}

// MARK: - Shared pieces

struct HeaderRow: View {
    @ObservedObject var item: PendingItem
    let trailing: AnyView
    var body: some View {
        HStack(spacing: 7) {
            Circle().fill(Color(nsColor: item.session.color)).frame(width: 7, height: 7)
            Text(item.session.projectName).font(Brand.ui(12, .semibold)).foregroundStyle(Brand.ink).lineLimit(1)
            Text("·")
            HStack(spacing: 5) { HostGlyph(host: item.session.host, small: false); Text(item.session.host.name).lineLimit(1) }
            if item.session.isSubagentActive { SubagentPill() }
            Spacer(minLength: 4)
            trailing
        }
        .font(Brand.ui(12)).foregroundStyle(Brand.ink2)
    }
}

struct HostGlyph: View {
    let host: Host; let small: Bool
    var body: some View {
        Text(host.code).font(Brand.mono(small ? 7 : 8, .medium)).foregroundStyle(Brand.ink)
            .frame(width: 14, height: 14).background(Color.white.opacity(0.12)).clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

struct SubagentPill: View {
    var body: some View {
        HStack(spacing: 5) {
            TimelineView(.animation(minimumInterval: 1/30)) { ctx in
                Circle().trim(from: 0, to: 0.75).stroke(Brand.mint, lineWidth: 1.5).frame(width: 7, height: 7)
                    .rotationEffect(.degrees(ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1) * 360))
            }
            Text("subagent")
        }
        .padding(.horizontal, 7).padding(.vertical, 1).background(Color.white.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

struct QuestionBody: View {
    @ObservedObject var item: PendingItem
    let questions: [Question]
    let focused: Bool
    let compact: Bool
    var body: some View {
        let i = min(item.currentQuestion, questions.count - 1)
        let q = questions[i]
        let picked = item.answers[i] ?? []
        VStack(alignment: .leading, spacing: 10) {
            Text(q.text).font(Brand.ui(15, .semibold)).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 4) {
                ForEach(Array(q.options.enumerated()), id: \.offset) { n, opt in
                    OptionRow(number: n + 1, label: opt.label, desc: opt.description, selected: picked.contains(n), multi: q.multiSelect) { Store.shared.choose(item, option: n) }
                }
            }
            HStack(spacing: 6) {
                Text(footnote(q: q, index: i)).font(Brand.ui(12)).foregroundStyle(Brand.ink2).lineLimit(1)
                Spacer(minLength: 0)
                if q.multiSelect {
                    BButton(.primary, i + 1 < questions.count ? "Next" : "Answer", trailing: AnyView(ReturnGlyph(size: 14, color: Brand.smoke, lineWidth: 7.5)), focused: focused) { Store.shared.advanceQuestion(item) }
                        .disabled(picked.isEmpty).opacity(picked.isEmpty ? 0.5 : 1)
                }
                if !compact { BButton(.ghost, "Claude ↗") { Store.shared.jump(to: item) } }
            }
        }
    }
    private func footnote(q: Question, index: Int) -> String {
        var s = q.multiSelect ? "Multiple choice · pick all that apply" : "Single choice · picking answers"
        if index + 1 < questions.count { s += " · next: \(questions[index + 1].header)" }
        return s
    }
}

struct OptionRow: View {
    let number: Int; let label: String; let desc: String; let selected: Bool; let multi: Bool; let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("\(number)").font(Brand.mono(11)).foregroundStyle(selected ? Brand.smoke : Brand.ink2)
                    .frame(width: 14, alignment: .leading)
                VStack(alignment: .leading, spacing: 1) {
                    Text(label).font(Brand.ui(13, .semibold)).foregroundStyle(Brand.ink)
                    if !desc.isEmpty { Text(desc).font(Brand.ui(12)).foregroundStyle(Brand.ink2).lineSpacing(2).fixedSize(horizontal: false, vertical: true) }
                }
                Spacer(minLength: 0)
                if multi { Image(systemName: selected ? "checkmark.square.fill" : "square").font(.system(size: 12)).foregroundStyle(selected ? Brand.mint : Brand.ink2) }
            }
            .padding(.horizontal, 11).padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? Brand.mint.opacity(0.22) : hover ? Brand.mint.opacity(0.16) : Color.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain).onHover { hover = $0 }
    }
}

struct FinishedBody: View {
    @ObservedObject var item: PendingItem
    let summary: String
    let focused: Bool
    var replyFocused: FocusState<Bool>.Binding
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(summary.isEmpty ? "Claude finished its turn." : summary).font(Brand.ui(13)).foregroundStyle(Brand.ink3).lineSpacing(3).lineLimit(5).fixedSize(horizontal: false, vertical: true)
            if item.sent {
                HStack(spacing: 6) { ReturnGlyph(size: 12); Text("Sent to \(item.session.projectName)").font(Brand.ui(12)).foregroundStyle(Brand.ink2) }
            } else if item.session.canReceiveMessages {
                HStack(spacing: 6) {
                    HStack(spacing: 6) {
                        TextField("Reply to \(item.session.projectName)", text: $item.replyText)
                            .textFieldStyle(.plain).font(Brand.ui(13)).foregroundStyle(Brand.ink)
                            .focused(replyFocused).onSubmit { Store.shared.sendReply(item) }
                        Button { Store.shared.sendReply(item) } label: {
                            ReturnGlyph(size: 12).frame(width: 24, height: 22).background(Brand.mint.opacity(0.18)).clipShape(RoundedRectangle(cornerRadius: 6))
                        }.buttonStyle(.plain)
                    }
                    .padding(.leading, 11).padding(.trailing, 4).frame(height: 30)
                    .background(Color.black.opacity(0.3)).clipShape(RoundedRectangle(cornerRadius: 9))
                    .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(focused && replyFocused.wrappedValue ? Brand.mint.opacity(0.6) : Color.white.opacity(0.08), lineWidth: 1))
                    BButton(.secondary, "Done") { Store.shared.dismiss(item) }
                    if !focused { } else { BButton(.ghost, "Claude ↗") { Store.shared.jump(to: item) } }
                }
                if let err = item.sendError { Text(err).font(Brand.ui(12)).foregroundStyle(Brand.denyText) }
            } else {
                HStack(spacing: 6) {
                    BButton(.secondary, "Open in \(item.session.host.name)") { Store.shared.jump(to: item) }
                    BButton(.ghost, "Dismiss") { Store.shared.dismiss(item) }
                    Spacer(minLength: 0)
                    Text("Session ended").font(Brand.ui(12)).foregroundStyle(Brand.ink2)
                }
            }
        }
    }
}

struct InfoBody: View {
    @ObservedObject var item: PendingItem
    let text: String
    let focused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(text).font(Brand.ui(13)).foregroundStyle(Brand.ink3).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                BButton(.secondary, "Open in \(item.session.host.name)") { Store.shared.jump(to: item) }
                BButton(.ghost, "Dismiss") { Store.shared.dismiss(item) }
            }
        }
    }
}

struct FooterBar: View {
    @ObservedObject var item: PendingItem
    let focused: Bool
    let more: Int
    var body: some View {
        HStack(spacing: 12) {
            ReturnGlyph(size: 16, glow: true)
            if focused { hints } else { HStack(spacing: 0) { Text("⌥Space").foregroundStyle(Brand.ink); Text(" to use keys") } }
            Spacer(minLength: 0)
            if focused { Text("esc").foregroundStyle(Brand.ink) }
            if more > 0 { Text("+\(more) more").font(Brand.ui(12, .semibold)).foregroundStyle(Brand.ink) }
        }
        .font(Brand.mono(11)).foregroundStyle(Brand.ink2)
        .padding(.horizontal, 14).frame(height: 38)
        .background(Color(red: 15/255, green: 17/255, blue: 20/255).opacity(0.35))
        .overlay(alignment: .top) { Divider().overlay(Color.white.opacity(0.08)) }
    }
    @ViewBuilder private var hints: some View {
        switch item.kind {
        case .permission: key("⏎", "allow", mint: true); key("⌥2", "always"); key("⌥3", "deny"); key("⌥J", "claude")
        case .question(let qs, _):
            let n = qs[min(item.currentQuestion, qs.count - 1)].options.count
            key("1–\(min(9, n))", "pick"); if qs[min(item.currentQuestion, qs.count - 1)].multiSelect { key("⏎", "confirm", mint: true) }; key("⌥J", "claude")
        case .finished: if item.session.canReceiveMessages { key("⏎", "send", mint: true); key("⌥1", "done") } else { key("⌥1", "open"); key("⌥2", "dismiss") }; key("⌥J", "claude")
        case .info: key("⌥1", "open"); key("⌥2", "dismiss")
        }
    }
    private func key(_ k: String, _ label: String, mint: Bool = false) -> some View {
        HStack(spacing: 4) { Text(k).foregroundStyle(mint ? Brand.mint : Brand.ink); Text(label) }
    }
}

// MARK: - Buttons

struct BButton: View {
    enum Kind { case primary, secondary, deny, ghost }
    let kind: Kind; let title: String; var hint: String = ""; var trailing: AnyView? = nil; var focused = false; let action: () -> Void
    @State private var hover = false
    init(_ kind: Kind, _ title: String, hint: String = "", trailing: AnyView? = nil, focused: Bool = false, action: @escaping () -> Void) {
        self.kind = kind; self.title = title; self.hint = hint; self.trailing = trailing; self.focused = focused; self.action = action
    }
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title).font(Brand.ui(13, kind == .primary ? .bold : .semibold)).lineLimit(1)
                if !hint.isEmpty { Text(hint).font(Brand.mono(11)).foregroundStyle(Brand.ink2).lineLimit(1) }
                if let trailing { trailing }
            }
            .foregroundStyle(fg)
            .padding(.horizontal, kind == .primary ? 12 : kind == .ghost ? 9 : 11).frame(height: 30)
            .background(bg).clipShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain).onHover { hover = $0 }
    }
    private var fg: Color {
        switch kind { case .primary: return Brand.smoke; case .deny: return hover ? Brand.denyText : Brand.ink; case .ghost: return hover ? Brand.ink : Brand.ink2; case .secondary: return Brand.ink }
    }
    private var bg: Color {
        switch kind {
        case .primary: return hover ? Brand.mintHover : Brand.mint
        case .secondary: return Color.white.opacity(hover ? 0.18 : 0.12)
        case .deny: return hover ? Brand.denyBg : Color.white.opacity(0.12)
        case .ghost: return hover ? Color.white.opacity(0.08) : .clear
        }
    }
}

func timeLabel(_ item: PendingItem) -> String {
    let s = Int(Date().timeIntervalSince(item.createdAt))
    if s < 5 { return "now" }; if s < 60 { return "\(s)s" }; return "\(s / 60)m"
}
