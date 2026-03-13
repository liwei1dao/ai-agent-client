import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/service_library_provider.dart';
import '../widgets/service_card.dart';
import '../widgets/add_service_modal.dart';

class ServicesScreen extends ConsumerWidget {
  const ServicesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final services = ref.watch(serviceLibraryProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Services')),
      body: services.isEmpty
          ? const Center(child: Text('还没有配置服务，点击 + 添加'))
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: services.length,
              itemBuilder: (_, i) => ServiceCard(service: services[i]),
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          builder: (_) => const AddServiceModal(),
        ),
        child: const Icon(Icons.add),
      ),
    );
  }
}
