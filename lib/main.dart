import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:uuid/uuid.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(fileName: ".env");

  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
  );

  runApp(const CarBookingApp());
}

class CarBookingApp extends StatelessWidget {
  const CarBookingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Car Booking',
      home: AuthGate(),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        final session = snapshot.data?.session ??
            Supabase.instance.client.auth.currentSession;

        if (session == null) {
          return const LoginScreen();
        }

        return const CalendarScreen();
      },
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final firstNameController = TextEditingController();

  bool isLogin = true;

  String _displayName = '';

  Future<void> submit() async {
    try {
      final email = emailController.text.trim();
      final password = passwordController.text;

      if (isLogin) {
        await Supabase.instance.client.auth.signInWithPassword(
          email: email,
          password: password,
        );

        final user = Supabase.instance.client.auth.currentUser;
        _displayName = user?.userMetadata?['full_name'] ?? 'User';
      } else {
        _displayName = firstNameController.text.trim().isEmpty
            ? 'User'
            : firstNameController.text.trim();

        final res = await Supabase.instance.client.auth.signUp(
          email: email,
          password: password,
        );

        final user = res.user ?? Supabase.instance.client.auth.currentUser;

        if (user != null) {
          await Supabase.instance.client.auth.updateUser(
            UserAttributes(data: {'full_name': _displayName}),
          );
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }



  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(isLogin ? 'Login' : 'Sign Up')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            if (!isLogin)
              TextField(
                controller: firstNameController,
                decoration: const InputDecoration(labelText: 'Your Name'),
              ),
            TextField(
              controller: emailController,
              decoration: const InputDecoration(labelText: 'Email'),
            ),
            TextField(
              controller: passwordController,
              decoration: const InputDecoration(labelText: 'Password'),
              obscureText: true,
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: submit,
              child: Text(isLogin ? 'Login' : 'Sign Up'),
            ),
            TextButton(
              onPressed: () => setState(() => isLogin = !isLogin),
              child: Text(
                isLogin
                    ? 'No account? Sign up'
                    : 'Already have an account? Login',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  final supabase = Supabase.instance.client;

  DateTime _selectedDay = DateTime.now();
  DateTime _focusedDay = DateTime.now();
  Set<String> _selectedTimes = {};

  bool repeatWeekly = false;
  DateTime? repeatUntil;

  final String carId = 'car_1';

  final List<String> timeSlots = [
    '6:00 AM - 7:00 AM','7:00 AM - 8:00 AM','8:00 AM - 9:00 AM','9:00 AM - 10:00 AM','10:00 AM - 11:00 AM','11:00 AM - 12:OO PM',
    '12:00 PM - 1:00 PM','1:00 PM - 2:00 PM','2:00 PM - 3:00 PM','3:00 PM - 4:00 PM','4:00 PM - 5:00 PM','5:00 PM - 6:00 PM',
    '6:00 PM - 7:00 PM','7:00 PM - 8:00 PM','8:00 PM - 9:00 PM','9:00 PM - 10:00 PM','10:00 PM - 11:00 PM',
  ];

  List<Map<String, dynamic>> bookedTimes = [];
  Map<DateTime, List<int>> bookingsPerDay = {};

  @override
  void initState() {
    super.initState();
    loadBookingsForDay(_selectedDay);
  }

  bool isContinuousSelection(List<String> times) {
    final indexes = times.map((t) => timeSlots.indexOf(t)).toList()..sort();
    for (int i = 1; i < indexes.length; i++) {
      if (indexes[i] != indexes[i - 1] + 1) return false;
    }
    return true;
  }

  bool slotIsBooked(String slot, Map<String, dynamic> booking) {
    final s = timeSlots.indexOf(booking['start_time']);
    final e = timeSlots.indexOf(booking['end_time']);
    final i = timeSlots.indexOf(slot);
    return i >= s && i <= e;
  }

  List<DateTime> generateWeeklyDates(DateTime start, DateTime until) {
    final dates = <DateTime>[];
    var current = start;
    while (!current.isAfter(until)) {
      dates.add(current);
      current = current.add(const Duration(days: 7));
    }
    return dates;
  }

  Future<bool> hasConflict(
    DateTime date,
    String startTime,
    String endTime,
  ) async {
    final dateStr = date.toIso8601String().split('T')[0];

    final res = await supabase
        .from('bookings')
        .select()
        .eq('car_id', carId)
        .eq('booking_date', dateStr);

    final newStart = timeSlots.indexOf(startTime);
    final newEnd = timeSlots.indexOf(endTime);

    for (final b in res) {
      final s = timeSlots.indexOf(b['start_time']);
      final e = timeSlots.indexOf(b['end_time']);
      if (newStart <= e && newEnd >= s) return true;
    }
    return false;
  }

  Future<void> loadBookingsForDay(DateTime day) async {
    final res = await supabase
        .from('bookings')
        .select('id, booking_date, start_time, end_time, user_id, user_name, recurring_group_id, is_recurring')
        .eq('car_id', carId);

    Map<DateTime, List<int>> markers = {};
    List<Map<String, dynamic>> dayBookings = [];

    for (final e in res) {
      final d = DateTime.parse(e['booking_date']);
      final simple = DateTime(d.year, d.month, d.day);

      markers.putIfAbsent(simple, () => []).add(1);
      if (isSameDay(simple, day)) dayBookings.add(e);
    }

    if (!mounted) return;
    setState(() {
      bookingsPerDay = markers;
      bookedTimes = dayBookings;
      _selectedTimes.clear();
    });
  }

  Future<void> bookCar() async {
    if (_selectedTimes.isEmpty) return;

    final user = supabase.auth.currentUser;
    if (user == null) return;

    final sorted = _selectedTimes.toList()
      ..sort((a, b) =>
          timeSlots.indexOf(a).compareTo(timeSlots.indexOf(b)));

    if (!isContinuousSelection(sorted)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select continuous time slots for single reservation')),
      );
      return;
    }

    final startTime = sorted.first;
    final endTime = sorted.last;
    final name = user.userMetadata?['full_name'] ?? 'User';

    final recurringGroupId = 
      repeatWeekly ? const Uuid().v4() : null;

    final dates = repeatWeekly && repeatUntil != null
        ? generateWeeklyDates(_selectedDay, repeatUntil!)
        : [_selectedDay];

    for (final d in dates) {
      if (await hasConflict(d, startTime, endTime)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Conflict on ${d.toString().split(' ')[0]}')),
        );
        return;
      }
    }

    final inserts = dates.map((d) {
      final dateStr = d.toIso8601String().split('T')[0];
      return {
        'car_id': carId,
        'booking_date': dateStr,
        'start_time': startTime,
        'end_time': endTime,
        'user_id': user.id,
        'user_name': name,
        'is_recurring': repeatWeekly,
        'recurring_day': repeatWeekly ? d.weekday : null,
        'recurring_group_id': recurringGroupId,
        'recurring_until':
            repeatWeekly ? repeatUntil!.toIso8601String().split('T')[0] : null,
      };
    }).toList();

    await supabase.from('bookings').insert(inserts);

    setState(() {
      _selectedTimes.clear();
      repeatWeekly = false;
      repeatUntil = null;
    });
    await loadBookingsForDay(_selectedDay);
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = supabase.auth.currentUser?.id;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reserve the Car'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => supabase.auth.signOut(),
          )
        ],
      ),
      body: Column(
        children: [
          TableCalendar(
            headerStyle: const HeaderStyle(formatButtonVisible: false),
            firstDay: DateTime.utc(2026, 1, 1),
            lastDay: DateTime.utc(2030, 12, 31),
            focusedDay: _focusedDay,
            selectedDayPredicate: (d) => isSameDay(d, _selectedDay),
            onDaySelected: (d, f) async {
              setState(() {
                _selectedDay = d;
                _focusedDay = f;
              });
              await loadBookingsForDay(d);
            },
            calendarBuilders: CalendarBuilders(
              markerBuilder: (_, day, __) {
                final d = DateTime(day.year, day.month, day.day);
                if (bookingsPerDay[d]?.isNotEmpty == true) {
                  return const Positioned(
                    bottom: 1,
                    child: CircleAvatar(radius: 3, backgroundColor: Colors.red),
                  );
                }
                return const SizedBox();
              },
            ),
          ),

          SwitchListTile(
            title: const Text('Repeat weekly'),
            value: repeatWeekly,
            onChanged: (v) => setState(() => repeatWeekly = v),
          ),
          if (repeatWeekly)
            TextButton(
              onPressed: () async {
                final picked = await showDatePicker(
                  context: context,
                  firstDate: _selectedDay,
                  lastDate: DateTime(2030),
                  initialDate: repeatUntil ?? _selectedDay,
                );
                if (picked != null) setState(() => repeatUntil = picked);
              },
              style: const ButtonStyle(backgroundColor: WidgetStatePropertyAll(Colors.blue)),
              child: Text(
                repeatUntil == null
                    ? 'Select end date'
                    : 'Until: ${repeatUntil!.toString().split(' ')[0]}',
                style: const TextStyle(color: Colors.white),
              ),
            ),

          Expanded(
            child: ListWheelScrollView.useDelegate(
              itemExtent: 64,
              childDelegate: ListWheelChildBuilderDelegate(
                childCount: timeSlots.length,
                builder: (_, i) {
                  final time = timeSlots[i];
                  final booked = bookedTimes.firstWhere(
                    (b) => slotIsBooked(time, b),
                    orElse: () => {},
                  );

                  final isBooked = booked.isNotEmpty;
                  final isMine = isBooked && booked['user_id'] == currentUser;
                  final isSelected = _selectedTimes.contains(time);

                  Color color;
                  if (isSelected) {
                    color = Colors.green.shade700;
                  } else if (isBooked && isMine) {
                    color = Colors.green;
                  } else if (isBooked) {
                    color = Colors.red;
                  } else {
                    color = Colors.blue;
                  }

                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: isBooked
                              ? null
                              : () {
                                  setState(() {
                                    if (_selectedTimes.contains(time)) {
                                      _selectedTimes.remove(time);
                                    } else {
                                      _selectedTimes.add(time);
                                    }
                                  });
                                },
                            style: ElevatedButton.styleFrom(backgroundColor: color),
                            child: Text(
                              isBooked
                                ? isMine
                                  ? '$time (Reserved for You)'
                                  : '$time (Reserved for ${booked['user_name']})'
                                : time,
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                        ),
                        if (isMine)
                          IconButton(
                            icon: const Icon(Icons.cancel, color: Colors.red),
                            onPressed: () async {
                              final isRecurring = booked['recurring_group_id'] != null;

                              if (!isRecurring) {
                                await supabase
                                  .from('bookings')
                                  .delete()
                                  .eq('id', booked['id']);
                              } else {
                                  final choice = await showDialog<String>(
                                    context: context,
                                    builder: (_) => AlertDialog(
                                      title: const Text('Cancel Reservation'),
                                      content: const Text('Cancel one or all recurring?'),
                                      actionsPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                      actions: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: TextButton(
                                                style: const ButtonStyle(
                                                  backgroundColor: WidgetStatePropertyAll(Colors.blue),
                                                ),
                                                onPressed: () => Navigator.pop(context, 'one'),
                                                child: const Text('One', style: TextStyle(color: Colors.white)),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: TextButton(
                                                style: const ButtonStyle(
                                                  backgroundColor: WidgetStatePropertyAll(Colors.blue),
                                                ),
                                                onPressed: () => Navigator.pop(context, 'all'),
                                                child: const Text('All', style: TextStyle(color: Colors.white)),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: TextButton(
                                                style: const ButtonStyle(
                                                  backgroundColor: WidgetStatePropertyAll(Colors.blue),
                                                ),
                                                onPressed: () => Navigator.pop(context, null),
                                                child: const Text('Cancel', style: TextStyle(color: Colors.white)),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  );

                                if (choice == 'one') {
                                  await supabase
                                    .from('bookings')
                                    .delete()
                                    .eq('id', booked['id']);
                                }

                                if (choice == 'all') {
                                  await supabase
                                    .from('bookings')
                                    .delete()
                                    .eq('recurring_group_id', booked['recurring_group_id']);
                                }
                              }
                              await loadBookingsForDay(_selectedDay);
                            },
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(16),
            child: ElevatedButton(
              onPressed: _selectedTimes.isEmpty ? null : bookCar,
              child: const Text('Confirm Reservation'),
            ),
          ),

          Padding( 
            padding: const EdgeInsets.all(20)
          )
        ],
      ),
    );
  }
}
