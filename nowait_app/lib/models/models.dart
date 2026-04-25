class UserModel {
  final String id;
  final String name;
  final String phone;
  final String city;
  final UserRole role;

  const UserModel({
    required this.id,
    required this.name,
    required this.phone,
    required this.city,
    required this.role,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      phone: json['phone'] ?? '',
      city: json['city'] ?? '',
      role: json['role'] == 'owner' ? UserRole.owner : UserRole.customer,
    );
  }
}

enum UserRole { customer, owner }

class ShopModel {
  final String id;
  final String name;
  final String category;
  final String address;
  final String city;
  final String state;
  final double rating;
  final bool isOpen;
  int queueCount;
  int currentToken;
  final int avgWaitMinutes;
  final String distance;
  final String ownerName;
  final List<String> images;
  final List<ServiceModel> services;
  final bool isPromoted;
  bool hasActiveSubscription;
  final SchemeModel? activeScheme;
  final bool queuePaused;
  final int? maxQueueSize;
  final String? openingHours;

  ShopModel({
    required this.id,
    required this.name,
    required this.category,
    required this.address,
    required this.city,
    this.state = '',
    required this.rating,
    required this.isOpen,
    required this.queueCount,
    required this.currentToken,
    required this.avgWaitMinutes,
    required this.distance,
    required this.ownerName,
    required this.images,
    required this.services,
    this.isPromoted = false,
    this.hasActiveSubscription = true,
    this.activeScheme,
    this.queuePaused = false,
    this.maxQueueSize,
    this.openingHours,
  });

  bool get canAcceptQueue => isOpen && hasActiveSubscription && !queuePaused;

  factory ShopModel.fromJson(Map<String, dynamic> json) {
    final allPromotions = json['active_promotions'] as List? ?? [];
    final schemeEntries = allPromotions
        .where((p) => (p as Map)['title'] != 'Featured Promotion')
        .toList();
    SchemeModel? activeScheme;
    if (schemeEntries.isNotEmpty) {
      try {
        activeScheme = SchemeModel.fromJson(schemeEntries.first as Map<String, dynamic>);
      } catch (_) {}
    }

    final servicesList = json['services'] as List?;
    final services = servicesList != null
        ? servicesList.map((s) => ServiceModel.fromJson(s as Map<String, dynamic>)).toList()
        : <ServiceModel>[];

    return ShopModel(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      category: json['category'] ?? '',
      address: json['address'] ?? '',
      city: json['city'] ?? '',
      state: json['state'] ?? '',
      rating: (json['rating'] as num?)?.toDouble() ?? 0.0,
      isOpen: json['is_open'] ?? false,
      queueCount: json['queue_count'] ?? 0,
      currentToken: json['now_serving_token'] ?? 0,
      avgWaitMinutes: json['avg_wait_minutes'] ?? 10,
      distance: '',
      ownerName: json['owner_name'] ?? '',
      images: List<String>.from(json['images'] ?? []),
      services: services,
      isPromoted: json['is_promoted'] as bool? ?? false,
      hasActiveSubscription: json['has_active_subscription'] ?? false,
      activeScheme: activeScheme,
      queuePaused: json['queue_paused'] as bool? ?? false,
      maxQueueSize: json['max_queue_size'] as int?,
      openingHours: json['opening_hours'] as String?,
    );
  }
}

class ServiceModel {
  final String id;
  final String name;
  final String description;
  final double price;

  const ServiceModel({
    required this.id,
    required this.name,
    required this.description,
    required this.price,
  });

  factory ServiceModel.fromJson(Map<String, dynamic> json) {
    return ServiceModel(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      description: json['description'] ?? '',
      price: (json['price'] as num).toDouble(),
    );
  }
}

class SchemeModel {
  final String id;
  final String title;
  final String description;
  final DateTime validUntil;

  const SchemeModel({
    required this.id,
    required this.title,
    required this.description,
    required this.validUntil,
  });

  bool get isActive => DateTime.now().isBefore(validUntil);

  String get validityText {
    final days = validUntil.difference(DateTime.now()).inDays;
    if (days <= 0) return 'Expired';
    if (days == 1) return 'Valid 1 more day';
    return 'Valid $days more days';
  }

  factory SchemeModel.fromJson(Map<String, dynamic> json) {
    return SchemeModel(
      id: json['id'] ?? '',
      title: json['title'] ?? '',
      description: json['description'] ?? '',
      validUntil: DateTime.parse(json['valid_until']),
    );
  }
}

class CategoryProduct {
  final String name;
  final String icon;
  final String priceFrom;

  const CategoryProduct({
    required this.name,
    required this.icon,
    required this.priceFrom,
  });
}

class QueueEntry {
  final String id;
  final String entryId;
  final String shopId;
  final String shopName;
  final String token;
  final int position;
  int peopleAhead;
  final int estimatedWaitMinutes;
  int nowServingToken;
  QueueStatus status;
  final bool queuePaused;

  QueueEntry({
    required this.id,
    required this.entryId,
    required this.shopId,
    required this.shopName,
    required this.token,
    required this.position,
    required this.peopleAhead,
    required this.estimatedWaitMinutes,
    required this.nowServingToken,
    required this.status,
    this.queuePaused = false,
  });

  factory QueueEntry.fromJson(Map<String, dynamic> json) {
    final displayStatus = json['display_status'] as String? ?? 'waiting';
    QueueStatus status;
    switch (displayStatus) {
      case 'yourTurn':
        status = QueueStatus.yourTurn;
      case 'almostThere':
        status = QueueStatus.almostThere;
      case 'skipped':
        status = QueueStatus.skipped;
      case 'completed':
        status = QueueStatus.completed;
      case 'cancelled':
        status = QueueStatus.cancelled;
      default:
        status = QueueStatus.waiting;
    }
    final entryId = json['id'] ?? '';
    return QueueEntry(
      id: entryId,
      entryId: entryId,
      shopId: json['shop_id'] ?? '',
      shopName: json['shop_name'] ?? '',
      token: '#${json['token_number']}',
      position: json['position'] ?? 0,
      peopleAhead: json['people_ahead'] ?? 0,
      estimatedWaitMinutes: json['estimated_wait_minutes'] ?? 0,
      nowServingToken: json['now_serving_token'] ?? 0,
      status: status,
    );
  }
}

enum QueueStatus { waiting, almostThere, yourTurn, skipped, completed, cancelled }

class NotificationModel {
  final String id;
  final NotificationType type;
  final String title;
  final String body;
  final String shopName;
  final DateTime time;
  final bool isRead;

  const NotificationModel({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.shopName,
    required this.time,
    this.isRead = false,
  });

  factory NotificationModel.fromJson(Map<String, dynamic> json) {
    final typeStr = json['type'] as String? ?? '';
    NotificationType type;
    switch (typeStr) {
      case 'your_turn':
        type = NotificationType.yourTurn;
      case 'almost_there':
        type = NotificationType.almostThere;
      case 'skipped':
        type = NotificationType.skipped;
      case 'promotion':
        type = NotificationType.promotion;
      case 'coming':
        type = NotificationType.coming;
      default:
        type = NotificationType.yourTurn;
    }
    return NotificationModel(
      id: json['id'] ?? '',
      type: type,
      title: json['title'] ?? '',
      body: json['body'] ?? '',
      shopName: json['shop_name'] ?? '',
      time: DateTime.parse(json['created_at']),
      isRead: json['is_read'] ?? false,
    );
  }
}

enum NotificationType { yourTurn, almostThere, skipped, promotion, coming }

// ── Staff ─────────────────────────────────────────────────────────────────────

class StaffMember {
  final String id;
  final String shopId;
  final String userId;
  final String displayName;
  final String phone;
  final bool isOwnerStaff;
  final bool isActive;
  final double? avgServiceMinutes;

  const StaffMember({
    required this.id,
    required this.shopId,
    required this.userId,
    required this.displayName,
    required this.phone,
    required this.isOwnerStaff,
    required this.isActive,
    this.avgServiceMinutes,
  });

  factory StaffMember.fromJson(Map<String, dynamic> json) {
    return StaffMember(
      id: json['id'] ?? '',
      shopId: json['shop_id'] ?? '',
      userId: json['user_id'] ?? '',
      displayName: json['display_name'] ?? json['name'] ?? '',
      phone: json['phone'] ?? '',
      isOwnerStaff: json['is_owner_staff'] as bool? ?? false,
      isActive: json['is_active'] as bool? ?? true,
      avgServiceMinutes: (json['avg_service_minutes'] as num?)?.toDouble(),
    );
  }
}

// ── Analytics ─────────────────────────────────────────────────────────────────

class AnalyticsSummary {
  final String period;
  final int totalJoined;
  final int totalServed;
  final int totalCancelled;
  final int totalSkipped;
  final double? avgServiceMinutes;
  final double cancelRatePct;
  final double skipRatePct;
  final int? peakHour;

  const AnalyticsSummary({
    required this.period,
    required this.totalJoined,
    required this.totalServed,
    required this.totalCancelled,
    required this.totalSkipped,
    this.avgServiceMinutes,
    required this.cancelRatePct,
    required this.skipRatePct,
    this.peakHour,
  });

  factory AnalyticsSummary.fromJson(Map<String, dynamic> json) {
    return AnalyticsSummary(
      period: json['period'] ?? 'today',
      totalJoined: json['total_joined'] ?? 0,
      totalServed: json['total_served'] ?? 0,
      totalCancelled: json['total_cancelled'] ?? 0,
      totalSkipped: json['total_skipped'] ?? 0,
      avgServiceMinutes: (json['avg_service_minutes'] as num?)?.toDouble(),
      cancelRatePct: (json['cancel_rate_pct'] as num?)?.toDouble() ?? 0,
      skipRatePct: (json['skip_rate_pct'] as num?)?.toDouble() ?? 0,
      peakHour: json['peak_hour'] as int?,
    );
  }

  String get peakHourText {
    if (peakHour == null) return 'N/A';
    final h = peakHour!;
    final period = h < 12 ? 'AM' : 'PM';
    final display = h == 0 ? 12 : (h > 12 ? h - 12 : h);
    return '$display $period';
  }
}

// ── History ───────────────────────────────────────────────────────────────────

class VisitHistory {
  final String id;
  final String shopId;
  final String shopName;
  final String shopCategory;
  final String shopCity;
  final int tokenNumber;
  final String status;
  final String? serviceName;
  final DateTime joinedAt;
  final DateTime? servedAt;
  final int? actualServiceMinutes;

  const VisitHistory({
    required this.id,
    required this.shopId,
    required this.shopName,
    required this.shopCategory,
    required this.shopCity,
    required this.tokenNumber,
    required this.status,
    this.serviceName,
    required this.joinedAt,
    this.servedAt,
    this.actualServiceMinutes,
  });

  factory VisitHistory.fromJson(Map<String, dynamic> json) {
    return VisitHistory(
      id: json['id'] ?? '',
      shopId: json['shop_id'] ?? '',
      shopName: json['shop_name'] ?? '',
      shopCategory: json['shop_category'] ?? '',
      shopCity: json['shop_city'] ?? '',
      tokenNumber: json['token_number'] ?? 0,
      status: json['status'] ?? '',
      serviceName: json['service_name'] as String?,
      joinedAt: DateTime.parse(json['joined_at']),
      servedAt: json['served_at'] != null ? DateTime.parse(json['served_at']) : null,
      actualServiceMinutes: json['actual_service_minutes'] as int?,
    );
  }

  String get statusLabel {
    switch (status) {
      case 'completed':
        return 'Served';
      case 'skipped':
        return 'Skipped';
      case 'cancelled':
        return 'Cancelled';
      default:
        return status;
    }
  }
}
