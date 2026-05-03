import 'package:flutter/material.dart';

import '../../../shared/themes/app_theme.dart';
import '../models/country.dart';

Future<Country?> showCountryPicker(BuildContext context) {
  return showModalBottomSheet<Country>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => const _CountryPickerSheet(),
  );
}

class _CountryPickerSheet extends StatefulWidget {
  const _CountryPickerSheet();

  @override
  State<_CountryPickerSheet> createState() => _CountryPickerSheetState();
}

class _CountryPickerSheetState extends State<_CountryPickerSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final filtered = _query.isEmpty
        ? kCountries
        : kCountries.where((c) {
            final q = _query.toLowerCase();
            return c.name.toLowerCase().contains(q) ||
                c.code.toLowerCase().contains(q);
          }).toList();

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.75,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          children: [
            Text(
              '选择国家/地区',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: colors.text1,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              decoration: const InputDecoration(
                hintText: '搜索国家或区号',
                prefixIcon: Icon(Icons.search, size: 20),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: filtered.length,
                itemBuilder: (ctx, i) {
                  final c = filtered[i];
                  return ListTile(
                    onTap: () => Navigator.of(ctx).pop(c),
                    leading: Text(c.flag, style: const TextStyle(fontSize: 24)),
                    title: Text(c.name,
                        style: TextStyle(color: colors.text1, fontSize: 14)),
                    trailing: Text(
                      c.code.isEmpty ? '—' : c.code,
                      style: TextStyle(color: colors.text2, fontSize: 13),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
