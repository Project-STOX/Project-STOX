class Permission {
  final int permId;
  final String permName;

  Permission({
    required this.permId,
    required this.permName,
  });

  factory Permission.fromJson(Map<String, dynamic> json) {
    int parseInt(dynamic value) {
      if (value is num) {
        return value.toInt();
      }
      return int.tryParse(value?.toString() ?? '') ?? 0;
    }

    return Permission(
      permId: parseInt(json['perm_id'] ?? json['id']),
      permName: (json['perm_name'] ?? json['action_name'] ?? '').toString(),
    );
  }
}
