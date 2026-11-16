import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../branding.dart';
import 'finance_models.dart';

class HouseholdScreen extends StatefulWidget {
  final String userId;

  const HouseholdScreen({super.key, required this.userId});

  @override
  State<HouseholdScreen> createState() => _HouseholdScreenState();
}

class _HouseholdScreenState extends State<HouseholdScreen> {
  final client = Supabase.instance.client;
  late Future<List<Map<String, dynamic>>> householdsFuture;

  @override
  void initState() {
    super.initState();
    householdsFuture = _loadHouseholds();
  }

  Future<List<Map<String, dynamic>>> _loadHouseholds() async {
    final memberships = await client
        .from('household_memberships')
        .select('household_id, role')
        .eq('user_id', widget.userId)
        .eq('status', 'active');
    if (memberships.isEmpty) return [];
    final ids = memberships
        .map((row) => row['household_id'] as String)
        .toList();
    final households = await client
        .from('households')
        .select('id, name, owner_id, created_at')
        .inFilter('id', ids)
        .order('created_at');
    return households.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  void _reload() => setState(() => householdsFuture = _loadHouseholds());

  Future<void> _createHousehold() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create a household'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 50,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Household name',
            hintText: 'e.g. Home',
          ),
          onSubmitted: (value) => Navigator.pop(context, value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty || !mounted) return;
    try {
      await client.from('households').insert({
        'owner_id': widget.userId,
        'name': name,
      });
      _reload();
    } catch (error) {
      _showError(
        'Could not create this household. Apply the MADS database migration first.',
      );
    }
  }

  Future<void> _acceptInvite() async {
    final controller = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Join a household'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Invite code'),
          textCapitalization: TextCapitalization.none,
          onSubmitted: (value) => Navigator.pop(context, value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Join'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (code == null || code.isEmpty || !mounted) return;
    try {
      await client.rpc('accept_household_invite', params: {'p_code': code});
      _reload();
    } catch (_) {
      _showError(
        'This code could not be used. It may have expired or already been accepted.',
      );
    }
  }

  Future<void> _createInvite(String householdId) async {
    try {
      final code = await client.rpc(
        'create_household_invite',
        params: {'p_household_id': householdId},
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Household invite'),
          content: SelectableText(
            '$code\n\nShare this one use code with the person you want to invite. It expires in 7 days.',
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: '$code'));
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('Copy code'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Done'),
            ),
          ],
        ),
      );
    } catch (_) {
      _showError('Only a household owner can create an invite.');
    }
  }

  Future<void> _addSharedExpense(String householdId) async {
    final descriptionController = TextEditingController();
    final amountController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final entry = await showDialog<(String, int)?>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add a shared expense'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: descriptionController,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'What was it for?',
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Enter a description.'
                    : null,
              ),
              TextFormField(
                controller: amountController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Amount',
                  prefixText: '₹ ',
                ),
                validator: (value) {
                  final amount = value == null ? null : Money.parseMinor(value);
                  return amount == null || amount <= 0
                      ? 'Enter an amount above ₹0.'
                      : null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (!formKey.currentState!.validate()) return;
              Navigator.pop(context, (
                descriptionController.text.trim(),
                Money.parseMinor(amountController.text)!,
              ));
            },
            child: const Text('Save expense'),
          ),
        ],
      ),
    );
    descriptionController.dispose();
    amountController.dispose();
    if (entry == null || !mounted) return;
    try {
      await client.from('household_shared_expenses').insert({
        'household_id': householdId,
        'created_by': widget.userId,
        'description': entry.$1,
        'amount_minor': entry.$2,
        'currency': 'INR',
      });
      _reload();
    } catch (_) {
      _showError('Could not save the shared expense.');
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Household')),
    body: FutureBuilder<List<Map<String, dynamic>>>(
      future: householdsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _errorState();
        }
        final households = snapshot.data ?? const [];
        return ListView(
          physics: const ClampingScrollPhysics(),
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'Share the expenses you choose.',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: madsSoftWhite,
              ),
            ),
            const SizedBox(height: 7),
            const Text(
              'Household members only see shared household expenses here. Your personal accounts and boards stay private.',
              style: TextStyle(color: madsMutedText, height: 1.45),
            ),
            const SizedBox(height: 17),
            Wrap(
              spacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: _createHousehold,
                  icon: const Icon(Icons.add_home_outlined),
                  label: const Text('Create household'),
                ),
                OutlinedButton.icon(
                  onPressed: _acceptInvite,
                  icon: const Icon(Icons.group_add_outlined),
                  label: const Text('Join with code'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (households.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 35),
                child: Center(
                  child: Text(
                    'You are not in a household yet.',
                    style: TextStyle(color: madsMutedText),
                  ),
                ),
              )
            else
              ...households.map(_householdCard),
          ],
        );
      },
    ),
  );

  Widget _householdCard(
    Map<String, dynamic> household,
  ) => FutureBuilder<List<Map<String, dynamic>>>(
    future: client
        .from('household_shared_expenses')
        .select('description, amount_minor, currency, occurred_at, created_by')
        .eq('household_id', household['id'])
        .order('occurred_at', ascending: false),
    builder: (context, snapshot) {
      final rows = snapshot.data ?? const [];
      return Card(
        margin: const EdgeInsets.only(bottom: 18),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.home_work_outlined, color: madsBlue),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      '${household['name']}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Create invite code',
                    onPressed: () => _createInvite('${household['id']}'),
                    icon: const Icon(Icons.person_add_alt_1_outlined),
                  ),
                ],
              ),
              const Text(
                'Shared expenses',
                style: TextStyle(color: madsMutedText),
              ),
              const SizedBox(height: 5),
              if (snapshot.connectionState == ConnectionState.waiting)
                const LinearProgressIndicator()
              else if (rows.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'No shared expenses yet.',
                    style: TextStyle(color: madsMutedText),
                  ),
                )
              else
                ...rows.take(8).map((row) {
                  final amount = row['amount_minor'] as num? ?? 0;
                  final date =
                      DateTime.tryParse('${row['occurred_at']}') ??
                      DateTime.now();
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text('${row['description']}'),
                    subtitle: Text('${date.day}/${date.month}/${date.year}'),
                    trailing: Text(
                      Money.format(
                        amount.toInt(),
                        currency: row['currency'] as String? ?? 'INR',
                      ),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  );
                }),
              const SizedBox(height: 5),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _addSharedExpense('${household['id']}'),
                  icon: const Icon(Icons.add),
                  label: const Text('Add shared expense'),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );

  Widget _errorState() => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_outlined, color: madsFaintText, size: 38),
          const SizedBox(height: 12),
          const Text(
            'Household sharing needs the MADS database migration and an internet connection.',
            textAlign: TextAlign.center,
            style: TextStyle(color: madsMutedText, height: 1.45),
          ),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: _reload, child: const Text('Try again')),
        ],
      ),
    ),
  );
}
