import 'package:flutter/material.dart';
import '../models/user.dart';
import '../services/api/api_client.dart';
import '../services/api/api_config.dart';

class SendFeedbackView extends StatefulWidget {
  final UserModel user;
  final bool isEmbedded;
  final VoidCallback? onSuccess;

  const SendFeedbackView({
    super.key,
    required this.user,
    this.isEmbedded = false,
    this.onSuccess,
  });

  @override
  State<SendFeedbackView> createState() => _SendFeedbackViewState();
}

class _SendFeedbackViewState extends State<SendFeedbackView> {
  final TextEditingController _messageController = TextEditingController();
  
  // Reactive getter ensures we always use latest local URL
  ApiClient get _apiClient => ApiClient(baseUrl: ApiConfig.baseUrl);
  
  String _selectedCategory = 'Suggestion';
  bool _isSending = false;

  final List<String> _categories = [
    'Bug',
    'Suggestion',
    'Complaint',
    'Question',
    'Other'
  ];

  Future<void> _submitFeedback() async {
    final message = _messageController.text.trim();
    if (message.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your feedback message.')),
      );
      return;
    }

    setState(() => _isSending = true);

    try {
      await _apiClient.post(
        '/export/feedback',
        body: {
          'category': _selectedCategory,
          'message': message,
        },
        authorized: true,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Thank you! Your feedback has been sent directly to the developers.'),
            backgroundColor: Colors.green,
          ),
        );
        
        if (widget.onSuccess != null) {
          widget.onSuccess!();
        } else {
          Navigator.pop(context);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send feedback: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final content = SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'We value your input',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Help us improve STOX. Your feedback is sent directly to our team.',
            style: TextStyle(
              fontSize: 14,
              color: colorScheme.onSurface.withOpacity(0.7),
            ),
          ),
          const SizedBox(height: 32),
          
          Text(
            'CATEGORY',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
              color: colorScheme.primary,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: _categories.map((cat) {
              final isSelected = _selectedCategory == cat;
              return ChoiceChip(
                label: Text(cat),
                selected: isSelected,
                onSelected: (selected) {
                  if (selected) setState(() => _selectedCategory = cat);
                },
                selectedColor: colorScheme.primaryContainer,
                labelStyle: TextStyle(
                  color: isSelected ? colorScheme.primary : colorScheme.onSurface,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              );
            }).toList(),
          ),
          
          const SizedBox(height: 32),
          
          Text(
            'YOUR FEEDBACK',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
              color: colorScheme.primary,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _messageController,
            maxLines: 8,
            decoration: InputDecoration(
              hintText: 'Tell us what is on your mind...',
              hintStyle: TextStyle(color: colorScheme.onSurface.withOpacity(0.4)),
              filled: true,
              fillColor: colorScheme.surfaceContainerHighest.withOpacity(0.3),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: colorScheme.outline),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: colorScheme.outlineVariant),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: colorScheme.primary, width: 2),
              ),
            ),
          ),
          
          const SizedBox(height: 40),
          
          SizedBox(
            width: double.infinity,
            height: 50,
            child: FilledButton.icon(
              onPressed: _isSending ? null : _submitFeedback,
              icon: _isSending 
                ? const SizedBox(
                    width: 18, 
                    height: 18, 
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)
                  )
                : const Icon(Icons.send_rounded),
              label: Text(_isSending ? 'Sending...' : 'Submit Feedback'),
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );

    if (widget.isEmbedded) return content;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Send Feedback'),
        elevation: 0,
      ),
      body: content,
    );
  }
}
