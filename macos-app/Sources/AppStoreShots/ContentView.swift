import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var document: Document
    @StateObject private var preview = PreviewModel()

    @State private var isExporting = false
    @State private var showResult = false
    @State private var resultMessage = ""
    @State private var exportedDirectory: URL?

    var body: some View {
        HSplitView {
            editor
                .frame(minWidth: 380, idealWidth: 430, maxWidth: 540)
            previewPane
                .frame(minWidth: 520, maxWidth: .infinity, maxHeight: .infinity)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    document.addFrame()
                } label: {
                    Label("Kare ekle", systemImage: "plus.rectangle.portrait")
                }
                .help("Yeni kare ekle (en fazla \(Document.maxFrames))")
                .disabled(document.frames.count >= Document.maxFrames)

                Button {
                    export()
                } label: {
                    Label("Dışa aktar", systemImage: "square.and.arrow.up")
                }
                .help("PNG dosyalarını bir klasöre kaydet")
                .disabled(isExporting)
            }
        }
        .navigationTitle("App Store Görselleri")
        .onAppear { preview.bind(to: document) }
        .alert("Dışa aktarma", isPresented: $showResult) {
            if let dir = exportedDirectory {
                Button("Finder'da Göster") {
                    NSWorkspace.shared.activateFileViewerSelecting([dir])
                }
            }
            Button("Tamam", role: .cancel) {}
        } message: {
            Text(resultMessage)
        }
    }

    // MARK: Editor

    private var editor: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ThemeEditor()

                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Kartlar kare sınırlarına oturabilir; konum kare cinsindendir: 1,0 birinci ve ikinci karenin sınırı, 0,5 birinci karenin ortasıdır. İkon için bir SF Symbol adı yazın; boş bırakılırsa küçük bir nokta çizilir.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if document.showChips {
                            ForEach(document.chips) { chip in
                                ChipEditor(
                                    chip: document.chipBinding(for: chip.id),
                                    frameCount: document.frames.count,
                                    onRemove: { document.removeChip(id: chip.id) }
                                )
                            }
                            Button {
                                document.addChip()
                            } label: {
                                Label("Kart ekle", systemImage: "plus")
                            }
                            .disabled(document.chips.count >= Document.maxChips)
                        }
                    }
                    .padding(4)
                } label: {
                    Toggle("Yüzen kartlar", isOn: $document.showChips)
                        .font(.headline)
                }

                ForEach(document.frames) { frame in
                    FrameEditor(
                        index: document.index(of: frame.id),
                        frame: document.binding(for: frame.id),
                        canRemove: document.frames.count > 1,
                        onPick: { pickImage(for: frame.id) },
                        onDrop: { url in document.setImage(from: url, for: frame.id) },
                        onRemove: { document.removeFrame(id: frame.id) }
                    )
                }
            }
            .padding(16)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: Preview

    private var previewPane: some View {
        ZStack {
            Color(nsColor: .underPageBackgroundColor)

            if preview.frames.isEmpty {
                ProgressView("Önizleme hazırlanıyor…")
            } else {
                GeometryReader { geo in
                    let spacing: CGFloat = 12
                    let count = CGFloat(preview.frames.count)
                    let availableW = geo.size.width - 48 - spacing * (count - 1)
                    let availableH = geo.size.height - 48
                    let aspect = Renderer.frameWidth / Renderer.frameHeight
                    let frameH = min(availableH, availableW / count / aspect)
                    let frameW = frameH * aspect

                    HStack(spacing: spacing) {
                        ForEach(Array(preview.frames.enumerated()), id: \.offset) { _, image in
                            Image(nsImage: NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height)))
                                .resizable()
                                .interpolation(.high)
                                .frame(width: frameW, height: frameH)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .shadow(color: .black.opacity(0.35), radius: 18, y: 10)
                        }
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                }
            }

            if preview.isRendering && !preview.frames.isEmpty {
                VStack {
                    HStack {
                        Spacer()
                        ProgressView()
                            .controlSize(.small)
                            .padding(8)
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
                            .padding(12)
                    }
                    Spacer()
                }
            }

            if isExporting {
                Color.black.opacity(0.25)
                ProgressView("Dosyalar yazılıyor…")
                    .padding(20)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    // MARK: Actions

    private func pickImage(for id: FrameSpec.ID) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .heic, .image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Bu kare için ekran görüntüsünü seçin"
        panel.prompt = "Seç"
        if panel.runModal() == .OK, let url = panel.url {
            document.setImage(from: url, for: id)
        }
    }

    private func export() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Görsellerin kaydedileceği klasörü seçin"
        panel.prompt = "Buraya Kaydet"
        guard panel.runModal() == .OK, let directory = panel.url else { return }

        isExporting = true
        let spec = document.renderSpec
        Task.detached(priority: .userInitiated) {
            let result: Result<[URL], Error> = Result { try Renderer(spec: spec).export(to: directory) }
            await MainActor.run {
                isExporting = false
                switch result {
                case .success(let files):
                    exportedDirectory = directory
                    resultMessage = "\(files.count) dosya kaydedildi:\n\(directory.path)"
                case .failure(let error):
                    exportedDirectory = nil
                    resultMessage = "Hata: \(error.localizedDescription)"
                }
                showResult = true
            }
        }
    }
}

// MARK: - Theme editor

struct ThemeEditor: View {
    @EnvironmentObject private var document: Document

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                    GridRow {
                        ColorPicker("Fon üst", selection: $document.theme.bgTop, supportsOpacity: false)
                        ColorPicker("Fon alt", selection: $document.theme.bgBottom, supportsOpacity: false)
                    }
                    GridRow {
                        ColorPicker("Üst ışık", selection: $document.theme.glow, supportsOpacity: false)
                        ColorPicker("Alt ışık", selection: $document.theme.coolGlow, supportsOpacity: false)
                    }
                    GridRow {
                        ColorPicker("Rozet (1-2-3)", selection: $document.theme.badge, supportsOpacity: false)
                        ColorPicker("Rozet yazısı", selection: $document.theme.badgeText, supportsOpacity: false)
                    }
                    GridRow {
                        ColorPicker("Başlık", selection: $document.theme.headline, supportsOpacity: false)
                        ColorPicker("Vurgu (*kelime*)", selection: $document.theme.highlight, supportsOpacity: false)
                    }
                    GridRow {
                        ColorPicker("Alt metin", selection: $document.theme.sub, supportsOpacity: false)
                        Toggle("Izgara deseni", isOn: $document.theme.showGrid)
                    }
                }

                HStack(spacing: 12) {
                    Text("Metin yüksekliği")
                    Slider(value: $document.textY, in: 180...900)
                    Text("\(document.textY, specifier: "%.0f")").monospacedDigit().frame(width: 44, alignment: .trailing)
                }
                .font(.callout)
                .foregroundStyle(.secondary)

                HStack {
                    Text("Vurgulu kelimenin yeri başlıkta *yıldız* işaretleriyle belirlenir; hizayı her karede ayrı seçebilirsiniz.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Sıfırla") { document.resetTheme() }
                        .controlSize(.small)
                }
            }
            .padding(4)
        } label: {
            Text("Renkler ve metin").font(.headline)
        }
    }
}

// MARK: - Chip editor

struct ChipEditor: View {
    @Binding var chip: ChipSpec
    let frameCount: Int
    let onRemove: () -> Void

    private var symbolIsValid: Bool { Symbols.isValid(chip.symbol.trimmingCharacters(in: .whitespaces)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TextField("Kart metni", text: $chip.text)
                    .textFieldStyle(.roundedBorder)

                Button(role: .destructive) {
                    onRemove()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Kartı sil")
            }

            HStack(spacing: 8) {
                ZStack {
                    Circle().fill(chip.iconColor)
                    if symbolIsValid {
                        Image(systemName: chip.symbol.trimmingCharacters(in: .whitespaces))
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                    } else {
                        Circle().fill(chip.iconColor).frame(width: 10, height: 10)
                            .overlay(Circle().stroke(.white, lineWidth: 1.5))
                    }
                }
                .frame(width: 24, height: 24)

                TextField("SF Symbol adı (boş = nokta)", text: $chip.symbol)
                    .textFieldStyle(.roundedBorder)
                    .foregroundStyle(chip.symbol.isEmpty || symbolIsValid ? Color.primary : Color.red)

                Menu {
                    Button("Nokta (ikon yok)") { chip.symbol = "" }
                    Divider()
                    ForEach(ChipSpec.suggestedSymbols, id: \.self) { name in
                        Button {
                            chip.symbol = name
                        } label: {
                            Label(name, systemImage: name)
                        }
                    }
                } label: {
                    Image(systemName: "chevron.down.circle")
                }
                .menuStyle(.borderlessButton)
                .frame(width: 24)
                .help("Hazır ikonlardan seç")

                ColorPicker("", selection: $chip.iconColor, supportsOpacity: false)
                    .labelsHidden()
                    .help("İkon rengi")
            }

            HStack(spacing: 16) {
                Toggle("İlerleme çubuğu", isOn: $chip.showProgress)
                if chip.showProgress {
                    Stepper("Dolu: \(chip.done)", value: $chip.done, in: 0...chip.total)
                    Stepper("Toplam: \(chip.total)", value: $chip.total, in: 1...20)
                        .onChange(of: chip.total) { newTotal in
                            if chip.done > newTotal { chip.done = newTotal }
                        }
                }
            }
            .font(.callout)

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                GridRow {
                    Text("Konum").frame(width: 48, alignment: .leading)
                    Slider(value: $chip.x, in: 0...Double(frameCount))
                    Text("\(chip.x, specifier: "%.2f")").monospacedDigit().frame(width: 44, alignment: .trailing)
                }
                GridRow {
                    Text("Dikey").frame(width: 48, alignment: .leading)
                    Slider(value: $chip.y, in: 300...2600)
                    Text("\(chip.y, specifier: "%.0f")").monospacedDigit().frame(width: 44, alignment: .trailing)
                }
                GridRow {
                    Text("Eğim").frame(width: 48, alignment: .leading)
                    Slider(value: $chip.angle, in: -12...12)
                    Text("\(chip.angle, specifier: "%.0f")°").monospacedDigit().frame(width: 44, alignment: .trailing)
                }
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Frame editor

struct FrameEditor: View {
    let index: Int
    @Binding var frame: FrameSpec
    let canRemove: Bool
    let onPick: () -> Void
    let onDrop: (URL) -> Void
    let onRemove: () -> Void

    @State private var isTargeted = false

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    dropZone
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Adım etiketi", text: $frame.label)
                        TextField("Başlık (*kelime* turuncu olur)", text: $frame.headline, axis: .vertical)
                            .lineLimit(2...3)
                        TextField("Alt metin", text: $frame.sub)
                        Picker("Hiza", selection: $frame.align) {
                            Text("Sol").tag(HAlign.left)
                            Text("Orta").tag(HAlign.center)
                            Text("Sağ").tag(HAlign.right)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                    .textFieldStyle(.roundedBorder)
                }

                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                    GridRow {
                        Text("Eğim").frame(width: 48, alignment: .leading)
                        Slider(value: $frame.angle, in: -12...12)
                        Text("\(frame.angle, specifier: "%.0f")°").monospacedDigit().frame(width: 44, alignment: .trailing)
                    }
                    GridRow {
                        Text("Yatay").frame(width: 48, alignment: .leading)
                        Slider(value: $frame.dx, in: -200...200)
                        Text("\(frame.dx, specifier: "%.0f")").monospacedDigit().frame(width: 44, alignment: .trailing)
                    }
                    GridRow {
                        Text("Dikey").frame(width: 48, alignment: .leading)
                        Slider(value: $frame.dy, in: -200...200)
                        Text("\(frame.dy, specifier: "%.0f")").monospacedDigit().frame(width: 44, alignment: .trailing)
                    }
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }
            .padding(4)
        } label: {
            HStack {
                Text("Kare \(index + 1)").font(.headline)
                if let name = frame.imageURL?.lastPathComponent {
                    Text(name).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
                Spacer()
                Button(role: .destructive) {
                    onRemove()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .disabled(!canRemove)
                .help("Kareyi sil")
            }
        }
    }

    private var dropZone: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor))
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(style: StrokeStyle(lineWidth: isTargeted ? 2 : 1, dash: [5]))
                .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary.opacity(0.6))

            if let image = frame.image {
                Image(nsImage: NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height)))
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .padding(5)
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "photo")
                        .font(.title2)
                    Text("Sürükle\nveya tıkla")
                        .font(.caption2)
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(.secondary)
            }
        }
        .frame(width: 100, height: 200)
        .contentShape(Rectangle())
        .onTapGesture(perform: onPick)
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            onDrop(url)
            return true
        } isTargeted: { targeted in
            isTargeted = targeted
        }
        .help("Ekran görüntüsünü buraya sürükleyin veya seçmek için tıklayın")
    }
}
