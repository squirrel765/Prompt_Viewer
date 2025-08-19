import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
    AndroidInitializationSettings('@mipmap/ic_launcher'); // 앱 아이콘 사용

    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
    );

    await _notificationsPlugin.initialize(initializationSettings);
  }

  Future<void> showProgressNotification(int maxProgress, int currentProgress, String status) async {
    final AndroidNotificationDetails androidPlatformChannelSpecifics =
    AndroidNotificationDetails(
      'gallery_sync_channel', // 채널 ID
      '갤러리 동기화', // 채널 이름
      channelDescription: '갤러리 폴더 동기화 진행 상태를 표시합니다.', // 채널 설명
      importance: Importance.low, // 중요도를 낮게 설정하여 소리나 진동 최소화
      priority: Priority.low,
      showProgress: true,
      maxProgress: maxProgress,
      progress: currentProgress,
      ongoing: true, // 사용자가 지울 수 없는 지속적인 알림
      onlyAlertOnce: true, // 최초에만 알림음 발생
    );
    final NotificationDetails platformChannelSpecifics =
    NotificationDetails(android: androidPlatformChannelSpecifics);

    await _notificationsPlugin.show(
      0, // 알림 ID
      '갤러리 동기화 중...',
      status,
      platformChannelSpecifics,
    );
  }

  Future<void> showCompletionNotification(String message) async {
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
    AndroidNotificationDetails(
      'gallery_sync_channel',
      '갤러리 동기화',
      channelDescription: '갤러리 폴더 동기화 진행 상태를 표시합니다.',
      importance: Importance.defaultImportance, // 완료 시에는 기본 중요도
      priority: Priority.defaultPriority,
      ongoing: false, // 이제 지울 수 있음
      onlyAlertOnce: true,
    );
    const NotificationDetails platformChannelSpecifics =
    NotificationDetails(android: androidPlatformChannelSpecifics);
    await _notificationsPlugin.show(
      0,
      '갤러리 동기화 완료',
      message,
      platformChannelSpecifics,
    );
  }

  Future<void> cancelNotification() async {
    await _notificationsPlugin.cancel(0);
  }
}