import 'package:flutter/material.dart';

import '../../app/theme.dart';
import 'portal_navigation.dart';

class PortalSidebar extends StatelessWidget {
  const PortalSidebar({
    required this.selectedDestination,
    required this.onSelectDestination,
    required this.onLogout,
    this.width = 250,
    super.key,
  });

  final PortalDestination selectedDestination;
  final ValueChanged<PortalDestination> onSelectDestination;
  final VoidCallback onLogout;
  final double width;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = theme.extension<PatientPortalTextColors>()!.secondary;

    return Container(
      width: width,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(right: BorderSide(color: theme.colorScheme.outline)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _BrandHeader(secondary: secondary),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 28, 14, 10),
            child: Text(
              'PATIENT PORTAL',
              style: theme.textTheme.labelSmall?.copyWith(
                color: secondary,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: PortalDestination.values
                  .map(
                    (destination) => _NavigationItem(
                      destination: destination,
                      selected: destination == selectedDestination,
                      onTap: () => onSelectDestination(destination),
                    ),
                  )
                  .toList(),
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: theme.colorScheme.outline)),
            ),
            child: _NavigationItem(
              destination: null,
              label: 'Logout',
              icon: Icons.logout,
              selected: false,
              onTap: onLogout,
            ),
          ),
        ],
      ),
    );
  }
}

class _BrandHeader extends StatelessWidget {
  const _BrandHeader({required this.secondary});

  final Color secondary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    return Container(
      height: 72,
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.colorScheme.outline)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: primary.withValues(alpha: 0.22)),
              ),
              child: Icon(Icons.visibility_outlined, color: primary, size: 23),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Gonzales Vision Clinic',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Patient Portal',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: secondary,
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavigationItem extends StatelessWidget {
  const _NavigationItem({
    required this.destination,
    required this.selected,
    required this.onTap,
    this.label,
    this.icon,
  });

  final PortalDestination? destination;
  final bool selected;
  final VoidCallback onTap;
  final String? label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final selectedBackground = theme.brightness == Brightness.light
        ? const Color(0xFFEFF6FF)
        : const Color(0xFF122C58);
    final selectedBorder = theme.brightness == Brightness.light
        ? const Color(0xFFBFDBFE)
        : const Color(0xFF244F91);
    final textColor = selected
        ? primary
        : theme.colorScheme.onSurface.withValues(alpha: 0.8);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Material(
        color: selected ? selectedBackground : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            constraints: const BoxConstraints(minHeight: 46),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: selected ? Border.all(color: selectedBorder) : null,
            ),
            child: Row(
              children: [
                Icon(icon ?? destination!.icon, size: 20, color: textColor),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label ?? destination!.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: textColor,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
