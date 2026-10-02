import 'package:flutter/material.dart';
import 'package:smart_local_cache/smart_local_cache.dart';

import 'note.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'smart_local_storage demo (typed)',
      home: NotesListPage(),
    );
  }
}

class NotesListPage extends StatefulWidget {
  const NotesListPage({super.key});

  @override
  State<NotesListPage> createState() => _NotesListPageState();
}

class _NotesListPageState extends State<NotesListPage> {
  SmartModelBox<Note>? _notesBox;
  List<Note> _notes = [];

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final box = await SmartLocalStorage.box('notes');
    final notesBox = SmartModelBox<Note>(
      box,
      toMap: (note) => note.toMap(),
      fromMap: Note.fromMap,
    );
    setState(() {
      _notesBox = notesBox;
      _notes = notesBox.getAll();
    });
  }

  Future<void> _addNote() async {
    final notesBox = _notesBox;
    if (notesBox == null) return;
    await notesBox.add(Note(
      title: 'Note ${notesBox.length + 1}',
      detail: 'Created at ${DateTime.now()}',
    ));
    setState(() => _notes = notesBox.getAll());
  }

  Future<void> _deleteNote(String id) async {
    final notesBox = _notesBox;
    if (notesBox == null) return;
    await notesBox.delete(id);
    setState(() => _notes = notesBox.getAll());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Notes (typed SmartModelBox<Note>)')),
      floatingActionButton: FloatingActionButton(
        onPressed: _addNote,
        child: const Icon(Icons.add),
      ),
      body: _notes.isEmpty
          ? const Center(child: Text('No notes yet — tap + to add one'))
          : ListView.builder(
              itemCount: _notes.length,
              itemBuilder: (context, index) {
                final note = _notes[index];
                return ListTile(
                  title: Text(note.title),
                  subtitle: Text('id: ${note.id}'),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => NoteDetailPage(id: note.id!),
                    ),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _deleteNote(note.id!),
                  ),
                );
              },
            ),
    );
  }
}

class NoteDetailPage extends StatefulWidget {
  const NoteDetailPage({super.key, required this.id});

  final String id;

  @override
  State<NoteDetailPage> createState() => _NoteDetailPageState();
}

class _NoteDetailPageState extends State<NoteDetailPage> {
  Note? _note;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final box = await SmartLocalStorage.box('notes');
    final notesBox = SmartModelBox<Note>(
      box,
      toMap: (note) => note.toMap(),
      fromMap: Note.fromMap,
    );
    setState(() => _note = notesBox.get(widget.id));
  }

  @override
  Widget build(BuildContext context) {
    final note = _note;
    return Scaffold(
      appBar: AppBar(title: Text('Note ${widget.id}')),
      body: note == null
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(note.title, style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Text(note.detail),
                ],
              ),
            ),
    );
  }
}
