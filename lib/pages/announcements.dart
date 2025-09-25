import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_linkify/flutter_linkify.dart';

// Configure your CEO email(s) here.
const Set<String> _ceoEmails = {
  'ceo@yourcompany.com', // change to your real CEO email(s)
};

class AnnouncementsPage extends StatefulWidget {
  const AnnouncementsPage({super.key});

  @override
  State<AnnouncementsPage> createState() => _AnnouncementsPageState();
}

class _AnnouncementsPageState extends State<AnnouncementsPage> {
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;
  final _contentCtrl = TextEditingController();

  bool _isSubmitting = false;

  /// UI filter; also doubles as post type when the user is CEO.
  /// Allowed values: 'employee' | 'ceo'
  String _listFilter = 'employee';

  User get _user => _auth.currentUser!;

  bool get _isCeo {
    final email = _user.email?.toLowerCase();
    if (email == null) return false;
    return _ceoEmails.contains(email);
  }

  @override
  void dispose() {
    _contentCtrl.dispose();
    super.dispose();
  }

  Future<String> _resolveUserName() async {
    try {
      final doc = await _firestore.collection('users').doc(_user.uid).get();
      final fromUsers = doc.data()?['userName'] as String?;
      if (fromUsers != null && fromUsers.trim().isNotEmpty) {
        return fromUsers.trim();
      }
    } catch (_) {}
    final display = _user.displayName;
    if (display != null && display.trim().isNotEmpty) return display.trim();
    return 'Anonymous';
  }

  Future<void> _submitAnnouncement() async {
    final content = _contentCtrl.text.trim();
    if (content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter content.')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final userName = await _resolveUserName();
      final type = _isCeo ? _listFilter : 'employee';

      await _firestore.collection('announcements').add({
        'userName': userName,
        'title': '', // kept for schema compatibility; not shown in UI
        'content': content,
        'type': type, // 'employee' | 'ceo'
        'fileUrl': null, // attachments removed
        'createdAt': FieldValue.serverTimestamp(),
        'userId': _user.uid,
        'likes': <String>[],
        'pinned': false,
      });

      _contentCtrl.clear();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Announcement posted.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to post: $e')),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Query _buildQuery() {
    return _firestore
        .collection('announcements')
        .where('type', isEqualTo: _listFilter)
        .orderBy('pinned', descending: true)
        .orderBy('createdAt', descending: true);
  }

  Future<void> _toggleLike(DocumentSnapshot doc) async {
    final id = _user.uid;
    final likes = List<String>.from(doc['likes'] ?? []);
    final ref = doc.reference;
    if (likes.contains(id)) {
      await ref.update({
        'likes': FieldValue.arrayRemove([id])
      });
    } else {
      await ref.update({
        'likes': FieldValue.arrayUnion([id])
      });
    }
  }

  Future<void> _togglePin(DocumentSnapshot doc) async {
    if (!_isCeo) return;
    final current = (doc['pinned'] as bool?) ?? false;
    await doc.reference.update({'pinned': !current});
  }

  Future<void> _setReaction({
    required DocumentReference ref,
    required String userId,
    required String? emoji,
  }) async {
    if (emoji == null) {
      await ref.update({'reactions.$userId': FieldValue.delete()});
    } else {
      await ref.set({
        'reactions': {userId: emoji}
      }, SetOptions(merge: true));
    }
  }

  String _formatTime(Timestamp? ts) {
    final dt = ts?.toDate();
    if (dt == null) return '';
    return timeago.format(dt, allowFromNow: true);
  }

  // ---------- Link handling ----------
  Future<void> _openLink(String raw) async {
    // Add scheme to bare domains.
    final String url = raw.startsWith('http')
        ? raw
        : (raw.startsWith('mailto:') ? raw : 'https://$raw');
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      // Fallback: try default open
      await launchUrl(uri);
    }
  }

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Announcements'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: () => setState(() {}),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          _composeCard(),
          const SizedBox(height: 4),
          _filterChips(),
          const Divider(height: 24),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _buildQuery().snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }
                final docs = snapshot.data?.docs ?? [];
                if (docs.isEmpty) {
                  return const Center(child: Text('No announcements yet.'));
                }
                return ListView.separated(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) =>
                      _announcementCard(docs[index]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _composeCard() {
    return Card(
      margin: const EdgeInsets.all(12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // No Title, no attachments — just content.
            TextField(
              controller: _contentCtrl,
              minLines: 3,
              maxLines: 6,
              decoration: const InputDecoration(
                labelText: "What's new?",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Spacer(),
                FilledButton(
                  onPressed: _isSubmitting ? null : _submitAnnouncement,
                  child: _isSubmitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Post'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _filterChips() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Wrap(
        spacing: 8,
        children: [
          ChoiceChip(
            label: const Text('Employee'),
            selected: _listFilter == 'employee',
            onSelected: (_) => setState(() => _listFilter = 'employee'),
          ),
          ChoiceChip(
            label: const Text('CEO'),
            selected: _listFilter == 'ceo',
            onSelected: (_) => setState(() => _listFilter = 'ceo'),
          ),
        ],
      ),
    );
  }

  Widget _announcementCard(DocumentSnapshot doc) {
    final data = doc.data()! as Map<String, dynamic>;
    final likes = List<String>.from(data['likes'] ?? []);
    final liked = likes.contains(_user.uid);
    final pinned = (data['pinned'] as bool?) ?? false;
    final type = (data['type'] as String?) ?? 'employee';

    final reactions = Map<String, dynamic>.from(data['reactions'] ?? {});
    final reactionCounts = <String, int>{};
    for (final r in reactions.values) {
      final e = r?.toString() ?? '';
      if (e.isEmpty) continue;
      reactionCounts[e] = (reactionCounts[e] ?? 0) + 1;
    }

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header line: Author • time • type badge • pin button (CEO only)
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    children: [
                      if (pinned) const Icon(Icons.push_pin, size: 16),
                      Text(
                        '${data['userName'] ?? 'Anonymous'} • ${_formatTime(data['createdAt'] as Timestamp?)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(999),
                          color: type == 'ceo'
                              ? Colors.purple.withOpacity(0.12)
                              : Colors.grey.withOpacity(0.15),
                        ),
                        child: Text(
                          type.toUpperCase(),
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_isCeo)
                  IconButton(
                    tooltip: pinned ? 'Unpin' : 'Pin',
                    onPressed: () => _togglePin(doc),
                    icon:
                        Icon(pinned ? Icons.push_pin : Icons.push_pin_outlined),
                  ),
              ],
            ),
            const SizedBox(height: 8),

            // Body content — linkified
            Linkify(
              text: (data['content'] as String?) ?? '',
              onOpen: (link) => _openLink(link.url),
              options: const LinkifyOptions(humanize: true),
              linkStyle: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                decoration: TextDecoration.underline,
              ),
              // You can style normal text via DefaultTextStyle.of(context)
            ),

            const SizedBox(height: 8),

            Row(
              children: [
                IconButton(
                  onPressed: () => _toggleLike(doc),
                  icon: Icon(liked ? Icons.favorite : Icons.favorite_border),
                ),
                Text(likes.length.toString()),
                const SizedBox(width: 12),
                _reactionMenuButton(
                  onSelected: (emoji) => _setReaction(
                      ref: doc.reference, userId: _user.uid, emoji: emoji),
                ),
                if (reactionCounts.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: -8,
                      children: reactionCounts.entries
                          .map((e) => Chip(label: Text('${e.key} ${e.value}')))
                          .toList(),
                    ),
                  ),
                ],
                const Spacer(),
                TextButton.icon(
                  onPressed: () => _openCommentsSheet(doc.reference),
                  icon: const Icon(Icons.comment_outlined),
                  label: const Text('Comments'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  PopupMenuButton<String> _reactionMenuButton({
    required ValueChanged<String?> onSelected,
  }) {
    const emojis = ['👍', '❤️', '🎉', '😮', '👏', '🔥'];
    return PopupMenuButton<String>(
      tooltip: 'React',
      itemBuilder: (context) => [
        ...emojis.map((e) => PopupMenuItem(value: e, child: Text(e))),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'REMOVE', child: Text('Remove reaction')),
      ],
      onSelected: (value) {
        if (value == 'REMOVE') {
          onSelected(null);
        } else {
          onSelected(value);
        }
      },
      child: const Icon(Icons.emoji_emotions_outlined),
    );
  }

  Future<void> _openCommentsSheet(DocumentReference announcementRef) async {
    final userName = await _resolveUserName();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        final commentCtrl = TextEditingController();
        return Padding(
          padding:
              EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.7,
            child: Column(
              children: [
                const SizedBox(height: 8),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade400,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 8),
                const Text('Comments',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const Divider(),
                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: announcementRef
                        .collection('comments')
                        .orderBy('createdAt', descending: true)
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final docs = snapshot.data!.docs;
                      if (docs.isEmpty) {
                        return const Center(
                            child: Text('Be the first to comment.'));
                      }
                      return ListView.separated(
                        padding: const EdgeInsets.all(12),
                        itemCount: docs.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final d = docs[index];
                          final m = d.data()! as Map<String, dynamic>;
                          final reactions =
                              Map<String, dynamic>.from(m['reactions'] ?? {});
                          final reactionCounts = <String, int>{};
                          for (final r in reactions.values) {
                            final e = r?.toString() ?? '';
                            if (e.isEmpty) continue;
                            reactionCounts[e] = (reactionCounts[e] ?? 0) + 1;
                          }
                          return Card(
                            child: Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${m['userName'] ?? 'Anonymous'} • ${_formatTime(m['createdAt'] as Timestamp?)}',
                                    style:
                                        Theme.of(context).textTheme.bodySmall,
                                  ),
                                  const SizedBox(height: 6),
                                  // Linkified comments too
                                  Linkify(
                                    text: (m['comment'] as String?) ?? '',
                                    onOpen: (link) => _openLink(link.url),
                                    options:
                                        const LinkifyOptions(humanize: true),
                                    linkStyle: TextStyle(
                                      color:
                                          Theme.of(context).colorScheme.primary,
                                      decoration: TextDecoration.underline,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      _reactionMenuButton(
                                        onSelected: (emoji) => _setReaction(
                                          ref: d.reference,
                                          userId: _user.uid,
                                          emoji: emoji,
                                        ),
                                      ),
                                      if (reactionCounts.isNotEmpty) ...[
                                        const SizedBox(width: 8),
                                        Wrap(
                                          spacing: 8,
                                          children: reactionCounts.entries
                                              .map((e) => Chip(
                                                  label: Text(
                                                      '${e.key} ${e.value}')))
                                              .toList(),
                                        ),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: commentCtrl,
                          decoration: const InputDecoration(
                            hintText: 'Add a comment…',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: () async {
                          final text = commentCtrl.text.trim();
                          if (text.isEmpty) return;
                          await announcementRef.collection('comments').add({
                            'userId': _user.uid,
                            'userName': userName,
                            'comment': text,
                            'createdAt': FieldValue.serverTimestamp(),
                          });
                          commentCtrl.clear();
                        },
                        child: const Text('Send'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
