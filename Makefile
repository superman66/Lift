.PHONY: build build-debug build-release clean run open test help

# 默认目标
help:
	@echo "Lift 项目构建命令:"
	@echo ""
	@echo "  make build         - 构建 Debug 版本"
	@echo "  make build-release - 构建 Release 版本 (优化)"
	@echo "  make clean         - 清理构建产物"
	@echo "  make run           - 运行 Release 版本"
	@echo "  make open          - 在 Finder 中打开构建目录"
	@echo "  make test          - 运行测试"
	@echo "  make rebuild       - 清理并重新构建 Release 版本"
	@echo ""

# 构建 Debug 版本
build:
	@echo "🔨 构建 Debug 版本..."
	xcodebuild -project Lift.xcodeproj -scheme Lift -configuration Debug build

# 构建 Release 版本
build-release:
	@echo "🚀 构建 Release 版本..."
	xcodebuild -project Lift.xcodeproj -scheme Lift -configuration Release build
	@echo "✅ 构建完成!"
	@echo "📦 应用位置: $$(xcodebuild -project Lift.xcodeproj -scheme Lift -configuration Release -showBuildSettings | grep -m 1 "BUILT_PRODUCTS_DIR" | sed 's/.*= //')/Lift.app"

# 清理构建产物
clean:
	@echo "🧹 清理构建产物..."
	xcodebuild -project Lift.xcodeproj -scheme Lift clean
	@echo "✅ 清理完成!"

# 清理并重新构建
rebuild: clean build-release

# 运行 Release 版本
run:
	@echo "▶️  运行应用..."
	@BUILD_DIR=$$(xcodebuild -project Lift.xcodeproj -scheme Lift -configuration Release -showBuildSettings | grep -m 1 "BUILT_PRODUCTS_DIR" | sed 's/.*= //'); \
	open "$$BUILD_DIR/Lift.app"

# 在 Finder 中打开构建目录
open:
	@BUILD_DIR=$$(xcodebuild -project Lift.xcodeproj -scheme Lift -configuration Release -showBuildSettings | grep -m 1 "BUILT_PRODUCTS_DIR" | sed 's/.*= //'); \
	open "$$BUILD_DIR"

# 运行测试
test:
	@echo "🧪 运行测试..."
	xcodebuild -project Lift.xcodeproj -scheme Lift -destination 'platform=macOS' test
