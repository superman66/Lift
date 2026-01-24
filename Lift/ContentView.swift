import SwiftUI

struct ContentView: View {
    // 状态管理：持有 ImageProcessor 的实例
    @StateObject private var imageProcessor = ImageProcessor()
    
    var body: some View {
        VStack {
            // 根据 ImageProcessor 的状态切换视图
            switch imageProcessor.status {
            case .idle:
                DropZoneView(onDrop: handleDrop, removalMethod: $imageProcessor.removalMethod)
            case .processing:
                ProcessingView()
            case .finished(let original, let processed, let currentIndex, let totalCount):
                FinishedView(
                    originalImage: original,
                    processedImage: processed,
                    currentIndex: currentIndex,
                    totalCount: totalCount,
                    onSave: handleSave,
                    onCopy: handleCopy,
                    onSkip: skipCurrent,
                    onReset: reset,
                    imageProcessor: imageProcessor
                )
            case .failed(let error):
                ErrorView(error: error, onReset: reset)
            }
        }
        .frame(minWidth: 300, minHeight: 300)
        .padding()
    }
    
    // 处理文件拖放（支持多文件）
    private func handleDrop(urls: [URL]) {
        imageProcessor.processImages(urls: urls)
    }
    
    // 处理保存操作
    private func handleSave(image: NSImage, fileName: String) {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.png]
        savePanel.canCreateDirectories = true
        savePanel.nameFieldStringValue = "\(fileName).png"
        
        if savePanel.runModal() == .OK, let url = savePanel.url {
            imageProcessor.saveImage(image, to: url)
            // 保存后自动处理下一张（如果有的话）
            imageProcessor.currentIndex += 1
            imageProcessor.processNextImage()
        }
    }
    
    // 处理复制到剪贴板
    private func handleCopy(image: NSImage) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
        // 复制后自动处理下一张（如果有的话）
        imageProcessor.currentIndex += 1
        imageProcessor.processNextImage()
    }
    
    // 跳过当前图片
    private func skipCurrent() {
        imageProcessor.skipCurrentImage()
    }
    
    // 重置视图状态
    private func reset() {
        imageProcessor.reset()
    }
}

// MARK: - Subviews

// 拖放区域视图
struct DropZoneView: View {
    var onDrop: ([URL]) -> Void
    @Binding var removalMethod: ImageProcessor.BackgroundRemovalMethod
    
    @State private var isTargeted = false
    @State private var isFilePickerPresented = false
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.largeTitle)
                .padding(.bottom, 8)
            
            Text("拖入图片自动去底 + 裁切")
                .font(.headline)
            
            Text("支持单张或多张图片")
                .font(.caption)
                .foregroundColor(.secondary)
            
            // 背景移除方式选择
            Picker("移除方式", selection: $removalMethod) {
                ForEach(ImageProcessor.BackgroundRemovalMethod.allCases, id: \.self) { method in
                    Text(method.rawValue).tag(method)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 250)
            
            Text("或")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Button(action: {
                isFilePickerPresented = true
            }) {
                Label("选择图片", systemImage: "folder.badge.plus")
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(isTargeted ? Color.blue.opacity(0.1) : Color.clear)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [10]))
                .foregroundColor(isTargeted ? .blue : .gray.opacity(0.5))
        )
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            let group = DispatchGroup()
            var urls: [URL] = []
            
            for provider in providers {
                group.enter()
                provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { (item, error) in
                    if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                        urls.append(url)
                    }
                    group.leave()
                }
            }
            
            group.notify(queue: .main) {
                if !urls.isEmpty {
                    onDrop(urls)
                }
            }
            
            return true
        }
        .fileImporter(
            isPresented: $isFilePickerPresented,
            allowedContentTypes: [.image],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                var accessibleURLs: [URL] = []
                for url in urls {
                    if url.startAccessingSecurityScopedResource() {
                        accessibleURLs.append(url)
                        // 注意：这里不能立即调用 stopAccessingSecurityScopedResource
                        // 需要在处理完成后调用
                    } else {
                        accessibleURLs.append(url)
                    }
                }
                if !accessibleURLs.isEmpty {
                    onDrop(accessibleURLs)
                }
            case .failure(let error):
                print("选择文件失败: \(error.localizedDescription)")
            }
        }
    }
}

// 处理中视图
struct ProcessingView: View {
    var body: some View {
        VStack {
            ProgressView()
                .scaleEffect(1.5)
                .padding()
            Text("正在处理...")
                .font(.headline)
        }
    }
}

// 完成视图
struct FinishedView: View {
    let originalImage: NSImage
    let processedImage: NSImage
    let currentIndex: Int
    let totalCount: Int
    let onSave: (NSImage, String) -> Void
    let onCopy: (NSImage) -> Void
    let onSkip: () -> Void
    let onReset: () -> Void
    @ObservedObject var imageProcessor: ImageProcessor
    
    @State private var isDropTargeted = false
    
    var body: some View {
        VStack {
            // 批量处理进度显示
            if totalCount > 1 {
                HStack {
                    Text("图片 \(currentIndex + 1)/\(totalCount)")
                        .font(.headline)
                        .foregroundColor(.blue)
                    Spacer()
                }
                .padding(.horizontal)
            }
            
            HStack(spacing: 20) {
                VStack {
                    Text("处理前")
                    Image(nsImage: originalImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .border(Color.gray.opacity(0.5), width: 1)
                }
                
                VStack {
                    Text("处理后")
                    Image(nsImage: processedImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .background(checkerboardBackground) // 添加棋盘格背景
                }
            }
            .padding()
            
            HStack(spacing: 12) {
                Button(action: {
                    let fileName = imageProcessor.processedResults[currentIndex].originalFileName
                    onSave(processedImage, fileName)
                }) {
                    Label("保存图片", systemImage: "square.and.arrow.down")
                }
                .keyboardShortcut("s", modifiers: .command)
                
                Button(action: { onCopy(processedImage) }) {
                    Label("复制到剪贴板", systemImage: "doc.on.doc")
                }
                
                // 批量处理时显示跳过按钮
                if totalCount > 1 && currentIndex < totalCount - 1 {
                    Button(action: onSkip) {
                        Label("跳过", systemImage: "forward.fill")
                    }
                }
                
                Button("处理新图片", action: onReset)
            }
            .padding(.top, 8)
            
            // 批量处理时显示缩略图预览
            if totalCount > 1 {
                ThumbnailPreviewBar(
                    results: imageProcessor.processedResults,
                    currentIndex: currentIndex,
                    totalCount: totalCount,
                    onSelect: { index in
                        imageProcessor.navigateToImage(at: index)
                    }
                )
            }
        }
        .background(isDropTargeted ? Color.blue.opacity(0.1) : Color.clear)
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDropInFinishedView(providers)
            return true
        }
    }
    
    // 处理在结果页面的拖放
    private func handleDropInFinishedView(_ providers: [NSItemProvider]) {
        let group = DispatchGroup()
        var urls: [URL] = []
        
        for provider in providers {
            group.enter()
            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { (item, error) in
                if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                    urls.append(url)
                }
                group.leave()
            }
        }
        
        group.notify(queue: .main) {
            if !urls.isEmpty {
                // 重置并开始新的处理流程
                imageProcessor.reset()
                imageProcessor.processImages(urls: urls)
            }
        }
    }
    
    // 创建一个棋盘格背景，用于展示透明效果
    private var checkerboardBackground: some View {
        Canvas { context, size in
            let checkSize: CGFloat = 10
            for y in stride(from: 0, to: size.height, by: checkSize) {
                for x in stride(from: 0, to: size.width, by: checkSize) {
                    let isLight = (Int(x/checkSize) + Int(y/checkSize)) % 2 == 0
                    context.fill(
                        Path(CGRect(x: x, y: y, width: checkSize, height: checkSize)),
                        with: .color(isLight ? .white : Color(white: 0.9))
                    )
                }
            }
        }
    }
}

// 错误视图
struct ErrorView: View {
    let error: Error
    let onReset: () -> Void
    
    var body: some View {
        VStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundColor(.red)
                .padding()
            Text("处理失败")
                .font(.headline)
            Text(error.localizedDescription)
                .font(.caption)
                .multilineTextAlignment(.center)
                .padding()
            Button("重试", action: onReset)
        }
    }
}

// 缩略图预览栏
struct ThumbnailPreviewBar: View {
    let results: [ImageProcessor.ProcessedResult]
    let currentIndex: Int
    let totalCount: Int
    let onSelect: (Int) -> Void
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(0..<totalCount, id: \.self) { index in
                    ThumbnailView(
                        image: index < results.count ? results[index].processed : nil,
                        index: index,
                        isSelected: index == currentIndex,
                        onTap: { onSelect(index) }
                    )
                }
            }
            .padding(.horizontal)
        }
        .frame(height: 100)
        .background(Color.gray.opacity(0.1))
    }
}

// 单个缩略图视图
struct ThumbnailView: View {
    let image: NSImage?
    let index: Int
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        VStack(spacing: 4) {
            if let image = image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 60, height: 60)
                    .background(checkerboardBackground)
                    .cornerRadius(4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 3)
                    )
            } else {
                // 未处理的图片显示占位符
                ZStack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 60, height: 60)
                    ProgressView()
                        .scaleEffect(0.7)
                }
            }
            
            Text("\(index + 1)")
                .font(.caption2)
                .foregroundColor(isSelected ? .blue : .secondary)
        }
        .onTapGesture(perform: onTap)
    }
    
    // 创建一个棋盘格背景，用于展示透明效果
    private var checkerboardBackground: some View {
        Canvas { context, size in
            let checkSize: CGFloat = 5
            for y in stride(from: 0, to: size.height, by: checkSize) {
                for x in stride(from: 0, to: size.width, by: checkSize) {
                    let isLight = (Int(x/checkSize) + Int(y/checkSize)) % 2 == 0
                    context.fill(
                        Path(CGRect(x: x, y: y, width: checkSize, height: checkSize)),
                        with: .color(isLight ? .white : Color(white: 0.9))
                    )
                }
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
