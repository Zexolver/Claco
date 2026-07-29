import 'package:flutter/material.dart';

import '../../models/agent_status.dart';

/// Small AppBar indicator for whether the model is Loaded/Unloaded (spec
/// 4.4 "App Bar: Displays model loading status").
class ModelStatusChip extends StatelessWidget {
  const ModelStatusChip({super.key, required this.state});

  final ModelLoadState state;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (state) {
      ModelLoadState.unloaded => ('Unloaded', Colors.grey),
      ModelLoadState.loading => ('Loading…', Colors.amber),
      ModelLoadState.loaded => ('Loaded', Colors.greenAccent),
      ModelLoadState.error => ('Error', Colors.redAccent),
    };

    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: Chip(
        avatar: Icon(Icons.memory, size: 16, color: color),
        label: Text(label, style: const TextStyle(fontSize: 12)),
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}
