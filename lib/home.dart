// invoicematcher/lib/home.dart
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

// NOTE: Replace 127.0.0.1 with your computer's local IP address for mobile testing.
const String backendUrl = 'https://invoicematcher-api.onrender.com/match';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  PlatformFile? _invoiceFile;
  PlatformFile? _poFile;
  Map<String, dynamic>? _matchResult;
  bool _isLoading = false;
  double _progressValue = 0.0;
  // NEW: Timer to update progress
  Timer? _timer;
  String _statusMessage =
      'Select Invoice and Purchase Order (PO) to start matching.';

  static const double breakpoint = 600;

  // --- File Picker Function ---
  Future<void> _pickFile(bool isInvoice) async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      withData: true,
    );

    if (result != null && result.files.first.bytes != null) {
      setState(() {
        final file = result.files.first;
        if (isInvoice) {
          _invoiceFile = file;
          _statusMessage = 'Invoice: ${file.name} selected.';
        } else {
          _poFile = file;
          _statusMessage = 'PO: ${file.name} selected.';
        }
        _matchResult = null;
      });
    } else if (result != null) {
      setState(
        () => _statusMessage = 'Error reading file bytes. Try a different PDF.',
      );
    }
  }

  // --- API Call to Backend ---
  Future<void> _runMatching() async {
    if (_invoiceFile == null || _poFile == null) {
      setState(() => _statusMessage = 'Error: Please select both files.');
      return;
    }

    setState(() {
      _isLoading = true;
      _progressValue = 0.0; // Reset progress
      _statusMessage =
          'Processing documents with AI & Hybrid OCR/Table Extraction...';
    });
    _startProgressTimer();

    try {
      var request = http.MultipartRequest('POST', Uri.parse(backendUrl));

      request.files.add(
        http.MultipartFile.fromBytes(
          'invoice',
          _invoiceFile!.bytes!,
          filename: _invoiceFile!.name,
        ),
      );
      request.files.add(
        http.MultipartFile.fromBytes(
          'po',
          _poFile!.bytes!,
          filename: _poFile!.name,
        ),
      );

      var response = await request.send();
      final responseBody = await response.stream.bytesToString();

      // After the response is received, instantly set to 100% and proceed
      _stopProgressTimer(finalValue: 1.0);

      if (response.statusCode == 200) {
        setState(() {
          _matchResult = jsonDecode(responseBody);
          _statusMessage = 'Matching complete. Review results below.';
        });
      } else {
        setState(() {
          _matchResult = null;
          _statusMessage =
              'Error: Server processing failed (Status ${response.statusCode}). Details: $responseBody';
        });
      }
    } catch (e) {
      _stopProgressTimer(finalValue: 0.0);
      setState(() {
        _matchResult = null;
        _statusMessage =
            'Network Error: Could not connect to backend. Is the Python server running? Error: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // --- UI Widget Helpers ---

  Widget _buildFileCard(PlatformFile? file, bool isInvoice) {
    return Card(
      elevation: 2,
      child: ListTile(
        leading: Icon(
          FontAwesomeIcons.filePdf,
          color: isInvoice ? Colors.red.shade700 : Colors.blue.shade700,
        ),
        title: Text(isInvoice ? 'Invoice File' : 'PO File'),
        subtitle: Text(file?.name ?? 'No file selected (PDF Only)'),
        trailing: ElevatedButton(
          onPressed: _isLoading ? null : () => _pickFile(isInvoice),
          child: Text(file == null ? 'SELECT FILE' : 'CHANGE FILE'),
        ),
      ),
    );
  }

  Widget _buildDataSummary(
    Map<String, dynamic> data,
    String title,
    Color color,
  ) {
    // Determine box color for a cleaner palette.
    final bool isInvoice = title.contains('INVOICE');
    final Color boxColor =
        isInvoice
            ? Colors.blueGrey.shade100.withOpacity(0.5)
            : color.withOpacity(0.1);
    final Color textColor = isInvoice ? Colors.indigo : color;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: boxColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: textColor,
            ),
          ),
          const Divider(height: 10, color: Colors.grey),
          Text(
            'ID: ${data['id'] ?? 'N/A'}',
            style: const TextStyle(fontSize: 14),
          ),
          Text(
            'Vendor: ${data['vendor'] ?? 'N/A'}',
            style: const TextStyle(fontSize: 14),
          ),
          Text(
            'Total: \$${(data['total'] as num?)?.toStringAsFixed(2) ?? '0.00'}',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Widget _buildResultCard(double screenWidth) {
    if (_matchResult == null) return Container();

    final status = _matchResult!['status'] as String? ?? 'ERROR';
    final explanations = _matchResult!['explanations'] as List<dynamic>? ?? [];
    final invData =
        _matchResult!['invoice_data'] as Map<String, dynamic>? ?? {};
    final poData = _matchResult!['po_data'] as Map<String, dynamic>? ?? {};

    final isApproved = status == 'APPROVED';
    final color = isApproved ? Colors.green.shade700 : Colors.red.shade700;
    final bgColor = isApproved ? Colors.green.shade50 : Colors.red.shade50;

    final bool isMobileLayout = screenWidth < breakpoint;

    Widget dataComparisonWidget;

    if (isMobileLayout) {
      dataComparisonWidget = Column(
        children: [
          _buildDataSummary(invData, 'INVOICE DATA (Extracted)', Colors.indigo),
          const SizedBox(height: 15),
          _buildDataSummary(poData, 'PO DATA (Extracted)', Colors.teal),
        ],
      );
    } else {
      dataComparisonWidget = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _buildDataSummary(
              invData,
              'INVOICE DATA (Extracted)',
              Colors.indigo,
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: _buildDataSummary(
              poData,
              'PO DATA (Extracted)',
              Colors.teal,
            ),
          ),
        ],
      );
    }

    // Agent Summary/Explanation logic
    String agentSummary =
        explanations.isNotEmpty
            ? explanations.first.toString()
            : 'Processing result empty.';

    // Aggressively remove leading warning icon and trim.
    agentSummary =
        agentSummary
            .replaceFirst('⚠️', '')
            .replaceFirst('!', '')
            .replaceFirst('🚩', '')
            .trimLeft();

    // Split the summary: primary status before the first dash, detail after.
    final int dashIndex = agentSummary.indexOf(' - ');
    final String primaryStatusText =
        dashIndex != -1 ? agentSummary.substring(0, dashIndex) : agentSummary;
    final String mainExplanationText =
        dashIndex != -1 ? agentSummary.substring(dashIndex + 3) : '';

    // Define clean, non-italic, black text styles
    final TextStyle primaryTextStyle;

    // Style for the mismatch summary text for full control
    const TextStyle mismatchSummaryTextStyle = TextStyle(
      fontWeight: FontWeight.normal,
      fontStyle: FontStyle.normal,
      fontSize: 14,
      color: Colors.black,
      decoration: TextDecoration.none,
    );

    if (isApproved) {
      // Approved status: Green, bold, with custom status text
      primaryTextStyle = TextStyle(
        fontWeight: FontWeight.w800,
        fontStyle: FontStyle.normal,
        fontSize: 16,
        color: color,
      );
    } else {
      // Mismatch status: Red, bold for the main header
      primaryTextStyle = const TextStyle(
        fontWeight: FontWeight.w800,
        fontStyle: FontStyle.normal,
        fontSize: 16,
        color: Colors.red,
      );
    }

    return Card(
      elevation: 4,
      color: bgColor,
      margin: const EdgeInsets.symmetric(vertical: 20),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Status Header
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  isApproved
                      ? FontAwesomeIcons.circleCheck
                      : FontAwesomeIcons.circleExclamation,
                  color: color,
                  size: 24,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'MATCH STATUS:',
                        style: TextStyle(fontSize: 15, color: color),
                      ),
                      // Apply primaryTextStyle to status
                      Text(
                        status,
                        style: primaryTextStyle,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 30),

            // AGENT-STYLE SUMMARY
            Padding(
              padding: const EdgeInsets.only(bottom: 15.0),
              child: Text(
                '$primaryStatusText${mainExplanationText.isNotEmpty ? ' - $mainExplanationText' : ''}',
                style:
                    mismatchSummaryTextStyle, // Applies clean, non-italic, no-underline, black text
              ),
            ),

            // Responsive Data Comparison
            dataComparisonWidget,
            const SizedBox(height: 20),

            // DETAILED EXPLANATIONS
            const Text(
              'Detailed Findings (Agent Log):',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            // Checkmark/warning icon handling
            ...explanations
                .skip(1)
                .map(
                  (exp) => Padding(
                    padding: const EdgeInsets.only(bottom: 8.0, left: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          exp.toString().contains('⚠️') ? '🔴' : '✅',
                          style: const TextStyle(fontSize: 16),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            exp.toString().replaceFirst('⚠️', '').trim(),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
                .toList(),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final double maxContentWidth =
        screenWidth > breakpoint ? 850.0 : screenWidth * 0.95;

    // Dynamic top padding: Large initially (40.0), reduced during/after matching (20.0).
    final double topPadding =
        (_matchResult == null && !_isLoading) ? 40.0 : 20.0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Invoice & PO Matcher 🤖'),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        // Apply the dynamic padding at the top
        padding: EdgeInsets.fromLTRB(20.0, topPadding, 20.0, 20.0),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxContentWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1. FILE PICKERS
                _buildFileCard(_invoiceFile, true),
                const SizedBox(height: 10),
                _buildFileCard(_poFile, false),
                const SizedBox(height: 20),

                // 2. RUN BUTTON
                ElevatedButton.icon(
                  onPressed:
                      (_invoiceFile != null && _poFile != null && !_isLoading)
                          ? _runMatching
                          : null,
                  icon:
                      _isLoading
                          ? const SizedBox(
                            width: 15,
                            height: 15,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                          : const Icon(FontAwesomeIcons.rocket),
                  label: Text(
                    _isLoading
                        ? 'MATCHING... PLEASE WAIT(${(_progressValue * 100).round()}%)' // Display percentage'
                        : 'RUN AI MATCHING & REVIEW',
                  ),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    backgroundColor: Theme.of(context).primaryColor,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.grey,
                  ),
                ),
                const SizedBox(height: 15),

                // Status Message
                Center(
                  child: Text(
                    _statusMessage,
                    textAlign: TextAlign.center,
                    maxLines: 1, // Enforce single line
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontStyle: FontStyle.italic,
                      color: _isLoading ? Colors.blue : Colors.black54,
                      fontSize: 12, // Smaller font size
                    ),
                  ),
                ),
                const SizedBox(height: 10),

                // 3. RESULTS DISPLAY
                _buildResultCard(screenWidth),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // NEW: Timer Logic
  void _startProgressTimer() {
    const int totalTimeInSeconds = 15; // Simulate a 15-second process
    const Duration updateInterval = Duration(milliseconds: 500);
    final double increment =
        1.0 / (totalTimeInSeconds * 1000 / updateInterval.inMilliseconds);

    // Stop any existing timer
    _timer?.cancel();

    _timer = Timer.periodic(updateInterval, (timer) {
      setState(() {
        if (_progressValue < 0.9) {
          // Cap progress before 100% until response is received
          _progressValue += increment;

          // Update status message dynamically
          int percent = (_progressValue * 100).round();
          if (percent < 25) {
            _statusMessage = 'Extraction (OCR) in progress: $percent%';
          } else if (percent < 75) {
            _statusMessage = 'AI Matching Logic running: $percent%';
          } else {
            _statusMessage = 'Finalizing report... $percent%';
          }
        } else {
          // Stop timer once it hits 90% and waits for network response
          _progressValue = 0.9;
          timer.cancel();
        }
      });
    });
  }

  void _stopProgressTimer({required double finalValue}) {
    _timer?.cancel();
    setState(() {
      _progressValue = finalValue;
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
