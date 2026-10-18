import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/chat_model.dart';
import '../providers/chat_ai_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/responsive_layout.dart';
import '../widgets/app_sidebar.dart';
import 'dashboard_screen.dart';
import 'usaha_screen.dart';
import 'produk_screen.dart';
import 'transaksi_screen.dart';
import 'portofolio_screen.dart';
import 'forecast_screen.dart';
import 'laporan_screen.dart';

class ChatAiScreen extends StatefulWidget {
  const ChatAiScreen({super.key});

  @override
  State<ChatAiScreen> createState() => _ChatAiScreenState();
}

class _ChatAiScreenState extends State<ChatAiScreen> {
  final TextEditingController _inputCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();

  void _kirimPesan() {
    final text = _inputCtrl.text;
    if (text.trim().isEmpty) return;
    _inputCtrl.clear();
    context.read<ChatAiProvider>().sendMessage(text);
    _scrollToBottom();
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 150), () {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = ResponsiveLayout.isMobile(context);
    final provider = context.watch<ChatAiProvider>();

    return Scaffold(
      appBar: isMobile
          ? AppBar(
              backgroundColor: AppTheme.surfaceWhite,
              elevation: 0,
              title: const Text('Asisten AI Finansial', style: TextStyle(color: AppTheme.primaryBlue, fontWeight: FontWeight.bold)),
            )
          : null,
      drawer: isMobile ? _buildNavigationDrawer(context) : null,
      body: Row(
        children: [
          if (!isMobile) const AppSidebar(activeRoute: 'chat_ai'),
          Expanded(
            child: SafeArea(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 32, vertical: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!isMobile) _buildDesktopHeader(),
                    if (!isMobile) const SizedBox(height: 16),
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceWhite,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppTheme.cardBorder),
                        ),
                        child: Column(
                          children: [
                            Expanded(
                              child: ListView.separated(
                                controller: _scrollCtrl,
                                padding: const EdgeInsets.all(20),
                                itemCount: provider.messages.length,
                                separatorBuilder: (_, __) => const SizedBox(height: 16),
                                itemBuilder: (context, index) {
                                  final msg = provider.messages[index];
                                  return _buildMessageBubble(msg);
                                },
                              ),
                            ),
                            if (provider.isTyping)
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                                child: Row(
                                  children: const [
                                    SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryBlue),
                                    ),
                                    SizedBox(width: 8),
                                    Text('AI sedang menganalisis data portofolio...', style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                                  ],
                                ),
                              ),
                            const Divider(height: 1, color: AppTheme.cardBorder),
                            _buildInputBar(),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: isMobile ? _buildMobileBottomBar(context) : null,
    );
  }

  Widget _buildDesktopHeader() {
    final sisaKuota = context.watch<ChatAiProvider>().sisaKuotaAi;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: AppTheme.lightBlueBg, borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.auto_awesome_rounded, color: AppTheme.primaryBlue, size: 24),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text('Konsultasi & Insight AI BI', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppTheme.textPrimary)),
                Text('Tanyakan apa saja seputar data keuangan, alokasi BCG, dan performa cabang.', style: TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
              ],
            ),
          ],
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: AppTheme.lightGreenBg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFA7F3D0)),
          ),
          child: Row(
            children: [
              const Icon(Icons.bolt_rounded, size: 18, color: AppTheme.accentGreen),
              const SizedBox(width: 6),
              Text(
                'Sisa Kuota AI: $sisaKuota Tanya',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.accentGreen),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMessageBubble(ChatMessageModel msg) {
    return Align(
      alignment: msg.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: Column(
          crossAxisAlignment: msg.isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: msg.isUser ? AppTheme.primaryBlue : AppTheme.lightBlueBg,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(msg.isUser ? 16 : 4),
                  bottomRight: Radius.circular(msg.isUser ? 4 : 16),
                ),
              ),
              child: Text(
                msg.content,
                style: TextStyle(
                  color: msg.isUser ? Colors.white : AppTheme.textPrimary,
                  fontSize: 14,
                  height: 1.45,
                ),
              ),
            ),
            if (msg.suggestions != null && msg.suggestions!.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: msg.suggestions!.map((sug) {
                  return ActionChip(
                    label: Text(sug, style: const TextStyle(fontSize: 12, color: AppTheme.primaryBlue)),
                    backgroundColor: AppTheme.surfaceWhite,
                    side: const BorderSide(color: AppTheme.cardBorder),
                    onPressed: () {
                      _inputCtrl.text = sug;
                      _kirimPesan();
                    },
                  );
                }).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInputBar() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _inputCtrl,
              onSubmitted: (_) => _kirimPesan(),
              decoration: InputDecoration(
                hintText: 'Tanyakan sesuatu (contoh: Bagaimana tren laba bulan ini?)...',
                hintStyle: const TextStyle(fontSize: 13, color: AppTheme.textMuted),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.send_rounded, color: AppTheme.primaryBlue),
            onPressed: _kirimPesan,
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopSidebar(BuildContext context) {
    return Container(
      width: 250,
      decoration: const BoxDecoration(color: AppTheme.surfaceWhite, border: Border(right: BorderSide(color: AppTheme.cardBorder))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 28),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: const [
                Icon(Icons.hub_rounded, color: AppTheme.primaryBlue, size: 28),
                SizedBox(width: 12),
                Text('MultiUsaha', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppTheme.primaryBlue)),
              ],
            ),
          ),
          const SizedBox(height: 36),
          _buildSidebarItem(context, 'Dashboard', Icons.dashboard_rounded, false, () {
            Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const DashboardScreen()));
          }),
          _buildSidebarItem(context, 'Unit Usaha', Icons.storefront_rounded, false, () {
            Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const UsahaScreen()));
          }),
          _buildSidebarItem(context, 'Inventaris', Icons.inventory_2_rounded, false, () {
            Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const ProdukScreen()));
          }),
          _buildSidebarItem(context, 'Transaksi', Icons.receipt_long_rounded, false, () {
            Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const TransaksiScreen()));
          }),
          _buildSidebarItem(context, 'Laporan Keuangan', Icons.assessment_rounded, false, () {
            Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LaporanScreen()));
          }),
          _buildSidebarItem(context, 'Portofolio BCG', Icons.pie_chart_rounded, false, () {
            Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const PortofolioScreen()));
          }),
          _buildSidebarItem(context, 'Forecasting', Icons.trending_up_rounded, false, () {
            Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const ForecastScreen()));
          }),
          _buildSidebarItem(context, 'Asisten AI', Icons.smart_toy_rounded, true, () {}),
        ],
      ),
    );
  }

  Widget _buildSidebarItem(BuildContext context, String label, IconData icon, bool isSelected, VoidCallback onTap) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(color: isSelected ? AppTheme.lightBlueBg : Colors.transparent, borderRadius: BorderRadius.circular(10)),
      child: ListTile(
        leading: Icon(icon, color: isSelected ? AppTheme.primaryBlue : AppTheme.textSecondary, size: 22),
        title: Text(label, style: TextStyle(color: isSelected ? AppTheme.primaryBlue : AppTheme.textSecondary, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal, fontSize: 14)),
        onTap: onTap,
      ),
    );
  }

  Widget _buildNavigationDrawer(BuildContext context) {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          const DrawerHeader(
            decoration: BoxDecoration(color: AppTheme.primaryBlue),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text('MultiUsaha', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                SizedBox(height: 4),
                Text('Sistem Manajemen Portofolio', style: TextStyle(color: Colors.white70, fontSize: 13)),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.dashboard_rounded),
            title: const Text('Dashboard'),
            onTap: () {
              Navigator.pop(context);
              Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const DashboardScreen()));
            },
          ),
          ListTile(
            leading: const Icon(Icons.assessment_rounded),
            title: const Text('Laporan Keuangan'),
            onTap: () {
              Navigator.pop(context);
              Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LaporanScreen()));
            },
          ),
          ListTile(
            leading: const Icon(Icons.smart_toy_rounded, color: AppTheme.primaryBlue),
            title: const Text('Asisten AI'),
            onTap: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileBottomBar(BuildContext context) {
    return BottomNavigationBar(
      currentIndex: 0,
      onTap: (index) {
        if (index == 0) {
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const DashboardScreen()));
        } else if (index == 1) {
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const UsahaScreen()));
        } else if (index == 2) {
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const TransaksiScreen()));
        } else if (index == 3) {
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LaporanScreen()));
        }
      },
      selectedItemColor: AppTheme.primaryBlue,
      unselectedItemColor: AppTheme.textSecondary,
      type: BottomNavigationBarType.fixed,
      backgroundColor: AppTheme.surfaceWhite,
      items: const [
        BottomNavigationBarItem(icon: Icon(Icons.dashboard_rounded), label: 'Dashboard'),
        BottomNavigationBarItem(icon: Icon(Icons.storefront_rounded), label: 'Usaha'),
        BottomNavigationBarItem(icon: Icon(Icons.receipt_long_rounded), label: 'Transaksi'),
        BottomNavigationBarItem(icon: Icon(Icons.assessment_rounded), label: 'Laporan'),
      ],
    );
  }
}
