// Typed client for /v1/chat/* — the in-app AI assistant (same agent family as
// the @rvpnplus_bot). Phase A: REST request/reply, no streaming.

import 'package:dio/dio.dart';
import 'package:hiddify/core/api/app_api.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

enum ChatErrorCode { unauthorized, network, unconfigured, upstream, unknown }

class ChatApiException implements Exception {
  final ChatErrorCode code;
  final String message;
  const ChatApiException(this.code, this.message);
  @override
  String toString() => 'ChatApiException($code, $message)';
}

class ChatMessage {
  final int id;
  final String role; // "user" | "assistant"
  final String content;
  final DateTime createdAt;

  const ChatMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.createdAt,
  });

  bool get isUser => role == 'user';

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        id: json['id'] as int,
        role: json['role'] as String,
        content: json['content'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}

class SendMessageResult {
  final int sessionId;
  final ChatMessage userMessage;
  final ChatMessage assistantMessage;
  const SendMessageResult({
    required this.sessionId,
    required this.userMessage,
    required this.assistantMessage,
  });
}

class ChatApi {
  final Dio _dio;
  const ChatApi(this._dio);

  Future<List<ChatMessage>> history({
    required String accessToken,
    int limit = 50,
  }) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/chat/history',
        queryParameters: {'limit': limit},
        options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
      );
      if (response.statusCode == 200) {
        return (response.data!['messages'] as List<dynamic>)
            .cast<Map<String, dynamic>>()
            .map(ChatMessage.fromJson)
            .toList();
      }
      throw _statusError(response.statusCode);
    } on DioException catch (e) {
      throw ChatApiException(ChatErrorCode.network, e.message ?? 'Network error');
    }
  }

  Future<SendMessageResult> send({
    required String accessToken,
    required String content,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/chat/message',
        data: {'content': content},
        options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
      );
      if (response.statusCode == 200) {
        final data = response.data!;
        return SendMessageResult(
          sessionId: data['session_id'] as int,
          userMessage:
              ChatMessage.fromJson(data['user_message'] as Map<String, dynamic>),
          assistantMessage: ChatMessage.fromJson(
              data['assistant_message'] as Map<String, dynamic>),
        );
      }
      throw _statusError(response.statusCode);
    } on DioException catch (e) {
      throw ChatApiException(ChatErrorCode.network, e.message ?? 'Network error');
    }
  }

  Future<void> reset({required String accessToken}) async {
    try {
      await _dio.post<void>(
        '/chat/reset',
        options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
      );
    } on DioException catch (e) {
      throw ChatApiException(ChatErrorCode.network, e.message ?? 'Network error');
    }
  }

  ChatApiException _statusError(int? status) => switch (status) {
        401 => const ChatApiException(
            ChatErrorCode.unauthorized, 'Access token rejected'),
        503 => const ChatApiException(
            ChatErrorCode.unconfigured, 'AI chat is not configured'),
        502 => const ChatApiException(
            ChatErrorCode.upstream, 'AI is temporarily unavailable'),
        _ => ChatApiException(ChatErrorCode.unknown, 'HTTP $status'),
      };
}

final chatApiProvider = Provider<ChatApi>((ref) {
  return ChatApi(ref.watch(appApiClientProvider));
});
