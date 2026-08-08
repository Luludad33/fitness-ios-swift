import SwiftUI
import UIKit
import ImageIO

/// 检查 bundle 里是否有指定名字的 .gif 资源（名字 = 动作 id）
func bundleHasGIF(named name: String) -> Bool {
    Bundle.main.url(forResource: name, withExtension: "gif") != nil
}

/// 读取 bundle 内 `<name>.gif` 第一帧的像素尺寸，用于详情页头图按原生宽高比自适应高度（避免竖版图显示过小）。
func gifPixelSize(named name: String) -> CGSize? {
    guard let url = Bundle.main.url(forResource: name, withExtension: "gif"),
          let data = try? Data(contentsOf: url),
          let source = CGImageSourceCreateWithData(data as CFData, nil),
          let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
          let w = props[kCGImagePropertyPixelWidth] as? Double,
          let h = props[kCGImagePropertyPixelHeight] as? Double else {
        return nil
    }
    return CGSize(width: w, height: h)
}

/// GIF 播放视图：从 bundle 读取 `<gifName>.gif`，解码成帧后用 UIImageView 帧动画循环播放。
/// 用 UIImageView.animationImages（而非手写定时器），播放最稳、最省电。
struct GIFView: UIViewRepresentable {
    let gifName: String

    func makeUIView(context: Context) -> UIImageView {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.backgroundColor = .clear
        context.coordinator.loadedName = gifName
        loadFrames(into: imageView)
        return imageView
    }

    func updateUIView(_ uiView: UIImageView, context: Context) {
        // 名字变化时重新加载（本项目每个 GIFView 名字固定，通常不会触发）
        if context.coordinator.loadedName != gifName {
            context.coordinator.loadedName = gifName
            loadFrames(into: uiView)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var loadedName: String?
    }

    private func loadFrames(into imageView: UIImageView) {
        guard let url = Bundle.main.url(forResource: gifName, withExtension: "gif"),
              let data = try? Data(contentsOf: url),
              let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            imageView.image = nil
            imageView.animationImages = nil
            return
        }

        let count = CGImageSourceGetCount(source)
        var frames: [UIImage] = []
        var totalDelay: Double = 0
        for i in 0..<count {
            guard let cg = CGImageSourceCreateImageAtIndex(source, i, nil) else { continue }
            frames.append(UIImage(cgImage: cg))
            totalDelay += frameDelay(at: i, source: source)
        }
        guard !frames.isEmpty else { return }

        imageView.animationImages = frames
        // 总时长用真实帧延迟之和；若 GIF 没写延迟则按每帧 0.1s
        imageView.animationDuration = totalDelay > 0 ? totalDelay : Double(frames.count) * 0.1
        imageView.animationRepeatCount = 0   // 0 = 无限循环
        imageView.image = frames.first
        imageView.startAnimating()
    }

    private func frameDelay(at index: Int, source: CGImageSource) -> Double {
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
              let gifProps = props[kCGImagePropertyGIFDictionary] as? [CFString: Any] else {
            return 0.1
        }
        let delay = (gifProps[kCGImagePropertyGIFUnclampedDelayTime] as? Double)
            ?? (gifProps[kCGImagePropertyGIFDelayTime] as? Double)
            ?? 0.1
        // 浏览器/系统会把过短帧钳制到 ~100ms，保持一致
        return delay < 0.011 ? 0.1 : delay
    }
}
