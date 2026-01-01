import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:ui';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key});

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  DateTime _selectedDate = DateTime.now();
  bool _isEditMode = false;

  // 【修正】パスワードを直書きせず、Firestoreから取得した値を保持する
  String _fetchedAdminPass = "";

  // Firestoreのインスタンス
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // 保存されるスケジュールデータ (key: "yyyy-MM-dd")
  Map<String, String> _scheduleData = {};

  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();

  final Map<String, Color> _statusColors = {
    "イベント": const Color(0xFFD4AF37),
    "おやすみ": const Color(0xFFFF5252),
    "一部貸切": const Color(0xFF448AFF),
    "営業時間変更": const Color(0xFF69F0AE),
  };

  @override
  void initState() {
    super.initState();
    _initNotifications();
    _listenToSchedule();
    _loadAndCleanData();
    _loadAdminSettings(); // 管理者パスワードの読み込み
  }

  // --- Firestoreから管理者設定（パスワード）を取得 ---
  Future<void> _loadAdminSettings() async {
    try {
      DocumentSnapshot settings = await _firestore.collection('settings').doc('admin').get();
      if (settings.exists) {
        setState(() {
          // 他のページと共通のフィールドを参照
          _fetchedAdminPass = settings.get('reserve_pass') ?? "";
        });
      }
    } catch (e) {
      debugPrint("Settings Load Error: $e");
    }
  }

  // --- 通知の初期設定 ---
  Future<void> _initNotifications() async {
    const DarwinInitializationSettings initializationSettingsIOS = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const InitializationSettings initializationSettings = InitializationSettings(iOS: initializationSettingsIOS);
    await _notificationsPlugin.initialize(initializationSettings);
  }

  // --- 通知を送る機能 ---
  Future<void> _sendNotification(String title, String body) async {
    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentSound: true,
      presentBadge: true,
    );
    const NotificationDetails platformDetails = NotificationDetails(iOS: iosDetails);
    await _notificationsPlugin.show(0, title, body, platformDetails);
  }

  // --- Firestoreからデータをリアルタイム取得 ---
  void _listenToSchedule() {
    _firestore.collection('calendar').snapshots().listen((snapshot) {
      final Map<String, String> newData = {};
      for (var doc in snapshot.docs) {
        if (doc.data().containsKey('status')) {
          newData[doc.id] = doc.data()['status'] as String;
        }
      }
      if (mounted) {
        setState(() {
          _scheduleData = newData;
        });
        _saveDataLocal();
      }
    });
  }

  // --- データの読み込みと1週間経過データの自動削除 ---
  Future<void> _loadAndCleanData() async {
    final prefs = await SharedPreferences.getInstance();
    final String? jsonStr = prefs.getString('ragnoise_calendar_data');

    if (jsonStr != null) {
      setState(() {
        _scheduleData = Map<String, String>.from(jsonDecode(jsonStr));
      });
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final threshold = today.subtract(const Duration(days: 7));

    bool isChanged = false;
    List<String> keysToRemove = [];

    _scheduleData.forEach((key, value) {
      try {
        DateTime date = DateTime.parse(key);
        if (date.isBefore(threshold)) {
          keysToRemove.add(key);
          isChanged = true;
        }
      } catch (e) {}
    });

    for (var key in keysToRemove) {
      _scheduleData.remove(key);
      if (_isEditMode) {
        await _firestore.collection('calendar').doc(key).delete();
      }
    }

    if (isChanged) {
      _saveDataLocal();
    }
  }

  // --- データの保存処理 ---
  Future<void> _saveAllData(String dateKey, String? status) async {
    try {
      if (status == null) {
        await _firestore.collection('calendar').doc(dateKey).delete();
      } else {
        await _firestore.collection('calendar').doc(dateKey).set({
          'status': status,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      debugPrint("Firestore Error: $e");
    }
    _saveDataLocal();
  }

  Future<void> _saveDataLocal() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ragnoise_calendar_data', jsonEncode(_scheduleData));
  }

  void _showPassDialog() {
    final TextEditingController passCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: AlertDialog(
          backgroundColor: Colors.black.withAlpha(200),
          shape: RoundedRectangleBorder(
              side: const BorderSide(color: Color(0xFFD4AF37), width: 0.5),
              borderRadius: BorderRadius.circular(15)
          ),
          title: const Text('ADMIN ACCESS', style: TextStyle(color: Color(0xFFD4AF37), fontSize: 14, letterSpacing: 4)),
          content: TextField(
            controller: passCtrl,
            obscureText: true,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              hintText: 'Password',
              hintStyle: TextStyle(color: Colors.white24),
              enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFD4AF37))),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCEL', style: TextStyle(color: Colors.white24))),
            TextButton(
              onPressed: () {
                // Firestoreから取得した共通パスワードで照合
                if (_fetchedAdminPass.isNotEmpty && passCtrl.text == _fetchedAdminPass) {
                  setState(() => _isEditMode = true);
                  Navigator.pop(context);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Invalid Password"), backgroundColor: Colors.redAccent),
                  );
                }
              },
              child: const Text('LOGIN', style: TextStyle(color: Color(0xFFD4AF37))),
            ),
          ],
        ),
      ),
    );
  }

  void _editDayStatus(String dateKey) {
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: const Color(0xFF121212),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
          border: Border.all(color: const Color(0xFFD4AF37).withAlpha(100), width: 0.5),
        ),
        child: Wrap(
          children: [
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 10),
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const Padding(
              padding: EdgeInsets.all(25.0),
              child: Text('SELECT STATUS', style: TextStyle(color: Color(0xFFD4AF37), fontSize: 12, letterSpacing: 2)),
            ),
            ..._statusColors.entries.map((e) => ListTile(
              leading: Icon(Icons.circle, color: e.value, size: 16),
              title: Text(e.key, style: const TextStyle(color: Colors.white, fontSize: 14)),
              onTap: () {
                setState(() => _scheduleData[dateKey] = e.key);
                _saveAllData(dateKey, e.key);
                _sendNotification("SCHEDULE UPDATED", "$dateKey は 「${e.key}」 です");
                Navigator.pop(context);
              },
            )),
            ListTile(
              leading: const Icon(Icons.refresh, color: Colors.white24, size: 16),
              title: const Text('通常営業に戻す', style: TextStyle(color: Colors.white54, fontSize: 14)),
              onTap: () {
                setState(() => _scheduleData.remove(dateKey));
                _saveAllData(dateKey, null);
                Navigator.pop(context);
              },
            ),
            const SizedBox(height: 60),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('SCHEDULE', style: TextStyle(fontSize: 13, letterSpacing: 5, fontWeight: FontWeight.w300)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios, size: 16), onPressed: () => Navigator.pop(context)),
        actions: [
          IconButton(
            icon: Icon(_isEditMode ? Icons.check_circle : Icons.tune,
                color: _isEditMode ? Colors.green : const Color(0xFFD4AF37), size: 20),
            onPressed: () => _isEditMode ? setState(() => _isEditMode = false) : _showPassDialog(),
          )
        ],
      ),
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              image: DecorationImage(
                image: AssetImage('assets/image/背景1.png'),
                fit: BoxFit.cover,
                colorFilter: ColorFilter.mode(Colors.black87, BlendMode.darken),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                _buildWeeklyBar(),
                const SizedBox(height: 30),
                Expanded(child: _buildDateDetail()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWeeklyBar() {
    return SizedBox(
      height: 100,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        itemCount: 21,
        itemBuilder: (context, index) {
          final now = DateTime.now();
          final startDate = now.subtract(Duration(days: now.weekday - 1 + 7));
          final date = startDate.add(Duration(days: index));

          final isSelected = date.day == _selectedDate.day && date.month == _selectedDate.month && date.year == _selectedDate.year;
          final dateKey = "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
          final hasStatus = _scheduleData.containsKey(dateKey);

          return GestureDetector(
            onTap: () => setState(() => _selectedDate = date),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: 55,
              margin: const EdgeInsets.symmetric(horizontal: 5, vertical: 10),
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFFD4AF37).withAlpha(40) : Colors.white.withAlpha(5),
                borderRadius: BorderRadius.circular(15),
                border: Border.all(
                    color: isSelected ? const Color(0xFFD4AF37) : Colors.white10,
                    width: isSelected ? 1.5 : 0.5
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'][date.weekday - 1],
                    style: TextStyle(fontSize: 9, color: isSelected ? const Color(0xFFD4AF37) : Colors.white38),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '${date.day}',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w300,
                        color: isSelected ? Colors.white : Colors.white70
                    ),
                  ),
                  if (hasStatus)
                    Container(
                      margin: const EdgeInsets.only(top: 4),
                      width: 4,
                      height: 4,
                      decoration: BoxDecoration(color: _statusColors[_scheduleData[dateKey]], shape: BoxShape.circle),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildDateDetail() {
    final dateKey = "${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}";
    final status = _scheduleData[dateKey];
    final color = status != null ? _statusColors[status]! : const Color(0xFFD4AF37);

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Padding(
        padding: const EdgeInsets.all(25.0),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('${_selectedDate.month} / ${_selectedDate.day}',
                    style: const TextStyle(fontSize: 48, fontWeight: FontWeight.w100, letterSpacing: -2, color: Colors.white)),
                const SizedBox(width: 15),
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ['MONDAY', 'TUESDAY', 'WEDNESDAY', 'THURSDAY', 'FRIDAY', 'SATURDAY', 'SUNDAY'][_selectedDate.weekday - 1],
                        style: const TextStyle(letterSpacing: 2, color: Colors.white38, fontSize: 12),
                      ),
                      Text('${_selectedDate.year}', style: const TextStyle(letterSpacing: 4, color: Color(0xFFD4AF37), fontSize: 10)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 40),
            GestureDetector(
              onTap: _isEditMode ? () => _editDayStatus(dateKey) : null,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(25),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 400),
                    width: double.infinity,
                    padding: const EdgeInsets.all(35),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [color.withAlpha(60), Colors.black.withAlpha(150)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(25),
                      border: Border.all(color: color.withAlpha(180), width: 0.8),
                      boxShadow: [
                        BoxShadow(color: color.withAlpha(40), blurRadius: 25, spreadRadius: 1)
                      ],
                    ),
                    child: Column(
                      children: [
                        Icon(status != null ? Icons.stars : Icons.local_bar, color: color, size: 48),
                        const SizedBox(height: 25),
                        Text(
                          status ?? "通常営業",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 26,
                              color: color,
                              letterSpacing: 6,
                              fontWeight: FontWeight.bold,
                              shadows: [Shadow(color: Colors.black.withAlpha(100), blurRadius: 10)]
                          ),
                        ),
                        const SizedBox(height: 15),
                        const Divider(color: Colors.white10, thickness: 0.5),
                        const SizedBox(height: 15),
                        Text(
                          status != null ? "SPECIAL SCHEDULE" : "OPEN 19:00 - CLOSE 03:00",
                          style: const TextStyle(color: Colors.white54, fontSize: 11, letterSpacing: 2),
                        ),
                        if (_isEditMode)
                          Container(
                            margin: const EdgeInsets.only(top: 25),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                                border: Border.all(color: Colors.green.withAlpha(200)),
                                borderRadius: BorderRadius.circular(20),
                                color: Colors.green.withAlpha(30)
                            ),
                            child: const Text("EDIT MODE : TAP TO CHANGE", style: TextStyle(color: Colors.green, fontSize: 10, fontWeight: FontWeight.bold)),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 60),
            const Opacity(
              opacity: 0.3,
              child: Text(
                "RAGNOISE - THE ART OF NOISE AND SILENCE",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontSize: 9, letterSpacing: 2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}