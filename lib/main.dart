import 'package:flutter/material.dart';
import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:tmlink/core/dashboard_page.dart';
import 'package:tmlink/core/settings_page.dart';

void main() {
  runApp(const TMLinkApp());

  // Set up a resizable, draggable window
  doWhenWindowReady(() {
    appWindow.title = "TMLink";
    appWindow.minSize = const Size(800, 500);
    appWindow.size = const Size(1000, 600);
    appWindow.alignment = Alignment.center;
    appWindow.show();
  });
}

class TMLinkApp extends StatelessWidget {
  const TMLinkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TMLink',
      debugShowCheckedModeBanner: false, // Remove debug banner
      themeMode: ThemeMode.system, // Follow system theme
      theme: ThemeData.light().copyWith(
        primaryColor: Colors.yellowAccent,
        scaffoldBackgroundColor: Colors.white,
        textSelectionTheme: const TextSelectionThemeData(
          cursorColor: Colors.black, // Makes the text cursor yellow
          selectionColor:
              Colors.black, // Highlight color when selecting text
          selectionHandleColor:
              Colors.black, // Handle color for text selection
        ),
        inputDecorationTheme: InputDecorationTheme(
          focusedBorder: const OutlineInputBorder(
            borderSide: BorderSide(
              color: Colors.black,
              width: 2,
            ), // Yellow border when focused
          ),
          enabledBorder: const OutlineInputBorder(
            borderSide: BorderSide(
              color: Colors.grey,
              width: 1,
            ), // Default border
          ),
          labelStyle: const TextStyle(
            color: Colors.black,
          ), // Yellow label text when focused
          focusedErrorBorder: const OutlineInputBorder(
            borderSide: BorderSide(
              color: Colors.redAccent,
              width: 2,
            ), // Red error border when focused
          ),
        ),
      ),
      darkTheme: ThemeData.dark().copyWith(
        primaryColor: Colors.yellowAccent,
        scaffoldBackgroundColor: const Color(
          0xFF1E1E1E,
        ), // Dark mode background
        textSelectionTheme: const TextSelectionThemeData(
          cursorColor: Colors.white, // Makes the text cursor yellow
          selectionColor: Colors.white, // Highlight color when selecting text
          selectionHandleColor: Colors.white, // Handle color for text selection
        ),
        inputDecorationTheme: InputDecorationTheme(
          focusedBorder: const OutlineInputBorder(
            borderSide: BorderSide(
              color: Colors.white,
              width: 2,
            ), // Yellow border when focused
          ),
          enabledBorder: const OutlineInputBorder(
            borderSide: BorderSide(
              color: Colors.grey,
              width: 1,
            ), // Default border
          ),
          labelStyle: const TextStyle(
            color: Colors.white,
          ), // Yellow label text when focused
          focusedErrorBorder: const OutlineInputBorder(
            borderSide: BorderSide(
              color: Colors.redAccent,
              width: 2,
            ), // Red error border when focused
          ),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

  final List<Widget> _pages = [
    const DashboardPage(),
    const SettingsPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          _buildSidebar(context), // Sidebar navigation
          Expanded(
            child: Column(
              children: [
                Expanded(child: _pages[_selectedIndex]),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Custom sidebar for navigation
  Widget _buildSidebar(BuildContext context) {
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: 200,
      color: isDarkMode ? Colors.black87 : Colors.grey[200],
      child: Column(
        children: [
          const SizedBox(height: 20),
          Text(
            "TMLink",
            style: TextStyle(
              fontSize: 20,
              color: isDarkMode ? Colors.white : Colors.black,
            ),
          ),
          Text(
            "by System Overload",
            style: TextStyle(
              fontSize: 12,
              fontStyle: FontStyle.italic,
              color: isDarkMode ? Colors.white : Colors.black,
            ),
          ),
          Divider(color: isDarkMode ? Colors.white24 : Colors.black26),
          _buildNavItem(Icons.dashboard, "Dashboard", 0, isDarkMode),
          _buildNavItem(Icons.settings, "Settings", 1, isDarkMode),
        ],
      ),
    );
  }

  void _onNavItemTapped(int index) {
    if (_selectedIndex == index) return; // Prevent unnecessary saves

    // Call save function if the current page has one
    if (_selectedIndex == 0) {
      DashboardPage.saveFieldMappings(); // Save dashboard data
    } else if (_selectedIndex == 1) {
      SettingsPage.saveSettings(); // Save settings data
    }

    setState(() {
      _selectedIndex = index;
    });
  }


  /// Sidebar navigation item
  Widget _buildNavItem(
    IconData icon,
    String title,
    int index,
    bool isDarkMode,
  ) {
    return ListTile(
      focusNode: FocusNode(skipTraversal: true),
      leading: Stack(
        children: [
          // Black outline
          Icon(
            icon,
            size: 25,
            color: Colors.black, // Black outline in light mode
          ),
          // Actual icon (slightly smaller to create the outline effect)
          Positioned.fill(
            child: Align(
              alignment: Alignment.center,
              child: Icon(
                icon,
                size: 24, // Slightly smaller than the outline icon
                color:
                    _selectedIndex == index
                        ? Colors.yellowAccent
                        : (isDarkMode ? Colors.white : Colors.black),
              ),
            ),
          ),
        ],
      ),
      title: Text(
        title,
        style: TextStyle(color: isDarkMode ? Colors.white : Colors.black),
      ),
      selected: _selectedIndex == index,
      onTap: () => _onNavItemTapped(index),
    );
  }
}
