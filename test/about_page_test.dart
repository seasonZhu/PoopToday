import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:poop_today/settings/about_page.dart';
import 'package:package_info_plus/package_info_plus.dart';

class RetryBundle extends CachingAssetBundle {
  bool fail = true;
  @override
  Future<ByteData> load(String key) async {
    if (fail) throw StateError('读取失败');
    return ByteData.sublistView(Uint8List.fromList(utf8.encode('# 本地正文')));
  }
}

void main() {
  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: '拉💩了冒',
      packageName: 'poop_today',
      version: '1.0.1',
      buildNumber: '2',
      buildSignature: '',
    );
  });

  testWidgets('关于页面显示安装包版本号和构建号', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: AboutPage()));
    await tester.pumpAndSettle();
    expect(find.text('版本号 1.0.1 · 构建号 2'), findsOneWidget);
  });

  test('过滤截图容器和图片，保留正文及链接', () {
    final result = documentWithoutImages('''# 标题
<p align="center">
<img src="image/a.PNG" />
</p>
![截图](image/b.png)
[许可证](LICENSE.md)
正文''');
    expect(result, contains('# 标题'));
    expect(result, contains('[许可证](LICENSE.md)'));
    expect(result, contains('正文'));
    expect(result, isNot(contains('<p')));
    expect(result, isNot(contains('image/')));
  });

  testWidgets('关于菜单进入本地正文并返回', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: AboutPage()));
    expect(find.text('我的掘金'), findsOneWidget);
    expect(find.text('我的Github'), findsOneWidget);
    await tester.tap(find.text('关于App'));
    await tester.pumpAndSettle();
    expect(find.text('为什么会有这个 App'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(find.text('关于'), findsOneWidget);
  });

  testWidgets('正文许可证打开本地文档', (tester) async {
    final bundle = RetryBundle()..fail = false;
    await tester.pumpWidget(
      MaterialApp(
        home: DefaultAssetBundle(
          bundle: bundle,
          child: const LocalDocumentPage(title: '关于App', asset: 'README.md'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    tester.widget<Markdown>(find.byType(Markdown)).onTapLink!(
      '许可证',
      'LICENSE.md',
      '',
    );
    await tester.pumpAndSettle();
    expect(find.text('许可证'), findsOneWidget);
    expect(find.byType(Markdown), findsOneWidget);
  });

  testWidgets('浏览器不可用时提示失败', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: AboutPage()));
    await tester.tap(find.text('我的Github'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
    expect(find.text('无法打开浏览器，请稍后重试'), findsOneWidget);
  });

  testWidgets('文档读取失败后可重试', (tester) async {
    final bundle = RetryBundle();
    await tester.pumpWidget(
      MaterialApp(
        home: DefaultAssetBundle(
          bundle: bundle,
          child: const LocalDocumentPage(title: '关于App', asset: 'README.md'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    bundle.fail = false;
    await tester.tap(find.text('文档加载失败，点击重试'));
    await tester.pumpAndSettle();
    expect(find.text('本地正文'), findsOneWidget);
  });
}
