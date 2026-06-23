#!/bin/bash

# Lift 项目快速构建脚本
# 使用方法: ./build.sh [debug|release|clean|run]

set -e

PROJECT="Lift.xcodeproj"
SCHEME="Lift"

# 颜色输出
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

function show_help() {
    echo -e "${BLUE}Lift 项目构建脚本${NC}"
    echo ""
    echo "使用方法: ./build.sh [命令]"
    echo ""
    echo "可用命令:"
    echo "  debug    - 构建 Debug 版本"
    echo "  release  - 构建 Release 版本 (默认)"
    echo "  clean    - 清理构建产物"
    echo "  run      - 构建并运行 Release 版本"
    echo "  install  - 构建并安装到 /Applications/Lift.app"
    echo "  test     - 运行测试"
    echo "  help     - 显示此帮助信息"
    echo ""
}

function build_debug() {
    echo -e "${BLUE}🔨 构建 Debug 版本...${NC}"
    xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Debug build
    echo -e "${GREEN}✅ Debug 构建完成!${NC}"
}

function build_release() {
    echo -e "${BLUE}🚀 构建 Release 版本...${NC}"
    xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release build
    
    BUILD_DIR=$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release -showBuildSettings | grep -m 1 "BUILT_PRODUCTS_DIR" | sed 's/.*= //')
    
    echo -e "${GREEN}✅ Release 构建完成!${NC}"
    echo -e "${YELLOW}📦 应用位置: $BUILD_DIR/Lift.app${NC}"
}

function clean_build() {
    echo -e "${BLUE}🧹 清理构建产物...${NC}"
    xcodebuild -project "$PROJECT" -scheme "$SCHEME" clean
    echo -e "${GREEN}✅ 清理完成!${NC}"
}

function run_app() {
    echo -e "${BLUE}🚀 构建并运行应用...${NC}"
    build_release
    
    BUILD_DIR=$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release -showBuildSettings | grep -m 1 "BUILT_PRODUCTS_DIR" | sed 's/.*= //')
    
    echo -e "${BLUE}▶️  启动应用...${NC}"
    open "$BUILD_DIR/Lift.app"
}

function install_app() {
    echo -e "${BLUE}🚀 构建 Release 版本...${NC}"
    xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release clean build

    BUILD_DIR=$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release -showBuildSettings | grep -m 1 "BUILT_PRODUCTS_DIR" | sed 's/.*= //')

    echo -e "${BLUE}🛑 退出正在运行的 Lift...${NC}"
    osascript -e 'quit app "Lift"' >/dev/null 2>&1 || true
    pkill -x Lift >/dev/null 2>&1 || true
    sleep 1

    echo -e "${BLUE}📦 安装到 /Applications/Lift.app...${NC}"
    rm -rf /Applications/Lift.app
    cp -R "$BUILD_DIR/Lift.app" /Applications/Lift.app
    xattr -dr com.apple.quarantine /Applications/Lift.app

    echo -e "${GREEN}✅ 安装完成: /Applications/Lift.app${NC}"
    open /Applications/Lift.app
}

function run_tests() {
    echo -e "${BLUE}🧪 运行测试...${NC}"
    xcodebuild -project "$PROJECT" -scheme "$SCHEME" -destination 'platform=macOS' test
    echo -e "${GREEN}✅ 测试完成!${NC}"
}

# 主逻辑
case "${1:-release}" in
    debug)
        build_debug
        ;;
    release)
        build_release
        ;;
    clean)
        clean_build
        ;;
    run)
        run_app
        ;;
    install)
        install_app
        ;;
    test)
        run_tests
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        echo -e "${YELLOW}未知命令: $1${NC}"
        show_help
        exit 1
        ;;
esac
