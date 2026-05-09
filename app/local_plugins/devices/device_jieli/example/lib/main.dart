import 'dart:async';

import 'package:flutter/material.dart';
import 'package:device_jieli/device_jieli.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final _plugin = Jielihome.instance;
  final _devices = <String, JieliDevice>{};
  StreamSubscription<JieliEvent>? _sub;

  bool _initialized = false;
  bool _scanning = false;
  String? _connectedAddress;
  String _status = 'idle';
  final _logs = <String>[];

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();

    await _plugin.initialize(enableLog: true);
    _sub = _plugin.events.listen(_onEvent);
    setState(() => _initialized = true);
    _log('initialized');
  }

  void _onEvent(JieliEvent event) {
    if (event is DeviceFoundEvent) {
      setState(() => _devices[event.device.address] = event.device);
    } else if (event is ScanStatusEvent) {
      setState(() {
        _scanning = event.started;
        _status = event.started ? 'scanning' : 'scan stopped';
      });
      _log('scanStatus started=${event.started} ble=${event.ble}');
    } else if (event is ConnectionStateEvent) {
      _log('connectionState ${event.address} state=${event.state}');
      setState(() {
        if (event.state == ConnectionStateEvent.connectionOk) {
          _connectedAddress = event.address;
          _status = 'connected';
        } else if (event.state == ConnectionStateEvent.connectionDisconnect &&
            event.address == _connectedAddress) {
          _connectedAddress = null;
          _status = 'disconnected';
        } else if (event.state == ConnectionStateEvent.connectionConnecting) {
          _status = 'connecting…';
        }
      });
    } else if (event is RcspInitEvent) {
      _log('rcspInit ${event.address} code=${event.code}');
    } else if (event is AdapterStatusEvent) {
      _log('adapter enabled=${event.enabled} hasBle=${event.hasBle}');
    } else if (event is BondStatusEvent) {
      _log('bond ${event.address} status=${event.status}');
    } else if (event is UnknownJieliEvent) {
      _log('unknown ${event.raw}');
    }
  }

  void _log(String msg) {
    setState(() {
      _logs.insert(0, msg);
      if (_logs.length > 200) _logs.removeLast();
    });
  }

  Future<void> _toggleScan() async {
    try {
      if (_scanning) {
        await _plugin.stopScan();
      } else {
        _devices.clear();
        await _plugin.startScan();
      }
    } catch (e) {
      _log('scan error: $e');
    }
  }

  Future<void> _connect(JieliDevice d) async {
    try {
      await _plugin.stopScan();
      setState(() => _status = 'connecting ${d.address}');
      await _plugin.connect(d);
    } catch (e) {
      _log('connect error: $e');
    }
  }

  Future<void> _disconnect() async {
    final addr = _connectedAddress;
    if (addr == null) return;
    try {
      await _plugin.disconnect(addr);
    } catch (e) {
      _log('disconnect error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = _devices.values.toList()
      ..sort((a, b) => (b.rssi ?? -127).compareTo(a.rssi ?? -127));

    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('JieLi Home Demo'),
          actions: [
            if (_connectedAddress != null)
              IconButton(
                icon: const Icon(Icons.bluetooth_disabled),
                onPressed: _disconnect,
              ),
          ],
        ),
        body: !_initialized
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text('Status: $_status'
                              '${_connectedAddress != null ? '\nConnected: $_connectedAddress' : ''}'),
                        ),
                        ElevatedButton.icon(
                          onPressed: _toggleScan,
                          icon: Icon(_scanning ? Icons.stop : Icons.search),
                          label: Text(_scanning ? 'Stop' : 'Scan'),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    flex: 3,
                    child: ListView.separated(
                      itemCount: list.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final d = list[i];
                        return ListTile(
                          dense: true,
                          title: Text(d.name),
                          subtitle: Text(
                              '${d.address}  rssi=${d.rssi}  type=${d.deviceType}  way=${d.connectWay}'),
                          trailing: ElevatedButton(
                            onPressed: () => _connect(d),
                            child: const Text('Connect'),
                          ),
                        );
                      },
                    ),
                  ),
                  const Divider(height: 1),
                  Container(
                    color: Colors.black87,
                    height: 200,
                    child: ListView.builder(
                      itemCount: _logs.length,
                      itemBuilder: (_, i) => Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        child: Text(
                          _logs[i],
                          style: const TextStyle(
                              color: Colors.greenAccent,
                              fontSize: 11,
                              fontFamily: 'monospace'),
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
