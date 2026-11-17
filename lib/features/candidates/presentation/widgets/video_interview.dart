import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../candidate_profile_screen.dart' show openExternal;

/// The maid's video interview (YouTube). Shows the thumbnail first; the
/// player loads only when the customer taps play, to save data.
class VideoInterview extends ConsumerStatefulWidget {
  const VideoInterview({super.key, required this.videoId});

  /// YouTube video ID (11 characters).
  final String videoId;

  @override
  ConsumerState<VideoInterview> createState() => _VideoInterviewState();
}

class _VideoInterviewState extends ConsumerState<VideoInterview> {
  YoutubePlayerController? _controller;

  void _play() {
    setState(() {
      _controller = YoutubePlayerController.fromVideoId(
        videoId: widget.videoId,
        autoPlay: true,
        params: const YoutubePlayerParams(
          showFullscreenButton: true,
          strictRelatedVideos: true,
        ),
      );
    });
  }

  @override
  void dispose() {
    unawaited(_controller?.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: AppRadius.mdAll,
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: controller == null
                ? _Thumbnail(videoId: widget.videoId, onPlay: _play)
                : YoutubePlayer(controller: controller),
          ),
        ),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: TextButton.icon(
            onPressed: () => unawaited(
              openExternal(
                context,
                ref,
                Uri.https('www.youtube.com', '/watch', {'v': widget.videoId}),
                failureMessage: "YouTube couldn't be opened.",
              ),
            ),
            icon: const Icon(Icons.open_in_new_rounded, size: 18),
            label: const Text('Open in YouTube'),
          ),
        ),
      ],
    );
  }
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.videoId, required this.onPlay});

  final String videoId;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Play video interview',
      excludeSemantics: true,
      child: InkWell(
        onTap: onPlay,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.network(
              'https://i.ytimg.com/vi/$videoId/hqdefault.jpg',
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) =>
                  const ColoredBox(color: AppColors.lightBlue),
            ),
            const ColoredBox(color: Color(0x33000000)),
            Center(
              child: Container(
                width: 64,
                height: 64,
                decoration: const BoxDecoration(
                  color: AppColors.white,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.play_arrow_rounded,
                  size: 40,
                  color: AppColors.primary,
                ),
              ),
            ),
            Positioned(
              left: AppSpacing.sm,
              bottom: AppSpacing.sm,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xs,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  borderRadius: AppRadius.pillAll,
                ),
                child: Text(
                  'Video interview',
                  style: AppTypography.labelSmall.copyWith(
                    color: AppColors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Small "Video" label for maid cards.
class VideoBadge extends StatelessWidget {
  const VideoBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: 3),
      decoration: const BoxDecoration(
        color: AppColors.lightBlue,
        borderRadius: AppRadius.pillAll,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.play_circle_fill_rounded,
            size: 14,
            color: AppColors.infoText,
          ),
          const SizedBox(width: 3),
          Text(
            'Video',
            style: AppTypography.labelSmall.copyWith(color: AppColors.infoText),
          ),
        ],
      ),
    );
  }
}
