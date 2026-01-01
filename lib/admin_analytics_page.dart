import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'dart:ui';
import 'package:intl/intl.dart';

/// RAGNOISE 管理者用アナリティクス
/// Firestoreに蓄積された来店ログを可視化し、Gemini AIによる経営診断を行います。
class AdminAnalyticsPage extends StatefulWidget {
  const AdminAnalyticsPage({super.key});

  @override
  State<AdminAnalyticsPage> createState() => _AdminAnalyticsPageState();
}

class _AdminAnalyticsPageState extends State<AdminAnalyticsPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  bool _isLoading = true;
  bool _isAnalyzing = false;

  // 集計データ
  int _totalVisits = 0;
  Map<String, int> _ageStats = {};
  Map<String, int> _genderStats = {};
  Map<int, int> _hourStats = {};
  Map<String, int> _monthlyStats = {};

  // Gemini分析結果
  String _aiResponse = "データ集計後にAI経営診断を開始できます。";

  // 【重要】セキュリティ対策: APIキーは直接書かず、環境変数から取得する形式に変更
  // 公開用リポジトリではこのままにしておき、実行時に --dart-define で渡します。
  final String _apiKey = const String.fromEnvironment('GEMINI_API_KEY');

  @override
  void initState() {
    super.initState();
    _fetchAndAnalyzeData();
  }

  /// Firestoreから来店ログ(visit_logs)を取得し、各属性をリアルタイム集計
  Future<void> _fetchAndAnalyzeData() async {
    setState(() => _isLoading = true);
    try {
      // ポイントページで記録した 'visit_logs' コレクションを参照
      final snapshot = await _firestore.collection('visit_logs').get();
      final docs = snapshot.docs;

      int total = docs.length;
      Map<String, int> ageMap = {};
      Map<String, int> genderMap = {};
      Map<int, int> hourMap = {};
      Map<String, int> monthMap = {};

      for (var doc in docs) {
        final data = doc.data();

        // 属性集計
        String age = data['ageGroup'] ?? "不明";
        String gender = data['gender'] ?? "不明";
        ageMap[age] = (ageMap[age] ?? 0) + 1;
        genderMap[gender] = (genderMap[gender] ?? 0) + 1;

        if (data['timestamp'] != null) {
          DateTime dt = (data['timestamp'] as Timestamp).toDate();

          // 時間帯別ヒートマップ用
          hourMap[dt.hour] = (hourMap[dt.hour] ?? 0) + 1;

          // 月別アクティブユーザー推移用
          String monthKey = DateFormat('yyyy-MM').format(dt);
          monthMap[monthKey] = (monthMap[monthKey] ?? 0) + 1;
        }
      }

      setState(() {
        _totalVisits = total;
        _ageStats = ageMap;
        _genderStats = genderMap;
        _hourStats = hourMap;
        _monthlyStats = monthMap;
        _isLoading = false;
        if (total == 0) _aiResponse = "データが蓄積されると、AIによる店舗診断が可能になります。";
      });
    } catch (e) {
      debugPrint("Analysis Load Error: $e");
      setState(() => _isLoading = false);
    }
  }

  /// 集計データをGemini APIに送信し、経営改善アドバイスを生成
  Future<void> _runGeminiAnalysis() async {
    if (_totalVisits == 0) return;

    // APIキーが設定されていない場合のガード
    if (_apiKey.isEmpty || _apiKey == "YOUR_GEMINI_API_KEY_HERE") {
      setState(() => _aiResponse = "APIキーが設定されていません。環境変数を設定してください。");
      return;
    }

    setState(() => _isAnalyzing = true);

    try {
      final model = GenerativeModel(model: 'gemini-1.5-flash', apiKey: _apiKey);

      final prompt = """
あなたはBar RAGNOISEの専属データサイエンティストです。
以下の実データに基づき、プロフェッショナルな「経営診断報告書」を作成してください。

【実データ】
累計来店数: $_totalVisits
月別推移: $_monthlyStats
顧客構成: 年齢層$_ageStats / 性別$_genderStats
ピーク時間帯分布: $_hourStats (時:回数)

【診断の要件】
1. 現状の客層から読み取れる「店舗の強み」
2. データに基づいた「リピート率向上または売上最大化のための具体策」
3. 今後の成長に向けたアドバイス
回答はバーの経営者向けに、日本語で論理的に250文字程度で出力してください。
""";

      final content = [Content.text(prompt)];
      final response = await model.generateContent(content);

      setState(() {
        _aiResponse = response.text ?? "診断結果を取得できませんでした。";
        _isAnalyzing = false;
      });
    } catch (e) {
      setState(() {
        _aiResponse = "診断エラーが発生しました。通信状況を確認してください。";
        _isAnalyzing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('RAGNOISE - 戦略分析室', style: TextStyle(fontSize: 14, letterSpacing: 2)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios, size: 16), onPressed: () => Navigator.pop(context)),
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
          _isLoading
              ? const Center(child: CircularProgressIndicator(color: Color(0xFFD4AF37)))
              : SafeArea(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              children: [
                _buildSummaryCard(),
                const SizedBox(height: 20),
                _buildGeminiCard(),
                const SizedBox(height: 30),
                const Text("月間アクティブユーザー推移", style: TextStyle(color: Color(0xFFD4AF37), fontSize: 10, letterSpacing: 2, fontWeight: FontWeight.bold)),
                const SizedBox(height: 15),
                _buildMonthlyChart(),
                const SizedBox(height: 30),
                const Text("ターゲット属性分析", style: TextStyle(color: Color(0xFFD4AF37), fontSize: 10, letterSpacing: 2, fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: _buildStatCard("年齢層別分布", _ageStats)),
                    const SizedBox(width: 10),
                    Expanded(child: _buildStatCard("男女比率", _genderStats)),
                  ],
                ),
                const SizedBox(height: 30),
                _buildPeakChart(),
                const SizedBox(height: 50),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(15),
        gradient: LinearGradient(colors: [const Color(0xFFD4AF37).withOpacity(0.2), Colors.transparent]),
        border: Border.all(color: const Color(0xFFD4AF37).withOpacity(0.3)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _columnStat("累計ログ数", "$_totalVisits"),
          _columnStat("メイン客層", _ageStats.entries.isEmpty ? "-" : _ageStats.entries.reduce((a, b) => a.value > b.value ? a : b).key),
        ],
      ),
    );
  }

  Widget _columnStat(String label, String value) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: Colors.white38, fontSize: 10)),
        const SizedBox(height: 5),
        Text(value, style: const TextStyle(color: Color(0xFFD4AF37), fontSize: 22, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildGeminiCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.07),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.auto_awesome, color: Color(0xFFD4AF37), size: 18),
                  SizedBox(width: 10),
                  Text("AI ビジネスインサイト", style: TextStyle(color: Color(0xFFD4AF37), fontSize: 12, fontWeight: FontWeight.bold)),
                ],
              ),
              if (!_isAnalyzing && _totalVisits > 0)
                TextButton(
                  onPressed: _runGeminiAnalysis,
                  child: const Text("再診断", style: TextStyle(color: Color(0xFFD4AF37), fontSize: 12)),
                )
            ],
          ),
          const Divider(color: Colors.white10, height: 30),
          if (_isAnalyzing)
            const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator(color: Color(0xFFD4AF37), strokeWidth: 2)))
          else
            Text(_aiResponse, style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.7)),
        ],
      ),
    );
  }

  Widget _buildMonthlyChart() {
    if (_monthlyStats.isEmpty) return const Center(child: Text("推移データなし", style: TextStyle(color: Colors.white12)));

    var sortedKeys = _monthlyStats.keys.toList()..sort();
    var lastSix = sortedKeys.length > 6 ? sortedKeys.sublist(sortedKeys.length - 6) : sortedKeys;

    return Container(
      height: 120,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: lastSix.map((month) {
          int count = _monthlyStats[month] ?? 0;
          double h = (count / (_totalVisits == 0 ? 1 : _totalVisits)) * 100 + 10;
          return Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text("$count", style: const TextStyle(color: Color(0xFFD4AF37), fontSize: 10)),
              const SizedBox(height: 5),
              Container(width: 25, height: h, decoration: BoxDecoration(color: const Color(0xFFD4AF37).withOpacity(0.6), borderRadius: BorderRadius.circular(4))),
              const SizedBox(height: 5),
              Text(month.substring(5), style: const TextStyle(color: Colors.white38, fontSize: 9)),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _buildStatCard(String title, Map<String, int> stats) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.04), borderRadius: BorderRadius.circular(15)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: Colors.white38, fontSize: 10)),
          const SizedBox(height: 10),
          ...stats.entries.take(4).map((e) => Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(e.key, style: const TextStyle(color: Colors.white70, fontSize: 11)),
                Text("${e.value}", style: const TextStyle(color: Color(0xFFD4AF37), fontSize: 11, fontWeight: FontWeight.bold)),
              ],
            ),
          )).toList(),
        ],
      ),
    );
  }

  Widget _buildPeakChart() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.04), borderRadius: BorderRadius.circular(20)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("24時間別 来店ヒートマップ", style: TextStyle(color: Colors.white38, fontSize: 10)),
          const SizedBox(height: 20),
          SizedBox(
            height: 60,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(24, (i) {
                int count = _hourStats[i] ?? 0;
                return Container(
                  width: 4,
                  height: (count * 5.0).clamp(2.0, 60.0),
                  decoration: BoxDecoration(color: count > 0 ? const Color(0xFFD4AF37) : Colors.white10, borderRadius: BorderRadius.circular(1)),
                );
              }),
            ),
          ),
          const SizedBox(height: 5),
          const Center(child: Text("0:00 - 23:00", style: TextStyle(color: Colors.white24, fontSize: 8))),
        ],
      ),
    );
  }
}