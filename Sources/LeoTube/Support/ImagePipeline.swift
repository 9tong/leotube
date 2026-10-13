import AppKit
import CoreImage
import SwiftUI
import YTMusicKit

/// Memory + disk cached image loading with request coalescing.
actor ImagePipeline {
    static let shared = ImagePipeline()

    private let session: URLSession
    private let memory = NSCache<NSURL, NSImage>()
    private var inflight: [URL: Task<NSImage?, Never>] = [:]
    private var colors: [URL: NSColor] = [:]
    private let ciContext = CIContext(options: [.workingColorSpace: NSNull()])

    init() {
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LeoTube/Images", isDirectory: true)
        let cfg = URLSessionConfiguration.default
        cfg.urlCache = URLCache(memoryCapacity: 64 << 20, diskCapacity: 512 << 20, directory: cacheDir)
        cfg.requestCachePolicy = .returnCacheDataElseLoad
        session = URLSession(configuration: cfg)
        memory.countLimit = 600
    }

    nonisolated func cached(_ url: URL) -> NSImage? {
        memory.object(forKey: url as NSURL)
    }

    func image(for url: URL) async -> NSImage? {
        if let img = memory.object(forKey: url as NSURL) { return img }
        if let t = inflight[url] { return await t.value }
        let task = Task<NSImage?, Never> { [session] in
            guard let (data, _) = try? await session.data(from: url), let img = NSImage(data: data) else { return nil }
            return img
        }
        inflight[url] = task
        let img = await task.value
        inflight[url] = nil
        if let img { memory.setObject(img, forKey: url as NSURL) }
        return img
    }

    /// A vivid-but-dark average color, suited to page backgrounds.
    func dominantColor(for url: URL) async -> NSColor? {
        if let c = colors[url] { return c }
        guard let img = await image(for: url),
              let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let ci = CIImage(cgImage: cg)
        guard let filter = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: ci, kCIInputExtentKey: CIVector(cgRect: ci.extent),
        ]), let out = filter.outputImage else { return nil }
        var px = [UInt8](repeating: 0, count: 4)
        ciContext.render(out, toBitmap: &px, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                         format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
        let base = NSColor(srgbRed: CGFloat(px[0]) / 255, green: CGFloat(px[1]) / 255, blue: CGFloat(px[2]) / 255, alpha: 1)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        base.usingColorSpace(.sRGB)?.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        let color = NSColor(hue: h, saturation: min(1, s * 1.25 + 0.08), brightness: min(max(b, 0.42), 0.62), alpha: 1)
        colors[url] = color
        return color
    }
}

/// Async artwork view with fade-in, placeholder and caching.
struct ArtworkView: View {
    var artwork: Artwork?
    var size: Int = 300
    var cornerRadius: CGFloat = 8
    var circle = false
    var contentMode: ContentMode = .fill
    var placeholderSymbol = "music.note"

    @State private var image: NSImage?

    private var url: URL? { artwork?.url(size: size) }

    var body: some View {
        Color.clear.overlay {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .transition(.opacity)
            } else {
                Rectangle()
                    .fill(.quaternary.opacity(0.6))
                    .overlay {
                        Image(systemName: placeholderSymbol)
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(.tertiary)
                    }
            }
        }
        .clipShape(shape)
        .contentShape(shape)
        .task(id: url) {
            guard let url else { image = nil; return }
            if let c = ImagePipeline.shared.cached(url) { image = c; return }
            let img = await ImagePipeline.shared.image(for: url)
            withAnimation(.easeOut(duration: 0.25)) { image = img }
        }
    }

    private var shape: AnyShape {
        circle ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

/// Resolves and animates the dominant color of an artwork.
struct DominantColorReader: ViewModifier {
    var artwork: Artwork?
    @Binding var color: Color

    func body(content: Content) -> some View {
        content.task(id: artwork?.url(size: 120)) {
            guard let url = artwork?.url(size: 120), let c = await ImagePipeline.shared.dominantColor(for: url) else { return }
            withAnimation(.easeInOut(duration: 0.6)) { color = Color(nsColor: c) }
        }
    }
}

extension View {
    func dominantColor(of artwork: Artwork?, into color: Binding<Color>) -> some View {
        modifier(DominantColorReader(artwork: artwork, color: color))
    }
}
