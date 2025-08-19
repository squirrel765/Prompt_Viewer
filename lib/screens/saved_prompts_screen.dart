// lib/screens/saved_prompts_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prompt_viewer/providers/saved_prompts_provider.dart';

class SavedPromptsScreen extends ConsumerWidget {
  const SavedPromptsScreen({super.key});

  /// 프롬프트 수정을 위한 팝업(Dialog)을 띄우는 함수
  Future<void> _showEditPromptDialog(BuildContext context, WidgetRef ref, String currentPrompt, int index) async {
    final controller = TextEditingController(text: currentPrompt);

    return showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        // AlertDialog는 기본적으로 Material3 테마를 잘 따르므로 별도 수정이 필요 없습니다.
        return AlertDialog(
          title: const Text('프롬프트 수정'),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLines: null,
            // TextField는 main.dart의 inputDecorationTheme을 따릅니다.
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
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
                final newText = controller.text;
                ref.read(savedPromptsProvider.notifier).editPrompt(index, newText);
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // [핵심] 현재 테마 정보를 가져옵니다.
    final theme = Theme.of(context);
    final savedPrompts = ref.watch(savedPromptsProvider);

    if (savedPrompts.isEmpty) {
      return Center(
        child: Text(
          '저장된 프롬프트가 없습니다.',
          // [수정] 고정된 회색 대신 테마의 연한 글자색을 사용합니다.
          style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16.0),
      itemCount: savedPrompts.length,
      itemBuilder: (context, index) {
        final prompt = savedPrompts[index];
        // [수정] Card 위젯은 main.dart의 cardTheme을 자동으로 따르므로 별도 스타일 지정이 필요 없습니다.
        return Card(
          child: ListTile(
            contentPadding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
            title: SelectableText(prompt),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 수정 버튼
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  tooltip: '수정',
                  onPressed: () => _showEditPromptDialog(context, ref, prompt, index),
                ),
                // 복사 버튼
                IconButton(
                  icon: const Icon(Icons.copy_all_outlined, size: 20),
                  tooltip: '복사',
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: prompt));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('프롬프트가 복사되었습니다.')),
                    );
                  },
                ),
                // 삭제 버튼
                IconButton(
                  icon: Icon(
                    Icons.delete_outline,
                    size: 20,
                    // [수정] 고정된 redAccent 색상 대신 테마의 error 색상을 사용합니다.
                    color: theme.colorScheme.error,
                  ),
                  tooltip: '삭제',
                  onPressed: () {
                    ref.read(savedPromptsProvider.notifier).deletePrompt(index);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}