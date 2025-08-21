// lib/screens/memos_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:prompt_viewer/providers/memos_provider.dart';
import 'package:url_launcher/url_launcher.dart';

// [수정] ConsumerStatefulWidget으로 변경
class MemosScreen extends ConsumerStatefulWidget {
  const MemosScreen({super.key});

  @override
  ConsumerState<MemosScreen> createState() => _MemosScreenState();
}

class _MemosScreenState extends ConsumerState<MemosScreen> {
  // [추가] 화면이 처음 로드될 때 데이터를 불러오도록 initState 설정
  @override
  void initState() {
    super.initState();
    // 위젯 트리가 빌드된 후 단 한 번만 실행되도록 보장
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(memosProvider.notifier).loadMemos();
      }
    });
  }

  /// 메모를 추가하거나 수정하기 위한 다이얼로그를 표시하는 함수
  Future<void> _showMemoEditorDialog(BuildContext context, [Memo? memo]) async {
    final controller = TextEditingController(text: memo?.content ?? '');
    final isCreating = memo == null;

    return showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(isCreating ? '새 메모' : '메모 수정'),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLines: 10,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: '내용을 입력하세요... (마크다운 지원)',
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('취소'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            TextButton(
              child: const Text('저장'),
              onPressed: () {
                final newContent = controller.text;
                if (newContent.isNotEmpty) {
                  if (isCreating) {
                    ref.read(memosProvider.notifier).addMemo(newContent);
                  } else {
                    ref.read(memosProvider.notifier).editMemo(memo.id, newContent);
                  }
                }
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final memos = ref.watch(memosProvider);
    final theme = Theme.of(context);

    return Scaffold(
      body: memos.isEmpty
          ? Center(
        child: Text(
          '저장된 메모가 없습니다.',
          style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
        ),
      )
          : ListView.builder(
        padding: const EdgeInsets.all(16.0),
        itemCount: memos.length,
        itemBuilder: (context, index) {
          final memo = memos[index];
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  MarkdownBody(
                    data: memo.content,
                    selectable: true,
                    onTapLink: (text, href, title) {
                      if (href != null) {
                        launchUrl(Uri.parse(href));
                      }
                    },
                    styleSheet: MarkdownStyleSheet(
                      p: TextStyle(color: theme.colorScheme.onSurface),
                      h1: TextStyle(color: theme.colorScheme.onSurface),
                      h2: TextStyle(color: theme.colorScheme.onSurface),
                      h3: TextStyle(color: theme.colorScheme.onSurface),
                      listBullet: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                      code: TextStyle(backgroundColor: theme.colorScheme.surfaceContainerHighest, fontFamily: 'monospace'),
                    ),
                  ),
                  const Divider(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit_outlined, size: 20),
                        tooltip: '수정',
                        onPressed: () => _showMemoEditorDialog(context, memo),
                      ),
                      IconButton(
                        icon: Icon(Icons.delete_outline, size: 20, color: theme.colorScheme.error),
                        tooltip: '삭제',
                        onPressed: () {
                          ref.read(memosProvider.notifier).deleteMemo(memo.id);
                        },
                      ),
                    ],
                  )
                ],
              ),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showMemoEditorDialog(context),
        child: const Icon(Icons.add),
      ),
    );
  }
}