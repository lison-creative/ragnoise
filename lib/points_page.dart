import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class PointsPage extends StatefulWidget {
  const PointsPage({super.key});

  @override
  State<PointsPage> createState() => _PointsPageState();
}

class _PointsPageState extends State<PointsPage> {
  int _currentPoints = 0;
  int _totalPoints = 0;
  String _lastCheckInDate = "";
  bool _isLoading = true;

  // ユーザープロファイル情報
  String _displayName = "";
  String _ageGroup = "";
  String _gender = "";

  // Firestoreから取得したチェックイン用パスワードを保持
  String _fetchedCheckInPass = "";

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    _initializeUserAndData();
    _loadAdminSettings();
  }

  // --- Firestoreからチェックイン用パスワードを取得 ---
  Future<void> _loadAdminSettings() async {
    try {
      DocumentSnapshot settings = await _firestore.collection('settings').doc('admin').get();
      if (settings.exists) {
        setState(() {
          _fetchedCheckInPass = settings.get('checkin_pass') ?? "";
        });
      }
    } catch (e) {
      debugPrint("Settings Load Error: $e");
    }
  }

  Future<void> _initializeUserAndData() async {
    setState(() => _isLoading = true);
    await _loadFromLocal();

    try {
      UserCredential userCredential = await _auth.signInAnonymously();
      String uid = userCredential.user!.uid;

      DocumentSnapshot userDoc = await _firestore.collection('users').doc(uid).get();

      if (userDoc.exists) {
        final data = userDoc.data() as Map<String, dynamic>;
        setState(() {
          _currentPoints = data['current_points'] ?? 0;
          _totalPoints = data['total_points'] ?? 0;
          _lastCheckInDate = data['last_date'] ?? "";
          _displayName = data['display_name'] ?? "";
          _ageGroup = data['age_group'] ?? "";
          _gender = data['gender'] ?? "";
        });

        // プロファイルが未設定なら登録ダイアログを表示
        if (_ageGroup.isEmpty || _gender.isEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _showProfileRegistration());
        }
      } else {
        // 新規作成
        await _firestore.collection('users').doc(uid).set({
          'current_points': _currentPoints,
          'total_points': _totalPoints,
          'last_date': _lastCheckInDate,
          'display_name': _displayName,
          'age_group': _ageGroup,
          'gender': _gender,
          'created_at': FieldValue.serverTimestamp(),
        });
        WidgetsBinding.instance.addPostFrameCallback((_) => _showProfileRegistration());
      }
      await _saveToLocal();
    } catch (e) {
      debugPrint("Sync Error: $e");
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // --- ユーザープロファイル登録シート ---
  void _showProfileRegistration() {
    String tempAge = _ageGroup.isNotEmpty ? _ageGroup : "20s";
    String tempGender = _gender.isNotEmpty ? _gender : "Male";
    final TextEditingController nameCtrl = TextEditingController(text: _displayName);

    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          padding: const EdgeInsets.all(25),
          decoration: const BoxDecoration(
            color: Color(0xFF1A1A1A),
            borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text("USER PROFILE", style: TextStyle(color: Color(0xFFD4AF37), letterSpacing: 4, fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                const Text("分析とサービス向上のため、属性をご登録ください", style: TextStyle(color: Colors.white38, fontSize: 10)),
                const SizedBox(height: 25),
                TextField(
                  controller: nameCtrl,
                  style: const TextStyle(color: Colors.white),
                  decoration: _inputDecoration("Nickname"),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: _buildModalDropdown("AGE", tempAge, ["10s", "20s", "30s", "40s", "50s", "60+"], (v) {
                        setModalState(() => tempAge = v!);
                      }),
                    ),
                    const SizedBox(width: 15),
                    Expanded(
                      child: _buildModalDropdown("GENDER", tempGender, ["Male", "Female", "Other"], (v) {
                        setModalState(() => tempGender = v!);
                      }),
                    ),
                  ],
                ),
                const SizedBox(height: 30),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: () async {
                      if (nameCtrl.text.isNotEmpty) {
                        setState(() {
                          _displayName = nameCtrl.text;
                          _ageGroup = tempAge;
                          _gender = tempGender;
                        });
                        await _syncData();
                        Navigator.pop(context);
                      }
                    },
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD4AF37)),
                    child: const Text("SAVE PROFILE", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(height: 10),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildModalDropdown(String label, String value, List<String> items, ValueChanged<String?> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Color(0xFFD4AF37), fontSize: 10, letterSpacing: 2)),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: value,
          dropdownColor: const Color(0xFF1A1A1A),
          style: const TextStyle(color: Colors.white, fontSize: 14),
          decoration: _inputDecoration(""),
          items: items.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
          onChanged: onChanged,
        ),
      ],
    );
  }

  Future<void> _loadFromLocal() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _currentPoints = prefs.getInt('ragnoise_current_points') ?? 0;
      _totalPoints = prefs.getInt('ragnoise_total_points') ?? 0;
      _lastCheckInDate = prefs.getString('ragnoise_last_date') ?? "";
      _displayName = prefs.getString('ragnoise_user_name') ?? "";
      _ageGroup = prefs.getString('ragnoise_user_age') ?? "";
      _gender = prefs.getString('ragnoise_user_gender') ?? "";
    });
  }

  Future<void> _syncData() async {
    String? uid = _auth.currentUser?.uid;
    await _saveToLocal();

    if (uid != null) {
      try {
        await _firestore.collection('users').doc(uid).update({
          'current_points': _currentPoints,
          'total_points': _totalPoints,
          'last_date': _lastCheckInDate,
          'display_name': _displayName,
          'age_group': _ageGroup,
          'gender': _gender,
          'updated_at': FieldValue.serverTimestamp(),
        });
      } catch (e) {
        debugPrint("Cloud Update Error: $e");
      }
    }
  }

  Future<void> _saveToLocal() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('ragnoise_current_points', _currentPoints);
    await prefs.setInt('ragnoise_total_points', _totalPoints);
    await prefs.setString('ragnoise_last_date', _lastCheckInDate);
    await prefs.setString('ragnoise_user_name', _displayName);
    await prefs.setString('ragnoise_user_age', _ageGroup);
    await prefs.setString('ragnoise_user_gender', _gender);
  }

  String _getBusinessDate() {
    final now = DateTime.now();
    final businessTime = now.subtract(const Duration(hours: 5));
    return "${businessTime.year}-${businessTime.month}-${businessTime.day}";
  }

  String _getLevel() {
    if (_totalPoints >= 150) return "常連 Lv.MAX";
    if (_totalPoints >= 100) return "常連 Lv.2";
    if (_totalPoints >= 80) return "常連";
    if (_totalPoints >= 50) return "GOLD";
    if (_totalPoints >= 30) return "SILVER";
    if (_totalPoints >= 10) return "BRONZE";
    return "VISITOR";
  }

  void _openCheckInDialog() {
    final businessDate = _getBusinessDate();

    if (_lastCheckInDate == businessDate) {
      _showMsg("本日のポイントは取得済みです。");
      return;
    }

    final TextEditingController _passController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xFFD4AF37), width: 1),
        ),
        title: const Text(
          "STAFF ONLY",
          textAlign: TextAlign.center,
          style: TextStyle(color: Color(0xFFD4AF37), fontSize: 14, letterSpacing: 2),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "店員がパスワードを入力します",
              style: TextStyle(color: Colors.white70, fontSize: 11),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _passController,
              autofocus: true,
              keyboardType: TextInputType.number,
              obscureText: true,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 24, letterSpacing: 10),
              decoration: const InputDecoration(
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white10)),
                focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFD4AF37))),
              ),
              onChanged: (value) {
                if (_fetchedCheckInPass.isNotEmpty && value == _fetchedCheckInPass) {
                  Navigator.pop(context);
                  _addPoint(businessDate);
                }
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("CANCEL", style: TextStyle(color: Colors.white38)),
          ),
        ],
      ),
    );
  }

  // --- 修正ポイント: AI分析用の訪問ログを詳細に記録 ---
  Future<void> _recordVisitLog() async {
    String? uid = _auth.currentUser?.uid;
    if (uid == null) return;

    try {
      // AI分析画面が読みに行くコレクション 'visit_logs' に保存
      await _firestore.collection('visit_logs').add({
        'user_id': uid,
        // ↓これが月別・時間帯分析の要になります
        'timestamp': FieldValue.serverTimestamp(),
        'ageGroup': _ageGroup, // 分析画面の変数名に合わせて調整
        'gender': _gender,
        'points_added': 1,
        'user_name': _displayName,
      });
      debugPrint("Visit Log Recorded with Timestamp");
    } catch (e) {
      debugPrint("Visit Log Error: $e");
    }
  }

  void _addPoint(String businessDate) {
    setState(() {
      if (_currentPoints < 10) _currentPoints++;
      _totalPoints++;
      _lastCheckInDate = businessDate;
    });
    _syncData();
    _recordVisitLog(); // ここで詳細なログ（timestamp付き）を記録
    _showMsg("1 POINT GET!");
  }

  void _useService(int cost) {
    if (_currentPoints < cost) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(side: const BorderSide(color: Color(0xFFD4AF37))),
        title: const Text("SERVICE CODE", style: TextStyle(color: Color(0xFFD4AF37), fontSize: 14)),
        content: const Text("店長にこの画面を提示してください。\n特典を利用しますか？", style: TextStyle(color: Colors.white70, fontSize: 12)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("CANCEL")),
          TextButton(
            onPressed: () {
              setState(() {
                _currentPoints -= cost;
              });
              _syncData();
              Navigator.pop(context);
              _showMsg("特典を利用しました。");
            },
            child: const Text("USE", style: TextStyle(color: Color(0xFFD4AF37))),
          ),
        ],
      ),
    );
  }

  void _showMsg(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(text),
          backgroundColor: const Color(0xFFD4AF37),
          behavior: SnackBarBehavior.floating
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Colors.white24, fontSize: 13),
      filled: true,
      fillColor: Colors.white.withAlpha(10),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading && _totalPoints == 0) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Color(0xFFD4AF37))),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('VISIT POINTS', style: TextStyle(fontSize: 14, letterSpacing: 4)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios, size: 16),
            onPressed: () => Navigator.pop(context)
        ),
        actions: [
          // プロファイル編集ボタン
          IconButton(
            icon: const Icon(Icons.account_circle_outlined, color: Color(0xFFD4AF37), size: 20),
            onPressed: _showProfileRegistration,
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
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(30),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("RANK", style: TextStyle(color: Color(0xFFD4AF37), fontSize: 10, letterSpacing: 2)),
                          Text(_getLevel(), style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                          if (_displayName.isNotEmpty)
                            Text(_displayName, style: const TextStyle(color: Color(0xFFD4AF37), fontSize: 12)),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          const Text("TOTAL VISITS", style: TextStyle(color: Colors.white38, fontSize: 10, letterSpacing: 2)),
                          Text("$_totalPoints", style: const TextStyle(color: Colors.white, fontSize: 18)),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 40),

                  Container(
                    padding: const EdgeInsets.all(25),
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha(5),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFD4AF37).withAlpha(50)),
                    ),
                    child: Wrap(
                      spacing: 20,
                      runSpacing: 20,
                      alignment: WrapAlignment.center,
                      children: List.generate(10, (index) {
                        bool isLit = index < _currentPoints;
                        return Column(
                          children: [
                            Icon(
                              Icons.local_bar,
                              size: 35,
                              color: isLit ? const Color(0xFFD4AF37) : Colors.white10,
                              shadows: isLit ? [const Shadow(color: Color(0xFFD4AF37), blurRadius: 15)] : null,
                            ),
                            const SizedBox(height: 5),
                            Text("${index + 1}", style: TextStyle(color: isLit ? const Color(0xFFD4AF37) : Colors.white10, fontSize: 8)),
                          ],
                        );
                      }),
                    ),
                  ),
                  const SizedBox(height: 40),

                  SizedBox(
                    width: double.infinity,
                    height: 55,
                    child: ElevatedButton.icon(
                      onPressed: _openCheckInDialog,
                      icon: const Icon(Icons.key, color: Colors.black),
                      label: const Text("CHECK-IN", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, letterSpacing: 2)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFD4AF37),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 30),

                  Row(
                    children: [
                      Expanded(child: _buildServiceBtn("5pts Service", 5)),
                      const SizedBox(width: 15),
                      Expanded(child: _buildServiceBtn("10pts Service", 10)),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const Text("※特典利用時は店長に画面を提示してください", style: TextStyle(color: Colors.white24, fontSize: 10)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildServiceBtn(String label, int cost) {
    bool canUse = _currentPoints >= cost;
    return InkWell(
      onTap: canUse ? () => _useService(cost) : null,
      child: Container(
        height: 50,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: canUse ? const Color(0xFFD4AF37) : Colors.white10),
          color: canUse ? const Color(0xFFD4AF37).withAlpha(20) : Colors.transparent,
        ),
        child: Text(label, style: TextStyle(color: canUse ? const Color(0xFFD4AF37) : Colors.white10, fontSize: 12, fontWeight: FontWeight.bold)),
      ),
    );
  }
}