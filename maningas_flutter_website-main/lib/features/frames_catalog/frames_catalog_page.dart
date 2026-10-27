import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/responsive.dart';
import '../../app/theme.dart';
import '../../core/config/api_config.dart';
import '../../core/network/api_failure.dart';
import '../auth/application/patient_auth_scope.dart';
import 'catalog_frame.dart';
import 'frames_catalog_repository.dart';
import 'try_on_config.dart';

class FramesCatalogPage extends StatefulWidget {
  const FramesCatalogPage({super.key, this.onOpenTryOn});

  final ValueChanged<Uri>? onOpenTryOn;

  @override
  State<FramesCatalogPage> createState() => _FramesCatalogPageState();
}

class _FramesCatalogPageState extends State<FramesCatalogPage> {
  final _searchController = TextEditingController();
  String _sort = 'newest';
  String _availability = 'all';
  String _category = 'All';
  FramesCatalogRepository? _repository;
  List<CatalogFrame> _allFrames = const [];
  bool _isLoading = true;
  bool _hasError = false;
  bool _repositoryInitialized = false;
  bool _isFetching = false;
  String? _refreshError;
  Timer? _refreshTimer;

  List<String> get _categories {
    final categories =
        _allFrames
            .map((frame) => frame.category)
            .whereType<String>()
            .toSet()
            .toList()
          ..sort((a, b) => a.compareTo(b));
    return ['All', ...categories];
  }

  List<CatalogFrame> get _visibleFrames {
    final query = _searchController.text.trim().toLowerCase();
    final category = _category.toLowerCase();
    final frames = _allFrames.where((frame) {
      final matchesQuery =
          query.isEmpty ||
          frame.name.toLowerCase().contains(query) ||
          (frame.brand?.toLowerCase().contains(query) ?? false);
      final matchesCategory =
          _category == 'All' ||
          (frame.category?.toLowerCase().contains(category) ?? false);
      final matchesAvailability =
          _availability == 'all' ||
          switch (_availability) {
            'available' => frame.stockQuantity > 2,
            'low' => frame.stockQuantity > 0 && frame.stockQuantity <= 2,
            'out' => frame.stockQuantity <= 0,
            _ => true,
          };
      return matchesQuery && matchesCategory && matchesAvailability;
    }).toList();

    if (_sort != 'newest') {
      frames.sort((a, b) {
        return switch (_sort) {
          'name-asc' => a.name.compareTo(b.name),
          'name-desc' => b.name.compareTo(a.name),
          'price-low' => a.price.compareTo(b.price),
          'price-high' => b.price.compareTo(a.price),
          _ => b.frameId.compareTo(a.frameId),
        };
      });
    }
    return frames;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final repository = PatientAuthScope.framesCatalogOf(context);
    if (!_repositoryInitialized || !identical(repository, _repository)) {
      _repositoryInitialized = true;
      _repository = repository;
      _allFrames = const [];
      _isLoading = repository != null;
      _hasError = false;
      _refreshError = null;
      _refreshTimer?.cancel();
      if (repository != null) {
        _fetchFrames(repository);
        _refreshTimer = Timer.periodic(
          const Duration(seconds: 60),
          (_) => _refreshFrames(),
        );
      } else {
        _hasError = true;
      }
    }
  }

  Future<void> _loadFrames() async {
    setState(() {
      _isLoading = true;
      _hasError = false;
      _refreshError = null;
    });
    final repository = _repository;
    if (repository == null) {
      setState(() {
        _isLoading = false;
        _hasError = true;
      });
      return;
    }
    await _fetchFrames(repository);
  }

  Future<void> _fetchFrames(FramesCatalogRepository repository) async {
    if (_isFetching) return;
    _isFetching = true;
    try {
      final frames = await repository.getFrames();
      if (!mounted) return;
      setState(() {
        _allFrames = frames;
        _isLoading = false;
        _hasError = false;
        _refreshError = null;
      });
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _hasError = _allFrames.isEmpty;
        _refreshError = _allFrames.isEmpty ? null : failure.message;
      });
    } finally {
      _isFetching = false;
    }
  }

  void _refreshFrames() {
    final repository = _repository;
    if (repository != null && !_isFetching) {
      unawaited(_fetchFrames(repository));
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final compact = width <= PatientPortalBreakpoints.mobileNavigation;
    final horizontalPadding = width <= 360
        ? 8.0
        : width <= PatientPortalBreakpoints.mobile
        ? 12.0
        : compact
        ? 22.0
        : 18.0;
    final frames = _visibleFrames;

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        horizontalPadding,
        compact ? 22 : 32,
        horizontalPadding,
        compact ? 28 : 40,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: PatientPortalBreakpoints.contentMaxWidth,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _PageHeader(compact: compact),
              const SizedBox(height: 24),
              _FiltersCard(
                searchController: _searchController,
                sort: _sort,
                availability: _availability,
                categories: _categories,
                selectedCategory: _category,
                onSearchChanged: (_) => setState(() {}),
                onSortChanged: (value) {
                  if (value != null) setState(() => _sort = value);
                },
                onAvailabilityChanged: (value) {
                  if (value != null) setState(() => _availability = value);
                },
                onCategoryChanged: (value) => setState(() => _category = value),
              ),
              const SizedBox(height: 20),
              if (_refreshError != null) ...[
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    'Could not refresh the catalog. Showing the last loaded '
                    'results. $_refreshError',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onErrorContainer,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              _CollectionCard(
                frames: frames,
                isLoading: _isLoading,
                hasError: _hasError,
                isEmptyCatalog: _allFrames.isEmpty && !_hasError,
                onOpenDetails: _showDetails,
                onTryOn: _launchTryOn,
                onRetry: _loadFrames,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDetails(CatalogFrame frame) {
    showDialog<void>(
      context: context,
      builder: (context) => _FrameDetailsDialog(
        frame: frame,
        onTryOn: () {
          Navigator.of(context).pop();
          _launchTryOn(frame);
        },
      ),
    );
  }

  void _launchTryOn(CatalogFrame frame) {
    if (!frame.hasTryOnModel) {
      _showTryOnMessage(
        'This frame does not have a usable 3D model for Try-On.',
      );
      return;
    }

    final uri = TryOnConfig.buildLaunchUri(
      frameId: frame.frameId,
      apiBaseUri: ApiConfig.baseUri,
      websiteOrigin: Uri.base.origin,
    );
    if (uri == null) {
      _showTryOnMessage(
        '3D Try-On is unavailable for this catalog environment. Use the '
        'clinic live catalog to continue.',
      );
      return;
    }

    final openTryOn = widget.onOpenTryOn;
    if (openTryOn == null) {
      _showTryOnMessage('Try-On is unavailable from this screen.');
      return;
    }
    openTryOn(uri);
  }

  void _showTryOnMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _PageHeader extends StatelessWidget {
  const _PageHeader({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = theme.extension<PatientPortalTextColors>()!.secondary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.visibility_outlined,
              size: 16,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Text(
              'GONZALES VISION CLINIC',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.primary,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Frames Catalog',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontSize: compact ? 28 : 36,
            height: 1.2,
            letterSpacing: -1.2,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Explore our collection of eyewear frames, view frame details, and '
          'preview selected frames with 3D Try-On.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: secondary,
            fontSize: compact ? 13 : 14,
            height: 1.6,
          ),
        ),
      ],
    );
  }
}

class _FiltersCard extends StatelessWidget {
  const _FiltersCard({
    required this.searchController,
    required this.sort,
    required this.availability,
    required this.categories,
    required this.selectedCategory,
    required this.onSearchChanged,
    required this.onSortChanged,
    required this.onAvailabilityChanged,
    required this.onCategoryChanged,
  });

  final TextEditingController searchController;
  final String sort;
  final String availability;
  final List<String> categories;
  final String selectedCategory;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String?> onSortChanged;
  final ValueChanged<String?> onAvailabilityChanged;
  final ValueChanged<String> onCategoryChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = theme.extension<PatientPortalTextColors>()!.secondary;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Find a Frame',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              "Search and filter the clinic's available eyewear collection.",
              style: theme.textTheme.bodySmall?.copyWith(color: secondary),
            ),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth < 650) {
                  return Column(
                    children: [
                      _buildSearch(context),
                      const SizedBox(height: 10),
                      _buildSelects(context, stacked: true),
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(flex: 3, child: _buildSearch(context)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildDropdown(
                        context,
                        value: sort,
                        label: 'Sort frames',
                        items: const [
                          ('newest', 'Newest'),
                          ('name-asc', 'Name A–Z'),
                          ('name-desc', 'Name Z–A'),
                          ('price-low', 'Price: Low to High'),
                          ('price-high', 'Price: High to Low'),
                        ],
                        onChanged: onSortChanged,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildDropdown(
                        context,
                        value: availability,
                        label: 'Filter availability',
                        items: const [
                          ('all', 'All Availability'),
                          ('available', 'Available'),
                          ('low', 'Low Stock'),
                          ('out', 'Out of Stock'),
                        ],
                        onChanged: onAvailabilityChanged,
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 14),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (var index = 0; index < categories.length; index++) ...[
                    if (index > 0) const SizedBox(width: 8),
                    _CategoryPill(
                      label: categories[index] == 'All'
                          ? 'All Frames'
                          : categories[index],
                      selected: categories[index] == selectedCategory,
                      onTap: () => onCategoryChanged(categories[index]),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearch(BuildContext context) {
    return TextField(
      controller: searchController,
      onChanged: onSearchChanged,
      decoration: const InputDecoration(
        prefixIcon: Icon(Icons.search),
        hintText: 'Search by frame name or brand...',
        isDense: true,
      ),
    );
  }

  Widget _buildSelects(BuildContext context, {required bool stacked}) {
    final sortField = _buildDropdown(
      context,
      value: sort,
      label: 'Sort frames',
      items: const [
        ('newest', 'Newest'),
        ('name-asc', 'Name A–Z'),
        ('name-desc', 'Name Z–A'),
        ('price-low', 'Price: Low to High'),
        ('price-high', 'Price: High to Low'),
      ],
      onChanged: onSortChanged,
    );
    final availabilityField = _buildDropdown(
      context,
      value: availability,
      label: 'Filter availability',
      items: const [
        ('all', 'All Availability'),
        ('available', 'Available'),
        ('low', 'Low Stock'),
        ('out', 'Out of Stock'),
      ],
      onChanged: onAvailabilityChanged,
    );
    if (stacked) {
      return Column(
        children: [sortField, const SizedBox(height: 10), availabilityField],
      );
    }
    return Row(
      children: [
        Expanded(child: sortField),
        const SizedBox(width: 10),
        Expanded(child: availabilityField),
      ],
    );
  }

  Widget _buildDropdown(
    BuildContext context, {
    required String value,
    required String label,
    required List<(String, String)> items,
    required ValueChanged<String?> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 14,
        ),
      ),
      items: [
        for (final (itemValue, itemLabel) in items)
          DropdownMenuItem(value: itemValue, child: Text(itemLabel)),
      ],
      onChanged: onChanged,
    );
  }
}

class _CategoryPill extends StatelessWidget {
  const _CategoryPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 36),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        backgroundColor: selected
            ? theme.colorScheme.primary
            : theme.colorScheme.surface,
        foregroundColor: selected
            ? Colors.white
            : theme.extension<PatientPortalTextColors>()!.secondary,
        side: BorderSide(
          color: selected
              ? theme.colorScheme.primary
              : theme.colorScheme.outline,
        ),
        shape: const StadiumBorder(),
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
      ),
      child: Text(label),
    );
  }
}

class _CollectionCard extends StatelessWidget {
  const _CollectionCard({
    required this.frames,
    required this.isLoading,
    required this.hasError,
    required this.isEmptyCatalog,
    required this.onOpenDetails,
    required this.onTryOn,
    required this.onRetry,
  });

  final List<CatalogFrame> frames;
  final bool isLoading;
  final bool hasError;
  final bool isEmptyCatalog;
  final ValueChanged<CatalogFrame> onOpenDetails;
  final ValueChanged<CatalogFrame> onTryOn;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = theme.extension<PatientPortalTextColors>()!.secondary;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Our Collection',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Choose a frame to view more information or try it on.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: secondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                _FrameCount(count: frames.length),
              ],
            ),
          ),
          Divider(height: 1, color: theme.colorScheme.outline),
          if (isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 56),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (hasError)
            _CatalogErrorState(onRetry: onRetry)
          else if (frames.isEmpty)
            _EmptyState(isEmptyCatalog: isEmptyCatalog)
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 950
                    ? 3
                    : constraints.maxWidth >= 560
                    ? 2
                    : 1;
                final spacing = constraints.maxWidth < 560 ? 12.0 : 18.0;
                return GridView.builder(
                  padding: const EdgeInsets.all(20),
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: frames.length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    crossAxisSpacing: spacing,
                    mainAxisSpacing: spacing,
                    mainAxisExtent: 438,
                  ),
                  itemBuilder: (context, index) => _FrameCard(
                    frame: frames[index],
                    onOpenDetails: () => onOpenDetails(frames[index]),
                    onTryOn: () => onTryOn(frames[index]),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

class _FrameCard extends StatelessWidget {
  const _FrameCard({
    required this.frame,
    required this.onOpenDetails,
    required this.onTryOn,
  });

  final CatalogFrame frame;
  final VoidCallback onOpenDetails;
  final VoidCallback onTryOn;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = theme.extension<PatientPortalTextColors>()!.secondary;
    final stockColor = switch (frame.availability) {
      'Available' => const Color(0xFF15803D),
      'Low Stock' => const Color(0xFFB45309),
      _ => const Color(0xFFB91C1C),
    };
    final stockBackground = switch (frame.availability) {
      'Available' => const Color(0xFFDCFCE7),
      'Low Stock' => const Color(0xFFFEF3C7),
      _ => const Color(0xFFFEE2E2),
    };

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 5,
            child: Container(
              decoration: BoxDecoration(
                color: theme.brightness == Brightness.dark
                    ? const Color(0xFF18243A)
                    : const Color(0xFFF4F7FC),
                border: Border(
                  bottom: BorderSide(color: theme.colorScheme.outline),
                ),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _FrameImage(frame: frame),
                  if (frame.imageUrl == null)
                    Positioned(
                      left: 10,
                      top: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surface.withValues(
                            alpha: .9,
                          ),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'IMAGE UNAVAILABLE',
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            color: secondary,
                          ),
                        ),
                      ),
                    ),
                  if (frame.hasTryOnModel)
                    Positioned(right: 10, top: 10, child: _ThreeDBadge()),
                ],
              ),
            ),
          ),
          Expanded(
            flex: 6,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    frame.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    _frameSubtitle(frame),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: secondary,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: stockBackground,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      frame.availability,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: stockColor,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    _formatPrice(frame.price),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: onOpenDetails,
                          child: const Text('View Details'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton(
                          onPressed: frame.hasTryOnModel ? onTryOn : null,
                          child: Text(
                            frame.hasTryOnModel
                                ? 'Try On 3D'
                                : frame.isTryOnConverted
                                ? '3D Model Unavailable'
                                : frame.conversionStatus?.toLowerCase() ==
                                      'processing'
                                ? 'Converting...'
                                : '2D Only',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FrameDetailsDialog extends StatelessWidget {
  const _FrameDetailsDialog({required this.frame, required this.onTryOn});

  final CatalogFrame frame;
  final VoidCallback onTryOn;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = theme.extension<PatientPortalTextColors>()!.secondary;
    return AlertDialog(
      contentPadding: EdgeInsets.zero,
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 650),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                height: 210,
                color: theme.brightness == Brightness.dark
                    ? const Color(0xFF18243A)
                    : const Color(0xFFF4F7FC),
                child: _FrameImage(frame: frame),
              ),
              Padding(
                padding: const EdgeInsets.all(22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'FRAME DETAILS',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w800,
                        letterSpacing: .7,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      frame.name,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      _frameSubtitle(frame),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: secondary,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      _formatPrice(frame.price),
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(frame.description ?? '—'),
                    const SizedBox(height: 18),
                    Text(
                      'Availability: ${frame.availability}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 20),
                    if (frame.isTryOnConverted)
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: frame.hasTryOnModel ? onTryOn : null,
                          icon: const Icon(Icons.view_in_ar_outlined),
                          label: Text(
                            frame.hasTryOnModel
                                ? 'Try On 3D'
                                : '3D Model Unavailable',
                          ),
                        ),
                      ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Close'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FrameCount extends StatelessWidget {
  const _FrameCount({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: theme.brightness == Brightness.dark
            ? const Color(0xFF18243A)
            : const Color(0xFFF4F7FC),
        border: Border.all(color: theme.colorScheme.outline),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        count == 1 ? '1 frame' : '$count frames',
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.extension<PatientPortalTextColors>()!.secondary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.isEmptyCatalog});

  final bool isEmptyCatalog;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = theme.extension<PatientPortalTextColors>()!.secondary;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 56),
      child: Column(
        children: [
          Icon(Icons.search, size: 28, color: theme.colorScheme.primary),
          const SizedBox(height: 12),
          Text(
            isEmptyCatalog
                ? 'No frames currently available'
                : 'No frames found',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            isEmptyCatalog
                ? 'Please check back later.'
                : 'Try changing your search or filter options.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(color: secondary),
          ),
        ],
      ),
    );
  }
}

class _CatalogErrorState extends StatelessWidget {
  const _CatalogErrorState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = theme.extension<PatientPortalTextColors>()!.secondary;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
      child: Column(
        children: [
          Icon(
            Icons.wifi_off_outlined,
            size: 28,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: 12),
          Text(
            'Unable to load frames',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Please check your connection and try again.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(color: secondary),
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

class _FrameImage extends StatelessWidget {
  const _FrameImage({required this.frame});

  final CatalogFrame frame;

  @override
  Widget build(BuildContext context) {
    final imageUrl = frame.imageUrl;
    if (imageUrl == null) {
      return const Center(
        child: CustomPaint(
          size: Size(170, 90),
          painter: _GlassesPlaceholderPainter(),
        ),
      );
    }

    return Image.network(
      imageUrl.toString(),
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CustomPaint(
              size: Size(170, 90),
              painter: _GlassesPlaceholderPainter(),
            ),
            const SizedBox(height: 8),
            Text(
              'Image unavailable',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
      ),
    );
  }
}

String _frameSubtitle(CatalogFrame frame) {
  final values = [
    frame.brand,
    frame.category,
  ].whereType<String>().where((value) => value.isNotEmpty).toList();
  return values.isEmpty ? '—' : values.join(' • ');
}

class _ThreeDBadge extends StatelessWidget {
  const _ThreeDBadge();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: theme.colorScheme.outline),
      ),
      child: Text(
        '3D',
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.primary,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _GlassesPlaceholderPainter extends CustomPainter {
  const _GlassesPlaceholderPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final framePaint = Paint()
      ..color = const Color(0xFF2563EB)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final lensWidth = size.width * .38;
    final lensHeight = size.height * .55;
    final top = size.height * .23;
    final leftRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(size.width * .06, top, lensWidth, lensHeight),
      const Radius.circular(18),
    );
    final rightRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(size.width * .56, top, lensWidth, lensHeight),
      const Radius.circular(18),
    );
    canvas.drawRRect(leftRect, framePaint);
    canvas.drawRRect(rightRect, framePaint);
    final bridge = Path()
      ..moveTo(size.width * .44, size.height * .45)
      ..quadraticBezierTo(
        size.width * .5,
        size.height * .37,
        size.width * .56,
        size.height * .45,
      );
    canvas.drawPath(bridge, framePaint);
    canvas.drawLine(
      Offset(0, size.height * .36),
      Offset(size.width * .06, size.height * .4),
      framePaint,
    );
    canvas.drawLine(
      Offset(size.width * .94, size.height * .4),
      Offset(size.width, size.height * .36),
      framePaint,
    );
  }

  @override
  bool shouldRepaint(covariant _GlassesPlaceholderPainter oldDelegate) => false;
}

String _formatPrice(double price) {
  final parts = price.toStringAsFixed(2).split('.');
  final whole = parts.first.replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ',',
  );
  return '₱$whole.${parts.last}';
}
