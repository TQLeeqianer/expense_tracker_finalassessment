import 'dart:io';
import 'package:flutter/material.dart';
import 'dart:typed_data';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:file_saver/file_saver.dart';
import '../models/transaction_model.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../providers/settings_provider.dart';
import '../utils/currency_helper.dart';
import '../widgets/manage_currencies_sheet.dart';
import '../widgets/manage_wallets_sheet.dart';
import '../widgets/manage_tags_sheet.dart';
import '../widgets/manage_goal_sheet.dart';
import '../widgets/manage_categories_sheet.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context, listen: false);
    final settingsProvider = Provider.of<SettingsProvider>(context);
    final email = authService.user?.email ?? 'developer@expensix.com';
    final Color blueColor = Theme.of(context).colorScheme.primary;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9), // Light off-white grey
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            backgroundColor: blueColor,
            expandedHeight: 280,
            pinned: true,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
              onPressed: () => Navigator.of(context).pop(),
            ),
            title: const Text('Profile', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
            centerTitle: true,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: BoxDecoration(
                  color: blueColor,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(height: 60), // Offset for AppBar
                    Stack(
                      alignment: Alignment.bottomRight,
                      children: [
                        GestureDetector(
                          onTap: () async {
                            final picker = ImagePicker();
                            // Use lower quality to ensure small base64 size for local storage cache
                            final pickedFile = await picker.pickImage(source: ImageSource.gallery, imageQuality: 40);
                            if (pickedFile != null) {
                              final bytes = await pickedFile.readAsBytes();
                              final base64String = base64Encode(bytes);
                              settingsProvider.setProfileImage(base64String);
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white.withOpacity(0.3), width: 3),
                            ),
                            child: CircleAvatar(
                              radius: 45,
                              backgroundColor: Colors.white24,
                              backgroundImage: settingsProvider.profileImagePath != null && settingsProvider.profileImagePath!.length > 500
                                  ? MemoryImage(base64Decode(settingsProvider.profileImagePath!))
                                  : null,
                              child: (settingsProvider.profileImagePath == null || settingsProvider.profileImagePath!.length <= 500)
                                  ? const Icon(Icons.person, size: 50, color: Colors.white)
                                  : null,
                            ),
                          ),
                        ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: const BoxDecoration(
                              color: Colors.blueAccent,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.edit, color: Colors.white, size: 14),
                          ),
                        )
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      authService.user?.displayName ?? 'Developer',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      email,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          
          SliverToBoxAdapter(
            child: Transform.translate(
              offset: const Offset(0, -30),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Preferences Group
                    _buildSectionTitle('Preferences'),
                    _buildCardGroup([
                      _buildListItem(
                        icon: Icons.currency_exchange,
                        iconColor: Colors.purple,
                        title: 'Default Currency',
                        trailingText: settingsProvider.baseCurrency,
                        onTap: () {
                          _showCurrencyPicker(context, settingsProvider);
                        },
                      ),
                      _buildDivider(),
                      _buildListItem(
                        icon: Icons.settings_suggest,
                        iconColor: Colors.indigo,
                        title: 'Manage Currencies',
                        trailingText: '${settingsProvider.activeCurrencies.length} Active',
                        onTap: () {
                          showModalBottomSheet(
                            context: context,
                            isScrollControlled: true,
                            backgroundColor: Colors.transparent,
                            builder: (ctx) => const ManageCurrenciesSheet(),
                          );
                        },
                      ),
                      _buildDivider(),
                      _buildListItem(
                        icon: Icons.account_balance_wallet,
                        iconColor: Colors.teal,
                        title: 'Manage Wallets',
                        trailingText: '${settingsProvider.wallets.length} Wallets',
                        onTap: () {
                          showModalBottomSheet(
                            context: context,
                            isScrollControlled: true,
                            backgroundColor: Colors.transparent,
                            builder: (ctx) => const ManageWalletsSheet(),
                          );
                        },
                      ),
                      _buildDivider(),
                      _buildListItem(
                        icon: Icons.pie_chart,
                        iconColor: Colors.deepPurple,
                        title: 'Manage Categories',
                        trailingText: '${settingsProvider.expenseCategories.length + settingsProvider.incomeCategories.length} Categories',
                        onTap: () {
                          showModalBottomSheet(
                            context: context,
                            isScrollControlled: true,
                            backgroundColor: Colors.transparent,
                            builder: (ctx) => const ManageCategoriesSheet(),
                          );
                        },
                      ),
                      _buildDivider(),
                      _buildListItem(
                        icon: Icons.label,
                        iconColor: Colors.orange,
                        title: 'Manage Tags',
                        trailingText: '${settingsProvider.activeTags.length} Tags',
                        onTap: () {
                          showModalBottomSheet(
                            context: context,
                            isScrollControlled: true,
                            backgroundColor: Colors.transparent,
                            builder: (ctx) => const ManageTagsSheet(),
                          );
                        },
                      ),
                      _buildDivider(),
                      _buildListItem(
                        icon: Icons.flag,
                        iconColor: Colors.purple,
                        title: 'Set Monthly Goal',
                        trailingText: settingsProvider.monthlySavingsGoal > 0 
                            ? '${settingsProvider.baseCurrency} ${settingsProvider.monthlySavingsGoal.toStringAsFixed(0)}'
                            : 'Not Set',
                        onTap: () {
                          showModalBottomSheet(
                            context: context,
                            isScrollControlled: true,
                            backgroundColor: Colors.transparent,
                            builder: (ctx) => const ManageGoalSheet(),
                          );
                        },
                      ),
                      _buildDivider(),
                      _buildListItem(
                        icon: Icons.remove_red_eye,
                        iconColor: Colors.blue,
                        title: 'Privacy Mode',
                        trailingText: settingsProvider.isPrivacyModeEnabled ? 'Enabled' : 'Disabled',
                        onTap: () {
                          if (!settingsProvider.isPrivacyModeEnabled) {
                            showDialog(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                title: const Column(
                                  children: [
                                    Icon(Icons.privacy_tip, size: 48, color: Colors.blueAccent),
                                    SizedBox(height: 12),
                                    Text(
                                      'Enable Privacy Mode',
                                      style: TextStyle(fontWeight: FontWeight.bold),
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                ),
                                content: const Text(
                                  'Your balances and amounts will be hidden. Go back to Profile to disable.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: Colors.grey),
                                ),
                                actionsAlignment: MainAxisAlignment.center,
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx),
                                    child: const Text('Cancel'),
                                  ),
                                  ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.blueAccent,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                    ),
                                    onPressed: () {
                                      Navigator.pop(ctx);
                                      settingsProvider.togglePrivacyMode();
                                    },
                                    child: const Text('Enable'),
                                  ),
                                ],
                              ),
                            );
                          } else {
                            settingsProvider.togglePrivacyMode();
                          }
                        },
                      ),
                    ]),
                    
                    const SizedBox(height: 24),
                    
                    // Data Group
                    _buildSectionTitle('Data Management'),
                    _buildCardGroup([
                      _buildListItem(
                        icon: Icons.download,
                        iconColor: Colors.teal,
                        title: 'Export Statements',
                        trailingText: 'CSV',
                        onTap: () async {
                          showDialog(
                            context: context,
                            builder: (ctx) => const Center(child: CircularProgressIndicator()),
                          );

                          try {
                            final txList = await FirestoreService().getTransactionsStream().first;
                            String csvData = "Date,Type,Category,Amount,Currency,Account,Tags,Notes\n";
                            String dateStrForFilename = DateFormat('yyyyMMdd').format(DateTime.now());
                            
                            for (var t in txList) {
                               String dateStr = DateFormat('yyyy-MM-dd HH:mm').format(t.date);
                               String typeStr = t.type.name;
                               String categoryStr = t.category;
                               String amountStr = t.amount.toStringAsFixed(2);
                               String currencyStr = t.currency;
                               String accountStr = t.type == TransactionType.transfer 
                                  ? "${t.fromAccount} -> ${t.toAccount}" 
                                  : (t.fromAccount ?? t.toAccount ?? '');
                               String tagsStr = "\"${t.tags.join(', ')}\"";
                               String titleStr = "\"${t.title.replaceAll('"', '""')}\""; // escape quotes in CSV
                               csvData += "$dateStr,$typeStr,$categoryStr,$amountStr,$currencyStr,$accountStr,$tagsStr,$titleStr\n";
                            }
                            
                            if (context.mounted) Navigator.pop(context); // Close loading
                            
                            // Universally save the file (Works on Web, Windows, Android, iOS)
                            Uint8List bytes = Uint8List.fromList(csvData.codeUnits);
                            String filePath = await FileSaver.instance.saveFile(
                              name: 'Expensix_Transactions_$dateStrForFilename',
                              bytes: bytes,
                              fileExtension: 'csv',
                              mimeType: MimeType.csv,
                            );
                            
                            if (context.mounted) {
                               ScaffoldMessenger.of(context).showSnackBar(
                                 SnackBar(content: Text('File saved successfully!'), backgroundColor: Colors.green),
                               );
                            }
                          } catch (e) {
                            if (context.mounted) Navigator.pop(context);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export failed: $e')));
                            }
                          }
                        },
                      ),
                    ]),

                    const SizedBox(height: 24),
                    
                    // System Group
                    _buildSectionTitle('System'),
                    _buildCardGroup([
                      _buildListItem(
                        icon: Icons.info_outline,
                        iconColor: Colors.grey.shade600,
                        title: 'About Expensix',
                        trailingText: 'v1.0.0',
                        onTap: () {
                          showDialog(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                              title: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(color: Colors.blueAccent.withOpacity(0.1), shape: BoxShape.circle),
                                    child: const Icon(Icons.rocket_launch, color: Colors.blueAccent),
                                  ),
                                  const SizedBox(width: 16),
                                  const Text('Expensix v1.0', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                                ],
                              ),
                              content: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Thank you for using Expensix! This is the official milestone release.\n\nComing Soon in v2.0:', 
                                    style: TextStyle(color: Colors.black87, height: 1.5)
                                  ),
                                  const SizedBox(height: 16),
                                  Row(children: [Icon(Icons.auto_graph, size: 20, color: Colors.purple), const SizedBox(width: 12), const Text('Predictive AI Budgeting', style: TextStyle(fontWeight: FontWeight.w500))]),
                                  const SizedBox(height: 12),
                                  Row(children: [Icon(Icons.group, size: 20, color: Colors.orange), const SizedBox(width: 12), const Text('Shared Family Vaults', style: TextStyle(fontWeight: FontWeight.w500))]),
                                  const SizedBox(height: 12),
                                  Row(children: [Icon(Icons.receipt_long, size: 20, color: Colors.teal), const SizedBox(width: 12), const Text('Smart Receipt OCR Parser', style: TextStyle(fontWeight: FontWeight.w500))]),
                                ],
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx),
                                  child: const Text('Stay Tuned!', style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold)),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                      _buildDivider(),
                      _buildListItem(
                        icon: Icons.logout,
                        iconColor: Colors.redAccent,
                        isDanger: true,
                        title: 'Log Out',
                        trailingText: '',
                        onTap: () async {
                          Navigator.of(context).pop(); // pop profile
                          await authService.signOut();
                        },
                      ),
                    ]),
                    
                    const SizedBox(height: 60),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 8.0, bottom: 12.0),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: Colors.grey.shade500,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildCardGroup(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: children,
      ),
    );
  }

  Widget _buildDivider() {
    return Divider(
      height: 1,
      thickness: 1,
      color: Colors.grey.shade100,
      indent: 64, // Align with text start
      endIndent: 24,
    );
  }

  Widget _buildListItem({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String trailingText,
    required VoidCallback onTap,
    bool isDanger = false,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconColor, size: 22),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: isDanger ? Colors.red : Colors.black87,
                  ),
                ),
              ),
              if (trailingText.isNotEmpty) ...[
                Text(
                  trailingText,
                  style: TextStyle(
                    color: Colors.grey.shade500,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Icon(Icons.chevron_right, color: Colors.grey.shade300, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  void _showCurrencyPicker(BuildContext context, SettingsProvider provider) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        height: MediaQuery.of(context).size.height * 0.6,
        padding: const EdgeInsets.only(top: 24, left: 24, right: 24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Select Default Currency', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Expanded(
              child: ListView(
                children: provider.activeCurrencies.map((c) => ListTile(
                  title: Text(c, style: const TextStyle(fontWeight: FontWeight.w600)),
                  trailing: provider.baseCurrency == c ? const Icon(Icons.check, color: Colors.blue) : null,
                  onTap: () {
                    provider.setBaseCurrency(c);
                    Navigator.pop(ctx);
                  },
                )).toList(),
              ),
            ),
          ],
        ),
      )
    );
  }

  void _showComingSoonDialog(BuildContext context, String title, String message, IconData icon) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Column(
          children: [
            Icon(icon, size: 48, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 16),
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.center),
          ],
        ),
        content: Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
            ),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Got it!'),
          ),
        ],
      ),
    );
  }
}
