// R-VPN+ AI assistant — full-screen cosmic chat backed by /v1/chat/*.
// Phase A: text request/reply. (Phase B will render tool-driven action
// buttons / deep-links for full parity with the bot agent.)

import 'package:flutter/material.dart';
import 'package:hiddify/core/api/chat_api.dart';
import 'package:hiddify/core/theme/cosmic_palette.dart';
import 'package:hiddify/features/auth/notifier/auth_notifier.dart';
import 'package:hiddify/features/common/cosmic_background.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

class ChatPage extends ConsumerStatefulWidget {
  const ChatPage({super.key});

  @override
  ConsumerState<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends ConsumerState<ChatPage> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final List<ChatMessage> _messages = [];
  // Actions (e.g. pay links) the assistant attached to a given message id.
  final Map<int, List<ChatAction>> _actions = {};
  bool _loadingHistory = true;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  String? get _token {
    final auth = ref.read(authNotifierProvider);
    return auth is AuthAuthenticated ? auth.accessToken : null;
  }

  Future<void> _loadHistory() async {
    final token = _token;
    if (token == null) {
      setState(() => _loadingHistory = false);
      return;
    }
    try {
      final msgs = await ref.read(chatApiProvider).history(accessToken: token);
      if (!mounted) return;
      setState(() {
        _messages
          ..clear()
          ..addAll(msgs);
        _loadingHistory = false;
      });
      _jumpToBottom();
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingHistory = false);
    }
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    final token = _token;
    if (text.isEmpty || _sending || token == null) return;

    setState(() {
      _error = null;
      _sending = true;
      _messages.add(ChatMessage(
        id: -DateTime.now().millisecondsSinceEpoch,
        role: 'user',
        content: text,
        createdAt: DateTime.now(),
      ));
      _input.clear();
    });
    _jumpToBottom();

    try {
      final res = await ref.read(chatApiProvider).send(accessToken: token, content: text);
      if (!mounted) return;
      setState(() {
        // Replace the optimistic user bubble with the persisted pair.
        _messages
          ..removeWhere((m) => m.id < 0)
          ..add(res.userMessage)
          ..add(res.assistantMessage);
        if (res.actions.isNotEmpty) {
          _actions[res.assistantMessage.id] = res.actions;
        }
        _sending = false;
      });
      _jumpToBottom();
    } on ChatApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = switch (e.code) {
          ChatErrorCode.unauthorized => 'Сессия истекла. Войдите заново.',
          ChatErrorCode.network => 'Нет связи с сервером.',
          ChatErrorCode.unconfigured => 'AI-чат временно недоступен.',
          ChatErrorCode.upstream => 'AI перегружен, попробуйте ещё раз.',
          ChatErrorCode.unknown => 'Не удалось отправить: ${e.message}',
        };
      });
    }
  }

  Future<void> _reset() async {
    final token = _token;
    if (token == null) return;
    try {
      await ref.read(chatApiProvider).reset(accessToken: token);
    } catch (_) {/* best-effort */}
    if (!mounted) return;
    setState(() {
      _messages.clear();
      _actions.clear();
    });
  }

  void _jumpToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent + 120,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Row(
          children: [
            ClipOval(
              child: Image.asset('assets/images/rocket_badge.png',
                  width: 30, height: 30, fit: BoxFit.cover),
            ),
            const SizedBox(width: 10),
            const Text('Ассистент R-VPN+'),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Новый разговор',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _messages.isEmpty ? null : _reset,
          ),
        ],
      ),
      body: CosmicBackground(
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              Expanded(
                child: _loadingHistory
                    ? const Center(child: CircularProgressIndicator())
                    : _messages.isEmpty
                        ? const _EmptyChat()
                        : ListView.builder(
                            controller: _scroll,
                            padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
                            itemCount: _messages.length + (_sending ? 1 : 0),
                            itemBuilder: (context, i) {
                              if (_sending && i == _messages.length) {
                                return const _TypingBubble();
                              }
                              final m = _messages[i];
                              return _Bubble(message: m, actions: _actions[m.id]);
                            },
                          ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Text(_error!,
                      style: TextStyle(color: theme.colorScheme.error, fontSize: 13)),
                ),
              _Composer(controller: _input, sending: _sending, onSend: _send),
            ],
          ),
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message, this.actions});
  final ChatMessage message;
  final List<ChatAction>? actions;

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    final acts = actions ?? const <ChatAction>[];
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment:
            isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Container(
            constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.78),
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              gradient: isUser
                  ? const LinearGradient(colors: [Cosmic.violet, Cosmic.violetBright])
                  : null,
              color: isUser ? null : Cosmic.card,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: Radius.circular(isUser ? 16 : 4),
                bottomRight: Radius.circular(isUser ? 4 : 16),
              ),
              border: isUser
                  ? null
                  : Border.all(color: Colors.white.withValues(alpha: .06)),
            ),
            child: Text(
              message.content,
              style: const TextStyle(color: Cosmic.text, fontSize: 15, height: 1.35),
            ),
          ),
          for (final a in acts)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: FilledButton.icon(
                icon: const Icon(Icons.open_in_new_rounded, size: 18),
                label: Text(a.label),
                onPressed: () => launchUrl(Uri.parse(a.value),
                    mode: LaunchMode.externalApplication),
              ),
            ),
        ],
      ),
    );
  }
}

class _TypingBubble extends StatelessWidget {
  const _TypingBubble();
  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Cosmic.card,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomLeft: Radius.circular(4),
            bottomRight: Radius.circular(16),
          ),
          border: Border.all(color: Colors.white.withValues(alpha: .06)),
        ),
        child: const SizedBox(
          width: 28,
          height: 14,
          child: Center(
            child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyChat extends StatelessWidget {
  const _EmptyChat();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ClipOval(
              child: Image.asset('assets/images/rocket_badge.png',
                  width: 72, height: 72, fit: BoxFit.cover),
            ),
            const SizedBox(height: 20),
            const Text(
              'Спросите ассистента',
              style: TextStyle(
                  color: Cosmic.text, fontSize: 20, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            const Text(
              'Подписка, оплата, подключение, серверы —\nпомогу разобраться.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Cosmic.text2, fontSize: 14, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.sending,
    required this.onSend,
  });
  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: const BoxDecoration(
        color: Cosmic.section,
        border: Border(top: BorderSide(color: Color(0x14FFFFFF))),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 5,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onSend(),
                decoration: const InputDecoration(
                  hintText: 'Сообщение…',
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Material(
              color: Cosmic.violet,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: sending ? null : onSend,
                child: const Padding(
                  padding: EdgeInsets.all(12),
                  child: Icon(Icons.send_rounded, color: Colors.white, size: 20),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
