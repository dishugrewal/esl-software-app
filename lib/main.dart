import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

const String API_BASE = "https://esl.rankorax.digital/includes/api.php";
const String SERVICE_UUID = "0000fff0-0000-1000-8000-00805f9b34fb";
const String CHAR_UUID = "0000fff5-0000-1000-8000-00805f9b34fb";
const int PACKET_SIZE = 200;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Color(0xFF0F172A),
    statusBarIconBrightness: Brightness.light,
  ));
  runApp(const EslNativeApp());
}

class EslNativeApp extends StatelessWidget {
  const EslNativeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ESL Software',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2563EB),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF1F5F9),
      ),
      home: const AuthGateScreen(),
    );
  }
}

// =========================================================================
// 1. NATIVE LOGIN & LICENSE CHECK SCREEN
// =========================================================================
class AuthGateScreen extends StatefulWidget {
  const AuthGateScreen({super.key});

  @override
  State<AuthGateScreen> createState() => _AuthGateScreenState();
}

class _AuthGateScreenState extends State<AuthGateScreen> {
  final TextEditingController _userCtrl = TextEditingController();
  final TextEditingController _passCtrl = TextEditingController();
  bool _loading = true;
  String _errorMsg = "";

  @override
  void initState() {
    super.initState();
    _checkSavedSession();
  }

  Future<void> _checkSavedSession() async {
    final prefs = await SharedPreferences.getInstance();
    final savedU = prefs.getString('esl_u') ?? '';
    final savedP = prefs.getString('esl_p') ?? '';
    if (savedU.isNotEmpty && savedP.isNotEmpty) {
      _userCtrl.text = savedU;
      _passCtrl.text = savedP;
      await _performLogin(savedU, savedP, silent: true);
    } else {
      setState(() => _loading = false);
    }
  }

  Future<void> _performLogin(String u, String p, {bool silent = false}) async {
    setState(() {
      _loading = true;
      _errorMsg = "";
    });

    try {
      final res = await http.post(
        Uri.parse("$API_BASE?action=login&_t=${DateTime.now().millisecondsSinceEpoch}"),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'username': u.trim(), 'password': p.trim()}),
      );
      final data = jsonDecode(res.body);
      if (res.statusCode != 200 || data['success'] != true) {
        throw Exception(data['error'] ?? 'Invalid credentials or License Expired');
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('esl_u', u.trim());
      await prefs.setString('esl_p', p.trim());

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => MainDashboardScreen(
            username: u.trim(),
            password: p.trim(),
            userInfo: Map<String, dynamic>.from(data['user'] ?? {}),
          ),
        ),
      );
    } catch (e) {
      if (silent) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.clear();
      }
      setState(() {
        _loading = false;
        _errorMsg = e.toString().replaceAll('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(28),
                boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 24)],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
                    decoration: const BoxDecoration(
                      color: Color(0xFF1E293B),
                      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                    ),
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF2563EB),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.bolt, color: Colors.amber, size: 22),
                              SizedBox(width: 6),
                              Text(
                                "ESL Software",
                                style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          "7.5\" Digital Nameplate Native App",
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          "Made by Dishu Grewal",
                          style: TextStyle(color: Color(0xFF60A5FA), fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: _loading
                        ? const Padding(
                            padding: EdgeInsets.symmetric(vertical: 30),
                            child: CircularProgressIndicator(),
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (_errorMsg.isNotEmpty)
                                Container(
                                  margin: const EdgeInsets.only(bottom: 16),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFEF2F2),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: const Color(0xFFFECACA)),
                                  ),
                                  child: Text(
                                    _errorMsg,
                                    style: const TextStyle(color: Color(0xFFB91C1C), fontSize: 12, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              TextField(
                                controller: _userCtrl,
                                decoration: InputDecoration(
                                  labelText: "User ID or Email",
                                  prefixIcon: const Icon(Icons.person),
                                  filled: true,
                                  fillColor: const Color(0xFFF8FAFC),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                                ),
                              ),
                              const SizedBox(height: 16),
                              TextField(
                                controller: _passCtrl,
                                obscureText: true,
                                decoration: InputDecoration(
                                  labelText: "Password",
                                  prefixIcon: const Icon(Icons.lock),
                                  filled: true,
                                  fillColor: const Color(0xFFF8FAFC),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                                ),
                              ),
                              const SizedBox(height: 22),
                              ElevatedButton.icon(
                                onPressed: () => _performLogin(_userCtrl.text, _passCtrl.text),
                                icon: const Icon(Icons.login, color: Colors.white),
                                label: const Text(
                                  "Sign In to Workspace",
                                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF2563EB),
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                ),
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

// =========================================================================
// 2. MAIN NATIVE DASHBOARD (PLATES, STUDIO TEMPLATES, MAC MANAGER)
// =========================================================================
class MainDashboardScreen extends StatefulWidget {
  final String username;
  final String password;
  final Map<String, dynamic> userInfo;

  const MainDashboardScreen({
    super.key,
    required this.username,
    required this.password,
    required this.userInfo,
  });

  @override
  State<MainDashboardScreen> createState() => _MainDashboardScreenState();
}

class _MainDashboardScreenState extends State<MainDashboardScreen> {
  int _currentTab = 0;
  bool _loadingDb = true;
  bool _isSyncing = false;
  String _statusBanner = "Loading workspace from MySQL...";
  int _syncProgress = 0;

  List> _plates = [];
  List> _templates = [];
  String _activeTemplateId = "t1";
  String _clearDefaultText = "PMI IT";

  final TextEditingController _rangeFromCtrl = TextEditingController(text: "1");
  final TextEditingController _rangeToCtrl = TextEditingController(text: "5");
  final TextEditingController _clearTextCtrl = TextEditingController(text: "PMI IT");

  // Add MAC Form Controllers
  final TextEditingController _macPlateNoCtrl = TextEditingController(text: "1");
  final TextEditingController _macAddrCtrl = TextEditingController();
  final TextEditingController _macNameCtrl = TextEditingController();
  final TextEditingController _macDesigCtrl = TextEditingController();
  final TextEditingController _macProjCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _initBlePermissions();
    _fetchWorkspaceFromServer();
  }

  Future<void> _initBlePermissions() async {
    if (Platform.isAndroid) {
      await [
        Permission.bluetooth,
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.locationWhenInUse,
      ].request();
      try {
        if (await FlutterBluePlus.isSupported) {
          final state = await FlutterBluePlus.adapterState.first;
          if (state != BluetoothAdapterState.on) {
            await FlutterBluePlus.turnOn();
          }
        }
      } catch (_) {}
    }
  }

  Future<void> _fetchWorkspaceFromServer() async {
    setState(() {
      _loadingDb = true;
      _statusBanner = "Syncing workspace with MySQL...";
    });

    try {
      final cid = widget.userInfo['clientId'] ?? 'ntpc';
      final uri = Uri.parse(
        "$API_BASE?action=load&client_id=${Uri.encodeComponent(cid.toString())}&u=${Uri.encodeComponent(widget.username)}&p=${Uri.encodeComponent(widget.password)}&_t=${DateTime.now().millisecondsSinceEpoch}",
      );
      final res = await http.get(uri);
      final data = jsonDecode(res.body);

      if (res.statusCode == 401 || res.statusCode == 403 || data['success'] != true) {
        throw Exception(data['error'] ?? "License or session expired");
      }

      final rawPlates = (data['plates'] as List?) ?? [];
      final rawTemplates = (data['templates'] as List?) ?? [];

      _plates = rawPlates.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      _templates = rawTemplates.isNotEmpty
          ? rawTemplates.map((e) => Map<String, dynamic>.from(e as Map)).toList()
          : _getDefaultTemplates();

      _activeTemplateId = (data['activeTemplateId'] ?? 't1').toString();
      _clearDefaultText = (data['clearDefaultText'] ?? 'PMI IT').toString();
      _clearTextCtrl.text = _clearDefaultText;

      _plates.sort((a, b) => (int.tryParse(a['plateNo'].toString()) ?? 0).compareTo(int.tryParse(b['plateNo'].toString()) ?? 0));
      final nextNo = _plates.isEmpty ? 1 : ((int.tryParse(_plates.last['plateNo'].toString()) ?? 0) + 1);
      _macPlateNoCtrl.text = nextNo.toString();

      setState(() {
        _loadingDb = false;
        _statusBanner = "Loaded ${_plates.length} plates for ${widget.userInfo['companyName'] ?? widget.username}";
      });
    } catch (e) {
      setState(() {
        _loadingDb = false;
        _statusBanner = "Error: ${e.toString().replaceAll('Exception: ', '')}";
      });
    }
  }

  List> _getDefaultTemplates() {
    return [
      {'id': 't1', 'name': '1. Classic Center Underline', 'bgColor': '#EAE8E3', 'textColor': '#000000', 'accentColor': '#D32F2F', 'nameSize': 68, 'desigSize': 34, 'projSize': 28, 'showDivider': true},
      {'id': 't2', 'name': '2. Pure White + Solid Black', 'bgColor': '#FFFFFF', 'textColor': '#000000', 'accentColor': '#000000', 'nameSize': 72, 'desigSize': 34, 'projSize': 28, 'showDivider': true},
      {'id': 't8', 'name': '8. Clean No-Lines (Name 100 / Desig 60)', 'bgColor': '#FFFFFF', 'textColor': '#000000', 'accentColor': '#D32F2F', 'nameSize': 100, 'desigSize': 60, 'projSize': 34, 'showDivider': false},
    ];
  }

  Map<String, dynamic> _getTemplateForPlate(Map<String, dynamic> plate) {
    final tid = (plate['templateId'] ?? _activeTemplateId).toString();
    for (final t in _templates) {
      if (t['id'].toString() == tid) return t;
    }
    return _templates.isNotEmpty ? _templates.first : _getDefaultTemplates().first;
  }

  Future<void> _saveWorkspaceToServer() async {
    try {
      final cid = widget.userInfo['clientId'] ?? 'ntpc';
      final res = await http.post(
        Uri.parse("$API_BASE?action=save&_t=${DateTime.now().millisecondsSinceEpoch}"),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': widget.username,
          'password': widget.password,
          'clientId': cid,
          'plates': _plates,
          'templates': _templates,
          'activeTemplateId': _activeTemplateId,
          'clearDefaultText': _clearTextCtrl.text.trim(),
        }),
      );
      final data = jsonDecode(res.body);
      if (data['success'] == true) {
        setState(() => _statusBanner = "Saved ${_plates.length} plates to MySQL ✓");
      } else {
        setState(() => _statusBanner = "Save Error: ${data['error']}");
      }
    } catch (e) {
      setState(() => _statusBanner = "Network Error: $e");
    }
  }

  // =========================================================================
  // 800x480 NATIVE CANVAS RENDERER & 192,000 BYTES BWRY PAYLOAD GENERATOR
  // =========================================================================
  Future<Uint8List> _generateDualDdsPayload(Map<String, dynamic> plate) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, 800, 480));
    final tpl = _getTemplateForPlate(plate);

    EinkPlatePainter(plate: plate, template: tpl).paint(canvas, const Size(800, 480));

    final picture = recorder.endRecording();
    final img = await picture.toImage(800, 480);
    final byteData = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
    final pixels = byteData!.buffer.asUint8List();

    final singleScreenBytes = Uint8List(96000);
    int byteIdx = 0, b = 0, j = 0;

    for (int p = 0; p < pixels.length; p += 4) {
      final int r = pixels[p];
      final int g = pixels[p + 1];
      final int bVal = pixels[p + 2];
      b = (b << 2) & 0xFF;

      final bool isRed = (r > 145 && g < 95 && bVal < 95);
      final bool isYellow = (r > 160 && g > 145 && bVal < 95);
      final double lum = 0.299 * r + 0.587 * g + 0.114 * bVal;

      if (isRed) {
        b = (b | 3) & 0xFF;
      } else if (isYellow) {
        b = (b | 2) & 0xFF;
      } else if (lum > 140) {
        b = (b | 1) & 0xFF;
      } else {
        b = (b | 0) & 0xFF;
      }

      j++;
      if (j == 4) {
        singleScreenBytes[byteIdx++] = b;
        j = 0;
        b = 0;
      }
    }

    final totalPayload = Uint8List(192000);
    totalPayload.setRange(0, 96000, singleScreenBytes);
    totalPayload.setRange(96000, 192000, singleScreenBytes);
    return totalPayload;
  }

  // =========================================================================
  // ZERO-POPUP DIRECT MAC BLE SYNC ENGINE
  // =========================================================================
  Future<bool> _syncSinglePlateBle(int index) async {
    final plate = _plates[index];
    final String mac = (plate['mac'] ?? '').toString().trim().toUpperCase();
    final int plateNo = int.tryParse(plate['plateNo'].toString()) ?? (index + 1);

    if (mac.length != 17) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Plate #$plateNo has no valid MAC address!")),
      );
      return false;
    }

    setState(() {
      _isSyncing = true;
      _syncProgress = 1;
      _plates[index]['status'] = 'Syncing...';
      _statusBanner = "Connecting to Plate #$plateNo ($mac)...";
    });

    final Uint8List payloadBytes = await _generateDualDdsPayload(plate);
    final int totalBytes = payloadBytes.length;
    final int totalPackets = (totalBytes + PACKET_SIZE - 1) ~/ PACKET_SIZE;

    BluetoothDevice? device;

    for (int attempt = 1; attempt <= 3; attempt++) {
      try {
        setState(() {
          _statusBanner = "Attempt $attempt/3: Locking MAC $mac (Plate #$plateNo)...";
        });

        if (Platform.isWindows) {
          // On Windows, perform a quick 2.5s scan if device isn't cached yet
          await FlutterBluePlus.startScan(timeout: const Duration(milliseconds: 2500));
          await Future.delayed(const Duration(milliseconds: 2600));
          await FlutterBluePlus.stopScan();
        }

        device = BluetoothDevice.fromId(mac);
        await device.connect(timeout: const Duration(seconds: 18), autoConnect: false, mtu: null);

        if (Platform.isAndroid) {
          try {
            await device.requestMtu(247);
          } catch (_) {}
        }

        final services = await device.discoverServices();
        BluetoothCharacteristic? targetChar;

        for (final srv in services) {
          if (srv.uuid.toString().toLowerCase().contains("fff0")) {
            for (final c in srv.characteristics) {
              if (c.uuid.toString().toLowerCase().contains("fff5")) {
                targetChar = c;
                break;
              }
            }
          }
        }

        if (targetChar == null) {
          throw Exception("Characteristic fff5 not found on $mac");
        }

        for (int pkt = 0; pkt < totalPackets; pkt++) {
          final int start = pkt * PACKET_SIZE;
          final int end = (start + PACKET_SIZE < totalBytes) ? (start + PACKET_SIZE) : totalBytes;
          await targetChar.write(payloadBytes.sublist(start, end), withoutResponse: true);

          if ((pkt + 1) % 45 == 0 || pkt == totalPackets - 1) {
            final int pct = (((pkt + 1) / totalPackets) * 100).round();
            setState(() {
              _syncProgress = pct;
              _statusBanner = "Syncing Plate #$plateNo ($mac): $pct%";
            });
          }
          await Future.delayed(const Duration(milliseconds: 8));
        }

        await Future.delayed(const Duration(milliseconds: 1200));
        await device.disconnect();

        setState(() {
          _isSyncing = false;
          _syncProgress = 100;
          _plates[index]['status'] = 'Synced ✓';
          _statusBanner = "Plate #$plateNo (${plate['name']}) Synced 100% ✓";
        });
        await _saveWorkspaceToServer();
        return true;
      } catch (e) {
        try {
          await device?.disconnect();
        } catch (_) {}
        await Future.delayed(const Duration(milliseconds: 800));
      }
    }

    setState(() {
      _isSyncing = false;
      _plates[index]['status'] = 'Failed';
      _statusBanner = "Failed to sync Plate #$plateNo ($mac)";
    });
    await _saveWorkspaceToServer();
    return false;
  }

  Future<void> _syncSelectedOrAllPlates({bool onlySelected = false}) async {
    if (_isSyncing || _plates.isEmpty) return;

    final List<int> indices = [];
    for (int i = 0; i < _plates.length; i++) {
      if (!onlySelected || _plates[i]['selected'] == true) {
        indices.add(i);
      }
    }

    if (indices.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please select at least 1 plate first!")),
      );
      return;
    }

    int ok = 0, fail = 0;
    for (final idx in indices) {
      final res = await _syncSinglePlateBle(idx);
      if (res) {
        ok++;
      } else {
        fail++;
      }
      await Future.delayed(const Duration(milliseconds: 500));
    }

    setState(() {
      _statusBanner = "Bulk Sync Complete! Synced: $ok | Failed: $fail";
    });
  }

  void _selectRange() {
    final int from = int.tryParse(_rangeFromCtrl.text) ?? 1;
    final int to = int.tryParse(_rangeToCtrl.text) ?? 5;
    final int minNo = from < to ? from : to;
    final int maxNo = from > to ? from : to;

    int count = 0;
    setState(() {
      for (final p in _plates) {
        final int pNo = int.tryParse(p['plateNo'].toString()) ?? 0;
        final bool match = pNo >= minNo && pNo <= maxNo;
        p['selected'] = match;
        if (match) count++;
      }
      _statusBanner = "Selected $count plate(s) from #$minNo to #$maxNo";
    });
  }

  void _clearSelectedToDefaultText() {
    final String txt = _clearTextCtrl.text.trim();
    if (txt.isEmpty) return;
    final bool anySel = _plates.any((p) => p['selected'] == true);

    setState(() {
      for (final p in _plates) {
        if (!anySel || p['selected'] == true) {
          p['name'] = txt;
          p['designation'] = '';
          p['project'] = '';
          p['status'] = 'Ready';
        }
      }
      _statusBanner = "Set plates to \"$txt\"";
    });
    _saveWorkspaceToServer();
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const AuthGateScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final int selectedCount = _plates.where((p) => p['selected'] == true).length;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFF2563EB),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.bolt, color: Colors.amber, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("ESL Software", style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
                  Text(
                    "${widget.userInfo['companyName'] ?? widget.username} • Made by Dishu Grewal",
                    style: const TextStyle(fontSize: 11, color: Color(0xFF60A5FA), fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: _fetchWorkspaceFromServer,
            icon: const Icon(Icons.refresh),
            tooltip: "Refresh from MySQL",
          ),
          IconButton(
            onPressed: _logout,
            icon: const Icon(Icons.power_settings_new, color: Colors.redAccent),
            tooltip: "Logout",
          ),
        ],
      ),
      body: Column(
        children: [
          // Live Status & Progress Bar Banner
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: _isSyncing ? const Color(0xFF1E3A8A) : const Color(0xFFEFF6FF),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      _isSyncing ? Icons.bluetooth_searching : Icons.check_circle,
                      size: 16,
                      color: _isSyncing ? Colors.amber : const Color(0xFF2563EB),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _statusBanner,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: _isSyncing ? Colors.white : const Color(0xFF1E293B),
                        ),
                      ),
                    ),
                    if (_isSyncing)
                      Text(
                        "$_syncProgress%",
                        style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.w900, fontSize: 13),
                      ),
                  ],
                ),
                if (_isSyncing) ...[
                  const SizedBox(height: 6),
                  LinearProgressIndicator(
                    value: _syncProgress / 100.0,
                    backgroundColor: Colors.white24,
                    valueColor: const AlwaysStoppedAnimation<Color>(Colors.amber),
                  ),
                ],
              ],
            ),
          ),

          Expanded(
            child: _loadingDb
                ? const Center(child: CircularProgressIndicator())
                : IndexedStack(
                    index: _currentTab,
                    children: [
                      _buildPlatesTab(selectedCount),
                      _buildTemplatesTab(),
                      _buildMacManagerTab(),
                    ],
                  ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentTab,
        onDestinationSelected: (idx) => setState(() => _currentTab = idx),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.grid_view_rounded),
            label: "Plates (${_plates.length})",
          ),
          NavigationDestination(
            icon: const Icon(Icons.palette_outlined),
            label: "Templates (${_templates.length})",
          ),
          const NavigationDestination(
            icon: Icon(Icons.bluetooth),
            label: "Add / MACs",
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // TAB 1: NATIVE PLATES EDITOR, RANGE SELECTOR & SYNC
  // =========================================================================
  Widget _buildPlatesTab(int selectedCount) {
    return Column(
      children: [
        // Top Action & Range Control Bar
        Container(
          padding: const EdgeInsets.all(12),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _isSyncing ? null : () => _syncSelectedOrAllPlates(onlySelected: true),
                      icon: const Icon(Icons.done_all, size: 16, color: Colors.white),
                      label: Text(
                        "Sync Selected ($selectedCount)",
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.white),
                      ),
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF059669)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _isSyncing ? null : () => _syncSelectedOrAllPlates(onlySelected: false),
                      icon: const Icon(Icons.bluetooth_connected, size: 16, color: Colors.white),
                      label: Text(
                        "Auto-Sync All (${_plates.length})",
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.white),
                      ),
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2563EB)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    Checkbox(
                      value: _plates.isNotEmpty && selectedCount == _plates.length,
                      onChanged: (v) {
                        setState(() {
                          for (final p in _plates) {
                            p['selected'] = v ?? false;
                          }
                        });
                      },
                    ),
                    const Text("All", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    const SizedBox(width: 10),
                    const Text("From #", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    const SizedBox(width: 4),
                    SizedBox(
                      width: 44,
                      height: 32,
                      child: TextField(
                        controller: _rangeFromCtrl,
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                        decoration: const InputDecoration(
                          contentPadding: EdgeInsets.zero,
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4),
                      child: Text("to", style: TextStyle(fontSize: 12)),
                    ),
                    SizedBox(
                      width: 44,
                      height: 32,
                      child: TextField(
                        controller: _rangeToCtrl,
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                        decoration: const InputDecoration(
                          contentPadding: EdgeInsets.zero,
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    OutlinedButton(
                      onPressed: _selectRange,
                      child: const Text("Select Range", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 90,
                      height: 32,
                      child: TextField(
                        controller: _clearTextCtrl,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                        decoration: const InputDecoration(
                          contentPadding: EdgeInsets.symmetric(horizontal: 8),
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    ElevatedButton(
                      onPressed: _clearSelectedToDefaultText,
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                      child: const Text("Clear Text", style: TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        Expanded(
          child: _plates.isEmpty
              ? const Center(child: Text("No plates registered. Add plates in Tab 3."))
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _plates.length,
                  itemBuilder: (context, idx) {
                    final p = _plates[idx];
                    final tpl = _getTemplateForPlate(p);
                    final String curTplId = tpl['id'].toString();

                    return Card(
                      key: ValueKey("plate_${p['plateNo']}"),
                      margin: const EdgeInsets.only(bottom: 14),
                      elevation: 1,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                        side: BorderSide(
                          color: p['selected'] == true ? const Color(0xFF2563EB) : const Color(0xFFCBD5E1),
                          width: p['selected'] == true ? 2 : 1,
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Card Header
                            Row(
                              children: [
                                Checkbox(
                                  value: p['selected'] == true,
                                  onChanged: (v) => setState(() => p['selected'] = v ?? false),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF0F172A),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    "Plate #${p['plateNo']}",
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    "MAC: ${p['mac'] ?? 'Unassigned'}",
                                    style: const TextStyle(fontFamily: 'monospace', fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF2563EB)),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: p['status'].toString().contains('Synced') ? const Color(0xFFD1FAE5) : const Color(0xFFF1F5F9),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    (p['status'] ?? 'Ready').toString(),
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: p['status'].toString().contains('Synced') ? const Color(0xFF065F46) : Colors.black87,
                                    ),
                                  ),
                                ),
                              ],
                            ),

                            // Per-Plate Template Dropdown
                            Container(
                              margin: const EdgeInsets.symmetric(vertical: 8),
                              padding: const EdgeInsets.symmetric(horizontal: 10),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: const Color(0xFFE2E8F0)),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  value: _templates.any((t) => t['id'].toString() == curTplId) ? curTplId : _templates.first['id'].toString(),
                                  isExpanded: true,
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87),
                                  items: _templates.map((t) {
                                    return DropdownMenuItem<String>(
                                      value: t['id'].toString(),
                                      child: Text("Template: ${t['name']}"),
                                    );
                                  }).toList(),
                                  onChanged: (newId) {
                                    if (newId == null) return;
                                    setState(() {
                                      p['templateId'] = newId;
                                      p['status'] = 'Ready';
                                    });
                                    _saveWorkspaceToServer();
                                  },
                                ),
                              ),
                            ),

                            // Live 800x480 Hardware Preview
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: const Color(0xFFCBD5E1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: AspectRatio(
                                aspectRatio: 800 / 480,
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: CustomPaint(
                                    painter: EinkPlatePainter(plate: p, template: tpl),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),

                            // Name, Designation, Project Fields
                            TextFormField(
                              initialValue: (p['name'] ?? '').toString(),
                              decoration: const InputDecoration(
                                labelText: "Full Name",
                                isDense: true,
                                border: OutlineInputBorder(),
                              ),
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                              onChanged: (val) {
                                setState(() {
                                  p['name'] = val;
                                  p['status'] = 'Ready';
                                });
                              },
                              onEditingComplete: _saveWorkspaceToServer,
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    initialValue: (p['designation'] ?? '').toString(),
                                    decoration: const InputDecoration(
                                      labelText: "Designation",
                                      isDense: true,
                                      border: OutlineInputBorder(),
                                    ),
                                    style: const TextStyle(fontSize: 12),
                                    onChanged: (val) => setState(() => p['designation'] = val),
                                    onEditingComplete: _saveWorkspaceToServer,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: TextFormField(
                                    initialValue: (p['project'] ?? '').toString(),
                                    decoration: const InputDecoration(
                                      labelText: "Project / Location",
                                      isDense: true,
                                      border: OutlineInputBorder(),
                                    ),
                                    style: const TextStyle(fontSize: 12),
                                    onChanged: (val) => setState(() => p['project'] = val),
                                    onEditingComplete: _saveWorkspaceToServer,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),

                            // Save & Direct BLE Sync Buttons
                            Row(
                              children: [
                                OutlinedButton.icon(
                                  onPressed: _saveWorkspaceToServer,
                                  icon: const Icon(Icons.cloud_upload_outlined, size: 16),
                                  label: const Text("Save DB", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: _isSyncing ? null : () => _syncSinglePlateBle(idx),
                                    icon: const Icon(Icons.bluetooth, size: 16, color: Colors.white),
                                    label: Text(
                                      "Sync Plate #${p['plateNo']} via BLE",
                                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.white),
                                    ),
                                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2563EB)),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // =========================================================================
  // TAB 2: STUDIO TEMPLATES SELECTOR & FONT CUSTOMIZER
  // =========================================================================
  Widget _buildTemplatesTab() {
    final activeTpl = _templates.firstWhere(
      (t) => t['id'].toString() == _activeTemplateId,
      orElse: () => _templates.first,
    );

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          "Select Default Template or Apply to All Plates",
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 10),
        ..._templates.map((t) {
          final bool isSel = t['id'].toString() == _activeTemplateId;
          return Card(
            color: isSel ? const Color(0xFFEFF6FF) : Colors.white,
            child: ListTile(
              title: Text(t['name'].toString(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              trailing: isSel
                  ? const Icon(Icons.check_circle, color: Color(0xFF2563EB))
                  : TextButton(
                      onPressed: () {
                        setState(() => _activeTemplateId = t['id'].toString());
                        _saveWorkspaceToServer();
                      },
                      child: const Text("Select"),
                    ),
              onTap: () {
                setState(() => _activeTemplateId = t['id'].toString());
              },
            ),
          );
        }),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          onPressed: () {
            setState(() {
              for (final p in _plates) {
                p['templateId'] = _activeTemplateId;
              }
              _statusBanner = "Applied ${activeTpl['name']} to ALL ${_plates.length} plates!";
            });
            _saveWorkspaceToServer();
          },
          icon: const Icon(Icons.format_paint, color: Colors.white),
          label: const Text("Apply Selected Template to ALL Plates", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF2563EB),
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
      ],
    );
  }

  // =========================================================================
  // TAB 3: MAC ADDRESS MANAGER
  // =========================================================================
  Widget _buildMacManagerTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text("Register New Plate & MAC Address", style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      flex: 1,
                      child: TextField(
                        controller: _macPlateNoCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: "Plate #", border: OutlineInputBorder(), isDense: true),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: _macAddrCtrl,
                        decoration: const InputDecoration(
                          labelText: "MAC (E4:52:1E:E5:66:4F)",
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _macNameCtrl,
                  decoration: const InputDecoration(labelText: "Person Name", border: OutlineInputBorder(), isDense: true),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _macDesigCtrl,
                        decoration: const InputDecoration(labelText: "Designation", border: OutlineInputBorder(), isDense: true),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _macProjCtrl,
                        decoration: const InputDecoration(labelText: "Project / Location", border: OutlineInputBorder(), isDense: true),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: () {
                    final int pNo = int.tryParse(_macPlateNoCtrl.text.trim()) ?? (_plates.length + 1);
                    final String mac = _macAddrCtrl.text.trim().toUpperCase();
                    if (mac.length != 17) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("Enter valid 17-character MAC (XX:XX:XX:XX:XX:XX)")),
                      );
                      return;
                    }
                    setState(() {
                      _plates.removeWhere((x) => int.tryParse(x['plateNo'].toString()) == pNo);
                      _plates.add({
                        'plateNo': pNo,
                        'name': _macNameCtrl.text.trim().isEmpty ? 'Plate #$pNo' : _macNameCtrl.text.trim(),
                        'designation': _macDesigCtrl.text.trim(),
                        'project': _macProjCtrl.text.trim(),
                        'mac': mac,
                        'templateId': _activeTemplateId,
                        'status': 'Ready',
                        'selected': false,
                      });
                      _plates.sort((a, b) => (int.tryParse(a['plateNo'].toString()) ?? 0).compareTo(int.tryParse(b['plateNo'].toString()) ?? 0));
                      _macPlateNoCtrl.text = (pNo + 1).toString();
                      _macAddrCtrl.clear();
                      _macNameCtrl.clear();
                      _macDesigCtrl.clear();
                      _macProjCtrl.clear();
                    });
                    _saveWorkspaceToServer();
                  },
                  icon: const Icon(Icons.add, color: Colors.white),
                  label: const Text("Save Plate & MAC to MySQL", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2563EB)),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Text("Registered MAC Directory", style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        ..._plates.asMap().entries.map((entry) {
          final int idx = entry.key;
          final Map<String, dynamic> p = entry.value;
          return Card(
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: const Color(0xFF0F172A),
                child: Text("#${p['plateNo']}", style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
              ),
              title: Text(p['name'].toString(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              subtitle: Text("MAC: ${p['mac']}", style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: Color(0xFF2563EB))),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                onPressed: () {
                  setState(() => _plates.removeAt(idx));
                  _saveWorkspaceToServer();
                },
              ),
            ),
          );
        }),
      ],
    );
  }
}

// =========================================================================
// 3. NATIVE 800x480 E-INK HARDWARE PAINTER
// =========================================================================
class EinkPlatePainter extends CustomPainter {
  final Map<String, dynamic> plate;
  final Map<String, dynamic> template;

  EinkPlatePainter({required this.plate, required this.template});

  Color _parseHex(String hex, Color fallback) {
    final clean = hex.replaceAll('#', '').trim();
    if (clean.length == 6) {
      return Color(int.parse("FF$clean", radix: 16));
    }
    return fallback;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final double scaleX = size.width / 800.0;
    final double scaleY = size.height / 480.0;
    canvas.save();
    canvas.scale(scaleX, scaleY);

    final Color bgColor = _parseHex((template['bgColor'] ?? '#EAE8E3').toString(), const Color(0xFFEAE8E3));
    final Color txtColor = _parseHex((template['textColor'] ?? '#000000').toString(), Colors.black);
    final Color accColor = _parseHex((template['accentColor'] ?? '#D32F2F').toString(), const Color(0xFFD32F2F));
    final String style = (template['style'] ?? 'underline').toString();

    canvas.drawRect(const Rect.fromLTWH(0, 0, 800, 480), Paint()..color = bgColor);

    if (style == 'border') {
      canvas.drawRect(
        const Rect.fromLTWH(20, 20, 760, 440),
        Paint()
          ..color = accColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6,
      );
    } else if (style == 'top-banner') {
      canvas.drawRect(const Rect.fromLTWH(0, 0, 800, 56), Paint()..color = accColor);
    } else if (style == 'exec-banner') {
      canvas.drawRect(const Rect.fromLTWH(0, 0, 800, 28), Paint()..color = accColor);
      canvas.drawRect(const Rect.fromLTWH(0, 452, 800, 28), Paint()..color = accColor);
    }

    String name = (plate['name'] ?? '').toString().trim();
    String desig = (plate['designation'] ?? '').toString().trim();
    String proj = (plate['project'] ?? '').toString().trim();

    if (template['uppercase'] == true) {
      name = name.toUpperCase();
      desig = desig.toUpperCase();
      proj = proj.toUpperCase();
    }

    if (name.isEmpty) {
      canvas.restore();
      return;
    }

    double nameFontSize = double.tryParse((template['nameSize'] ?? 68).toString()) ?? 68;
    final double desigFontSize = double.tryParse((template['desigSize'] ?? 34).toString()) ?? 34;
    final bool showDivider = template['showDivider'] != false && style != 'none';
    final bool hasSub = desig.isNotEmpty || proj.isNotEmpty;

    TextPainter nameTp;
    while (true) {
      nameTp = TextPainter(
        text: TextSpan(
          text: name,
          style: TextStyle(color: txtColor, fontSize: nameFontSize, fontWeight: FontWeight.w900),
        ),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 740);

      if (nameTp.height <= 190 || nameFontSize <= 28) break;
      nameFontSize -= 4;
    }

    final double nameY = hasSub ? (190 - nameTp.height / 2) : (240 - nameTp.height / 2);
    nameTp.paint(canvas, Offset(400 - nameTp.width / 2, nameY));

    if (hasSub) {
      double nextY = nameY + nameTp.height + 20;
      if (showDivider) {
        final double lineW = (nameTp.width + 40).clamp(160.0, 680.0);
        canvas.drawRect(Rect.fromLTWH(400 - lineW / 2, nextY, lineW, 4), Paint()..color = accColor);
        nextY += 22;
      }

      final String combinedSub = [desig, proj].where((s) => s.isNotEmpty).join("  |  ");
      final TextPainter subTp = TextPainter(
        text: TextSpan(
          text: combinedSub,
          style: TextStyle(color: txtColor, fontSize: desigFontSize, fontWeight: FontWeight.bold),
        ),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 740);

      subTp.paint(canvas, Offset(400 - subTp.width / 2, nextY));
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant EinkPlatePainter oldDelegate) => true;
}
