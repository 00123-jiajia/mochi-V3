import AppKit
import MochiCore
import SwiftUI

struct BubbleShape: Shape {
    var radius: CGFloat = AppConfig.bubbleRadius
    var beakY: CGFloat
    var pointsRight: Bool

    func path(in rect: CGRect) -> Path {
        let beak = AppConfig.beakWidth
        let body = pointsRight
            ? CGRect(x: rect.minX, y: rect.minY, width: max(1, rect.width - beak), height: rect.height)
            : CGRect(x: rect.minX + beak, y: rect.minY, width: max(1, rect.width - beak), height: rect.height)
        let corner = min(radius, min(body.width, body.height) / 2)
        let edgeX = pointsRight ? body.maxX : body.minX
        let sign: CGFloat = pointsRight ? 1 : -1
        let lower = corner + 8
        let upper = max(lower, rect.height - corner - 8)
        let mid = min(max(beakY, lower), upper)
        var path = Path()
        path.move(to: CGPoint(x: body.minX + corner, y: body.minY))
        path.addLine(to: CGPoint(x: body.maxX - corner, y: body.minY))
        path.addArc(
            center: CGPoint(x: body.maxX - corner, y: body.minY + corner),
            radius: corner,
            startAngle: .degrees(-90),
            endAngle: .degrees(0),
            clockwise: false
        )
        if pointsRight {
            appendBeak(&path, edgeX: edgeX, sign: sign, mid: mid, downward: true)
        }
        path.addLine(to: CGPoint(x: body.maxX, y: body.maxY - corner))
        path.addArc(
            center: CGPoint(x: body.maxX - corner, y: body.maxY - corner),
            radius: corner,
            startAngle: .degrees(0),
            endAngle: .degrees(90),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: body.minX + corner, y: body.maxY))
        path.addArc(
            center: CGPoint(x: body.minX + corner, y: body.maxY - corner),
            radius: corner,
            startAngle: .degrees(90),
            endAngle: .degrees(180),
            clockwise: false
        )
        if !pointsRight {
            appendBeak(&path, edgeX: edgeX, sign: sign, mid: mid, downward: false)
        }
        path.addLine(to: CGPoint(x: body.minX, y: body.minY + corner))
        path.addArc(
            center: CGPoint(x: body.minX + corner, y: body.minY + corner),
            radius: corner,
            startAngle: .degrees(180),
            endAngle: .degrees(270),
            clockwise: false
        )
        path.closeSubpath()
        return path
    }

    /// Beak root curves and a 2.8pt tip, taken from the liquid-glass popup SVG.
    private func appendBeak(_ path: inout Path, edgeX: CGFloat, sign: CGFloat, mid: CGFloat, downward: Bool) {
        func point(_ dx: CGFloat, _ dy: CGFloat) -> CGPoint {
            CGPoint(x: edgeX + sign * dx, y: mid + (downward ? dy : -dy))
        }
        path.addLine(to: point(0, -9.5))
        path.addCurve(to: point(3.5, -5.5), control1: point(0, -7.5), control2: point(1.5, -6.5))
        path.addCurve(to: point(9.2, -1.2), control1: point(6.5, -4), control2: point(8.5, -2.5))
        let chord: CGFloat = 2.53
        let center = CGPoint(x: edgeX + sign * (9.2 - chord), y: mid)
        let start = point(9.2, -1.2)
        let end = point(9.2, 1.2)
        let startAngle = Angle.radians(atan2(start.y - center.y, start.x - center.x))
        let endAngle = Angle.radians(atan2(end.y - center.y, end.x - center.x))
        path.addArc(
            center: center,
            radius: AppConfig.beakTipRadius,
            startAngle: startAngle,
            endAngle: endAngle,
            clockwise: downward ? false : true
        )
        path.addCurve(to: point(3.5, 5.5), control1: point(8.5, 2.5), control2: point(6.5, 4))
        path.addCurve(to: point(0, 9.5), control1: point(1.5, 6.5), control2: point(0, 7.5))
    }
}

struct BubbleChoice: Identifiable, Equatable {
    var id: String
    var label: String
}

enum BubbleKind {
    case card, alert, picker, label
}

@MainActor
final class BubbleModel: ObservableObject {
    @Published var kind: BubbleKind = .card
    @Published var title = ""
    @Published var appName = ""
    @Published var source = "cursor"
    @Published var status = ""
    @Published var taskStatus = ""
    @Published var summary = ""
    @Published var answer = ""
    @Published var choicePrompt = ""
    @Published var awaitingAnswer = false
    @Published var answerExpanded = false
    @Published var updated: Double = 0
    @Published var options: [BubbleChoice] = []
    @Published var icon: NSImage?
    @Published var beakY: CGFloat = 28
    @Published var pointsRight = true
    @Published var bodyWidth: CGFloat = 270
    @Published var summaryHeight: CGFloat = 14
    @Published var computedHeight: CGFloat = 44
    @Published var maxHeight: CGFloat = 360
    var taskID = ""
    var requestID = ""
    var questionID = ""
    var taskKind = ""
    var onChoice: ((BubbleChoice) -> Void)?
    var onOpen: (() -> Void)?
    var onPick: ((String) -> Void)?
    var onLayout: (() -> Void)?
}

struct BubbleFace: View {
    @ObservedObject var model: BubbleModel
    @ObservedObject private var pickerMenu = PickerMenu.shared

    var body: some View {
        let plate = RoundedRectangle(cornerRadius: AppConfig.bubbleRadius, style: .continuous)
        HStack(spacing: 0) {
            if !model.pointsRight {
                Color.clear.frame(width: AppConfig.beakWidth)
            }
            content
                .frame(width: model.bodyWidth, height: model.computedHeight, alignment: .top)
            if model.pointsRight {
                Color.clear.frame(width: AppConfig.beakWidth)
            }
        }
        .background {
            // Same regular liquid glass as the capsule. Standard shapes merge into the beak.
            // A custom shape here was painting a solid blue plate.
            GlassEffectContainer(spacing: 24) {
                plate
                    .fill(Color.clear)
                    .glassEffect(.regular.tint(nil), in: plate)
                    .padding(model.pointsRight ? .trailing : .leading, 2)
                Capsule()
                    .fill(Color.clear)
                    .frame(width: AppConfig.beakHeight, height: AppConfig.beakWidth + 8)
                    .glassEffect(.regular.tint(nil), in: Capsule())
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: model.pointsRight ? .trailing : .leading)
                    .offset(y: model.beakY - model.computedHeight / 2)
            }
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.kind {
        case .picker:
            picker
        case .label:
            Text(model.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .padding(.horizontal, AppConfig.bubblePadX)
                .padding(.vertical, AppConfig.bubblePadY)
        case .card, .alert:
            card
        }
    }

    /// The icon row opens the source app. 展开 grows the card downward and scrolls.
    /// Allow / Deny keep their own actions.
    private var card: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: CardColumn.gap) {
                icon(model.icon, source: model.source, side: 16)
                    .frame(width: CardColumn.mark, alignment: .leading)
                Text(headerName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: CardColumn.gap)
                if !model.status.isEmpty {
                    Text(model.status)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(statusTint)
                        .lineLimit(1)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(statusTint.opacity(0.16)))
                        .accessibilityLabel(model.status)
                }
                if !ageLabel.isEmpty {
                    Text(ageLabel)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { model.onOpen?() }
            if model.answerExpanded {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        qaRow(label: "Q：", text: model.summary, lines: 20, pending: false)
                        answerBody(lines: 40)
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .scrollContentBackground(.hidden)
                .frame(height: max(28, model.summaryHeight))
            } else {
                qaRow(label: "Q：", text: model.summary, lines: 2, pending: false)
                    .contentShape(Rectangle())
                    .onTapGesture { model.onOpen?() }
                answerBody(lines: thinking ? 1 : 2)
            }
            if canExpand {
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    Button(model.answerExpanded ? "收起" : "展开") {
                        model.answerExpanded.toggle()
                        model.onLayout?()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.primary.opacity(0.08)))
                    .accessibilityLabel(model.answerExpanded ? "收起" : "展开")
                }
            }
            if !model.options.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    if !model.choicePrompt.isEmpty {
                        Text(model.choicePrompt)
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .truncationMode(.tail)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.leading, CardColumn.mark + CardColumn.gap)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    ForEach(model.options) { option in
                        HStack(spacing: CardColumn.gap) {
                            Color.clear.frame(width: CardColumn.mark)
                            Button {
                                model.onChoice?(option)
                            } label: {
                                Text(option.label)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.primary)
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background {
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .fill(Color.primary.opacity(0.1))
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(AppConfig.bubblePadX)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Product name beside the icon. It shares the body column with Q and A.
    private var headerName: String {
        let name = model.appName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty { return name }
        return SlotFace.displayName(for: model.source)
    }

    private var ageLabel: String {
        BubbleAge.relative(updated: model.updated, now: Date().timeIntervalSince1970)
    }

    private var thinking: Bool {
        model.awaitingAnswer && model.answer.isEmpty
    }

    private var canExpand: Bool {
        !thinking && (model.summary.count > 36 || model.answer.count > 36)
    }

    private var statusTint: Color {
        switch model.taskStatus {
        case "running": return AgentStatusRing.thinking
        case "wait", "fail": return AgentStatusRing.stuck
        case "done": return AgentStatusRing.done
        default: return Color.primary
        }
    }

    private func answerBody(lines: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: CardColumn.gap) {
            markLabel("A：")
            if thinking {
                BouncingEllipsis()
                    .offset(y: 1)
            } else {
                Text(model.answer)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.secondary)
                    .lineLimit(lines)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    /// The mark stays one column wide. A sibling with no text baseline must not squeeze it into an ellipsis.
    private func markLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .frame(width: CardColumn.mark, alignment: .leading)
            .fixedSize(horizontal: true, vertical: false)
            .layoutPriority(1)
    }

    private func qaRow(label: String, text: String, lines: Int, pending: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: CardColumn.gap) {
            markLabel(label)
            if pending {
                BouncingEllipsis()
                    .offset(y: 1)
            } else {
                Text(text)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.secondary)
                    .lineLimit(lines)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var picker: some View {
        HStack(spacing: 8) {
            ForEach(pickerMenu.sources, id: \.self) { source in
                Button {
                    model.onPick?(source)
                }                 label: {
                    icon(AgentIcon.image(source: source), source: source, side: 28)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(SlotFace.pickerName(for: source))
            }
        }
        .padding(.horizontal, AppConfig.bubblePadX)
        .padding(.vertical, AppConfig.bubblePadY)
    }

    private func icon(_ image: NSImage?, source: String, side: CGFloat) -> some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: side, height: side)
            } else {
                AgentMark(source: source)
                    .frame(width: side, height: side)
            }
        }
    }
}

/// The Q / A mark is the glyph width. Body text, the product name, and option plates start one gap after it.
/// Status, time, and 展开 share the trailing edge.
private enum CardColumn {
    static let gap: CGFloat = 4
    static let mark: CGFloat = {
        let font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        let width = ["Q：", "A："].map { ($0 as NSString).size(withAttributes: [.font: font]).width }.max() ?? 20
        return ceil(width)
    }()
}

enum BubbleMeasure {
    static func textHeight(_ text: String, width: CGFloat, font: NSFont, lines: Int) -> CGFloat {
        let field = NSTextField(wrappingLabelWithString: text)
        field.font = font
        field.maximumNumberOfLines = lines
        field.preferredMaxLayoutWidth = width
        let measured = field.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: width, height: 8_000)).height ?? font.boundingRectForFont.height
        let cap = ceil(font.boundingRectForFont.height * CGFloat(lines) + 4)
        return min(max(font.boundingRectForFont.height, measured), cap)
    }

    static func probe(screenHeight: CGFloat) -> [String: Any] {
        let titleFont = NSFont.systemFont(ofSize: 13, weight: .semibold)
        let summaryFont = NSFont.systemFont(ofSize: 11, weight: .regular)
        let width = AppConfig.bubbleMaxWidth - AppConfig.beakWidth - AppConfig.bubblePadX * 2
        let one = textHeight("Hello", width: width, font: titleFont, lines: 2)
        let two = textHeight(
            "Open title that should wrap onto more than one line when the card is expanded",
            width: width,
            font: titleFont,
            lines: 2
        )
        let summary = textHeight(String(repeating: "A long prompt that stays inside the bubble. ", count: 40), width: width, font: summaryFont, lines: 4)
        let choice = textHeight("Choose the third long option without clipping the label", width: width - 20, font: titleFont, lines: 3)
        let half = screenHeight / 2
        return [
            "oneLine": one,
            "twoLine": two,
            "summary": summary,
            "choice": choice,
            "twoTaller": two > one + 1,
            "summaryCapped": summary > 0 && summary <= half + 1,
            "choiceVisible": choice > 12
        ]
    }
}

@MainActor
final class BubblePanel: NSObject {
    let panel: CapsulePanel
    let model: BubbleModel
    private let hosting: NSHostingView<BubbleFace>
    private(set) var visible = false

    override init() {
        let model = BubbleModel()
        let panel = CapsulePanel(
            contentRect: NSRect(x: 0, y: 0, width: 180, height: 80),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.isMovable = false
        panel.ignoresMouseEvents = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.isRestorable = false
        panel.animationBehavior = .none
        panel.title = "Mochi Bubble"
        panel.level = .floating
        let hosting = BubbleHostingView(rootView: BubbleFace(model: model))
        hosting.sizingOptions = []
        hosting.wantsLayer = true
        hosting.layer?.isOpaque = false
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = hosting
        self.panel = panel
        self.model = model
        self.hosting = hosting
        super.init()
    }

    func attach(to host: NSWindow) {
        panel.level = NSWindow.Level(rawValue: host.level.rawValue + 3)
        panel.collectionBehavior = host.collectionBehavior
        if host.childWindows?.contains(panel) != true {
            host.addChildWindow(panel, ordered: .above)
        }
        hide()
    }

    func hide() {
        visible = false
        panel.alphaValue = 0
        panel.ignoresMouseEvents = true
        panel.orderOut(nil)
    }

    func show(anchor: CGRect, capsule: CGRect, screen: CGRect) {
        let room = max(AppConfig.bubbleMinHeight, anchor.maxY - screen.minY - 8)
        model.maxHeight = min(screen.height * 0.4, room)
        let body = measuredBody()
        let size = CGSize(width: body.width + AppConfig.beakWidth, height: body.height)
        let placed = BubblePlacer.place(anchor: anchor, capsule: capsule, size: size, screen: screen)
        model.beakY = placed.beakY
        model.pointsRight = placed.pointsRight
        model.bodyWidth = body.width
        hosting.frame = NSRect(origin: .zero, size: NSSize(width: size.width, height: size.height))
        panel.setFrame(placed.frame, display: true)
        panel.alphaValue = 1
        panel.ignoresMouseEvents = false
        visible = true
        panel.orderFrontRegardless()
    }

    private func measuredBody() -> CGSize {
        let maxBody = AppConfig.bubbleMaxWidth - AppConfig.beakWidth
        let minBody = AppConfig.bubbleMinWidth - AppConfig.beakWidth
        prepare(width: maxBody)
        let host = NSHostingController(rootView: BubbleFace(model: model))
        let fitted = host.sizeThatFits(in: CGSize(width: maxBody, height: 10_000))
        var height = max(AppConfig.bubbleMinHeight, model.computedHeight)
        if fitted.height.isFinite, fitted.height >= AppConfig.bubbleMinHeight, fitted.height < 4_000 {
            height = max(height, fitted.height)
        }
        model.computedHeight = height
        let width = model.kind == .label
            ? min(maxBody, max(minBody, fitted.width))
            : maxBody
        return CGSize(width: width, height: height)
    }

    private func prepare(width: CGFloat) {
        let textWidth = max(40, width - AppConfig.bubblePadX * 2 - CardColumn.mark - CardColumn.gap)
        let screen = NSScreen.main?.frame.height ?? 900
        let summaryFont = NSFont.systemFont(ofSize: 11, weight: .regular)
        let titleFont = NSFont.systemFont(ofSize: 13, weight: .semibold)
        let thinking = model.awaitingAnswer && model.answer.isEmpty
        let questionLines = model.answerExpanded ? 20 : 2
        let questionHeight = BubbleMeasure.textHeight(
            model.summary.isEmpty ? "Q：" : "Q：\(model.summary)",
            width: textWidth,
            font: summaryFont,
            lines: questionLines
        )
        let answerHeight: CGFloat
        if thinking || model.answer.isEmpty {
            answerHeight = 14
        } else if model.answerExpanded {
            answerHeight = max(14, BubbleMeasure.textHeight("A：\(model.answer)", width: textWidth, font: summaryFont, lines: 40))
        } else {
            answerHeight = min(28, max(14, BubbleMeasure.textHeight("A：\(model.answer)", width: textWidth, font: summaryFont, lines: 2)))
        }
        let canExpand = !thinking && (model.summary.count > 36 || model.answer.count > 36)
        let toggle: CGFloat = canExpand ? 18 : 0
        let title = BubbleMeasure.textHeight(model.title.isEmpty ? model.appName : model.title, width: textWidth, font: titleFont, lines: 1)
        var choices: CGFloat = 0
        if !model.options.isEmpty {
            if !model.choicePrompt.isEmpty {
                choices += BubbleMeasure.textHeight(model.choicePrompt, width: textWidth, font: summaryFont, lines: 2) + 6
            }
            for option in model.options {
                choices += BubbleMeasure.textHeight(option.label, width: textWidth - 20, font: titleFont, lines: 4) + 16 + 6
            }
        }
        switch model.kind {
        case .picker:
            model.computedHeight = max(AppConfig.bubbleMinHeight, 28 + AppConfig.bubblePadY * 2)
        case .label:
            model.computedHeight = max(AppConfig.bubbleMinHeight, title + AppConfig.bubblePadY * 2)
        case .card, .alert:
            let header: CGFloat = 22
            let pads = AppConfig.bubblePadX * 2
            let gaps: CGFloat = 4 + 4 + (toggle > 0 ? 4 : 0) + (choices > 0 ? 4 : 0)
            let natural = pads + header + questionHeight + answerHeight + toggle + choices + gaps
            let limit = model.maxHeight > AppConfig.bubbleMinHeight ? model.maxHeight : screen * 0.4
            if model.answerExpanded && natural > limit {
                let chrome = pads + header + toggle + choices + gaps
                model.summaryHeight = max(36, limit - chrome)
                model.computedHeight = max(AppConfig.bubbleMinHeight, limit)
            } else {
                model.summaryHeight = questionHeight + answerHeight + 4
                model.computedHeight = max(AppConfig.bubbleMinHeight, natural)
            }
        }
    }
}

/// Three dots that bounce while the assistant reply has not arrived.
private struct BouncingEllipsis: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(Color.secondary)
                        .frame(width: 4, height: 4)
                        .offset(y: bounce(t: t, index: index))
                }
            }
        }
        .frame(height: 12, alignment: .center)
        .alignmentGuide(.firstTextBaseline) { dimensions in
            dimensions[VerticalAlignment.center]
        }
        .accessibilityLabel("…")
    }

    private func bounce(t: TimeInterval, index: Int) -> CGFloat {
        let wave = sin(t * 7.2 - Double(index) * 0.7)
        return CGFloat(-max(0, wave) * 4)
    }
}

/// Drops the legacy visual-effect backdrop. That view is the solid light-blue fill.
final class BubbleHostingView<Content: View>: NSHostingView<Content> {
    private var strippedVisualEffects = false
    override var isOpaque: Bool { false }

    override func layout() {
        super.layout()
        layer?.isOpaque = false
        layer?.backgroundColor = NSColor.clear.cgColor
        guard !strippedVisualEffects else { return }
        strippedVisualEffects = true
        stripVisualEffects(self)
    }

    private func stripVisualEffects(_ view: NSView) {
        for subview in view.subviews {
            if let material = subview as? NSVisualEffectView {
                material.isHidden = true
                material.removeFromSuperview()
            } else {
                stripVisualEffects(subview)
            }
        }
    }
}
