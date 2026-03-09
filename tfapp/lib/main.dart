import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:webview_flutter_android/webview_flutter_android.dart';

void main() {
  runApp(const TimeFlowApp());
}

// ═══════════════════════════════════════════
//  配色
// ═══════════════════════════════════════════
class C {
  static const bg      = Color(0xFFF5F0E8);
  static const surface = Color(0xFFFBF8F3);
  static const header  = Color(0xFFEDE8DE);
  static const border  = Color(0xFFD2CAC0);
  static const text    = Color(0xFF1C1917);
  static const muted   = Color(0xFF766F69);
  static const faint   = Color(0xFFAAA39D);
  static const accent  = Color(0xFFCF6347);
  static const todayBg = Color(0x14CF6347);
  static const todayHd = Color(0x26CF6347);
}

const List<Color> courseColors = [
  Color(0xFFD4907A), // 莫兰迪砖红
  Color(0xFF7FA8C9), // 莫兰迪天蓝
  Color(0xFF85AA8F), // 莫兰迪灰绿
  Color(0xFFA98BC2), // 莫兰迪淡紫
  Color(0xFFCDAA72), // 莫兰迪暖黄
  Color(0xFF7FB5B0), // 莫兰迪青灰
  Color(0xFFBF8B8B), // 莫兰迪玫瑰
  Color(0xFF8FA8C2), // 莫兰迪钢蓝
  Color(0xFF9EAF88), // 莫兰迪橄榄
  Color(0xFFC4956A), // 莫兰迪驼色
];

// ═══════════════════════════════════════════
//  数据模型
// ═══════════════════════════════════════════
class Course {
  final String name;
  final String teacher;
  final String room;
  final String weeks;
  final List<int> weekList; // 实际上课周次列表
  final int dayOfWeek;   // 1=周一 7=周日
  final int startPeriod;
  final int spanPeriods;
  final Color color;

  const Course({
    required this.name, required this.teacher, required this.room,
    required this.weeks, required this.weekList, required this.dayOfWeek,
    required this.startPeriod, required this.spanPeriods, required this.color,
  });

  Map<String, dynamic> toJson() => {
    'name': name, 'teacher': teacher, 'room': room, 'weeks': weeks,
    'weekList': weekList,
    'dayOfWeek': dayOfWeek, 'startPeriod': startPeriod, 'spanPeriods': spanPeriods,
    'colorValue': color.value,
  };

  factory Course.fromJson(Map<String, dynamic> j) => Course(
    name: j['name'], teacher: j['teacher'], room: j['room'], weeks: j['weeks'],
    weekList: (j['weekList'] as List?)?.map((e) => e as int).toList() ?? [],
    dayOfWeek: j['dayOfWeek'], startPeriod: j['startPeriod'], spanPeriods: j['spanPeriods'],
    color: Color(j['colorValue']),
  );
}



// 夏季作息：每年4月第一个周一到10月最后一个周日
// 通知插件
final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();
bool _notificationsEnabled = false;

Future<void> initNotifications() async {
  tz_data.initializeTimeZones();
  tz.setLocalLocation(tz.getLocation('Asia/Shanghai'));

  const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
  const initSettings = InitializationSettings(android: androidSettings);
  await _notificationsPlugin.initialize(initSettings);

  // 请求Android 13+通知权限
  final android = _notificationsPlugin.resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>();
  final granted = await android?.requestNotificationsPermission() ?? false;
  _notificationsEnabled = granted;
}

Future<void> scheduleClassNotifications(List<Course> courses, DateTime semesterStart) async {
  if (!_notificationsEnabled) return;
  // 取消所有旧通知
  await _notificationsPlugin.cancelAll();

  final now = DateTime.now();
  const androidDetails = AndroidNotificationDetails(
    'class_reminder', '上课提醒',
    channelDescription: '提前30分钟提醒上课',
    importance: Importance.high,
    priority: Priority.high,
  );
  const details = NotificationDetails(android: androidDetails);

  int id = 0;
  // 安排未来4周的通知
  for (int weekOffset = 0; weekOffset < 4; weekOffset++) {
    final weekStart = semesterStart.add(Duration(days: ((_currentWeek - 1 + weekOffset) * 7)));
    final weekNum = _currentWeek + weekOffset;
    for (final course in courses) {
      if (course.weekList.isNotEmpty && !course.weekList.contains(weekNum)) continue;
      // 找到这节课在本周的日期
      // dayOfWeek: 1=周一，weekStart是第一天
      final daysFromStart = (course.dayOfWeek - weekStart.weekday + 7) % 7;
      final courseDate = weekStart.add(Duration(days: daysFromStart));
      final period = periods.firstWhere((p) => p.number == course.startPeriod, orElse: () => periods.first);
      final timeParts = period.currentStart.split(':');
      final classTime = DateTime(courseDate.year, courseDate.month, courseDate.day,
          int.parse(timeParts[0]), int.parse(timeParts[1]));
      final notifyTime = classTime.subtract(const Duration(minutes: 30));
      if (notifyTime.isAfter(now)) {
        await _notificationsPlugin.zonedSchedule(
          id++,
          '📚 ${course.name}',
          '30分钟后开始 · ${period.currentStart} · ${course.room}',
          tz.TZDateTime.from(notifyTime, tz.local),
          details,
          androidScheduleMode: AndroidScheduleMode.alarmClock,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
        );
      }
    }
  }
}

int _currentWeek = 1; // 供scheduleClassNotifications使用

// 夏季作息开关
bool _summerMode = false;

// 开学日期（第1周周一）
DateTime? _semesterStart; // 用户设置前为null

DateTime _nearestMonday() {
  final now = DateTime.now();
  final daysBack = (now.weekday - 1) % 7; // 周一=0，周日=6
  return DateTime(now.year, now.month, now.day).subtract(Duration(days: daysBack));
}

Future<void> loadSemesterStart() async {
  final prefs = await SharedPreferences.getInstance();
  final ms = prefs.getInt('semesterStart');
  if (ms != null) {
    _semesterStart = DateTime.fromMillisecondsSinceEpoch(ms);
  } else {
    _semesterStart = _nearestMonday();
  }
}

Future<void> saveSemesterStart(DateTime date) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setInt('semesterStart', date.millisecondsSinceEpoch);
  _semesterStart = date;
}

bool isSummerSeason() => _summerMode;

Future<void> loadSummerPref() async {
  final prefs = await SharedPreferences.getInstance();
  _summerMode = prefs.getBool('summerMode') ?? false;
}

Future<void> saveSummerPref(bool value) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool('summerMode', value);
  _summerMode = value;
}

class Period {
  final int number;
  final String start;
  final String end;
  final String summerStart;
  final String summerEnd;
  const Period(this.number, this.start, this.end, this.summerStart, this.summerEnd);

  String get currentStart => isSummerSeason() ? summerStart : start;
  String get currentEnd   => isSummerSeason() ? summerEnd   : end;
}

const List<Period> periods = [
  Period(1,  '07:50','08:30','07:50','08:30'),
  Period(2,  '08:40','09:20','08:40','09:20'),
  Period(3,  '09:35','10:15','09:35','10:15'),
  Period(4,  '10:30','11:10','10:30','11:10'),
  Period(5,  '11:20','12:00','11:20','12:00'),
  Period(6,  '13:30','14:10','14:00','14:40'),
  Period(7,  '14:20','15:00','14:50','15:30'),
  Period(8,  '15:20','16:00','15:50','16:30'),
  Period(9,  '16:10','16:50','16:40','17:20'),
  Period(10, '18:30','19:10','19:00','19:40'),
  Period(11, '19:20','20:00','19:50','20:30'),
  Period(12, '20:10','20:50','20:40','21:20'),
];

// 把 "1-16周" 或 "7周,15周" 解析成周次列表
List<int> parseWeekList(String weeks) {
  final result = <int>{};
  final cleaned = weeks.replaceAll('周', '').replaceAll('，', ',');
  for (final part in cleaned.split(',')) {
    final trimmed = part.trim();
    if (trimmed.isEmpty) continue;
    if (trimmed.contains('-') || trimmed.contains('~') || trimmed.contains('～')) {
      final nums = RegExp(r'\d+').allMatches(trimmed).map((m) => int.parse(m.group(0)!)).toList();
      if (nums.length >= 2) {
        for (int w = nums[0]; w <= nums[1]; w++) result.add(w);
      }
    } else {
      final n = int.tryParse(trimmed);
      if (n != null) result.add(n);
    }
  }
  return result.toList()..sort();
}

// ═══════════════════════════════════════════
//  数据存储
// ═══════════════════════════════════════════
class ScheduleStore {
  static const _key = 'schedule_courses';

  static Future<List<Course>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List;
    return list.map((e) => Course.fromJson(e)).toList();
  }

  static Future<void> save(List<Course> courses) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(courses.map((c) => c.toJson()).toList()));
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}

// ═══════════════════════════════════════════
//  课表解析（南通大学格式）
// ═══════════════════════════════════════════
class ScheduleParser {
  static List<Course> parse(String html) {
    final courses = <Course>[];
    final colorMap = <String, Color>{};
    int colorIdx = 0;

    // 找所有td单元格
    final tdReg = RegExp(r'<td[^>]*>(.*?)</td>', dotAll: true);
    final textReg = RegExp(r'<[^>]+>');

    // 解析表格行列
    // 找table中的tr
    final trReg = RegExp(r'<tr[^>]*>(.*?)</tr>', dotAll: true);
    final rows = trReg.allMatches(html).toList();

    for (int rowIdx = 0; rowIdx < rows.length; rowIdx++) {
      final tds = tdReg.allMatches(rows[rowIdx].group(0)!).toList();
      for (int colIdx = 0; colIdx < tds.length; colIdx++) {
        final cell = tds[colIdx].group(1)!;
        final text = cell.replaceAll(textReg, ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
        if (text.isEmpty) continue;

        // 检测课程标记符
        if (!RegExp(r'[■◆▲★●]').hasMatch(text)) continue;

        // 提取课程名
        final nameMatch = RegExp(r'^(.+?)[■◆▲★●]').firstMatch(text);
        if (nameMatch == null) continue;
        final name = nameMatch.group(1)!.trim();
        if (name.isEmpty) continue;

        // 节次
        final periodsMatch = RegExp(r'[(（](\d+)[-~～](\d+)节[)）]').firstMatch(text);
        if (periodsMatch == null) continue;
        final startP = int.parse(periodsMatch.group(1)!);
        final endP   = int.parse(periodsMatch.group(2)!);
        final span   = endP - startP + 1;

        // 周数
        final weeksMatch = RegExp(r'(\d+[-~～]\d+周[^\s]*)').firstMatch(text);
        final weeks = weeksMatch?.group(1) ?? '';

        // 教室
        final roomMatch = RegExp(r'([A-Z][A-Z0-9\-]+)').firstMatch(text);
        final room = roomMatch?.group(1) ?? '';

        // 教师（2-5个汉字）
        final teacherMatch = RegExp(r'[\u4e00-\u9fa5]{2,5}(?=\s|$)').allMatches(text).toList();
        String teacher = '';
        if (teacherMatch.isNotEmpty) {
          teacher = teacherMatch.last.group(0)!;
        }

        // 列索引对应星期（跳过第0列时间列）
        final dow = colIdx; // 1=周一
        if (dow < 1 || dow > 7) continue;

        // 分配颜色
        if (!colorMap.containsKey(name)) {
          colorMap[name] = courseColors[colorIdx % courseColors.length];
          colorIdx++;
        }

        courses.add(Course(
          name: name, teacher: teacher, room: room, weeks: weeks,
          weekList: parseWeekList(weeks),
          dayOfWeek: dow, startPeriod: startP, spanPeriods: span,
          color: colorMap[name]!,
        ));
      }
    }
    return courses;
  }
}

// ═══════════════════════════════════════════
//  App
// ═══════════════════════════════════════════
class TimeFlowApp extends StatelessWidget {
  const TimeFlowApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '光流 TimeFlow',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true),
      home: const SchedulePage(),
    );
  }
}

// ═══════════════════════════════════════════
//  主页
// ═══════════════════════════════════════════
class SchedulePage extends StatefulWidget {
  const SchedulePage({super.key});
  @override
  State<SchedulePage> createState() => _SchedulePageState();
}

class _SchedulePageState extends State<SchedulePage> {
  int _week = 1;
  List<Course> _courses = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadCourses();
    // 计算当前周次（简单：从3月3日算第1周）
    if (_semesterStart != null) {
      final now = DateTime.now();
      final diff = now.difference(_semesterStart!).inDays;
      _week = (diff / 7).floor() + 1;
      if (_week < 1) _week = 1;
      if (_week > 20) _week = 20;
    }
  }

  Future<void> _loadCourses() async {
    await loadSummerPref();
  await initNotifications();
    await loadSemesterStart();
    final courses = await ScheduleStore.load();
    setState(() { _courses = courses; _loading = false; });
    _currentWeek = _week;
    if (_semesterStart != null) {
      scheduleClassNotifications(courses, _semesterStart!);
    }
  }

  Future<void> _saveCourses(List<Course> courses) async {
    await ScheduleStore.save(courses);
    setState(() => _courses = courses);
  }

  int get _todayDow => DateTime.now().weekday; // 保留但不再用于高亮判断

  void _openImport() async {
    final result = await Navigator.push<List<Course>>(
      context,
      MaterialPageRoute(builder: (_) => const ImportPage()),
    );
    if (result != null && result.isNotEmpty) {
      // 导入课表时强制重置开学日期为本周一
      await saveSemesterStart(_nearestMonday());
      setState(() {});
      await _saveCourses(result);
      if (mounted) {
        _openSettings(showSemesterHint: true);
      }
    }
  }

  void _openSettings({bool showSemesterHint = false}) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _SettingsSheet(
        showSemesterHint: showSemesterHint,
        onSummerChanged: () => setState(() {}),
        onSemesterChanged: () {
          setState(() {});
          if (_semesterStart != null) {
            _currentWeek = _week;
            scheduleClassNotifications(_courses, _semesterStart!);
          }
        },
        onDelete: () async {
          await ScheduleStore.clear();
          setState(() => _courses = []);
          if (mounted) Navigator.pop(context);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: C.bg,
      body: SafeArea(
        child: _loading
          ? const Center(child: CircularProgressIndicator(color: C.accent))
          : Column(
              children: [
                _TopBar(week: _week,
                  onPrev: () => setState(() => _week = (_week - 1).clamp(1, 20)),
                  onNext: () => setState(() => _week = (_week + 1).clamp(1, 20)),
                  onThisWeek: () { if (_semesterStart != null) { final now = DateTime.now(); setState(() => _week = ((now.difference(_semesterStart!).inDays/7).floor()+1).clamp(1,20)); } },
                  onImport: _openImport,
                  onSettings: _openSettings,
                ),
                _StatsBar(courses: _courses, week: _week),
                Expanded(
                  child: _courses.isEmpty
                    ? _EmptyState(onImport: _openImport)
                    : GestureDetector(
                        onHorizontalDragEnd: (details) {
                          if (details.primaryVelocity == null) return;
                          if (details.primaryVelocity! < -300) {
                            // 向左滑 → 下一周
                            setState(() => _week = (_week + 1).clamp(1, 20));
                          } else if (details.primaryVelocity! > 300) {
                            // 向右滑 → 上一周
                            setState(() => _week = (_week - 1).clamp(1, 20));
                          }
                        },
                        child: _ScheduleGrid(courses: _courses, todayDow: _todayDow, week: _week, semesterStart: _semesterStart),
                      ),
                ),
              ],
            ),
      ),
    );
  }
}

// ═══════════════════════════════════════════
//  空状态
// ═══════════════════════════════════════════
class _EmptyState extends StatelessWidget {
  final VoidCallback onImport;
  const _EmptyState({required this.onImport});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.calendar_today_outlined, size: 56, color: C.faint.withOpacity(0.5)),
          const SizedBox(height: 16),
          const Text('暂无课表', style: TextStyle(fontSize: 16, color: C.faint)),
          const SizedBox(height: 8),
          const Text('点击导入课表开始使用', style: TextStyle(fontSize: 13, color: C.faint)),
          const SizedBox(height: 24),
          GestureDetector(
            onTap: onImport,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
              decoration: BoxDecoration(color: C.accent, borderRadius: BorderRadius.circular(10)),
              child: const Text('导入课表', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500)),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════
//  顶栏
// ═══════════════════════════════════════════
class _TopBar extends StatelessWidget {
  final int week;
  final VoidCallback onPrev, onNext, onThisWeek, onImport, onSettings;
  const _TopBar({required this.week, required this.onPrev, required this.onNext,
    required this.onThisWeek, required this.onImport, required this.onSettings});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
      decoration: const BoxDecoration(
        color: C.surface,
        border: Border(bottom: BorderSide(color: C.border)),
      ),
      child: Column(children: [
        Row(children: [
          SvgPicture.asset('assets/logo.svg', width: 26, height: 26),
          const SizedBox(width: 7),
          const Text('光流 TimeFlow', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: C.text, letterSpacing: 0.5)),
          const Spacer(),
          GestureDetector(
            onTap: onImport,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
              decoration: BoxDecoration(color: C.accent, borderRadius: BorderRadius.circular(8)),
              child: const Text('导入课表', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500)),
            ),
          ),
          const SizedBox(width: 7),
          GestureDetector(
            onTap: onSettings,
            child: Container(
              width: 30, height: 30,
              decoration: BoxDecoration(color: C.header, borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.settings_outlined, color: C.muted, size: 16),
            ),
          ),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          _NavBtn(icon: Icons.chevron_left, onTap: onPrev),
          SizedBox(width: 72, child: Text('第 $week 周',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: C.text))),
          _NavBtn(icon: Icons.chevron_right, onTap: onNext),
          const Spacer(),
          GestureDetector(
            onTap: onThisWeek,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(border: Border.all(color: C.border), borderRadius: BorderRadius.circular(6)),
              child: const Text('本周', style: TextStyle(fontSize: 11, color: C.muted)),
            ),
          ),
        ]),
      ]),
    );
  }
}

class _NavBtn extends StatelessWidget {
  final IconData icon; final VoidCallback onTap;
  const _NavBtn({required this.icon, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 26, height: 26,
      decoration: BoxDecoration(color: C.header, borderRadius: BorderRadius.circular(7)),
      child: Icon(icon, size: 16, color: C.muted),
    ),
  );
}

// ═══════════════════════════════════════════
//  统计栏
// ═══════════════════════════════════════════
class _StatsBar extends StatelessWidget {
  final List<Course> courses; final int week;
  const _StatsBar({required this.courses, required this.week});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final dateStr = '${now.month.toString().padLeft(2,'0')}/${now.day.toString().padLeft(2,'0')}';
    final uniqueCourses = courses.map((c) => c.name).toSet().length;
    final totalPeriods = courses.fold<int>(0, (s, c) => s + c.spanPeriods);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: const BoxDecoration(color: C.surface, border: Border(bottom: BorderSide(color: C.border))),
      child: Row(children: [
        RichText(text: TextSpan(children: [
          TextSpan(text: '$uniqueCourses', style: const TextStyle(color: C.accent, fontWeight: FontWeight.w600, fontSize: 12)),
          const TextSpan(text: ' 门课本周', style: TextStyle(color: C.muted, fontSize: 11)),
        ])),
        Container(width: 1, height: 10, color: C.border, margin: const EdgeInsets.symmetric(horizontal: 8)),
        RichText(text: TextSpan(children: [
          TextSpan(text: '$totalPeriods', style: const TextStyle(color: C.accent, fontWeight: FontWeight.w600, fontSize: 12)),
          const TextSpan(text: ' 节课时', style: TextStyle(color: C.muted, fontSize: 11)),
        ])),
        const Spacer(),
        RichText(text: TextSpan(children: [
          TextSpan(text: '$dateStr ', style: const TextStyle(color: C.muted, fontSize: 11)),
          const TextSpan(text: '今日', style: TextStyle(color: C.accent, fontWeight: FontWeight.w600, fontSize: 11)),
        ])),
      ]),
    );
  }
}

// ═══════════════════════════════════════════
//  课程网格
// ═══════════════════════════════════════════
class _ScheduleGrid extends StatelessWidget {
  final List<Course> courses;
  final int todayDow;
  final int week;

  final DateTime? semesterStart;
  const _ScheduleGrid({required this.courses, required this.todayDow, required this.week, required this.semesterStart});

  static const double timeColW = 48.0;
  static const Set<int> dividers = {5, 9};

  // 根据可用高度动态计算格子高度
  // 12节 + 2个分隔行，分隔行高度 = cellH * 0.35
  static double calcCellH(double availH) {
    // availH = 12 * cellH + 2 * divH = 12 * cellH + 2 * cellH * 0.35 = cellH * 12.7
    return (availH / 12.7).clamp(40.0, 60.0);
  }

  static double divH(double cellH) => cellH * 0.35;

  double periodY(int p, double cellH) {
    double y = 0;
    for (final period in periods) {
      if (period.number == p) return y;
      y += cellH;
      if (dividers.contains(period.number)) y += divH(cellH);
    }
    return y;
  }

  double spanH(int start, int span, double cellH) {
    double h = 0; int counted = 0;
    for (final period in periods) {
      if (period.number < start) continue;
      if (counted >= span) break;
      h += cellH; counted++;
      if (dividers.contains(period.number) && counted < span) h += divH(cellH);
    }
    return h;
  }

  double totalH(double cellH) {
    double h = 0;
    for (final p in periods) { h += cellH; if (dividers.contains(p.number)) h += divH(cellH); }
    return h;
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    // weekStart = 第week周的第一天（即开学日 + (week-1)*7天）
    final weekStart = semesterStart != null
        ? semesterStart!.add(Duration(days: (week - 1) * 7))
        : now.subtract(Duration(days: now.weekday - 1));
    return LayoutBuilder(builder: (context, constraints) {
      final availH = constraints.maxHeight - 38; // 减去表头行高度
      final cellH = calcCellH(availH);
      return Column(children: [
        // 表头
        Row(children: [
          Container(width: timeColW, height: 38,
            decoration: const BoxDecoration(color: C.header,
              border: Border(right: BorderSide(color: C.border), bottom: BorderSide(color: C.border)))),
          ...List.generate(7, (i) {
            final isToday = weekStart.add(Duration(days: i)).day == now.day &&
              weekStart.add(Duration(days: i)).month == now.month &&
              weekStart.add(Duration(days: i)).year == now.year;
            final date = weekStart.add(Duration(days: i));
            final dayNames = ['一','二','三','四','五','六','日'];
            final dowLabel = dayNames[date.weekday - 1]; // date.weekday 1=周一..7=周日
            return Expanded(child: Container(height: 38,
              decoration: BoxDecoration(
                color: isToday ? C.todayHd : C.header,
                border: const Border(right: BorderSide(color: C.border), bottom: BorderSide(color: C.border))),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text('周$dowLabel', style: const TextStyle(fontSize: 9, color: C.muted)),
                Text('${date.month}/${date.day}',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: isToday ? C.accent : C.text)),
              ]),
            ));
          }),
        ]),
        // 网格主体
        Expanded(child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // 时间列：Stack绝对定位，文字不影响格子高度
          SizedBox(width: timeColW, child: Stack(children: [
            Column(children: [
              for (final p in periods) ...[
                Container(height: cellH,
                  decoration: const BoxDecoration(color: C.surface,
                    border: Border(right: BorderSide(color: C.border), bottom: BorderSide(color: C.border)))),
                if (dividers.contains(p.number))
                  Container(height: divH(cellH),
                    decoration: const BoxDecoration(color: C.surface,
                      border: Border(right: BorderSide(color: C.border), bottom: BorderSide(color: C.border)))),
              ],
            ]),
            for (final p in periods) ...[
              Positioned(
                top: periodY(p.number, cellH), left: 0, right: 1, height: cellH,
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text('${p.number}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: C.muted, height: 1.0)),
                  Text(p.currentStart, style: const TextStyle(fontSize: 8, color: C.faint, height: 1.3)),
                  Text(p.currentEnd,   style: const TextStyle(fontSize: 8, color: C.faint, height: 1.3)),
                ]),
              ),
              if (dividers.contains(p.number))
                Positioned(
                  top: periodY(p.number, cellH) + cellH, left: 0, right: 1, height: divH(cellH),
                  child: Center(child: Text(p.number == 5 ? '午休' : '傍晚',
                    style: const TextStyle(fontSize: 8, color: C.faint))),
                ),
            ],
          ])),
          // 7天列
          Expanded(child: Stack(children: [
            // 背景
            Row(children: List.generate(7, (i) {
              final isToday = weekStart.add(Duration(days: i)).day == now.day &&
              weekStart.add(Duration(days: i)).month == now.month &&
              weekStart.add(Duration(days: i)).year == now.year;
              return Expanded(child: Column(children: [
                for (final p in periods) ...[
                  Container(height: cellH,
                    decoration: BoxDecoration(
                      color: isToday ? C.todayBg : Colors.transparent,
                      border: const Border(right: BorderSide(color: C.border), bottom: BorderSide(color: C.border)))),
                  if (dividers.contains(p.number))
                    Container(height: divH(cellH),
                      decoration: BoxDecoration(
                        color: isToday ? const Color(0x1ACF6347) : C.header,
                        border: const Border(right: BorderSide(color: C.border), bottom: BorderSide(color: C.border)))),
                ],
              ]));
            })),
            // 课程卡片：真正区间重叠检测，本周优先、最长span显示
            ...() {
              // 已结束的课程（weekList非空且最大周次 < 当前周）不显示
              final visibleCourses = courses.where((c) {
                if (c.weekList.isEmpty) return true;
                return c.weekList.any((w) => w >= week);
              }).toList();
              // 按 dayOfWeek 分组
              final byDay = <int, List<Course>>{};
              for (final c in visibleCourses) byDay.putIfAbsent(c.dayOfWeek, () => []).add(c);

              final List<Widget> cards = [];
              for (final dayGroup in byDay.values) {
                // 排序：本周优先，相同则 spanPeriods 长的优先
                final sorted = [...dayGroup]..sort((a, b) {
                  final aIn = a.weekList.isEmpty || a.weekList.contains(week);
                  final bIn = b.weekList.isEmpty || b.weekList.contains(week);
                  if (aIn != bIn) return aIn ? -1 : 1;
                  return b.spanPeriods.compareTo(a.spanPeriods);
                });

                // 贪心：依次取代表，合并所有与它区间重叠的课程
                final used = <int>{};
                for (int i = 0; i < sorted.length; i++) {
                  if (used.contains(i)) continue;
                  final group = [i];
                  used.add(i);
                  for (int j = i + 1; j < sorted.length; j++) {
                    if (used.contains(j)) continue;
                    final overlaps = group.any((gi) {
                      final a = sorted[gi], b = sorted[j];
                      return a.startPeriod < b.startPeriod + b.spanPeriods &&
                             b.startPeriod < a.startPeriod + a.spanPeriods;
                    });
                    if (overlaps) { group.add(j); used.add(j); }
                  }
                  final primary = sorted[i];
                  final isInWeek = group.map((gi) => sorted[gi])
                      .any((c) => c.weekList.isEmpty || c.weekList.contains(week))
                    ? (primary.weekList.isEmpty || primary.weekList.contains(week))
                    : false;
                  final col = (primary.dayOfWeek - weekStart.weekday + 7) % 7;
                  cards.add(_CourseCard(
                    col: col,
                    top: periodY(primary.startPeriod, cellH),
                    height: spanH(primary.startPeriod, primary.spanPeriods, cellH),
                    course: primary,
                    inCurrentWeek: primary.weekList.isEmpty || primary.weekList.contains(week),
                    hasConflict: group.length > 1,
                    onTap: () => showModalBottomSheet(
                      context: context,
                      backgroundColor: Colors.transparent,
                      builder: (_) => _CourseDetailSheet(courses: group.map((gi) => sorted[gi]).toList()),
                    ),
                  ));
                }
              }
              return cards;
            }(),
          ])),
        ])),
      ]);
    });
  }
}

// ═══════════════════════════════════════════
//  课程卡片
// ═══════════════════════════════════════════
class _CourseCard extends StatelessWidget {
  final int col; final double top, height;
  final Course course; final VoidCallback onTap;
  final bool inCurrentWeek;
  final bool hasConflict;
  const _CourseCard({required this.col, required this.top, required this.height, required this.course, required this.onTap, this.inCurrentWeek = true, this.hasConflict = false});

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(child: LayoutBuilder(builder: (ctx, constraints) {
      final colW = constraints.maxWidth / 7;
      return Stack(children: [Positioned(
        left: col * colW + 1.5, top: top + 1.5,
        width: colW - 3, height: height - 3,
        child: GestureDetector(onTap: onTap, child: Stack(children: [
          // 卡片主体
          Positioned.fill(child: inCurrentWeek
            ? Container(
                decoration: BoxDecoration(color: course.color, borderRadius: BorderRadius.circular(5)),
                padding: const EdgeInsets.all(3),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text(course.name,
                    style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: Colors.white, height: 1.3),
                    maxLines: 4, overflow: TextOverflow.ellipsis),
                  Text(course.room,
                    style: TextStyle(fontSize: 7.5, color: Colors.white.withOpacity(0.85)),
                    maxLines: 4, overflow: TextOverflow.clip),
                ]),
              )
            : CustomPaint(
                painter: _DashedBorderPainter(color: course.color.withOpacity(0.5)),
                child: Container(
                  decoration: BoxDecoration(
                    color: course.color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  padding: const EdgeInsets.all(3),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text(course.name,
                      style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: course.color.withOpacity(0.7), height: 1.3),
                      maxLines: 4, overflow: TextOverflow.ellipsis),
                    Text(course.room,
                      style: TextStyle(fontSize: 7.5, color: course.color.withOpacity(0.5)),
                      maxLines: 4, overflow: TextOverflow.clip),
                  ]),
                ),
              ),
          ),
          // 右上角冲突三角标
          if (hasConflict)
            Positioned(
              top: 0, right: 0,
              child: ClipRRect(
                borderRadius: const BorderRadius.only(topRight: Radius.circular(5)),
                child: CustomPaint(
                  size: const Size(14, 14),
                  painter: _ConflictTrianglePainter(
                    color: inCurrentWeek
                        ? Colors.white.withOpacity(0.55)
                        : course.color.withOpacity(0.45),
                  ),
                ),
              ),
            ),
        ])),
      )]);
    }));
  }
}

// 右上角三角画笔
class _ConflictTrianglePainter extends CustomPainter {
  final Color color;
  const _ConflictTrianglePainter({required this.color});
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color..style = PaintingStyle.fill;
    final path = Path()
      ..moveTo(size.width, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(0, 0)
      ..close();
    canvas.drawPath(path, paint);
  }
  @override
  bool shouldRepaint(_ConflictTrianglePainter old) => old.color != color;
}

// ═══════════════════════════════════════════
//  虚线边框画笔
// ═══════════════════════════════════════════
class _DashedBorderPainter extends CustomPainter {
  final Color color;
  const _DashedBorderPainter({required this.color});
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color..strokeWidth = 1.2..style = PaintingStyle.stroke;
    const dash = 4.0, gap = 3.0, r = 5.0;
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, size.width, size.height), const Radius.circular(r)));
    final metrics = path.computeMetrics();
    for (final m in metrics) {
      double d = 0;
      while (d < m.length) {
        canvas.drawPath(m.extractPath(d, d + dash), paint);
        d += dash + gap;
      }
    }
  }
  @override bool shouldRepaint(_DashedBorderPainter o) => o.color != color;
}

// ═══════════════════════════════════════════
//  课程详情
// ═══════════════════════════════════════════
class _CourseDetailSheet extends StatelessWidget {
  final List<Course> courses;
  const _CourseDetailSheet({required this.courses});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(color: C.surface, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Center(child: Container(width: 36, height: 4, margin: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(color: C.border, borderRadius: BorderRadius.circular(2)))),
        if (courses.length > 1)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: C.accent.withOpacity(0.12), borderRadius: BorderRadius.circular(4)),
                child: Text('${courses.length} 门课重叠',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFFB8860B))),
              ),
            ]),
          ),
        for (int i = 0; i < courses.length; i++) ...[
          if (i > 0) Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Divider(color: C.border, height: 1),
          ),
          _CourseSection(course: courses[i]),
        ],
        const SizedBox(height: 8),
      ]),
    );
  }
}

class _CourseSection extends StatelessWidget {
  final Course course;
  const _CourseSection({required this.course});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(width: 4, height: 44, decoration: BoxDecoration(color: course.color, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 12),
        Expanded(child: Text(course.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: C.text, height: 1.3))),
      ]),
      const SizedBox(height: 10),
      _DetailRow(icon: Icons.access_time_outlined, label: '节次', value: '${course.startPeriod}–${course.startPeriod+course.spanPeriods-1}节 · ${course.weeks}'),
      const SizedBox(height: 8),
      _DetailRow(icon: Icons.location_on_outlined, label: '教室', value: course.room),
      const SizedBox(height: 8),
      _DetailRow(icon: Icons.person_outline, label: '教师', value: course.teacher),
    ]);
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon; final String label, value;
  const _DetailRow({required this.icon, required this.label, required this.value});
  @override
  Widget build(BuildContext context) => Row(children: [
    Icon(icon, size: 15, color: C.faint), const SizedBox(width: 8),
    Text(label, style: const TextStyle(fontSize: 13, color: C.muted)), const SizedBox(width: 6),
    Expanded(child: Text(value, style: const TextStyle(fontSize: 13, color: C.text))),
  ]);
}

// ═══════════════════════════════════════════
//  设置面板
// ═══════════════════════════════════════════
class _SettingsSheet extends StatefulWidget {
  final VoidCallback onDelete;
  final VoidCallback onSummerChanged;
  final VoidCallback onSemesterChanged;
  final bool showSemesterHint;
  const _SettingsSheet({required this.onDelete, required this.onSummerChanged, required this.onSemesterChanged, this.showSemesterHint = false});
  @override
  State<_SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<_SettingsSheet> {
  late bool _summer;
  DateTime? _start;

  @override
  void initState() {
    super.initState();
    _summer = _summerMode;
    _start = _semesterStart;
  }

  void _setSummer(bool value) async {
    await saveSummerPref(value);
    setState(() => _summer = value);
    widget.onSummerChanged();
  }

  void _pickSemesterStart() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _start ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      helpText: '选择开学第一天',
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(primary: C.accent, onPrimary: Colors.white, surface: C.surface),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      await saveSemesterStart(picked);
      setState(() => _start = _semesterStart);
      widget.onSemesterChanged();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(color: C.surface, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Center(child: Container(width: 36, height: 4, margin: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(color: C.border, borderRadius: BorderRadius.circular(2)))),
        const Text('设置', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: C.text)),
        const SizedBox(height: 20),

        // 夏季作息开关
        Row(children: [
          const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('夏季作息', style: TextStyle(fontSize: 14, color: C.text, fontWeight: FontWeight.w500)),
            SizedBox(height: 2),
            Text('开启后下午和晚上课程推迟30分钟', style: TextStyle(fontSize: 12, color: C.muted)),
          ]),
          const Spacer(),
          Switch(
            value: _summer,
            onChanged: _setSummer,
            activeColor: const Color(0xFFE07B39),      // 夏天暖橙
            inactiveTrackColor: const Color(0xFFB0C8E8), // 冬天冷蓝
            inactiveThumbColor: const Color(0xFF6B9AC4),
          ),
        ]),
        const Divider(height: 28, color: C.border),

        // 开学日期
        if (widget.showSemesterHint)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: C.accent.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: C.accent.withOpacity(0.3)),
            ),
            child: const Row(children: [
              Icon(Icons.info_outline, size: 16, color: C.accent),
              SizedBox(width: 8),
              Expanded(child: Text('课表已导入！请设置开学第一天以正确显示周次和日期。',
                style: TextStyle(fontSize: 12, color: C.accent))),
            ]),
          ),
        Row(children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('开学日期', style: TextStyle(fontSize: 14, color: C.text, fontWeight: FontWeight.w500)),
            const SizedBox(height: 2),
            Text(_start != null ? '开学第一天：${_start!.year}/${_start!.month}/${_start!.day}' : '未设置，请点击修改',
              style: const TextStyle(fontSize: 12, color: C.muted)),
          ]),
          const Spacer(),
          GestureDetector(
            onTap: _pickSemesterStart,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(border: Border.all(color: C.border), borderRadius: BorderRadius.circular(8)),
              child: const Text('修改', style: TextStyle(fontSize: 13, color: C.muted)),
            ),
          ),
        ]),
        const Divider(height: 28, color: C.border),

        // 删除课表
        Row(children: [
          const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('删除课表数据', style: TextStyle(fontSize: 14, color: C.text, fontWeight: FontWeight.w500)),
            SizedBox(height: 2),
            Text('清除已导入的全部课程', style: TextStyle(fontSize: 12, color: C.muted)),
          ]),
          const Spacer(),
          GestureDetector(
            onTap: () => showDialog(context: context, builder: (_) => AlertDialog(
              backgroundColor: C.surface,
              title: const Text('确认删除', style: TextStyle(fontSize: 16, color: C.text)),
              content: const Text('确定要删除全部课表数据吗？此操作不可撤销。', style: TextStyle(color: C.muted)),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消', style: TextStyle(color: C.muted))),
                TextButton(onPressed: () { Navigator.pop(context); widget.onDelete(); },
                  child: const Text('删除', style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600))),
              ],
            )),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(border: Border.all(color: C.border), borderRadius: BorderRadius.circular(8)),
              child: const Text('删除', style: TextStyle(fontSize: 13, color: C.muted)),
            ),
          ),
        ]),
        const SizedBox(height: 8),
      ]),
    );
  }
}

// ═══════════════════════════════════════════
//  导入页（WebView）
// ═══════════════════════════════════════════
class ImportPage extends StatefulWidget {
  const ImportPage({super.key});
  @override
  State<ImportPage> createState() => _ImportPageState();
}

class _ImportPageState extends State<ImportPage> {
  late final WebViewController _controller;
  bool _loading = true;
  bool _parsing = false;

  static const _url = 'https://tdjw.ntu.edu.cn/';

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) => setState(() => _loading = true),
        onPageFinished: (_) => setState(() => _loading = false),

        onNavigationRequest: (request) {
          // 拦截重定向到SSO登录页，改为重新发起请求，避免ERR_CACHE_MISS
          if (!request.isMainFrame) return NavigationDecision.navigate;
          final uri = Uri.tryParse(request.url);
          if (uri == null) return NavigationDecision.navigate;
          // 允许正常导航
          return NavigationDecision.navigate;
        },

      ))
      ..loadRequest(Uri.parse(_url));

  }

  Future<void> _parseSchedule() async {
    setState(() => _parsing = true);
    try {
      // 只用一句简单JS拿table1的outerHTML，不注入复杂逻辑
      final raw = await _controller.runJavaScriptReturningResult(
        'document.getElementById("table1") ? document.getElementById("table1").outerHTML : ""'
      ) as String;

      // 去掉外层引号和转义
      var html = raw;
      if (html.startsWith('"') && html.endsWith('"')) {
        html = html.substring(1, html.length - 1);
      }
      html = html
          .replaceAll(r'\"', '"')
          .replaceAll(r'\n', '\n')
          .replaceAll(r'\t', '\t')
          .replaceAll(r'\/', '/')
          .replaceAll(r'\u003C', '<')
          .replaceAll(r'\u003c', '<')
          .replaceAll(r'\u003E', '>')
          .replaceAll(r'\u003e', '>')
          .replaceAll(r'\u0026', '&')
          .replaceAll(r'\u0027', "'")
          .replaceAll(r'\u003D', '=')
          .replaceAll(r'\u003d', '=');

      if (html.length < 10) throw Exception('未找到课表，请先点击查询');

      final courses = _parseHtml(html);
      setState(() => _parsing = false);
      if (!mounted) return;

      if (courses.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('未解析到课程，请确认课表已加载完成'),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
        ));
      } else {
        Navigator.pop(context, courses);
      }
    } catch (e) {
      setState(() => _parsing = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('解析失败：$e'),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  static String _stripTags(String s) {
    return s
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .replaceAll('&nbsp;', ' ')
        .replaceAll(RegExp(r'&\w+;'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  List<Course> _parseHtml(String html) {
    final courses = <Course>[];
    final colorMap = <String, Color>{};
    int colorIdx = 0;

    // 找所有有 id="dayCol-periodRow" 格式的 td（有课程内容的格子）
    final tdReg = RegExp(
      r'<td([^>]*?id=["\x27](\d+)-(\d+)["\x27][^>]*)>([\s\S]*?)</td>',
      caseSensitive: false,
    );

    // 找每个 timetable_con 块的起始位置
    final conStartReg = RegExp(
      r'<div\s+class=(["\x27])timetable_con\b',
      caseSensitive: false,
    );

    // 从图标后面提取信息：格式 glyphicon-xxx ... </font></span> <font color>内容</font>
    RegExp _iconReg(String icon) => RegExp(
      'glyphicon-$icon[\\s\\S]*?</font>\\s*</span>\\s*<font[^>]*>([\\s\\S]*?)</font>',
      caseSensitive: false,
    );
    final periodIconReg  = _iconReg('time');
    final locationIconReg = _iconReg('map-marker');
    final teacherIconReg  = _iconReg('user');

    for (final tdMatch in tdReg.allMatches(html)) {
      final dayOfWeek = int.tryParse(tdMatch.group(2) ?? '') ?? 0;
      if (dayOfWeek < 1 || dayOfWeek > 7) continue;

      final inner = tdMatch.group(4) ?? '';
      if (!inner.contains('timetable_con')) continue;

      // 找到所有 timetable_con 块的起始位置，按位置切割
      final starts = conStartReg.allMatches(inner).map((m) => m.start).toList();
      if (starts.isEmpty) continue;

      for (int i = 0; i < starts.length; i++) {
        final blockStart = starts[i];
        final blockEnd = i + 1 < starts.length ? starts[i + 1] : inner.length;
        final block = inner.substring(blockStart, blockEnd);

        // 提取课程名（.title 的 span 或 u 标签内容）
        final titleMatch = RegExp(
          r'class=(["\x27])title[^>]*>([\s\S]*?)</',
          caseSensitive: false,
        ).firstMatch(block);
        if (titleMatch == null) continue;

        String name = _stripTags(titleMatch.group(2) ?? '').trim();
        name = name.replaceAll(RegExp(r'^【[^】]+】'), '').trim(); // 去【调】
        name = name.replaceAll(RegExp(r'[■▲◆]\s*$'), '').trim(); // 去标记符
        if (name.isEmpty) continue;

        // 提取节次和周次
        int sp = 1, ep = 1;
        String weeks = '';
        final pwMatch = periodIconReg.firstMatch(block);
        if (pwMatch != null) {
          final pwText = _stripTags(pwMatch.group(1) ?? '').trim();
          // 格式：(1-3节)1-16周  或  (3-3节)11周
          final periodMatch = RegExp(r'\((\d+)-(\d+)节\)').firstMatch(pwText);
          if (periodMatch != null) {
            sp = int.tryParse(periodMatch.group(1)!) ?? 1;
            ep = int.tryParse(periodMatch.group(2)!) ?? sp;
          }
          // 周次：括号之后的部分
          final afterParen = pwText.replaceFirst(RegExp(r'^\([^)]+\)'), '').trim();
          if (afterParen.isNotEmpty) weeks = afterParen;
        }

        // 提取教室（地点图标后）
        String room = '';
        final locMatch = locationIconReg.firstMatch(block);
        if (locMatch != null) {
          final locText = _stripTags(locMatch.group(1) ?? '').trim();
          // 格式：啬园校区  JX07-409（张謇专用）  或  啬园校区  38-406
          final campusIdx = locText.indexOf('校区');
          final afterCampus = campusIdx >= 0
              ? locText.substring(campusIdx + 2).trim()
              : locText;
          room = afterCampus.replaceAll(RegExp(r'\s+'), ' ').trim();
        }

        // 提取教师
        String teacher = '';
        final teacherMatch = teacherIconReg.firstMatch(block);
        if (teacherMatch != null) {
          teacher = _stripTags(teacherMatch.group(1) ?? '').trim();
        }

        if (!colorMap.containsKey(name)) {
          colorMap[name] = courseColors[colorIdx % courseColors.length];
          colorIdx++;
        }

        final wl = parseWeekList(weeks);
        courses.add(Course(
          name: name,
          teacher: teacher,
          room: room,
          weeks: weeks,
          weekList: wl,
          dayOfWeek: dayOfWeek,
          startPeriod: sp,
          spanPeriods: (ep - sp + 1).clamp(1, 6),
          color: colorMap[name]!,
        ));
      }
    }
    return courses;
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: C.bg,
      appBar: AppBar(
        backgroundColor: C.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: C.muted),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('导入课表', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: C.text)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: C.border),
        ),
        actions: [

          if (_parsing)
            const Padding(padding: EdgeInsets.all(14), child: SizedBox(width: 20, height: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: C.accent)))
          else
            TextButton(
              onPressed: _parseSchedule,
              child: const Text('获取课表', style: TextStyle(color: C.accent, fontWeight: FontWeight.w600)),
            ),
        ],
      ),
      body: Stack(children: [
        WebViewWidget(controller: _controller),
        if (_loading) const LinearProgressIndicator(color: C.accent, backgroundColor: Colors.transparent),
      ]),
    );
  }
}