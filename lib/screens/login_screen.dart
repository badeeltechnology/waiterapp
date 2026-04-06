import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../providers/auth_provider.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _showScanner = false;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final theme = Theme.of(context);

    // QR Scanner
    if (_showScanner) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Scan QR Code'),
          leading: IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => _showScanner = false)),
        ),
        body: MobileScanner(
          onDetect: (capture) async {
            final barcode = capture.barcodes.firstOrNull;
            if (barcode?.rawValue != null) {
              setState(() => _showScanner = false);
              await auth.configureFromQR(barcode!.rawValue!);
            }
          },
        ),
      );
    }

    // Not configured yet — show QR setup
    if (!auth.isConfigured) {
      return Scaffold(
        backgroundColor: theme.colorScheme.surface,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 80, height: 80,
                    decoration: BoxDecoration(color: theme.colorScheme.primary, borderRadius: BorderRadius.circular(20)),
                    child: const Icon(Icons.restaurant_menu, color: Colors.white, size: 40),
                  ),
                  const SizedBox(height: 16),
                  Text('ServePOS', style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900, color: theme.colorScheme.primary)),
                  const SizedBox(height: 4),
                  Text('Waiter App', style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey)),
                  const SizedBox(height: 48),
                  const Text('Scan the QR code from your\nPOS terminal to get started', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, fontSize: 15)),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: () => setState(() => _showScanner = true),
                    icon: const Icon(Icons.qr_code_scanner, size: 24),
                    label: const Text('Scan QR Code', style: TextStyle(fontSize: 16)),
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                  ),
                  if (auth.error != null) ...[
                    const SizedBox(height: 16),
                    Text(auth.error!, style: TextStyle(color: Colors.red[700], fontSize: 13), textAlign: TextAlign.center),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    }

    // Configured — show waiter selection + PIN
    return _WaiterLoginScreen();
  }
}

class _WaiterLoginScreen extends StatefulWidget {
  @override
  State<_WaiterLoginScreen> createState() => _WaiterLoginScreenState();
}

class _WaiterLoginScreenState extends State<_WaiterLoginScreen> {
  String? _selectedWaiter;
  final _pinController = TextEditingController();
  bool _showPinEntry = false;

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'reset') auth.resetConfig();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'reset', child: Row(children: [
                Icon(Icons.link_off, size: 18, color: Colors.red),
                SizedBox(width: 8),
                Text('Disconnect', style: TextStyle(color: Colors.red)),
              ])),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: !_showPinEntry
          // Waiter list
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const SizedBox(height: 20),
                      Text('Welcome', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text('Select your name to continue', style: TextStyle(color: Colors.grey[600])),
                      Text(auth.serverUrl, style: TextStyle(color: Colors.grey[400], fontSize: 11)),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Expanded(
                  child: auth.waiters.isEmpty
                    ? Center(
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.person_off, size: 48, color: Colors.grey[300]),
                          const SizedBox(height: 12),
                          const Text('No waiters found', style: TextStyle(color: Colors.grey)),
                          const SizedBox(height: 8),
                          TextButton.icon(
                            onPressed: () => auth.loadWaiters(),
                            icon: const Icon(Icons.refresh),
                            label: const Text('Refresh'),
                          ),
                        ]),
                      )
                    : RefreshIndicator(
                        onRefresh: () => auth.loadWaiters(),
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          itemCount: auth.waiters.length,
                          itemBuilder: (_, i) {
                            final w = auth.waiters[i];
                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: theme.colorScheme.primaryContainer,
                                  child: Text(
                                    (w['waiter_name'] ?? '?')[0].toUpperCase(),
                                    style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.primary),
                                  ),
                                ),
                                title: Text(w['waiter_name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () {
                                  setState(() {
                                    _selectedWaiter = w['waiter_name'];
                                    _showPinEntry = true;
                                    _pinController.clear();
                                  });
                                },
                              ),
                            );
                          },
                        ),
                      ),
                ),
              ],
            )
          // PIN entry — full screen centered
          : Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: CircleAvatar(
                        radius: 44,
                        backgroundColor: theme.colorScheme.primaryContainer,
                        child: Text(
                          (_selectedWaiter ?? '?')[0].toUpperCase(),
                          style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: theme.colorScheme.primary),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Center(
                      child: Text(_selectedWaiter ?? '', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(height: 32),
                    TextField(
                      controller: _pinController,
                      obscureText: true,
                      autofocus: true,
                      textAlign: TextAlign.center,
                      keyboardType: TextInputType.number,
                      maxLength: 8,
                      style: const TextStyle(fontSize: 28, letterSpacing: 12, fontWeight: FontWeight.bold),
                      decoration: InputDecoration(
                        hintText: 'Enter PIN',
                        hintStyle: TextStyle(fontSize: 16, letterSpacing: 1, color: Colors.grey[400]),
                        counterText: '',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                        contentPadding: const EdgeInsets.symmetric(vertical: 20),
                      ),
                      onSubmitted: (_) => _login(),
                    ),
                    if (auth.error != null) ...[
                      const SizedBox(height: 12),
                      Text(auth.error!, style: TextStyle(color: Colors.red[700], fontSize: 13), textAlign: TextAlign.center),
                    ],
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: auth.isLoading ? null : _login,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: auth.isLoading
                        ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Login', style: TextStyle(fontSize: 17)),
                    ),
                    const SizedBox(height: 16),
                    Center(
                      child: TextButton(
                        onPressed: () => setState(() { _showPinEntry = false; _selectedWaiter = null; }),
                        child: const Text('Back to waiter list'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
      ),
    );
  }

  Future<void> _login() async {
    if (_selectedWaiter == null || _pinController.text.isEmpty) return;
    await context.read<AuthProvider>().loginWithPin(_selectedWaiter!, _pinController.text);
  }
}
