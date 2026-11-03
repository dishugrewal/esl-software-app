import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

const String PORTAL_URL   = "https://esl.rankorax.digital/index.php";
const String SERVICE_UUID = "0000fff0-0000-1000-8000-00805f9b34fb";
const String CHAR_UUID    = "0000fff5-0000-1000-8000-00805f9b34fb";
const int PACKET_SIZE     = 200;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Color(0xFF0F172A),
    statusBarIconBrightness: Brightness.light,
  ));
  runApp(const EslSoftwareApp());
}

class EslSoftwareApp extends StatelessWidget {
  const EslSoftwareApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ESL Software',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2563EB)),
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        useMaterial3: true,
      ),
      home: const EslPortalScreen(),
    );
  }
}

class EslPortalScreen extends StatefulWidget {
  const EslPortalScreen({super.key});

  @override
  State<EslPortalScreen> createState() => _EslPortalScreenState();
}

class _EslPortalScreenState extends State<EslPortalScreen> {
  late final WebViewController _controller;
  bool _isLoading = true;
  bool _isSyncingBle = false;
  int _syncProgressPct = 0;
  String _syncOverlayStatus = "";

  @override
  void initState() {
    super.initState();
    _initPermissions();
    _initWebView();
  }

  Future<void> _initPermissions() async {
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

  void _initWebView() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF0F172A))
      ..addJavaScriptChannel(
        'ESLAndroidChannel',
        onMessageReceived: (JavaScriptMessage message) async {
          try {
            final Map<String, dynamic> data = jsonDecode(message.message);
            final String reqId = (data['reqId'] ?? '').toString();
            final String mac = (data['mac'] ?? '').toString();
            final int plateNo = int.tryParse((data['plateNo'] ?? '1').toString()) ?? 1;
            final String payloadBase64 = (data['payloadBase64'] ?? '').toString();

            final Map<String, dynamic> res = await _syncPayloadToMac(
              macAddress: mac,
              plateNo: plateNo,
              payloadBase64: payloadBase64,
            );

            final String resJson = jsonEncode(res);
            await _controller.runJavaScript(
              "if(window.__eslResolve && window.__eslResolve['$reqId']) { window.__eslResolve['$reqId']($resJson); delete window.__eslResolve['$reqId']; }",
            );
          } catch (e) {
            final String errStr = jsonEncode({"success": false, "error": e.toString()});
            await _controller.runJavaScript(
              "if(window.__eslResolve) { Object.values(window.__eslResolve).forEach(fn => fn($errStr)); window.__eslResolve = {}; }",
            );
          }
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) => setState(() => _isLoading = true),
          onPageFinished: (_) async {
            setState(() => _isLoading = false);
            // Inject Native Bridge Polyfill so existing assets/app.js works seamlessly!
            await _controller.runJavaScript('''
              window.ESLNativeApp = true;
              window.__eslResolve = window.__eslResolve || {};
              window.flutter_inappwebview = {
                callHandler: function(handlerName, payloadObj) {
                  return new Promise(function(resolve) {
                    var reqId = 'req_' + Date.now() + '_' + Math.random().toString(36).substring(2);
                    window.__eslResolve[reqId] = resolve;
                    ESLAndroidChannel.postMessage(JSON.stringify({
                      reqId: reqId,
                      mac: payloadObj.mac,
                      plateNo: payloadObj.plateNo,
                      payloadBase64: payloadObj.payloadBase64
                    }));
                  });
                }
              };
              if (typeof checkLocalSilentBridge === 'function') {
                checkLocalSilentBridge(false);
              }
            ''');
          },
        ),
      )
      ..loadRequest(Uri.parse(PORTAL_URL));
  }

  Future> _syncPayloadToMac({
    required String macAddress,
    required int plateNo,
    required String payloadBase64,
  }) async {
    final String cleanMac = macAddress.trim().toUpperCase();
    final Uint8List payloadBytes = base64Decode(payloadBase64);
    final int totalBytes = payloadBytes.length;
    final int totalPackets = (totalBytes + PACKET_SIZE - 1) ~/ PACKET_SIZE;

    setState(() {
      _isSyncingBle = true;
      _syncProgressPct = 1;
      _syncOverlayStatus = "Connecting to Plate #$plateNo ($cleanMac)...";
    });

    BluetoothDevice? device;
    Exception? lastErr;

    for (int attempt = 1; attempt <= 3; attempt++) {
      try {
        setState(() {
          _syncOverlayStatus = "Attempt $attempt/3: Locking MAC $cleanMac...";
        });

        device = BluetoothDevice.fromId(cleanMac);

        await device.connect(
          timeout: const Duration(seconds: 18),
          autoConnect: false,
          mtu: null,
        );

        if (Platform.isAndroid) {
          try {
            await device.requestMtu(247);
          } catch (_) {}
        }

        final List<BluetoothService> services = await device.discoverServices();
        BluetoothCharacteristic? targetChar;

        for (final BluetoothService srv in services) {
          if (srv.uuid.toString().toLowerCase().contains("fff0")) {
            for (final BluetoothCharacteristic c in srv.characteristics) {
              if (c.uuid.toString().toLowerCase().contains("fff5")) {
                targetChar = c;
                break;
              }
            }
          }
        }

        if (targetChar == null) {
          throw Exception("Characteristic fff5 not found on $cleanMac");
        }

        for (int pkt = 0; pkt < totalPackets; pkt++) {
          final int start = pkt * PACKET_SIZE;
          final int end = (start + PACKET_SIZE < totalBytes) ? (start + PACKET_SIZE) : totalBytes;
          final List<int> chunk = payloadBytes.sublist(start, end);

          await targetChar.write(chunk, withoutResponse: true);

          if ((pkt + 1) % 40 == 0 || pkt == totalPackets - 1) {
            final int pct = (((pkt + 1) / totalPackets) * 100).round();
            setState(() {
              _syncProgressPct = pct;
              _syncOverlayStatus = "Syncing Plate #$plateNo ($cleanMac): $pct%";
            });
          }

          await Future.delayed(const Duration(milliseconds: 8));
        }

        await Future.delayed(const Duration(milliseconds: 1200));
        await device.disconnect();

        setState(() {
          _isSyncingBle = false;
          _syncProgressPct = 100;
        });

        return {"success": true, "mac": cleanMac, "plateNo": plateNo};
      } catch (e) {
        lastErr = Exception(e.toString());
        try {
          await device?.disconnect();
        } catch (_) {}
        await Future.delayed(const Duration(milliseconds: 800));
      }
    }

    setState(() {
      _isSyncingBle = false;
    });

    return {
      "success": false,
      "error": lastErr?.toString() ?? "Failed to connect to MAC $cleanMac"
    };
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (bool didPop) async {
        if (didPop) return;
        if (await _controller.canGoBack()) {
          await _controller.goBack();
        }
      },
      child: Scaffold(
        body: SafeArea(
          child: Stack(
            children: [
              WebViewWidget(controller: _controller),

              if (_isLoading)
                Container(
                  color: const Color(0xFF0F172A),
                  child: const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(color: Color(0xFF3B82F6)),
                        SizedBox(height: 16),
                        Text(
                          "ESL Software",
                          style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900),
                        ),
                        SizedBox(height: 4),
                        Text(
                          "Made by Dishu Grewal",
                          style: TextStyle(color: Color(0xFF60A5FA), fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),

              if (_isSyncingBle)
                Positioned(
                  top: 12,
                  left: 16,
                  right: 16,
                  child: Material(
                    elevation: 10,
                    borderRadius: BorderRadius.circular(16),
                    color: const Color(0xFF0F172A),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFF3B82F6), width: 1.5),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  _syncOverlayStatus,
                                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Text(
                                "$_syncProgressPct%",
                                style: const TextStyle(color: Color(0xFF34D399), fontSize: 13, fontWeight: FontWeight.w900),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: LinearProgressIndicator(
                              value: _syncProgressPct / 100.0,
                              minHeight: 6,
                              backgroundColor: const Color(0xFF1E293B),
                              valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF3B82F6)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
