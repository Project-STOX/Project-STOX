class Permission {
  final int permId;
  final String permName;

  Permission({
    required this.permId,
    required this.permName,
  });

  factory Permission.fromJson(Map<String, dynamic> json) {
    return Permission(
      permId: json['perm_id'],
      permName: json['perm_name'],
    );
  }
}
