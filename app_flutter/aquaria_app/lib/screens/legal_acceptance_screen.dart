import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/supabase_service.dart';

const _cDark = Color(0xFF0E5A66);
const _cMid = Color(0xFF1FA2A8);

class LegalAcceptanceScreen extends StatefulWidget {
  final VoidCallback onAccepted;
  const LegalAcceptanceScreen({super.key, required this.onAccepted});

  @override
  State<LegalAcceptanceScreen> createState() => _LegalAcceptanceScreenState();
}

class _LegalAcceptanceScreenState extends State<LegalAcceptanceScreen> {
  bool _termsChecked = false;
  bool _privacyChecked = false;
  bool _loading = false;

  bool get _canAccept => _termsChecked && _privacyChecked && !_loading;

  Future<void> _accept() async {
    setState(() => _loading = true);
    try {
      await SupabaseService.recordAcceptance(
        appVersion: '1.0.0',
        deviceInfo: '${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
      );
      widget.onAccepted();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to record acceptance: $e')),
        );
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            children: [
              const Spacer(flex: 2),
              Image.asset('assets/images/fulllogo.jpg', width: 160),
              const SizedBox(height: 24),
              const Text(
                'Before you continue',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: _cDark,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Please review and accept our Terms & Conditions and Privacy Policy to use Aquaria.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.black54, height: 1.5),
              ),
              const SizedBox(height: 32),

              // Terms checkbox
              _LegalCheckRow(
                checked: _termsChecked,
                onChanged: (v) => setState(() => _termsChecked = v ?? false),
                label: 'I have read and agree to the ',
                linkText: 'Terms & Conditions',
                onLinkTap: () => _openUrl('https://aquaria-ai.com/terms'),
              ),
              const SizedBox(height: 16),

              // Privacy checkbox
              _LegalCheckRow(
                checked: _privacyChecked,
                onChanged: (v) => setState(() => _privacyChecked = v ?? false),
                label: 'I have read and agree to the ',
                linkText: 'Privacy Policy',
                onLinkTap: () => _openUrl('https://aquaria-ai.com/privacy'),
              ),
              const SizedBox(height: 12),

              // AI disclaimer
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF8E1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFFFCC80)),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, size: 18, color: Color(0xFFE65100)),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'This app uses AI to generate recommendations. AI-generated content may be inaccurate. '
                        'All care decisions are your sole responsibility. Always consult a qualified professional.',
                        style: TextStyle(fontSize: 12, color: Colors.black87, height: 1.5),
                      ),
                    ),
                  ],
                ),
              ),

              const Spacer(flex: 3),

              // Accept button
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: _canAccept ? _cDark : Colors.grey.shade300,
                    foregroundColor: _canAccept ? Colors.white : Colors.grey.shade500,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: _canAccept ? _accept : null,
                  child: _loading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Accept & Continue', style: TextStyle(fontSize: 15)),
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}

class _LegalCheckRow extends StatelessWidget {
  final bool checked;
  final ValueChanged<bool?> onChanged;
  final String label;
  final String linkText;
  final VoidCallback onLinkTap;

  const _LegalCheckRow({
    required this.checked,
    required this.onChanged,
    required this.label,
    required this.linkText,
    required this.onLinkTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!checked),
      borderRadius: BorderRadius.circular(8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 24,
            height: 24,
            child: Checkbox(
              value: checked,
              onChanged: onChanged,
              activeColor: _cDark,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: const TextStyle(fontSize: 14, color: Colors.black87),
                children: [
                  TextSpan(text: label),
                  WidgetSpan(
                    child: GestureDetector(
                      onTap: onLinkTap,
                      child: Text(
                        linkText,
                        style: const TextStyle(
                          fontSize: 14,
                          color: _cMid,
                          decoration: TextDecoration.underline,
                          decorationColor: _cMid,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
