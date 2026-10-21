/// Login / me response shapes (WAITER_API_V2 "Auth").
library;

class WaiterUser {
  const WaiterUser({required this.user, required this.fullName, required this.waiter, this.image});
  final String user;
  final String fullName;
  final String waiter;
  final String? image;

  factory WaiterUser.fromJson(Map<String, dynamic> j) => WaiterUser(
        user: (j['user'] ?? '').toString(),
        fullName: (j['full_name'] ?? j['user'] ?? '').toString(),
        waiter: (j['waiter'] ?? '').toString(),
        image: j['image']?.toString(),
      );
  Map<String, dynamic> toJson() => {'user': user, 'full_name': fullName, 'waiter': waiter, 'image': image};

  String get initials {
    final parts = fullName.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.characters1.toUpperCase();
    return (parts.first.characters1 + parts.last.characters1).toUpperCase();
  }
}

extension on String {
  String get characters1 => isEmpty ? '' : String.fromCharCode(runes.first);
}

class PosProfile {
  const PosProfile({required this.name, this.restaurantName, this.branch, this.currency = 'QAR'});
  final String name;
  final String? restaurantName;
  final String? branch;
  final String currency;

  String get displayName => (restaurantName == null || restaurantName!.isEmpty) ? name : restaurantName!;

  factory PosProfile.fromJson(Map<String, dynamic> j) => PosProfile(
        name: (j['name'] ?? '').toString(),
        restaurantName: j['restaurant_name']?.toString(),
        branch: j['branch']?.toString(),
        currency: (j['currency'] ?? 'QAR').toString(),
      );
  Map<String, dynamic> toJson() => {'name': name, 'restaurant_name': restaurantName, 'branch': branch, 'currency': currency};
}

class SessionInfo {
  const SessionInfo({
    required this.user,
    required this.profiles,
    this.defaultProfile,
    this.site,
    this.serverVersion,
    this.expiresOn,
    this.serverTime,
  });
  final WaiterUser user;
  final List<PosProfile> profiles;
  final String? defaultProfile;
  final String? site;
  final String? serverVersion;
  final String? expiresOn;

  /// Server clock at response time ("YYYY-MM-DD HH:MM:SS"), used to correct phone clock skew.
  final String? serverTime;

  factory SessionInfo.fromJson(Map<String, dynamic> j) {
    final server = j['server'] is Map ? Map<String, dynamic>.from(j['server'] as Map) : const <String, dynamic>{};
    return SessionInfo(
      user: WaiterUser.fromJson(j['user'] is Map ? Map<String, dynamic>.from(j['user'] as Map) : const {}),
      profiles: [
        for (final p in (j['pos_profiles'] as List? ?? const []))
          if (p is Map) PosProfile.fromJson(Map<String, dynamic>.from(p)),
      ],
      defaultProfile: j['default_pos_profile']?.toString(),
      site: server['site']?.toString(),
      serverVersion: server['servepos_version']?.toString(),
      expiresOn: j['expires_on']?.toString(),
      serverTime: server['time']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'user': user.toJson(),
        'pos_profiles': [for (final p in profiles) p.toJson()],
        'default_pos_profile': defaultProfile,
        'server': {'site': site, 'servepos_version': serverVersion},
        'expires_on': expiresOn,
      };
}

class LoginResult {
  const LoginResult(this.token, this.session);
  final String token;
  final SessionInfo session;
}

class DeviceSession {
  const DeviceSession({required this.name, required this.deviceName, this.platform, this.lastSeen, this.current = false});
  final String name;
  final String deviceName;
  final String? platform;
  final String? lastSeen;
  final bool current;

  factory DeviceSession.fromJson(Map<String, dynamic> j) => DeviceSession(
        name: (j['name'] ?? '').toString(),
        deviceName: (j['device_name'] ?? j['name'] ?? '').toString(),
        platform: j['platform']?.toString(),
        lastSeen: j['last_seen']?.toString(),
        current: j['current'] == true || j['current'] == 1,
      );
}
