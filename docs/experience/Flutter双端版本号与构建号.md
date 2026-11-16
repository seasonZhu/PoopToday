# Flutter 双端版本号与构建号经验

记录日期为 2026-11-16，适用于 PoopToday 当前构建配置。

## 现象与原因

关于页通过 `package_info_plus` 读取安装包信息。配置 `version: 1.0.1+2` 后，iOS 显示构建号 `2`，Android ARM64 分架构 APK 显示 `2002`。

Android 发布流程使用以下命令生成分架构安装包。

```sh
flutter build apk --release --split-per-abi --target-platform android-arm,android-arm64
```

当前 Flutter Gradle 插件为分架构 APK 计算独立版本码。

```text
APK versionCode = ABI 编号 × 1000 + 原始构建号
```

| ABI 编号 | ABI 标识 | 含义 | 原始构建号为 2 时的版本码 |
| --- | --- | --- | --- |
| 1 | armeabi-v7a | 32 位 ARM，主要兼容较老设备 | 1002 |
| 2 | arm64-v8a | 64 位 ARM，主流 Android 手机 | 2002 |
| 3 | x86 | 32 位 Intel，当前 Flutter 已移除支持，编号保留 | — |
| 4 | x86_64 | 64 位 Intel/AMD，常用于模拟器 | 4002 |

此表来自本机 Flutter 工具源码的 `FlutterPluginConstants.ABI_VERSION`，计算规则来自 `FlutterPlugin.kt`。升级 Flutter 后应重新核对。当前项目发布 ARM32 和 ARM64 两种 APK。该偏移规则针对分架构 APK，不能直接套用到所有 Android 产物。

`pubspec.yaml` 改为 `1.0.1+1` 后，重新生成的 ARM64 分架构 APK 通常对应 `2001`。设备继续显示 `2002` 时，应核对已安装包、实际构建参数和构建来源。

## 当前解决方式

关于页统一显示原始构建号，例如 `版本号 1.0.1 · 构建号 2`。APK 内部保留实际 `versionCode`，供系统判断升级。

实现链路如下。

1. `android/app/build.gradle.kts` 保留 `versionCode = flutter.versionCode`，另用 `resValue` 将 `flutter.versionCode` 写入字符串资源 `display_build_number`。
2. `MainActivity.kt` 通过 `poop_today/build_info` MethodChannel 的 `buildNumber` 方法返回该资源。
3. `lib/settings/about_page.dart` 在 Android 读取此原始构建号，iOS 继续使用 `PackageInfo.buildNumber`。版本号继续读取安装包信息。
4. Android 原生通道不可用时，页面回退显示安装包实际构建号，因此故障或旧原生调试环境下仍可能显示 `2002`。

资源取值发生在 Flutter 为分架构 APK 增加偏移之前，适用于本地与 CI 构建，也能跟随 `--build-number` 参数。页面无需对实际版本码取余反推原始值。

新增或修改 Android 原生资源、通道后，需要重新构建并安装，热重载无法更新安装包内的原生实现。

## 版本管理与覆盖安装

```yaml
version: 1.0.1+2
```

`1.0.1` 是版本号，`2` 是原始构建号。Flutter 默认将它们映射到 Android 的 `versionName`、`versionCode` 和 iOS 的 `CFBundleShortVersionString`、`CFBundleVersion`。构建命令的 `--build-name`、`--build-number` 可覆盖配置值。

本项目双端统一采用持续递增的原始构建号，版本号升级后继续累加。

```text
1.0.0+1 → 1.0.1+2 → 1.0.1+3 → 1.0.2+4
```

准备分发、安装测试或发布的新构建递增即可，日常调试编译无需每次手动增加。

Android 在包名与签名一致的前提下，根据实际 `versionCode` 判断降级。较低版本码通常无法正常覆盖安装，相同版本码通常可手动覆盖，但 Google Play 要求新上传产物使用未用过的版本码。版本名称提高也无法绕过实际版本码降低的限制。

分架构包与通用包混装时，要比较最终实际版本码。例如已安装 ARM64 `2002`，通用包即使原始构建号为 `3`，也可能因实际版本码降低而无法覆盖。切换打包策略前需检查产物版本码。原始构建号达到 1000 附近时，也需重新评估当前偏移方案的架构区间与冲突风险。

Android 的规则与 iOS 分发规则应分别核对。本项目持续递增的约定便于双端统一维护。覆盖安装问题优先检查包名、签名、实际版本码及分发方式，涉及本地记录时先导出备份。

## 排查与验收

- 核对 `pubspec.yaml` 和构建命令，确认是否传入版本覆盖参数。
- 核对 `.github/workflows/android-release.yml` 中的分架构参数。
- Android 可用 `apkanalyzer manifest version-code <APK路径>` 检查产物实际版本码，用 `adb shell dumpsys package com.pooptoday.poop_today` 查看设备已安装版本。
- iOS 检查构建产物的 `CFBundleShortVersionString`、`CFBundleVersion`。`ios/Flutter/Generated.xcconfig` 可作为生成配置线索，以实际产物为准。
- 验证 Android 关于页显示 `2`，ARM64 APK 内部仍为 `2002`，iOS 关于页显示 `2`。
- 本次实现的 7 项关于页测试、静态分析和差异检查已通过。Android 原生构建、设备显示和覆盖安装待设备验收。APK 由用户构建并测试。

## 参考

- [Android 版本管理](https://developer.android.com/studio/publish/versioning)
- [Apple CFBundleVersion](https://developer.apple.com/documentation/bundleresources/information-property-list/cfbundleversion)
