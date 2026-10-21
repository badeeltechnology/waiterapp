import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/api/api_exception.dart';
import '../../core/i18n.dart';
import '../../core/models/session.dart';
import '../../core/server_url.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import '../settings/app_settings.dart';
import 'session_controller.dart';

/// Deep-teal header with the brand, cream body. Shared by all auth screens.
class AuthScaffold extends StatelessWidget {
  const AuthScaffold({super.key, required this.title, this.subtitle, required this.children, this.footer});
  final String title;
  final String? subtitle;
  final List<Widget> children;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Nami.cream,
      body: SafeArea(
        top: false,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Container(
                color: Nami.deep,
                padding: EdgeInsets.fromLTRB(24, MediaQuery.paddingOf(context).top + 28, 24, 28),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Container(
                      width: 40,
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: Nami.amber, borderRadius: BorderRadius.circular(Nami.radius)),
                      child: Text('S', style: Nami.num(26, color: Nami.deep)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Row(children: [
                        Flexible(
                          child: Text('ServePOS', maxLines: 1, overflow: TextOverflow.fade, softWrap: false, style: Nami.num(26, color: Nami.white)),
                        ),
                        const SizedBox(width: 8),
                        Text('WAITER', style: Nami.cap.copyWith(color: Nami.onDeepMuted)),
                      ]),
                    ),
                    const _LanguageToggle(),
                  ]),
                  const SizedBox(height: 28),
                  Text(title, style: Nami.num(34, color: Nami.white)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 6),
                    Text(subtitle!, style: const TextStyle(color: Nami.onDeep, fontSize: 15)),
                  ],
                ]),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
              sliver: SliverList.list(children: children),
            ),
            if (footer != null)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Align(alignment: Alignment.bottomCenter, child: Padding(padding: const EdgeInsets.all(16), child: footer)),
              ),
          ],
        ),
      ),
    );
  }
}

class _LanguageToggle extends StatelessWidget {
  const _LanguageToggle();
  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppSettings>();
    return TextButton(
      onPressed: () => s.setLanguage(s.language == 'ar' ? 'en' : 'ar'),
      style: TextButton.styleFrom(foregroundColor: Nami.white),
      child: Text(s.language == 'ar' ? 'English' : 'العربية'),
    );
  }
}

class ErrorBox extends StatelessWidget {
  const ErrorBox(this.text, {super.key, this.color = Nami.red});
  final String text;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          border: BorderDirectional(start: BorderSide(color: color, width: 4)),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(text, style: TextStyle(color: color == Nami.red ? const Color(0xFF8E2A1F) : Nami.ink, fontSize: 15, fontWeight: FontWeight.w500)),
      );
}

// ------------------------------------------------------------------ server URL

class ServerUrlScreen extends StatefulWidget {
  const ServerUrlScreen({super.key});
  @override
  State<ServerUrlScreen> createState() => _ServerUrlScreenState();
}

class _ServerUrlScreenState extends State<ServerUrlScreen> {
  final _ctrl = TextEditingController();
  String? _error;
  bool _busy = false;

  /// Shown as a fixed prefix, so waiters only type the address. Becomes
  /// http:// only when someone types or pastes an http:// address (local test
  /// servers), and goes back to https:// when the field is cleared.
  String _scheme = 'https://';

  static final _schemeRe = RegExp(r'^\s*(https?)://', caseSensitive: false);

  /// Moves a typed or pasted scheme out of the text and into the prefix.
  void _setAddress(String raw) {
    if (raw.isEmpty) {
      if (_scheme != 'https://') setState(() => _scheme = 'https://');
      return;
    }
    final m = _schemeRe.firstMatch(raw);
    if (m == null) return;
    final rest = raw.substring(m.end);
    setState(() => _scheme = '${m.group(1)!.toLowerCase()}://');
    _ctrl.value = TextEditingValue(text: rest, selection: TextSelection.collapsed(offset: rest.length));
  }

  String get _fullUrl => '$_scheme${_ctrl.text.trim()}';

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final d = await Clipboard.getData(Clipboard.kTextPlain);
    if (d?.text == null) return;
    final text = d!.text!.trim();
    _ctrl.text = text;
    if (_schemeRe.hasMatch(text)) {
      _setAddress(text);
    } else {
      setState(() => _scheme = 'https://');
    }
  }

  Future<void> _continue({bool insecureConfirmed = false}) async {
    final session = context.read<SessionController>();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final n = await session.checkServer(_fullUrl, insecureConfirmed: insecureConfirmed);
      await session.setServer(n);
    } on ServerUrlException catch (e) {
      if (!mounted) return;
      if (e.message == 'http_local') {
        setState(() => _busy = false);
        final ok = await confirmDialog(
          context,
          title: context.t('server_http_local_title'),
          body: context.t('server_http_local_body'),
          confirm: context.t('server_http_local_ok'),
          destructive: true,
        );
        if (ok) return _continue(insecureConfirmed: true);
        return;
      }
      setState(() => _error = switch (e.message) {
            'http_public' || 'http_release' => context.t('server_http_public'),
            'unreachable' => context.t('server_unreachable'),
            _ => context.t('server_invalid'),
          });
    } on ApiException {
      if (mounted) setState(() => _error = context.t('server_unreachable'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: context.t('server_title'),
      subtitle: context.t('server_hint'),
      children: [
        if (_error != null) ErrorBox(_error!),
        TextField(
          key: const Key('server_field'),
          controller: _ctrl,
          keyboardType: TextInputType.url,
          autocorrect: false,
          enableSuggestions: false,
          textInputAction: TextInputAction.go,
          onChanged: _setAddress,
          onSubmitted: (_) => _busy ? null : _continue(),
          style: const TextStyle(fontSize: 17),
          decoration: InputDecoration(
            labelText: context.t('server_label'),
            hintText: 'demo.myapp.qa',
            // Always visible (prefixText would hide until the field is focused).
            prefixIcon: Padding(
              padding: const EdgeInsetsDirectional.only(start: 12, end: 2),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.link),
                const SizedBox(width: 8),
                Text(_scheme,
                    key: const Key('server_scheme'),
                    textDirection: TextDirection.ltr,
                    style: TextStyle(fontSize: 17, color: Theme.of(context).hintColor)),
              ]),
            ),
            suffixIcon: TextButton(onPressed: _paste, child: Text(context.t('server_paste'))),
          ),
        ),
        const SizedBox(height: 20),
        FilledButton(
          key: const Key('server_continue'),
          onPressed: _busy ? null : () => _continue(),
          child: _busy
              ? Row(mainAxisSize: MainAxisSize.min, children: [
                  const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5)),
                  const SizedBox(width: 12),
                  Text(context.t('server_checking')),
                ])
              : Text(context.t('server_continue')),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------------ login

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  late final TextEditingController _user;
  final _pwd = TextEditingController();
  final _pwdFocus = FocusNode();
  bool _obscure = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _user = TextEditingController(text: context.read<AppSettings>().lastUsername ?? '');
  }

  @override
  void dispose() {
    _user.dispose();
    _pwd.dispose();
    _pwdFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final session = context.read<SessionController>();
    if (_user.text.trim().isEmpty || _pwd.text.isEmpty) return;
    setState(() => _error = null);
    try {
      await session.login(_user.text, _pwd.text);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = context.t('error_generic'));
    } finally {
      _pwd.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();
    final host = Uri.tryParse(session.serverUrl ?? '')?.host ?? '';
    final message = session.loginMessage;
    return AuthScaffold(
      title: context.t('login_title'),
      subtitle: host,
      footer: TextButton.icon(
        onPressed: session.busy ? null : session.changeServer,
        icon: const Icon(Icons.swap_horiz),
        label: Text(context.t('login_change_server')),
      ),
      children: [
        if (message != null && _error == null) ErrorBox(context.t(message), color: Nami.amber),
        if (_error != null) ErrorBox(_error!),
        TextField(
          key: const Key('login_user'),
          controller: _user,
          autocorrect: false,
          enableSuggestions: false,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.username],
          onSubmitted: (_) => _pwdFocus.requestFocus(),
          style: const TextStyle(fontSize: 17),
          decoration: InputDecoration(labelText: context.t('login_user'), prefixIcon: const Icon(Icons.person_outline)),
        ),
        const SizedBox(height: 14),
        TextField(
          key: const Key('login_password'),
          controller: _pwd,
          focusNode: _pwdFocus,
          obscureText: _obscure,
          autocorrect: false,
          enableSuggestions: false,
          textInputAction: TextInputAction.done,
          autofillHints: const [AutofillHints.password],
          onSubmitted: (_) => session.busy ? null : _submit(),
          style: const TextStyle(fontSize: 17),
          decoration: InputDecoration(
            labelText: context.t('login_password'),
            prefixIcon: const Icon(Icons.lock_outline),
            suffixIcon: IconButton(
              icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
        ),
        const SizedBox(height: 20),
        FilledButton(
          key: const Key('login_submit'),
          onPressed: session.busy ? null : _submit,
          child: session.busy
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
              : Text(context.t('login_button')),
        ),
        const SizedBox(height: 16),
        Text(context.t('login_help'), style: const TextStyle(color: Nami.muted, fontSize: 14)),
      ],
    );
  }
}

// ------------------------------------------------------------------ lock

class LockScreen extends StatefulWidget {
  const LockScreen({super.key, this.autoPrompt = true});
  final bool autoPrompt;
  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  bool _failed = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (widget.autoPrompt) WidgetsBinding.instance.addPostFrameCallback((_) => _unlock());
  }

  Future<void> _unlock() async {
    if (_busy) return;
    setState(() => _busy = true);
    final ok = await context.read<SessionController>().unlock(context.t('lock_reason'));
    if (mounted) {
      setState(() {
        _busy = false;
        _failed = !ok;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();
    final name = session.user?.fullName ?? '';
    return Scaffold(
      backgroundColor: Nami.deep,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(children: [
            const Spacer(),
            if (name.isNotEmpty) WaiterDisc(name: name, size: 72),
            const SizedBox(height: 16),
            Text(name, style: Nami.num(30, color: Nami.white)),
            const SizedBox(height: 6),
            Text(context.t('lock_title'), style: const TextStyle(color: Nami.onDeep, fontSize: 16)),
            const SizedBox(height: 40),
            SizedBox(
              width: 112,
              height: 112,
              child: Material(
                color: Nami.rail,
                shape: const CircleBorder(side: BorderSide(color: Nami.amber, width: 2)),
                child: InkWell(
                  key: const Key('lock_unlock'),
                  customBorder: const CircleBorder(),
                  onTap: _busy ? null : _unlock,
                  child: const Icon(Icons.fingerprint, size: 64, color: Nami.amber),
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (_failed) Text(context.t('lock_failed'), style: const TextStyle(color: Color(0xFFFFB4A8), fontSize: 15)),
            const Spacer(),
            TextButton(
              key: const Key('lock_password'),
              onPressed: session.usePasswordInstead,
              style: TextButton.styleFrom(foregroundColor: Nami.white),
              child: Text(context.t('lock_use_password')),
            ),
          ]),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ outlet

class ProfilePickerScreen extends StatelessWidget {
  const ProfilePickerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();
    final profiles = session.session?.profiles ?? const <PosProfile>[];
    return AuthScaffold(
      title: context.t('profile_pick'),
      subtitle: session.user?.fullName,
      footer: TextButton(
        onPressed: session.signOut,
        child: Text(context.t('acc_sign_out')),
      ),
      children: [
        for (final p in profiles)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: NamiCard(
              key: Key('profile_${p.name}'),
              onTap: () => session.chooseProfile(p),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              border: p.name == session.settings.selectedProfile ? Border.all(color: Nami.teal, width: 2) : null,
              child: Row(children: [
                const Icon(Icons.storefront_outlined, color: Nami.teal, size: 28),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(p.displayName, style: Nami.num(22)),
                    Text([p.branch, p.name].whereType<String>().where((s) => s.isNotEmpty).join(' · '),
                        style: const TextStyle(color: Nami.muted, fontSize: 14)),
                  ]),
                ),
                const Icon(Icons.chevron_right, color: Nami.muted),
              ]),
            ),
          ),
      ],
    );
  }
}
