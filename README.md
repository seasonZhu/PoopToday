# 拉💩了冒

离线 Flutter Android 应用，第 01 票实现创建本地用户档案、主动选择通畅度和排便量、保存及展示今天记录。

## 工程配置

- Flutter 3.47.0，Dart 3.13.0。
- SQLite（sqflite），数据库版本 1，事务写入。后续结构变更需递增版本并增加升级迁移。
- 状态管理使用 Flutter 内置 StatefulWidget。
- Android 最低 API 24，应用标识 `com.pooptoday.poop_today`。
- 业务入口为 `Business`，支持注入数据库工厂和时间。
- 测试使用临时实际 SQLite 文件，宿主机通过系统 SQLite 运行。
- Android 禁用云备份并配置排除设备迁移数据，实际设备行为待验证。

## 本地验证

运行 `flutter analyze`、`flutter test` 和 `flutter build apk --debug`。

## iOS 自测

已按追加需求建立 iOS 工程，无签名 Debug 编译通过。使用 Xcode 打开 `ios/Runner.xcworkspace`，选择自己的开发团队和设备后运行。实际交互与真机重启由用户验收。
