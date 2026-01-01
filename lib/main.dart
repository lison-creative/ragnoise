import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:async';
import 'dart:math';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// 各ページ・設定ファイルのインポート
import 'calendar_page.dart';
import 'moments_page.dart';
import 'reserve_page.dart';
import 'points_page.dart';
import 'menu_page.dart';
import 'admin_analytics_page.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebaseの初期化
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // iPhoneのノッチ・ステータスバーの設定
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Colors.black,
  ));

  runApp(const RagnoiseApp());
}

class RagnoiseApp extends StatelessWidget {
  const RagnoiseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Bar RAGNOISE',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0D0D0D),
        fontFamily: 'Georgia',
      ),
      home: const KidoGamen(),
    );
  }
}

// --- 1. 起動画面 (KidoGamen) ---
class KidoGamen extends StatefulWidget {
  const KidoGamen({super.key});

  @override
  State<KidoGamen> createState() => _KidoGamenState();
}

class _KidoGamenState extends State<KidoGamen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final String _logoPath = 'assets/image/ロゴ.png';

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 3));
    _controller.forward();

    Timer(const Duration(milliseconds: 3200), () {
      if (mounted) {
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            pageBuilder: (context, anim, secAnim) => const HomeGamen(),
            transitionsBuilder: (context, anim, secAnim, child) => FadeTransition(opacity: anim, child: child),
            transitionDuration: const Duration(milliseconds: 1200),
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: LogoNoiseEffect(
          imagePath: _logoPath,
          controller: _controller,
          imageWidth: 280,
        ),
      ),
    );
  }
}

class LogoNoiseEffect extends StatelessWidget {
  final String imagePath;
  final AnimationController controller;
  final double imageWidth;

  const LogoNoiseEffect({
    super.key,
    required this.imagePath,
    required this.controller,
    required this.imageWidth,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        final double t = controller.value;
        double opacity = (t < 0.7) ? (t / 0.7).clamp(0, 1) : (1.0 - (t - 0.8) / 0.2).clamp(0, 1);
        final bool isGlitch = Random().nextDouble() < 0.25 && t < 0.8;

        return Opacity(
          opacity: opacity,
          child: Transform.translate(
            offset: Offset(isGlitch ? Random().nextDouble() * 10 - 5 : 0, 0),
            child: Image.asset(
              imagePath,
              width: imageWidth,
              errorBuilder: (c, e, s) => const Text(
                'RAGNOISE',
                style: TextStyle(fontSize: 42, color: Color(0xFFD4AF37), letterSpacing: 8),
              ),
            ),
          ),
        );
      },
    );
  }
}

// --- 2. ホーム画面 (HomeGamen) ---
class HomeGamen extends StatefulWidget {
  const HomeGamen({super.key});

  @override
  State<HomeGamen> createState() => _HomeGamenState();
}

class _HomeGamenState extends State<HomeGamen> {
  final PageController _pageController = PageController(viewportFraction: 1.0);
  int _currentPage = 0;
  late Timer _sliderTimer;
  int _unconfirmedCount = 0;

  final List<String> _sliderImages = [
    'assets/image/スライド1.JPG',
    'assets/image/スライド2.JPG',
    'assets/image/スライド3.JPG',
  ];

  @override
  void initState() {
    super.initState();
    _checkUnconfirmedReservations();

    _sliderTimer = Timer.periodic(const Duration(seconds: 3), (Timer timer) {
      if (_currentPage < _sliderImages.length - 1) {
        _currentPage++;
      } else {
        _currentPage = 0;
      }

      if (_pageController.hasClients) {
        _pageController.animateToPage(
          _currentPage,
          duration: const Duration(milliseconds: 800),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  Future<void> _checkUnconfirmedReservations() async {
    final prefs = await SharedPreferences.getInstance();
    final String? jsonStr = prefs.getString('ragnoise_reserve_data');
    if (jsonStr != null) {
      final List<dynamic> data = jsonDecode(jsonStr);
      if (mounted) {
        setState(() {
          _unconfirmedCount = data.where((r) => r['isConfirmed'] == false).length;
        });
      }
    }
  }

  // --- 修正ポイント: Firestoreからパスワードを取得して認証 ---
  void _openAdminAnalytics() async {
    final TextEditingController _passController = TextEditingController();

    // 1. Firestoreから最新のパスワードを取得
    String? correctPass;
    try {
      final doc = await FirebaseFirestore.instance.collection('settings').doc('admin').get();
      // スクリーンショットで追加したフィールド名「admin_analytics_pass」を取得
      correctPass = doc.data()?['admin_analytics_pass'];
    } catch (e) {
      debugPrint("Firestore取得エラー: $e");
    }

    // パスワードが取得できなかった場合のバックアップ（任意）
    correctPass ??= "8888";

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xFFD4AF37), width: 1),
        ),
        title: const Text("ADMIN ACCESS", style: TextStyle(color: Color(0xFFD4AF37), fontSize: 14, letterSpacing: 2)),
        content: TextField(
          controller: _passController,
          obscureText: true,
          autofocus: true,
          keyboardType: TextInputType.number,
          style: const TextStyle(color: Colors.white, fontSize: 24, letterSpacing: 8),
          textAlign: TextAlign.center,
          decoration: const InputDecoration(
            hintText: "****",
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white10)),
          ),
          onChanged: (val) {
            // Firestoreの値と一致したら遷移
            if (val == correctPass) {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (context) => const AdminAnalyticsPage()));
            }
          },
        ),
      ),
    );
  }

  @override
  void dispose() {
    _sliderTimer.cancel();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _launchURL() async {
    final Uri url = Uri.parse('https://bar-ragnoise.com/');
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) throw 'Could not launch $url';
  }

  @override
  Widget build(BuildContext context) {
    final double screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      body: Stack(
        children: [
          Container(
            width: double.infinity,
            height: double.infinity,
            decoration: const BoxDecoration(
              image: DecorationImage(
                image: AssetImage('assets/image/背景1.png'),
                fit: BoxFit.cover,
                colorFilter: ColorFilter.mode(Colors.black54, BlendMode.darken),
              ),
            ),
          ),

          SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              children: [
                SizedBox(
                  height: screenHeight * 0.45,
                  width: double.infinity,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      PageView.builder(
                        controller: _pageController,
                        itemCount: _sliderImages.length,
                        onPageChanged: (int page) => setState(() => _currentPage = page),
                        itemBuilder: (context, index) {
                          return Container(
                            width: double.infinity,
                            height: double.infinity,
                            child: Image.asset(
                              _sliderImages[index],
                              fit: BoxFit.cover,
                              alignment: Alignment.center,
                              errorBuilder: (c, e, s) => Center(
                                child: Image.asset('assets/image/ロゴ.png', fit: BoxFit.contain),
                              ),
                            ),
                          );
                        },
                      ),
                      Positioned(
                        bottom: 20,
                        child: Row(
                          children: List.generate(_sliderImages.length, (index) {
                            return AnimatedContainer(
                              duration: const Duration(milliseconds: 300),
                              margin: const EdgeInsets.symmetric(horizontal: 4),
                              height: 4,
                              width: _currentPage == index ? 20 : 8,
                              decoration: BoxDecoration(
                                color: _currentPage == index
                                    ? const Color(0xFFD4AF37)
                                    : const Color(0xFFD4AF37).withOpacity(0.3),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            );
                          }),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),
                const Text(
                  'RAGNOISE',
                  style: TextStyle(
                    fontSize: 28,
                    letterSpacing: 12,
                    color: Color(0xFFD4AF37),
                    fontWeight: FontWeight.w200,
                  ),
                ),
                const SizedBox(height: 40),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 2,
                    crossAxisSpacing: 15,
                    mainAxisSpacing: 15,
                    childAspectRatio: 1.0,
                    children: [
                      _buildImageFramedTile(context, 'CALENDAR', Icons.calendar_month, 'assets/image/額縁1.png', const CalendarPage()),
                      _buildImageFramedTile(context, 'MOMENTS', Icons.forum_outlined, 'assets/image/額縁2.png', const MomentsPage()),
                      _buildImageFramedTile(context, 'RESERVE', Icons.edit_calendar, 'assets/image/額縁3.png', const ReservePage(), badgeCount: _unconfirmedCount),
                      _buildImageFramedTile(context, 'POINTS', Icons.stars_outlined, 'assets/image/額縁4.png', const PointsPage()),
                      _buildImageFramedTile(context, 'MENU', Icons.local_bar, 'assets/image/額縁5.png', const MenuPage()),
                      _buildImageFramedTile(context, 'WEBSITE', Icons.language, 'assets/image/額縁6.png', null, action: _launchURL),
                    ],
                  ),
                ),

                const SizedBox(height: 50),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 25),
                  child: Container(
                    padding: const EdgeInsets.all(25),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.4),
                      borderRadius: BorderRadius.circular(2),
                      border: Border.all(color: const Color(0xFFD4AF37).withOpacity(0.2)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: GestureDetector(
                            onLongPress: _openAdminAnalytics, // ここで認証メソッドを呼び出し
                            child: const Text(
                              'ABOUT RAGNOISE',
                              style: TextStyle(color: Color(0xFFD4AF37), fontSize: 18, letterSpacing: 4, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                        const SizedBox(height: 25),
                        _aboutText('Concept', '秘密の遊び場 『RAGNOISE』'),
                        const SizedBox(height: 20),
                        _aboutText('Opening Hours', '不定休: 基本19:00 - 03:00'),
                        const SizedBox(height: 20),
                        _aboutText('Access', '南行徳駅南口より徒歩4分\n住所：千葉県市川市南行徳1-22-8 東15ビル 4F D号'),
                        const SizedBox(height: 25),
                        const Divider(color: Color(0xFFD4AF37), thickness: 0.5),
                        const SizedBox(height: 15),
                        const Text(
                          'アコギ、ベース、電子ピアノなど 楽器を演奏しながらお酒を飲むことができるBAR。\nカラオケも完備されており、 楽器が出来ない方も楽しめます!\n友人との語らいや、ひとりの時間を楽しむ場所としても最適。\nソフトドリンク、ノンアルコールカクテルもご用意しているので、お酒が苦手な方でも気軽にお越しいただけます。',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.8),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 120),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _aboutText(String label, String content) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(), style: const TextStyle(color: Color(0xFFD4AF37), fontSize: 10, letterSpacing: 2, fontWeight: FontWeight.w900)),
        const SizedBox(height: 6),
        Text(content, style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.6)),
      ],
    );
  }

  Widget _buildImageFramedTile(BuildContext context, String title, IconData icon, String framePath, Widget? nextPage, {Function? action, int badgeCount = 0}) {
    return GestureDetector(
      onTap: () async {
        HapticFeedback.mediumImpact();
        if (action != null) {
          action();
        } else if (nextPage != null) {
          await Navigator.push(context, MaterialPageRoute(builder: (context) => nextPage));
          _checkUnconfirmedReservations();
        }
      },
      child: Stack(
        alignment: Alignment.center,
        children: [
          Image.asset(
            framePath,
            fit: BoxFit.contain,
            width: double.infinity,
            height: double.infinity,
            errorBuilder: (context, error, stackTrace) => Container(
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFFD4AF37).withOpacity(0.5), width: 1),
                color: Colors.black26,
              ),
              child: const Center(child: Text('NO FRAME', style: TextStyle(fontSize: 8))),
            ),
          ),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: const Color(0xFFD4AF37).withOpacity(0.1), blurRadius: 10, spreadRadius: 2)],
                ),
                child: Icon(icon, color: const Color(0xFFD4AF37), size: 34),
              ),
              const SizedBox(height: 8),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  letterSpacing: 1.5,
                  fontWeight: FontWeight.bold,
                  shadows: [Shadow(color: Colors.black, blurRadius: 4, offset: Offset(2, 2))],
                ),
              ),
            ],
          ),
          if (badgeCount > 0)
            Positioned(
              top: 15,
              right: 15,
              child: Container(
                padding: const EdgeInsets.all(5),
                decoration: const BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle),
                constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                child: Text(
                  '$badgeCount',
                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// SubPage定義
class SubPage extends StatelessWidget {
  final String title;
  const SubPage({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title, style: const TextStyle(fontSize: 14, letterSpacing: 2)),
        backgroundColor: Colors.black,
        elevation: 0,
        centerTitle: true,
      ),
      body: Stack(
        children: [
          Container(
            width: double.infinity,
            height: double.infinity,
            decoration: const BoxDecoration(
              image: DecorationImage(
                image: AssetImage('assets/image/背景1.png'),
                fit: BoxFit.cover,
                colorFilter: ColorFilter.mode(Colors.black87, BlendMode.darken),
              ),
            ),
          ),
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.wine_bar, color: Color(0xFFD4AF37), size: 50),
                const SizedBox(height: 20),
                Text(
                  '$title\nCOMING SOON',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white24, letterSpacing: 4, height: 2),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}