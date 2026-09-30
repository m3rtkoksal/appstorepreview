import AppKit
import CoreText
import UniformTypeIdentifiers

// MARK: - Spec

enum HAlign: String, CaseIterable, Identifiable {
    case left, center, right
    var id: String { rawValue }
}

struct RenderFrame {
    var image: CGImage?
    var label: String
    var headline: String          // words wrapped in *asterisks* render in the highlight colour
    var sub: String
    var align: HAlign
    var angle: CGFloat            // phone tilt in degrees, positive = counter-clockwise
    var dx: CGFloat
    var dy: CGFloat
}

struct RenderChip {
    var text: String
    var symbol: String            // SF Symbol name; empty = small dot
    var iconColor: CGColor
    var showProgress: Bool
    var done: Int
    var total: Int
    var x: CGFloat                // horizontal position in frame units (1.0 = seam between frame 1 and 2)
    var y: CGFloat                // vertical position in px from the top
    var angle: CGFloat
}

struct RenderTheme {
    var bgTop: CGColor
    var bgBottom: CGColor
    var glow: CGColor             // warm light at the top
    var coolGlow: CGColor         // counterweight light at the bottom
    var badge: CGColor
    var badgeText: CGColor
    var headline: CGColor
    var highlight: CGColor
    var sub: CGColor
    var showGrid: Bool
}

struct RenderSpec {
    var frames: [RenderFrame]
    var theme: RenderTheme
    var textY: CGFloat            // top of the headline block
    var showChips: Bool
    var chips: [RenderChip]
}

// MARK: - Palette / fonts

enum Palette {
    static func rgb(_ r: Int, _ g: Int, _ b: Int, _ a: CGFloat = 1) -> CGColor {
        CGColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: a)
    }

    static let navy = rgb(11, 18, 32)
    static let navy2 = rgb(19, 30, 54)
    static let white = rgb(255, 255, 255)
    static let ink = rgb(15, 23, 42)
    static let muted = rgb(163, 177, 201)
    static let subtle = rgb(100, 112, 138)
    static let orange = rgb(242, 101, 34)
    static let orange2 = rgb(255, 145, 66)
    static let green = rgb(22, 163, 74)
    static let violet = rgb(124, 58, 237)
    static let blue = rgb(37, 99, 235)
    static let track = rgb(226, 232, 240)
}

enum Fonts {
    // SF Pro switches to its Display optical size above 20pt, which is very
    // close to the Inter Display face used by the Python generator.
    static func display(_ size: CGFloat) -> NSFont { .systemFont(ofSize: size, weight: .bold) }
    static func semibold(_ size: CGFloat) -> NSFont { .systemFont(ofSize: size, weight: .semibold) }
    static func medium(_ size: CGFloat) -> NSFont { .systemFont(ofSize: size, weight: .medium) }
}

// MARK: - CGContext helpers (top-left origin; the renderer flips the context once)

enum TextAnchor { case topLeft, topCenter, topRight, middleLeft, middleRight, middleCenter }

struct TextRun {
    let text: String
    let color: CGColor
}

extension CGContext {
    private func makeLine(_ runs: [TextRun], font: NSFont) -> CTLine {
        let attr = NSMutableAttributedString()
        for run in runs {
            attr.append(NSAttributedString(string: run.text, attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): run.color,
            ]))
        }
        return CTLineCreateWithAttributedString(attr)
    }

    func textWidth(_ text: String, font: NSFont) -> CGFloat {
        let line = makeLine([TextRun(text: text, color: Palette.white)], font: font)
        return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    }

    @discardableResult
    func drawText(_ runs: [TextRun], font: NSFont, at p: CGPoint, anchor: TextAnchor = .topLeft) -> CGFloat {
        let line = makeLine(runs, font: font)
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, nil))
        let middleBaseline = p.y + (ascent - descent) / 2

        var x = p.x
        let baseline: CGFloat
        switch anchor {
        case .topLeft:
            baseline = p.y + ascent
        case .topCenter:
            x = p.x - width / 2
            baseline = p.y + ascent
        case .topRight:
            x = p.x - width
            baseline = p.y + ascent
        case .middleLeft:
            baseline = middleBaseline
        case .middleRight:
            x = p.x - width
            baseline = middleBaseline
        case .middleCenter:
            x = p.x - width / 2
            baseline = middleBaseline
        }

        saveGState()
        textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        textPosition = CGPoint(x: x, y: baseline)
        CTLineDraw(line, self)
        restoreGState()
        return width
    }

    @discardableResult
    func drawText(_ text: String, font: NSFont, color: CGColor, at p: CGPoint, anchor: TextAnchor = .topLeft) -> CGFloat {
        drawText([TextRun(text: text, color: color)], font: font, at: p, anchor: anchor)
    }

    func fillRoundedRect(_ rect: CGRect, radius: CGFloat, color: CGColor) {
        let r = min(radius, rect.width / 2, rect.height / 2)
        addPath(CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil))
        setFillColor(color)
        fillPath()
    }

    func fillCircle(center: CGPoint, radius: CGFloat, color: CGColor) {
        setFillColor(color)
        fillEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    }

    /// Draws a CGImage upright inside a context whose CTM has been flipped to top-left origin.
    func drawImageFlipped(_ image: CGImage, in rect: CGRect) {
        saveGState()
        translateBy(x: rect.minX, y: rect.maxY)
        scaleBy(x: 1, y: -1)
        interpolationQuality = .high
        draw(image, in: CGRect(x: 0, y: 0, width: rect.width, height: rect.height))
        restoreGState()
    }

    /// Fills `rect` with `color` through the alpha of `mask` (used for SF Symbols), upright in a flipped context.
    func drawMaskTinted(_ mask: CGImage, in rect: CGRect, color: CGColor) {
        saveGState()
        translateBy(x: rect.minX, y: rect.maxY)
        scaleBy(x: 1, y: -1)
        let local = CGRect(x: 0, y: 0, width: rect.width, height: rect.height)
        clip(to: local, mask: mask)
        setFillColor(color)
        fill(local)
        restoreGState()
    }

    /// Draws an SF Symbol centred in `box`, scaled to fit while keeping its aspect ratio.
    func drawSymbol(_ name: String, in box: CGRect, color: CGColor) {
        guard let mask = Symbols.image(name, pointSize: box.height) else { return }
        let w = CGFloat(mask.width), h = CGFloat(mask.height)
        let scale = min(box.width / w, box.height / h)
        let size = CGSize(width: w * scale, height: h * scale)
        let origin = CGPoint(x: box.midX - size.width / 2, y: box.midY - size.height / 2)
        drawMaskTinted(mask, in: CGRect(origin: origin, size: size), color: color)
    }
}

enum Symbols {
    static func isValid(_ name: String) -> Bool {
        !name.isEmpty && NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil
    }

    static func image(_ name: String, pointSize: CGFloat) -> CGImage? {
        guard !name.isEmpty,
              let base = NSImage(systemSymbolName: name, accessibilityDescription: nil),
              let sized = base.withSymbolConfiguration(.init(pointSize: pointSize, weight: .bold))
        else { return nil }
        var rect = CGRect(origin: .zero, size: sized.size)
        return sized.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }
}

// MARK: - Renderer

struct RenderOutput {
    var panorama: CGImage
    var frames: [CGImage]
}

enum RenderError: LocalizedError {
    case contextFailed
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .contextFailed: return "Görsel oluşturulamadı."
        case .writeFailed(let name): return "\(name) dosyası yazılamadı."
        }
    }
}

struct Renderer {
    static let frameWidth: CGFloat = 1284
    static let frameHeight: CGFloat = 2778
    static let screenWidth: CGFloat = 860
    static let bezel: CGFloat = 22

    let spec: RenderSpec

    private var W: CGFloat { Renderer.frameWidth }
    private var H: CGFloat { Renderer.frameHeight }
    private var count: Int { max(spec.frames.count, 1) }
    private var PW: CGFloat { W * CGFloat(count) }

    private static let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    private var colorSpace: CGColorSpace { Renderer.colorSpace }

    // MARK: Public

    func render() -> RenderOutput? {
        guard let panorama = renderPanorama() else { return nil }
        var frames: [CGImage] = []
        for i in 0..<count {
            let rect = CGRect(x: CGFloat(i) * W, y: 0, width: W, height: H)
            if let f = panorama.cropping(to: rect) { frames.append(f) }
        }
        return RenderOutput(panorama: panorama, frames: frames)
    }

    /// Writes all App Store assets into `directory` and returns the created files.
    func export(to directory: URL) throws -> [URL] {
        guard let out = render() else { throw RenderError.contextFailed }
        var written: [URL] = []

        func save(_ image: CGImage, _ name: String) throws {
            let url = directory.appendingPathComponent(name)
            guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
                throw RenderError.writeFailed(name)
            }
            CGImageDestinationAddImage(dest, image, nil)
            guard CGImageDestinationFinalize(dest) else { throw RenderError.writeFailed(name) }
            written.append(url)
        }

        for (i, frame) in out.frames.enumerated() {
            try save(frame, "appstore_\(i + 1)_1284x2778.png")
            if let small = Renderer.resized(frame, to: CGSize(width: 1242, height: 2688)) {
                try save(small, "appstore_\(i + 1)_1242x2688.png")
            }
        }
        try save(out.panorama, "panorama.png")
        if let sheet = contactSheet(out.frames) { try save(sheet, "preview_sheet.png") }
        return written
    }

    // MARK: Context

    static func makeContext(width: Int, height: Int) -> CGContext? {
        CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    }

    static func resized(_ image: CGImage, to size: CGSize) -> CGImage? {
        guard let ctx = makeContext(width: Int(size.width), height: Int(size.height)) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(origin: .zero, size: size))
        return ctx.makeImage()
    }

    private func contactSheet(_ frames: [CGImage]) -> CGImage? {
        let gap: CGFloat = 40
        let width = (W + gap) * CGFloat(frames.count) - gap
        guard let ctx = Renderer.makeContext(width: Int(width), height: Int(H)) else { return nil }
        ctx.setFillColor(Palette.rgb(24, 24, 28))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: H))
        for (i, f) in frames.enumerated() {
            ctx.draw(f, in: CGRect(x: CGFloat(i) * (W + gap), y: 0, width: W, height: H))
        }
        guard let full = ctx.makeImage() else { return nil }
        return Renderer.resized(full, to: CGSize(width: width / 4, height: H / 4))
    }

    // MARK: Scene

    private func renderPanorama() -> CGImage? {
        guard let ctx = Renderer.makeContext(width: Int(PW), height: Int(H)) else { return nil }
        // Work in top-left coordinates like the Python original.
        ctx.translateBy(x: 0, y: H)
        ctx.scaleBy(x: 1, y: -1)

        drawBackground(ctx)
        drawCopy(ctx)
        drawPhones(ctx)
        if spec.showChips { drawChips(ctx) }
        return ctx.makeImage()
    }

    private func drawBackground(_ ctx: CGContext) {
        let theme = spec.theme
        let gradient = CGGradient(colorsSpace: colorSpace, colors: [theme.bgTop, theme.bgBottom] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: H), options: [])

        if theme.showGrid {
            // Blueprint grid fading out towards the bottom (echoes the app header).
            let step: CGFloat = 96
            ctx.setLineWidth(2)
            var y: CGFloat = 0
            while y < H {
                let alpha = max(0, 22 * (1 - (y / H * 255) / 150)) / 255
                if alpha > 0 {
                    ctx.setStrokeColor(Palette.rgb(255, 255, 255, alpha))
                    ctx.move(to: CGPoint(x: 0, y: y))
                    ctx.addLine(to: CGPoint(x: PW, y: y))
                    var x: CGFloat = 0
                    while x < PW {
                        ctx.move(to: CGPoint(x: x, y: y))
                        ctx.addLine(to: CGPoint(x: x, y: y + step))
                        x += step
                    }
                    ctx.strokePath()
                }
                y += step
            }
        }

        // One big "sunrise" glow drifting across the whole panorama, cool counterweights below.
        glow(ctx, center: CGPoint(x: PW * 0.30, y: -300), radii: CGSize(width: 2600, height: 1500), color: theme.glow, alpha: 110 / 255)
        glow(ctx, center: CGPoint(x: PW * 0.72, y: -200), radii: CGSize(width: 1800, height: 1100), color: theme.glow, alpha: 70 / 255)
        glow(ctx, center: CGPoint(x: PW * 0.12, y: 2650), radii: CGSize(width: 1500, height: 900), color: theme.coolGlow, alpha: 70 / 255)
        glow(ctx, center: CGPoint(x: PW * 0.88, y: 2500), radii: CGSize(width: 1700, height: 1000), color: theme.coolGlow, alpha: 60 / 255)
        glow(ctx, center: CGPoint(x: PW * 0.5, y: 2900), radii: CGSize(width: 2200, height: 700), color: theme.glow, alpha: 55 / 255)
    }

    private func glow(_ ctx: CGContext, center: CGPoint, radii: CGSize, color: CGColor, alpha: CGFloat) {
        guard
            let c0 = color.copy(alpha: alpha),
            let c1 = color.copy(alpha: alpha * 0.6),
            let c2 = color.copy(alpha: 0),
            let gradient = CGGradient(colorsSpace: colorSpace, colors: [c0, c1, c2] as CFArray, locations: [0, 0.45, 1])
        else { return }
        // The Python version blurred a hard ellipse by ~500px; widen the radius to match its reach.
        let spread: CGFloat = 420
        ctx.saveGState()
        ctx.translateBy(x: center.x, y: center.y)
        ctx.scaleBy(x: radii.width + spread, y: radii.height + spread)
        ctx.drawRadialGradient(gradient, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: 1, options: [])
        ctx.restoreGState()
    }

    private func drawCopy(_ ctx: CGContext) {
        let theme = spec.theme
        let margin: CGFloat = 96
        let badgeY: CGFloat = 236
        let badgeR: CGFloat = 34

        // Connector line running behind every step badge, across the whole panorama.
        ctx.setStrokeColor(Palette.rgb(255, 255, 255, 34 / 255))
        ctx.setLineWidth(2)
        ctx.move(to: CGPoint(x: 0, y: badgeY))
        ctx.addLine(to: CGPoint(x: PW, y: badgeY))
        ctx.strokePath()

        for (i, frame) in spec.frames.enumerated() {
            let ox = CGFloat(i) * W
            let label = frame.label.uppercased(with: Locale(identifier: "tr_TR"))
            let labelFont = Fonts.semibold(34)
            let pillW = label.isEmpty ? 0 : ctx.textWidth(label, font: labelFont) + 40
            let groupW = badgeR * 2 + (pillW > 0 ? 20 + pillW : 0)

            let groupX: CGFloat
            switch frame.align {
            case .left: groupX = ox + margin
            case .center: groupX = ox + (W - groupW) / 2
            case .right: groupX = ox + W - margin - groupW
            }

            let bx = groupX + badgeR
            ctx.fillCircle(center: CGPoint(x: bx, y: badgeY), radius: badgeR, color: theme.badge)
            ctx.drawText("\(i + 1)", font: Fonts.display(34), color: theme.badgeText,
                         at: CGPoint(x: bx, y: badgeY + 1), anchor: .middleCenter)

            if pillW > 0 {
                ctx.fillRoundedRect(CGRect(x: bx + badgeR + 20, y: badgeY - 30, width: pillW, height: 60), radius: 30, color: theme.bgTop)
                ctx.drawText(label, font: labelFont, color: theme.sub,
                             at: CGPoint(x: bx + badgeR + 40, y: badgeY + 1), anchor: .middleLeft)
            }

            let textX: CGFloat
            let anchor: TextAnchor
            switch frame.align {
            case .left: textX = ox + margin; anchor = .topLeft
            case .center: textX = ox + W / 2; anchor = .topCenter
            case .right: textX = ox + W - margin; anchor = .topRight
            }
            let yEnd = drawHeadline(ctx, x: textX, y: spec.textY, text: frame.headline, maxWidth: W - margin * 2, anchor: anchor)
            ctx.drawText(frame.sub, font: Fonts.medium(44), color: theme.sub, at: CGPoint(x: textX, y: yEnd + 28), anchor: anchor)
        }
    }

    private func drawHeadline(_ ctx: CGContext, x: CGFloat, y: CGFloat, text: String, maxWidth: CGFloat, anchor: TextAnchor) -> CGFloat {
        let lines = text.components(separatedBy: "\n")
        var size: CGFloat = 108
        while size > 60 {
            let f = Fonts.display(size)
            let fits = lines.allSatisfy { ctx.textWidth($0.replacingOccurrences(of: "*", with: ""), font: f) <= maxWidth }
            if fits { break }
            size -= 2
        }
        let font = Fonts.display(size)
        let lineHeight = floor(size * 1.08)
        for (i, line) in lines.enumerated() {
            let runs = Renderer.parseMarkup(line, base: spec.theme.headline, highlight: spec.theme.highlight)
            ctx.drawText(runs, font: font, at: CGPoint(x: x, y: y + CGFloat(i) * lineHeight), anchor: anchor)
        }
        return y + CGFloat(lines.count) * lineHeight
    }

    static func parseMarkup(_ line: String, base: CGColor, highlight: CGColor) -> [TextRun] {
        var runs: [TextRun] = []
        var buffer = ""
        var highlighted = false
        for ch in line {
            if ch == "*" {
                if !buffer.isEmpty {
                    runs.append(TextRun(text: buffer, color: highlighted ? highlight : base))
                    buffer = ""
                }
                highlighted.toggle()
            } else {
                buffer.append(ch)
            }
        }
        if !buffer.isEmpty {
            runs.append(TextRun(text: buffer, color: highlighted ? highlight : base))
        }
        return runs
    }

    // MARK: Phones

    private func drawPhones(_ ctx: CGContext) {
        let screenW = Renderer.screenWidth
        let bezel = Renderer.bezel
        for (i, frame) in spec.frames.enumerated() {
            let screenH: CGFloat
            if let img = frame.image {
                screenH = (screenW * CGFloat(img.height) / CGFloat(img.width)).rounded()
            } else {
                screenH = (screenW * H / W).rounded()
            }
            let phoneW = screenW + bezel * 2
            let phoneH = screenH + bezel * 2
            let cx = CGFloat(i) * W + W / 2 + frame.dx
            let cy = 720 + frame.dy + phoneH / 2

            ctx.saveGState()
            ctx.translateBy(x: cx, y: cy)
            ctx.rotate(by: -frame.angle * .pi / 180)   // context is flipped, so negate to keep PIL's direction
            ctx.translateBy(x: -phoneW / 2, y: -phoneH / 2)
            drawPhone(ctx, width: phoneW, height: phoneH, screenHeight: screenH, image: frame.image)
            ctx.restoreGState()
        }
    }

    private func drawPhone(_ ctx: CGContext, width: CGFloat, height: CGFloat, screenHeight: CGFloat, image: CGImage?) {
        let outerR: CGFloat = 128
        let bezel = Renderer.bezel

        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -70), blur: 60, color: Palette.rgb(0, 0, 0, 0.75))
        ctx.fillRoundedRect(CGRect(x: 0, y: 0, width: width, height: height), radius: outerR, color: Palette.rgb(38, 40, 46))
        ctx.restoreGState()
        ctx.fillRoundedRect(CGRect(x: 3, y: 3, width: width - 6, height: height - 6), radius: outerR - 3, color: Palette.rgb(12, 12, 14))

        let screenRect = CGRect(x: bezel, y: bezel, width: Renderer.screenWidth, height: screenHeight)
        ctx.saveGState()
        ctx.addPath(CGPath(roundedRect: screenRect, cornerWidth: outerR - bezel, cornerHeight: outerR - bezel, transform: nil))
        ctx.clip()
        if let image {
            ctx.drawImageFlipped(image, in: screenRect)
        } else {
            ctx.setFillColor(Palette.navy)
            ctx.fill(screenRect)
            ctx.drawText("Ekran görüntüsünü buraya bırakın", font: Fonts.medium(36), color: Palette.muted,
                         at: CGPoint(x: screenRect.midX, y: screenRect.midY), anchor: .middleCenter)
        }
        ctx.restoreGState()

        // Dynamic island
        let islandW: CGFloat = 250, islandH: CGFloat = 72
        ctx.fillRoundedRect(CGRect(x: (width - islandW) / 2, y: bezel + 24, width: islandW, height: islandH), radius: islandH / 2, color: Palette.rgb(8, 8, 10))

        // Side buttons
        let button = Palette.rgb(60, 62, 68)
        ctx.fillRoundedRect(CGRect(x: -4, y: 420, width: 6, height: 100), radius: 3, color: button)
        ctx.fillRoundedRect(CGRect(x: -4, y: 580, width: 6, height: 180), radius: 3, color: button)
        ctx.fillRoundedRect(CGRect(x: -4, y: 800, width: 6, height: 180), radius: 3, color: button)
        ctx.fillRoundedRect(CGRect(x: width - 3, y: 620, width: 6, height: 280), radius: 3, color: button)
    }

    // MARK: Chips

    private func drawChips(_ ctx: CGContext) {
        for chip in spec.chips {
            let size = chipSize(ctx, chip)
            let center = CGPoint(x: chip.x * W, y: chip.y)
            ctx.saveGState()
            ctx.translateBy(x: center.x, y: center.y)
            ctx.rotate(by: -chip.angle * .pi / 180)
            ctx.translateBy(x: -size.width / 2, y: -size.height / 2)

            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: -30), blur: 36, color: Palette.rgb(0, 0, 0, 0.47))
            ctx.fillRoundedRect(CGRect(origin: .zero, size: size), radius: 40, color: Palette.white)
            ctx.restoreGState()

            drawChipContent(ctx, chip, size: size)
            ctx.restoreGState()
        }
    }

    private var chipPadX: CGFloat { 40 }
    private var chipPadY: CGFloat { 34 }
    private var chipTitleFont: NSFont { Fonts.semibold(40) }
    private var chipSmallFont: NSFont { Fonts.medium(32) }
    private var iconDiameter: CGFloat { 56 }
    private var dotDiameter: CGFloat { 28 }

    private func chipText(_ chip: RenderChip) -> String {
        let trimmed = chip.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Metin" : trimmed
    }

    private func hasSymbol(_ chip: RenderChip) -> Bool {
        Symbols.isValid(chip.symbol.trimmingCharacters(in: .whitespaces))
    }

    /// Width taken by the icon (dot or symbol circle) plus its trailing gap.
    private func iconSlot(_ chip: RenderChip) -> CGFloat {
        if hasSymbol(chip) { return iconDiameter + 20 }
        // Progress chips without a symbol keep the original bare title row.
        return chip.showProgress ? 0 : dotDiameter + 20
    }

    private func chipSize(_ ctx: CGContext, _ chip: RenderChip) -> CGSize {
        let tw = ctx.textWidth(chipText(chip), font: chipTitleFont)
        let iconW = iconSlot(chip)
        if chip.showProgress {
            let counter = ctx.textWidth("\(chip.done)/\(chip.total)", font: chipSmallFont)
            return CGSize(width: max(520, chipPadX * 2 + iconW + tw + 40 + counter), height: 168)
        }
        let rowH = hasSymbol(chip) ? iconDiameter : 48
        return CGSize(width: chipPadX * 2 + iconW + tw, height: chipPadY * 2 + rowH)
    }

    private func drawIcon(_ ctx: CGContext, _ chip: RenderChip, centerY: CGFloat) {
        let symbol = chip.symbol.trimmingCharacters(in: .whitespaces)
        if !hasSymbol(chip) && chip.showProgress { return }
        if hasSymbol(chip) {
            let r = iconDiameter / 2
            let cx = chipPadX + r
            ctx.fillCircle(center: CGPoint(x: cx, y: centerY), radius: r, color: chip.iconColor)
            let inset: CGFloat = 13
            ctx.drawSymbol(symbol, in: CGRect(x: cx - r + inset, y: centerY - r + inset, width: iconDiameter - inset * 2, height: iconDiameter - inset * 2), color: Palette.white)
        } else {
            ctx.fillCircle(center: CGPoint(x: chipPadX + dotDiameter / 2, y: centerY), radius: dotDiameter / 2, color: chip.iconColor)
        }
    }

    private func drawChipContent(_ ctx: CGContext, _ chip: RenderChip, size: CGSize) {
        let text = chipText(chip)
        let textX = chipPadX + iconSlot(chip)

        if chip.showProgress {
            let rowY: CGFloat = 56
            drawIcon(ctx, chip, centerY: rowY)
            ctx.drawText(text, font: chipTitleFont, color: Palette.ink, at: CGPoint(x: textX, y: rowY), anchor: .middleLeft)
            let total = max(1, chip.total)
            let done = max(0, min(chip.done, total))
            ctx.drawText("\(done)/\(total)", font: chipSmallFont, color: Palette.subtle, at: CGPoint(x: size.width - chipPadX, y: rowY), anchor: .middleRight)
            let gap: CGFloat = 10
            let segW = (size.width - chipPadX * 2 - gap * CGFloat(total - 1)) / CGFloat(total)
            for i in 0..<total {
                let x0 = chipPadX + CGFloat(i) * (segW + gap)
                ctx.fillRoundedRect(CGRect(x: x0, y: 104, width: segW, height: 20), radius: 8,
                                    color: i < done ? chip.iconColor : Palette.track)
            }
        } else {
            let cy = size.height / 2
            drawIcon(ctx, chip, centerY: cy)
            ctx.drawText(text, font: chipTitleFont, color: Palette.ink, at: CGPoint(x: textX, y: cy), anchor: .middleLeft)
        }
    }
}

// MARK: - Image loading

enum ImageLoader {
    static func load(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCache: true] as CFDictionary)
    }
}
