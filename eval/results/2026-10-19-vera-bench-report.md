# Generation benchmark: bench1

Build: `bac89bf Do not let the model think while finishing a composed screen, and let the itinerary cover the search-or-form veto`. 5 runs. Reasoning effort: low.

## 1. Runs

| run | ok | attempts | wall s | requests | model s | reasoning s | reasoning tok | code s | tool calls | tools s |
|---|---|---|---|---|---|---|---|---|---|---|
| egg-1 | yes | 1 | 7.8 | 2 | 5.8 | 0.0 | 0 | 3.3 | 1 | 0.2 |
| melody-1 | yes | 1 | 11.3 | 2 | 7.9 | 0.0 | 0 | 5.4 | 2 | 0.3 |
| pill-1 | yes | 1 | 11.0 | 2 | 8.4 | 0.0 | 0 | 5.1 | 2 | 0.3 |
| shanghai-1 | yes | 0 | 5.0 | 0 | 0.0 | 0.0 | 0 | 0.0 | 0 | 0.0 |
| tip-1 | yes | 0 | 2.2 | 0 | 0.0 | 0.0 | 0 | 0.0 | 0 | 0.0 |

## 2. Per prompt

| prompt | runs | ok | first-attempt compile | median wall s | min–max s | median reasoning tok | median requests |
|---|---|---|---|---|---|---|---|
| egg | 1 | 1 | 1/1 | 7.8 | 7.8–7.8 | 0 | 2 |
| melody | 1 | 1 | 1/1 | 11.3 | 11.3–11.3 | 0 | 2 |
| pill | 1 | 1 | 1/1 | 11.0 | 11.0–11.0 | 0 | 2 |
| shanghai | 1 | 1 | 0/1 | 5.0 | 5.0–5.0 | 0 | 0 |
| tip | 1 | 1 | 0/1 | 2.2 | 2.2–2.2 | 0 | 0 |

## 3. Compile errors

No compile failed.

## 4. Tool calls

### egg-1

UI described up front (39): Column, Row, Card, Text, Spacer, Button, AppTheme, Hero, AdaptiveColumns, Header, Section, SectionHeader, ListGroup, ListItem, NumberListItem, ActionBar, IconButton, Badge, EmptyState, InsetBanner, Stat, NumberStat, MetricGroup, NumberText, ClockText, TextField, Toggle, Checkbox, Slider, Select, NumberField, TimeField, Progress, Ticker, TimelineItem, Snackbar, Spinner, Skeleton, Timeline

| round | tool | need | ms | returned | used in program |
|---|---|---|---|---|---|
| 1 | find_sdk_function | vibrate the phone | 169 | SensorServiceKit.vibrator.vibrate, SensorServiceKit.vibrator.startVibration, SensorServiceKit.vibrator.isSupportEffectSync, SensorServiceKit.vibrator.isSupportEffect, SensorServiceKit.vibrator.isHdHapticSupported, SensorServiceKit.vibrator.stopVibration, AudioKit.AudioManager.getRingerMode, AudioKit.AudioManager.setRingerMode, TelephonyKit.call.isRinging, TelephonyKit.call.hasVoiceCapability, AccessibilityKit.accessibility.isFlashReminderEnabledSync, TelephonyKit.call.setMuted, AccessibilityKit.accessibility.isFlashReminderEnabled, NotificationKit.notificationManager.isSupportDoNotDisturbMode, ArkUI.display.getFoldDisplayMode, AudioKit.AudioManager.setVolume | SensorServiceKit.vibrator.vibrate |

### melody-1

UI described up front (40): Column, Row, Card, Text, Spacer, Button, AppTheme, Hero, AdaptiveColumns, Header, Section, SectionHeader, ListGroup, ListItem, NumberListItem, ActionBar, IconButton, Badge, EmptyState, InsetBanner, Stat, NumberStat, MetricGroup, NumberText, ClockText, TextField, Toggle, Checkbox, Slider, Select, NumberField, TimeField, Progress, Ticker, Sparkline, Path, Snackbar, TimelineItem, Canvas, Timeline

| round | tool | need | ms | returned | used in program |
|---|---|---|---|---|---|
| 1 | find_sdk_function | write raw audio samples to the audio renderer with a sample rate | 173 | AudioKit.AudioRenderer.write, AudioKit.AudioRenderer.start, AudioKit.AudioRenderer.release, AudioKit.AudioRenderer.stop, AudioKit.AudioManager.setVolume, MediaKit.AVRecorder.start, AudioKit.audio.createTonePlayer, AudioKit.AudioManager.setMicrophoneMute, InputKit.inputDevice.setKeyboardRepeatRate, AudioKit.TonePlayer.start, AudioKit.AudioManager.getVolume, AudioKit.AudioManager.mute, AudioKit.AudioManager.setRingerMode, AudioKit.AudioManager.getMaxVolume, InputKit.pointer.setTouchpadPointerSpeed, PerformanceAnalysisKit.hiAppEvent.addProcessorFromConfig | AudioKit.AudioRenderer.write |
| 1 | find_sdk_function | turn the flashlight torch on and off | 135 | CameraKit.CameraManager.setTorchMode, InputKit.pointer.setTouchpadTapSwitch, InputKit.pointer.setTouchpadScrollSwitch, AccessibilityKit.accessibility.isFlashReminderEnabled, AccessibilityKit.accessibility.isFlashReminderEnabledSync, ConnectivityKit.wifiManager.enableWifi, InputKit.pointer.setTouchpadPinchSwitch, InputKit.pointer.getTouchpadTapSwitch, InputKit.pointer.setTouchpadSwipeSwitch, ConnectivityKit.wifiManager.enableSemiWifi, NotificationKit.notificationManager.setPriorityEnabled, AccessibilityKit.accessibility.setSeniorModeStateForSelf, ConnectivityKit.wifiManager.isOpenSoftApAllowed, ArkUI.window.setGestureNavigationEnabled, AbilityKit.overlay.setOverlayEnabled, IMEKit.inputMethod.setSimpleKeyboardEnabled | CameraKit.CameraManager.setTorchMode |

### pill-1

UI described up front (40): Column, Row, Card, Text, Spacer, Button, AppTheme, Hero, AdaptiveColumns, Header, Section, SectionHeader, ListGroup, ListItem, NumberListItem, ActionBar, IconButton, Badge, EmptyState, InsetBanner, Stat, NumberStat, MetricGroup, NumberText, ClockText, TextField, Toggle, Checkbox, Slider, Select, NumberField, TimeField, Progress, TimelineItem, Timeline, Ticker, Table, KeyValueGroup, KeyValueItem, TableRow

| round | tool | need | ms | returned | used in program |
|---|---|---|---|---|---|
| 1 | find_sdk_function | add a calendar event with a reminder alarm, repeating daily | 181 | CalendarKit.Calendar.addEvents, CalendarKit.Calendar.addEvent, CalendarKit.CalendarManager.createCalendar, BackgroundTasksKit.reminderAgentManager.deleteExcludeDates, CalendarKit.CalendarManager.getCalendar, CalendarKit.Calendar.deleteEvent, BackgroundTasksKit.reminderAgentManager.cancelAllReminders, NotificationKit.notificationManager.setSmartReminderEnabled, BackgroundTasksKit.reminderAgentManager.cancelReminderOnDisplay, NotificationKit.notificationManager.snoozeNotification, AccessibilityKit.accessibility.isFlashReminderEnabled, BackgroundTasksKit.reminderAgentManager.cancelReminder, CalendarKit.Calendar.getEvents, CalendarKit.CalendarManager.editEvent, BasicServicesKit.systemTimer.startTimer, AccessibilityKit.accessibility.isFlashReminderEnabledSync | CalendarKit.Calendar.addEvent |
| 1 | find_ui_component | a time of day picker field | 87 | Scroll, Cell, Divider | — |

### shanghai-1

No tool calls.

### tip-1

No tool calls.

Calls by tool: {'find_sdk_function': 4, 'find_ui_component': 1}. Results offered 67 items, final programs used 4.

## 5. Per-request timeline

| run | round | tools offered | first byte s | reasoning s | reasoning tok | code s | total s | in tok | cached | finish | calls |
|---|---|---|---|---|---|---|---|---|---|---|---|
| egg-1 | 1 | yes | 1.5 | 0.0 | 0 | 0.0 | 1.5 | 9189 | 768 | tool_calls | sdk_function |
| egg-1 | 2 | yes | 1.0 | 0.0 | 0 | 3.3 | 4.2 | 10636 | 9216 | stop |  |
| melody-1 | 1 | yes | 1.2 | 0.0 | 0 | 0.0 | 1.2 | 9600 | 768 | tool_calls | sdk_function, sdk_function |
| melody-1 | 2 | yes | 1.3 | 0.0 | 0 | 5.4 | 6.7 | 12541 | 9472 | stop |  |
| pill-1 | 1 | yes | 2.0 | 0.0 | 0 | 0.0 | 2.0 | 9191 | 1792 | tool_calls | sdk_function, ui_component |
| pill-1 | 2 | yes | 1.3 | 0.0 | 0 | 5.1 | 6.4 | 12024 | 9216 | stop |  |
