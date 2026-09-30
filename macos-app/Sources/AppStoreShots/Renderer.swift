import AppKit
import CoreText
import UniformTypeIdentifiers

// MARK: - Spec

struct RenderFrame {
    var image: CGImage?
    var label: String
    var headline: String          // words wrapped in *asterisks* render orange
    var sub: String
    var angle: CGFloat            // phone tilt in degrees, positive = counter-clockwise
    var dx: CGFloat
    var dy: CGFloat
}

struct RenderSpec {
    var frames: [RenderFrame]
    var showChips: Bool
    var offersDone: Int
    var offersTotal: Int = 10
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

enum TextAnchor { case topLeft, middleLeft, middleRight, middleCenter }

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
        let gradient = CGGradient(colorsSpace: colorSpace, colors: [Palette.navy2, Palette.navy] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: H), options: [])

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

        // One big "sunrise" glow drifting across the whole panorama, cool counterweights below.
        glow(ctx, center: CGPoint(x: PW * 0.30, y: -300), radii: CGSize(width: 2600, height: 1500), color: Palette.orange, alpha: 110 / 255)
        glow(ctx, center: CGPoint(x: PW * 0.72, y: -200), radii: CGSize(width: 1800, height: 1100), color: Palette.orange2, alpha: 70 / 255)
        glow(ctx, center: CGPoint(x: PW * 0.12, y: 2650), radii: CGSize(width: 1500, height: 900), color: Palette.violet, alpha: 70 / 255)
        glow(ctx, center: CGPoint(x: PW * 0.88, y: 2500), radii: CGSize(width: 1700, height: 1000), color: Palette.blue, alpha: 60 / 255)
        glow(ctx, center: CGPoint(x: PW * 0.5, y: 2900), radii: CGSize(width: 2200, height: 700), color: Palette.orange, alpha: 55 / 255)
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
            let bx = ox + margin + badgeR

            ctx.fillCircle(center: CGPoint(x: bx, y: badgeY), radius: badgeR, color: Palette.orange)
            ctx.drawText("\(i + 1)", font: Fonts.display(34), color: Palette.white,
                         at: CGPoint(x: bx, y: badgeY + 1), anchor: .middleCenter)

            let label = frame.label.uppercased(with: Locale(identifier: "tr_TR"))
            let labelFont = Fonts.semibold(34)
            let pillW = ctx.textWidth(label, font: labelFont) + 40
            ctx.fillRoundedRect(CGRect(x: bx + badgeR + 20, y: badgeY - 30, width: pillW, height: 60), radius: 30, color: Palette.navy2)
            ctx.drawText(label, font: labelFont, color: Palette.muted,
                         at: CGPoint(x: bx + badgeR + 40, y: badgeY + 1), anchor: .middleLeft)

            let yEnd = drawHeadline(ctx, x: ox + margin, y: 330, text: frame.headline, maxWidth: W - margin * 2)
            ctx.drawText(frame.sub, font: Fonts.medium(44), color: Palette.muted, at: CGPoint(x: ox + margin, y: yEnd + 28))
        }
    }

    private func drawHeadline(_ ctx: CGContext, x: CGFloat, y: CGFloat, text: String, maxWidth: CGFloat) -> CGFloat {
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
            ctx.drawText(Renderer.parseMarkup(line), font: font, at: CGPoint(x: x, y: y + CGFloat(i) * lineHeight))
        }
        return y + CGFloat(lines.count) * lineHeight
    }

    static func parseMarkup(_ line: String) -> [TextRun] {
        var runs: [TextRun] = []
        var buffer = ""
        var highlighted = false
        for ch in line {
            if ch == "*" {
                if !buffer.isEmpty {
                    runs.append(TextRun(text: buffer, color: highlighted ? Palette.orange2 : Palette.white))
                    buffer = ""
                }
                highlighted.toggle()
            } else {
                buffer.append(ch)
            }
        }
        if !buffer.isEmpty {
            runs.append(TextRun(text: buffer, color: highlighted ? Palette.orange2 : Palette.white))
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

    private enum ChipKind { case status, progress, check }

    private struct Chip {
        let kind: ChipKind
        let center: CGPoint
        let angle: CGFloat
    }

    private func chipPlan() -> [Chip] {
        var chips: [Chip] = []
        // Alternate chips on every seam so they straddle two frames.
        for seam in 1..<count {
            if (seam - 1) % 2 == 0 {
                chips.append(Chip(kind: .status, center: CGPoint(x: W * CGFloat(seam), y: 1460), angle: -6))
            } else {
                chips.append(Chip(kind: .progress, center: CGPoint(x: W * CGFloat(seam), y: 1180), angle: 4))
            }
        }
        chips.append(Chip(kind: .check, center: CGPoint(x: PW - 240, y: 1720), angle: -3))
        return chips
    }

    private func drawChips(_ ctx: CGContext) {
        for chip in chipPlan() {
            let size = chipSize(ctx, chip.kind)
            ctx.saveGState()
            ctx.translateBy(x: chip.center.x, y: chip.center.y)
            ctx.rotate(by: -chip.angle * .pi / 180)
            ctx.translateBy(x: -size.width / 2, y: -size.height / 2)

            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: -30), blur: 36, color: Palette.rgb(0, 0, 0, 0.47))
            ctx.fillRoundedRect(CGRect(origin: .zero, size: size), radius: 40, color: Palette.white)
            ctx.restoreGState()

            drawChipContent(ctx, chip.kind, size: size)
            ctx.restoreGState()
        }
    }

    private var chipPadX: CGFloat { 40 }
    private var chipPadY: CGFloat { 34 }

    private func chipSize(_ ctx: CGContext, _ kind: ChipKind) -> CGSize {
        let titleFont = Fonts.semibold(40)
        switch kind {
        case .status:
            let tw = ctx.textWidth("Teklif toplanıyor", font: titleFont)
            return CGSize(width: chipPadX * 2 + 28 + 20 + tw, height: chipPadY * 2 + 48)
        case .progress:
            return CGSize(width: 520, height: 168)
        case .check:
            let tw = ctx.textWidth("Güvenle seç", font: titleFont)
            return CGSize(width: chipPadX * 2 + 56 + 20 + tw, height: chipPadY * 2 + 56)
        }
    }

    private func drawChipContent(_ ctx: CGContext, _ kind: ChipKind, size: CGSize) {
        let titleFont = Fonts.semibold(40)
        let smallFont = Fonts.medium(32)
        let cy = size.height / 2

        switch kind {
        case .status:
            ctx.fillCircle(center: CGPoint(x: chipPadX + 14, y: cy), radius: 14, color: Palette.green)
            ctx.drawText("Teklif toplanıyor", font: titleFont, color: Palette.ink, at: CGPoint(x: chipPadX + 48, y: cy), anchor: .middleLeft)

        case .progress:
            let done = max(0, min(spec.offersDone, spec.offersTotal))
            let total = max(1, spec.offersTotal)
            ctx.drawText("Gelen teklifler", font: titleFont, color: Palette.ink, at: CGPoint(x: chipPadX, y: 56), anchor: .middleLeft)
            ctx.drawText("\(done)/\(total)", font: smallFont, color: Palette.subtle, at: CGPoint(x: size.width - chipPadX, y: 56), anchor: .middleRight)
            let gap: CGFloat = 10
            let segW = (size.width - chipPadX * 2 - gap * CGFloat(total - 1)) / CGFloat(total)
            for i in 0..<total {
                let x0 = chipPadX + CGFloat(i) * (segW + gap)
                ctx.fillRoundedRect(CGRect(x: x0, y: 104, width: segW, height: 20), radius: 8,
                                    color: i < done ? Palette.orange : Palette.track)
            }

        case .check:
            let cx = chipPadX + 28
            ctx.fillCircle(center: CGPoint(x: cx, y: cy), radius: 28, color: Palette.orange)
            ctx.setStrokeColor(Palette.white)
            ctx.setLineWidth(6)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            ctx.move(to: CGPoint(x: cx - 13, y: cy + 1))
            ctx.addLine(to: CGPoint(x: cx - 3, y: cy + 11))
            ctx.addLine(to: CGPoint(x: cx + 15, y: cy - 9))
            ctx.strokePath()
            ctx.drawText("Güvenle seç", font: titleFont, color: Palette.ink, at: CGPoint(x: chipPadX + 76, y: cy), anchor: .middleLeft)
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
