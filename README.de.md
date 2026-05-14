<div align="center">
  <img src="https://cliptate.github.io/assets/app-icon.png" width="120" alt="Cliptate App-Icon" />
  <h1>Cliptate</h1>
  <p><strong>Der KI-Arbeitsbereich auf dem Gerät für Mac-Audio- und Videoersteller</strong></p>

  <p>
    <a href="https://apps.apple.com/"><img alt="Im App Store laden" src="https://img.shields.io/badge/App%20Store-Laden-0066cc?logo=apple&logoColor=white&style=flat-square" /></a>
    <img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-000000?logo=apple&logoColor=white&style=flat-square" />
    <img alt="Apple Silicon" src="https://img.shields.io/badge/Apple%20Silicon-MLX-ff6900?style=flat-square" />
    <img alt="Swift" src="https://img.shields.io/badge/Swift-5.10-f05138?logo=swift&logoColor=white&style=flat-square" />
    <img alt="100% Lokal" src="https://img.shields.io/badge/Verarbeitung-100%25%20Lokal-22c55e?style=flat-square" />
  </p>

  <p>
    <a href="https://cliptate.github.io">Website</a> ·
    <a href="https://cliptate.github.io#features">Funktionen</a> ·
    <a href="https://cliptate.github.io#voice">Sprache & TTS</a> ·
    <a href="https://apps.apple.com/">Download</a>
  </p>

  <p>
    <a href="README.md">English</a> ·
    <a href="README.zh.md">中文</a> ·
    <a href="README.ja.md">日本語</a> ·
    <a href="README.ko.md">한국어</a> ·
    <a href="README.de.md">Deutsch</a>
  </p>
</div>

---

Cliptate ist eine native macOS-App, die die zeitaufwändigsten Schritte in der Audio- und Videoproduktion in einen durchgehenden, vollständig lokalen Workflow zusammenführt. Kein Cloud-Upload, keine API-Schlüssel, keine Netzwerkwartezeiten — alle Modelle laufen auf Ihrem Mac.

---

## Funktionen

### 🎙 Spracheingabe — Sprechen zum Tippen

Echtzeit-Sprach-zu-Text-Streaming, das wie eine Eingabemethode funktioniert. Mit einem globalen Tastaturkürzel aus jeder App aufrufbar — sprechen Sie einfach, und bearbeitbarer Text wird sofort erzeugt.

- Streaming-Transkription mit minimaler Latenz
- Automatische Mehrsprechererkennung und -beschriftung
- Benutzerdefiniertes Wörterbuch für domänenspezifische Genauigkeit
- Globales Tastaturkürzel zum sofortigen Aufrufen oder Pausieren

### 📝 Offline-Transkription

Batch-Transkription von Audio- und Videodateien vollständig auf dem Gerät. Unterstützt mehrere ASR-Engines (Parakeet, Qwen3, FireRed ASR) und Apple-Silicon-optimierte MLX-Inferenz für präzise Untertitel — ohne Audioübertragung an Server.

### ✂️ Intelligentes Pausen-Trimming

VAD-basierte Stille-Erkennung identifiziert und entfernt überflüssige Pausen in Podcasts, Interviews und Kursaufnahmen automatisch. Der Rohschnitt kommt der Auslieferungsreife erheblich näher.

### 👥 Sprecher-Diarisierung

Erkennt und beschriftet mehrere Sprecher in einer Aufnahme automatisch. Sortformer- und Silero-VAD-Modelle laufen auf dem Gerät und erzeugen strukturierte, sprecherzugeordnete Transkripte für Interviews, Panels und Meetings.

### 🔊 TTS-Sprachsynthese — Vier Modi

| Modus | Beschreibung |
|---|---|
| **Preset-Stimmen** | Integrierte mehrsprachige Stimmen, sofort einsatzbereit |
| **Stimm-Klon** | Referenzaudio hochladen und Klang sowie Rhythmus des Sprechers reproduzieren |
| **Emotionssteuerung** | Emotion und Sprechstil einer benannten Stimme per Textprompt steuern |
| **Stimmdesign** | Stimmeigenschaften per Text beschreiben und eine völlig originelle Persona synthetisieren |

Alle TTS-Inferenz läuft via MLX auf dem Gerät. Kein Audio wird in die Cloud gesendet.

### 🌐 KI-Korrektur & Übersetzung

Kontextsensitive Transkriptkorrektur, gefolgt von mehrsprachiger Ausgabe — auf dem Gerät oder über Apple Übersetzer. Erstellen Sie Inhalte für ein globales Publikum, ohne das Tool zu wechseln.

### ⭐ Highlight-Erkennung

Erkennt automatisch die wichtigsten Sätze und bemerkenswertesten Momente einer Aufnahme und markiert sie auf der Timeline — damit Schnitt und Veröffentlichung schneller vorankommen.

---

## Exportformate

Cliptate exportiert direkt in die Tools, die Sie bereits verwenden:

| Format | Verwendung |
|---|---|
| **FCPXML** | Final Cut Pro Timeline-Projektaustausch |
| **SRT** | Universelle Untertitellieferung |
| **ASS** | Gestaltete Untertitel mit Positionierung |
| **VTT** | Web-Untertitel für Browser und Streaming-Plattformen |

Kompatibel mit **Final Cut Pro**, **DaVinci Resolve** und **Adobe Premiere Pro**.

---

## Datenschutz & Sicherheit

- **Kein Cloud-Upload** — Audio, Video und Transkripte verlassen Ihren Mac nicht
- **Keine API-Schlüssel erforderlich** — alle Modelle sind in der App enthalten oder werden beim ersten Start heruntergeladen
- **Keine Netzwerkabhängigkeit** — funktioniert vollständig offline, sobald Modelle gecacht sind
- Geeignet für sensible, vertrauliche und compliance-relevante Inhalte

---

## Systemanforderungen

| | |
|---|---|
| **Plattform** | macOS 14 Sonoma oder neuer |
| **Architektur** | Apple Silicon (M1 und neuer) empfohlen |
| **Speicher** | Abhängig von der Modellauswahl (vollständiges Modell-Set: 2–8 GB) |

---

## Technologie-Stack

Cliptate ist vollständig in Swift geschrieben und basiert auf Apple-nativen Frameworks:

---

## Anwendungsfälle

**Podcaster & Interviewer** — Pausen kürzen, Untertitel generieren und veröffentlichungsfähige Momente markieren — alles in einer App.

**Vlog- & Kurzvideoersteller** — Talking-Head-Schnitte flüssiger gestalten und den Fokus auf Rhythmus und Ausdruck legen.

**Kursersteller & Meeting-Protokollanten** — Stunden an Live- oder Aufnahmeaudio per Diktat oder Batch-Transkription in durchsuchbare, übersetzbare und lieferbare Textressourcen verwandeln.

**Mehrsprachige Content-Teams** — Stimme klonen, Transkript übersetzen, Synchronfassungen erstellen — alles auf einem Mac.

---

## Links

- **Website:** [cliptate.github.io](https://cliptate.github.io)
- **App Store:** [Cliptate laden](https://apps.apple.com/)
- **Probleme & Feedback:** [GitHub Issues](https://github.com/cliptate/cliptate.github.io/issues)

---

<div align="center">
  <sub>Entwickelt für Kreative, denen Datenschutz, Geschwindigkeit und professionelle Ausgabe wichtig sind.</sub>
</div>
