import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Esp32BleBaseApp(),
  ));
}

class Esp32BleBaseApp extends StatefulWidget {
  const Esp32BleBaseApp({super.key});

  @override
  State<Esp32BleBaseApp> createState() => _Esp32BleBaseAppState();
}

class _Esp32BleBaseAppState extends State<Esp32BleBaseApp> {
  static const targetServiceUUID = '28cc6cc7-8f00-467d-800c-259ed5e3ac71';
  static const targetCharacteristicUUID = 'fbd620c9-06b3-4db6-8c8b-8b1528f1cbb1';

  final TextEditingController _textController = TextEditingController();
  final List<ScanResult> _scanResults = [];

  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _targetCharacteristic;
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  StreamSubscription<List<int>>? _notificationSubscription;

  bool _isScanning = false;
  String _receivedData = 'No data received yet';

  @override
  void initState() {
    super.initState();
    _requestPermissions();
  }

  @override
  void dispose() {
    _scanSubscription?.cancel();
    _notificationSubscription?.cancel();
    _connectedDevice?.disconnect();
    _textController.dispose();
    super.dispose();
  }

  Future<void> _requestPermissions() async {
    await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();
  }

  Future<void> _startScan() async {
    setState(() {
      _isScanning = true;
      _scanResults.clear();
    });

    await _scanSubscription?.cancel();
    _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
      setState(() {
        _scanResults
          ..clear()
          ..addAll(results.where((result) => result.device.platformName.isNotEmpty));
      });
    });

    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));
    if (mounted) setState(() => _isScanning = false);
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    await FlutterBluePlus.stopScan();
    setState(() => _isScanning = false);

    try {
      await device.connect(timeout: const Duration(seconds: 15));
      if (!mounted) return;
      setState(() => _connectedDevice = device);

      final services = await device.discoverServices();
      for (final service in services) {
        if (service.uuid.str.toLowerCase() != targetServiceUUID) continue;

        for (final characteristic in service.characteristics) {
          if (characteristic.uuid.str.toLowerCase() != targetCharacteristicUUID) continue;

          setState(() => _targetCharacteristic = characteristic);

          if (characteristic.properties.notify) {
            await characteristic.setNotifyValue(true);
            await _notificationSubscription?.cancel();
            _notificationSubscription = characteristic.lastValueStream.listen((value) {
              if (!mounted) return;
              setState(() {
                _receivedData = utf8.decode(value, allowMalformed: true);
              });
            });
          }
        }
      }
    } catch (error) {
      _showSnackBar('Error connecting to device: $error');
    }
  }

  Future<void> _disconnect() async {
    await _notificationSubscription?.cancel();
    _notificationSubscription = null;
    await _connectedDevice?.disconnect();

    if (!mounted) return;
    setState(() {
      _connectedDevice = null;
      _targetCharacteristic = null;
      _receivedData = 'Disconnected';
    });
  }

  Future<void> _sendData(String message) async {
    if (_targetCharacteristic == null || message.isEmpty) return;

    try {
      await _targetCharacteristic!.write(
        utf8.encode(message),
        withoutResponse: false,
      );
    } catch (error) {
      _showSnackBar('Error sending data: $error');
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ESP32 Bluetooth Controller'),
        actions: [
          if (_connectedDevice != null)
            IconButton(
              icon: const Icon(Icons.bluetooth_disabled),
              onPressed: _disconnect,
              tooltip: 'Disconnect',
            ),
        ],
      ),
      body: _connectedDevice == null ? _buildScanView() : _buildControlView(),
    );
  }

  Widget _buildScanView() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isScanning ? null : _startScan,
              icon: const Icon(Icons.search),
              label: Text(_isScanning ? 'Scanning...' : 'Scan for ESP32'),
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: _scanResults.length,
            itemBuilder: (context, index) {
              final device = _scanResults[index].device;
              return ListTile(
                title: Text(device.platformName),
                subtitle: Text(device.remoteId.toString()),
                trailing: ElevatedButton(
                  onPressed: () => _connectToDevice(device),
                  child: const Text('Connect'),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildControlView() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Connected to: ${_connectedDevice?.platformName}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Incoming Data: $_receivedData',
                    style: const TextStyle(fontSize: 16, color: Colors.blue),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _textController,
            decoration: const InputDecoration(
              labelText: 'Message',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          ElevatedButton(
            onPressed: () => _sendData(_textController.text),
            child: const Text('Send to ESP32'),
          ),
        ],
      ),
    );
  }
}
