import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:universal_ble/universal_ble.dart';
import 'package:permission_handler/permission_handler.dart';

// =========================================================================
// LIVE PORTAL URL (CONNECTED TO ESL.RANKORAX.DIGITAL)
// =========================================================================
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
      title: 'ESL Software — Made by Dishu Grewal',
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
  InAppWebViewController? _webViewController;
  bool _isLoading = true;
  bool _isSyncingBle = false;
  int _syncProgressPct = 0;
  String _syncOverlayStatus = "";

  @override
  void initState() {
    super.initState();
    _initBlePermissions();
  }

  Future<void> _initBlePermissions() async {
    if (Platform.isAndroid) {
      await [
        Permission.bluetooth,
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.locationWhenInUse,
      ].request();
    }
  }

  // =========================================================================
  // UNIVERSAL DIRECT-MAC BLE SYNC (WORKS ON ANDROID APK & WINDOWS EXE!)
  // =========================================================================
  Future> _syncPayloadToMac({
    required String macAddress,
    required int plateNo,
    required String payloadBase64,
  }) async {
    final cleanMac = macAddress.trim().toUpperCase();
    final Uint8List payloadBytes = base64Decode(payloadBase64);
    final int totalBytes = payloadBytes.length;
    final int totalPackets = (totalBytes + PACKET_SIZE - 1) ~/ PACKET_SIZE;

    setState(() {
      _isSyncingBle = true;
      _syncProgressPct = 1;
      _syncOverlayStatus = "Connecting to Plate #$plateNo ($cleanMac)...";
    });

    Exception? lastErr;

    for (int attempt = 1; attempt <= 3; attempt++) {
      try {
        setState(() {
          _syncOverlayStatus = "Attempt $attempt/3: Connecting to $cleanMac...";
        });

        await UniversalBle.connect(cleanMac);
        await Future.delayed(const Duration(milliseconds: 400));

        if (Platform.isAndroid) {
          try {
            await UniversalBle.requestMtu(cleanMac, 247);
          } catch (_) {}
        }

        await UniversalBle.discoverServices(cleanMac);

        for (int pkt = 0; pkt < totalPackets; pkt++) {
          final int start = pkt * PACKET_SIZE;
          final int end = (start + PACKET_SIZE < totalBytes) ? (start + PACKET_SIZE) : totalBytes;
          final Uint8List chunk = payloadBytes.sublist(start, end);

          await UniversalBle.writeValue(
            cleanMac,
            SERVICE_UUID,
            CHAR_UUID,
            chunk,
            BleOutputProperty.withoutResponse,
          );

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
        await UniversalBle.disconnect(cleanMac);

        setState(() {
          _isSyncingBle = false;
          _syncProgressPct = 100;
        });

        return {"success": true, "mac": cleanMac, "plateNo": plateNo};
      } catch (e) {
        lastErr = Exception(e.toString());
        try {
          await UniversalBle.disconnect(cleanMac);
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
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            InAppWebView(
              initialUrlRequest: URLRequest(url: WebUri(PORTAL_URL)),
              initialSettings: InAppWebViewSettings(
                javaScriptEnabled: true,
                domStorageEnabled: true,
                databaseEnabled: true,
                allowFileAccess: true,
                allowContentAccess: true,
                mediaPlaybackRequiresUserGesture: false,
                mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
                userAgent: "ESLSoftwareNativeApp/1.0 (Made by Dishu Grewal)",
              ),
              onWebViewCreated: (controller) {
                _webViewController = controller;
                controller.addJavaScriptHandler(
                  handlerName: 'nativeMacSync',
                  callback: (args) async {
                    if (args.isEmpty || args[0] is! Map) {
                      return {"success": false, "error": "Invalid sync payload"};
                    }
                    final Map data = args[0] as Map;
                    return await _syncPayloadToMac(
                      macAddress: (data['mac'] ?? '').toString(),
                      plateNo: int.tryParse((data['plateNo'] ?? '1').toString()) ?? 1,
                      payloadBase64: (data['payloadBase64'] ?? '').toString(),
                    );
                  },
                );
              },
              onLoadStart: (controller, url) => setState(() => _isLoading = true),
              onLoadStop: (controller, url) async {
                setState(() => _isLoading = false);
                await controller.evaluateJavascript(
                  source: "window.ESLNativeApp = true; if(typeof checkLocalSilentBridge === 'function') checkLocalSilentBridge(false);",
                );
              },
            ),

            if (_isLoading)
              Container(
                color: const Color(0xFF0F172A),
                child: const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: Color(0xFF3B82F6)),
                      SizedBox(height: 16),
                      Text("ESL Software", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
                      SizedBox(height: 4),
                      Text("Made by Dishu Grewal", style: TextStyle(color: Color(0xFF60A5FA), fontSize: 12, fontWeight: FontWeight.bold)),
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
    );
  }
}
