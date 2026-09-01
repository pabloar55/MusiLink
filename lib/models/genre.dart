class Genre {
  final String name;
  final int count;
  final double percentage;

  const Genre({
    required this.name,
    required this.count,
    required this.percentage,
  });

  factory Genre.fromMap(Map<String, dynamic> map) => Genre(
    name: (map['name'] ?? '').toString(),
    count: (map['count'] as num?)?.toInt() ?? 0,
    percentage: (map['percentage'] as num?)?.toDouble() ?? 0.0,
  );

  /// Parses untrusted persisted data without throwing.
  static Genre? tryFromMap(Object? value) {
    if (value is! Map) return null;

    final name = value['name'];
    final rawCount = value['count'];
    final rawPercentage = value['percentage'];
    if (name is! String || name.trim().isEmpty) return null;
    if (rawCount != null && rawCount is! num) return null;
    if (rawPercentage != null && rawPercentage is! num) return null;

    final percentage = (rawPercentage as num?)?.toDouble() ?? 0.0;
    if (!percentage.isFinite) return null;
    return Genre(
      name: name.trim(),
      count: (rawCount as num?)?.toInt() ?? 0,
      percentage: percentage,
    );
  }

  Map<String, dynamic> toMap() => {
    'name': name,
    'count': count,
    'percentage': percentage,
  };
}
