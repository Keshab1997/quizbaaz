import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../data/services/shop_service.dart';
import '../../../data/services/trusted_ops_service.dart';
import '../../../l10n/app_strings.dart';

/// Screen to view all users or guests from Firestore.
class UserListScreen extends StatefulWidget {
  final bool isGuestView;

  const UserListScreen({super.key, this.isGuestView = false});

  @override
  State<UserListScreen> createState() => _UserListScreenState();
}

class _UserListScreenState extends State<UserListScreen> {
  final TextEditingController _searchController = TextEditingController();
  late Future<List<Map<String, dynamic>>> _usersFuture;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _refreshUsers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _refreshUsers() {
    _usersFuture = ShopService.getUsers(guestsOnly: widget.isGuestView);
  }

  List<Map<String, dynamic>> _filteredUsers(List<Map<String, dynamic>> users) {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) return users;
    return users.where((user) {
      final name = _displayName(user).toLowerCase();
      final username = (user['username'] ?? '').toString().toLowerCase();
      final id = _userId(user).toLowerCase();
      return name.contains(query) || username.contains(query) || id.contains(query);
    }).toList();
  }

  String _userId(Map<String, dynamic> user) =>
      (user['user_id'] ?? user['id'] ?? '').toString();

  String _displayName(Map<String, dynamic> user) {
    final fullName = (user['full_name'] ?? '').toString().trim();
    final username = (user['username'] ?? '').toString().trim();
    if (fullName.isNotEmpty) return fullName;
    if (username.isNotEmpty) return username;
    return widget.isGuestView ? 'Guest User' : 'User';
  }

  String _subtitle(Map<String, dynamic> user) {
    final username = (user['username'] ?? '').toString().trim();
    final id = _userId(user);
    if (username.isNotEmpty && id.isNotEmpty) return '@$username • $id';
    if (username.isNotEmpty) return '@$username';
    return id;
  }

  int _todayCount(List<Map<String, dynamic>> users) {
    final now = DateTime.now();
    final today = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    return users.where((user) {
      final lastStreakDate = (user['last_streak_date'] ?? '').toString();
      final playedToday = user['played_today_daily_quiz'] == true;
      return playedToday || lastStreakDate == today;
    }).length;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.isGuestView ? 'Guest Users' : 'All Users',
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.w900,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AppColors.neonCyan),
            onPressed: () => setState(_refreshUsers),
          ),
        ],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _usersFuture,
        builder: (context, snapshot) {
          final users = snapshot.data ?? const <Map<String, dynamic>>[];
          final filteredUsers = _filteredUsers(users);
          final isLoading = snapshot.connectionState == ConnectionState.waiting;

          return Column(
            children: [
              _buildSearchBar(),
              _buildStatsRow(users, isLoading),
              const SizedBox(height: 16),
              Expanded(
                child: isLoading
                    ? const Center(child: CircularProgressIndicator(color: AppColors.neonCyan))
                    : snapshot.hasError
                        ? _buildEmptyState('Failed to load users', Icons.error_outline_rounded, detail: ShopService.lastError)
                        : filteredUsers.isEmpty
                            ? _buildEmptyState(
                                widget.isGuestView ? 'No Guest Users' : 'No Users Yet',
                                widget.isGuestView ? Icons.person_outline_rounded : Icons.people_rounded,
                                detail: ShopService.lastError,
                              )
                            : _buildUserList(filteredUsers),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: TextField(
        controller: _searchController,
        onChanged: (value) => setState(() => _searchQuery = value),
        style: const TextStyle(color: AppColors.textPrimary),
        decoration: InputDecoration(
          hintText: 'Search users...',
          hintStyle: TextStyle(color: AppColors.textMuted.withValues(alpha: 0.5)),
          prefixIcon: const Icon(Icons.search_rounded, color: AppColors.neonCyan),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear_rounded, color: AppColors.textMuted),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                )
              : null,
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.05),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppColors.neonCyan),
          ),
        ),
      ),
    );
  }

  Widget _buildStatsRow(List<Map<String, dynamic>> users, bool isLoading) {
    final activeUsers = users.where((user) => user['is_guest'] != true).length;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          _buildMiniStat(Icons.people_rounded, 'Total', isLoading ? '...' : '${users.length}', AppColors.neonCyan),
          const SizedBox(width: 12),
          _buildMiniStat(Icons.check_circle_rounded, 'Active', isLoading ? '...' : '$activeUsers', AppColors.neonGreen),
          const SizedBox(width: 12),
          _buildMiniStat(Icons.schedule_rounded, S.today, isLoading ? '...' : '${_todayCount(users)}', AppColors.neonGold),
        ],
      ),
    );
  }

  Widget _buildMiniStat(IconData icon, String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(width: 6),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(value, style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.w900)),
                Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 9)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUserList(List<Map<String, dynamic>> users) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
      itemCount: users.length,
      itemBuilder: (context, index) => _buildUserCard(users[index]),
    );
  }

  Widget _buildUserCard(Map<String, dynamic> user) {
    final isAdmin = user['is_admin'] == true;
    final isGuest = user['is_guest'] == true;
    final coins = (user['coins'] as num?)?.toInt() ?? 0;
    final gems = (user['gems'] as num?)?.toInt() ?? 0;
    return Card(
      color: Colors.white.withValues(alpha: 0.05),
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: AppColors.neonCyan.withValues(alpha: 0.15),
          child: Icon(isGuest ? Icons.person_outline_rounded : Icons.person_rounded, color: AppColors.neonCyan),
        ),
        title: Text(_displayName(user), style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w800)),
        subtitle: Text(
          '${_subtitle(user)}\nCoins: $coins • Gems: $gems${isAdmin ? ' • Admin' : ''}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
        ),
        isThreeLine: true,
        trailing: PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert_rounded, color: AppColors.textMuted),
          onSelected: (value) {
            if (value == 'edit') _showEditUserSheet(user);
            if (value == 'admin') _toggleAdmin(user);
            if (value == 'delete') _showDeleteUserDialog(user);
          },
          itemBuilder: (context) => [
            const PopupMenuItem(value: 'edit', child: Text('Edit')),
            PopupMenuItem(value: 'admin', child: Text(isAdmin ? 'Remove Admin' : 'Make Admin')),
            const PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: AppColors.neonRed))),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(String title, IconData icon, {String? detail}) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 60, color: AppColors.textMuted.withValues(alpha: 0.3)),
          const SizedBox(height: 16),
          Text(title, style: const TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text(
            detail?.isNotEmpty == true ? detail! : 'Firestore data will appear here',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
        ],
      ),
    );
  }

  void _showEditUserSheet(Map<String, dynamic> user) {
    final usernameController = TextEditingController(text: (user['username'] ?? '').toString());
    final fullNameController = TextEditingController(text: (user['full_name'] ?? '').toString());
    final coinsController = TextEditingController(text: '${(user['coins'] as num?)?.toInt() ?? 0}');
    final gemsController = TextEditingController(text: '${(user['gems'] as num?)?.toInt() ?? 0}');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceElevated,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Edit User', style: TextStyle(color: AppColors.textPrimary, fontSize: 20, fontWeight: FontWeight.w900)),
              const SizedBox(height: 16),
              _sheetField(usernameController, S.profileUsername),
              const SizedBox(height: 12),
              _sheetField(fullNameController, 'Full Name'),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: _sheetField(coinsController, S.coins, TextInputType.number)),
                const SizedBox(width: 12),
                Expanded(child: _sheetField(gemsController, S.gems, TextInputType.number)),
              ]),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    final navigator = Navigator.of(ctx);
                    final ok = await ShopService.updateUser(_userId(user), {
                      'username': usernameController.text.trim(),
                      'full_name': fullNameController.text.trim(),
                      'coins': int.tryParse(coinsController.text.trim()) ?? 0,
                      'gems': int.tryParse(gemsController.text.trim()) ?? 0,
                    });
                    if (!mounted) return;
                    navigator.pop();
                    _showSnack(ok ? '✅ User updated' : '❌ Update failed', ok);
                    if (ok) setState(_refreshUsers);
                  },
                  child: Text(S.save),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sheetField(TextEditingController controller, String label, [TextInputType? keyboardType]) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      style: const TextStyle(color: AppColors.textPrimary),
      decoration: InputDecoration(labelText: label, filled: true, fillColor: Colors.white.withValues(alpha: 0.05)),
    );
  }

  Future<void> _toggleAdmin(Map<String, dynamic> user) async {
    // Authority is the `admin` custom claim issued by the setAdmin callable
    // (functions/src/admin.ts) — a client write to `is_admin` alone is denied
    // by firestore.rules and can never grant authority. Issue/revoke the
    // claim first, then mirror the display flag (succeeds when the caller
    // already holds the claim).
    final uid = _userId(user);
    final grant = user['is_admin'] != true;
    final claimOk = await TrustedOpsService.setAdmin(uid: uid, admin: grant);
    if (!mounted) return;
    if (!claimOk) {
      _showSnack(
          '❌ ${ShopService.lastError ?? 'Admin claim failed — need admin claim or bootstrap account'}',
          false);
      return;
    }
    final ok = await ShopService.updateUser(uid, {'is_admin': grant});
    if (!mounted) return;
    _showSnack(ok ? '✅ User role updated' : '❌ ${ShopService.lastError ?? 'Failed to update role'}', ok);
    if (ok) setState(_refreshUsers);
  }

  void _showDeleteUserDialog(Map<String, dynamic> user) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        title: const Text('Delete User?'),
        content: Text('Delete "${_displayName(user)}" from Firestore?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(S.cancel)),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final ok = await ShopService.deleteUser(_userId(user));
              if (!mounted) return;
              _showSnack(ok ? '✅ User deleted' : '❌ ${ShopService.lastError ?? 'Delete failed'}', ok);
              if (ok) setState(_refreshUsers);
            },
            child: const Text('Delete', style: TextStyle(color: AppColors.neonRed)),
          ),
        ],
      ),
    );
  }

  void _showSnack(String message, bool success) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: success ? AppColors.neonGreen : AppColors.neonRed),
    );
  }
}
