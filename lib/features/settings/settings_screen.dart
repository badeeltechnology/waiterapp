import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../../core/api/api_exception.dart';
import '../../core/api/waiter_api.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/models/order.dart' show parseServerTime;
import '../../core/models/session.dart';
import '../../core/platform.dart';
import '../../core/push.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import '../auth/session_controller.dart';
import '../order/menu_repository.dart';
import '../order/outbox.dart';
import 'app_settings.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  List<DeviceSession>? _devices;
  String? _devicesError;
  bool? _bioAvailable;
  String _version = '';

  @override
  void initState() {
    super.initState();
    _loadDevices();
    context.read<BiometricGate>().isAvailable().then((v) {
      if (mounted) setState(() => _bioAvailable = v);
    });
    PackageInfo.fromPlatform().then((p) {
      if (mounted) setState(() => _version = '${p.version} (${p.buildNumber})');
    }).catchError((Object _) {});
  }

  Future<void> _loadDevices() async {
    try {
      final d = await context.read<WaiterApi>().sessions();
      if (mounted) setState(() => (_devices = d, _devicesError = null));
    } on ApiException catch (e) {
      if (mounted) setState(() => _devicesError = e.message);
    }
  }

  Future<void> _revoke(DeviceSession d) async {
    final ok = await confirmDialog(context, title: context.t('acc_revoke_q', {'d': d.deviceName}), confirm: context.t('acc_revoke'), destructive: true);
    if (!ok || !mounted) return;
    try {
      await context.read<WaiterApi>().revokeSession(d.name);
      await _loadDevices();
    } on ApiException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    }
  }

  Future<void> _signOut() async {
    final outbox = context.read<Outbox>();
    final session = context.read<SessionController>();
    final ok = await confirmDialog(
      context,
      title: context.t('acc_sign_out'),
      body: outbox.count > 0 ? context.t('acc_sign_out_q') : context.t('acc_sign_out_q_clean'),
      confirm: context.t('acc_revoke'),
      destructive: true,
    );
    if (ok) await session.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();
    final settings = context.watch<AppSettings>();
    final menu = context.watch<MenuRepository>();
    final user = session.user;
    final profile = session.profile;
    final multiProfile = (session.session?.profiles.length ?? 0) > 1;

    Widget tile({required IconData icon, required String title, String? subtitle, Widget? trailing, VoidCallback? onTap, Key? key}) => ListTile(
          key: key,
          minTileHeight: 60,
          leading: Icon(icon, color: Nami.teal),
          title: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
          subtitle: subtitle == null ? null : Text(subtitle, style: const TextStyle(color: Nami.muted, fontSize: 14)),
          trailing: trailing,
          onTap: onTap,
        );

    return Scaffold(
      appBar: AppBar(title: Text(context.t('nav_account'))),
      body: ListView(padding: const EdgeInsets.only(bottom: 32), children: [
        Container(
          color: Nami.rail,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
          child: Row(children: [
            WaiterDisc(name: user?.fullName ?? '?', size: 56),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(user?.fullName ?? '', style: Nami.num(28, color: Nami.white)),
                Text(user?.user ?? '', style: const TextStyle(color: Nami.onDeep, fontSize: 14)),
              ]),
            ),
          ]),
        ),
        SectionCap(context.t('acc_outlet')),
        _Group(children: [
          tile(
            icon: Icons.storefront_outlined,
            title: profile?.displayName ?? '',
            subtitle: [profile?.branch, profile?.currency].whereType<String>().join(' · '),
            trailing: multiProfile ? TextButton(onPressed: session.pickAnotherProfile, child: Text(context.t('acc_change_outlet'))) : null,
          ),
          tile(
            icon: Icons.restaurant_menu,
            title: context.t('acc_refresh_menu'),
            subtitle: menu.updatedAt == null ? null : context.t('acc_menu_version', {'t': hhmm(menu.updatedAt!)}),
            trailing: menu.loading ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)) : const Icon(Icons.refresh),
            onTap: menu.loading ? null : () => menu.refresh(force: true),
          ),
          tile(icon: Icons.dns_outlined, title: context.t('acc_server'), subtitle: session.serverUrl),
        ]),
        SectionCap(context.t('acc_notifications')),
        _Group(children: [
          Builder(builder: (context) {
            final on = context.read<PushService>().available;
            return tile(
              key: const Key('acc_push'),
              icon: on ? Icons.notifications_active_outlined : Icons.notifications_off_outlined,
              title: context.t(on ? 'acc_push_on' : 'acc_push_off'),
              subtitle: context.t(on ? 'acc_push_on_sub' : 'acc_push_off_sub'),
            );
          }),
        ]),
        SectionCap(context.t('acc_security')),
        _Group(children: [
          SwitchListTile(
            key: const Key('acc_biometric'),
            minTileHeight: 60,
            secondary: const Icon(Icons.fingerprint, color: Nami.teal),
            title: Text(context.t('acc_biometric'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
            subtitle: _bioAvailable == false ? Text(context.t('acc_biometric_unavailable'), style: const TextStyle(color: Nami.muted)) : null,
            value: settings.biometricEnabled,
            onChanged: _bioAvailable == false ? null : (v) => session.setBiometric(v, context.t('lock_reason')),
          ),
          tile(
            icon: Icons.timer_outlined,
            title: context.t('acc_idle'),
            trailing: DropdownButton<int>(
              value: settings.idleMinutes,
              underline: const SizedBox.shrink(),
              style: const TextStyle(fontSize: 14, color: Nami.ink, fontFamily: Nami.bodyFont),
              selectedItemBuilder: (_) => [for (final m in AppSettings.idleChoices) Center(child: Text('$m min'))],
              items: [for (final m in AppSettings.idleChoices) DropdownMenuItem(value: m, child: Text(context.t('acc_idle_n', {'n': m})))],
              onChanged: settings.biometricEnabled ? (v) => v == null ? null : settings.setIdleMinutes(v) : null,
            ),
          ),
          SwitchListTile(
            minTileHeight: 60,
            secondary: const Icon(Icons.screenshot_monitor, color: Nami.teal),
            title: Text(context.t('acc_screenshots'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
            value: settings.blockScreenshots,
            onChanged: settings.setBlockScreenshots,
          ),
        ]),
        SectionCap(context.t('acc_language')),
        _Group(children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: SegmentedButton<String>(
              style: SegmentedButton.styleFrom(minimumSize: const Size(48, 48), selectedBackgroundColor: Nami.amber, selectedForegroundColor: Nami.ink),
              showSelectedIcon: false,
              segments: const [ButtonSegment(value: 'en', label: Text('English')), ButtonSegment(value: 'ar', label: Text('العربية'))],
              selected: {settings.language},
              onSelectionChanged: (s) => settings.setLanguage(s.first),
            ),
          ),
        ]),
        SectionCap(context.t('acc_devices'), trailing: IconButton(onPressed: _loadDevices, icon: const Icon(Icons.refresh, color: Nami.muted))),
        _Group(children: [
          if (_devices == null && _devicesError == null) const Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator()),
          if (_devicesError != null) Padding(padding: const EdgeInsets.all(16), child: Text(_devicesError!, style: const TextStyle(color: Nami.muted))),
          for (final d in _devices ?? const <DeviceSession>[])
            tile(
              icon: d.current ? Icons.smartphone : Icons.phone_android_outlined,
              title: d.current ? '${d.deviceName} · ${context.t('acc_this_device')}' : d.deviceName,
              subtitle: [
                d.platform,
                if (d.lastSeen != null) context.t('acc_last_seen', {'t': _when(d.lastSeen!)}),
              ].whereType<String>().join(' · '),
              trailing: d.current ? null : TextButton(onPressed: () => _revoke(d), style: TextButton.styleFrom(foregroundColor: Nami.red), child: Text(context.t('acc_revoke'))),
            ),
        ]),
        const SizedBox(height: 24),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: OutlinedButton.icon(
            key: const Key('acc_sign_out'),
            style: OutlinedButton.styleFrom(foregroundColor: Nami.red, side: const BorderSide(color: Nami.red, width: 1.5)),
            onPressed: session.busy ? null : _signOut,
            icon: const Icon(Icons.logout),
            label: Text(context.t('acc_sign_out')),
          ),
        ),
        const SizedBox(height: 16),
        Center(child: Text(context.t('acc_version', {'v': _version}), style: const TextStyle(color: Nami.muted, fontSize: 13))),
      ]),
    );
  }

  String _when(String s) {
    final t = parseServerTime(s);
    if (t == null) return s;
    final now = ServerClock.now();
    if (t.year == now.year && t.month == now.month && t.day == now.day) return hhmm(t);
    return '${t.day}/${t.month} ${hhmm(t)}';
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(Nami.radius), boxShadow: Nami.cardShadow),
        child: Material(
          color: Nami.white,
          borderRadius: BorderRadius.circular(Nami.radius),
          clipBehavior: Clip.antiAlias,
          child: Column(children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const Divider(indent: 56),
              children[i],
            ],
          ]),
        ),
      );
}
