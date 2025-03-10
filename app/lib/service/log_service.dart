import 'dart:convert';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;

class TransferLogEntry {
  final String senderName;
  final String senderIp;
  final String receiverName;
  final String receiverIp;
  final String fileName;
  final int fileSize;
  final String fileType;
  final DateTime timestamp;
  final bool successful;

  TransferLogEntry({
    required this.senderName,
    required this.senderIp,
    required this.receiverName,
    required this.receiverIp,
    required this.fileName,
    required this.fileSize,
    required this.fileType,
    required this.timestamp,
    required this.successful,
  });

  Map<String, dynamic> toJson() {
    return {
      'senderName': senderName,
      'senderIp': senderIp,
      'receiverName': receiverName,
      'receiverIp': receiverIp,
      'fileName': fileName,
      'fileSize': fileSize,
      'fileType': fileType,
      'timestamp': timestamp.toIso8601String(),
      'successful': successful,
    };
  }
}

class LogService {
  final String _serverUrl;
  
  LogService(this._serverUrl);

  Future<bool> sendTransferLog(TransferLogEntry log) async {
    try {
      debugPrint('📤 ส่ง Log ไปยัง server: ${log.fileName}');
      final response = await http.post(
        Uri.parse('$_serverUrl/api/logs'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(log.toJson()),
      );
      
      if (response.statusCode == 200) {
        debugPrint('✅ ส่ง Log สำเร็จ');
        return true;
      } else {
        debugPrint('❌ ส่ง Log ล้มเหลว: Status code ${response.statusCode}');
        return false;
      }
    } catch (e) {
      debugPrint('❌ เกิดข้อผิดพลาดขณะส่ง Log: $e');
      return false;
    }
  }
}
