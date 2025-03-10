import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tmlink/core/config.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  // Store state reference for saving data on navigation change
  static _DashboardPageState? _dashboardState;

  /// Saves updated field mappings when navigating away
  static Future<void> saveFieldMappings() async {
    if (_dashboardState == null) {
      return; // Prevents errors if state is not initialized
    }

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    for (int i = 0; i < _dashboardState!._numFields; i++) {
      await prefs.setString(
        'field_name_$i',
        _dashboardState!.fieldNameControllers[i].text.trim(),
      );
      await prefs.setString(
        'scene_name_$i',
        _dashboardState!.sceneNameControllers[i].text.trim(),
      );
    }
  }

  @override
  State<DashboardPage> createState() {
    _dashboardState = _DashboardPageState(); // Assign state reference
    return _dashboardState!;
  }
}

class _DashboardPageState extends State<DashboardPage> {
  int _numFields = 1;
  List<TextEditingController> fieldNameControllers = [];
  List<TextEditingController> sceneNameControllers = [];
  late Future<void> _loadFieldsFuture; // Store future result

  @override
  void initState() {
    super.initState();
    _loadFieldsFuture = _loadFieldMappings(); // Load field mappings on startup
  }

  /// Loads field mappings from SharedPreferences
  Future<void> _loadFieldMappings() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    int fieldCount = prefs.getInt('num_fields') ?? Config.defaultFieldNumber;

    // Ensure at least 1 field to prevent index errors
    if (fieldCount < 1) fieldCount = 1;

    _numFields = fieldCount;
    fieldNameControllers = List.generate(
      _numFields,
      (i) => TextEditingController(
        text: prefs.getString('field_name_$i') ?? 'Field ${i + 1}',
      ),
    );
    sceneNameControllers = List.generate(
      _numFields,
      (i) => TextEditingController(
        text: prefs.getString('scene_name_$i') ?? 'OBS Scene ${i + 1}',
      ),
    );

    setState(() {}); // Trigger UI update after loading data
  }

  /// Saves updated field mappings manually
  Future<void> _saveFieldMappings() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    for (int i = 0; i < _numFields; i++) {
      await prefs.setString(
        'field_name_$i',
        fieldNameControllers[i].text.trim(),
      );
      await prefs.setString(
        'scene_name_$i',
        sceneNameControllers[i].text.trim(),
      );
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Field mappings updated successfully!")),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _loadFieldsFuture, // Wait for data to load
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(),
          ); // Show loading indicator
        }
        return _buildDashboard();
      },
    );
  }

  /// Builds the dashboard UI
  Widget _buildDashboard() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Dashboard",
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const Divider(),
          Expanded(
            child: ListView.builder(
              itemCount: _numFields,
              itemBuilder: (context, index) {
                return _buildFieldMapping(index);
              },
            ),
          ),
          const SizedBox(height: 20),
          Center(
            child: ElevatedButton(
              onPressed: _saveFieldMappings,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
              ),
              child: const Text("Save Field Mappings"),
            ),
          ),
        ],
      ),
    );
  }

  /// Builds an editable Field Name → OBS Scene Name mapping
  Widget _buildFieldMapping(int index) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          // Field Name Input
          Expanded(
            flex: 2,
            child: TextField(
              controller: fieldNameControllers[index],
              decoration: InputDecoration(
                labelText: "Field ${index + 1} Name",
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(width: 10),
          const Icon(Icons.arrow_forward, size: 24, color: Colors.grey),
          const SizedBox(width: 10),
          // OBS Scene Name Input
          Expanded(
            flex: 2,
            child: TextField(
              controller: sceneNameControllers[index],
              decoration: InputDecoration(
                labelText: "OBS Scene Name",
                border: const OutlineInputBorder(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
