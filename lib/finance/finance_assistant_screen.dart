import 'package:flutter/material.dart';

import '../branding.dart';
import 'finance_assistant.dart';

class MadsConversationScreen extends StatefulWidget {
  final MadsFinanceContext contextData;
  final MadsAssistant assistant;
  final String? initialQuestion;

  const MadsConversationScreen({
    super.key,
    required this.contextData,
    required this.assistant,
    this.initialQuestion,
  });

  @override
  State<MadsConversationScreen> createState() => _MadsConversationScreenState();
}

class _MadsConversationScreenState extends State<MadsConversationScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  late final List<MadsConversationMessage> _messages;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    final hasProfile =
        widget.contextData.facts['monthlyIncome'] != null ||
        widget.contextData.facts['balanceSnapshot'] != null;
    _messages = [
      MadsConversationMessage(
        role: 'assistant',
        content: hasProfile
            ? "Hey! Your money profile is ready. How's your month going? Ask me anything, and I'll be clear when something isn't in your records."
            : "Hi! What's on your mind? I'll use only the details you've saved and let you know when I need more information.",
      ),
    ];
    final question = widget.initialQuestion?.trim();
    if (question != null && question.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _send(question));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _send([String? suppliedText]) async {
    if (_sending) return;
    final text = (suppliedText ?? _controller.text).trim();
    if (text.isEmpty) return;

    _controller.clear();
    setState(() {
      _messages.add(MadsConversationMessage(role: 'user', content: text));
      _sending = true;
    });
    _scrollToLatest();

    try {
      final history = _messages.length > 17
          ? _messages.sublist(_messages.length - 17)
          : List<MadsConversationMessage>.of(_messages);
      final reply = await widget.assistant.reply(
        context: widget.contextData,
        conversation: history,
      );
      if (!mounted) return;
      setState(() {
        _messages.add(
          MadsConversationMessage(role: 'assistant', content: reply),
        );
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _messages.add(
          const MadsConversationMessage(
            role: 'assistant',
            content: "I can't reach your finance companion right now. Your profile hasn't changed. Please try again in a moment.",
          ),
        );
      });
    } finally {
      if (mounted) {
        setState(() => _sending = false);
        _scrollToLatest();
      }
    }
  }

  void _scrollToLatest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Money Angel'),
          Text(
            'Your finance pal.',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
          ),
        ],
      ),
    ),
    body: SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 0),
            child: Text(
              'When you send a message, Money Angel shares your saved finance summary and chat with its AI service to prepare a reply.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(18, 20, 18, 16),
              itemCount: _messages.length + (_sending ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == _messages.length) {
                  return const _AssistantBubble(
                    message: 'Let me look at the information you shared…',
                    isAssistant: true,
                  );
                }
                final message = _messages[index];
                return _AssistantBubble(
                  message: message.content,
                  isAssistant: message.role == 'assistant',
                );
              },
            ),
          ),
          _composer(context),
        ],
      ),
    ),
  );

  Widget _composer(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: TextField(
            controller: _controller,
            minLines: 1,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => _send(),
            decoration: InputDecoration(
              hintText: 'Ask anything about your money…',
              filled: true,
              fillColor: Theme.of(context).colorScheme.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(24),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 13,
              ),
            ),
          ),
        ),
        const SizedBox(width: 9),
        IconButton.filled(
          tooltip: 'Send message',
          onPressed: _sending ? null : _send,
          icon: const Icon(Icons.arrow_upward_rounded),
        ),
      ],
    ),
  );
}

class _AssistantBubble extends StatelessWidget {
  final String message;
  final bool isAssistant;

  const _AssistantBubble({required this.message, required this.isAssistant});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Align(
      alignment: isAssistant ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 330),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isAssistant ? colors.surface : forestGreen,
          borderRadius: BorderRadius.circular(19),
        ),
        child: Text(
          message,
          style: TextStyle(
            color: isAssistant ? colors.onSurface : Colors.white,
            height: 1.4,
          ),
        ),
      ),
    );
  }
}
