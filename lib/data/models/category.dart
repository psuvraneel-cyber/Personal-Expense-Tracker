import 'package:flutter/material.dart';

class Category {
  final String id;
  final String name;
  final IconData icon;
  final Color color;
  final bool isCustom;
  final String type; // 'expense', 'income', 'both'

  Category({
    required this.id,
    required this.name,
    required this.icon,
    required this.color,
    this.isCustom = false,
    this.type = 'expense',
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'iconCodePoint': icon.codePoint,
      'iconFontFamily': icon.fontFamily,
      'colorValue': color.toARGB32(),
      'isCustom': isCustom ? 1 : 0,
      'type': type,
    };
  }

  factory Category.fromMap(Map<String, dynamic> map) {
    return Category(
      id: map['id'] as String,
      name: map['name'] as String,
      icon: CategoryIconHelper.fromCodePoint(map['iconCodePoint'] as int?),
      color: Color(map['colorValue'] as int),
      isCustom: (map['isCustom'] as int? ?? 0) == 1,
      type: map['type'] as String? ?? 'expense',
    );
  }

  Category copyWith({
    String? id,
    String? name,
    IconData? icon,
    Color? color,
    bool? isCustom,
    String? type,
  }) {
    return Category(
      id: id ?? this.id,
      name: name ?? this.name,
      icon: icon ?? this.icon,
      color: color ?? this.color,
      isCustom: isCustom ?? this.isCustom,
      type: type ?? this.type,
    );
  }
}

/// Helper to map stored icon code points to compile-time constant [IconData] references.
///
/// This avoids dynamic [IconData] constructor invocations which fail AOT release builds
/// during icon tree-shaking (`flutter build appbundle --release`).
class CategoryIconHelper {
  CategoryIconHelper._();

  static const IconData defaultIcon = Icons.category;

  static const List<IconData> _supportedIcons = [
    // Default categories
    Icons.restaurant,
    Icons.directions_car,
    Icons.receipt_long,
    Icons.shopping_bag,
    Icons.local_hospital,
    Icons.movie,
    Icons.school,
    Icons.local_grocery_store,
    Icons.home,
    Icons.phone_android,
    Icons.account_balance,
    Icons.more_horiz,
    Icons.account_balance_wallet,
    Icons.work,
    Icons.trending_up,
    Icons.card_giftcard,
    Icons.replay,
    Icons.attach_money,

    // Settings category icon picker
    Icons.category,
    Icons.star,
    Icons.favorite,
    Icons.sports_esports,
    Icons.pets,
    Icons.flight,
    Icons.local_cafe,
    Icons.fitness_center,
    Icons.music_note,
    Icons.book,
    Icons.construction,
    Icons.devices,

    // Common extras
    Icons.fastfood,
    Icons.local_dining,
    Icons.coffee,
    Icons.local_bar,
    Icons.commute,
    Icons.directions_bus,
    Icons.directions_bike,
    Icons.local_gas_station,
    Icons.flight_takeoff,
    Icons.hotel,
    Icons.local_mall,
    Icons.store,
    Icons.shopping_cart,
    Icons.medical_services,
    Icons.medication,
    Icons.theater_comedy,
    Icons.games,
    Icons.menu_book,
    Icons.computer,
    Icons.laptop,
    Icons.smartphone,
    Icons.phone,
    Icons.wifi,
    Icons.electrical_services,
    Icons.water_drop,
    Icons.power,
    Icons.build,
    Icons.credit_card,
    Icons.savings,
    Icons.payments,
    Icons.paid,
    Icons.monetization_on,
    Icons.currency_exchange,
    Icons.help_outline,
    Icons.circle,
    Icons.lightbulb,
    Icons.security,
    Icons.vpn_key,
    Icons.check,
    Icons.close,
    Icons.warning,
    Icons.error,
    Icons.info,
    Icons.notifications,
    Icons.sms,
    Icons.receipt,
    Icons.description,
  ];

  static final Map<int, IconData> _codePointMap = {
    for (final icon in _supportedIcons) icon.codePoint: icon,
  };

  /// Resolves an [IconData] constant by codePoint, falling back to [defaultIcon]
  /// if not present in the known icon set.
  static IconData fromCodePoint(int? codePoint) {
    if (codePoint == null) return defaultIcon;
    return _codePointMap[codePoint] ?? defaultIcon;
  }
}
