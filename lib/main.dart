import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tmlink/core/config.dart';

void main() {
  runApp(const TMLinkApp());
}

class TMLinkApp extends StatelessWidget {
  const TMLinkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TMLink',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const SettingsPage(),
    );
  }
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final TextEditingController _tmIpController = TextEditingController();
  final TextEditingController _tmApiKeyController = TextEditingController();
  final TextEditingController _obsWsController = TextEditingController();
  final TextEditingController _fieldSetIdController = TextEditingController();
  int _numFields = 1;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  /// Loads saved settings from persistent storage
  Future<void> _loadSettings() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      _tmIpController.text = prefs.getString('tm_ip') ?? Config.defaultTmIp;
      _tmApiKeyController.text = prefs.getString('tm_api_key') ?? '';
      _obsWsController.text =
          prefs.getString('obs_ws_url') ?? Config.defaultObsWsUrl;
      _fieldSetIdController.text = prefs.getString('field_set_id') ?? Config.defaultFieldSetId;
      _numFields = prefs.getInt('num_fields') ?? Config.defaultFieldNumber;
    });
  }

  /// Saves settings persistently
  Future<void> _saveSettings() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('tm_ip', _tmIpController.text.trim());
    await prefs.setString('tm_api_key', _tmApiKeyController.text.trim());
    await prefs.setString('obs_ws_url', _obsWsController.text.trim());
    await prefs.setString('field_set_id', _fieldSetIdController.text.trim());
    await prefs.setInt('num_fields', _numFields);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Settings saved successfully!")),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("TMLink - Settings"),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Connection Settings",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),

            // TM Server IP
            _buildTextField(_tmIpController, "TM Server IP"),
            const SizedBox(height: 10),

            // TM API Key
            _buildTextField(
              _tmApiKeyController,
              "TM API Key",
              isPassword: true,
            ),
            const SizedBox(height: 10),

            // OBS WebSocket Address
            _buildTextField(_obsWsController, "OBS WebSocket Address"),
            const SizedBox(height: 10),

            // Field Set ID
            _buildTextField(_fieldSetIdController, "Field Set ID"),
            const SizedBox(height: 10),

            // Number of Fields Dropdown
            const Text("Number of Fields:", style: TextStyle(fontSize: 16)),
            DropdownButton<int>(
              value: _numFields,
              items:
                  List.generate(10, (index) => index + 1)
                      .map(
                        (num) => DropdownMenuItem<int>(
                          value: num,
                          child: Text(num.toString()),
                        ),
                      )
                      .toList(),
              onChanged: (int? newValue) {
                if (newValue != null) {
                  setState(() {
                    _numFields = newValue;
                  });
                }
              },
            ),
            const SizedBox(height: 20),

            // Save Button
            Center(
              child: ElevatedButton(
                onPressed: _saveSettings,
                child: const Text("Save Settings"),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Helper function to build a text input field
  Widget _buildTextField(
    TextEditingController controller,
    String label, {
    bool isPassword = false,
  }) {
    return TextField(
      controller: controller,
      obscureText: isPassword,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
    );
  }
}
