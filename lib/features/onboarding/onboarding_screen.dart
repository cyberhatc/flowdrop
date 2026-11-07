import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/state/app_controller.dart';
import '../../ui/glow.dart';

/// First-run 3-slide onboarding.
///
/// Shown once after startup until the user finishes or skips, then
/// persisted in settings so it never pops up again. Each slide explains a
/// permission or a safety behaviour the user is about to depend on.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _pageController = PageController();
  int _page = 0;

  static const _slides = [
    _Slide(
      icon: Icons.radar_rounded,
      title: 'Same Wi-Fi or hotspot',
      body:
          'FlowDrop finds nearby devices on your local network — no router, '
          'no internet. Your system may ask for local-network or firewall '
          'permission; that is what lets devices discover each other.',
      bullets: [
        'Works over Wi-Fi, a phone hotspot or a laptop hotspot',
        'Discovery uses tiny UDP beacons plus mDNS — it never leaves your LAN',
      ],
    ),
    _Slide(
      icon: Icons.swap_vert_rounded,
      title: 'Send files and text',
      body:
          'Tap a device on the radar, choose what to send, and it streams '
          'directly. Files are verified with SHA-256 before they are saved, '
          'so a corrupted transfer never lands on disk as a "complete" file.',
      bullets: [
        'Large files stream in chunks — memory stays flat',
        'Interrupted transfers resume where they left off',
      ],
    ),
    _Slide(
      icon: Icons.shield_outlined,
      title: 'You approve every sender',
      body:
          'Devices prove who they are with a certificate fingerprint before '
          'anything flows. Unknown devices always need your Accept first, and '
          'pairing codes expire after two uses-free minutes. Nothing is '
          'auto-accepted from a stranger.',
      bullets: [
        'TLS everywhere, pinned per device — never blanket-trusted',
        'QR pairing works even when discovery is blocked',
        'Only the download folder is ever written to',
      ],
    ),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    final controller = ref.read(appControllerProvider.notifier);
    await controller.completeOnboarding();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final last = _page == _slides.length - 1;

    return Scaffold(
      body: NeonBackground(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Row(
                      children: [
                        const Spacer(),
                        TextButton(
                          onPressed: _finish,
                          child: Text(
                            'Skip',
                            style: TextStyle(
                              color: scheme.onSurface.withValues(alpha: 0.6),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: PageView.builder(
                      controller: _pageController,
                      itemCount: _slides.length,
                      onPageChanged: (index) => setState(() => _page = index),
                      itemBuilder: (context, index) =>
                          _SlideBody(slide: _slides[index]),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (var i = 0; i < _slides.length; i++) ...[
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 220),
                            width: i == _page ? 22 : 7,
                            height: 7,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(999),
                              color: i == _page
                                  ? scheme.primary
                                  : scheme.onSurface.withValues(alpha: 0.25),
                            ),
                          ),
                          if (i != _slides.length - 1)
                            const SizedBox(width: 6),
                        ],
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 4, 24, 28),
                    child: Row(
                      children: [
                        if (_page > 0)
                          GlowButton(
                            label: 'Back',
                            tone: GlowTone.ghost,
                            onPressed: () => _pageController.previousPage(
                              duration: const Duration(milliseconds: 280),
                              curve: Curves.easeOut,
                            ),
                          ),
                        const Spacer(),
                        GlowButton(
                          label: last ? 'Get started' : 'Next',
                          icon: last
                              ? Icons.rocket_launch_rounded
                              : Icons.arrow_forward_rounded,
                          onPressed: () {
                            if (last) {
                              _finish();
                            } else {
                              _pageController.nextPage(
                                duration: const Duration(milliseconds: 280),
                                curve: Curves.easeOut,
                              );
                            }
                          },
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
    );
  }
}

class _Slide {
  const _Slide({
    required this.icon,
    required this.title,
    required this.body,
    required this.bullets,
  });

  final IconData icon;
  final String title;
  final String body;
  final List<String> bullets;
}

class _SlideBody extends StatelessWidget {
  const _SlideBody({required this.slide});

  final _Slide slide;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 16, 28, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GlowIcon(icon: slide.icon, size: 72),
          const SizedBox(height: 24),
          GradientHeadline(
            slide.title,
            style: Theme.of(context)
                .textTheme
                .headlineMedium
                ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.4),
          ),
          const SizedBox(height: 12),
          Text(
            slide.body,
            style: TextStyle(
              fontSize: 14,
              height: 1.55,
              color: scheme.onSurface.withValues(alpha: 0.75),
            ),
          ),
          const SizedBox(height: 18),
          for (final bullet in slide.bullets) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.check_circle_rounded,
                  size: 17,
                  color: scheme.primary,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    bullet,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.45,
                      color: scheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}
