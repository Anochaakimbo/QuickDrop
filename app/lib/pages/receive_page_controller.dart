import 'package:common/model/device.dart';
import 'package:common/model/session_status.dart';
import 'package:dart_mappable/dart_mappable.dart';
import 'package:localsend_app/model/persistence/receive_history_entry.dart';
import 'package:localsend_app/pages/progress_page.dart';
import 'package:localsend_app/pages/receive_page.dart';
import 'package:localsend_app/provider/local_ip_provider.dart'; // Add this import
import 'package:localsend_app/provider/network/server/server_provider.dart';
import 'package:localsend_app/provider/selection/selected_receiving_files_provider.dart';
import 'package:localsend_app/provider/settings_provider.dart';
import 'package:localsend_app/service/log_service.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:routerino/routerino.dart';


part 'receive_page_controller.mapper.dart';

// ปรับปรุง provider ใน receive_page_controller.dart
final logServiceProvider = Provider<LogService>((ref) {
  // ตั้งค่า URL ของ Web Server
  return LogService('http://localhost:3000');
});


@MappableClass()
class ReceivePageVm with ReceivePageVmMappable {
  final SessionStatus? status;
  final Device sender;

  /// Show hashtag and device model.
  final bool showSenderInfo;
  final int fileCount;
  final String? message;
  final bool isLink;
  final bool showFullIp;
  final void Function() onAccept;
  final void Function() onDecline;
  final void Function() onClose;

  ReceivePageVm({
    required this.status,
    required this.sender,
    required this.showSenderInfo,
    required this.fileCount,
    required this.message,
    required this.isLink,
    required this.showFullIp,
    required this.onAccept,
    required this.onDecline,
    required this.onClose,
  });
}

final receivePageControllerProvider = ReduxProvider<ReceivePageController, ReceivePageVm>((ref) {
  return ReceivePageController(
    server: ref.notifier(serverProvider),
    selectedReceivingFiles: ref.notifier(selectedReceivingFilesProvider),
    ref: ref, // ส่ง ref
  );
});

class ReceivePageController extends ReduxNotifier<ReceivePageVm> {
  final ServerService _server;
  final SelectedReceivingFilesNotifier _selectedReceivingFiles;
  final Ref _ref; // เพิ่ม ref

  ReceivePageController({
    required ServerService server,
    required SelectedReceivingFilesNotifier selectedReceivingFiles,
    required Ref ref, // เพิ่ม parameter
  })  : _server = server,
        _selectedReceivingFiles = selectedReceivingFiles,
        _ref = ref; // กำหนดค่า ref

  @override
  ReceivePageVm init() {
    return ReceivePageVm(
      status: SessionStatus.waiting,
      sender: const Device(
        ip: '0.0.0.0',
        version: '1.0.0',
        port: 8080,
        https: false,
        fingerprint: 'fingerprint',
        alias: 'alias',
        deviceModel: 'deviceModel',
        deviceType: DeviceType.desktop,
        download: true,
      ),
      showSenderInfo: true,
      fileCount: 1,
      message: 'message',
      isLink: false,
      showFullIp: false,
      onAccept: () {},
      onDecline: () {},
      onClose: () {},
    );
  }

  @override
  get initialAction => _WatchStatusAction();
}

class _WatchStatusAction extends WatchAction<ReceivePageController, ReceivePageVm> {
  @override
  ReceivePageVm reduce() {
    return state.copyWith(
      status: ref.watch(serverProvider.select((state) => state?.session?.status)),
    );
  }
}

class InitReceivePageAction extends ReduxAction<ReceivePageController, ReceivePageVm> {
  @override
  ReceivePageVm reduce() {
    final receiveSession = notifier._server.state?.session;
    if (receiveSession == null) {
      return state;
    }

    return state.copyWith(
      sender: receiveSession.sender,
      showSenderInfo: true,
      fileCount: receiveSession.files.length,
      message: receiveSession.message,
      isLink: receiveSession.message != null && (receiveSession.message!.isLink),
      showFullIp: false,
      onAccept: () async {
        if (state.message != null) {
          // accept nothing
          notifier._server.acceptFileRequest({});
          return;
        }

        final sessionId = notifier._server.state?.session?.sessionId;
        if (sessionId == null) {
          return;
        }

        final selectedFiles = notifier._selectedReceivingFiles.state;
        notifier._server.acceptFileRequest(selectedFiles);

        // ส่ง Log เมื่อรับไฟล์
        final session = notifier._server.state?.session;
        if (session != null) {
          for (final fileEntry in selectedFiles.entries) {
            final file = session.files[fileEntry.key]?.file;
            if (file != null) {
              // Get the local IP from the localIpProvider using ref instead of context
              final networkState = notifier._ref.read(localIpProvider);
              final localIp = networkState.localIps.isNotEmpty ? networkState.localIps.first : '0.0.0.0';
              
              final logEntry = TransferLogEntry(
                senderName: session.sender.alias,
                senderIp: session.sender.ip,
                receiverName: notifier._ref.read(settingsProvider).alias,
                receiverIp: localIp,
                fileName: file.fileName,
                fileSize: file.size,
                fileType: file.fileType.name,
                timestamp: DateTime.now(),
                successful: true,
              );
        
              try {
                // ส่ง Log ไปยัง Server
                final logService = notifier._ref.read(logServiceProvider);
                await logService.sendTransferLog(logEntry);
              } catch (e) {
                // จัดการข้อผิดพลาดในการส่ง log
                print('Error sending log: $e');
              }
            } else {
              print('File not found for key: ${fileEntry.key}');
            }
          }
        } else {
          print('Session is null');
        }

        await Routerino.context.pushAndRemoveUntilImmediately(
          removeUntil: ReceivePage,
          builder: () => ProgressPage(
            showAppBar: false,
            closeSessionOnClose: true,
            sessionId: sessionId,
          ),
        );
      },
      onDecline: () {
        notifier._server.declineFileRequest();
      },
      onClose: () {
        notifier._server.closeSession();
      },
    );
  }
}

class InitReceivePageFromHistoryMessageAction extends ReduxAction<ReceivePageController, ReceivePageVm> {
  final ReceiveHistoryEntry entry;

  InitReceivePageFromHistoryMessageAction({required this.entry});

  @override
  ReceivePageVm reduce() {
    return state.copyWith(
      sender: Device(
        ip: '0.0.0.0',
        version: '1.0.0',
        port: 8080,
        https: false,
        fingerprint: 'fingerprint',
        alias: entry.senderAlias,
        deviceModel: 'deviceModel',
        deviceType: DeviceType.web,
        download: true,
      ),
      showSenderInfo: false,
      fileCount: 1,
      message: entry.fileName,
      isLink: entry.fileName.isLink,
      showFullIp: false,
      onAccept: () {},
      onDecline: () {},
      onClose: () {},
    );
  }
}

class SetShowFullIpAction extends ReduxAction<ReceivePageController, ReceivePageVm> {
  final bool showFullIp;

  SetShowFullIpAction(this.showFullIp);

  @override
  ReceivePageVm reduce() {
    return state.copyWith(
      showFullIp: showFullIp,
    );
  }
}

extension on String {
  bool get isLink => Uri.tryParse(this)?.isAbsolute ?? false;
}

