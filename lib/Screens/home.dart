// lib/home.dart
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:csv/csv.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/student.dart';
import '../services/auth_service.dart';
import '../services/student_data_service.dart';

class HomePage extends StatefulWidget {
  const HomePage({Key? key}) : super(key: key);

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final backgroundColor = const Color(0xFF1A1A1A);
  final cardColor = const Color(0xFF262626);
  final selectedItemColor = const Color(0xFF2E4F3A);
  List<Student> students = [];
  bool isLoading = true;
  final _auth = AuthService();
  final _studentDataService = StudentDataService();
  Map<String, dynamic>? _studentInfo;
  Map<String, List<dynamic>>? _semesterResults;
  double? _overallCGPA;
  String? userId;
  final ScrollController _scrollController = ScrollController();
  bool _showScrollToTop = false;
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;
  List<Student> _filteredStudents = [];
  String _searchQuery = '';
  final Map<String, GlobalKey> _studentKeys = {};
  bool _isScrolling = false;

  @override
  void initState() {
    super.initState();
    loadStudents();
    userId = _auth.getCurrentUserId();
    _loadPreferences();
    _initializeData();

    _scrollController.addListener(() {
      final showScrollToTop = _scrollController.offset > 200;
      if (showScrollToTop != _showScrollToTop) {
        setState(() {
          _showScrollToTop = showScrollToTop;
        });
      }
    });

    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.toLowerCase();
      });
      if (_searchQuery.isNotEmpty) {
        // Add a small delay to ensure the build is complete
        Future.delayed(const Duration(milliseconds: 100), () {
          _scrollToMatchingStudent();
        });
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _scrollToTop() {
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeInOut,
    );
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {});
  }

  Future<void> _initializeData() async {
    setState(() {});

    final hasCache = await _loadCachedData();
    if (!hasCache) {
      await _fetchStudentData();
    }

    setState(() {});
  }

  Future<bool> _loadCachedData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final studentInfoString = prefs.getString('studentInfo');
      final semesterResultsString = prefs.getString('semesterResults');
      final cgpa = prefs.getDouble('overallCGPA');

      if (studentInfoString != null) {
        setState(() {
          _studentInfo = json.decode(studentInfoString);
          _semesterResults = semesterResultsString != null
              ? Map<String, List<dynamic>>.from(json
                  .decode(semesterResultsString)
                  .map(
                      (key, value) => MapEntry(key, List<dynamic>.from(value))))
              : null;
          _overallCGPA = cgpa;
        });
        return true;
      }
      return false;
    } catch (e) {
      print('Error loading cached data: $e');
      return false;
    }
  }

  Future<void> _saveDataToCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_studentInfo != null) {
        await prefs.setString('studentInfo', json.encode(_studentInfo));
      }
      if (_semesterResults != null) {
        await prefs.setString('semesterResults', json.encode(_semesterResults));
      }
      if (_overallCGPA != null) {
        await prefs.setDouble('overallCGPA', _overallCGPA!);
      }
    } catch (e) {
      print('Error saving data to cache: $e');
    }
  }

  Future<void> loadStudents() async {
    try {
      // Load CSV file from assets
      final String csvData =
          await rootBundle.loadString('assets/studentRank61CSE.csv');

      // Convert CSV to list of values
      List<List<dynamic>> csvTable =
          const CsvToListConverter().convert(csvData);

      // Remove header row
      csvTable.removeAt(0);

      // Convert each row to Student object
      List<Student> loadedStudents =
          csvTable.map((row) => Student.fromCsvRow(row)).toList();

      setState(() {
        students = loadedStudents;
        isLoading = false;
      });
    } catch (e) {
      print('Error loading students: $e');
      setState(() {
        isLoading = false;
      });
    }
  }

  Future<void> _fetchStudentData() async {
    try {
      // Get current user's student ID from Firebase
      final userId = _auth.getCurrentUserId();
      if (userId == null) throw Exception('User not found');

      // Fetch student info from Firestore
      final userData = await _studentDataService.getUserData(userId);
      if (userData == null) throw Exception('User data not found');

      final studentId = userData['studentId'];

      // Fetch detailed student info and results
      _studentInfo = await _studentDataService.fetchStudentInfo(studentId);
      _semesterResults = await _studentDataService.fetchResults(studentId);
      _overallCGPA =
          _studentDataService.calculateOverallCGPA(_semesterResults!);

      // Save to cache
      await _saveDataToCache();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading data'),
            backgroundColor: Colors.red,
          ),
        );
      }
      if (_studentInfo == null) {
        setState(() {
          _studentInfo = null;
          _semesterResults = null;
          _overallCGPA = null;
        });
      }
    }
  }

  Future<bool> _onWillPop() async {
    return await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: cardColor,
            title:
                const Text('Exit App', style: TextStyle(color: Colors.white)),
            content: const Text('Do you want to exit the app?',
                style: TextStyle(color: Colors.white70)),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child:
                    const Text('No', style: TextStyle(color: Colors.white70)),
              ),
              TextButton(
                onPressed: () => SystemNavigator.pop(),
                child: const Text('Yes', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ) ??
        false;
  }

  Widget _buildCurrentUserRank() {
    String? currentUserId = _studentInfo?['studentId'] as String?;
    currentUserId ??= userId;

    if (currentUserId == null) return const SizedBox.shrink();

    // Find the current user's position
    int userIndex =
        students.indexWhere((student) => student.id == currentUserId);
    if (userIndex < 0 || userIndex < 3) return const SizedBox.shrink();

    final student = students[userIndex];
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: selectedItemColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white24, width: 1),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 30,
            child: Text(
              '${userIndex + 1}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          CircleAvatar(
            radius: 20,
            backgroundColor: Colors.grey[800],
            child: Text(
              student.name[0].toUpperCase(),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  student.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  'Your Position',
                  style: TextStyle(
                    color: Colors.grey[400],
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Text(
            student.cgpa.toStringAsFixed(2),
            style: TextStyle(
              color: Colors.grey[400],
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  void _scrollToMatchingStudent() {
    if (_searchQuery.isEmpty) return;

    // Find all matching students
    List<int> matchingIndices = [];
    
    // Check all students, including podium
    for (int i = 0; i < students.length; i++) {
      if (students[i].name.toLowerCase().contains(_searchQuery)) {
        matchingIndices.add(i);
      }
    }

    if (matchingIndices.isEmpty) return;

    // Get the first match
    int matchIndex = matchingIndices[0];
    Student matchingStudent = students[matchIndex];

    // Calculate the scroll offset based on position
    double offset;
    if (matchIndex < 3) {
      // For podium positions (0, 1, 2), scroll to top
      offset = 0;
    } else {
      // For list positions (3 and beyond)
      // Height calculation:
      // - 200 for podium section
      // - ~76 for current user rank (if shown)
      // - 20 for spacing
      // - ~72 per list item
      double podiumHeight = 200;
      double currentUserHeight = _buildCurrentUserRank().toString() != 'SizedBox.shrink' ? 76 : 0;
      double spacingHeight = 20;
      double itemHeight = 72;
      
      offset = podiumHeight + currentUserHeight + spacingHeight + 
               ((matchIndex - 3) * itemHeight);
    }

    // Perform the scroll with a slight offset for better visibility
    _scrollController.animateTo(
      max(0, offset - 100), // Subtract 100 to show some content above
      duration: const Duration(milliseconds: 100),
      curve: Curves.easeInOut,
    ).then((_) {
      // After main scroll, ensure the specific item is fully visible
      if (_studentKeys[matchingStudent.id]?.currentContext != null) {
        Scrollable.ensureVisible(
          _studentKeys[matchingStudent.id]!.currentContext!,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          alignment: 0.3, // Align towards the top third of the screen
        );
      }
    });
  }

  

  void _toggleSearch() {
    setState(() {
      _isSearching = !_isSearching;
      if (!_isSearching) {
        _searchController.clear();
        _searchQuery = '';
      }
    });
  }

  

  @override
  Widget build(BuildContext context) {
    String? currentUserId = _studentInfo?['studentId'] as String?;
    currentUserId ??= userId;
    final batch = _studentInfo?['batchNo'].toString();

    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        appBar: AppBar(
          title: _isSearching
              ? TextField(
                  controller: _searchController,
                  autofocus: true,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Search by name...',
                    hintStyle: TextStyle(color: Colors.grey[400]),
                    border: InputBorder.none,
                  ),
                )
              : Column(
                  children: [
                    const Text(
                      'DIU Leaderboard',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'CSE - Batch ${batch}',
                      style: TextStyle(
                        color: Colors.grey[400],
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
          centerTitle: true,
          leading: _isSearching
              ? IconButton(
                  icon: const Icon(Icons.arrow_back),
                  color: Colors.white,
                  onPressed: _toggleSearch,
                )
              : null,
          actions: [
            IconButton(
              icon: Icon(_isSearching ? Icons.clear : Icons.search),
              onPressed: _toggleSearch,
              color: Colors.white,
            ),
          ],
          backgroundColor: backgroundColor,
        ),
        backgroundColor: backgroundColor,
        body: SafeArea(
          child: isLoading
              ? const Center(child: CircularProgressIndicator())
              : students.isEmpty
                  ? const Center(
                      child: Text('No data available',
                          style: TextStyle(color: Colors.white)))
                  // : _isSearching
                  //     ? SingleChildScrollView(
                  //         child: Column(
                  //           children: [
                  //             const SizedBox(height: 16),
                  //             _buildSearchResults(),
                  //           ],
                  //         ),
                  //       )
                  : CustomScrollView(
                      controller: _scrollController,
                      slivers: [
                        // App Bar with Title

                        // Top 3 Podium
                        if (students.length >= 3)
                          SliverToBoxAdapter(
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16.0),
                              child: SizedBox(
                                height: 200,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Expanded(
                                        child:
                                            _buildPodiumItem(students[1], 2)),
                                    Expanded(
                                        flex: 2,
                                        child:
                                            _buildPodiumItem(students[0], 1)),
                                    Expanded(
                                        child:
                                            _buildPodiumItem(students[2], 3)),
                                  ],
                                ),
                              ),
                            ),
                          ),

                        // Current User's Rank (if not in top 3)
                        SliverToBoxAdapter(
                          child: _buildCurrentUserRank(),
                        ),

                        const SliverToBoxAdapter(
                          child: SizedBox(height: 20),
                        ),

                        // Remaining Rankings
                        SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, index) {
                              final student = students[index + 3];
                              final isCurrentUser = student.id == currentUserId;
                              return _buildListItem(
                                  student, index + 4, isCurrentUser);
                            },
                            childCount:
                                students.length > 3 ? students.length - 3 : 0,
                          ),
                        ),
                      ],
                    ),
        ),
        floatingActionButton: AnimatedOpacity(
          opacity: _showScrollToTop && !_isSearching ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 200),
          child: FloatingActionButton(
            onPressed: _scrollToTop,
            child: const Icon(Icons.arrow_upward, color: Colors.yellowAccent),
            backgroundColor: cardColor,
            elevation: 1,
          ),
        ),
      ),
    );
  }

  Widget _buildPodiumItem(Student student, int rank) {
    Color getMedalColor(int rank) {
      switch (rank) {
        case 1:
          return const Color(0xFFFFD700); // Gold
        case 2:
          return const Color(0xFFC0C0C0); // Silver
        case 3:
          return const Color(0xFFCD7F32); // Bronze
        default:
          return Colors.grey[400]!;
      }
    }

    final bool isMatch = _searchQuery.isNotEmpty &&
        student.name.toLowerCase().contains(_searchQuery);

    // Create a key for podium items
    _studentKeys.putIfAbsent(student.id, () => GlobalKey());

    return Container(
      key: _studentKeys.putIfAbsent(student.id, () => GlobalKey()),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (rank == 1)
            Transform.translate(
              offset: const Offset(0, 10),
              child: Image.asset(
                'assets/crown.png',
                width: 50,
                height: 50,
                fit: BoxFit.contain,
              ),
            ),
          Stack(
            alignment: Alignment.center,
            children: [
              CircleAvatar(
                radius: rank == 1 ? 40 : 30,
                backgroundColor: isMatch ? Colors.amber : getMedalColor(rank),
                child: Text(
                  student.name[0].toUpperCase(),
                  style: TextStyle(
                    color: isMatch ? Colors.black : Colors.white,
                    fontSize: rank == 1 ? 24 : 20,
                  ),
                ),
              ),
              if (rank <= 3)
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: CircleAvatar(
                    radius: 12,
                    backgroundColor: Colors.grey[600]!,
                    child: Text(
                      '$rank',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            student.name,
            style: TextStyle(
              color: isMatch ? Colors.amber : Colors.white,
              fontSize: rank == 1 ? 16 : 14,
              fontWeight: FontWeight.bold,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            student.cgpa.toStringAsFixed(2),
            style: TextStyle(
              color: isMatch ? Colors.amber : getMedalColor(rank),
              fontSize: rank == 1 ? 16 : 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildListItem(Student student, int rank, bool isCurrentUser) {
    final bool isMatch = _searchQuery.isNotEmpty &&
        student.name.toLowerCase().contains(_searchQuery);

    return Container(
      key: _studentKeys.putIfAbsent(student.id, () => GlobalKey()),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      decoration: BoxDecoration(
        color: isMatch
            ? Colors.amber.withOpacity(0.3)
            : (isCurrentUser ? selectedItemColor : cardColor),
        borderRadius: BorderRadius.circular(12),
        border: isMatch ? Border.all(color: Colors.amber, width: 2) : null,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 40,
            child: Text(
              '$rank',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          CircleAvatar(
            radius: 20,
            backgroundColor: isMatch ? Colors.amber : Colors.grey[800],
            child: Text(
              student.name[0].toUpperCase(),
              style: TextStyle(
                color: isMatch ? Colors.black : Colors.white,
                fontSize: 14,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              student.name,
              style: TextStyle(
                color: isMatch ? Colors.amber : Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Text(
            student.cgpa.toStringAsFixed(2),
            style: TextStyle(
              color: isMatch ? Colors.amber : Colors.grey[400],
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
