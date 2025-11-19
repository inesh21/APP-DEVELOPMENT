import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import 'data/countries.dart';
import 'models/country.dart';

void main() {
  runApp(WorldClockApp());
}

class WorldClockApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'World Clock',
      theme: ThemeData(primarySwatch: Colors.indigo),
      home: HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  @override
  _HomePageState createState() => _HomePageState();
}

// Home: contains toggle button (top-left), search bar and country list
class _HomePageState extends State<HomePage> {
  String _search = '';
  bool _isDarkMode = false; // controlled by the toggle button

  @override
  Widget build(BuildContext context) {
    final filtered = countries.where((c) {
      final q = _search.toLowerCase();
      return c.name.toLowerCase().contains(q) || c.timezone.toLowerCase().contains(q);
    }).toList();

    final bg = _isDarkMode
        ? LinearGradient(colors: [Colors.indigo.shade900, Colors.black87])
        : LinearGradient(colors: [Colors.blue.shade50, Colors.lightBlue.shade100]);

    final appBarColor = _isDarkMode ? Colors.grey[900] : Colors.indigo;

    return Scaffold(
      // AppBar with the custom toggle at the left and sticky search bar below
      appBar: AppBar(
        backgroundColor: appBarColor,
        title: Row(
          children: [
            // Compact visual toggle button
            GestureDetector(
              onTap: () => setState(() => _isDarkMode = !_isDarkMode),
              child: AnimatedContainer(
                duration: Duration(milliseconds: 300),
                width: 56,
                height: 30,
                padding: EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  color: _isDarkMode ? Colors.black54 : Colors.white,
                  boxShadow: [
                    BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2)),
                  ],
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // sun and moon icons
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Opacity(opacity: _isDarkMode ? 0.4 : 1.0, child: Padding(padding: EdgeInsets.only(left: 4), child: Text('🌞'))),
                        Opacity(opacity: _isDarkMode ? 1.0 : 0.4, child: Padding(padding: EdgeInsets.only(right: 4), child: Text('🌙'))),
                      ],
                    ),
                    // sliding knob
                    AnimatedAlign(
                      duration: Duration(milliseconds: 300),
                      alignment: _isDarkMode ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _isDarkMode ? Colors.grey[200] : Colors.orangeAccent,
                        ),
                      ),
                    )
                  ],
                ),
              ),
            ),
            SizedBox(width: 10),
            Expanded(child: Text('World Clock', style: TextStyle(fontSize: 18))),
          ],
        ),
        elevation: 2,
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8),
            child: _buildSearchField(),
          ),
        ),
      ),
      // Animated background that changes instantly when you toggle
      body: AnimatedContainer(
        duration: Duration(milliseconds: 300),
        decoration: BoxDecoration(gradient: bg),
        child: ListView.builder(
          padding: EdgeInsets.only(top: 8, bottom: 24),
          itemCount: filtered.length,
          itemBuilder: (context, index) {
            final Country c = filtered[index];
            return Card(
              color: _isDarkMode ? Colors.grey[850] : Colors.white,
              margin: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: ListTile(
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Image.network(c.flagUrl, width: 56, height: 36, fit: BoxFit.cover),
                ),
                title: Text(c.name, style: TextStyle(color: _isDarkMode ? Colors.white : Colors.black87)),
                subtitle: Text(c.timezone, style: TextStyle(color: _isDarkMode ? Colors.white70 : Colors.black54)),
                trailing: Icon(Icons.chevron_right, color: _isDarkMode ? Colors.white70 : Colors.black54),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => DetailPage(country: c, overrideDark: _isDarkMode),
                    ),
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildSearchField() {
    return TextField(
      style: TextStyle(color: _isDarkMode ? Colors.white : Colors.black87),
      decoration: InputDecoration(
        hintText: 'Search country or timezone...',
        hintStyle: TextStyle(color: _isDarkMode ? Colors.white54 : Colors.black45),
        prefixIcon: Icon(Icons.search, color: _isDarkMode ? Colors.white70 : Colors.black45),
        filled: true,
        fillColor: _isDarkMode ? Colors.black54 : Colors.white,
        contentPadding: EdgeInsets.symmetric(horizontal: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      ),
      onChanged: (v) => setState(() => _search = v),
    );
  }
}

// DetailPage shows analog clock + digital time and uses retrying async fetch
class DetailPage extends StatefulWidget {
  final Country country;
  final bool? overrideDark; // force dark? true => dark mode

  DetailPage({required this.country, this.overrideDark});

  @override
  _DetailPageState createState() => _DetailPageState();
}

class _DetailPageState extends State<DetailPage> {
  DateTime? localTime;
  bool loading = true;
  String? error;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // start the robust fetch (await + retries)
    _robustFetchTime();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  // robust fetch with retries and exponential backoff (async/await)
  Future<void> _robustFetchTime() async {
    setState(() {
      loading = true;
      error = null;
    });

    const int maxAttempts = 5;
    int attempt = 0;
    int delayMillis = 800; // initial wait for backoff

    while (attempt < maxAttempts) {
      attempt++;
      try {
        await _fetchTimeOnce(); // will throw on failure
        // success -> break out
        setState(() {
          loading = false;
          error = null;
        });
        return;
      } catch (e) {
        // last attempt -> show error. Otherwise wait & retry
        if (attempt >= maxAttempts) {
          setState(() {
            loading = false;
            error = 'Could not fetch time after $attempt attempts.\nLast error: $e';
          });
          return;
        } else {
          // wait and then try again
          await Future.delayed(Duration(milliseconds: delayMillis));
          delayMillis *= 2; // exponential backoff
        }
      }
    }
  }

  // single attempt to fetch; throws on failure
  Future<void> _fetchTimeOnce() async {
    final tz = widget.country.timezone;
    final url = Uri.parse('http://worldtimeapi.org/api/timezone/$tz');
    final res = await http.get(url).timeout(Duration(seconds: 10));
    if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
    final map = json.decode(res.body) as Map<String, dynamic>;
    final iso = map['datetime'] as String;
    localTime = DateTime.parse(iso);

    // start local ticker (only after successful fetch)
    _timer?.cancel();
    _timer = Timer.periodic(Duration(seconds: 1), (_) {
      setState(() {
        localTime = localTime!.add(Duration(seconds: 1));
      });
    });
  }

  bool get _isDaytime {
    if (widget.overrideDark != null) return !widget.overrideDark!;
    if (localTime == null) return true;
    final h = localTime!.hour;
    return h >= 6 && h < 18;
  }

  @override
  Widget build(BuildContext context) {
    final bg = _isDaytime
        ? LinearGradient(colors: [Colors.blue.shade300, Colors.lightBlue.shade100])
        : LinearGradient(colors: [Colors.indigo.shade900, Colors.black87]);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.country.name),
        actions: [
          IconButton(icon: Icon(Icons.refresh), onPressed: _robustFetchTime),
        ],
      ),
      body: AnimatedContainer(
        duration: Duration(milliseconds: 400),
        decoration: BoxDecoration(gradient: bg),
        child: SafeArea(
          child: Center(
            child: loading
                ? Column(mainAxisSize: MainAxisSize.min, children: [
              CircularProgressIndicator(),
              SizedBox(height: 12),
              Text('Loading time… (trying automatically)', style: TextStyle(color: Colors.white70)),
            ])
                : error != null
                ? Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.error, size: 48, color: Colors.white),
                SizedBox(height: 12),
                Text(error!, textAlign: TextAlign.center, style: TextStyle(color: Colors.white70)),
                SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: _robustFetchTime,
                  icon: Icon(Icons.refresh),
                  label: Text('Retry now'),
                ),
              ]),
            )
                : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Analog clock
                SizedBox(
                  width: 260,
                  height: 260,
                  child: CustomPaint(
                    painter: ClockPainter(time: localTime!),
                  ),
                ),
                SizedBox(height: 18),
                // digital time, bold & minimal
                Text(
                  DateFormat('HH:mm:ss').format(localTime!),
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 44,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  DateFormat('EEEE, d MMM y').format(localTime!),
                  style: TextStyle(color: Colors.white70),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Minimal custom painter for analog clock
class ClockPainter extends CustomPainter {
  final DateTime time;
  ClockPainter({required this.time});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width, size.height) / 2;
    final paintCircle = Paint()
      ..color = Colors.white.withOpacity(0.06)
      ..style = PaintingStyle.fill;

    // background circle
    canvas.drawCircle(center, radius, paintCircle);

    final tickPaint = Paint()
      ..color = Colors.white70
      ..strokeWidth = 2;

    // hour ticks
    for (int i = 0; i < 12; i++) {
      final angle = (i * 30) * pi / 180;
      final inner = Offset(center.dx + (radius - 14) * sin(angle), center.dy - (radius - 14) * cos(angle));
      final outer = Offset(center.dx + radius * sin(angle), center.dy - radius * cos(angle));
      canvas.drawLine(inner, outer, tickPaint);
    }

    // center dot
    final centerPaint = Paint()..color = Colors.white;
    canvas.drawCircle(center, 4, centerPaint);

    // hour hand
    final hourAngle = ((time.hour % 12) + time.minute / 60) * 30 * pi / 180;
    final hourHand = Offset(center.dx + (radius * 0.5) * sin(hourAngle), center.dy - (radius * 0.5) * cos(hourAngle));
    final hourPaint = Paint()..color = Colors.white..strokeWidth = 6..strokeCap = StrokeCap.round;
    canvas.drawLine(center, hourHand, hourPaint);

    // minute hand
    final minuteAngle = (time.minute + time.second / 60) * 6 * pi / 180;
    final minuteHand = Offset(center.dx + (radius * 0.72) * sin(minuteAngle), center.dy - (radius * 0.72) * cos(minuteAngle));
    final minutePaint = Paint()..color = Colors.white..strokeWidth = 4..strokeCap = StrokeCap.round;
    canvas.drawLine(center, minuteHand, minutePaint);

    // second hand
    final secondAngle = time.second * 6 * pi / 180;
    final secondHand = Offset(center.dx + (radius * 0.82) * sin(secondAngle), center.dy - (radius * 0.82) * cos(secondAngle));
    final secondPaint = Paint()..color = Colors.redAccent..strokeWidth = 2..strokeCap = StrokeCap.round;
    canvas.drawLine(center, secondHand, secondPaint);
  }

  @override
  bool shouldRepaint(covariant ClockPainter oldDelegate) {
    return oldDelegate.time.second != time.second || oldDelegate.time.minute != time.minute || oldDelegate.time.hour != time.hour;
  }
}
