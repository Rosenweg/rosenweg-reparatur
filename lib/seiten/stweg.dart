// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:flutter/material.dart';

import '../daten.dart';
import '../reparatur_api.dart';
import 'haupt.dart';

/// "Meine STWEG": alle Meldungen der STWEG mit Stand, ohne Namen der
/// meldenden Person (GET /api/reklamationen/uebersicht?stweg=N). Ersetzt
/// stweg1…7/pages/reklamationen.html und meg/pages/reklamationen.html.
/// Meldungen ohne STWEG (uebergreifend) stehen immer mit dabei.
class StwegSeite extends StatefulWidget {
  const StwegSeite({super.key, required this.api, required this.rechte});
  final ReparaturApi api;
  final ReparaturRechte? rechte;

  @override
  State<StwegSeite> createState() => _StwegSeiteState();
}

class _StwegSeiteState extends State<StwegSeite> {
  late int? _stweg = _vorschlag();

  int? _vorschlag() {
    final r = widget.rechte;
    if (r == null || r.uebersichtStwegs.isEmpty) return null;
    final e = r.eigeneStwegs.where(r.uebersichtStwegs.contains);
    return e.isNotEmpty ? e.first : r.uebersichtStwegs.first;
  }

  @override
  Widget build(BuildContext context) {
    final waehlbar = widget.rechte?.uebersichtStwegs ?? const <int>[];
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (waehlbar.length > 1)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final n in waehlbar)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(stwegText(n)),
                        selected: _stweg == n,
                        onSelected: (_) => setState(() => _stweg = n),
                      ),
                    ),
                ],
              ),
            ),
          ),
        Expanded(
          child: Laden<List<Meldung>>(
            key: ValueKey(_stweg),
            laden: () => widget.api.uebersicht(stweg: _stweg),
            fertig: (context, liste, neu) {
              final aktiv = [
                for (final m in liste)
                  if (!m.status.abgeschlossen) m,
              ];
              final fertig = [
                for (final m in liste)
                  if (m.status.abgeschlossen) m,
              ];
              return RefreshIndicator(
                onRefresh: neu,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                  children: [
                    Text(
                      'Meldungen ${_stweg == null ? 'deiner STWEG' : 'der ${stwegText(_stweg)}'} und übergreifende, mit Stand. '
                      'Aus Datenschutzgründen ohne Namen.',
                      style: t.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    Text('In Arbeit (${aktiv.length})', style: t.titleMedium),
                    const SizedBox(height: 4),
                    if (aktiv.isEmpty)
                      const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('Zurzeit nichts offen.')),
                    for (final m in aktiv) MeldungKachel(m: m, zeigeStweg: true),
                    const SizedBox(height: 16),
                    Text('Abgeschlossen (${fertig.length})', style: t.titleMedium),
                    const SizedBox(height: 4),
                    if (fertig.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text('Noch nichts abgeschlossen.'),
                      ),
                    for (final m in fertig) MeldungKachel(m: m, zeigeStweg: true),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
