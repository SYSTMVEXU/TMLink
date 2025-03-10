import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  // Store state reference for saving data on navigation change
  static _SettingsPageState? _settingsState;

  /// Saves settings persistently when switching pages
  static Future<void> saveSettings() async {
    if (_settingsState == null) return;

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('tm_ip', _settingsState!._tmIpController.text.trim());
    await prefs.setString(
      'tm_api_key',
      _settingsState!._tmApiKeyController.text.trim(),
    );
    await prefs.setString(
      'obs_ws_url',
      _settingsState!._obsWsController.text.trim(),
    );
    await prefs.setString(
      'field_set_id',
      _settingsState!._fieldSetIdController.text.trim(),
    );
    await prefs.setInt('num_fields', _settingsState!._numFields);
  }

  @override
  State<SettingsPage> createState() {
    _settingsState = _SettingsPageState();
    return _settingsState!;
  }
}

class _SettingsPageState extends State<SettingsPage> {
  final TextEditingController _tmIpController = TextEditingController();
  final TextEditingController _tmApiKeyController = TextEditingController();
  final TextEditingController _obsWsController = TextEditingController();
  final TextEditingController _fieldSetIdController = TextEditingController();
  int _numFields = 1;
  late Future<void> _loadSettingsFuture;

  @override
  void initState() {
    super.initState();
    _loadSettingsFuture = _loadSettings(); // Load settings on startup
  }

  /// Loads settings from SharedPreferences
  Future<void> _loadSettings() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();

    int fieldCount = prefs.getInt('num_fields') ?? 1;
    if (fieldCount < 1) fieldCount = 1;

    setState(() {
      _numFields = fieldCount;
      _tmIpController.text = prefs.getString('tm_ip') ?? '127.0.0.1';
      _tmApiKeyController.text = prefs.getString('tm_api_key') ?? '';
      _obsWsController.text =
          prefs.getString('obs_ws_url') ?? 'ws://localhost:4444/';
      _fieldSetIdController.text = prefs.getString('field_set_id') ?? '1';
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
    return FutureBuilder(
      future: _loadSettingsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(),
          ); // Show loading indicator
        }
        return _buildSettingsPage();
      },
    );
  }

  /// Builds the settings UI
  Widget _buildSettingsPage() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Settings",
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const Divider(),
          _buildTextField(_tmIpController, "TM Server IP"),
          const SizedBox(height: 10),
          _buildTextField(_tmApiKeyController, "TM API Key", isPassword: true),
          const SizedBox(height: 10),
          _buildTextField(_obsWsController, "OBS WebSocket Address"),
          const SizedBox(height: 10),
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

          Center(
            child: ElevatedButton(
              onPressed: _saveSettings,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
              ),
              child: const Text("Save Settings"),
            ),
          ),
        ],
      ),
    );
  }

  /// Helper to build a text input field
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
