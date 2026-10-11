import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:tmlink/core/app_controller.dart';

class Panel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  const Panel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(24),
  });
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: padding,
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(
        color: Theme.of(context).dividerColor.withValues(alpha: .35),
      ),
    ),
    child: child,
  );
}

class PageHeading extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget? action;
  const PageHeading({
    super.key,
    required this.title,
    required this.subtitle,
    this.action,
  });
  @override
  Widget build(BuildContext context) {
    final heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.headlineLarge),
        const SizedBox(height: 6),
        Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) => constraints.maxWidth >= 650
          ? Row(
              children: [
                Expanded(child: heading),
                if (action != null) ...[const SizedBox(width: 24), action!],
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                heading,
                if (action != null) ...[const SizedBox(height: 16), action!],
              ],
            ),
    );
  }
}

class StatusBadge extends StatelessWidget {
  final ServiceState state;
  final String? label;
  const StatusBadge({super.key, required this.state, this.label});
  @override
  Widget build(BuildContext context) {
    final color = switch (state) {
      ServiceState.connected =>
        Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF30D158)
            : const Color(0xFF248A3D),
      ServiceState.connecting => const Color(0xFF007AFF),
      ServiceState.failed => const Color(0xFFD14343),
      ServiceState.disconnected => Theme.of(
        context,
      ).colorScheme.onSurfaceVariant,
    };
    final text =
        label ??
        switch (state) {
          ServiceState.connected => 'Connected',
          ServiceState.connecting => 'Connecting',
          ServiceState.failed => 'Needs attention',
          ServiceState.disconnected => 'Not connected',
        };
    return Semantics(
      label: text,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .10),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (state == ServiceState.connecting)
              SizedBox(
                width: 9,
                height: 9,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: color,
                ),
              )
            else
              Icon(CupertinoIcons.circle_fill, color: color, size: 7),
            const SizedBox(width: 6),
            Text(
              text,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class NoticeBanner extends StatelessWidget {
  final String message;
  final VoidCallback? onDismiss;
  const NoticeBanner({super.key, required this.message, this.onDismiss});
  @override
  Widget build(BuildContext context) => Panel(
    padding: const EdgeInsets.all(16),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(
          CupertinoIcons.info_circle,
          color: Color(0xFFD48100),
          size: 20,
        ),
        const SizedBox(width: 12),
        Expanded(child: SelectableText(message)),
        if (onDismiss != null)
          IconButton(
            tooltip: 'Dismiss message',
            onPressed: onDismiss,
            icon: const Icon(CupertinoIcons.xmark, size: 14),
          ),
      ],
    ),
  );
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final Widget? action;
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 36,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 7),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (action != null) ...[const SizedBox(height: 18), action!],
        ],
      ),
    ),
  );
}

class SecretField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final String? helper;
  final bool enabled;
  final ValueChanged<String>? onChanged;
  const SecretField({
    super.key,
    required this.controller,
    required this.label,
    this.helper,
    this.enabled = true,
    this.onChanged,
  });
  @override
  State<SecretField> createState() => _SecretFieldState();
}

class _SecretFieldState extends State<SecretField> {
  bool _visible = false;
  @override
  Widget build(BuildContext context) => TextFormField(
    controller: widget.controller,
    enabled: widget.enabled,
    obscureText: !_visible,
    autocorrect: false,
    enableSuggestions: false,
    onChanged: widget.onChanged,
    decoration: InputDecoration(
      labelText: widget.label,
      helperText: widget.helper,
      helperMaxLines: 3,
      suffixIcon: IconButton(
        tooltip: _visible ? 'Hide ${widget.label}' : 'Show ${widget.label}',
        onPressed: widget.enabled
            ? () => setState(() => _visible = !_visible)
            : null,
        icon: Icon(
          _visible ? CupertinoIcons.eye_slash : CupertinoIcons.eye,
          size: 18,
        ),
      ),
    ),
  );
}
