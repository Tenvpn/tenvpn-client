import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'theme.dart';

const privacyAsset = 'docs/privacy.md';

enum PrivacyBlockKind { title, heading, bullet, paragraph }

typedef PrivacyBlock = ({PrivacyBlockKind kind, String text});

/// The subset of Markdown `docs/privacy.md` is written in: `#`/`##`
/// headings, `-` bullets, paragraphs, `**bold**` and `[text](url)`.
List<PrivacyBlock> parsePrivacyMarkdown(String source) {
  String clean(String text) => text
      .replaceAll('**', '')
      .replaceAllMapped(
        RegExp(r'\[([^\]]+)\]\(([^)]+)\)'),
        (m) => m[1] == m[2] ? m[1]! : '${m[1]} (${m[2]})',
      )
      .trim();

  final blocks = <PrivacyBlock>[];
  final paragraph = <String>[];
  void flush() {
    if (paragraph.isEmpty) return;
    blocks.add((
      kind: PrivacyBlockKind.paragraph,
      text: clean(paragraph.join(' ')),
    ));
    paragraph.clear();
  }

  for (final raw in source.split(RegExp(r'\r?\n'))) {
    final line = raw.trimRight();
    if (line.trim().isEmpty || line.startsWith('<!--') || line == '---') {
      flush();
    } else if (line.startsWith('## ')) {
      flush();
      blocks.add((
        kind: PrivacyBlockKind.heading,
        text: clean(line.substring(3)),
      ));
    } else if (line.startsWith('# ')) {
      flush();
      blocks.add((
        kind: PrivacyBlockKind.title,
        text: clean(line.substring(2)),
      ));
    } else if (line.startsWith('- ')) {
      flush();
      blocks.add((
        kind: PrivacyBlockKind.bullet,
        text: clean(line.substring(2)),
      ));
    } else {
      paragraph.add(line.trim());
    }
  }
  flush();
  return blocks;
}

class TenvpnPrivacyView extends StatelessWidget {
  final AssetBundle? bundle;

  const TenvpnPrivacyView({super.key, this.bundle});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return CommonScaffold(
      title: context.appLocalizations.tenvpnPrivacy,
      body: FutureBuilder<String>(
        future: (bundle ?? rootBundle).loadString(privacyAsset),
        builder: (context, snapshot) {
          final text = snapshot.data;
          if (text == null) {
            return const Center(child: CircularProgressIndicator());
          }
          return SelectionArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: [
                for (final block in parsePrivacyMarkdown(text))
                  _block(block, p),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _block(PrivacyBlock block, TenvpnPalette p) {
    return switch (block.kind) {
      PrivacyBlockKind.title => Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 8),
        child: Text(
          block.text,
          style: TextStyle(
            fontFamily: tenvpnDisplayFont,
            fontWeight: FontWeight.w800,
            fontSize: 22,
            color: p.text,
          ),
        ),
      ),
      PrivacyBlockKind.heading => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 6),
        child: Text(
          block.text,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 16,
            color: p.text,
          ),
        ),
      ),
      PrivacyBlockKind.bullet => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('•  ', style: TextStyle(color: p.muted, height: 1.45)),
            Expanded(
              child: Text(
                block.text,
                style: TextStyle(fontSize: 14.5, height: 1.45, color: p.text),
              ),
            ),
          ],
        ),
      ),
      PrivacyBlockKind.paragraph => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          block.text,
          style: TextStyle(fontSize: 14.5, height: 1.45, color: p.text),
        ),
      ),
    };
  }
}
