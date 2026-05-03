import 'package:flutter/material.dart';

import '../../../shared/themes/app_theme.dart';

Future<String?> showEditTitleSheet(
  BuildContext context, {
  required String initial,
  String title = '修改会议标题',
  String hint = '请输入标题',
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => _EditTitleSheet(
      initial: initial,
      title: title,
      hint: hint,
    ),
  );
}

class _EditTitleSheet extends StatefulWidget {
  const _EditTitleSheet({
    required this.initial,
    required this.title,
    required this.hint,
  });
  final String initial;
  final String title;
  final String hint;

  @override
  State<_EditTitleSheet> createState() => _EditTitleSheetState();
}

class _EditTitleSheetState extends State<_EditTitleSheet> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initial);
    _ctrl.selection =
        TextSelection(baseOffset: 0, extentOffset: widget.initial.length);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    final colors = context.appColors;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + inset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.title,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: colors.text1,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _ctrl,
            autofocus: true,
            maxLength: 50,
            decoration: InputDecoration(
              hintText: widget.hint,
              counterText: '',
            ),
            onSubmitted: (v) => Navigator.pop(context, v.trim()),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () =>
                      Navigator.pop(context, _ctrl.text.trim()),
                  child: const Text('确定'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
