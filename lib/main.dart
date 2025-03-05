import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:csv/csv.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:app_links/app_links.dart';
import 'dart:async';
import 'package:process_run/process_run.dart';

import 'package:flutter_spinkit/flutter_spinkit.dart';

void main() {
  runApp(
      MyApp()); // สร้าง เพลลิสต์ใน spotify ได้เเล้ว ใช้ Emulator Pixel API 35(new)
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Spotify Playlist',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        scaffoldBackgroundColor: const Color.fromARGB(255, 17, 17, 17),
      ),
      home: MoodSearchPage(),
    );
  }
}

// หน้าที่ 1: หน้าค้นหาอารมณ์
class MoodSearchPage extends StatefulWidget {
  @override
  _MoodSearchPageState createState() => _MoodSearchPageState();
}

class _MoodSearchPageState extends State<MoodSearchPage> {
  final TextEditingController _moodController = TextEditingController();
  String accessToken = ''; // เก็บ accessToken ไว้เพื่อไม่ต้องขอใหม่
  String refreshToken = ''; // เก็บ refreshToken สำหรับรีเฟรช token
  DateTime? tokenExpiryTime; // เวลาหมดอายุของ Access Token

  final FocusNode _focusNode = FocusNode();
  bool _isFocused = false;

  final AppLinks _appLinks = AppLinks();

  @override
  void initState() {
    super.initState();
    _authorizeUser();

    _focusNode.addListener(() {
      // ฟังการโฟกัสของ TextField
      setState(() {
        _isFocused = _focusNode.hasFocus;
      });
    });
  }

  @override
  void dispose() {
    _focusNode.dispose(); // ปล่อย FocusNode เมื่อไม่ใช้งาน
    super.dispose();
  }

  void _onPlaylistButtonPressed(String playlistName) async {
    try {
      Map<String, dynamic> predictedEmotions =
          await _predictEmotion(playlistName);
      print('Received predicted emotions: $predictedEmotions');

      String highestEmotion = predictedEmotions['max_emotion'];

      Map<String, double> emotionPercentages =
          (predictedEmotions['emotion_percentages'] as Map<String, dynamic>)
              .map((key, value) => MapEntry(key, (value as num).toDouble()));

      // ใช้ Future เพื่อดีเลย์ Navigator.push ให้แน่ใจว่าทำหลัง build เสร็จ
      Future.delayed(Duration.zero, () {
        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => PlaylistPage(
                mood: playlistName,  // ใช้ชื่อเพลย์ลิสต์ 
                emotionPercentages: emotionPercentages,
                accessToken: accessToken,
              ),
            ),
          );
        }
      });
    } catch (e) {
      print('Error predicting emotion: $e');
    }
  }

  void _onEmotionButtonPressed(String emotion) {
    // ใช้ Future เพื่อดีเลย์ Navigator.push
    Future.delayed(Duration.zero, () {
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => PlaylistPage(
              mood: emotion,
              emotionPercentages: {}, // ส่งอารมณ์โดยไม่ต้องใช้หลายอารมณ์
              accessToken: accessToken,
            ),
          ),
        );
      }
    });
  }

  // ขอ Authorization ทันทีเมื่อเปิดแอป
  Future<void> _authorizeUser() async {
    final String clientId = '8dbfc478ce9a44738e1b874863381afc'; // Client ID
    final String clientSecret =
        '706721926ee6457a908ad3ba888d4467'; // Client Secret
    final String redirectUri = 'myspotifyapp://callback';

    final String authUrl = 'https://accounts.spotify.com/authorize?'
        'client_id=$clientId&response_type=code&redirect_uri=$redirectUri&scope=user-read-private%20playlist-modify-private';

    if (await canLaunch(authUrl)) {
      await launch(authUrl);
    } else {
      throw 'Could not launch $authUrl';
    }

    // จับ Incoming Links จาก Spotify
    _appLinks.uriLinkStream.listen((Uri? uri) async {
      if (uri != null) {
        final code = uri.queryParameters['code'];
        if (code != null) {
          await _getAccessTokenWithCode(
              clientId, clientSecret, redirectUri, code);
        }
      }
    });
  }

  Future<void> _getAccessTokenWithCode(String clientId, String clientSecret,
      String redirectUri, String code) async {
    final response = await http.post(
      Uri.parse('https://accounts.spotify.com/api/token'),
      headers: {
        'Authorization':
            'Basic ' + base64Encode(utf8.encode('$clientId:$clientSecret')),
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: {
        'grant_type': 'authorization_code',
        'code': code,
        'redirect_uri': redirectUri,
      },
    );

    if (response.statusCode == 200) {
      final responseData = json.decode(response.body);
      setState(() {
        accessToken = responseData['access_token'];
        refreshToken = responseData['refresh_token']; // เก็บ refresh token
        tokenExpiryTime = DateTime.now().add(
            Duration(seconds: responseData['expires_in'])); // เก็บเวลาหมดอายุ
      });
    } else {
      throw Exception('Failed to obtain access token');
    }
  }

  // ฟังก์ชันรีเฟรช Access Token
  Future<void> _refreshAccessToken() async {
    final String clientId = '8dbfc478ce9a44738e1b874863381afc'; // Client ID
    final String clientSecret =
        '706721926ee6457a908ad3ba888d4467'; // Client Secret

    final response = await http.post(
      Uri.parse('https://accounts.spotify.com/api/token'),
      headers: {
        'Authorization':
            'Basic ' + base64Encode(utf8.encode('$clientId:$clientSecret')),
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: {
        'grant_type': 'refresh_token',
        'refresh_token': refreshToken,
      },
    );

    if (response.statusCode == 200) {
      final responseData = json.decode(response.body);
      setState(() {
        accessToken = responseData['access_token'];
        tokenExpiryTime = DateTime.now().add(
            Duration(seconds: responseData['expires_in'])); // อัพเดตเวลาหมดอายุ
      });
    } else {
      print(
          'Failed to refresh access token. Status code: ${response.statusCode}');
    }
  }

  // ตรวจสอบว่า token หมดอายุหรือยัง
  Future<void> _checkAndRefreshAccessToken() async {
    if (tokenExpiryTime != null && DateTime.now().isAfter(tokenExpiryTime!)) {
      await _refreshAccessToken(); // รีเฟรช access token ถ้าหมดอายุ
    }
  }

  // เรียก API เพื่อทำนายอารมณ์
  Future<void> _navigateToPlaylist([String? emotion]) async {
    String moodText;

    // ถ้ามีอารมณ์ที่ส่งมาจากการกดกล่องอารมณ์ ให้ใช้อารมณ์นั้น
    // ถ้าไม่มีก็ใช้ค่าจากช่องกรอกอารมณ์
    if (emotion != null) {
      moodText = emotion;
    } else {
      moodText = _moodController.text.trim();
    }

    if (moodText.isNotEmpty) {
      await _checkAndRefreshAccessToken(); // ตรวจสอบการหมดอายุของ Access Token

      try {
        print('Sending request to API...');

        // ถ้าเป็นการพิมพ์อารมณ์ให้ทำการทำนาย
        if (emotion == null) {
          Map<String, dynamic> predictedEmotions =
              await _predictEmotion(moodText);
          print('Received predicted emotions: $predictedEmotions');

          // ค้นหาอารมณ์ที่มีเปอร์เซ็นต์สูงสุดและเก็บค่าไว้ในตัวแปร highestEmotion
          String highestEmotion =
              predictedEmotions['max_emotion']; // <-- แก้ไขตรงนี้

          // แปลงค่าเป็น Map<String, double>
          Map<String, dynamic> emotionPercentagesDynamic =
              predictedEmotions['emotion_percentages'];
          Map<String, double> emotionPercentages = emotionPercentagesDynamic
              .map((key, value) => MapEntry(key, (value as num).toDouble()));

          // ส่งค่า highestEmotion ไปยัง PlaylistPage
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => PlaylistPage(
                mood: moodText, // ใช้ข้อความที่ผู้ใช้พิมพ์เป็นชื่อเพลย์ลิสต์
                emotionPercentages:
                    emotionPercentages, // ส่งค่าเปอร์เซ็นต์อารมณ์
                accessToken: accessToken,
              ),
            ),
          );
        } else {
          // ถ้ามีค่า emotion ส่งไปตรงๆ
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => PlaylistPage(
                mood: moodText, // ใช้ emotion ที่ส่งมาโดยตรง
                emotionPercentages: {}, // ส่งค่า emotion เปล่าไปในกรณีนี้
                accessToken: accessToken,
              ),
            ),
          );
        }
      } catch (e) {
        print('Error navigating to playlist: $e');
      }
    }
  }

  Future<Map<String, dynamic>> _predictEmotion(String text) async {
    final url = Uri.parse(
        'https://flaskapi-809290853539.asia-southeast1.run.app/predict_emotion'); // URL ของ API บนคลาวด์

    print('Sending text: $text to $url');

    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'text': text}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data != null && data is Map<String, dynamic>) {
          return {
            'emotion_percentages':
                data['emotion_percentages'], // ข้อมูลเปอร์เซ็นต์
            'max_emotion': data['max_emotion'],
          };
        } else {
          throw Exception('Invalid data format');
        }
      } else if (response.statusCode == 400) {
        final errorData = jsonDecode(response.body);
        if (errorData['error'] != null) {
          // แสดงข้อความแจ้งเตือนจาก API
          _showErrorDialog(context, errorData['error']);
        }
        throw Exception('Error from API: ${errorData['error']}');
      } else {
        throw Exception('Unexpected error: ${response.statusCode}');
      }
    } catch (e) {
      print('Error calling API: $e');
      rethrow;
    }
  }

// ฟังก์ชันสำหรับแสดง AlertDialog เมื่อเกิดข้อผิดพลาด
  void _showErrorDialog(BuildContext context, String message) {
    String displayMessage;
    if (message
        .contains("เนื้อเพลงสั้นเกินไป กรุณาป้อนเนื้อเพลงที่ยาวกว่านี้")) {
      displayMessage = "กรุณาป้อนข้อความให้มีจำนวนคำมากกว่า 5 คำ";
    } else if (message.contains("กรุณาป้อนเนื้อเพลงเป็นภาษาไทย")) {
      displayMessage = "กรุณาป้อนอารมณ์เป็นภาษาไทย";
    } else {
      displayMessage = message; // ใช้ข้อความเดิมหากไม่มีการระบุข้อความพิเศษ
    }
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20.0), // มุมโค้งมน
          ),
          backgroundColor: Colors.grey[900], // สีพื้นหลังเข้ม
          title: Row(
            children: [
              Icon(Icons.error_outline,
                  color: Colors.red, size: 28), // ไอคอนแจ้งเตือน
              SizedBox(width: 10),
              Text(
                'ข้อผิดพลาด',
                style: TextStyle(
                  color: Colors.white, // สีตัวอักษร
                  fontSize: 22, // ขนาดตัวอักษรใหญ่ขึ้น
                  fontWeight: FontWeight.bold, // ตัวหนา
                ),
              ),
            ],
          ),
          content: Text(
            displayMessage,
            style: TextStyle(
              color: Colors.white70, // สีตัวอักษร
              fontSize: 18, // ขนาดตัวอักษรใหญ่ขึ้น
            ),
            textAlign: TextAlign.center, // จัดข้อความให้อยู่ตรงกลาง
          ),
          actions: [
            Center(
              child: ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent, // สีพื้นหลังปุ่ม
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10.0), // มุมปุ่มโค้งมน
                  ),
                  padding: EdgeInsets.symmetric(
                      horizontal: 20, vertical: 10), // ขนาดปุ่ม
                ),
                child: Text(
                  'ตกลง',
                  style: TextStyle(
                    color: Colors.white, // สีตัวอักษร
                    fontSize: 16, // ขนาดตัวอักษร
                    fontWeight: FontWeight.bold, // ตัวหนา
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _handlePredictedEmotion(Map<String, dynamic> data) {
    print('Raw data from API: $data '); // พิมพ์ข้อมูลทั้งหมดจาก API

    if (data.containsKey('emotion_percentages') &&
        data['emotion_percentages'] != null) {
      print(
          'Emotion percentages raw data: ${data['emotion_percentages']}'); // พิมพ์ข้อมูล emotion_percentages ที่เข้ามา

      Map<String, dynamic> rawEmotionPercentages = data['emotion_percentages'];
      Map<String, double> emotionPercentages = <String, double>{};

      rawEmotionPercentages.forEach((String key, dynamic value) {
        print('Key: $key, Value: $value, Type of value: ${value.runtimeType}');
        if (value is num) {
          emotionPercentages[key] = value.toDouble();
        } else {
          print(
              'Error: Invalid data type for $key. Expected num, found ${value.runtimeType}');
        }
      });

      // ดำเนินการต่อถ้าข้อมูลถูกต้อง
      String highestEmotion = emotionPercentages.entries
          .reduce((a, b) => a.value > b.value ? a : b)
          .key;

      print('Predicted emotion: ${data['max_emotion']}');
      print('Emotion percentages: $emotionPercentages');
      print('Highest emotion: $highestEmotion');
    } else {
      print('Error: emotion_percentages is null or missing.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'sync a song',
          style: TextStyle(color: Colors.white, fontSize: 28 ,fontWeight: FontWeight.bold),
          
        ),
        backgroundColor: Color.fromARGB(255, 17, 17, 17),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _moodController,
              focusNode: _focusNode,
              style: TextStyle(color: Colors.white), // สีข้อความเป็นสีขาว
              decoration: InputDecoration(
                hintText: _isFocused ? '' : 'บอกอารมณ์ของคุณตอนนี้',
                hintStyle:
                    TextStyle(color: Colors.grey[400]), // สีตัวอักษรที่จาง
                prefixIcon:
                    Icon(Icons.search, color: Colors.white), // ไอคอนค้นหา
                suffixIcon: IconButton(
                  icon: Icon(Icons.send,
                      color: Colors.blue.shade800), // ปุ่มไอคอน "ส่ง"
                  onPressed: () {
                    _navigateToPlaylist(); // กดปุ่มแล้วเรียกฟังก์ชันค้นหา
                  },
                ),
                filled: true,
                fillColor:
                    Color.fromARGB(255, 29, 29, 29), // สีพื้นหลังของช่องค้นหา
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12), // ขอบโค้งมน
                  borderSide: BorderSide.none, // ไม่มีขอบเส้น
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: Colors.blue.shade800, // ขอบเมื่อโฟกัส
                    width: 2, // ความหนาของขอบเมื่อโฟกัส
                  ),
                ),
                contentPadding: EdgeInsets.symmetric(
                    vertical: 14, horizontal: 20), // เพิ่ม Padding
              ),
              cursorColor: Colors.blue.shade800, // สีเคอร์เซอร์
              onSubmitted: (value) {
                // จัดการเมื่อผู้ใช้กด Enter
                _navigateToPlaylist();
              },
            ),
            SizedBox(height: 20), // เพิ่มระยะห่างระหว่างช่องค้นหากับหัวข้อ
            Align(
              alignment: Alignment.centerLeft, // จัดข้อความชิดซ้าย
              child: Text(
                'เพลย์ลิสต์', // ข้อความ "เพลย์ลิสต์"
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white, // สีข้อความ
                ),
              ),
            ),
            SizedBox(height: 5),
            Column(
              children: [
                _buildPlaylistButton(
                    'อกหักทันทีเพราะมีมือที่สาม', 'assets/images/image1.jpg'),
                _buildPlaylistButton('จีบไม่เป็นเลยอยากส่งเพลงให้เธอ',
                    'assets/images/image2.jpg'),
                _buildPlaylistButton('โกรธคือโง่ โมโหก็ใส่เลยจะรอไร',
                    'assets/images/image3.jpg'),
                _buildPlaylistButton('ในใจไม่เคยมีผู้ใด จนความรักเธอเข้ามา',
                    'assets/images/image4.jpg'),
              ],
            ),
            SizedBox(
              height: 50,
            ),
            GridView.count(
              shrinkWrap: true,
              crossAxisCount: 2,
              crossAxisSpacing: 20.0,
              mainAxisSpacing: 20.0,
              childAspectRatio: 1.8,
              children: [
                _buildEmotionButton('ความรัก', 'assets/images/love.jpg'),
                _buildEmotionButton('ความสุข', 'assets/images/happiness.jpg'),
                _buildEmotionButton('ความเศร้า', 'assets/images/sadness.jpg'),
                _buildEmotionButton('ความโกรธ', 'assets/images/anger.jpg'),
              ],
            )
          ],
        ),
      ),
    );
  }

  // Widget _buildPlaylistButton(String playlistName) {
  //   return Padding(
  //     padding: const EdgeInsets.symmetric(vertical: 8.0),
  //     child: ElevatedButton(
  //       onPressed: () => _onPlaylistButtonPressed(playlistName),
  //       style: ElevatedButton.styleFrom(
  //           shape: RoundedRectangleBorder(
  //             borderRadius: BorderRadius.circular(10.0),
  //             side: BorderSide(color: Colors.black, width: 0.5),
  //           ),
  //           padding: EdgeInsets.symmetric(vertical: 10.0, horizontal: 20.0),
  //           backgroundColor: Color.fromARGB(255, 66, 66, 66)),
  //       child: Align(
  //         alignment: Alignment.centerLeft,
  //         child: Column(
  //           crossAxisAlignment: CrossAxisAlignment.start,
  //           mainAxisSize: MainAxisSize.min,
  //           children: [
  //             Text(
  //               playlistName,
  //               style: TextStyle(
  //                 color: Colors.white,
  //                 fontSize: 16.0,
  //               ),
  //             ),
  //             Text(
  //               'เพลลิสต์',
  //               style: TextStyle(
  //                 color: Colors.grey,
  //                 fontSize: 12.0,
  //               ),
  //             ),
  //           ],
  //         ),
  //       ),
  //     ),
  //   );
  // }

  Widget _buildPlaylistButton(String playlistName, String assetPath) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: ElevatedButton(
        onPressed: () => _onPlaylistButtonPressed(playlistName),
        style: ElevatedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10.0),
            // side: BorderSide(color: Colors.black, width: 0.5),
          ),
          padding: EdgeInsets.symmetric(vertical: 10.0, horizontal: 20.0),
          backgroundColor: Color.fromARGB(255, 17, 17, 17),
        ),
        child: Row(
          children: [
            // เพิ่มรูปภาพทางด้านซ้ายของข้อความ
            ClipRRect(
              borderRadius: BorderRadius.circular(0),
              child: Image.asset(
                assetPath,
                width: 45, // ความกว้างของรูปภาพ
                height: 45, // ความสูงของรูปภาพ
                fit: BoxFit.cover, // ปรับให้รูปภาพพอดีกับพื้นที่
              ),
            ),
            SizedBox(width: 20), // เว้นระยะระหว่างรูปภาพกับข้อความ
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  playlistName,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16.0,
                  ),
                ),
                Text(
                  'เพลลิสต์',
                  style: TextStyle(
                    color: Colors.grey,
                    fontSize: 12.0,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // การสร้างปุ่มอารมณ์
  Widget _buildEmotionButton(String emotion, String imagePath) {
    Gradient gradient;

    // กำหนด Gradient สำหรับแต่ละอารมณ์
    switch (emotion) {
      case 'ความรัก':
        gradient = LinearGradient(
          colors: [Colors.pink.shade300, Colors.pink.shade800],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        );
        break;
      case 'ความสุข':
        gradient = LinearGradient(
          colors: [Colors.yellow.shade300, Colors.orange.shade600],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        );
        break;
      case 'ความเศร้า':
        gradient = LinearGradient(
          colors: [Colors.blue.shade300, Colors.blue.shade900],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        );
        break;
      case 'ความโกรธ':
        gradient = LinearGradient(
          colors: [Colors.red.shade300, Colors.red.shade900],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        );
        break;
      default:
        gradient = LinearGradient(
          colors: [Colors.grey.shade300, Colors.grey.shade700],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        );
    }

    return Container(
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 8,
            offset: Offset(2, 4), // เงาเล็กน้อยเพื่อความลึก
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: () => _onEmotionButtonPressed(emotion),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent, // ทำให้พื้นหลังโปร่งใส
          shadowColor: Colors.transparent, // ลบเงาเดิมของ ElevatedButton
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12), // มุมโค้งมน
          ),
          padding: EdgeInsets.zero, // ลบ Padding ด้านในของ ElevatedButton
        ),
        child: Stack(
          children: [
            // รูปภาพเอียงอยู่ด้านล่างขวา
            Positioned(
              bottom: -14, // ปรับตำแหน่งรูปภาพ
              right: -5, // ปรับตำแหน่งรูปภาพ
              child: Transform(
                transform: Matrix4.rotationZ(0.2), // หมุนรูปภาพตามแกน Z
                alignment: Alignment.bottomRight, // จุดหมุน
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.asset(
                    imagePath,
                    width: 80, // ความกว้างของรูปภาพ
                    height: 80, // ความสูงของรูปภาพ
                    fit: BoxFit.cover, // ปรับให้รูปภาพพอดีกับพื้นที่
                  ),
                ),
              ),
            ),
            // ข้อความอยู่ด้านซ้ายบน
            Positioned(
              top: 10,
              left: 10,
              child: Text(
                emotion,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// หน้าที่ 2: หน้าที่แสดงผลเพลงตามอารมณ์และสร้างเพลย์ลิสต์
class PlaylistPage extends StatefulWidget {
  final String mood;
  final String accessToken; // รับ accessToken จากหน้าแรก
  final Map<String, double> emotionPercentages; // รับผลการพยากรณ์หลายอารมณ์

  PlaylistPage(
      {required this.mood,
      required this.emotionPercentages,
      required this.accessToken});

  @override
  _PlaylistPageState createState() => _PlaylistPageState();
}

class _PlaylistPageState extends State<PlaylistPage> {
  List<Map<String, String>> _songs = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();

    // ให้เรียกหลังจาก build เสร็จสมบูรณ์
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.emotionPercentages.isEmpty) {
        _searchSongsByMood(widget.mood);
      } else {
        _searchSongsByPredictedEmotions(widget.emotionPercentages);
      }
    });
  }

  Future<void> _searchSongsByPredictedEmotions(
      Map<String, double> emotionPercentages) async {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => LoadingPage(message: 'กำลังสร้างเพลย์ลิสต์...'),
      ),
    );

    try {
      final csvData = await rootBundle
          .loadString('assets/mood_analysis_no_wordvector_updated.csv');
      List<List<dynamic>> csvTable =
          CsvToListConverter().convert(csvData, eol: "\n");

      List<Map<String, String>> selectedSongs = [];
      int totalSongs = 50;

      emotionPercentages.forEach((emotion, percentage) {
        int numberOfSongs = (totalSongs * (percentage / 100)).round();

        List<Map<String, String>> emotionSongs = csvTable
            .where((row) => row[5].toString().contains(emotion))
            .map((row) => {
                  'songName': row[2].toString(),
                  'mood': row[5].toString(),
                })
            .toList();

        emotionSongs.shuffle();
        selectedSongs.addAll(emotionSongs.take(numberOfSongs));
      });

      if (selectedSongs.isEmpty) {
        selectedSongs.add({'songName': "ไม่พบเพลงตามอารมณ์นี้", 'mood': ""});
      }

      setState(() {
        _songs = selectedSongs;
        _isLoading = false;
      });
    } catch (error) {
      print('Error loading songs: $error');
      setState(() {
        _songs = [
          {'songName': "ไม่สามารถโหลดเพลงได้", 'mood': ""}
        ];
        _isLoading = false;
      });
    } finally {
      Navigator.pop(context); // ปิดหน้า LoadingPage ไม่ว่าจะสำเร็จหรือไม่
    }
  }

  Future<void> _searchSongsByMood(String mood) async {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            LoadingPage(message: 'กำลังค้นหาเพลงตามอารมณ์...'),
      ),
    );

    try {
      final csvData = await rootBundle
          .loadString('assets/mood_analysis_no_wordvector_updated.csv');
      List<List<dynamic>> csvTable =
          CsvToListConverter().convert(csvData, eol: "\n");

      List<Map<String, String>> songs = csvTable
          .where((row) => row[5].toString().contains(mood))
          .map((row) => {
                'songName': row[2].toString(),
                'mood': row[5].toString(),
              })
          .toList();

      songs.shuffle();
      songs = songs.take(50).toList();

      setState(() {
        _songs = songs.isNotEmpty
            ? songs
            : [
                {'songName': "ไม่พบเพลง", 'mood': ""}
              ];
        _isLoading = false;
      });
    } catch (error) {
      print('Error loading songs: $error');
      setState(() {
        _songs = [
          {'songName': "ไม่สามารถโหลดเพลงได้", 'mood': ""}
        ];
        _isLoading = false;
      });
    } finally {
      Navigator.pop(context); // ปิดหน้า LoadingPage ไม่ว่าจะสำเร็จหรือไม่
    }
  }

  Future<String?> _searchTrackUri(String songName, String? artistName) async {
    setState(() {
      _isLoading = true; // แสดง Loading Indicator
    });

    final List<String?> searchQueries = [
      artistName != null
          ? 'track:${_removeParentheses(songName)} artist:$artistName'
          : null,
      'track:$songName',
      'track:${_removeParentheses(songName)}',
      artistName != null && _extractParentheses(songName) != null
          ? 'track:${_extractParentheses(songName)} artist:$artistName'
          : null,
      artistName != null ? 'track:$songName artist:$artistName' : null,
      _extractParentheses(songName) != null
          ? 'track:${_extractParentheses(songName)}'
          : null,
      _removeSpecialCharacters(songName),
    ];

    for (int i = 0; i < searchQueries.length; i++) {
      final query = searchQueries[i];
      if (query == null) continue;

      print('Step ${i + 1}: Searching with query: $query');
      final response = await http.get(
        Uri.parse(
            'https://api.spotify.com/v1/search?q=${Uri.encodeComponent(query)}&type=track&limit=1&market=TH'),
        headers: {
          'Authorization': 'Bearer ${widget.accessToken}',
        },
      );

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        if (responseData['tracks']['items'].isNotEmpty) {
          final track = responseData['tracks']['items'][0];
          print(
              'Found Track: ${track['name']} - ${track['artists'][0]['name']}');
          return track['uri'];
        }
      } else {
        print('Error in Step ${i + 1}: ${response.body}');
      }
    }

    print('No results found for $songName ${artistName ?? ""}');
    return null;
  }

  String _removeParentheses(String songName) {
    return songName.replaceAll(RegExp(r'\(.*?\)'), '').trim();
  }

  String? _extractParentheses(String songName) {
    final match = RegExp(r'\((.*?)\)').firstMatch(songName);
    return match != null ? match.group(1)?.trim() : null;
  }

  String _removeSpecialCharacters(String songName) {
    return songName.replaceAll(RegExp(r'[^a-zA-Z0-9\s]'), '').trim();
  }

  Future<void> _createSpotifyPlaylist(BuildContext context) async {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => LoadingPage(message: 'กำลังสร้างเพลย์ลิสต์...'),
      ),
    );

    final String playlistName = 'Playlist from Mood';
    try {
      final userId = await _getUserId();

      if (userId.isNotEmpty) {
        final createPlaylistResponse = await http.post(
          Uri.parse('https://api.spotify.com/v1/users/$userId/playlists'),
          headers: {
            'Authorization': 'Bearer ${widget.accessToken}',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'name': playlistName,
            'description': 'Playlist created from Flutter app',
            'public': false,
          }),
        );

        if (createPlaylistResponse.statusCode == 201) {
          final playlistData = json.decode(createPlaylistResponse.body);
          final playlistId = playlistData['id'];

          List<String> trackUris = [];
          for (var song in _songs) {
            final splitData = song['songName']?.split(' - ') ?? [];
            final songName = splitData.isNotEmpty ? splitData[0].trim() : '';
            final artistName =
                splitData.length > 1 ? splitData[1].trim() : null;

            final trackUri = await _searchTrackUri(songName, artistName);
            if (trackUri != null) {
              trackUris.add(trackUri);
            }
          }

          if (trackUris.isNotEmpty) {
            await http.post(
              Uri.parse(
                  'https://api.spotify.com/v1/playlists/$playlistId/tracks'),
              headers: {
                'Authorization': 'Bearer ${widget.accessToken}',
                'Content-Type': 'application/json',
              },
              body: jsonEncode({'uris': trackUris}),
            );

            final url = 'https://open.spotify.com/playlist/$playlistId';
            Navigator.pop(context); // ปิด LoadingPage
            if (await canLaunch(url)) {
              await launch(url);
            } else {
              throw 'Could not launch $url';
            }
          } else {
            throw 'No valid tracks found to add to the playlist.';
          }
        } else {
          throw 'Failed to create playlist: ${createPlaylistResponse.body}';
        }
      }
    } catch (error) {
      Navigator.pop(context); // ปิด LoadingPage
      print('Error creating playlist: $error');
    }
  }

  Future<String> _getUserId() async {
    final response = await http.get(
      Uri.parse('https://api.spotify.com/v1/me'),
      headers: {
        'Authorization': 'Bearer ${widget.accessToken}',
      },
    );

    if (response.statusCode == 200) {
      final responseData = json.decode(response.body);
      return responseData['id'];
    } else {
      throw Exception(
          'Failed to fetch user ID. Status code: ${response.statusCode}');
    }
  }

  // ฟังก์ชันสำหรับสุ่มเพลงใหม่จากหลายอารมณ์
  Future<void> _shufflePredictedSongs() async {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => LoadingPage(message: 'กำลังสร้างเพลย์ลิสต์...'),
      ),
    );

    try {
      final csvData = await rootBundle
          .loadString('assets/mood_analysis_no_wordvector_updated.csv');
      List<List<dynamic>> csvTable =
          CsvToListConverter().convert(csvData, eol: "\n");

      List<Map<String, String>> selectedSongs = [];
      int totalSongs = 50;

      widget.emotionPercentages.forEach((emotion, percentage) {
        int numberOfSongs = (totalSongs * (percentage / 100)).round();

        List<Map<String, String>> emotionSongs = csvTable
            .where((row) => row[5].toString().contains(emotion))
            .map((row) => {
                  'songName': row[2].toString(),
                  'mood': row[5].toString(),
                })
            .toList();

        emotionSongs.shuffle();
        selectedSongs.addAll(emotionSongs.take(numberOfSongs));
      });

      setState(() {
        _songs = selectedSongs.isNotEmpty
            ? selectedSongs
            : [
                {'songName': "ไม่พบเพลง", 'mood': ""}
              ];
        _isLoading = false;
      });
    } catch (error) {
      print('Error loading songs: $error');
      setState(() {
        _songs = [
          {'songName': "ไม่สามารถโหลดเพลงได้", 'mood': ""}
        ];
        _isLoading = false;
      });
    } finally {
      Navigator.pop(context); // ปิดหน้า LoadingPage ไม่ว่าจะสำเร็จหรือไม่
    }
  }

  // ฟังก์ชันสำหรับโหลดเพลงใหม่แบบสุ่ม
  Future<void> _shuffleSongs(BuildContext context) async {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => LoadingPage(message: 'กำลังสุ่มเพลงใหม่...'),
      ),
    );

    try {
      final csvData = await rootBundle
          .loadString('assets/mood_analysis_no_wordvector_updated.csv');
      List<List<dynamic>> csvTable =
          CsvToListConverter().convert(csvData, eol: "\n");

      csvTable.shuffle();

      List<Map<String, String>> shuffledSongs = csvTable
          .where((row) => row[5].toString().contains(widget.mood))
          .map((row) => {
                'songName': row[2].toString(),
                'mood': row[5].toString(),
              })
          .toList();

      shuffledSongs = shuffledSongs.take(50).toList(); // จำกัดจำนวนเพลงไว้ที่ 50 เพลง

      setState(() {
        _songs = shuffledSongs.isNotEmpty
            ? shuffledSongs
            : [
                {'songName': "ไม่พบเพลง", 'mood': ""}
              ];
      });
    } catch (error) {
      print('Error loading songs: $error');
      setState(() {
        _songs = [
          {'songName': "ไม่สามารถโหลดเพลงได้", 'mood': ""}
        ];
      });
    } finally {
      Navigator.pop(context); // ปิดหน้า LoadingPage
    }
  }

  void _deleteSong(int index) {
    setState(() {
      _songs.removeAt(index);
      print("Song at index $index removed");
    });
  }

  @override
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Color.fromARGB(255, 29, 29, 29),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            Navigator.of(context).pop();
          },
        ),
        title: Text(
          '${widget.mood}',
          style: TextStyle(color: Colors.white),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            if (_songs.isNotEmpty)
              Expanded(
                child: ListView.builder(
                  itemCount: _songs.length,
                  itemBuilder: (context, index) {
                    return ListTile(
                      title: Text(
                        "${index + 1}. ${_songs[index]['songName']} (${_songs[index]['mood']})",
                        style: TextStyle(color: Colors.white),
                      ),
                      trailing: IconButton(
                        icon: Icon(Icons.delete, color: Colors.red),
                        onPressed: () {
                          _deleteSong(index);
                        },
                      ),
                    );
                  },
                ),
              ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  onPressed: () => _createSpotifyPlaylist(context),
                  icon: Icon(
                    Icons.playlist_add,
                    color: Colors.white,
                    size: 24, // ขนาดไอคอน
                  ),
                  label: Text(
                    'สร้างเพลย์ลิสต์',
                    style: TextStyle(
                      fontSize: 18, // ขนาดตัวอักษรใหญ่ขึ้น
                      fontWeight: FontWeight.bold, // ตัวหนา
                      color: Colors.white, // สีข้อความขาวล้วน
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    padding: EdgeInsets.symmetric(horizontal: 25, vertical: 15),
                    backgroundColor:
                        Colors.blue.shade800, // สีพื้นหลังน้ำเงินเข้ม
                    shadowColor: Colors.blue.shade200, // เงาสีอ่อนลง
                    elevation: 8, // ความสูงเงา
                    shape: RoundedRectangleBorder(
                      side: BorderSide(
                        color: Colors.blue.shade800, // ขอบสีขาว
                        width: 2, // ความหนาขอบ
                      ),
                      borderRadius: BorderRadius.circular(30), // มุมปุ่มโค้งมน
                    ),
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: () {
                    if (widget.emotionPercentages.isEmpty) {
                      _shuffleSongs(context);
                    } else {
                      _shufflePredictedSongs();
                    }
                  },
                  icon: Icon(
                    Icons.shuffle,
                    color: Colors.white,
                    size: 24, // ขนาดไอคอน
                  ),
                  label: Text(
                    'Shuffle',
                    style: TextStyle(
                      fontSize: 18, // ขนาดตัวอักษรใหญ่ขึ้น
                      fontWeight: FontWeight.bold, // ตัวหนา
                      color: Colors.white, // สีข้อความขาวล้วน
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    padding: EdgeInsets.symmetric(horizontal: 25, vertical: 15),
                    backgroundColor:
                        Colors.deepPurple.shade800, // สีพื้นหลังม่วงเข้ม
                    shadowColor: Colors.deepPurple.shade200, // เงาสีอ่อนลง
                    elevation: 8, // ความสูงเงา
                    shape: RoundedRectangleBorder(
                      side: BorderSide(
                        color: Colors.deepPurple.shade800, // ขอบสีขาว
                        width: 2, // ความหนาขอบ
                      ),
                      borderRadius: BorderRadius.circular(30), // มุมปุ่มโค้งมน
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
}

class LoadingPage extends StatelessWidget {
  final String message;

  LoadingPage({required this.message});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black, // พื้นหลังสีดำดูเรียบหรู
      body: Stack(
        children: [
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // ใช้ SpinKitRing แสดงแอนิเมชันโทนสีทอง
                SpinKitRing(
                  color: Color.fromARGB(255, 1, 129, 204), // สีทอง (Gold)
                  size: 80.0,
                  lineWidth: 4.0, // ความหนาของแอนิเมชัน
                ),
                SizedBox(height: 30),
                // ข้อความแสดงสถานะ
                Text(
                  message,
                  style: TextStyle(
                    color: Colors.white, // สีขาวเรียบง่าย
                    fontSize: 20,
                    fontWeight: FontWeight.w500, // ความหนาของตัวอักษร
                    fontStyle: FontStyle.italic, // เพิ่มความมีสไตล์
                    letterSpacing: 1.5, // ระยะห่างระหว่างตัวอักษร
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}