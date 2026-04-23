import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

const _methodChannel = MethodChannel('charge_overlay_app/methods');
const _eventChannel = EventChannel('charge_overlay_app/charging_state');
const _notificationEventChannel = EventChannel(
  'charge_overlay_app/notification_events',
);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ChargeOverlayApp());
}

class ChargeOverlayApp extends StatefulWidget {
  const ChargeOverlayApp({super.key});

  @override
  State<ChargeOverlayApp> createState() => _ChargeOverlayAppState();
}

class _ChargeOverlayAppState extends State<ChargeOverlayApp> {
  final Future<AppBootstrap> _bootstrapFuture = AppBootstrap.load();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Charge Overlay',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF06121C),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF38BDF8),
          brightness: Brightness.dark,
          surface: const Color(0xFF0C1C2B),
        ),
        fontFamily: 'sans-serif',
      ),
      home: FutureBuilder<AppBootstrap>(
        future: _bootstrapFuture,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const _LoadingScreen();
          }

          final bootstrap = snapshot.data!;
          return bootstrap.overlayMode
              ? ChargingOverlayScreen(initialState: bootstrap.state)
              : SettingsScreen(initialSettings: bootstrap.settings);
        },
      ),
    );
  }
}

class AppBootstrap {
  const AppBootstrap({
    required this.overlayMode,
    required this.settings,
    required this.state,
  });

  final bool overlayMode;
  final ChargeSettings settings;
  final ChargingState state;

  static Future<AppBootstrap> load() async {
    final route = await _methodChannel.invokeMethod<String>('getLaunchMode');
    final rawSettings = await _methodChannel.invokeMapMethod<String, dynamic>(
      'getSettings',
    );
    final rawState = await _methodChannel.invokeMapMethod<String, dynamic>(
      'getChargingState',
    );

    return AppBootstrap(
      overlayMode: route == 'overlay',
      settings: ChargeSettings.fromMap(rawSettings ?? const {}),
      state: ChargingState.fromMap(rawState ?? const {}),
    );
  }
}

enum DisplayMode { live, video }

enum LiveScreenStyle {
  wave('Wave'),
  glass('Glass'),
  halo('Halo');

  const LiveScreenStyle(this.label);

  final String label;

  static LiveScreenStyle fromStorage(dynamic value) {
    final name = value as String?;
    return LiveScreenStyle.values.firstWhere(
      (style) => style.name == name,
      orElse: () => LiveScreenStyle.wave,
    );
  }
}

enum BackgroundStyle {
  pulse('Pulse'),
  aurora('Aurora'),
  drift('Drift');

  const BackgroundStyle(this.label);

  final String label;

  static BackgroundStyle fromStorage(dynamic value) {
    final name = value as String?;
    return BackgroundStyle.values.firstWhere(
      (style) => style.name == name,
      orElse: () => BackgroundStyle.pulse,
    );
  }
}

enum DisplayDuration {
  oneMinute(1, '1 minute'),
  twoMinutes(2, '2 minutes'),
  fiveMinutes(5, '5 minutes'),
  always(0, 'Always');

  const DisplayDuration(this.minutes, this.label);

  final int minutes;
  final String label;

  static DisplayDuration fromStorage(dynamic value) {
    final minutes = value is int ? value : int.tryParse('$value') ?? 2;
    return DisplayDuration.values.firstWhere(
      (duration) => duration.minutes == minutes,
      orElse: () => DisplayDuration.twoMinutes,
    );
  }
}

class ChargeSettings {
  const ChargeSettings({
    required this.enabled,
    required this.displayMode,
    required this.liveScreenStyle,
    required this.backgroundStyle,
    required this.displayDuration,
    required this.videoPath,
    required this.showPercentageOnVideo,
    required this.showNotifications,
    required this.keepScreenAwake,
  });

  final bool enabled;
  final DisplayMode displayMode;
  final LiveScreenStyle liveScreenStyle;
  final BackgroundStyle backgroundStyle;
  final DisplayDuration displayDuration;
  final String? videoPath;
  final bool showPercentageOnVideo;
  final bool showNotifications;
  final bool keepScreenAwake;

  ChargeSettings copyWith({
    bool? enabled,
    DisplayMode? displayMode,
    LiveScreenStyle? liveScreenStyle,
    BackgroundStyle? backgroundStyle,
    DisplayDuration? displayDuration,
    String? videoPath,
    bool clearVideoPath = false,
    bool? showPercentageOnVideo,
    bool? showNotifications,
    bool? keepScreenAwake,
  }) {
    return ChargeSettings(
      enabled: enabled ?? this.enabled,
      displayMode: displayMode ?? this.displayMode,
      liveScreenStyle: liveScreenStyle ?? this.liveScreenStyle,
      backgroundStyle: backgroundStyle ?? this.backgroundStyle,
      displayDuration: displayDuration ?? this.displayDuration,
      videoPath: clearVideoPath ? null : videoPath ?? this.videoPath,
      showPercentageOnVideo:
          showPercentageOnVideo ?? this.showPercentageOnVideo,
      showNotifications: showNotifications ?? this.showNotifications,
      keepScreenAwake: keepScreenAwake ?? this.keepScreenAwake,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'enabled': enabled,
      'displayMode': displayMode.name,
      'liveScreenStyle': liveScreenStyle.name,
      'backgroundStyle': backgroundStyle.name,
      'durationMinutes': displayDuration.minutes,
      'videoPath': videoPath,
      'showPercentageOnVideo': showPercentageOnVideo,
      'showNotifications': showNotifications,
      'keepScreenAwake': keepScreenAwake,
    };
  }

  static ChargeSettings fromMap(Map<dynamic, dynamic> map) {
    return ChargeSettings(
      enabled: map['enabled'] as bool? ?? false,
      displayMode: (map['displayMode'] as String?) == DisplayMode.video.name
          ? DisplayMode.video
          : DisplayMode.live,
      liveScreenStyle: LiveScreenStyle.fromStorage(map['liveScreenStyle']),
      backgroundStyle: BackgroundStyle.fromStorage(map['backgroundStyle']),
      displayDuration: DisplayDuration.fromStorage(map['durationMinutes']),
      videoPath: (map['videoPath'] as String?)?.trim().isEmpty ?? true
          ? null
          : map['videoPath'] as String?,
      showPercentageOnVideo: map['showPercentageOnVideo'] as bool? ?? true,
      showNotifications: map['showNotifications'] as bool? ?? true,
      keepScreenAwake: map['keepScreenAwake'] as bool? ?? true,
    );
  }
}

class ChargingState {
  const ChargingState({
    required this.level,
    required this.isCharging,
    required this.isPlugged,
    required this.source,
  });

  final int level;
  final bool isCharging;
  final bool isPlugged;
  final String source;

  static ChargingState fromMap(Map<dynamic, dynamic> map) {
    return ChargingState(
      level: (map['level'] as num?)?.round() ?? 0,
      isCharging: map['isCharging'] as bool? ?? false,
      isPlugged: map['isPlugged'] as bool? ?? false,
      source: map['source'] as String? ?? 'unknown',
    );
  }
}

class OverlayNotificationItem {
  const OverlayNotificationItem({
    required this.appName,
    required this.title,
    required this.message,
    required this.packageName,
    this.iconBytes,
  });

  final String appName;
  final String title;
  final String message;
  final String packageName;
  final Uint8List? iconBytes;

  bool get isWhatsApp {
    final pkg = packageName.toLowerCase();
    return pkg == 'com.whatsapp' ||
        pkg == 'com.whatsapp.w4b' ||
        pkg.startsWith('com.whatsapp');
  }

  String get dedupeKey =>
      '$packageName|$appName|$title|$message|${iconBytes?.length ?? 0}';

  static OverlayNotificationItem? fromEvent(dynamic event) {
    if (event is! Map) {
      return null;
    }
    final map = Map<dynamic, dynamic>.from(event);
    final appName = (map['appName'] as String? ?? '').trim();
    final title = (map['title'] as String? ?? '').trim();
    final message = (map['message'] as String? ?? '').trim();
    final packageName = (map['packageName'] as String? ?? '').trim();
    if (appName.isEmpty && title.isEmpty && message.isEmpty) {
      return null;
    }

    Uint8List? iconBytes;
    final rawIcon = map['iconBytes'];
    if (rawIcon is Uint8List) {
      iconBytes = rawIcon;
    } else if (rawIcon is List) {
      iconBytes = Uint8List.fromList(rawIcon.cast<int>());
    }

    return OverlayNotificationItem(
      appName: appName,
      title: title,
      message: message,
      packageName: packageName,
      iconBytes: iconBytes,
    );
  }
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.initialSettings});

  final ChargeSettings initialSettings;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late ChargeSettings _settings;
  bool _saving = false;
  bool _overlayGranted = false;
  bool _serviceRunning = false;
  bool _ignoringBatteryOptimizations = false;
  bool _notificationAccessGranted = false;

  @override
  void initState() {
    super.initState();
    _settings = widget.initialSettings;
    unawaited(_refreshCapabilities());
  }

  Future<void> _refreshCapabilities() async {
    final bool overlayGranted =
        await _methodChannel.invokeMethod<bool>('canDrawOverlays') ?? false;
    final bool serviceRunning =
        await _methodChannel.invokeMethod<bool>('isServiceRunning') ?? false;
    final bool ignoringBatteryOptimizations =
        await _methodChannel
            .invokeMethod<bool>('isIgnoringBatteryOptimizations') ??
        false;
    final bool notificationAccessGranted =
        await _methodChannel.invokeMethod<bool>('canReadNotifications') ??
        false;

    if (!mounted) {
      return;
    }

    setState(() {
      _overlayGranted = overlayGranted;
      _serviceRunning = serviceRunning;
      _ignoringBatteryOptimizations = ignoringBatteryOptimizations;
      _notificationAccessGranted = notificationAccessGranted;
    });
  }

  Future<void> _persist(ChargeSettings next) async {
    setState(() {
      _settings = next;
      _saving = true;
    });

    try {
      await _methodChannel.invokeMethod<void>('saveSettings', next.toMap());
      await _methodChannel.invokeMethod<void>('syncMonitoringState');
      await _refreshCapabilities();
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  Future<void> _pickVideo() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.video,
      allowMultiple: false,
    );

    final path = result?.files.single.path;
    if (path == null || path.isEmpty) {
      return;
    }

    await _persist(_settings.copyWith(videoPath: path));
  }

  Future<void> _requestOverlayPermission() async {
    await _methodChannel.invokeMethod<void>('openOverlayPermissionSettings');
    await Future<void>.delayed(const Duration(milliseconds: 400));
    await _refreshCapabilities();
  }

  Future<void> _openBatteryOptimizationSettings() async {
    await _methodChannel.invokeMethod<void>('openBatteryOptimizationSettings');
    await Future<void>.delayed(const Duration(milliseconds: 400));
    await _refreshCapabilities();
  }

  Future<void> _openNotificationAccessSettings() async {
    await _methodChannel.invokeMethod<void>('openNotificationListenerSettings');
    await Future<void>.delayed(const Duration(milliseconds: 400));
    await _refreshCapabilities();
  }

  Future<void> _showOverlayPreview() async {
    await _methodChannel.invokeMethod<void>('showOverlayPreview');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'Charge Overlay',
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Built for personal Android use. The monitor service listens for charger changes and opens a fullscreen charging experience when your phone is plugged in.',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: Colors.white70,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 20),
            _HeroStatusCard(
              enabled: _settings.enabled,
              overlayGranted: _overlayGranted,
              serviceRunning: _serviceRunning,
              saving: _saving,
            ),
            const SizedBox(height: 20),
            _SectionCard(
              title: 'Behavior',
              child: Column(
                children: [
                  SwitchListTile.adaptive(
                    value: _settings.enabled,
                    onChanged: (value) =>
                        _persist(_settings.copyWith(enabled: value)),
                    title: const Text('Enable charging overlay'),
                    subtitle: const Text(
                      'Keeps the foreground monitor running so plug events can trigger the overlay.',
                    ),
                    contentPadding: EdgeInsets.zero,
                  ),
                  const Divider(height: 24),
                  SegmentedButton<DisplayMode>(
                    segments: const [
                      ButtonSegment(
                        value: DisplayMode.live,
                        icon: Icon(Icons.bolt),
                        label: Text('Live animation'),
                      ),
                      ButtonSegment(
                        value: DisplayMode.video,
                        icon: Icon(Icons.movie_creation_outlined),
                        label: Text('Custom video'),
                      ),
                    ],
                    selected: {_settings.displayMode},
                    onSelectionChanged: (selection) {
                      _persist(
                        _settings.copyWith(displayMode: selection.first),
                      );
                    },
                  ),
                  if (_settings.displayMode == DisplayMode.live) ...[
                    const SizedBox(height: 16),
                    DropdownButtonFormField<LiveScreenStyle>(
                      initialValue: _settings.liveScreenStyle,
                      decoration: const InputDecoration(
                        labelText: 'Charging screen style',
                        border: OutlineInputBorder(),
                      ),
                      items: LiveScreenStyle.values
                          .map(
                            (style) => DropdownMenuItem(
                              value: style,
                              child: Text(style.label),
                            ),
                          )
                          .toList(),
                      onChanged: (style) {
                        if (style != null) {
                          _persist(_settings.copyWith(liveScreenStyle: style));
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<BackgroundStyle>(
                      initialValue: _settings.backgroundStyle,
                      decoration: const InputDecoration(
                        labelText: 'Animated background',
                        border: OutlineInputBorder(),
                      ),
                      items: BackgroundStyle.values
                          .map(
                            (style) => DropdownMenuItem(
                              value: style,
                              child: Text(style.label),
                            ),
                          )
                          .toList(),
                      onChanged: (style) {
                        if (style != null) {
                          _persist(_settings.copyWith(backgroundStyle: style));
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Built-in live styles stay battery-conscious: one active charging animation surface, a slow ambient background, no scrolling, no background polling, and the digital clock still refreshes only once per minute.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.white60,
                        height: 1.45,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  DropdownButtonFormField<DisplayDuration>(
                    initialValue: _settings.displayDuration,
                    decoration: const InputDecoration(
                      labelText: 'Show overlay for',
                      border: OutlineInputBorder(),
                    ),
                    items: DisplayDuration.values
                        .map(
                          (duration) => DropdownMenuItem(
                            value: duration,
                            child: Text(duration.label),
                          ),
                        )
                        .toList(),
                    onChanged: (duration) {
                      if (duration != null) {
                        _persist(_settings.copyWith(displayDuration: duration));
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile.adaptive(
                    value: _settings.keepScreenAwake,
                    onChanged: (value) =>
                        _persist(_settings.copyWith(keepScreenAwake: value)),
                    title: const Text('Keep screen awake while visible'),
                    subtitle: const Text(
                      'Prevents the display from sleeping only while the charging overlay is on screen.',
                    ),
                    contentPadding: EdgeInsets.zero,
                  ),
                  const Divider(height: 24),
                  SwitchListTile.adaptive(
                    value: _settings.showNotifications,
                    onChanged: (value) => _persist(
                      _settings.copyWith(showNotifications: value),
                    ),
                    title: const Text('Show notifications on overlay'),
                    subtitle: const Text(
                      'Briefly reveals incoming notifications on the charging screen with a small animated banner.',
                    ),
                    contentPadding: EdgeInsets.zero,
                  ),
                  if (_settings.displayMode == DisplayMode.video) ...[
                    const SizedBox(height: 16),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Selected video'),
                      subtitle: Text(
                        _settings.videoPath ?? 'No file selected yet',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: FilledButton.tonal(
                        onPressed: _pickVideo,
                        child: const Text('Choose'),
                      ),
                    ),
                    SwitchListTile.adaptive(
                      value: _settings.showPercentageOnVideo,
                      onChanged: (value) => _persist(
                        _settings.copyWith(showPercentageOnVideo: value),
                      ),
                      title: const Text('Show percentage on video'),
                      contentPadding: EdgeInsets.zero,
                    ),
                    if (_settings.videoPath != null)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () => _persist(
                            _settings.copyWith(clearVideoPath: true),
                          ),
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('Remove video'),
                        ),
                      ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            _SectionCard(
              title: 'Power and access',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      _overlayGranted
                          ? Icons.verified_user_outlined
                          : Icons.warning_amber_rounded,
                      color: _overlayGranted
                          ? Colors.lightGreenAccent
                          : Colors.amberAccent,
                    ),
                    title: Text(
                      _overlayGranted
                          ? 'Overlay permission granted'
                          : 'Overlay permission needed',
                    ),
                    subtitle: const Text(
                      'For Android 16 background launches, this app works best when "display over other apps" is allowed.',
                    ),
                    trailing: FilledButton.tonal(
                      onPressed: _requestOverlayPermission,
                      child: Text(_overlayGranted ? 'Review' : 'Grant'),
                    ),
                  ),
                  const Divider(height: 24),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      _ignoringBatteryOptimizations
                          ? Icons.battery_saver_outlined
                          : Icons.energy_savings_leaf_outlined,
                      color: _ignoringBatteryOptimizations
                          ? Colors.lightGreenAccent
                          : Colors.cyanAccent,
                    ),
                    title: Text(
                      _ignoringBatteryOptimizations
                          ? 'Battery restrictions relaxed'
                          : 'Battery use is already optimized',
                    ),
                    subtitle: Text(
                      _ignoringBatteryOptimizations
                          ? 'Android is less likely to stop the monitor service in the background.'
                          : 'The app now keeps its background work light and only streams live battery updates while the overlay is visible.',
                    ),
                    trailing: FilledButton.tonal(
                      onPressed: _openBatteryOptimizationSettings,
                      child: const Text('Open'),
                    ),
                  ),
                  const Divider(height: 24),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      _notificationAccessGranted
                          ? Icons.notifications_active_outlined
                          : Icons.notifications_off_outlined,
                      color: _notificationAccessGranted
                          ? Colors.lightGreenAccent
                          : Colors.amberAccent,
                    ),
                    title: Text(
                      _notificationAccessGranted
                          ? 'Notification access granted'
                          : 'Notification access needed',
                    ),
                    subtitle: const Text(
                      'Needed only if you want the charging overlay to briefly show incoming notifications.',
                    ),
                    trailing: FilledButton.tonal(
                      onPressed: _openNotificationAccessSettings,
                      child: Text(_notificationAccessGranted ? 'Review' : 'Grant'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Double-tap anywhere on the charging screen to dismiss it. If duration is set to Always, the overlay stays up until you dismiss it or unplug the charger. Background battery drain stays lower because the service only waits for plug and unplug events.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _overlayGranted ? _showOverlayPreview : null,
                    icon: const Icon(Icons.visibility_outlined),
                    label: const Text('Preview overlay'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Note: Android vendors can still apply their own power-management rules. On some Xiaomi/Redmi builds you may want to whitelist the app from battery restrictions after install.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: Colors.white54,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ChargingOverlayScreen extends StatefulWidget {
  const ChargingOverlayScreen({super.key, required this.initialState});

  final ChargingState initialState;

  @override
  State<ChargingOverlayScreen> createState() => _ChargingOverlayScreenState();
}

class _ChargingOverlayScreenState extends State<ChargingOverlayScreen>
    with TickerProviderStateMixin {
  late ChargingState _state;
  late Future<ChargeSettings> _settingsFuture;
  StreamSubscription<dynamic>? _subscription;
  StreamSubscription<dynamic>? _notificationSubscription;
  Timer? _closeTimer;
  Timer? _clockTimer;
  Timer? _estimateTimer;
  Timer? _generalNotificationTimer;
  Timer? _whatsappNotificationTimer;
  DateTime _now = DateTime.now();
  DateTime _lastLevelSync = DateTime.now();
  bool _showAnalogClock = false;
  OverlayNotificationItem? _generalNotification;
  OverlayNotificationItem? _whatsappNotification;

  static const Duration _notificationDisplayDuration = Duration(seconds: 6);
  static const Duration _notificationTransitionDuration =
      Duration(milliseconds: 650);
  late final AnimationController _introController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 550),
  );
  late final AnimationController _analogClockController = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 1),
  );

  @override
  void initState() {
    super.initState();
    _state = widget.initialState;
    _lastLevelSync = DateTime.now();
    _settingsFuture = _loadSettings();
    _startClockTimer();
    _startEstimateTimer();
    _introController.forward();
    _subscription = _eventChannel.receiveBroadcastStream().listen((event) {
      final next = ChargingState.fromMap(Map<dynamic, dynamic>.from(event));
      if (!mounted) {
        return;
      }
      setState(() {
        if (next.level != _state.level) {
          _lastLevelSync = DateTime.now();
        }
        _state = next;
      });
      if (!next.isPlugged) {
        _dismiss();
      }
    });
    _notificationSubscription = _notificationEventChannel
        .receiveBroadcastStream()
        .listen((event) {
          final item = OverlayNotificationItem.fromEvent(event);
          if (!mounted || item == null) {
            return;
          }
          if (item.isWhatsApp) {
            _whatsappNotificationTimer?.cancel();
            setState(() {
              _whatsappNotification = item;
            });
            _whatsappNotificationTimer = Timer(
              _notificationDisplayDuration,
              () {
                if (!mounted) {
                  return;
                }
                setState(() {
                  _whatsappNotification = null;
                });
              },
            );
          } else {
            _generalNotificationTimer?.cancel();
            setState(() {
              _generalNotification = item;
            });
            _generalNotificationTimer = Timer(
              _notificationDisplayDuration,
              () {
                if (!mounted) {
                  return;
                }
                setState(() {
                  _generalNotification = null;
                });
              },
            );
          }
        });
  }

  Future<ChargeSettings> _loadSettings() async {
    final rawSettings = await _methodChannel.invokeMapMethod<String, dynamic>(
      'getSettings',
    );
    final settings = ChargeSettings.fromMap(rawSettings ?? const {});
    _configureAutoDismiss(settings);
    await _syncWakeLock(settings);
    return settings;
  }

  void _configureAutoDismiss(ChargeSettings settings) {
    _closeTimer?.cancel();
    if (settings.displayDuration == DisplayDuration.always) {
      return;
    }

    _closeTimer = Timer(
      Duration(minutes: settings.displayDuration.minutes),
      _dismiss,
    );
  }

  void _startClockTimer() {
    _clockTimer?.cancel();
    final next = DateTime.now().add(const Duration(minutes: 1));
    final aligned = DateTime(next.year, next.month, next.day, next.hour, next.minute);
    _clockTimer = Timer(aligned.difference(DateTime.now()), () {
      if (!mounted) {
        return;
      }
      setState(() {
        _now = DateTime.now();
      });
      _startClockTimer();
    });
  }

  void _startEstimateTimer() {
    _estimateTimer?.cancel();
    _estimateTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!mounted || !_state.isCharging) {
        return;
      }
      setState(() {
        _now = _now;
      });
    });
  }

  void _setAnalogClock(bool value) {
    if (_showAnalogClock == value) {
      return;
    }
    setState(() {
      _showAnalogClock = value;
    });
    if (value) {
      _analogClockController.repeat();
    } else {
      _analogClockController.stop();
    }
  }

  void _handleVerticalSwipe(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (velocity < -220) {
      _setAnalogClock(true);
    } else if (velocity > 220) {
      _setAnalogClock(false);
    }
  }

  Future<void> _dismiss() async {
    _closeTimer?.cancel();
    await _syncWakeLock(null);
    await _methodChannel.invokeMethod<void>('dismissOverlay');
  }

  Future<void> _syncWakeLock(ChargeSettings? settings) async {
    await WakelockPlus.toggle(enable: settings?.keepScreenAwake ?? false);
  }

  @override
  void dispose() {
    _closeTimer?.cancel();
    _clockTimer?.cancel();
    _estimateTimer?.cancel();
    _generalNotificationTimer?.cancel();
    _whatsappNotificationTimer?.cancel();
    _subscription?.cancel();
    _notificationSubscription?.cancel();
    _introController.dispose();
    _analogClockController.dispose();
    unawaited(_syncWakeLock(null));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ChargeSettings>(
      future: _settingsFuture,
      builder: (context, snapshot) {
        final settings =
            snapshot.data ??
            const ChargeSettings(
              enabled: true,
              displayMode: DisplayMode.live,
              liveScreenStyle: LiveScreenStyle.wave,
              backgroundStyle: BackgroundStyle.pulse,
              displayDuration: DisplayDuration.twoMinutes,
              videoPath: null,
              showPercentageOnVideo: true,
              showNotifications: true,
              keepScreenAwake: true,
            );

        final displayPercent = _displayPercent();
        final screenStyle = settings.liveScreenStyle;
        final backgroundStyle = settings.backgroundStyle;

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onDoubleTap: _dismiss,
          onVerticalDragEnd: _handleVerticalSwipe,
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: LayoutBuilder(
              builder: (context, constraints) {
                final size = constraints.biggest;
                final meterSize = (size.height * 0.46).clamp(160.0, 260.0);
                final clock = _formatClock(_now);
                final hourFontSize = size.height < 420 ? 150.0 : 212.0;
                final detailFontSize = size.height < 420 ? 28.0 : 38.0;
                final clockAreaWidth = size.width * 0.56;
                final introCurve = CurvedAnimation(
                  parent: _introController,
                  curve: Curves.easeOutCubic,
                );

                return Stack(
                  fit: StackFit.expand,
                  children: [
                    if (settings.displayMode == DisplayMode.video &&
                        settings.videoPath != null)
                      _VideoBackground(
                        path: settings.videoPath!,
                        fallback: _AnimatedBackdrop(
                          backgroundStyle: backgroundStyle,
                          screenStyle: screenStyle,
                        ),
                      )
                    else
                      _AnimatedBackdrop(
                        backgroundStyle: backgroundStyle,
                        screenStyle: screenStyle,
                      ),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.black.withValues(alpha: 0.18),
                            Colors.black.withValues(alpha: 0.72),
                          ],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        ),
                      ),
                    ),
                    SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(34, 22, 34, 22),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 13,
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: FadeTransition(
                                  opacity: introCurve,
                                  child: SlideTransition(
                                    position: Tween(
                                      begin: const Offset(-0.06, 0),
                                      end: Offset.zero,
                                    ).animate(introCurve),
                                    child: SizedBox(
                                      width: clockAreaWidth,
                                      child: AnimatedSwitcher(
                                        duration: const Duration(milliseconds: 420),
                                        switchInCurve: Curves.easeOutCubic,
                                        switchOutCurve: Curves.easeInCubic,
                                        transitionBuilder:
                                            (child, animation) => FadeTransition(
                                              opacity: animation,
                                              child: SlideTransition(
                                                position: Tween(
                                                  begin: const Offset(0, 0.08),
                                                  end: Offset.zero,
                                                ).animate(animation),
                                                child: child,
                                              ),
                                            ),
                                        child: _showAnalogClock
                                            ? AnimatedBuilder(
                                                key: const ValueKey('analog'),
                                                animation: _analogClockController,
                                                builder: (context, _) {
                                                  return _AnalogClockFace(
                                                    now: DateTime.now(),
                                                    size:
                                                        (size.height * 0.52).clamp(
                                                          180.0,
                                                          320.0,
                                                        ),
                                                  );
                                                },
                                              )
                                            : _DigitalClockDisplay(
                                                key: const ValueKey('digital'),
                                                clock: clock,
                                                fontSize: hourFontSize,
                                              ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            SizedBox(width: size.width * 0.035),
                            Expanded(
                              flex: 7,
                              child: Align(
                                alignment: Alignment.centerRight,
                                child: FadeTransition(
                                  opacity: introCurve,
                                  child: SlideTransition(
                                    position: Tween(
                                      begin: const Offset(0.06, 0),
                                      end: Offset.zero,
                                    ).animate(introCurve),
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.center,
                                      children: [
                                        AnimatedSwitcher(
                                          duration:
                                              const Duration(milliseconds: 350),
                                          child: Text(
                                            '${displayPercent.toStringAsFixed(2)}%',
                                            key: ValueKey<String>(
                                              displayPercent.toStringAsFixed(2),
                                            ),
                                            style: Theme.of(context)
                                                .textTheme
                                                .headlineLarge
                                                ?.copyWith(
                                                  fontSize: detailFontSize,
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.w600,
                                                  letterSpacing: -1.4,
                                                ),
                                          ),
                                        ),
                                        const SizedBox(height: 20),
                                        RepaintBoundary(
                                          child: _WaveBatteryMeter(
                                            style: screenStyle,
                                            level: displayPercent / 100,
                                            size: meterSize,
                                          ),
                                        ),
                                        const SizedBox(height: 18),
                                        Text(
                                          _state.isCharging
                                              ? 'Charging'
                                              : 'Connected',
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleLarge
                                              ?.copyWith(
                                                color: Colors.white54,
                                                fontWeight: FontWeight.w400,
                                              ),
                                        ),
                                        const SizedBox(height: 10),
                                        Text(
                                          _showAnalogClock
                                              ? 'Swipe down for digits'
                                              : 'Swipe up for analog',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodyMedium
                                              ?.copyWith(
                                                color: Colors.white38,
                                              ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Align(
                      alignment: Alignment.bottomRight,
                      child: SafeArea(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 20, 24, 22),
                          child: AnimatedSwitcher(
                            duration: _notificationTransitionDuration,
                            switchInCurve: Curves.easeOutCubic,
                            switchOutCurve: Curves.easeInCubic,
                            transitionBuilder: (child, animation) =>
                                FadeTransition(
                                  opacity: animation,
                                  child: SlideTransition(
                                    position: Tween<Offset>(
                                      begin: const Offset(0, 0.22),
                                      end: Offset.zero,
                                    ).animate(animation),
                                    child: child,
                                  ),
                                ),
                            child: _generalNotification == null
                                ? const SizedBox.shrink()
                                : _NotificationBanner(
                                    key: ValueKey<String>(
                                      'general-${_generalNotification!.dedupeKey}',
                                    ),
                                    item: _generalNotification!,
                                  ),
                          ),
                        ),
                      ),
                    ),
                    Align(
                      alignment: Alignment.bottomLeft,
                      child: SafeArea(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(24, 20, 20, 22),
                          child: AnimatedSwitcher(
                            duration: _notificationTransitionDuration,
                            switchInCurve: Curves.easeOutCubic,
                            switchOutCurve: Curves.easeInCubic,
                            transitionBuilder: (child, animation) =>
                                FadeTransition(
                                  opacity: animation,
                                  child: SlideTransition(
                                    position: Tween<Offset>(
                                      begin: const Offset(-0.22, 0.08),
                                      end: Offset.zero,
                                    ).animate(animation),
                                    child: ScaleTransition(
                                      scale: Tween<double>(
                                        begin: 0.94,
                                        end: 1.0,
                                      ).animate(animation),
                                      alignment: Alignment.bottomLeft,
                                      child: child,
                                    ),
                                  ),
                                ),
                            child: _whatsappNotification == null
                                ? const SizedBox.shrink()
                                : _WhatsAppNotificationBanner(
                                    key: ValueKey<String>(
                                      'whatsapp-${_whatsappNotification!.dedupeKey}',
                                    ),
                                    item: _whatsappNotification!,
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  String _formatClock(DateTime dateTime) {
    final hour = dateTime.hour % 12 == 0 ? 12 : dateTime.hour % 12;
    final minute = dateTime.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  double _displayPercent() {
    if (!_state.isCharging || _state.level >= 100) {
      return _state.level.toDouble();
    }

    final elapsedMs = DateTime.now().difference(_lastLevelSync).inMilliseconds;
    final estimated = _state.level + (elapsedMs / 180000.0);
    return estimated.clamp(
      _state.level.toDouble(),
      (_state.level + 0.99).toDouble(),
    );
  }
}

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}

class _DigitalClockDisplay extends StatelessWidget {
  const _DigitalClockDisplay({
    super.key,
    required this.clock,
    required this.fontSize,
  });

  final String clock;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (bounds) => const LinearGradient(
        colors: [Color(0xFF8CC2FF), Color(0xFFD9ECFF)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(bounds),
      child: Text(
        clock,
        style: Theme.of(context).textTheme.displayLarge?.copyWith(
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
          letterSpacing: -8,
          height: 0.84,
          color: Colors.white,
        ),
      ),
    );
  }
}

class _AnalogClockFace extends StatelessWidget {
  const _AnalogClockFace({required this.now, required this.size});

  final DateTime now;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _AnalogClockPainter(now: now),
      ),
    );
  }
}

class _AnalogClockPainter extends CustomPainter {
  const _AnalogClockPainter({required this.now});

  final DateTime now;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2;

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = const Color(0xFF08121F).withValues(alpha: 0.72)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 20),
    );
    canvas.drawCircle(
      center,
      radius * 0.96,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0xFF162238), Color(0xFF060B14)],
        ).createShader(Rect.fromCircle(center: center, radius: radius)),
    );

    final tickPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.18)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 60; i++) {
      final angle = (-math.pi / 2) + (i * math.pi / 30);
      final outer = Offset(
        center.dx + math.cos(angle) * radius * 0.88,
        center.dy + math.sin(angle) * radius * 0.88,
      );
      final inner = Offset(
        center.dx + math.cos(angle) * radius * (i % 5 == 0 ? 0.73 : 0.8),
        center.dy + math.sin(angle) * radius * (i % 5 == 0 ? 0.73 : 0.8),
      );
      tickPaint.strokeWidth = i % 5 == 0 ? 3 : 1.5;
      canvas.drawLine(inner, outer, tickPaint);
    }

    final seconds =
        now.second + (now.millisecond / 1000) + (now.microsecond / 1000000);
    final minute = now.minute + (seconds / 60);
    final hour = (now.hour % 12) + (minute / 60);
    _drawHand(
      canvas,
      center,
      (-math.pi / 2) + (hour * math.pi / 6),
      radius * 0.42,
      10,
      Colors.white.withValues(alpha: 0.92),
    );
    _drawHand(
      canvas,
      center,
      (-math.pi / 2) + (minute * math.pi / 30),
      radius * 0.62,
      7,
      Colors.white.withValues(alpha: 0.86),
    );
    _drawHand(
      canvas,
      center,
      (-math.pi / 2) + (seconds * math.pi / 30),
      radius * 0.74,
      2.6,
      const Color(0xFF8CC2FF),
    );

    canvas.drawCircle(center, 10, Paint()..color = const Color(0xFF8CC2FF));
    canvas.drawCircle(center, 4.5, Paint()..color = Colors.white);
  }

  void _drawHand(
    Canvas canvas,
    Offset center,
    double angle,
    double length,
    double width,
    Color color,
  ) {
    final handPaint = Paint()
      ..color = color
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      center,
      Offset(
        center.dx + math.cos(angle) * length,
        center.dy + math.sin(angle) * length,
      ),
      handPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _AnalogClockPainter oldDelegate) {
    return oldDelegate.now != now;
  }
}

class _NotificationBanner extends StatelessWidget {
  const _NotificationBanner({super.key, required this.item});

  final OverlayNotificationItem item;

  @override
  Widget build(BuildContext context) {
    final headline = item.title.isNotEmpty ? item.title : item.appName;
    final body = item.message.isNotEmpty ? item.message : item.title;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF09111D).withValues(alpha: 0.86),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF8CC2FF).withValues(alpha: 0.14),
              blurRadius: 28,
              spreadRadius: 4,
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _NotificationAvatar(
              iconBytes: item.iconBytes,
              backgroundColor: Colors.white.withValues(alpha: 0.08),
              fallback: const Icon(
                Icons.notifications_none_rounded,
                size: 22,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 14),
            Flexible(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.appName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: Colors.white54,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    headline,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (body.isNotEmpty && body != headline) ...[
                    const SizedBox(height: 2),
                    Text(
                      body,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.white70,
                        height: 1.3,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WhatsAppNotificationBanner extends StatelessWidget {
  const _WhatsAppNotificationBanner({super.key, required this.item});

  final OverlayNotificationItem item;

  static const Color _whatsappDeep = Color(0xFF075E54);
  static const Color _whatsappTeal = Color(0xFF128C7E);
  static const Color _whatsappGreen = Color(0xFF25D366);
  static const Color _bubbleHighlight = Color(0xFFE5F8EE);

  @override
  Widget build(BuildContext context) {
    final sender = item.title.isNotEmpty ? item.title : item.appName;
    final message = item.message;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 380),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 18, 14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [_whatsappDeep, _whatsappTeal],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(22),
            topRight: Radius.circular(22),
            bottomRight: Radius.circular(22),
            bottomLeft: Radius.circular(6),
          ),
          border: Border.all(
            color: _whatsappGreen.withValues(alpha: 0.35),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: _whatsappGreen.withValues(alpha: 0.32),
              blurRadius: 28,
              spreadRadius: 2,
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 18,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _NotificationAvatar(
              iconBytes: item.iconBytes,
              backgroundColor: Colors.white.withValues(alpha: 0.22),
              ring: _whatsappGreen,
              fallback: const Icon(
                Icons.chat_bubble_rounded,
                color: Colors.white,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(
                        Icons.verified_rounded,
                        size: 13,
                        color: _whatsappGreen,
                      ),
                      SizedBox(width: 4),
                      Text(
                        'WhatsApp',
                        style: TextStyle(
                          color: Color(0xFF8FFFB5),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    sender,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (message.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      message,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _bubbleHighlight,
                        fontSize: 13.5,
                        height: 1.3,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotificationAvatar extends StatelessWidget {
  const _NotificationAvatar({
    required this.iconBytes,
    required this.backgroundColor,
    required this.fallback,
    this.ring,
    this.size = 42,
  });

  final Uint8List? iconBytes;
  final Color backgroundColor;
  final Widget fallback;
  final Color? ring;
  final double size;

  @override
  Widget build(BuildContext context) {
    final avatar = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: backgroundColor,
      ),
      clipBehavior: Clip.antiAlias,
      child: iconBytes != null
          ? Image.memory(
              iconBytes!,
              fit: BoxFit.cover,
              width: size,
              height: size,
              gaplessPlayback: true,
              filterQuality: FilterQuality.medium,
              errorBuilder: (_, __, ___) => fallback,
            )
          : fallback,
    );

    if (ring == null) {
      return avatar;
    }

    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: ring!.withValues(alpha: 0.85), width: 1.4),
      ),
      child: avatar,
    );
  }
}

class _HeroStatusCard extends StatelessWidget {
  const _HeroStatusCard({
    required this.enabled,
    required this.overlayGranted,
    required this.serviceRunning,
    required this.saving,
  });

  final bool enabled;
  final bool overlayGranted;
  final bool serviceRunning;
  final bool saving;

  @override
  Widget build(BuildContext context) {
    final online = enabled && overlayGranted && serviceRunning;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          colors: [Color(0xFF11314A), Color(0xFF081827)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: online ? const Color(0xFF0F766E) : const Color(0xFF7C2D12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              online ? Icons.bolt : Icons.power_settings_new,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  online ? 'Ready on plug-in' : 'Setup still needed',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  saving
                      ? 'Applying your latest changes...'
                      : online
                      ? 'The monitor service is active and can launch the charging overlay.'
                      : 'Enable the app and grant overlay access for the smoothest Android 16 behavior.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.white70,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF0A1724),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _WaveBatteryMeter extends StatefulWidget {
  const _WaveBatteryMeter({
    required this.level,
    required this.size,
    required this.style,
  });

  final double level;
  final double size;
  final LiveScreenStyle style;

  @override
  State<_WaveBatteryMeter> createState() => _WaveBatteryMeterState();
}

class _WaveBatteryMeterState extends State<_WaveBatteryMeter>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 4200),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return CustomPaint(
            painter: _BatteryMeterPainter(
              style: widget.style,
              level: widget.level.clamp(0.0, 1.0),
              phase: _controller.value * math.pi * 2,
            ),
          );
        },
      ),
    );
  }
}

class _BatteryMeterPainter extends CustomPainter {
  const _BatteryMeterPainter({
    required this.style,
    required this.level,
    required this.phase,
  });

  final LiveScreenStyle style;
  final double level;
  final double phase;

  @override
  void paint(Canvas canvas, Size size) {
    switch (style) {
      case LiveScreenStyle.wave:
        _paintWave(canvas, size);
        return;
      case LiveScreenStyle.glass:
        _paintGlass(canvas, size);
        return;
      case LiveScreenStyle.halo:
        _paintHalo(canvas, size);
        return;
    }
  }

  void _paintWave(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final radius = Radius.circular(size.width * 0.28);
    final outline = RRect.fromRectAndRadius(rect, radius);

    final glowPaint = Paint()
      ..color = const Color(0xFF79B8FF).withValues(alpha: 0.12)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 30);
    canvas.drawRRect(outline.inflate(4), glowPaint);

    final shellPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.05);
    canvas.drawRRect(outline, shellPaint);

    final clipPath = Path()..addRRect(outline);
    canvas.save();
    canvas.clipPath(clipPath);

    final fillTop = size.height * (1 - level);
    final waveBase = fillTop.clamp(size.height * 0.08, size.height * 0.92);
    final primaryWave = _buildWavePath(
      size: size,
      baseHeight: waveBase,
      phase: phase,
      amplitude: size.height * 0.028,
      wavelength: size.width * 0.88,
    );
    primaryWave.lineTo(size.width, size.height);
    primaryWave.lineTo(0, size.height);
    primaryWave.close();

    final secondaryWave = _buildWavePath(
      size: size,
      baseHeight: waveBase + (size.height * 0.022),
      phase: phase + 1.2,
      amplitude: size.height * 0.02,
      wavelength: size.width * 0.72,
    );
    secondaryWave.lineTo(size.width, size.height);
    secondaryWave.lineTo(0, size.height);
    secondaryWave.close();

    canvas.drawPath(
      secondaryWave,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFF2458A6), Color(0xFF4F87D6)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ).createShader(rect),
    );

    canvas.drawPath(
      primaryWave,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFF84D2FF), Color(0xFF5AA2FF)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ).createShader(rect),
    );

    canvas.restore();

    canvas.drawRRect(
      outline,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.024
        ..color = Colors.white.withValues(alpha: 0.18),
    );

    final boltPaint = Paint()..color = Colors.white.withValues(alpha: 0.92);
    final bolt = Path()
      ..moveTo(size.width * 0.53, size.height * 0.2)
      ..lineTo(size.width * 0.43, size.height * 0.5)
      ..lineTo(size.width * 0.52, size.height * 0.5)
      ..lineTo(size.width * 0.46, size.height * 0.8)
      ..lineTo(size.width * 0.61, size.height * 0.43)
      ..lineTo(size.width * 0.51, size.height * 0.43)
      ..close();
    canvas.drawPath(bolt, boltPaint);
  }

  void _paintGlass(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final radius = Radius.circular(size.width * 0.5);
    final shell = RRect.fromRectAndRadius(rect, radius);

    canvas.drawRRect(
      shell.inflate(3),
      Paint()
        ..color = const Color(0xFFB9D8FF).withValues(alpha: 0.08)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 24),
    );

    canvas.drawRRect(
      shell,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFF1D2533), Color(0xFF0C1220)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ).createShader(rect),
    );

    final inner = shell.deflate(size.width * 0.045);
    final clipPath = Path()..addRRect(inner);
    canvas.save();
    canvas.clipPath(clipPath);

    final fillRect = Rect.fromLTWH(
      0,
      size.height * (1 - level),
      size.width,
      size.height,
    );
    canvas.drawRect(
      fillRect,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFF8FD0FF), Color(0xFF5E9DFF)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ).createShader(rect),
    );

    final shimmer = Rect.fromLTWH(
      size.width * 0.16,
      size.height * 0.08,
      size.width * 0.26,
      size.height * 0.66,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(shimmer, Radius.circular(size.width * 0.2)),
      Paint()
        ..shader = const LinearGradient(
          colors: [
            Color(0x00FFFFFF),
            Color(0x66FFFFFF),
            Color(0x00FFFFFF),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ).createShader(shimmer),
    );
    canvas.restore();

    canvas.drawRRect(
      shell,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.026
        ..color = Colors.white.withValues(alpha: 0.18),
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(size.width * 0.1, size.height * 0.12, size.width * 0.8, size.height * 0.22),
        Radius.circular(size.width * 0.14),
      ),
      Paint()..color = Colors.white.withValues(alpha: 0.06),
    );

    _paintBolt(canvas, size, alpha: 0.92);
  }

  void _paintHalo(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final center = rect.center;
    final stroke = size.width * 0.08;
    final radius = (size.width - stroke) / 2;

    canvas.drawCircle(
      center,
      radius + 6,
      Paint()
        ..color = const Color(0xFF98C8FF).withValues(alpha: 0.10)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 28),
    );

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = Colors.white.withValues(alpha: 0.08),
    );

    final progressPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = stroke
      ..shader = const SweepGradient(
        colors: [Color(0xFF6BA8FF), Color(0xFFA8DEFF), Color(0xFF6BA8FF)],
      ).createShader(rect);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      math.pi * 2 * level,
      false,
      progressPaint,
    );

    canvas.drawCircle(
      center,
      radius - stroke * 0.85,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0xFF1B2331), Color(0xFF0B1020)],
        ).createShader(rect),
    );

    _paintBolt(canvas, size, alpha: 0.88);
  }

  void _paintBolt(Canvas canvas, Size size, {required double alpha}) {
    final boltPaint = Paint()..color = Colors.white.withValues(alpha: alpha);
    final bolt = Path()
      ..moveTo(size.width * 0.53, size.height * 0.2)
      ..lineTo(size.width * 0.43, size.height * 0.5)
      ..lineTo(size.width * 0.52, size.height * 0.5)
      ..lineTo(size.width * 0.46, size.height * 0.8)
      ..lineTo(size.width * 0.61, size.height * 0.43)
      ..lineTo(size.width * 0.51, size.height * 0.43)
      ..close();
    canvas.drawPath(bolt, boltPaint);
  }

  Path _buildWavePath({
    required Size size,
    required double baseHeight,
    required double phase,
    required double amplitude,
    required double wavelength,
  }) {
    final path = Path()..moveTo(0, baseHeight);
    for (double x = 0; x <= size.width; x += 6) {
      final y =
          baseHeight +
          math.sin((x / wavelength * math.pi * 2) + phase) * amplitude;
      path.lineTo(x, y);
    }
    return path;
  }

  @override
  bool shouldRepaint(covariant _BatteryMeterPainter oldDelegate) {
    return oldDelegate.style != style ||
        oldDelegate.level != level ||
        oldDelegate.phase != phase;
  }
}

class _AnimatedBackdrop extends StatefulWidget {
  const _AnimatedBackdrop({
    required this.backgroundStyle,
    required this.screenStyle,
  });

  final BackgroundStyle backgroundStyle;
  final LiveScreenStyle screenStyle;

  @override
  State<_AnimatedBackdrop> createState() => _AnimatedBackdropState();
}

class _AnimatedBackdropState extends State<_AnimatedBackdrop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 18),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final baseDecoration = switch (widget.screenStyle) {
      LiveScreenStyle.wave => const BoxDecoration(
        gradient: RadialGradient(
          colors: [Color(0xFF082F49), Color(0xFF020617)],
          radius: 1.35,
          center: Alignment(-0.55, 0),
        ),
      ),
      LiveScreenStyle.glass => const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF08101C), Color(0xFF04070F)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      LiveScreenStyle.halo => const BoxDecoration(
        gradient: RadialGradient(
          colors: [Color(0xFF111B36), Color(0xFF020617)],
          radius: 1.2,
          center: Alignment(0.5, 0),
        ),
      ),
    };

    return DecoratedBox(
      decoration: baseDecoration,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final t = _controller.value;
          return Stack(
            fit: StackFit.expand,
            children: switch (widget.backgroundStyle) {
              BackgroundStyle.pulse => _buildPulse(t),
              BackgroundStyle.aurora => _buildAurora(t),
              BackgroundStyle.drift => _buildDrift(t),
            },
          );
        },
      ),
    );
  }

  List<Widget> _buildPulse(double t) {
    final glowColor = switch (widget.screenStyle) {
      LiveScreenStyle.wave => const Color(0xFF22C55E),
      LiveScreenStyle.glass => const Color(0xFF94C4FF),
      LiveScreenStyle.halo => const Color(0xFF7AA2FF),
    };
    final scale = 0.92 + (math.sin(t * math.pi * 2) * 0.06);
    final alignment = switch (widget.screenStyle) {
      LiveScreenStyle.wave => const Alignment(-0.55, 0),
      LiveScreenStyle.glass => const Alignment(0.45, 0),
      LiveScreenStyle.halo => const Alignment(0.52, 0),
    };
    return [
      Align(
        alignment: alignment,
        child: Transform.scale(
          scale: scale,
          child: Container(
            width: 360,
            height: 360,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: glowColor.withValues(alpha: 0.08),
              boxShadow: [
                BoxShadow(
                  color: glowColor.withValues(alpha: 0.16),
                  blurRadius: 120,
                  spreadRadius: 40,
                ),
              ],
            ),
          ),
        ),
      ),
    ];
  }

  List<Widget> _buildAurora(double t) {
    return [
      Positioned.fill(
        child: Transform.translate(
          offset: Offset(40 * math.sin(t * math.pi * 2), 0),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF60A5FA).withValues(alpha: 0.12),
                  const Color(0xFF34D399).withValues(alpha: 0.08),
                  Colors.transparent,
                ],
                begin: Alignment(-1 + (t * 0.3), -0.4),
                end: Alignment(1, 0.8),
              ),
            ),
          ),
        ),
      ),
      Positioned.fill(
        child: Transform.translate(
          offset: Offset(-30 * math.cos(t * math.pi * 2), 18),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.transparent,
                  const Color(0xFF93C5FD).withValues(alpha: 0.09),
                  const Color(0xFF818CF8).withValues(alpha: 0.06),
                ],
                begin: Alignment(-0.6, -1),
                end: Alignment(0.8, 1),
              ),
            ),
          ),
        ),
      ),
    ];
  }

  List<Widget> _buildDrift(double t) {
    final offsets = [
      Offset(math.sin(t * math.pi * 2) * 26, math.cos(t * math.pi * 2) * 20),
      Offset(math.cos(t * math.pi * 2) * 18, math.sin(t * math.pi * 2) * 24),
    ];
    final colors = [
      const Color(0xFF93C5FD).withValues(alpha: 0.10),
      const Color(0xFF67E8F9).withValues(alpha: 0.08),
    ];
    final alignments = [const Alignment(-0.6, -0.2), const Alignment(0.56, 0.28)];
    return List<Widget>.generate(2, (index) {
      return Align(
        alignment: alignments[index],
        child: Transform.translate(
          offset: offsets[index],
          child: Container(
            width: index == 0 ? 320 : 260,
            height: index == 0 ? 320 : 260,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colors[index],
              boxShadow: [
                BoxShadow(
                  color: colors[index],
                  blurRadius: 110,
                  spreadRadius: 26,
                ),
              ],
            ),
          ),
        ),
      );
    });
  }
}

class _VideoBackground extends StatefulWidget {
  const _VideoBackground({required this.path, required this.fallback});

  final String path;
  final Widget fallback;

  @override
  State<_VideoBackground> createState() => _VideoBackgroundState();
}

class _VideoBackgroundState extends State<_VideoBackground> {
  VideoPlayerController? _controller;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final file = File(widget.path);
    if (!file.existsSync()) {
      return;
    }

    final controller = VideoPlayerController.file(file);
    try {
      await controller.initialize();
      await controller.setLooping(true);
      await controller.play();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _ready = true;
      });
    } catch (_) {
      await controller.dispose();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready || _controller == null) {
      return widget.fallback;
    }

    return FittedBox(
      fit: BoxFit.cover,
      child: SizedBox(
        width: _controller!.value.size.width,
        height: _controller!.value.size.height,
        child: VideoPlayer(_controller!),
      ),
    );
  }
}
