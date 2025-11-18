import SwiftUI

struct ContentView: View {
    // 状态管理：持有 ImageProcessor 的实例
    @StateObject private var imageProcessor = ImageProcessor()
    
    var body: some View {
        VStack {
            // 根据 ImageProcessor 的状态切换视图
            switch imageProcessor.status {
            case .idle:
                DropZoneView(onDrop: handleDrop)
            case .processing:
                ProcessingView()
            case .finished(let original, let processed):
                FinishedView(
                    originalImage: original,
                    processedImage: processed,
                    onSave: handleSave,
                    onCopy: handleCopy,
                    onReset: reset
                )
            case .failed(let error):
                ErrorView(error: error, onReset: reset)
            }
        }
        .frame(minWidth: 300, minHeight: 300)
        .padding()
    }
    
    // 处理文件拖放
    private func handleDrop(url: URL) {
        imageProcessor.processImage(at: url)
    }
    
    // 处理保存操作
    private func handleSave(image: NSImage) {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.png]
        savePanel.canCreateDirectories = true
        savePanel.nameFieldStringValue = "processed_image.png"
        
        if savePanel.runModal() == .OK, let url = savePanel.url {
            imageProcessor.saveImage(image, to: url)
        }
    }
    
    // 处理复制到剪贴板
    private func handleCopy(image: NSImage) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
    }
    
    // 重置视图状态
    private func reset() {
        imageProcessor.status = .idle
    }
}

// MARK: - Subviews

// 拖放区域视图
struct DropZoneView: View {
    var onDrop: (URL) -> Void
    
    @State private var isTargeted = false
    @State private var isFilePickerPresented = false
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.largeTitle)
                .padding(.bottom, 8)
            
            Text("拖入图片自动去底 + 裁切")
                .font(.headline)
            
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
            if let provider = providers.first {
                provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { (item, error) in
                    if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                        DispatchQueue.main.async {
                            onDrop(url)
                        }
                    }
                }
                return true
            }
            return false
        }
        .fileImporter(
            isPresented: $isFilePickerPresented,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    // 获取安全访问权限
                    if url.startAccessingSecurityScopedResource() {
                        defer { url.stopAccessingSecurityScopedResource() }
                        onDrop(url)
                    } else {
                        onDrop(url)
                    }
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
    let onSave: (NSImage) -> Void
    let onCopy: (NSImage) -> Void
    let onReset: () -> Void
    
    var body: some View {
        VStack {
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
            
            HStack {
                Button(action: { onSave(processedImage) }) {
                    Label("保存图片", systemImage: "square.and.arrow.down")
                }
                
                Button(action: { onCopy(processedImage) }) {
                    Label("复制到剪贴板", systemImage: "doc.on.doc")
                }
                
                Button("处理新图片", action: onReset)
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

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
