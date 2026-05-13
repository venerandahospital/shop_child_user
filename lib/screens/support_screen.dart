import 'package:flutter/material.dart';

class SupportScreen extends StatefulWidget {
  const SupportScreen({super.key});

  @override
  State<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends State<SupportScreen> {
  final _searchController = TextEditingController();
  final _expandedFaqIndex = ValueNotifier<int?>(null);

  static const _faqItems = [
    (
      q: 'What is inventory management?',
      a: 'Inventory management is the process of ordering, storing, and using a company\'s inventory: raw materials, components, and finished products. It involves tracking stock levels, reorder points, and ensuring products are available when customers need them.',
    ),
    (
      q: 'Why is inventory management important?',
      a: 'Effective inventory management is crucial for businesses to maintain optimal levels of stock to meet customer demand while minimizing carrying costs and the risk of stockouts. It helps in reducing excess inventory, improving cash flow, and enhancing overall operational efficiency.',
    ),
    (
      q: 'What are the different types of inventory?',
      a: 'Common types include raw materials, work-in-progress (WIP), finished goods, and MRO (maintenance, repair, operations) inventory. Each type serves a different stage of the production and sales cycle.',
    ),
    (
      q: 'How can I calculate inventory turnover?',
      a: 'Inventory turnover is calculated by dividing the cost of goods sold (COGS) by the average inventory during a specific period. The formula is: Inventory Turnover = COGS / Average Inventory. A higher turnover ratio generally indicates better inventory management.',
    ),
  ];

  @override
  void dispose() {
    _searchController.dispose();
    _expandedFaqIndex.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: _buildHeader(context),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: _buildSearchBar(context),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                _buildCardsGrid(context, theme),
                const SizedBox(height: 24),
                _buildOngoingDiscussion(theme),
                const SizedBox(height: 24),
                _buildFaqSection(theme),
                const SizedBox(height: 32),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF0D9488),
            Color(0xFF14B8A6),
            Color(0xFF5EEAD4),
            Color(0xFF99F6E4),
          ],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Material(
                    color: Colors.white.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(10),
                    child: InkWell(
                      onTap: () => Navigator.of(context).pop(),
                      borderRadius: BorderRadius.circular(10),
                      child: const Padding(
                        padding: EdgeInsets.all(12),
                        child: Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Support',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const Text(
                'Need Some',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Text(
                'help with front? Discussion',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: _buildHeaderIllustration(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderIllustration() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Icon(Icons.cloud_outlined, color: Colors.white.withValues(alpha: 0.8), size: 28),
          const Positioned(right: 8, top: 4, child: Icon(Icons.cloud_outlined, color: Colors.white54, size: 20)),
          const Positioned(
            right: 24,
            top: 12,
            child: Icon(Icons.headset_mic, color: Colors.white, size: 48),
          ),
          Positioned(
            right: 32,
            top: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 8, offset: const Offset(0, 2))],
              ),
              child: const Text('...', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            ),
          ),
          Positioned(
            right: 0,
            bottom: 8,
            child: Icon(Icons.chat_bubble_outline, color: Colors.white.withValues(alpha: 0.9), size: 24),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Material(
        elevation: 4,
        shadowColor: Colors.black26,
        borderRadius: BorderRadius.circular(16),
        child: TextField(
          controller: _searchController,
          decoration: InputDecoration(
            hintText: 'Search Something',
            hintStyle: TextStyle(color: Colors.grey.shade500),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            suffixIcon: Container(
              margin: const EdgeInsets.all(6),
              decoration: const BoxDecoration(
                color: Color(0xFF0D9488),
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: const Icon(Icons.search, color: Colors.white),
                onPressed: () {},
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCardsGrid(BuildContext context, ThemeData theme) {
    final cards = [
      (icon: Icons.lightbulb_outline, title: 'Get Started', desc: 'Unlocking a world of possibilities', color: const Color(0xFFFFC107)),
      (icon: Icons.person_outline, title: 'Accounts', desc: 'Manage your account efficiently', color: const Color(0xFF0D9488)),
      (icon: Icons.card_membership, title: 'Subscription', desc: 'Subscribe now to unlock premium', color: const Color(0xFF8B5CF6)),
      (icon: Icons.help_outline, title: 'Help', desc: 'Our dedicated support team is here to help', color: const Color(0xFF14B8A6)),
    ];

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 0.92,
      children: cards.map((c) => _buildSupportCard(theme, c.icon, c.title, c.desc, c.color)).toList(),
    );
  }

  Widget _buildSupportCard(ThemeData theme, IconData icon, String title, String desc, Color color) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      elevation: 2,
      shadowColor: Colors.black12,
      child: InkWell(
        onTap: () {},
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 26),
              ),
              const Spacer(),
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                desc,
                style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade700),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOngoingDiscussion(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Ongoing Discussion',
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          elevation: 2,
          shadowColor: Colors.black12,
          child: InkWell(
            onTap: () {},
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'The Future of Energy?',
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'This ongoing discussion explores the integration of renewable energy sources into daily business operations and how small businesses can reduce costs.',
                    style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade700),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFaqSection(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Frequently Asked Questions',
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        ValueListenableBuilder<int?>(
          valueListenable: _expandedFaqIndex,
          builder: (context, expandedIndex, _) {
            return Column(
              children: List.generate(_faqItems.length, (i) {
                final item = _faqItems[i];
                final isExpanded = expandedIndex == i;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Material(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      onTap: () {
                        _expandedFaqIndex.value = isExpanded ? null : i;
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    item.q,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                Icon(
                                  isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                                  color: Colors.grey.shade700,
                                ),
                              ],
                            ),
                            if (isExpanded) ...[
                              const SizedBox(height: 10),
                              Text(
                                item.a,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: Colors.grey.shade700,
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }),
            );
          },
        ),
      ],
    );
  }
}
