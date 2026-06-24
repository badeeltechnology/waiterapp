import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/calls_provider.dart';
import '../models/models.dart';

class CallsScreen extends StatefulWidget {
  const CallsScreen({super.key});

  @override
  State<CallsScreen> createState() => _CallsScreenState();
}

class _CallsScreenState extends State<CallsScreen> {
  @override
  void initState() {
    super.initState();
    context.read<CallsProvider>().loadHistory();
  }

  @override
  Widget build(BuildContext context) {
    final cp = context.watch<CallsProvider>();

    return RefreshIndicator(
      onRefresh: () async {
        await cp.loadCalls();
        await cp.loadHistory();
      },
      child: cp.isLoading && cp.pendingCalls.isEmpty && cp.myCalls.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                // My active calls (Accepted — need to attend)
                if (cp.myCalls.isNotEmpty) ...[
                  _SectionHeader(
                    title: 'My Active Calls',
                    count: cp.myCalls.length,
                    color: Colors.blue,
                  ),
                  ...cp.myCalls.map((c) => _ActiveCallCard(call: c)),
                  const SizedBox(height: 16),
                ],

                // Pending calls (waiting for someone to accept)
                if (cp.pendingCalls.isNotEmpty) ...[
                  _SectionHeader(
                    title: 'Incoming Calls',
                    count: cp.pendingCalls.length,
                    color: Colors.orange,
                  ),
                  ...cp.pendingCalls.map((c) => _PendingCallCard(call: c)),
                  const SizedBox(height: 16),
                ],

                // Empty state
                if (cp.pendingCalls.isEmpty && cp.myCalls.isEmpty)
                  _EmptyState(),

                // History
                if (cp.history.isNotEmpty) ...[
                  _SectionHeader(
                    title: 'Today\'s History',
                    count: cp.history.length,
                    color: Colors.grey,
                  ),
                  ...cp.history.map((c) => _HistoryCallCard(call: c)),
                ],
              ],
            ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final int count;
  final Color color;
  const _SectionHeader({required this.title, required this.count, required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 16,
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(width: 8),
          Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey[700])),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(color: color.withAlpha(30), borderRadius: BorderRadius.circular(8)),
            child: Text('$count', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color)),
          ),
        ],
      ),
    );
  }
}

class _ActiveCallCard extends StatelessWidget {
  final WaiterCall call;
  const _ActiveCallCard({required this.call});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.blue.shade300, width: 2),
      ),
      color: Colors.blue.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Seat info — big and prominent
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.location_on, color: Colors.blue.shade700, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Go to: ${call.tableName}',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blue.shade900)),
                      if (call.roomName != null && call.roomName!.isNotEmpty)
                        Text(call.roomName!, style: TextStyle(fontSize: 13, color: Colors.blue.shade600)),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Restaurant + guest info
            Row(
              children: [
                Icon(Icons.restaurant, size: 14, color: Colors.blue.shade400),
                const SizedBox(width: 4),
                Text(call.restaurantName, style: TextStyle(fontSize: 13, color: Colors.blue.shade600)),
                if (call.guestName != null && call.guestName!.isNotEmpty) ...[
                  const SizedBox(width: 12),
                  Icon(Icons.person, size: 14, color: Colors.blue.shade400),
                  const SizedBox(width: 4),
                  Text(call.guestName!, style: TextStyle(fontSize: 13, color: Colors.blue.shade600)),
                ],
              ],
            ),

            if (call.notes != null && call.notes!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text('"${call.notes}"', style: TextStyle(fontSize: 12, color: Colors.blue.shade500, fontStyle: FontStyle.italic)),
            ],

            const SizedBox(height: 14),

            // Mark attended button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () async {
                  final success = await context.read<CallsProvider>().markAttended(call.name);
                  if (success && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Marked as attended — ${call.tableName}'),
                        backgroundColor: Colors.green,
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.check_circle, size: 20),
                label: const Text('Mark Attended', style: TextStyle(fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue.shade600,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PendingCallCard extends StatefulWidget {
  final WaiterCall call;
  const _PendingCallCard({required this.call});

  @override
  State<_PendingCallCard> createState() => _PendingCallCardState();
}

class _PendingCallCardState extends State<_PendingCallCard> {
  bool _accepting = false;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.orange.shade300, width: 1.5),
      ),
      color: Colors.orange.shade50,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.orange.shade100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.notifications_active, color: Colors.orange.shade700, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.call.tableName,
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.orange.shade900)),
                  Text(widget.call.restaurantName,
                    style: TextStyle(fontSize: 12, color: Colors.orange.shade600)),
                  if (widget.call.callTime != null)
                    Text(_formatTime(widget.call.callTime!),
                      style: TextStyle(fontSize: 11, color: Colors.orange.shade400)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: _accepting
                  ? null
                  : () async {
                      setState(() => _accepting = true);
                      final success = await context.read<CallsProvider>().acceptCall(widget.call.name);
                      if (mounted) setState(() => _accepting = false);
                      if (!success && mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Already accepted by another waiter'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange.shade600,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: _accepting
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Accept', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(String datetime) {
    try {
      return DateFormat('hh:mm a').format(DateTime.parse(datetime));
    } catch (_) {
      return datetime;
    }
  }
}

class _HistoryCallCard extends StatelessWidget {
  final WaiterCall call;
  const _HistoryCallCard({required this.call});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 4),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Icon(
              call.status == 'Attended' ? Icons.check_circle : Icons.cancel,
              size: 18,
              color: call.status == 'Attended' ? Colors.green : Colors.grey,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(call.tableName, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  Text(call.restaurantName, style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(call.status, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: Colors.grey[600])),
                if (call.callTime != null)
                  Text(_formatTime(call.callTime!), style: TextStyle(fontSize: 10, color: Colors.grey[400])),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(String datetime) {
    try {
      return DateFormat('hh:mm a').format(DateTime.parse(datetime));
    } catch (_) {
      return datetime;
    }
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.notifications_none, size: 56, color: Colors.grey[300]),
            const SizedBox(height: 12),
            Text('No active calls', style: TextStyle(color: Colors.grey[500], fontSize: 16)),
            const SizedBox(height: 4),
            Text('Pull down to refresh', style: TextStyle(color: Colors.grey[400], fontSize: 13)),
          ],
        ),
      ),
    );
  }
}

/// Full-screen alert dialog shown when a new call arrives
class IncomingCallAlert extends StatelessWidget {
  final WaiterCall call;
  final VoidCallback onAccept;
  final VoidCallback onDismiss;

  const IncomingCallAlert({
    super.key,
    required this.call,
    required this.onAccept,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black54,
      child: Center(
        child: Container(
          margin: const EdgeInsets.all(32),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [BoxShadow(color: Colors.black.withAlpha(40), blurRadius: 20, spreadRadius: 5)],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Animated bell icon
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 600),
                curve: Curves.elasticOut,
                builder: (_, value, child) => Transform.scale(scale: value, child: child),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.orange.shade200, width: 3),
                  ),
                  child: Icon(Icons.notifications_active, size: 48, color: Colors.orange.shade600),
                ),
              ),

              const SizedBox(height: 20),

              Text('New Call!',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.grey.shade800)),
              const SizedBox(height: 8),

              // Seat name — big
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(call.tableName,
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.orange.shade800)),
              ),

              const SizedBox(height: 10),
              Text(call.restaurantName,
                style: TextStyle(fontSize: 15, color: Colors.grey.shade600)),

              if (call.guestName != null && call.guestName!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text('Guest: ${call.guestName}',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
              ],

              const SizedBox(height: 24),

              // Buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onDismiss,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        side: BorderSide(color: Colors.grey.shade300),
                      ),
                      child: Text('Dismiss', style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: onAccept,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green.shade600,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        elevation: 2,
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.check_circle, size: 20),
                          SizedBox(width: 8),
                          Text('Accept', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
