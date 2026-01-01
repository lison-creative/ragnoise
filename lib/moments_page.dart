import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:ui';
import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class MomentsPage extends StatefulWidget {
  const MomentsPage({super.key});

  @override
  State<MomentsPage> createState() => _MomentsPageState();
}

class _MomentsPageState extends State<MomentsPage> {
  bool _isEditMode = false;

  // パスワードを直書きせず、Firestoreから取得した値を保持する
  String _fetchedAdminPass = "";

  final ImagePicker _picker = ImagePicker();
  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  List<Map<String, dynamic>> _posts = [];

  @override
  void initState() {
    super.initState();
    _initNotifications();
    _listenToMoments();
    _loadAdminSettings(); // 管理者パスワードの読み込み
  }

  // --- Firestoreから管理者設定（パスワード）を取得 ---
  Future<void> _loadAdminSettings() async {
    try {
      DocumentSnapshot settings = await _firestore.collection('settings').doc('admin').get();
      if (settings.exists) {
        setState(() {
          _fetchedAdminPass = settings.get('reserve_pass') ?? "";
        });
      }
    } catch (e) {
      debugPrint("Settings Load Error: $e");
    }
  }

  Future<void> _initNotifications() async {
    const DarwinInitializationSettings initializationSettingsIOS = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const InitializationSettings initializationSettings = InitializationSettings(iOS: initializationSettingsIOS);
    await _notificationsPlugin.initialize(initializationSettings);
  }

  Future<void> _sendPostNotification(String content) async {
    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      interruptionLevel: InterruptionLevel.active,
    );
    const NotificationDetails platformDetails = NotificationDetails(iOS: iosDetails);

    await _notificationsPlugin.show(
      DateTime.now().millisecond,
      'RAGNOISE MOMENTS',
      content.length > 30 ? '${content.substring(0, 30)}...' : content,
      platformDetails,
    );
  }

  void _listenToMoments() {
    _firestore
        .collection('moments')
        .orderBy('timestamp', descending: true)
        .snapshots()
        .listen((snapshot) {
      final List<Map<String, dynamic>> fetched = snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();

      if (mounted) {
        setState(() {
          _posts = fetched;
        });
        _saveToLocal();
        _cleanupOldPosts();
      }
    });
  }

  Future<void> _saveToLocal() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ragnoise_moments_data', jsonEncode(_posts));
  }

  Future<void> _cleanupOldPosts() async {
    if (!_isEditMode) return;

    final now = DateTime.now();
    final threshold = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 7));

    for (var post in _posts) {
      try {
        DateTime postTime = DateTime.parse(post['timestamp']);
        if (postTime.isBefore(threshold)) {
          await _firestore.collection('moments').doc(post['id']).delete();
        }
      } catch (e) {
        // timestampが解析できない場合はスキップ
      }
    }
  }

  void _deletePost(String docId) {
    HapticFeedback.vibrate();
    showDialog(
      context: context,
      builder: (context) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: AlertDialog(
          backgroundColor: Colors.black.withAlpha(200),
          shape: RoundedRectangleBorder(
              side: const BorderSide(color: Colors.redAccent, width: 0.5),
              borderRadius: BorderRadius.circular(15)
          ),
          title: const Text('DELETE POST?', style: TextStyle(color: Colors.redAccent, fontSize: 14, letterSpacing: 2)),
          content: const Text('この投稿を削除しますか？', style: TextStyle(color: Colors.white70, fontSize: 12)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCEL', style: TextStyle(color: Colors.white24))),
            TextButton(
              onPressed: () async {
                await _firestore.collection('moments').doc(docId).delete();
                Navigator.pop(context);
              },
              child: const Text('DELETE', style: TextStyle(color: Colors.redAccent)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _createPost() async {
    final TextEditingController textCtrl = TextEditingController();
    XFile? image;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
              top: 20, left: 20, right: 20
          ),
          decoration: const BoxDecoration(
            color: Color(0xFF1A1A1A),
            borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('NEW MOMENT', style: TextStyle(color: Color(0xFFD4AF37), letterSpacing: 4, fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
              if (image != null)
                Container(
                  height: 150,
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 15),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.file(File(image!.path), fit: BoxFit.cover),
                  ),
                ),
              TextField(
                controller: textCtrl,
                maxLines: 3,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: "What's happening?",
                  hintStyle: const TextStyle(color: Colors.white24),
                  filled: true,
                  fillColor: Colors.white.withAlpha(10),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
                ),
              ),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.image_outlined, color: Color(0xFFD4AF37)),
                    onPressed: () async {
                      final selected = await _picker.pickImage(source: ImageSource.gallery);
                      if (selected != null) setModalState(() => image = selected);
                    },
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () async {
                      if (textCtrl.text.isNotEmpty || image != null) {
                        await _firestore.collection('moments').add({
                          'text': textCtrl.text,
                          'imagePath': image?.path,
                          'timestamp': DateTime.now().toIso8601String(),
                          'reactions': {'👍': 0, '😭': 0, '😆': 0},
                        });
                        _sendPostNotification(textCtrl.text.isNotEmpty ? textCtrl.text : "New photo posted.");
                        if (mounted) Navigator.pop(context);
                      }
                    },
                    child: const Text('POST', style: TextStyle(color: Color(0xFFD4AF37), fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  void _showReactionMenu(int index) {
    HapticFeedback.heavyImpact();
    final String docId = _posts[index]['id'];
    showDialog(
      context: context,
      builder: (context) => Center(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.black.withAlpha(150),
              borderRadius: BorderRadius.circular(40),
              border: Border.all(color: const Color(0xFFD4AF37).withAlpha(100)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: ['👍', '😭', '😆'].map((emoji) => GestureDetector(
                onTap: () async {
                  await _firestore.collection('moments').doc(docId).update({
                    'reactions.$emoji': FieldValue.increment(1)
                  });
                  if (mounted) Navigator.pop(context);
                },
                child: Padding(
                  padding: const EdgeInsets.all(10.0),
                  child: Text(emoji, style: const TextStyle(fontSize: 30)),
                ),
              )).toList(),
            ),
          ),
        ),
      ),
    );
  }

  void _showPassDialog() {
    final TextEditingController passCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(side: const BorderSide(color: Color(0xFFD4AF37), width: 0.5), borderRadius: BorderRadius.circular(15)),
        title: const Text('ADMIN ACCESS', style: TextStyle(color: Color(0xFFD4AF37), fontSize: 12, letterSpacing: 2)),
        content: TextField(
          controller: passCtrl,
          obscureText: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFD4AF37)))),
        ),
        actions: [
          TextButton(onPressed: () {
            // Firestoreから取得した管理者共通パスワードと比較
            if (_fetchedAdminPass.isNotEmpty && passCtrl.text == _fetchedAdminPass) {
              setState(() => _isEditMode = true);
              Navigator.pop(context);
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Invalid Password"), backgroundColor: Colors.redAccent),
              );
            }
          }, child: const Text('UNLOCK', style: TextStyle(color: Color(0xFFD4AF37)))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('MOMENTS', style: TextStyle(fontSize: 14, letterSpacing: 6, fontWeight: FontWeight.w300)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios, size: 16), onPressed: () => Navigator.pop(context)),
        actions: [
          IconButton(
            icon: Icon(_isEditMode ? Icons.check_circle : Icons.edit_note, color: _isEditMode ? Colors.green : const Color(0xFFD4AF37)),
            onPressed: () => _isEditMode ? setState(() => _isEditMode = false) : _showPassDialog(),
          )
        ],
      ),
      extendBodyBehindAppBar: true,
      floatingActionButton: _isEditMode ? FloatingActionButton(
        backgroundColor: const Color(0xFFD4AF37),
        onPressed: _createPost,
        child: const Icon(Icons.add, color: Colors.black),
      ) : null,
      body: Stack(
        children: [
          Container(
              decoration: const BoxDecoration(
                  image: DecorationImage(
                      image: AssetImage('assets/image/背景1.png'),
                      fit: BoxFit.cover,
                      colorFilter: ColorFilter.mode(Colors.black87, BlendMode.darken)
                  )
              )
          ),
          SafeArea(
            child: _posts.isEmpty
                ? const Center(child: Text("No moments yet.", style: TextStyle(color: Colors.white24, letterSpacing: 2)))
                : ListView.builder(
              padding: const EdgeInsets.all(15),
              itemCount: _posts.length,
              itemBuilder: (context, index) {
                final post = _posts[index];
                DateTime time;
                try {
                  time = DateTime.parse(post['timestamp']);
                } catch (e) {
                  time = DateTime.now();
                }
                return _buildPostCard(post, index, time);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPostCard(Map<String, dynamic> post, int index, DateTime time) {
    return GestureDetector(
      onLongPress: () => _showReactionMenu(index),
      child: Container(
        margin: const EdgeInsets.only(bottom: 20),
        decoration: BoxDecoration(
          color: Colors.white.withAlpha(15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white10, width: 0.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(15.0),
              child: Row(
                children: [
                  const CircleAvatar(backgroundColor: Color(0xFFD4AF37), radius: 15, child: Icon(Icons.local_bar, size: 15, color: Colors.black)),
                  const SizedBox(width: 10),
                  const Text('RAGNOISE', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 1)),
                  const Spacer(),
                  if (_isEditMode)
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 18),
                      onPressed: () => _deletePost(post['id']),
                    ),
                  Text('${time.month}/${time.day} ${time.hour}:${time.minute.toString().padLeft(2, '0')}', style: const TextStyle(color: Colors.white24, fontSize: 10)),
                ],
              ),
            ),
            if (post['text'] != null && post['text'].isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 5),
                child: Text(post['text'], style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.5)),
              ),
            if (post['imagePath'] != null)
              Container(
                margin: const EdgeInsets.all(10),
                width: double.infinity,
                decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(color: const Color(0xFFD4AF37).withAlpha(50), width: 0.5)
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(15),
                  child: post['imagePath'].startsWith('http')
                      ? Image.network(post['imagePath'], fit: BoxFit.cover)
                      : Image.file(File(post['imagePath']), fit: BoxFit.cover),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(15.0),
              child: Wrap(
                spacing: 10,
                children: (post['reactions'] as Map<String, dynamic>).entries.where((e) => e.value > 0).map((e) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                      color: const Color(0xFFD4AF37).withAlpha(40),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFD4AF37).withAlpha(100), width: 0.5)
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(e.key, style: const TextStyle(fontSize: 12)),
                      const SizedBox(width: 6),
                      Text('${e.value}', style: const TextStyle(color: Color(0xFFD4AF37), fontSize: 11, fontWeight: FontWeight.bold)),
                    ],
                  ),
                )).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}