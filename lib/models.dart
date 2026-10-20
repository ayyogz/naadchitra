// Instrument catalogue — Classical 5
// Natya Shastra families: tata (strings), avanaddha (membranes), sushira (wind)

class Instrument {
  final String id;
  final String name;
  final String family;
  final String familyEn;
  final String region;
  final String period;
  final String description;
  final String audioFile;

  const Instrument({
    required this.id,
    required this.name,
    required this.family,
    required this.familyEn,
    required this.region,
    required this.period,
    required this.description,
    required this.audioFile,
  });
}

const List<Instrument> instruments = [
  Instrument(
    id: 'sitar',
    name: 'Sitar',
    family: 'तत (Tata)',
    familyEn: 'Tata — Chordophone (Strings)',
    region: 'North India',
    period: 'Medieval — ~15th century CE',
    description:
        'Plucked string instrument of Hindustani classical music with a long neck, '
        'gourd resonating chamber, and 18-21 strings including sympathetic strings.',
    audioFile: 'sitar.mp3',
  ),
  Instrument(
    id: 'tabla',
    name: 'Tabla',
    family: 'अवनद्ध (Avanaddha)',
    familyEn: 'Avanaddha — Membranophone (Drums)',
    region: 'North India',
    period: 'Medieval — ~18th century CE',
    description:
        'Pair of hand drums — smaller dayan (treble) and larger bayan (bass). '
        'Principal percussion of Hindustani classical music.',
    audioFile: 'tabla.mp3',
  ),
  Instrument(
    id: 'veena',
    name: 'Saraswati Veena',
    family: 'तत (Tata)',
    familyEn: 'Tata — Chordophone (Strings)',
    region: 'Pan-Indian / South India',
    period: 'Ancient — Natya Shastra era',
    description:
        'Plucked string instrument of Carnatic music with 24 frets, 4 main strings, '
        'and 3 drone strings. Sacred instrument associated with Goddess Saraswati.',
    audioFile: 'veena.mp3',
  ),
  Instrument(
    id: 'mridangam',
    name: 'Mridangam',
    family: 'अवनद्ध (Avanaddha)',
    familyEn: 'Avanaddha — Membranophone (Drums)',
    region: 'South India',
    period: 'Ancient — Natya Shastra era',
    description:
        'Double-ended drum carved from jackwood, the primary rhythmic accompaniment '
        'in Carnatic music. Among the oldest percussion instruments in India.',
    audioFile: 'mridangam.mp3',
  ),
  Instrument(
    id: 'bansuri',
    name: 'Bansuri',
    family: 'सुषिर (Sushira)',
    familyEn: 'Sushira — Aerophone (Wind)',
    region: 'Pan-Indian',
    period: 'Ancient — Vedic literature',
    description:
        'Bamboo flute with 6-7 holes, central to Hindustani classical music. '
        'Closely associated with Lord Krishna, depicted in temple carvings across India.',
    audioFile: 'bansuri.mp3',
  ),
];

Instrument? findInstrumentById(String id) {
  try {
    return instruments.firstWhere((i) => i.id == id);
  } catch (_) {
    return null;
  }
}
