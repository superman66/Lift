# Lift: 轻松一拖，主体即现。

厌倦了图片去底后，四周总留有一大片恼人的透明区域？Lift 专为 macOS 设计，是一款极致高效的本地图片处理工具。

借助 macOS 14 (Sonoma) 强大的 Vision 框架，Lift 能够精确识别并移除图片背景，同时智能裁切掉所有多余的透明边缘。无论是商品图、证件照还是社交分享，只需简单拖拽，Lift 便能瞬间为你呈现一个干净、紧凑、只有主体的 PNG 图片。

## Lift 的核心优势：

- 极致简洁： 无需学习，拖拽即用。
- 毫秒处理： 离线运行，无上传等待，处理速度快如闪电。
- 隐私安全： 所有处理均在您的 Mac 本地完成，图片从不离开您的设备。
- 精准高效： 告别手动裁剪，智能算法一步到位。

让 Lift 成为您日常图片处理的新搭档，告别繁琐，专注于内容本身。

## 构建说明

Lift 支持在不打开 Xcode 的情况下进行构建，提供了多种便捷的构建方式。

### 方式 1: 使用 Makefile (推荐)

```bash
# 查看所有可用命令
make help

# 构建 Release 版本
make build-release

# 构建 Debug 版本
make build

# 清理并重新构建
make rebuild

# 运行应用
make run

# 在 Finder 中打开构建目录
make open

# 运行测试
make test
```

### 方式 2: 使用 Shell 脚本

```bash
# 构建 Release 版本 (默认)
./build.sh
./build.sh release

# 构建 Debug 版本
./build.sh debug

# 构建并运行
./build.sh run

# 清理构建
./build.sh clean

# 运行测试
./build.sh test

# 查看帮助
./build.sh help
```

### 方式 3: 手动使用 xcodebuild

```bash
# 构建 Release 版本
xcodebuild -project Lift.xcodeproj -scheme Lift -configuration Release build

# 构建 Debug 版本
xcodebuild -project Lift.xcodeproj -scheme Lift -configuration Debug build

# 清理构建产物
xcodebuild -project Lift.xcodeproj -scheme Lift clean
```

### 快捷方式 (可选)

在 `~/.zshrc` 中添加别名，可以在任何目录快速构建:

```bash
alias lift-build='cd /Users/superman/Developer/Lift && make build-release'
alias lift-run='cd /Users/superman/Developer/Lift && make run'
```

然后在任何地方只需输入:

```bash
lift-build  # 构建
lift-run    # 运行
```

## 系统要求

- macOS 14 (Sonoma) 或更高版本
- Xcode 15+ (仅用于构建，无需打开)
- Apple Silicon 或 Intel 处理器
