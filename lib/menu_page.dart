import 'package:flutter/material.dart';

class MenuPage extends StatelessWidget {
  const MenuPage({super.key});

  @override
  Widget build(BuildContext context) {
    // 表示する画像リスト
    final List<String> menuImages = [
      'assets/image/スコッチ.jpg',
      'assets/image/ウイスキー.jpg',
      'assets/image/ソフドリ.jpg',
    ];

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('MENU', style: TextStyle(fontSize: 14, letterSpacing: 4)),
        backgroundColor: Colors.black,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 16),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: PageView.builder(
        itemCount: menuImages.length,
        itemBuilder: (context, index) {
          return InteractiveViewer( // ピンチイン・アウトで拡大可能に
            child: Center(
              child: Image.asset(
                menuImages[index],
                fit: BoxFit.contain,
              ),
            ),
          );
        },
      ),
    );
  }
}