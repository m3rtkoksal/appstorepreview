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

@MainActor
final class Document: ObservableObject {
    static let maxFrames = 5

    @Published var frames: [FrameSpec] = FrameSpec.defaults
    @Published var showChips = true
    @Published var offersDone = 7

    var renderSpec: RenderSpec {
        RenderSpec(
            frames: frames.map {
                RenderFrame(image: $0.image, label: $0.label, headline: $0.headline, sub: $0.sub,
                            angle: CGFloat($0.angle), dx: CGFloat($0.dx), dy: CGFloat($0.dy))
            },
            showChips: showChips,
            offersDone: offersDone
        )
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
