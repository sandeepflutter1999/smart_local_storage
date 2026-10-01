import 'package:flutter/material.dart';
import 'package:smart_local_cache/smart_local_cache.dart';

/// STEP-BY-STEP: using SmartBox with plain Maps.
///
///  1. Open a box:            final box = await SmartLocalStorage.box('todos');
///  2. Write:                 box.add / box.put / box.update / box.delete
///  3. Read once:             box.get(id) / box.getAll() / box.query(...)
///  4. Read + auto-refresh:   StreamBuilder(stream: box.watchAll(), ...)
///
/// Notice there is NO setState after add/delete - the StreamBuilder
/// rebuilds by itself whenever the box changes.
class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  late final Future<SmartBox> _boxFuture = SmartLocalStorage.box('todos');
  final _text = TextEditingController();
  String _search = '';

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _add(SmartBox box) async {
    final title = _text.text.trim();
    if (title.isEmpty) return;
    _text.clear();
    // 'id' is created for you and returned. Do NOT put 'id' in the map.
    await box.add({'title': title, 'done': false, 'createdAt': DateTime.now().toIso8601String()});
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<SmartBox>(
      future: _boxFuture,
      builder: (context, snap) {
        final box = snap.data;
        if (box == null) return const Center(child: CircularProgressIndicator());
        return Scaffold(
          appBar: AppBar(title: const Text('Todos (plain Maps)')),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _text,
                      decoration: const InputDecoration(labelText: 'New todo', border: OutlineInputBorder()),
                      onSubmitted: (_) => _add(box),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(onPressed: () => _add(box), child: const Text('Add')),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: TextField(
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search (uses where:)'),
                  onChanged: (v) => setState(() => _search = v.toLowerCase()),
                ),
              ),
              Expanded(
                // watchAll = current list now + a new list after every change.
                // where / sort / limit work exactly like box.query().
                child: StreamBuilder<List<Map<String, dynamic>>>(
                  stream: box.watchAll(
                    where: (r) => (r['title'] as String).toLowerCase().contains(_search),
                    sort: (a, b) => (b['createdAt'] as String).compareTo(a['createdAt'] as String),
                  ),
                  builder: (context, snapshot) {
                    final todos = snapshot.data ?? const [];
                    if (todos.isEmpty) return const Center(child: Text('Nothing here yet'));
                    return ListView.builder(
                      itemCount: todos.length,
                      itemBuilder: (context, i) {
                        final t = todos[i];
                        final id = t['id'] as String; // id is always included
                        return CheckboxListTile(
                          value: t['done'] as bool,
                          title: Text(t['title'] as String),
                          subtitle: Text('id: $id'),
                          // update() merges - only send what changed.
                          onChanged: (v) => box.update(id, {'done': v}),
                          secondary: IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => box.delete(id),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
