import 'package:flutter/material.dart';
import '../../../../core/design_system/gochano_colors.dart';
import '../../../../core/design_system/gochano_spacing.dart';
import '../../../../core/design_system/gochano_typography.dart';
import '../../../../core/localization/gochano_language.dart';
import 'ai_conversation_service.dart';
import 'ziku_markdown_text.dart';

class ZikuAssistantPanel extends StatefulWidget {
  const ZikuAssistantPanel({
    super.key,
    this.currentDestination,
    this.appMode,
    this.onClose,
  });

  final String? currentDestination;
  final String? appMode;
  final VoidCallback? onClose;

  static Future<void> show(
    BuildContext context, {
    String? currentDestination,
    String? appMode,
  }) async {
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Ziku AI Assistant',
      barrierColor: Colors.black.withValues(alpha: 0.38),
      transitionDuration: const Duration(milliseconds: 280),
      pageBuilder: (ctx, anim1, anim2) {
        final screenWidth = MediaQuery.of(ctx).size.width;
        // Phone: 88-94% of available width. Tablet: capped at 420dp. Safe down to 320dp.
        final panelWidth = (screenWidth * 0.90).clamp(280.0, 420.0);

        return Align(
          alignment: Alignment.centerRight,
          child: SizedBox(
            width: panelWidth,
            height: double.infinity,
            child: Material(
              color: Colors.transparent,
              child: ZikuAssistantPanel(
                currentDestination: currentDestination,
                appMode: appMode,
                onClose: () => Navigator.of(ctx).maybePop(),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (ctx, anim, secondaryAnim, child) {
        final curvedAnimation = CurvedAnimation(
          parent: anim,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        // Spec §11 bans SlideTransition (decorative-motion widgets) — drive
        // the same right-edge slide off the dialog's own animation instead.
        return AnimatedBuilder(
          animation: curvedAnimation,
          builder: (context, _) {
            final offset = Tween<Offset>(
              begin: const Offset(1, 0),
              end: Offset.zero,
            ).transform(curvedAnimation.value);
            return Transform.translate(offset: offset, child: child);
          },
          child: child,
        );
      },
    );
  }

  @override
  State<ZikuAssistantPanel> createState() => _ZikuAssistantPanelState();
}

class _ZikuAssistantPanelState extends State<ZikuAssistantPanel> {
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final AiConversationService _service = AiConversationService.instance;

  @override
  void initState() {
    super.initState();
    _service.addListener(_onServiceUpdate);
  }

  @override
  void dispose() {
    _service.removeListener(_onServiceUpdate);
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onServiceUpdate() {
    if (mounted) {
      setState(() {});
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _handleSend([String? presetText]) async {
    final text = presetText ?? _inputController.text;
    if (text.trim().isEmpty || _service.loading) return;

    if (presetText == null) {
      _inputController.clear();
    }

    await _service.sendMessage(
      text,
      currentDestination: widget.currentDestination,
      appMode: widget.appMode,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20),
          bottomLeft: Radius.circular(20),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.16),
            blurRadius: 20,
            offset: const Offset(-4, 0),
          ),
        ],
      ),
      child: SafeArea(
        left: false,
        right: false,
        child: Column(
          children: [
            _buildHeader(colors, type),
            if (_service.hasActiveContext) _buildContextBar(colors, type),
            Expanded(
              child: _buildMessagesList(colors, type),
            ),
            _buildSuggestionsRow(colors, type),
            _buildComposer(colors, type),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(GochanoColors colors, GochanoTypography type) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: GochanoSpacing.md,
        vertical: GochanoSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(
          bottom: BorderSide(color: colors.border.withValues(alpha: 0.5)),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: colors.brand, width: 1.5),
            ),
            child: ClipOval(
              child: Image.asset(
                'assets/Ziku.png',
                semanticLabel: 'Ziku AI assistant avatar',
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Icon(
                  Icons.auto_awesome_rounded,
                  color: colors.brand,
                  size: 18,
                ),
              ),
            ),
          ),
          const SizedBox(width: GochanoSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Ziku AI',
                  style: type.body.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  widget.currentDestination != null
                      ? '${widget.currentDestination} assistant'
                      : GochanoLanguage.text('Your study companion', 'আপনার পড়ার সঙ্গী'),
                  style: type.caption.copyWith(color: colors.textSecondary),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: GochanoLanguage.text('Clear conversation', 'নতুন চ্যাট শুরু করুন'),
            icon: Icon(Icons.refresh_rounded, size: 20, color: colors.textSecondary),
            onPressed: () => _service.clearConversation(),
          ),
          IconButton(
            key: const ValueKey('ziku_panel_close_button'),
            tooltip: GochanoLanguage.text('Close', 'বন্ধ করুন'),
            icon: Icon(Icons.close_rounded, size: 20, color: colors.textSecondary),
            onPressed: widget.onClose ?? () => Navigator.of(context).maybePop(),
          ),
        ],
      ),
    );
  }

  Widget _buildContextBar(GochanoColors colors, GochanoTypography type) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: GochanoSpacing.md,
        vertical: 6,
      ),
      color: colors.brand.withValues(alpha: 0.08),
      child: Row(
        children: [
          Icon(Icons.description_outlined, size: 16, color: colors.brand),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _service.contextMaterialTitle ?? '',
              style: type.caption.copyWith(
                fontWeight: FontWeight.w600,
                color: colors.brand,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          InkWell(
            onTap: () => _service.clearContextMaterial(),
            child: Icon(Icons.close, size: 16, color: colors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildMessagesList(GochanoColors colors, GochanoTypography type) {
    if (_service.messages.isEmpty) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(GochanoSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: colors.brand, width: 2),
                ),
                child: ClipOval(
                  child: Image.asset(
                    'assets/Ziku.png',
                    semanticLabel: 'Ziku AI assistant avatar',
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Icon(
                      Icons.auto_awesome_rounded,
                      color: colors.brand,
                      size: 32,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: GochanoSpacing.md),
              Text(
                GochanoLanguage.text(
                  'Hello! How can I help with your studies today?',
                  'হ্যালো! আজ আপনার পড়াশোনায় কীভাবে সাহায্য করতে পারি?',
                ),
                style: type.body.copyWith(fontWeight: FontWeight.w600),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: GochanoSpacing.xs),
              Text(
                GochanoLanguage.text(
                  'Ask me to explain concepts, suggest revision schedules, or test your knowledge.',
                  'কোনো বিষয় বুঝতে, রিভিশন সাজাতে অথবা প্র্যাকটিস প্রশ্ন করতে জিজ্ঞেস করুন।',
                ),
                style: type.caption.copyWith(color: colors.textSecondary),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(GochanoSpacing.md),
      itemCount: _service.messages.length + (_service.loading ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _service.messages.length && _service.loading) {
          return _buildLoadingBubble(colors, type);
        }
        final message = _service.messages[index];
        return _buildMessageBubble(message, colors, type);
      },
    );
  }

  Widget _buildMessageBubble(
    ChatMessage message,
    GochanoColors colors,
    GochanoTypography type,
  ) {
    final isUser = message.isUser;
    final isError = message.isError;

    return Padding(
      padding: const EdgeInsets.only(bottom: GochanoSpacing.sm),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            Container(
              width: 26,
              height: 26,
              margin: const EdgeInsets.only(right: 8, top: 2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: colors.brand, width: 1.2),
              ),
              child: ClipOval(
                child: Image.asset(
                  'assets/Ziku.png',
                  semanticLabel: 'Ziku AI assistant avatar',
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Icon(
                    Icons.auto_awesome_rounded,
                    color: colors.brand,
                    size: 14,
                  ),
                ),
              ),
            ),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isUser
                    ? colors.brand
                    : (isError
                        ? colors.error.withValues(alpha: 0.1)
                        : colors.surfaceVariant),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isUser ? 16 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 16),
                ),
                border: isError
                    ? Border.all(color: colors.error.withValues(alpha: 0.4))
                    : null,
              ),
              // Assistant replies render Ziku's limited markdown (paragraphs,
              // **bold**, bullet/numbered lists). User text and errors stay
              // plain - never interpret user input as markup.
              child: (!isUser && !isError)
                  ? ZikuMarkdownText(
                      message.content,
                      style: type.body.copyWith(fontSize: 14),
                    )
                  : SelectableText(
                      message.content,
                      style: isUser
                          ? type.body.copyWith(
                              color: Colors.white,
                              fontSize: 14,
                            )
                          : type.body.copyWith(
                              color: colors.error,
                              fontSize: 14,
                            ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingBubble(GochanoColors colors, GochanoTypography type) {
    return Padding(
      padding: const EdgeInsets.only(bottom: GochanoSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26,
            height: 26,
            margin: const EdgeInsets.only(right: 8, top: 2),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: colors.brand, width: 1.2),
            ),
            child: ClipOval(
              child: Image.asset(
                'assets/Ziku.png',
                semanticLabel: 'Ziku AI assistant avatar',
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Icon(
                  Icons.auto_awesome_rounded,
                  color: colors.brand,
                  size: 14,
                ),
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: colors.surfaceVariant,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
                bottomLeft: Radius.circular(4),
                bottomRight: Radius.circular(16),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(colors.brand),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  GochanoLanguage.text('Ziku is thinking…', 'জিকু ভাবছে…'),
                  style: type.caption.copyWith(color: colors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuggestionsRow(GochanoColors colors, GochanoTypography type) {
    if (_service.loading || _service.suggestions.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: GochanoSpacing.sm,
        vertical: GochanoSpacing.xs,
      ),
      color: colors.surface.withValues(alpha: 0.5),
      child: SizedBox(
        height: 38,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: GochanoSpacing.xs),
          itemCount: _service.suggestions.length,
          separatorBuilder: (context, index) => const SizedBox(width: 8),
          itemBuilder: (context, index) {
            final suggestion = _service.suggestions[index];
            return ActionChip(
              key: ValueKey('ziku_suggestion_$index'),
              avatar: Icon(
                Icons.auto_awesome_outlined,
                size: 14,
                color: colors.brand,
              ),
              label: Text(
                suggestion,
                style: type.caption.copyWith(
                  fontSize: 12,
                  color: colors.textPrimary,
                ),
              ),
              backgroundColor: colors.surfaceVariant,
              side: BorderSide(color: colors.border.withValues(alpha: 0.5)),
              onPressed: () => _handleSend(suggestion),
            );
          },
        ),
      ),
    );
  }

  Widget _buildComposer(GochanoColors colors, GochanoTypography type) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        GochanoSpacing.md,
        GochanoSpacing.xs,
        GochanoSpacing.sm,
        GochanoSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(
          top: BorderSide(color: colors.border.withValues(alpha: 0.5)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: TextField(
                key: const ValueKey('ziku_message_input'),
                controller: _inputController,
                style: type.body.copyWith(fontSize: 14),
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _handleSend(),
                decoration: InputDecoration(
                  hintText: GochanoLanguage.text(
                    'Ask Ziku anything…',
                    'জিকুকে যেকোনো প্রশ্ন করুন…',
                  ),
                  hintStyle: type.caption.copyWith(color: colors.textSecondary),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide(color: colors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide(color: colors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide(color: colors.brand, width: 1.5),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: GochanoSpacing.xs),
            IconButton(
              key: const ValueKey('ziku_send_button'),
              tooltip: GochanoLanguage.text('Send message', 'বার্তা পাঠান'),
              icon: Icon(
                Icons.arrow_upward_rounded,
                color: _service.loading ? colors.disabled : colors.brand,
              ),
              onPressed: _service.loading ? null : () => _handleSend(),
            ),
          ],
        ),
      ),
    );
  }
}
