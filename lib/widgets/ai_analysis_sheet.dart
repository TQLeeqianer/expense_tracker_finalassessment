import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../services/gemini_service.dart';

class AiAnalysisSheet extends StatefulWidget {
  final Map<String, dynamic> summaryData;

  const AiAnalysisSheet({
    super.key,
    required this.summaryData,
  });

  @override
  State<AiAnalysisSheet> createState() => _AiAnalysisSheetState();
}

class _AiAnalysisSheetState extends State<AiAnalysisSheet> with SingleTickerProviderStateMixin {
  String? _adviceMarkdown;
  String? _error;
  bool _isLoading = true;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    
    _pulseAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    ));

    _fetchAdvice();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _fetchAdvice() async {
    try {
      final advice = await GeminiService().getFinancialAdvice(widget.summaryData);
      if (mounted) {
        setState(() {
          _adviceMarkdown = advice;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceAll('GeminiScanException: ', '');
          _isLoading = false;
        });
      }
    }
  }

  Widget _buildLoading() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          FadeTransition(
            opacity: _pulseAnimation,
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.blue.withOpacity(0.1),
              ),
              child: const Icon(
                Icons.auto_awesome,
                size: 64,
                color: Colors.blue,
              ),
            ),
          ),
          const SizedBox(height: 32),
          const Text(
            'Analyzing your financial habits...',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.blueGrey,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'The AI Advisor is reading your transactions',
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.blue.shade900, Colors.blue.shade600],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.auto_awesome, color: Colors.amber, size: 28),
                    SizedBox(width: 12),
                    Text(
                      'AI Financial Advisor',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                )
              ],
            ),
          ),
          
          Expanded(
            child: _isLoading
                ? _buildLoading()
                : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32.0),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.error_outline, size: 64, color: Colors.red),
                              const SizedBox(height: 16),
                              Text(_error!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
                              const SizedBox(height: 24),
                              ElevatedButton(
                                onPressed: () {
                                  setState(() {
                                    _error = null;
                                    _isLoading = true;
                                  });
                                  _fetchAdvice();
                                },
                                child: const Text('Try Again'),
                              )
                            ],
                          ),
                        ),
                      )
                    : Markdown(
                        data: _adviceMarkdown ?? '',
                        padding: const EdgeInsets.all(24),
                        styleSheet: MarkdownStyleSheet(
                          h1: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.black87),
                          h2: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.blueAccent),
                          h3: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
                          p: const TextStyle(fontSize: 16, height: 1.5, color: Colors.black87),
                          listBullet: const TextStyle(fontSize: 16, color: Colors.blue),
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}
