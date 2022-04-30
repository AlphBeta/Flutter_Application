import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_signin/screens/signin_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

String greetings = " ";
String risk = " ";

class _HomeScreenState extends State<HomeScreen> {
  String role = 'user';
  String username = ' ';
  String welcome_msg = 'Welcome';
  String? mtoken = " ";

  @override
  void initState() {
    super.initState();
    loadFCM();
    listenFCM();
    getToken();
    _checkRole();
  }

  late AndroidNotificationChannel channel;
  late FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin;

  void _checkRole() async {
    User? user = FirebaseAuth.instance.currentUser;
    final DocumentSnapshot snap = await FirebaseFirestore.instance
        .collection('users')
        .doc(user!.uid)
        .get();

    setState(() {
      role = snap['role'];
      username = snap['username'];
    });

    if (role == 'user') {
      welcome_msg = 'Welcome';
    } else if (role == 'admin') {
      welcome_msg = 'Welcome Admin';
    }
  }

  void sendPushMessage() async {
    try {
      await http.post(
        Uri.parse('https://fcm.googleapis.com/fcm/send'),
        headers: <String, String>{
          'Content-Type': 'application/json',
          'Authorization':
              'key=AAAAEyS1P4E:APA91bH7u0m4a7X7SqlJ0anFQ3hOpiud8oelz1QLoOkTPFBVvcGPRD3ZtnlIFRSAZK_824Geow7jNTv41ZZVnXtILwbidJ4exQLVvxNV-kjd3GgSg29hlSyYvDPk6UxTsCOe3fs3KWBV',
        },
        body: jsonEncode(
          <String, dynamic>{
            'notification': <String, dynamic>{
              'body': 'Fault Type: $greetings \n Severity: $risk',
              'title': 'Fault Occured! '
            },
            'priority': 'high',
            'data': <String, dynamic>{
              'click_action': 'FLUTTER_NOTIFICATION_CLICK',
              'id': '1',
              'status': 'done'
            },
            "to": "$mtoken",
          },
        ),
      );
    } catch (e) {
      print("error push notification");
    }
  }

  void saveToken(String token) async {
    User? user = FirebaseAuth.instance.currentUser;
    await FirebaseFirestore.instance
        .collection("UserTokens")
        .doc(user!.uid)
        .set({
      'token': token,
    });
  }

  void getToken() async {
    await FirebaseMessaging.instance.getToken().then((token) {
      setState(() {
        mtoken = token;
      });

      saveToken(token!);
    });
  }

  void listenFCM() async {
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      RemoteNotification? notification = message.notification;
      AndroidNotification? android = message.notification?.android;
      if (notification != null && android != null && !kIsWeb) {
        flutterLocalNotificationsPlugin.show(
          notification.hashCode,
          notification.title,
          notification.body,
          NotificationDetails(
            android: AndroidNotificationDetails(
              channel.id,
              channel.name,
              // TODO add a proper drawable resource to android, for now using
              //      one that already exists in example app.
              icon: 'launch_background',
            ),
          ),
        );
      }
    });
  }

  void loadFCM() async {
    if (!kIsWeb) {
      channel = const AndroidNotificationChannel(
        'high_importance_channel', // id
        'High Importance Notifications', // title
        importance: Importance.high,
        enableVibration: true,
      );

      flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

      /// Create an Android Notification Channel.
      ///
      /// We use this channel in the `AndroidManifest.xml` file to override the
      /// default FCM channel to enable heads up notifications.
      await flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);

      /// Update the iOS foreground notification presentation options to allow
      /// heads up notifications.
      await FirebaseMessaging.instance
          .setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: Text('Transmission Line Fault Detection'),
        centerTitle: true,
        backgroundColor: Color.fromRGBO(203, 43, 147, 1),
      ),
      body: Center(
        child: Container(
          padding: EdgeInsets.all(116),
          decoration: const BoxDecoration(
            image: DecorationImage(
              image: AssetImage("assets/images/tl-1.jpg"),
              fit: BoxFit.fill,
              opacity: 0.7,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: <Widget>[
              Text(
                welcome_msg + " " + username,
                style: TextStyle(fontSize: 24),
              ),
              Text(greetings, style: TextStyle(fontSize: 24)),
              ElevatedButton(
                onPressed: () async {
                  notify_user();
                },
                child: Text('Refresh', style: TextStyle(fontSize: 24)),
              ),
              ElevatedButton(
                child: Text("Logout", style: TextStyle(fontSize: 24)),
                onPressed: () {
                  FirebaseAuth.instance.signOut().then((value) {
                    Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (context) => SignInScreen()));
                  });
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future notify_user() async {
    Timer _timer = Timer.periodic(Duration(seconds: 10), (timer) async {
      if (FirebaseAuth.instance.currentUser != null) {
        final response = await http.get(Uri.parse('http://10.0.2.2:5000/'));
        //getting the response from our backend server script
        //we can add sleep to make the app wait for a while before displaying the response
        final decoded = json.decode(response.body) as Map<String, dynamic>;
        //converting it from json to key value pair
        setState(() {
          greetings = decoded['query'];
        });

        if (greetings != 'Normal' &&
            (greetings == 'A-G' || greetings == 'B-G' || greetings == 'C-G')) {
          risk = 'High';
          sendPushMessage();
        } else if (greetings == 'A-B-G' ||
            greetings == 'B-C-G' ||
            greetings == 'C-A-G') {
          risk = 'Moderate';
        } else {
          risk = 'Low';
          sendPushMessage();
        }
      } else if (FirebaseAuth.instance.currentUser == null) {
        greetings = '';
        return ;
      }
    });
  }
}