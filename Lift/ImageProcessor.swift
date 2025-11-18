import SwiftUI
import Vision
import CoreImage
import CoreImage.CIFilterBuiltins

@MainActor
class ImageProcessor: ObservableObject {
    
    enum Status {
        case idle
        case processing
        case finished(original: NSImage, processed: NSImage)
        case failed(Error)
    }
    
    @Published var status: Status = .idle
    
    // 主入口函数，处理拖入的图片
    func processImage(at url: URL) {
        self.status = .processing
        
        Task.detached(priority: .userInitiated) {
            do {
                // 0. 确保有文件访问权限（处理沙盒限制）
                let shouldStopAccessing = url.startAccessingSecurityScopedResource()
                defer {
                    if shouldStopAccessing {
                        url.stopAccessingSecurityScopedResource()
                    }
                }
                
                // 1. 加载图片 (在后台任务中访问 MainActor 隔离的 'self'，需要 await)
                guard let sourceImage = await self.loadImage(from: url) else {
                    throw NSError(domain: "ImageProcessor", code: 1, userInfo: [NSLocalizedDescriptionKey: "无法加载图片"])
                }
                
                // 2. 移除背景
                let imageWithoutBackground = try await self.removeBackground(from: sourceImage)
                
                // 3. 裁切透明区域 (同样需要 await)
                guard let trimmedImage = await self.trimTransparentPixels(from: imageWithoutBackground) else {
                    throw NSError(domain: "ImageProcessor", code: 2, userInfo: [NSLocalizedDescriptionKey: "裁切图片失败"])
                }
                
                // 4. 转换为 NSImage 并更新UI（创建独立的图片副本，避免访问权限问题）
                let originalNSImage = await self.createNSImage(from: sourceImage)
                let processedNSImage = await self.createNSImage(from: trimmedImage)
                
                await MainActor.run {
                    self.status = .finished(original: originalNSImage, processed: processedNSImage)
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
    
    // 步骤 A: 使用 Vision 框架移除背景
    private func removeBackground(from image: CGImage) async throws -> CGImage {
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
