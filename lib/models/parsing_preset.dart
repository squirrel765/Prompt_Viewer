enum PresetType { a1111, comfyui }

class ParsingPreset {
  final String id;
  String name;
  PresetType type;
  ParsingRules? rules; // ComfyUI 타입일 때만 사용

  ParsingPreset({
    required this.id,
    required this.name,
    required this.type,
    this.rules,
  });

  // JSON 직렬화/역직렬화를 위한 코드 (설정 저장용)
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'type': type.name,
    'rules': rules?.toJson(),
  };

  factory ParsingPreset.fromJson(Map<String, dynamic> json) => ParsingPreset(
    id: json['id'],
    name: json['name'],
    type: PresetType.values.byName(json['type']),
    rules: json['rules'] != null ? ParsingRules.fromJson(json['rules']) : null,
  );
}

class ParsingRules {
  List<Rule> positive;
  List<Rule> negative;
  List<Rule> others;

  ParsingRules({required this.positive, required this.negative, required this.others});

  Map<String, dynamic> toJson() => {
    'positive': positive.map((r) => r.toJson()).toList(),
    'negative': negative.map((r) => r.toJson()).toList(),
    'others': others.map((r) => r.toJson()).toList(),
  };

  factory ParsingRules.fromJson(Map<String, dynamic> json) => ParsingRules(
    positive: (json['positive'] as List).map((r) => Rule.fromJson(r)).toList(),
    negative: (json['negative'] as List).map((r) => Rule.fromJson(r)).toList(),
    others: (json['others'] as List).map((r) => Rule.fromJson(r)).toList(),
  );
}

class Rule {
  final String nodeId;
  final String path;
  final String? prefix;

  Rule({required this.nodeId, required this.path, this.prefix});

  Map<String, dynamic> toJson() => {'nodeId': nodeId, 'path': path, 'prefix': prefix};
  factory Rule.fromJson(Map<String, dynamic> json) => Rule(
    nodeId: json['nodeId'],
    path: json['path'],
    prefix: json['prefix'],
  );
}