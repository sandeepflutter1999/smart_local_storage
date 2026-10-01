import 'package:flutter/material.dart';
import 'package:smart_local_cache/smart_local_cache.dart';

import '../note.dart';

/// STEP-BY-STEP: using your own model class with SmartModelBox<T>.
///
///  1. Give your class toMap() and a fromMap() (see note.dart). No codegen.
///  2. Wrap a box:   SmartModelBox<Note>(box, toMap: ..., fromMap: ...)
///  3. Use it with Note objects instead of Maps. watchAll() gives List<Note>.
class TypedPage extends StatefulWidget {
  const TypedPage({super.key});

  @override
  State<TypedPage> createState() => _TypedPageState();
}

class _TypedPageState extends State<TypedPage> {
  late final Future<SmartModelBox<Note>> _notesFuture = _open();

  Future<SmartModelBox<Note>> _open() async {
    final box = await SmartLocalStorage.box('notes');
    return SmartModelBox<Note>(box, toMap: (n) => n.toMap(), fromMap: Note.fromMap);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<SmartModelBox<Note>>(
      future: _notesFuture,
      builder: (context, snap) {
        final notes = snap.data;
        if (notes == null) return const Center(child: CircularProgressIndicator());
        return Scaffold(
          appBar: AppBar(title: const Text('Notes (typed)')),
          floatingActionButton: FloatingActionButton(
            onPressed: () => notes.add(Note(
              title: 'Note ${notes.length + 1}',
              detail: 'Created at ${DateTime.now()}',
            )),
            child: const Icon(Icons.add),
          ),
          body: StreamBuilder<List<Note>>(
            stream: notes.watchAll(),
            builder: (context, snapshot) {
              final list = snapshot.data ?? const <Note>[];
              if (list.isEmpty) return const Center(child: Text('Tap + to add a note'));
              return ListView.builder(
                itemCount: list.length,
                itemBuilder: (context, i) {
                  final note = list[i];
                  return ListTile(
                    title: Text(note.title),
                    subtitle: Text(note.detail),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => _NoteDetail(notes: notes, id: note.id!)),
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => notes.delete(note.id!),
                    ),
                  );
                },
              );
            },
          ),
        );
      },
    );
  }
}

/// watch(id) follows ONE record - edit it from anywhere and this screen updates.
class _NoteDetail extends StatelessWidget {
  const _NoteDetail({required this.notes, required this.id});

  final SmartModelBox<Note> notes;
  final String id;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Note?>(
      stream: notes.watch(id),
      builder: (context, snap) {
        final note = snap.data;
        return Scaffold(
          appBar: AppBar(title: Text('Note $id')),
          body: note == null
              ? const Center(child: Text('Deleted or loading'))
              : Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(note.title, style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 8),
                      Text(note.detail),
                      const SizedBox(height: 16),
                      FilledButton(
                        // update() with a model merges all its fields.
                        onPressed: () => notes.update(id, note.copyWith(detail: 'Edited ${DateTime.now()}')),
                        child: const Text('Edit detail'),
                      ),
                    ],
                  ),
                ),
        );
      },
    );
  }
}
