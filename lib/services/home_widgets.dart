import 'dart:convert';
import 'dart:io';

import 'package:home_widget/home_widget.dart';

import '../models/story.dart';

/// Pushes the latest curated briefing to the Android home-screen widgets.
class HomeWidgets {
  static const _pkg = 'com.parallaxnews.parallax_news';

  static Map<String, Object?> _item(Story s) {
    final d = s.distribution;
    return {
      't': s.title,
      'cat': s.category.label,
      'n': s.uniqueSources.length,
      'l': d.left,
      'c': d.center,
      'r': d.right,
    };
  }

  static Future<void> publish(List<Story> briefing) async {
    if (!Platform.isAndroid || briefing.isEmpty) return;
    try {
      final now = DateTime.now();
      final hh = now.hour.toString().padLeft(2, '0');
      final mm = now.minute.toString().padLeft(2, '0');
      await HomeWidget.saveWidgetData<String>('briefing', jsonEncode(briefing.take(4).map(_item).toList()));
      await HomeWidget.saveWidgetData<String>('updated', 'Updated $hh:$mm');
      final blind = briefing.where((s) => s.distribution.blindspotFor != null).toList();
      if (blind.isNotEmpty) {
        final b = blind.first;
        await HomeWidget.saveWidgetData<String>(
            'blindspot', jsonEncode({..._item(b), 'side': b.distribution.blindspotFor!.label.toLowerCase()}));
      }
      await HomeWidget.updateWidget(qualifiedAndroidName: '$_pkg.BriefingWidgetProvider');
      await HomeWidget.updateWidget(qualifiedAndroidName: '$_pkg.BlindspotWidgetProvider');
    } catch (_) {
      // Widgets are optional; never break the feed over them.
    }
  }

  /// Tab index to open when the app was launched from a widget, else null.
  static int? tabFor(Uri? uri) {
    if (uri == null || uri.scheme != 'parallax') return null;
    switch (uri.host) {
      case 'briefing':
        return 0;
      case 'blindspot':
        return 4;
    }
    return null;
  }
}
