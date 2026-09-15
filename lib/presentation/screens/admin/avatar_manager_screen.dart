import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/constants/app_colors.dart';
import '../../../data/services/image_upload_service.dart';
import '../../../data/services/shop_service.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/cached_avatar.dart';
import '../../../l10n/app_strings.dart';

/// Admin screen to manage Firestore avatars.
class AvatarManagerScreen extends StatefulWidget {
  final String? initialAction;

  const AvatarManagerScreen({super.key, this.initialAction});

  @override
  State<AvatarManagerScreen> createState() => _AvatarManagerScreenState();
}

class _AdminAvatar {
  final String id;
  final String name;
  final String category;
  final String imageUrl;
  final bool isPremium;
  final int price;

  const _AdminAvatar({
    required this.id,
    required this.name,
    required this.category,
    required this.imageUrl,
    required this.isPremium,
    required this.price,
  });

  factory _AdminAvatar.fromMap(Map<String, dynamic> data) {
    return _AdminAvatar(
      id: (data['id'] ?? '').toString(),
      name: (data['name'] ?? 'New Avatar').toString(),
      category: (data['category'] ?? 'male').toString(),
      imageUrl: (data['image_url'] ?? data['avatar_url'] ?? '').toString(),
      isPremium: data['is_premium'] == true || data['category'] == 'premium',
      price: (data['price'] as num?)?.toInt() ?? 0,
    );
  }
}

class _AvatarManagerScreenState extends State<AvatarManagerScreen> {
  String _selectedCategory = 'all';
  late Future<List<_AdminAvatar>> _avatarsFuture;

  @override
  void initState() {
    super.initState();
    _refreshAvatars();
    if (widget.initialAction == 'add') {
      WidgetsBinding.instance.addPostFrameCallback((_) => _showAddAvatarSheet());
    }
  }

  void _refreshAvatars() {
    _avatarsFuture = _loadAvatars();
  }

  Future<List<_AdminAvatar>> _loadAvatars() async {
    final rows = await ShopService.getAvatars(forceRefresh: true); // admin sees live data
    return rows.map(_AdminAvatar.fromMap).toList();
  }

  List<_AdminAvatar> _filterAvatars(List<_AdminAvatar> avatars) {
    if (_selectedCategory == 'all') return avatars;
    if (_selectedCategory == 'premium') {
      return avatars.where((avatar) => avatar.isPremium).toList();
    }
    return avatars.where((avatar) => avatar.category == _selectedCategory).toList();
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
        title: const Text('Avatar Manager', style: TextStyle(color: AppColors.textPrimary, fontSize: 20, fontWeight: FontWeight.w900)),
        actions: [
          IconButton(icon: const Icon(Icons.refresh_rounded, color: AppColors.neonCyan), onPressed: () => setState(_refreshAvatars)),
          IconButton(
            icon: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(color: AppColors.neonPink.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.add_rounded, color: AppColors.neonPink, size: 20),
            ),
            onPressed: _showAddAvatarSheet,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: FutureBuilder<List<_AdminAvatar>>(
        future: _avatarsFuture,
        builder: (context, snapshot) {
          final avatars = snapshot.data ?? const <_AdminAvatar>[];
          final filteredAvatars = _filterAvatars(avatars);
          final isLoading = snapshot.connectionState == ConnectionState.waiting;

          return Column(
            children: [
              _buildCategoryFilter(),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Text(isLoading ? 'Loading avatars...' : '${filteredAvatars.length} avatars', style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: _showAddAvatarSheet,
                      icon: const Icon(Icons.add_rounded, size: 16),
                      label: const Text('Add Avatar'),
                      style: TextButton.styleFrom(foregroundColor: AppColors.neonPink),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: isLoading
                    ? const Center(child: CircularProgressIndicator(color: AppColors.neonPink))
                    : snapshot.hasError
                        ? _buildEmptyState('Failed to load avatars', detail: ShopService.lastError)
                        : filteredAvatars.isEmpty
                            ? _buildEmptyState('No Firestore avatars found', detail: ShopService.lastError)
                            : _buildAvatarGrid(filteredAvatars),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddAvatarSheet,
        backgroundColor: AppColors.neonPink,
        icon: const Icon(Icons.add_rounded, color: Colors.white),
        label: const Text('Add Avatar', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
      ),
    );
  }

  Widget _buildCategoryFilter() {
    final categories = [
      {'id': 'all', 'label': '🏪 All'},
      {'id': 'male', 'label': '👦 Male'},
      {'id': 'female', 'label': '👧 Female'},
      {'id': 'premium', 'label': '👑 Premium'},
    ];
    return SizedBox(
      height: 40,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        itemCount: categories.length,
        itemBuilder: (context, index) {
          final cat = categories[index];
          final isSelected = _selectedCategory == cat['id'];
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: GestureDetector(
              onTap: () => setState(() => _selectedCategory = cat['id']!),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.neonPurple.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: isSelected ? AppColors.neonPurple.withValues(alpha: 0.5) : Colors.white.withValues(alpha: 0.1)),
                ),
                child: Text(cat['label']!, style: TextStyle(fontSize: 11, fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600, color: isSelected ? AppColors.neonPurple : AppColors.textSecondary)),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildAvatarGrid(List<_AdminAvatar> avatars) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 0.85),
      itemCount: avatars.length,
      itemBuilder: (context, index) => _buildAvatarCard(avatars[index]),
    );
  }

  Widget _buildAvatarCard(_AdminAvatar avatar) {
    return GlassCard(
      borderRadius: 16,
      borderColor: avatar.isPremium ? AppColors.neonGold.withValues(alpha: 0.3) : Colors.white.withValues(alpha: 0.1),
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: avatar.imageUrl.isNotEmpty
                ? CachedAvatar(
                    url: avatar.imageUrl,
                    fit: BoxFit.cover,
                    width: double.infinity,
                    height: double.infinity,
                    progressColor: AppColors.neonPink,
                    fallbackBuilder: (_) => _avatarPlaceholder(),
                  )
                : _avatarPlaceholder(),
          ),
          if (avatar.isPremium)
            Positioned(
              top: 8,
              left: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: AppColors.neonGold.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(6), border: Border.all(color: AppColors.neonGold.withValues(alpha: 0.5))),
                child: Text('👑 ${avatar.price}', style: const TextStyle(color: AppColors.neonGold, fontSize: 8, fontWeight: FontWeight.w900)),
              ),
            ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(16), bottomRight: Radius.circular(16)), gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Colors.black.withValues(alpha: 0.8)])),
              child: Row(children: [
                Expanded(child: Text(avatar.name, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis)),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert_rounded, color: Colors.white, size: 16),
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'edit', child: Row(children: [Icon(Icons.edit_rounded, size: 14), SizedBox(width: 6), Text('Edit', style: TextStyle(fontSize: 12))])),
                    PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete_rounded, size: 14, color: AppColors.neonRed), SizedBox(width: 6), Text('Delete', style: TextStyle(fontSize: 12, color: AppColors.neonRed))])),
                  ],
                  onSelected: (value) {
                    if (value == 'edit') _showEditAvatarSheet(avatar);
                    if (value == 'delete') _showDeleteDialog(avatar);
                  },
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _avatarPlaceholder() {
    return Container(color: Colors.white.withValues(alpha: 0.05), child: const Center(child: Icon(Icons.person_rounded, color: AppColors.textMuted, size: 44)));
  }

  Widget _buildEmptyState(String message, {String? detail}) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.face_retouching_off_rounded, size: 56, color: AppColors.textMuted.withValues(alpha: 0.35)),
          const SizedBox(height: 14),
          Text(message, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(
            detail?.isNotEmpty == true ? detail! : 'Use Add Avatar to create Firestore data',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Future<void> _showAddAvatarSheet() async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const _AddEditAvatarSheet(),
    );
    if (changed == true && mounted) setState(_refreshAvatars);
  }

  Future<void> _showEditAvatarSheet(_AdminAvatar avatar) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _AddEditAvatarSheet(avatar: avatar),
    );
    if (changed == true && mounted) setState(_refreshAvatars);
  }

  void _showDeleteDialog(_AdminAvatar avatar) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        title: const Text('Delete Avatar?'),
        content: Text('Delete "${avatar.name}" from Firestore?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(S.cancel)),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final success = await ShopService.deleteAvatar(avatar.id);
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(success ? '✅ Avatar deleted' : '❌ ${ShopService.lastError ?? 'Delete failed'}'), backgroundColor: success ? AppColors.neonGreen : AppColors.neonRed));
              if (success) setState(_refreshAvatars);
            },
            child: const Text('Delete', style: TextStyle(color: AppColors.neonRed)),
          ),
        ],
      ),
    );
  }
}

class _AddEditAvatarSheet extends StatefulWidget {
  final _AdminAvatar? avatar;

  const _AddEditAvatarSheet({this.avatar});

  @override
  State<_AddEditAvatarSheet> createState() => _AddEditAvatarSheetState();
}

class _AddEditAvatarSheetState extends State<_AddEditAvatarSheet> {
  late final TextEditingController _nameController;
  late final TextEditingController _priceController;
  String _selectedCategory = 'male';
  bool _isPremium = false;
  File? _selectedImage;
  String? _uploadedImageUrl;
  bool _isUploading = false;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.avatar?.name ?? '');
    _priceController = TextEditingController(text: widget.avatar?.price.toString() ?? '50');
    _selectedCategory = widget.avatar?.category ?? 'male';
    _isPremium = widget.avatar?.isPremium ?? false;
    _uploadedImageUrl = widget.avatar?.imageUrl.isNotEmpty == true ? widget.avatar!.imageUrl : null;
  }

  Future<void> _pickImage() async {
    try {
      final XFile? image = await _picker.pickImage(source: ImageSource.gallery, maxWidth: 1024, maxHeight: 1024, imageQuality: 90);
      if (image != null) {
        setState(() { _selectedImage = File(image.path); _isUploading = true; });
        final url = await ImageUploadService.uploadAvatar(_selectedImage!);
        if (url != null) {
          setState(() { _uploadedImageUrl = url; _isUploading = false; });
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ Avatar image uploaded!'), backgroundColor: AppColors.neonGreen));
        } else {
          setState(() => _isUploading = false);
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('❌ Upload failed. Try again.'), backgroundColor: AppColors.neonRed));
        }
      }
    } catch (e) {
      setState(() => _isUploading = false);
    }
  }

  @override
  void dispose() { _nameController.dispose(); _priceController.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      decoration: const BoxDecoration(color: AppColors.surfaceElevated, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(widget.avatar == null ? 'Add New Avatar' : 'Edit Avatar', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: AppColors.textPrimary)),
            const Spacer(),
            IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(context)),
          ]),
          const SizedBox(height: 20),
          _buildImageUpload(),
          const SizedBox(height: 20),
          TextField(controller: _nameController, style: const TextStyle(color: AppColors.textPrimary),
            decoration: InputDecoration(labelText: 'Avatar Name', labelStyle: const TextStyle(color: AppColors.textSecondary), hintText: 'e.g., Blue Hoodie Boy',
              prefixIcon: const Icon(Icons.face_rounded, color: AppColors.neonCyan), filled: true, fillColor: Colors.white.withValues(alpha: 0.05),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1))))),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(initialValue: _selectedCategory, style: const TextStyle(color: AppColors.textPrimary),
            decoration: InputDecoration(labelText: 'Category', labelStyle: const TextStyle(color: AppColors.textSecondary),
              prefixIcon: const Icon(Icons.category_rounded, color: AppColors.neonCyan), filled: true, fillColor: Colors.white.withValues(alpha: 0.05),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)))),
            dropdownColor: AppColors.surfaceElevated,
            items: [const DropdownMenuItem(value: 'male', child: Text('👦 Male')), const DropdownMenuItem(value: 'female', child: Text('👧 Female')), DropdownMenuItem(value: 'premium', child: Text(S.avatarPremium))],
            onChanged: (value) => setState(() { _selectedCategory = value!; if (value == 'premium') _isPremium = true; })),
          const SizedBox(height: 16),
          SwitchListTile(title: const Text('Premium Avatar', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
            subtitle: const Text('Requires purchase in shop', style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
            value: _isPremium, onChanged: (value) => setState(() => _isPremium = value), activeThumbColor: AppColors.neonGold),
          if (_isPremium) ...[
            const SizedBox(height: 16),
            TextField(controller: _priceController, keyboardType: TextInputType.number, style: const TextStyle(color: AppColors.textPrimary),
              decoration: InputDecoration(labelText: 'Price (Gems)', labelStyle: const TextStyle(color: AppColors.textSecondary), hintText: '50',
                prefixIcon: const Icon(Icons.diamond_rounded, color: AppColors.neonPurple), filled: true, fillColor: Colors.white.withValues(alpha: 0.05),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1))))),
          ],
          const SizedBox(height: 24),
          SizedBox(width: double.infinity, child: ElevatedButton(onPressed: _isUploading ? null : _saveAvatar,
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.neonPink, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
            child: Text(widget.avatar == null ? 'Add Avatar' : 'Update Avatar', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white)))),
        ]),
      ),
    );
  }

  Widget _buildImageUpload() {
    final hasRemoteImage = _uploadedImageUrl != null && _uploadedImageUrl!.isNotEmpty;
    return Container(width: double.infinity, padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.03), borderRadius: BorderRadius.circular(16),
        border: Border.all(color: hasRemoteImage ? AppColors.neonGreen.withValues(alpha: 0.5) : AppColors.neonPink.withValues(alpha: 0.2))),
      child: Column(children: [
        if (_selectedImage != null)
          ClipRRect(borderRadius: BorderRadius.circular(16), child: Image.file(_selectedImage!, height: 160, width: 160, fit: BoxFit.cover))
        else if (hasRemoteImage)
          ClipRRect(borderRadius: BorderRadius.circular(16), child: Image.network(_uploadedImageUrl!, height: 160, width: 160, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _uploadPlaceholder()))
        else
          _uploadPlaceholder(),
        const SizedBox(height: 12),
        if (_isUploading) const Column(children: [CircularProgressIndicator(color: AppColors.neonPink), SizedBox(height: 8), Text('Uploading to ImageBB...', style: TextStyle(color: AppColors.textSecondary, fontSize: 12))])
        else ElevatedButton.icon(onPressed: _pickImage, icon: const Icon(Icons.upload_rounded), label: Text(hasRemoteImage ? 'Change Image' : 'Choose from Gallery'),
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.neonPink, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12))),
        if (hasRemoteImage) ...[
          const SizedBox(height: 8),
          Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(8)),
            child: Row(children: [const Icon(Icons.link_rounded, color: AppColors.neonPink, size: 14), const SizedBox(width: 6),
              Expanded(child: Text(_uploadedImageUrl!, style: const TextStyle(color: AppColors.neonPink, fontSize: 10), maxLines: 1, overflow: TextOverflow.ellipsis))])),
        ],
      ]),
    );
  }

  Widget _uploadPlaceholder() {
    return Container(width: 120, height: 120, decoration: BoxDecoration(color: AppColors.neonPink.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.neonPink.withValues(alpha: 0.3))), child: Icon(Icons.add_photo_alternate_rounded, size: 48, color: AppColors.neonPink.withValues(alpha: 0.5)));
  }

  void _saveAvatar() async {
    final name = _nameController.text.trim();
    final imageUrl = _uploadedImageUrl ?? '';
    final price = int.tryParse(_priceController.text.trim()) ?? 0;
    if (name.isEmpty) {
      _showError('Avatar name is required.');
      return;
    }
    if (imageUrl.isEmpty) {
      _showError('Please upload an avatar image before saving.');
      return;
    }
    if (_isPremium && price < 0) {
      _showError('Price must be 0 or more.');
      return;
    }

    final avatarData = {
      'id': widget.avatar?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
      'name': name,
      'category': _selectedCategory,
      'image_url': imageUrl,
      'is_premium': _isPremium,
      'price': _isPremium ? price : 0,
      'is_active': true,
      'created_at': DateTime.now().toIso8601String(),
    };

    final success = await ShopService.saveAvatar(avatarData);

    if (mounted) {
      Navigator.pop(context, success);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? (widget.avatar == null ? '✅ Avatar added!' : '✅ Avatar updated!') : '❌ ${ShopService.lastError ?? 'Failed to save. Try again.'}'),
          backgroundColor: success ? AppColors.neonPink : AppColors.neonRed,
        ),
      );
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('❌ $message'), backgroundColor: AppColors.neonRed),
    );
  }
}
