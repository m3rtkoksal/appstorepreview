import AppKit
import Combine
import SwiftUI

struct FrameSpec: Identifiable {
    let id = UUID()
    var imageURL: URL?
    var image: CGImage?
    var label: String
    var headline: String
    var sub: String
    var angle: Double
    var dx: Double
    var dy: Double

    static let defaults: [FrameSpec] = [
        FrameSpec(label: "Keşfet",
                  headline: "Evinize usta bulmak\nartık *çok kolay*",
                  sub: "Dakikalar içinde en iyi ustalardan teklif alın.",
                  angle: -7, dx: -60, dy: 10),
        FrameSpec(label: "Talep oluştur",
                  headline: "Talebini yaz,\n*kategorini* seç",
                  sub: "20 kategori, birkaç dokunuşla hazır talep.",
                  angle: 5, dx: 70, dy: -20),
        FrameSpec(label: "Teklifler",
                  headline: "En fazla *10 teklif*,\ntek ekranda",
                  sub: "Gelen teklifleri karşılaştır, en iyisini seç.",
                  angle: -4, dx: -40, dy: 0),
    ]

    static func blank(index: Int) -> FrameSpec {
        // Alternate tilt direction so a freshly added frame never lines up with its neighbour.
        let angle: Double = index % 2 == 0 ? -5 : 5
        return FrameSpec(label: "Adım \(index + 1)", headline: "Başlık\n*vurgu* burada",
                         sub: "Kısa açıklama metni.", angle: angle, dx: 0, dy: 0)
    }
}

struct ChipSpec: Identifiable {
    let id = UUID()
    var kind: ChipKind
    var text: String
    var done: Int = 7
    var total: Int = 10
    var x: Double          // frame units: 1.0 = seam between frame 1 and 2, 0.5 = middle of frame 1
    var y: Double          // px from top (0...2778)
    var angle: Double

    static let defaults: [ChipSpec] = [
        ChipSpec(kind: .status, text: "Teklif toplanıyor", x: 1.0, y: 1460, angle: -6),
        ChipSpec(kind: .progress, text: "Gelen teklifler", done: 7, total: 10, x: 2.0, y: 1180, angle: 4),
        ChipSpec(kind: .check, text: "Güvenle seç", x: 2.81, y: 1720, angle: -3),
    ]

    static func blank(frameCount: Int, index: Int) -> ChipSpec {
        let kinds = ChipKind.allCases
        let kind = kinds[index % kinds.count]
        // Put new chips on the first seam (or mid-frame for a single frame) and stagger them vertically.
        let x = frameCount > 1 ? 1.0 : 0.5
        let y = 1000 + Double(index % 4) * 320
        return ChipSpec(kind: kind, text: "", x: x, y: y, angle: index % 2 == 0 ? -5 : 4)
    }
}

@MainActor
final class Document: ObservableObject {
    static let maxFrames = 5
    static let maxChips = 6

    @Published var frames: [FrameSpec] = FrameSpec.defaults
    @Published var showChips = true
    @Published var chips: [ChipSpec] = ChipSpec.defaults

    var renderSpec: RenderSpec {
        RenderSpec(
            frames: frames.map {
                RenderFrame(image: $0.image, label: $0.label, headline: $0.headline, sub: $0.sub,
                            angle: CGFloat($0.angle), dx: CGFloat($0.dx), dy: CGFloat($0.dy))
            },
            showChips: showChips,
            chips: chips.map {
                RenderChip(kind: $0.kind, text: $0.text, done: $0.done, total: $0.total,
                           x: CGFloat($0.x), y: CGFloat($0.y), angle: CGFloat($0.angle))
            }
        )
    }

    func chipBinding(for id: ChipSpec.ID) -> Binding<ChipSpec> {
        Binding(
            get: { self.chips.first { $0.id == id } ?? ChipSpec.blank(frameCount: 1, index: 0) },
            set: { updated in
                if let i = self.chips.firstIndex(where: { $0.id == id }) { self.chips[i] = updated }
            }
        )
    }

    func addChip() {
        guard chips.count < Document.maxChips else { return }
        chips.append(ChipSpec.blank(frameCount: frames.count, index: chips.count))
    }

    func removeChip(id: ChipSpec.ID) {
        chips.removeAll { $0.id == id }
    }

    func binding(for id: FrameSpec.ID) -> Binding<FrameSpec> {
        Binding(
            get: { self.frames.first { $0.id == id } ?? FrameSpec.blank(index: 0) },
            set: { updated in
                if let i = self.frames.firstIndex(where: { $0.id == id }) { self.frames[i] = updated }
            }
        )
    }

    func index(of id: FrameSpec.ID) -> Int {
        frames.firstIndex { $0.id == id } ?? 0
    }

    func setImage(from url: URL, for id: FrameSpec.ID) {
        guard let i = frames.firstIndex(where: { $0.id == id }), let image = ImageLoader.load(url) else { return }
        frames[i].image = image
        frames[i].imageURL = url
    }

    func addFrame() {
        guard frames.count < Document.maxFrames else { return }
        frames.append(FrameSpec.blank(index: frames.count))
    }

    func removeFrame(id: FrameSpec.ID) {
        guard frames.count > 1 else { return }
        frames.removeAll { $0.id == id }
    }
}

@MainActor
final class PreviewModel: ObservableObject {
    @Published var frames: [CGImage] = []
    @Published var isRendering = false

    private var generation = 0
    private var subscriptions = Set<AnyCancellable>()

    func bind(to document: Document) {
        guard subscriptions.isEmpty else { return }
        document.objectWillChange
            .debounce(for: .milliseconds(200), scheduler: DispatchQueue.main)
            .sink { [weak self, weak document] _ in
                guard let self, let document else { return }
                self.render(document.renderSpec)
            }
            .store(in: &subscriptions)
        render(document.renderSpec)
    }

    func render(_ spec: RenderSpec) {
        generation += 1
        let current = generation
        isRendering = true
        Task.detached(priority: .userInitiated) {
            let output = Renderer(spec: spec).render()
            await MainActor.run {
                guard current == self.generation else { return }
                if let output { self.frames = output.frames }
                self.isRendering = false
            }
        }
    }
}
