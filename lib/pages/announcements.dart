import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:attendence_management_system/utils/responsive_utils.dart';


class AnnouncementsPage extends StatefulWidget {
  const AnnouncementsPage({super.key});

  @override
  State<AnnouncementsPage> createState() => _AnnouncementsPageState();
}

class _AnnouncementsPageState extends State<AnnouncementsPage> {
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;
  final _contentCtrl = TextEditingController();

  static const Color bpgGreen = Color(0xFF2E4A2C);

  bool _isSubmitting = false;
  String? _userRole;
  bool _isLoadingRole = true;

  /// UI filter for viewing announcements
  /// Allowed values: 'employee' | 'ceo'
  String _listFilter = 'employee';

  User get _user => _auth.currentUser!;

  bool get _isCeo => _userRole == 'ceo';
  bool get _isHr => _userRole == 'hr';
  bool get _isEmployee => _userRole == 'employee';

  @override
  void initState() {
    super.initState();
    _loadUserRole();
  }

  @override
  void dispose() {
    _contentCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadUserRole() async {
    try {
      final doc = await _firestore.collection('users').doc(_user.uid).get();
      if (doc.exists) {
        setState(() {
          _userRole = doc.data()?['role'] as String?;
          _isLoadingRole = false;
        });
      } else {
        setState(() {
          _userRole = 'employee'; // default role
          _isLoadingRole = false;
        });
      }
    } catch (e) {
      setState(() {
        _userRole = 'employee'; // default role
        _isLoadingRole = false;
      });
    }
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
      // Determine announcement type based on user role
      String announcementType;
      if (_isCeo) {
        announcementType = 'ceo';
      } else if (_isHr || _isEmployee) {
        announcementType = 'employee';
      } else {
        announcementType = 'employee'; // default
      }

      await _firestore.collection('announcements').add({
        'userName': userName,
        'title': '', // kept for schema compatibility; not shown in UI
        'content': content,
        'type': announcementType, // 'employee' | 'ceo'
        'fileUrl': null, // attachments removed
        'createdAt': FieldValue.serverTimestamp(),
        'userId': _user.uid,
        'likes': <String>[],
        'pinned': false,
        'reactions': <String, String>{},
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

  Future<void> _editAnnouncement(DocumentSnapshot doc) async {
    final data = doc.data()! as Map<String, dynamic>;
    final currentContent = data['content'] as String? ?? '';

    final controller = TextEditingController(text: currentContent);

    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Announcement'),
        content: TextField(
          controller: controller,
          maxLines: 5,
          decoration: const InputDecoration(
            hintText: 'Enter announcement content...',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            style: FilledButton.styleFrom(
              backgroundColor: bpgGreen,
              foregroundColor: Colors.white,
            ),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      try {
        await doc.reference.update({'content': result});
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Announcement updated successfully')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to update announcement: $e')),
          );
        }
      }
    }
  }

  Future<void> _deleteAnnouncement(DocumentSnapshot doc) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Announcement'),
        content: const Text(
            'Are you sure you want to delete this announcement? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.shade600,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        // Delete all comments first
        final commentsSnapshot =
            await doc.reference.collection('comments').get();
        for (final commentDoc in commentsSnapshot.docs) {
          await commentDoc.reference.delete();
        }

        // Delete the announcement
        await doc.reference.delete();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Announcement deleted successfully')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to delete announcement: $e')),
          );
        }
      }
    }
  }

  Future<void> _setReaction({
    required DocumentReference ref,
    required String userId,
    required String? emoji,
  }) async {
    try {
      if (emoji == null) {
        await ref.update({'reactions.$userId': FieldValue.delete()});
      } else {
        await ref.update({'reactions.$userId': emoji});
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update reaction: $e')),
        );
      }
    }
  }

  Future<void> _showLikesReactionsList(DocumentSnapshot doc) async {
    final data = doc.data()! as Map<String, dynamic>;
    final likes = List<String>.from(data['likes'] ?? []);
    final reactions = Map<String, dynamic>.from(data['reactions'] ?? {});

    if (likes.isEmpty && reactions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No likes or reactions yet')),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.6,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Likes & Reactions',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView(
                  children: [
                    if (likes.isNotEmpty) ...[
                      const Text(
                        'Likes',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      ...likes
                          .map((userId) => _buildUserListItem(userId, '❤️')),
                      const SizedBox(height: 16),
                    ],
                    if (reactions.isNotEmpty) ...[
                      const Text(
                        'Reactions',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      ...reactions.entries.map((entry) => _buildUserListItem(
                          entry.key, entry.value.toString())),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildUserListItem(String userId, String emoji) {
    return FutureBuilder<DocumentSnapshot>(
      future: _firestore.collection('users').doc(userId).get(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const ListTile(
            leading: CircularProgressIndicator(),
            title: Text('Loading...'),
          );
        }

        final userData = snapshot.data?.data() as Map<String, dynamic>?;
        final userName = userData?['userName'] ?? 'Unknown User';
        final userRole = userData?['role'] ?? 'employee';

        return ListTile(
          leading: Text(emoji, style: const TextStyle(fontSize: 20)),
          title: Text(userName),
          subtitle: Text(userRole.toUpperCase()),
          dense: true,
        );
      },
    );
  }

  Future<void> _editComment(
      DocumentReference commentRef, String currentText) async {
    final controller = TextEditingController(text: currentText);

    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Comment'),
        content: TextField(
          controller: controller,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: 'Enter comment...',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      try {
        await commentRef.update({'comment': result});
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Comment updated successfully')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to update comment: $e')),
          );
        }
      }
    }
  }

  Future<void> _deleteComment(DocumentReference commentRef) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Comment'),
        content: const Text(
            'Are you sure you want to delete this comment? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.shade600,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await commentRef.delete();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Comment deleted successfully')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to delete comment: $e')),
          );
        }
      }
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
    if (_isLoadingRole) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Announcements',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: bpgGreen,
        elevation: 0,
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: () => setState(() {}),
            icon: const Icon(Icons.refresh, color: Colors.white),
          ),
        ],
      ),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF30492D), Color(0xFF4CAF50)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Column(
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
                    return Center(
                      child: Text(
                        'No ${_listFilter == 'employee' ? 'employee/HR' : 'CEO'} announcements yet.',
                      ),
                    );
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
      ),
    );
  }

  Widget _composeCard() {
    return Card(
      margin: const EdgeInsets.all(12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: Colors.white,
      elevation: 4,
      shadowColor: bpgGreen.withOpacity(0.3),
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
                  style: FilledButton.styleFrom(
                    backgroundColor: bpgGreen,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 2,
                  ),
                  child: _isSubmitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Text('Post',
                          style: TextStyle(fontWeight: FontWeight.w600)),
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
            label: const Text('Employee/HR'),
            selected: _listFilter == 'employee',
            onSelected: (_) => setState(() => _listFilter = 'employee'),
            selectedColor: bpgGreen.withOpacity(0.2),
            checkmarkColor: bpgGreen,
            labelStyle: TextStyle(
              color:
                  _listFilter == 'employee' ? bpgGreen : Colors.grey.shade700,
              fontWeight: _listFilter == 'employee'
                  ? FontWeight.w600
                  : FontWeight.normal,
            ),
          ),
          ChoiceChip(
            label: const Text('CEO'),
            selected: _listFilter == 'ceo',
            onSelected: (_) => setState(() => _listFilter = 'ceo'),
            selectedColor: bpgGreen.withOpacity(0.2),
            checkmarkColor: bpgGreen,
            labelStyle: TextStyle(
              color: _listFilter == 'ceo' ? bpgGreen : Colors.grey.shade700,
              fontWeight:
                  _listFilter == 'ceo' ? FontWeight.w600 : FontWeight.normal,
            ),
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
      color: Colors.white,
      elevation: 2,
      shadowColor: bpgGreen.withOpacity(0.2),
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
                              : Colors.blue.withOpacity(0.12),
                        ),
                        child: Text(
                          type == 'ceo' ? 'CEO' : 'EMPLOYEE/HR',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ),
                    ],
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_isCeo)
                      IconButton(
                        tooltip: pinned ? 'Unpin' : 'Pin',
                        onPressed: () => _togglePin(doc),
                        icon: Icon(
                            pinned ? Icons.push_pin : Icons.push_pin_outlined),
                      ),
                    PopupMenuButton<String>(
                      onSelected: (value) {
                        switch (value) {
                          case 'edit':
                            _editAnnouncement(doc);
                            break;
                          case 'delete':
                            _deleteAnnouncement(doc);
                            break;
                        }
                      },
                      itemBuilder: (context) {
                        final isOwner = data['userId'] == _user.uid;
                        final canModerate = _isCeo || _isHr;

                        return [
                          if (isOwner)
                            const PopupMenuItem(
                              value: 'edit',
                              child: Row(
                                children: [
                                  Icon(Icons.edit, size: 18),
                                  SizedBox(width: 8),
                                  Text('Edit'),
                                ],
                              ),
                            ),
                          if (isOwner || canModerate)
                            const PopupMenuItem(
                              value: 'delete',
                              child: Row(
                                children: [
                                  Icon(Icons.delete,
                                      size: 18, color: Colors.red),
                                  SizedBox(width: 8),
                                  Text('Delete',
                                      style: TextStyle(color: Colors.red)),
                                ],
                              ),
                            ),
                        ];
                      },
                      child: const Icon(Icons.more_vert),
                    ),
                  ],
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
                  icon: Icon(
                    liked ? Icons.favorite : Icons.favorite_border,
                    color: liked ? Colors.red.shade600 : Colors.grey.shade600,
                  ),
                  style: IconButton.styleFrom(
                    backgroundColor:
                        liked ? Colors.red.shade50 : Colors.grey.shade100,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () => _showLikesReactionsList(doc),
                  child: Text(
                    likes.length.toString(),
                    style: TextStyle(
                      color: likes.isNotEmpty
                          ? Theme.of(context).colorScheme.primary
                          : null,
                      fontWeight: likes.isNotEmpty ? FontWeight.w600 : null,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: _reactionMenuButton(
                    onSelected: (emoji) => _setReaction(
                        ref: doc.reference, userId: _user.uid, emoji: emoji),
                  ),
                ),
                if (reactionCounts.isNotEmpty) ...[
                  SizedBox(width: context.w(2)),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => _showLikesReactionsList(doc),
                      child: Wrap(
                        spacing: context.w(2),
                        runSpacing: context.h(0.5), // Changed from -8 to positive small value
                        alignment: WrapAlignment.start,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: reactionCounts.entries
                            .map((e) => Chip(
                          label: Text(
                            '${e.key} ${e.value}',
                            style: TextStyle(
                              fontSize: context.sp(12), // Added responsive font size
                              color: bpgGreen,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          backgroundColor: bpgGreen.withOpacity(0.15),
                          side: BorderSide(
                            color: bpgGreen.withOpacity(0.3),
                            width: 1,
                          ),
                          padding: EdgeInsets.symmetric(
                            horizontal: context.w(2),
                            vertical: context.h(0.3),
                          ), // Added responsive padding
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap, // Reduces chip size
                          visualDensity: VisualDensity.compact, // Makes it more compact
                        ))
                            .toList(),
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                TextButton.icon(
                  onPressed: () => _openCommentsSheet(doc.reference),
                  icon: const Icon(Icons.comment_outlined, color: bpgGreen),
                  label: const Text('Comments',
                      style: TextStyle(
                          color: bpgGreen, fontWeight: FontWeight.w500)),
                  style: TextButton.styleFrom(
                    backgroundColor: bpgGreen.withOpacity(0.1),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
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
      child: const Icon(Icons.emoji_emotions_outlined, color: bpgGreen),
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
        bool isSubmittingComment = false;

        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
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
                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
                            return const Center(
                                child: CircularProgressIndicator());
                          }
                          if (snapshot.hasError) {
                            return Center(
                                child: Text('Error: ${snapshot.error}'));
                          }
                          final docs = snapshot.data?.docs ?? [];
                          if (docs.isEmpty) {
                            return const Center(
                                child: Text('Be the first to comment.'));
                          }
                          return ListView.separated(
                            padding: const EdgeInsets.all(12),
                            itemCount: docs.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final d = docs[index];
                              final m = d.data()! as Map<String, dynamic>;
                              final reactions = Map<String, dynamic>.from(
                                  m['reactions'] ?? {});
                              final reactionCounts = <String, int>{};
                              for (final r in reactions.values) {
                                final e = r?.toString() ?? '';
                                if (e.isEmpty) continue;
                                reactionCounts[e] =
                                    (reactionCounts[e] ?? 0) + 1;
                              }
                              return Card(
                                color: Colors.grey.shade50,
                                elevation: 1,
                                shadowColor: bpgGreen.withOpacity(0.1),
                                child: Padding(
                                  padding: const EdgeInsets.all(8.0),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${m['userName'] ?? 'Anonymous'} • ${_formatTime(m['createdAt'] as Timestamp?)}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall,
                                      ),
                                      const SizedBox(height: 6),
                                      // Linkified comments too
                                      Linkify(
                                        text: (m['comment'] as String?) ?? '',
                                        onOpen: (link) => _openLink(link.url),
                                        options: const LinkifyOptions(
                                            humanize: true),
                                        linkStyle: TextStyle(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .primary,
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
                                                            '${e.key} ${e.value}'),
                                                        backgroundColor:
                                                            bpgGreen
                                                                .withOpacity(
                                                                    0.15),
                                                        labelStyle: TextStyle(
                                                          color: bpgGreen,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                          fontSize: 11,
                                                        ),
                                                        side: BorderSide(
                                                          color: bpgGreen
                                                              .withOpacity(0.3),
                                                          width: 1,
                                                        ),
                                                      ))
                                                  .toList(),
                                            ),
                                          ],
                                          const Spacer(),
                                          PopupMenuButton<String>(
                                            onSelected: (value) {
                                              switch (value) {
                                                case 'edit':
                                                  _editComment(
                                                      d.reference,
                                                      m['comment'] as String? ??
                                                          '');
                                                  break;
                                                case 'delete':
                                                  _deleteComment(d.reference);
                                                  break;
                                              }
                                            },
                                            itemBuilder: (context) {
                                              final isOwner =
                                                  m['userId'] == _user.uid;
                                              final canModerate =
                                                  _isCeo || _isHr;

                                              return [
                                                if (isOwner)
                                                  const PopupMenuItem(
                                                    value: 'edit',
                                                    child: Row(
                                                      children: [
                                                        Icon(Icons.edit,
                                                            size: 18),
                                                        SizedBox(width: 8),
                                                        Text('Edit'),
                                                      ],
                                                    ),
                                                  ),
                                                if (isOwner || canModerate)
                                                  const PopupMenuItem(
                                                    value: 'delete',
                                                    child: Row(
                                                      children: [
                                                        Icon(Icons.delete,
                                                            size: 18,
                                                            color: Colors.red),
                                                        SizedBox(width: 8),
                                                        Text('Delete',
                                                            style: TextStyle(
                                                                color: Colors
                                                                    .red)),
                                                      ],
                                                    ),
                                                  ),
                                              ];
                                            },
                                            child: const Icon(Icons.more_vert,
                                                size: 16),
                                          ),
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
                            style: FilledButton.styleFrom(
                              backgroundColor: bpgGreen,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 20, vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 2,
                            ),
                            onPressed: isSubmittingComment
                                ? null
                                : () async {
                                    final text = commentCtrl.text.trim();
                                    if (text.isEmpty) return;

                                    setModalState(() {
                                      isSubmittingComment = true;
                                    });

                                    try {
                                      await announcementRef
                                          .collection('comments')
                                          .add({
                                        'userId': _user.uid,
                                        'userName': userName,
                                        'comment': text,
                                        'createdAt':
                                            FieldValue.serverTimestamp(),
                                        'reactions': <String, String>{},
                                      });
                                      commentCtrl.clear();
                                    } catch (e) {
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          SnackBar(
                                              content: Text(
                                                  'Failed to post comment: $e')),
                                        );
                                      }
                                    } finally {
                                      if (context.mounted) {
                                        setModalState(() {
                                          isSubmittingComment = false;
                                        });
                                      }
                                    }
                                  },
                            child: isSubmittingComment
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.white),
                                  )
                                : const Text('Send',
                                    style:
                                        TextStyle(fontWeight: FontWeight.w600)),
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
      },
    );
  }
}
