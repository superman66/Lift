import SwiftUI
import Vision
import CoreImage
import CoreImage.CIFilterBuiltins

@MainActor
class ImageProcessor: ObservableObject {
    
    /// 处理结果结构体
    struct ProcessedResult {
        let original: NSImage
        let processed: NSImage
        let originalFileName: String
    }
    
    enum Status {
        case idle
        case processing
        case finished(original: NSImage, processed: NSImage, currentIndex: Int, totalCount: Int)
        case failed(Error)
    }
    
    /// 背景移除方式
    enum BackgroundRemovalMethod: String, CaseIterable {
        case removeBG = "RemoveBG API"
        case vision = "Vision 框架"
    }
    
    private let removeBGAPIKey = "vFjZkwirpj5wBZsFM85gpJRF"
    private let removeBGAPIURL = "https://api.remove.bg/v1.0/removebg"
    
    @Published var status: Status = .idle
    @Published var removalMethod: BackgroundRemovalMethod = .removeBG
    
    // 批量处理支持
    @Published var imageQueue: [URL] = []
    @Published var currentIndex: Int = 0
    @Published var totalCount: Int = 0
    @Published var processedResults: [ProcessedResult] = []
    
    // 批量处理入口函数
    func processImages(urls: [URL]) {
        guard !urls.isEmpty else { return }
        self.imageQueue = urls
        self.currentIndex = 0
        self.totalCount = urls.count
        processNextImage()
    }
    
    // 处理队列中的下一张图片
    func processNextImage() {
        guard currentIndex < imageQueue.count else {
            // 所有图片处理完成，重置状态
            reset()
            return
        }
        
        let url = imageQueue[currentIndex]
        processImage(at: url)
    }
    
    // 跳过当前图片，处理下一张
    func skipCurrentImage() {
        currentIndex += 1
        processNextImage()
    }
    
    // 切换查看不同的处理结果
    func navigateToImage(at index: Int) {
        guard index >= 0 && index < processedResults.count else { return }
        let result = processedResults[index]
        currentIndex = index
        status = .finished(
            original: result.original,
            processed: result.processed,
            currentIndex: index,
            totalCount: totalCount
        )
    }
    
    // 重置到初始状态
    func reset() {
        imageQueue = []
        currentIndex = 0
        totalCount = 0
        processedResults = []
        status = .idle
    }
    
    // 主入口函数，处理拖入的图片
    func processImage(at url: URL) {
        self.status = .processing
        
        // 提取原始文件名（不含扩展名）
        let originalFileName = url.deletingPathExtension().lastPathComponent
        
        // 获取当前选择的方法（在进入 Task 之前捕获）
        let method = self.removalMethod
        
        Task.detached(priority: .userInitiated) {
            do {
                // 0. 确保有文件访问权限（处理沙盒限制）
                let shouldStopAccessing = url.startAccessingSecurityScopedResource()
                defer {
                    if shouldStopAccessing {
                        url.stopAccessingSecurityScopedResource()
                    }
                }
                
                // 1. 加载图片数据
                let imageData = try Data(contentsOf: url)
                
                // 2. 加载图片 (在后台任务中访问 MainActor 隔离的 'self'，需要 await)
                guard let sourceImage = await self.loadImage(from: url) else {
                    throw NSError(domain: "ImageProcessor", code: 1, userInfo: [NSLocalizedDescriptionKey: "无法加载图片"])
                }
                
                // 3. 根据选择的方法移除背景
                let imageWithoutBackground: CGImage
                switch method {
                case .removeBG:
                    imageWithoutBackground = try await self.removeBackgroundWithRemoveBG(imageData: imageData)
                case .vision:
                    imageWithoutBackground = try await self.removeBackgroundWithVision(from: sourceImage)
                }
                
                // 4. 裁切透明区域 (同样需要 await)
                guard let trimmedImage = await self.trimTransparentPixels(from: imageWithoutBackground) else {
                    throw NSError(domain: "ImageProcessor", code: 2, userInfo: [NSLocalizedDescriptionKey: "裁切图片失败"])
                }
                
                // 5. 转换为 NSImage 并更新UI（创建独立的图片副本，避免访问权限问题）
                let originalNSImage = await self.createNSImage(from: sourceImage)
                let processedNSImage = await self.createNSImage(from: trimmedImage)
                
                await MainActor.run {
                    // 存储处理结果
                    let result = ProcessedResult(
                        original: originalNSImage,
                        processed: processedNSImage,
                        originalFileName: originalFileName
                    )
                    if self.currentIndex < self.processedResults.count {
                        self.processedResults[self.currentIndex] = result
                    } else {
                        self.processedResults.append(result)
                    }
                    
                    self.status = .finished(
                        original: originalNSImage,
                        processed: processedNSImage,
                        currentIndex: self.currentIndex,
                        totalCount: self.totalCount
                    )
                }
                
            } catch {
                await MainActor.run {
                    self.status = .failed(error)
                }
            }
        }
    }
    
    // 从 URL 加载 CGImage
    private func loadImage(from url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }
        return image
    }
    
    // 创建独立的 NSImage 副本（避免访问权限问题）
    private func createNSImage(from cgImage: CGImage) -> NSImage {
        let width = cgImage.width
        let height = cgImage.height
        let size = NSSize(width: width, height: height)
        
        // 创建位图表示
        let bitmapRep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        
        // 将 CGImage 绘制到位图中
        let context = NSGraphicsContext(bitmapImageRep: bitmapRep)!
        NSGraphicsContext.current = context
        
        let rect = NSRect(origin: .zero, size: size)
        let cgContext = context.cgContext
        cgContext.draw(cgImage, in: rect)
        
        // 创建新的 NSImage
        let image = NSImage(size: size)
        image.addRepresentation(bitmapRep)
        
        return image
    }
    
    // MARK: - RemoveBG API 方法
    
    /// 使用 RemoveBG API 移除背景
    private func removeBackgroundWithRemoveBG(imageData: Data) async throws -> CGImage {
        guard let url = URL(string: removeBGAPIURL) else {
            throw NSError(domain: "RemoveBG", code: 0, userInfo: [NSLocalizedDescriptionKey: "无效的 API URL"])
        }
        
        // 创建 multipart/form-data 请求
        let boundary = UUID().uuidString
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue(removeBGAPIKey, forHTTPHeaderField: "X-Api-Key")
        
        // 构建 multipart body
        var body = Data()
        
        // 添加图片数据
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"image_file\"; filename=\"image.png\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/png\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n".data(using: .utf8)!)
        
        // 添加结束边界
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = body
        
        // 发送请求
        let (responseData, response) = try await URLSession.shared.data(for: request)
        
        // 检查响应状态
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "RemoveBG", code: 1, userInfo: [NSLocalizedDescriptionKey: "无效的服务器响应"])
        }
        
        if httpResponse.statusCode != 200 {
            // 尝试解析错误信息
            if let errorJson = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
               let errors = errorJson["errors"] as? [[String: Any]],
               let firstError = errors.first,
               let title = firstError["title"] as? String {
                throw NSError(domain: "RemoveBG", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "RemoveBG API 错误: \(title)"])
            }
            throw NSError(domain: "RemoveBG", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "RemoveBG API 请求失败，状态码: \(httpResponse.statusCode)"])
        }
        
        // 将响应数据转换为 CGImage
        guard let dataProvider = CGDataProvider(data: responseData as CFData),
              let cgImage = CGImage(pngDataProviderSource: dataProvider,
                                    decode: nil,
                                    shouldInterpolate: true,
                                    intent: .defaultIntent) else {
            // 尝试使用 NSImage 解析（支持更多格式）
            guard let nsImage = NSImage(data: responseData),
                  let tiffData = nsImage.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiffData),
                  let resultCGImage = bitmap.cgImage else {
                throw NSError(domain: "RemoveBG", code: 2, userInfo: [NSLocalizedDescriptionKey: "无法解析返回的图片数据"])
            }
            return resultCGImage
        }
        
        return cgImage
    }
    
    // MARK: - Vision 框架方法
    
    /// 使用 Vision 框架移除背景
    private func removeBackgroundWithVision(from image: CGImage) async throws -> CGImage {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: image)
        
        try handler.perform([request])
        
        guard let result = request.results?.first else {
            throw NSError(domain: "Vision", code: 1, userInfo: [NSLocalizedDescriptionKey: "无法获取主体蒙版"])
        }
        
        // 使用 Core Image 处理
        let originalCI = CIImage(cgImage: image)
        
        // 生成缩放后的蒙版
        let maskPixelBuffer = try result.generateScaledMaskForImage(forInstances: result.allInstances, from: handler)
        let maskCI = CIImage(cvPixelBuffer: maskPixelBuffer)
        
        // 确保蒙版和原图尺寸一致
        let scaledMask = maskCI.transformed(by: CGAffineTransform(
            scaleX: originalCI.extent.width / maskCI.extent.width,
            y: originalCI.extent.height / maskCI.extent.height
        ))
        
        // 使用蒙版混合，背景设为透明
        let blendFilter = CIFilter.blendWithMask()
        blendFilter.inputImage = originalCI
        blendFilter.backgroundImage = CIImage.empty()
        blendFilter.maskImage = scaledMask
        
        guard let output = blendFilter.outputImage else {
            throw NSError(domain: "CoreImage", code: 1, userInfo: [NSLocalizedDescriptionKey: "蒙版混合失败"])
        }
        
        let context = CIContext(options: [.useSoftwareRenderer: false])
        guard let cgImage = context.createCGImage(output, from: originalCI.extent) else {
            throw NSError(domain: "CoreImage", code: 2, userInfo: [NSLocalizedDescriptionKey: "无法创建最终图片"])
        }
        
        return cgImage
    }
    
    // 步骤 B: 裁切透明像素
    private func trimTransparentPixels(from image: CGImage) -> CGImage? {
        let width = image.width
        let height = image.height
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        let bitsPerComponent = 8
        
        // 获取像素数据
        var pixelData = [UInt8](repeating: 0, count: width * height * bytesPerPixel)
        guard let context = CGContext(
            data: &pixelData,
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        // 寻找非透明区域的边界
        var minX = width, minY = height, maxX = -1, maxY = -1
        
        for y in 0..<height {
            for x in 0..<width {
                let pixelIndex = (y * width + x) * bytesPerPixel
                let alphaIndex = pixelIndex + 3
                
                // 确保索引在有效范围内
                guard alphaIndex < pixelData.count else { continue }
                
                if pixelData[alphaIndex] > 0 {
                    if x < minX { minX = x }
                    if x > maxX { maxX = x }
                    if y < minY { minY = y }
                    if y > maxY { maxY = y }
                }
            }
        }
        
        // 如果没有找到任何非透明像素，则返回原图
        guard maxX != -1, minY != height else {
            return image
        }
        
        // 根据边界创建一个新的矩形并裁切
        let cropRect = CGRect(
            x: minX,
            y: minY,
            width: maxX - minX + 1,
            height: maxY - minY + 1
        )
        
        return image.cropping(to: cropRect)
    }
    
    // 将 NSImage 保存到文件
    func saveImage(_ image: NSImage, to url: URL) {
        // 使用 tiffRepresentation 和 NSBitmapImageRep 来安全地获取 CGImage
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            print("无法转换图片数据")
            return
        }
        
        do {
            try pngData.write(to: url)
        } catch {
            print("保存图片失败: \(error.localizedDescription)")
        }
    }
}
