import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:package_info_plus/package_info_plus.dart';

Future<void> openExternalLink(BuildContext context, String href) async {
  try {
    final uri = Uri.parse(href);
    if (uri.scheme != 'https' ||
        !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw StateError('无法打开链接');
    }
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('无法打开浏览器，请稍后重试')));
    }
  }
}

class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  late final Future<PackageInfo> packageInfo = PackageInfo.fromPlatform();

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFFAFAF5),
    appBar: AppBar(
      title: const Text('关于'),
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => Navigator.pop(context),
      ),
    ),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        ListTile(
          title: const Text('关于App'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) =>
                  const LocalDocumentPage(title: '关于App', asset: 'README.md'),
            ),
          ),
        ),
        for (final entry in const {
          '我的掘金': 'https://juejin.cn/user/4353721778057997/posts',
          '我的Github': 'https://github.com/seasonZhu',
        }.entries)
          ListTile(
            title: Text(entry.key),
            trailing: const Icon(Icons.open_in_new),
            onTap: () => openExternalLink(context, entry.value),
          ),
        FutureBuilder<PackageInfo>(
          future: packageInfo,
          builder: (context, snapshot) => ListTile(
            title: const Text('版本信息'),
            subtitle: Text(
              snapshot.hasError
                  ? '版本信息读取失败'
                  : snapshot.hasData
                  ? '版本号 ${snapshot.data!.version} · 构建号 ${snapshot.data!.buildNumber}'
                  : '正在读取…',
            ),
          ),
        ),
      ],
    ),
  );
}

String documentWithoutImages(String source) => source
    .replaceAll(
      RegExp(r'<p\b[^>]*>\s*(?:<img\b[^>]*>\s*)+</p>', caseSensitive: false),
      '',
    )
    .replaceAll(RegExp(r'<img\b[^>]*>', caseSensitive: false), '')
    .replaceAll(RegExp(r'!\[[^\]]*\]\([^\n]*?\)|!\[[^\]]*\]\[[^\]]*\]'), '');

class LocalDocumentPage extends StatefulWidget {
  const LocalDocumentPage({
    super.key,
    required this.title,
    required this.asset,
  });
  final String title;
  final String asset;

  @override
  State<LocalDocumentPage> createState() => _LocalDocumentPageState();
}

class _LocalDocumentPageState extends State<LocalDocumentPage> {
  late Future<String> document;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    document = DefaultAssetBundle.of(context).loadString(widget.asset);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFFAFAF5),
    appBar: AppBar(
      title: Text(widget.title),
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => Navigator.pop(context),
      ),
    ),
    body: FutureBuilder<String>(
      future: document,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: TextButton(
              onPressed: () => setState(() {
                document = DefaultAssetBundle.of(context)
                    .loadString(widget.asset, cache: false);
              }),
              child: const Text('文档加载失败，点击重试'),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        return Markdown(
          data: documentWithoutImages(snapshot.data!),
          padding: const EdgeInsets.all(24),
          imageBuilder: (_, _, _) => const SizedBox.shrink(),
          onTapLink: (_, href, _) {
            if (href == null) return;
            if (href == 'LICENSE.md' || href == './LICENSE.md') {
              Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => const LocalDocumentPage(
                    title: '许可证',
                    asset: 'LICENSE.md',
                  ),
                ),
              );
            } else {
              openExternalLink(context, href);
            }
          },
        );
      },
    ),
  );
}
