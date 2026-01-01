import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:ui';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ReservePage extends StatefulWidget {
  const ReservePage({super.key});

  @override
  State<ReservePage> createState() => _ReservePageState();
}

class _ReservePageState extends State<ReservePage> {
  bool _isEditMode = false;
  String _fetchedAdminPass = "";

  final TextEditingController _nameCtrl = TextEditingController();
  DateTime _selectedDate = DateTime.now().add(const Duration(days: 1));
  String _selectedTime = "19:00";

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  List<Map<String, dynamic>> _reservations = [];
  Map<String, dynamic> _calendarEvents = {};

  @override
  void initState() {
    super.initState();
    _listenToReservations();
    _loadCalendarData();
    _loadAdminSettings();
  }

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

  Future<void> _loadCalendarData() async {
    try {
      final snapshot = await _firestore.collection('calendar').get();
      final Map<String, dynamic> events = {};
      for (var doc in snapshot.docs) {
        events[doc.id] = doc.data();
      }
      if (mounted) {
        setState(() {
          _calendarEvents = events;
        });
      }
    } catch (e) {
      debugPrint("Calendar Load Error: $e");
    }
  }

  bool _isDateSelectable(DateTime date) {
    final dateKey = "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
    if (_calendarEvents.containsKey(dateKey)) {
      final status = _calendarEvents[dateKey]['status'];
      if (status == "おやすみ" || status == "一部貸切") {
        return false;
      }
    }
    return true;
  }

  void _listenToReservations() {
    _firestore
        .collection('reservations')
        .orderBy('timestamp', descending: true)
        .snapshots()
        .listen((snapshot) {
      final List<Map<String, dynamic>> fetched = snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        if (data['timestamp'] is Timestamp) {
          data['timestamp'] = (data['timestamp'] as Timestamp).millisecondsSinceEpoch;
        }
        return data;
      }).toList();

      if (mounted) {
        setState(() {
          _reservations = fetched;
        });
        _saveToLocalForBadge(fetched);
      }
    });
  }

  Future<void> _saveToLocalForBadge(List<Map<String, dynamic>> dataList) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final List<Map<String, dynamic>> cleanList = dataList.map((item) {
        return {
          'id': item['id'],
          'isConfirmed': item['isConfirmed'] ?? false,
          'name': item['name'] ?? '',
          'date': item['date'] ?? '',
          'time': item['time'] ?? '',
        };
      }).toList();

      await prefs.setString('ragnoise_reserve_data', jsonEncode(cleanList));
      debugPrint("Badge Update: ${cleanList.where((e) => e['isConfirmed'] == false).length} items");
    } catch (e) {
      debugPrint("Save Error: $e");
    }
  }

  Future<void> _submitReservation() async {
    if (_nameCtrl.text.isEmpty) return;

    final newReserve = {
      'name': _nameCtrl.text,
      'date': "${_selectedDate.year}-${_selectedDate.month}-${_selectedDate.day}",
      'time': _selectedTime,
      'isConfirmed': false,
      'timestamp': FieldValue.serverTimestamp(),
    };

    try {
      await _firestore.collection('reservations').add(newReserve);

      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: Colors.black,
            shape: RoundedRectangleBorder(side: const BorderSide(color: Color(0xFFD4AF37)), borderRadius: BorderRadius.circular(15)),
            title: const Text('送信完了', style: TextStyle(color: Color(0xFFD4AF37), fontSize: 14, letterSpacing: 2)),
            content: const Text('仮予約を承りました。店舗からの連絡をお待ちください。', style: TextStyle(color: Colors.white70, fontSize: 12)),
            actions: [
              TextButton(onPressed: () {
                Navigator.pop(context);
                _nameCtrl.clear();
              }, child: const Text('OK', style: TextStyle(color: Color(0xFFD4AF37)))),
            ],
          ),
        );
      }
    } catch (e) {
      debugPrint("Submit Error: $e");
    }
  }

  Future<void> _toggleConfirm(String id, bool currentStatus) async {
    try {
      await _firestore.collection('reservations').doc(id).update({
        'isConfirmed': !currentStatus,
      });

      final updatedList = _reservations.map((res) {
        if (res['id'] == id) {
          return {...res, 'isConfirmed': !currentStatus};
        }
        return res;
      }).toList();
      await _saveToLocalForBadge(updatedList);

    } catch (e) {
      debugPrint("Update Error: $e");
    }
  }

  void _showPassDialog() {
    final TextEditingController passCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(side: const BorderSide(color: Color(0xFFD4AF37), width: 0.5), borderRadius: BorderRadius.circular(15)),
        title: const Text('管理者認証', style: TextStyle(color: Color(0xFFD4AF37), fontSize: 12, letterSpacing: 2)),
        content: TextField(
          controller: passCtrl,
          obscureText: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
              hintText: "パスワードを入力",
              hintStyle: TextStyle(color: Colors.white24, fontSize: 12),
              enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFD4AF37)))
          ),
        ),
        actions: [
          TextButton(onPressed: () {
            if (_fetchedAdminPass.isNotEmpty && passCtrl.text == _fetchedAdminPass) {
              setState(() => _isEditMode = true);
              Navigator.pop(context);
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("パスワードが正しくありません"), backgroundColor: Colors.redAccent),
              );
            }
          }, child: const Text('ロック解除', style: TextStyle(color: Color(0xFFD4AF37)))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('RESERVE', style: TextStyle(fontSize: 14, letterSpacing: 6, fontWeight: FontWeight.w300)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios, size: 16),
            onPressed: () => Navigator.pop(context)
        ),
        actions: [
          IconButton(
            icon: Icon(_isEditMode ? Icons.person_outline : Icons.admin_panel_settings_outlined,
                color: _isEditMode ? Colors.green : const Color(0xFFD4AF37)),
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
                      colorFilter: ColorFilter.mode(Colors.black87, BlendMode.darken)
                  )
              )
          ),
          SafeArea(
            child: _isEditMode ? _buildAdminView() : _buildUserView(),
          ),
        ],
      ),
    );
  }

  Widget _buildAdminView() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text('予約管理モード', style: TextStyle(color: Color(0xFFD4AF37), fontSize: 10, letterSpacing: 2)),
        const SizedBox(height: 20),
        if (_reservations.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(child: Text("予約データがありません", style: TextStyle(color: Colors.white24, fontSize: 12))),
          )
        else
          ..._reservations.map((res) => _buildAdminReserveCard(res)),
      ],
    );
  }

  Widget _buildAdminReserveCard(Map<String, dynamic> data) {
    bool isConfirmed = data['isConfirmed'] ?? false;
    String docId = data['id'] ?? "";
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: !isConfirmed ? const Color(0xFFD4AF37).withAlpha(30) : Colors.white.withAlpha(5),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: !isConfirmed ? const Color(0xFFD4AF37).withAlpha(150) : Colors.white10),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(data['name'] ?? '名前不明', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                Text("${data['date']} ${data['time']}", style: const TextStyle(color: Colors.white54, fontSize: 12)),
              ],
            ),
          ),
          TextButton(
            onPressed: () => _toggleConfirm(docId, isConfirmed),
            child: Text(
              isConfirmed ? '未対応に戻す' : '承認する',
              style: TextStyle(color: isConfirmed ? Colors.white38 : const Color(0xFFD4AF37), fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserView() {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 30),
      children: [
        const SizedBox(height: 20),
        const Icon(Icons.auto_awesome, color: Color(0xFFD4AF37), size: 40),
        const SizedBox(height: 20),
        const Center(child: Text('予約リクエスト', style: TextStyle(color: Colors.white, fontSize: 18, letterSpacing: 4))),
        const SizedBox(height: 10),
        const Text('※お席を確定するものではありません。\n店舗より折り返しご連絡差し上げます。',
            textAlign: TextAlign.center, style: TextStyle(color: Colors.white38, fontSize: 11, height: 1.5)),
        const SizedBox(height: 40),

        _buildInputLabel("お名前"),
        TextField(
          controller: _nameCtrl,
          style: const TextStyle(color: Colors.white),
          decoration: _inputDecoration("お名前を入力してください"),
        ),
        const SizedBox(height: 25),

        _buildInputLabel("ご希望日"),
        GestureDetector(
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: _selectedDate,
              firstDate: DateTime.now(),
              lastDate: DateTime.now().add(const Duration(days: 60)),
              selectableDayPredicate: _isDateSelectable,
              builder: (context, child) => Theme(data: ThemeData.dark().copyWith(
                colorScheme: const ColorScheme.dark(primary: Color(0xFFD4AF37), onPrimary: Colors.black, surface: Color(0xFF1A1A1A)),
              ), child: child!),
            );
            if (picked != null) setState(() => _selectedDate = picked);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 20),
            decoration: BoxDecoration(color: Colors.white.withAlpha(10), borderRadius: BorderRadius.circular(15)),
            child: Row(
              children: [
                const Icon(Icons.calendar_today, color: Color(0xFFD4AF37), size: 16),
                const SizedBox(width: 15),
                Text("${_selectedDate.year}/${_selectedDate.month}/${_selectedDate.day}", style: const TextStyle(color: Colors.white)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 25),

        _buildInputLabel("ご希望時間"),
        DropdownButtonFormField<String>(
          value: _selectedTime,
          dropdownColor: const Color(0xFF1A1A1A),
          style: const TextStyle(color: Colors.white),
          decoration: _inputDecoration(""),
          items: [
            "19:00","20:00","21:00","22:00","23:00","24:00","25:00","26:00"
          ].map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
          onChanged: (v) => setState(() => _selectedTime = v!),
        ),

        const SizedBox(height: 40),
        SizedBox(
          width: double.infinity,
          height: 55,
          child: ElevatedButton(
            onPressed: _submitReservation,
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFD4AF37),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))
            ),
            child: const Text('リクエストを送信', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, letterSpacing: 2)),
          ),
        ),

        const SizedBox(height: 60),
        const Text('最近のリクエスト', style: TextStyle(color: Color(0xFFD4AF37), fontSize: 10, letterSpacing: 2)),
        const SizedBox(height: 15),

        if (_reservations.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Text("リクエスト履歴はありません", style: TextStyle(color: Colors.white24, fontSize: 12)),
          )
        else
          ..._reservations.take(5).map((res) => _buildUserReserveListItem(res)),

        const SizedBox(height: 50),
      ],
    );
  }

  Widget _buildUserReserveListItem(Map<String, dynamic> data) {
    bool isConfirmed = data['isConfirmed'] ?? false;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: isConfirmed ? Colors.green : const Color(0xFFD4AF37), width: 2)),
        color: Colors.white.withAlpha(5),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(data['name'] ?? '', style: const TextStyle(color: Colors.white, fontSize: 13)),
              Text("${data['date']} ${data['time']}", style: const TextStyle(color: Colors.white38, fontSize: 10)),
            ],
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              color: isConfirmed ? Colors.green.withAlpha(40) : const Color(0xFFD4AF37).withAlpha(40),
            ),
            child: Text(
              isConfirmed ? "承認済み" : "確認中",
              style: TextStyle(
                color: isConfirmed ? Colors.green : const Color(0xFFD4AF37),
                fontSize: 9,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(left: 5, bottom: 8),
      child: Align(alignment: Alignment.centerLeft, child: Text(label, style: const TextStyle(color: Color(0xFFD4AF37), fontSize: 10, letterSpacing: 2))),
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
}