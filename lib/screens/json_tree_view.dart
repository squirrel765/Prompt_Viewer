import 'package:flutter/material.dart';

/// JSON 데이터를 트리 형태로 보여주고, 특정 값을 선택할 수 있게 하는 위젯입니다.
class JsonTreeView extends StatelessWidget {
  final Map<String, dynamic> jsonData;
  final String? selectedPath;
  final Function(String path) onSelect;

  const JsonTreeView({
    super.key,
    required this.jsonData,
    this.selectedPath,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    // 스크롤이 가능하도록 SingleChildScrollView로 감쌉니다.
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: _buildTree(jsonData, ''),
      ),
    );
  }

  List<Widget> _buildTree(dynamic data, String currentPath) {
    // 데이터가 Map일 경우
    if (data is Map<String, dynamic>) {
      return data.entries.map((entry) {
        final newPath = currentPath.isEmpty ? entry.key : '$currentPath.${entry.key}';
        final value = entry.value;

        // 값이 Map이나 List이면 펼칠 수 있는 ExpansionTile로 만듭니다.
        if (value is Map<String, dynamic> || value is List) {
          return ExpansionTile(
            // key: PageStorageKey(newPath), // 상태 유지를 위해 필요할 수 있음
            title: Text(entry.key, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white70)),
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: _buildTree(value, newPath),
                ),
              ),
            ],
          );
        } else {
          // 단순 값이면 일반 ListTile로 만듭니다.
          return _buildValueTile(entry.key, value.toString(), newPath);
        }
      }).toList();
    }
    // 데이터가 List일 경우
    else if (data is List) {
      return data.asMap().entries.map((entry) {
        final index = entry.key;
        final value = entry.value;
        // 리스트 경로는 'path.index' 형태로 표현합니다.
        final newPath = '$currentPath.$index';
        if (value is Map<String, dynamic> || value is List) {
          return ExpansionTile(
            // key: PageStorageKey(newPath),
            title: Text('[$index]', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white70)),
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: _buildTree(value, newPath),
                ),
              ),
            ],
          );
        } else {
          return _buildValueTile('[$index]', value.toString(), newPath);
        }
      }).toList();
    }
    return [];
  }

  Widget _buildValueTile(String key, String value, String path) {
    final isSelected = selectedPath == path;
    return ListTile(
      dense: true,
      title: Text(key, style: TextStyle(color: isSelected ? Colors.blue.shade900 : Colors.grey.shade400)),
      subtitle: Text(
        value,
        style: TextStyle(
          color: isSelected ? Colors.blue.shade900 : null,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      tileColor: isSelected ? Colors.blue.shade100 : null,
      onTap: () => onSelect(path),
    );
  }
}