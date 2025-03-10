import 'dart:async';
import 'package:common/model/device.dart';
import 'package:common/model/session_status.dart';
import 'package:flutter/material.dart';
import 'package:localsend_app/config/theme.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/pages/receive_page_controller.dart';
import 'package:localsend_app/provider/device_info_provider.dart';
import 'package:localsend_app/provider/favorites_provider.dart';
import 'package:localsend_app/provider/network/send_provider.dart';
import 'package:localsend_app/service/log_service.dart';
import 'package:localsend_app/util/favorites.dart';
import 'package:localsend_app/util/native/taskbar_helper.dart';
import 'package:localsend_app/widget/animations/initial_fade_transition.dart';
import 'package:localsend_app/widget/animations/initial_slide_transition.dart';
import 'package:localsend_app/widget/dialogs/error_dialog.dart';
import 'package:localsend_app/widget/list_tile/device_list_tile.dart';
import 'package:localsend_app/widget/responsive_list_view.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:routerino/routerino.dart';

class SendPage extends StatefulWidget {
  final bool showAppBar;
  final bool closeSessionOnClose;
  final String sessionId;

  const SendPage({
    required this.showAppBar,
    required this.closeSessionOnClose,
    required this.sessionId,
  });

  @override
  State<SendPage> createState() => _SendPageState();
}

class _SendPageState extends State<SendPage> with Refena {
  Device? _myDevice;
  Device? _targetDevice;

  @override
  void dispose() {
    super.dispose();
    unawaited(TaskbarHelper.clearProgressBar());
  }

  void _cancel() {
    final myDevice = ref.read(deviceFullInfoProvider);
    final sendState = ref.read(sendProvider)[widget.sessionId];
    if (sendState == null) return;

    setState(() {
      _myDevice = myDevice;
      _targetDevice = sendState.target;
    });

    ref.notifier(sendProvider).cancelSession(widget.sessionId);
  }

  /// 📌 **ฟังก์ชันบันทึก Log ไปยัง Web Server**
  Future<void> _sendTransferLog() async {
  final sendState = ref.read(sendProvider)[widget.sessionId];
  if (sendState == null) return;

  final myDevice = ref.read(deviceFullInfoProvider);
  final targetDevice = sendState.target;
  final logService = ref.read(logServiceProvider); // ใช้ provider แทนการสร้างอินสแตนซ์ใหม่
  

  for (final entry in sendState.files.entries) {
    final file = entry.value;
    
    final fileExtension = file.file.fileName.contains('.')
        ? file.file.fileName.substring(file.file.fileName.lastIndexOf('.') + 1).toLowerCase()
        : 'unknown';

    final logEntry = TransferLogEntry(
      senderName: myDevice.alias,
      senderIp: myDevice.ip,
      receiverName: targetDevice.alias,
      receiverIp: targetDevice.ip,
      fileName: file.file.fileName,
      fileSize: file.file.size,
      fileType: fileExtension, // ใช้ extension แทน
      timestamp: DateTime.now(),
      successful: sendState.status == SessionStatus.finished,
    );

    try {
      // ส่ง Log ไปยัง Server ผ่าน HTTP API
      final success = await logService.sendTransferLog(logEntry);
      
      if (success) {
        // ส่ง Log ไปยัง WebSocket เพื่อให้ได้ real-time update
        
        debugPrint('📦 Log การส่งไฟล์ถูกส่งไปยังเซิร์ฟเวอร์: ${file.file.fileName}');
      } else {
        debugPrint('⚠️ ไม่สามารถส่ง Log ไปยังเซิร์ฟเวอร์: ${file.file.fileName}');
      }
    } catch (e) {
      debugPrint('❌ เกิดข้อผิดพลาดในการส่ง Log: $e');
    }
  }
}

  @override
  Widget build(BuildContext context) {
    final sendState = ref.watch(sendProvider.select((state) => state[widget.sessionId]), listener: (prev, next) {
      final prevStatus = prev[widget.sessionId]?.status;
      final nextStatus = next[widget.sessionId]?.status;
      if (prevStatus != nextStatus) {
        // ignore: discarded_futures
        TaskbarHelper.visualizeStatus(nextStatus);
      }
    });

    if (sendState == null && _myDevice == null && _targetDevice == null) {
      return Scaffold(body: Container());
    }

    final myDevice = ref.watch(deviceFullInfoProvider);
    final targetDevice = sendState?.target ?? _targetDevice!;
    final targetFavoriteEntry = ref.watch(favoritesProvider.select((state) => state.findDevice(targetDevice)));
    final waiting = sendState?.status == SessionStatus.waiting;

    return PopScope(
      onPopInvokedWithResult: (didPop, result) {
        if (didPop && widget.closeSessionOnClose) {
          _cancel();
        }
      },
      canPop: true,
      child: Scaffold(
        appBar: widget.showAppBar ? AppBar() : null,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: ResponsiveListView.defaultMaxWidth),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 30),
                child: Column(
                  children: [
                    Expanded(
                      child: Column(
                        children: [
                          InitialSlideTransition(
                            origin: const Offset(0, -1),
                            duration: const Duration(milliseconds: 400),
                            child: DeviceListTile(device: myDevice),
                          ),
                          const SizedBox(height: 20),
                          const InitialFadeTransition(
                            duration: Duration(milliseconds: 300),
                            delay: Duration(milliseconds: 400),
                            child: Icon(Icons.arrow_downward),
                          ),
                          const SizedBox(height: 20),
                          Hero(
                            tag: 'device-${targetDevice.ip}',
                            child: DeviceListTile(
                              device: targetDevice,
                              nameOverride: targetFavoriteEntry?.alias,
                            ),
                          ),
                        ],
                      ),
                    ),

                    /// ✅ **อัปเดต UI ให้แสดงผลเมื่อส่งไฟล์สำเร็จ**
                    if (sendState != null)
                      InitialFadeTransition(
                        duration: const Duration(milliseconds: 300),
                        delay: const Duration(milliseconds: 400),
                        child: Column(
                          children: [
                            if (sendState.status == SessionStatus.finished)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 20),
                                child: Text(
                                  '✅ ไฟล์ถูกส่งสำเร็จ!',
                                  style: TextStyle(color: Theme.of(context).colorScheme.primary),
                                  textAlign: TextAlign.center,
                                ),
                              ),

                            /// 📌 **เรียก `_sendTransferLog()` ก่อนปิดหน้า**
                            Center(
                              child: FilledButton.icon(
                                onPressed: () async {
                                  if (sendState?.status == SessionStatus.finished) {
                                    await _sendTransferLog(); // ✅ บันทึก Log
                                  }
                                  if (!mounted) return; // ✅ ป้องกัน BuildContext error
                                  _cancel();
                                  context.pop();
                                },
                                icon: Icon(waiting ? Icons.close : Icons.check_circle),
                                label: Text(waiting ? t.general.cancel : t.general.close),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
