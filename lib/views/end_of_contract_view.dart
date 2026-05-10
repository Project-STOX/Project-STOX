import 'package:flutter/material.dart';
import '../services/api/export_api_service.dart';
import '../utils/backup_downloader.dart';

class EndOfContractView extends StatefulWidget {
  const EndOfContractView({super.key});

  @override
// Handles createState.
  State<EndOfContractView> createState() => _EndOfContractViewState();
}

class _EndOfContractViewState extends State<EndOfContractView> {
  int _currentStep = 0;
  final ExportApiService _exportService = ExportApiService();

  // Step 1 State
  final Map<String, bool> _categories = {
    'users': true,
    'roles_permissions': true,
    'products': true,
    'suppliers': true,
    'stock_receipts': true,
    'historical_sales': true,
    'demand_forecasts': true,
    'audit_log': true,
    'notifications': true,
  };
  final Set<String> _formats = {'csv'}; // 'csv', 'json', 'sql'

  // Step 2 State
  bool _confirmDeletion = false;
  bool _confirmDark = false;

  // Step 3 State
  final TextEditingController _feedbackController = TextEditingController();

  // Step 4 State
  final TextEditingController _passwordController = TextEditingController();
  bool _isExporting = false;
  String _statusMessage = '';

// Handles _submitClosure.
  void _submitClosure() async {
    final selectedCategories = _categories.entries
        .where((e) => e.value)
        .map((e) => e.key)
        .toList();

    if (selectedCategories.isEmpty) {
      _showError('Select at least one category to export.');
      return;
    }

    if (_formats.isEmpty) {
      _showError('Select at least one format to export.');
      return;
    }

    if (_passwordController.text.isEmpty) {
      _showError('Password is required.');
      return;
    }

    setState(() {
      _isExporting = true;
      _statusMessage = 'Verifying credentials & Compiling export...';
    });

    try {
      final bytes = await _exportService.endOfContract(
        categories: selectedCategories,
        password: _passwordController.text,
        formats: _formats.toList(),
        feedback: _feedbackController.text.trim(),
      );

      setState(() => _statusMessage = 'Data compiled. Prompting download...');

      final timestamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '')
          .split('.')[0];
      final filename = 'stox_final_export_$timestamp.zip';

      await downloadZip(bytes, filename);

      if (!mounted) return;

      setState(() => _statusMessage = 'Closure intent registered effectively.');

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          icon: const Icon(
            Icons.check_circle_outline,
            size: 64,
            color: Colors.green,
          ),
          title: const Text('Export Complete'),
          content: const Text(
            'Your final data export has been downloaded successfully.\\n'
            'The IT department has received your request. All active dashboards and privileges will be terminated shortly.\\n'
            'Thank you for using STOX.',
            textAlign: TextAlign.center,
          ),
          actions: [
            FilledButton(
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.of(context).pop(); // Return to settings
              },
              child: const Text('Acknowledge'),
            ),
          ],
        ),
      );
    } catch (e) {
      _showError(e.toString());
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      }
    }
  }

// Handles _showError.
  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Theme.of(context).colorScheme.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // Formatting helpers
  String _formatCategoryKey(String key) {
    return key
        .split('_')
        .map((w) => w[0].toUpperCase() + w.substring(1))
        .join(' ');
  }

  @override
// Handles build.
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Account Closure & Data Export'),
        backgroundColor: colorScheme.error.withOpacity(0.05),
      ),
      body: Stepper(
        type: StepperType.vertical,
        currentStep: _currentStep,
        onStepContinue: () {
          if (_currentStep == 1 && (!_confirmDeletion || !_confirmDark)) {
            _showError(
              'You must explicitly acknowledge the termination conditions.',
            );
            return;
          }
          if (_currentStep < 3) {
            setState(() => _currentStep += 1);
          } else {
            _submitClosure();
          }
        },
        onStepCancel: () {
          if (_currentStep > 0) {
            setState(() => _currentStep -= 1);
          } else {
            Navigator.of(context).pop();
          }
        },
        controlsBuilder: (context, details) {
          final isLastStep = _currentStep == 3;
          return Padding(
            padding: const EdgeInsets.only(top: 24.0),
            child: Row(
              children: [
                FilledButton.icon(
                  onPressed: _isExporting ? null : details.onStepContinue,
                  icon: _isExporting
// Handles SizedBox.
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          isLastStep
                              ? Icons.warning_rounded
                              : Icons.arrow_forward,
                        ),
                  label: Text(
                    isLastStep ? 'Permanently Terminate & Export' : 'Continue',
                  ),
                  style: isLastStep
                      ? FilledButton.styleFrom(
                          backgroundColor: colorScheme.error,
                        )
                      : null,
                ),
                if (!isLastStep) ...[
                  const SizedBox(width: 12),
                  TextButton(
                    onPressed: details.onStepCancel,
                    child: Text(_currentStep == 0 ? 'Cancel' : 'Back'),
                  ),
                ],
              ],
            ),
          );
        },
        steps: [
          Step(
            title: const Text('Data Scope & Format'),
            subtitle: const Text('Select what to extract'),
            isActive: _currentStep >= 0,
            state: _currentStep > 0 ? StepState.complete : StepState.indexed,
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Format Selection', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    FilterChip(
                      label: const Text('CSV Format'),
                      selected: _formats.contains('csv'),
                      onSelected: (val) {
                        setState(() {
                          if (val) {
                            _formats.add('csv');
                          } else {
                            _formats.remove('csv');
                          }
                        });
                      },
                      tooltip: 'Best for Excel and spreadsheet manipulation',
                    ),
                    FilterChip(
                      label: const Text('JSON Format'),
                      selected: _formats.contains('json'),
                      onSelected: (val) {
                        setState(() {
                          if (val) {
                            _formats.add('json');
                          } else {
                            _formats.remove('json');
                          }
                        });
                      },
                      tooltip: 'Best for programmable database restoration',
                    ),
                    FilterChip(
                      label: const Text('SQL Dump'),
                      selected: _formats.contains('sql'),
                      onSelected: (val) {
                        setState(() {
                          if (val) {
                            _formats.add('sql');
                          } else {
                            _formats.remove('sql');
                          }
                        });
                      },
                      tooltip:
                          'Standard INSERT INTO statements for database cloning',
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Text('Granular Inclusion', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: _categories.keys.map((key) {
                    return FilterChip(
                      label: Text(_formatCategoryKey(key)),
                      selected: _categories[key]!,
                      onSelected: (val) =>
                          setState(() => _categories[key] = val),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          Step(
            title: const Text('Compliance & Finality'),
            subtitle: const Text('Acknowledge timeline'),
            isActive: _currentStep >= 1,
            state: _currentStep > 1 ? StepState.complete : StepState.indexed,
            content: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  CheckboxListTile(
                    value: _confirmDeletion,
                    onChanged: (val) =>
                        setState(() => _confirmDeletion = val ?? false),
                    title: const Text(
                      'I understand my physical data is held securely as a backup for a maximum of 30 days before being permanently destroyed and irrecoverable from STOX systems.',
                    ),
                    controlAffinity: ListTileControlAffinity.leading,
                    activeColor: colorScheme.error,
                  ),
                  const Divider(),
                  CheckboxListTile(
                    value: _confirmDark,
                    onChanged: (val) =>
                        setState(() => _confirmDark = val ?? false),
                    title: const Text(
                      'I acknowledge that confirming this prompt will alert IT administrators to instantly revoke all personnel access to live STOX dashboards.',
                    ),
                    controlAffinity: ListTileControlAffinity.leading,
                    activeColor: colorScheme.error,
                  ),
                ],
              ),
            ),
          ),
          Step(
            title: const Text('Feedback Collection (Optional)'),
            subtitle: const Text('Why are you migrating?'),
            isActive: _currentStep >= 2,
            state: _currentStep > 2 ? StepState.complete : StepState.indexed,
            content: TextField(
              controller: _feedbackController,
              maxLines: 4,
              decoration: InputDecoration(
                hintText:
                    'e.g., Transitioning to an alternative ERP solution, lack of necessary metrics...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                filled: true,
              ),
            ),
          ),
          Step(
            title: const Text('Authorization & Unlock'),
            subtitle: const Text('Verify administrative authority'),
            isActive: _currentStep >= 3,
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'To finalize the closure sequence, please authenticate using your current Master Password.',
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: 400,
                  child: TextField(
                    controller: _passwordController,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: 'SME Owner Password',
                      prefixIcon: const Icon(Icons.lock),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      filled: true,
                    ),
                  ),
                ),
                if (_isExporting) ...[
                  const SizedBox(height: 24),
                  LinearProgressIndicator(color: colorScheme.error),
                  const SizedBox(height: 8),
                  Text(
                    _statusMessage,
                    style: TextStyle(color: colorScheme.error),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
