# nix-darwin und Home Manager

Dieses Repository verwaltet dieselbe Benutzerumgebung aus einer gemeinsamen
Flake für:

- macOS mit nix-darwin und Home Manager,
- Linux mit Home Manager,
- Homebrew einschließlich aller Tap-Quellen,
- lokale Qwen-Transkription und den Raycast-Teams-Aufruf.

Benutzername, Plattformen, Home-Verzeichnisse, Hostname und Checkout-Pfade
stehen ausschließlich in [`machine-config.nix`](machine-config.nix). Die
Konfiguration ist in kleine Dateien unter [`modules/`](modules/) aufgeteilt.

## macOS: Ersteinrichtung

Homebrew und Determinate Nix sind die einmaligen Voraussetzungen:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | \
  sh -s -- install
```

Rosetta wird für diese Konfiguration nicht benötigt. Der Intel-Homebrew-Prefix
ist deaktiviert; ein bestehendes `/usr/local` wird weder verändert noch
gelöscht.

Danach das Repository an den in `machine-config.nix` hinterlegten Ort klonen
und die Maschinenwerte prüfen:

```bash
mkdir -p ~/.config
cd ~/.config
git clone https://github.com/sadomasupilami/nix-darwin.git
cd nix-darwin
```

Vor einer Aktivierung immer den read-only Preflight ausführen:

```bash
./config/nix-config/nix-config-preflight
```

Er baut die Konfiguration, wertet ein nicht leeres Brewfile aus, schützt
`chatgpt` und Minutes, parst alle installierten Formeln und Casks,
prüft Homebrew Bundle und zeigt mit `--all --zap` die geplante Bereinigung ohne
`--force`. Dafür verwendet er bereits das aus dem gemeinsamen Lockfile gebaute
Homebrew und nicht die eventuell noch ältere Live-Installation. Der
Preflight führt weder Upgrades noch Löschungen oder eine Aktivierung aus.

### Einmaliger Wechsel auf unveränderliche Taps

[`nix-homebrew.mutableTaps = false`](https://github.com/zhaofengli/nix-homebrew#declarative-taps) benötigt
`/opt/homebrew/Library/Taps` als Nix-verwalteten Symlink. Solange dort das
bisherige echte Verzeichnis liegt, stoppt der Preflight absichtlich. Die
Migration ist nicht automatisiert:

1. Den vom Preflight gemeldeten Pfad prüfen.
2. Erst nach separater Zustimmung das vorhandene Verzeichnis auf einen
   eindeutig datierten Backup-Pfad verschieben.
3. Den Preflight erneut ausführen.
4. Den ersten gepinnten Apply ausführen.
5. Homebrew und alle vier Taps verifizieren; das Backup erst danach und nur mit
   separater Zustimmung entfernen.

Beispiel für Schritt 2, bewusst **nicht automatisch ausgeführt**:

```bash
sudo mv /opt/homebrew/Library/Taps \
  /opt/homebrew/Library/Taps.before-nix-homebrew-YYYYMMDD-HHMMSS
```

Der empfohlene erste Apply führt den Preflight nochmals aus und verwendet
intern den im gemeinsamen Lockfile gepinnten `darwin-rebuild`:

```bash
./config/nix-config/nix-config-apply
```

Der zugrunde liegende Flake-Einstieg ist
`sudo -- "$(command -v nix)" run "$snapshot#darwin-rebuild" -- switch --flake "$snapshot#macos"`.
`$snapshot` ist dabei der zuvor geprüfte Nix-Store-Snapshot.
`sudo` ist für die Systemaktivierung erforderlich; die App und ihre Version
stammen weiterhin aus dem gemeinsamen Lockfile.

Ein echter Apply bleibt eine gesondert zu bestätigende Aktion. Er aktualisiert
deklarierte Homebrew- und App-Store-Apps und entfernt mit `cleanup = "zap"`
nicht deklarierte Homebrew-Apps samt Zap-Daten. Ein Nix-Rollback stellt weder
Homebrew-Upgrades noch gezappte Daten wieder her.

## Updates und Apply-Helfer

Nach der ersten Home-Manager-Aktivierung liegen diese Befehle in `~/.bin`.
Ihre Implementierung und Hilfsprogramme kommen aus dem Nix Store; Änderungen
im Checkout ändern die installierten Helfer erst beim nächsten Apply:

```bash
nix-config-update [all|homebrew]
nix-config-preflight
nix-config-apply [--gc] [--accept-zap HASH]
```

- `nix-config-update all` aktualisiert alle Root-Flake-Inputs und führt danach
  den Preflight aus.
- `nix-config-update homebrew` aktualisiert nur `nix-homebrew`, Core, Cask sowie
  die Azure- und Silverstein-Taps als gemeinsame Gruppe und führt danach den
  Preflight aus.
- Ein fehlgeschlagener Preflight lässt das neue `flake.lock` zur Prüfung liegen,
  blockiert aber den Apply.
- Preflight und Apply erfassen die getrackten Working-Tree-Dateien einmal als
  unveränderlichen Nix-Store-Snapshot. Prüfung und Aktivierung verwenden genau
  diesen Stand, auch wenn der Checkout inzwischen geändert wird. Ein sauberer
  Checkout gibt seinen Commit als `configurationRevision` an die Generation
  weiter; ein Checkout mit lokalen Änderungen bleibt unbeschriftet.
- Der Preflight vergleicht deklarierte Formula-Taps mit den installierten
  Receipts, damit Alias-Konflikte vor der Aktivierung auffallen. `azd` bleibt
  explizit `azure/azd/azd`; Minutes verwendet wegen des gleichnamigen Formula-
  Eintrags einen separaten Cask-Installationspfad.
- Ein nicht leerer Zap-Preview (auch nur alte Versionen oder Cache-Dateien)
  stoppt mit Exitcode 3. Nach Prüfung der Liste
  kann `nix-config-apply --accept-zap HASH` mit dem ausgegebenen Hash ausgeführt
  werden. Die Freigabe gilt nur für genau diese Liste und diesen Snapshot;
  geänderte Dateien oder eine andere Entfernungsliste benötigen eine neue
  Freigabe. Während des Apply keine parallelen Homebrew-Änderungen vornehmen.
- `nix-config-apply --gc` führt ein vollständiges `nix-collect-garbage` aus,
  weiterhin ohne Löschen alter Generationen und ohne Schonfrist für kürzlich
  entstandene Pfade (siehe unten). Ein separates `mas upgrade` gibt es nicht mehr.
- Neue Quelldateien müssen vor dem Preflight mit `git add` getrackt werden;
  ignorierte und ungetrackte Dateien gehören bewusst nicht zum Snapshot.

## Automatische Garbage Collection

Der Determinate-Nixd-eigene Collector ist abgeschaltet
(`garbageCollector.strategy = "disabled"`), weil er keine Aufbewahrungsfrist
kennt. An seiner Stelle prüft der LaunchDaemon `nix-gc-recent`
(`modules/nix-gc.nix`, Skript in `config/nix-gc/`) stündlich den freien Platz auf
`/nix`:

- Ab 20 % frei passiert nichts.
- Darunter wird `nix-store --gc` ausgeführt, aber unerreichbare Store-Pfade, die
  jünger als 14 Tage sind, bleiben samt ihren Abhängigkeiten erhalten. Dafür
  legt das Skript für die Dauer des Laufs temporäre GC-Roots unter
  `/nix/var/nix/gcroots/nix-gc-recent` an.
- Unter 5 % frei entfällt die Schonfrist, damit eine fast volle Platte die
  Bereinigung nicht blockiert.

`/nix` ist mit `noatime` eingehängt, ein Pfad trägt also nur den Zeitpunkt seiner
Registrierung. Die Schonfrist schützt daher kürzlich gebaute oder geladene Pfade,
nicht kürzlich ausgeführte. Protokoll: `/var/log/nix-gc-recent.log`. Prüfen ohne
Root und ohne Änderung:

```bash
nix-gc-recent --force --dry-run
```

Schonfrist und Schwellen stehen oben in `modules/nix-gc.nix`.

Homebrew-Casks und App-Store-Apps bleiben bewusst nativ verwaltet. Gepinnte
Tap-Quellen fixieren die Paketdefinitionen; App-eigene Updater und App-Store-
Versionen können davon unabhängig sein. Nix-Rollbacks rollen diese Apps nicht
zurück.

Die gewählte Homebrew-Politik bleibt `autoUpdate = false`, `upgrade = true` und
`cleanup = "zap"`. Die Homebrew-Version wird aus `flake.lock` abgeleitet. `chatgpt` ist der
[aktuelle Desktop-Weg mit integriertem Codex](https://learn.chatgpt.com/docs/app).
Das Verhalten der unforced Cleanup-Vorschau entspricht der
[Homebrew-Manpage](https://docs.brew.sh/Manpage.html).

`mas` erkennt installierte App-Store-Apps über Spotlight. Der read-only
Preflight unterbindet die automatische Indexierung durch `mas`; meldet er eine
vorhandene und deklarierte App trotzdem als fehlend, muss der Spotlight-Index
repariert werden, nicht die App zusätzlich als Cask deklariert werden. Siehe
die [Spotlight-Hinweise von mas](https://github.com/mas-cli/mas#spotlight) und
[Apples Anleitung zum Neuaufbau des Index](https://support.apple.com/102321).

## Linux Home Manager

Nach der Nix-Installation das Repository an den Linux-Pfad aus
`machine-config.nix` klonen. Die verschachtelte Flake und ihr zweites Lockfile
gibt es nicht mehr. Der erste Apply verwendet ausschließlich die im Root-Lock
festgelegte Home-Manager-Version:

```bash
cd ~/.config/nix-darwin
nix run .#home-manager -- switch --flake .#default
```

Dieselben Helfer stehen anschließend zur Verfügung. Unter Linux überspringt
der Preflight nur die macOS-/Homebrew-Prüfungen; die Root-Flake wird weiterhin
geprüft.

Die öffentlichen Flake-Ausgaben sind:

```text
darwinConfigurations.macos
homeConfigurations.default
homeConfigurations.michaelklug
```

## Claude-Mods

Der Flake-Input `claude-code-playground` pinnt die offiziellen Sample-Mods von
Anthropic in `flake.lock`. [`modules/claude-mods.nix`](modules/claude-mods.nix)
verlinkt `token-weather` (Kontextfenster-Prognose über dem Prompt) und
`blast-radius` (hält riskante Shell-Befehle an und zeigt vorab, was sie ändern
würden) nach `~/.claude/skills`. Dazu kommt der eigene Mod `usage-meter` aus
[`config/claude-mods/usage-meter/`](config/claude-mods/usage-meter/): Er zeigt
die Rate-Limit-Fenster (5h, 7d) und die Session-Kosten in der Statuszeile, mit
`/usage-meter` als Pane mit Balken und Reset-Zeiten, und warnt per Toast ab 80 %
und 95 %. Claude Code lädt diese Ordner in jeder Session automatisch als Plugin
`<name>@skills-dir`; `~/.claude/settings.json` bleibt unangetastet. Tests für
den eigenen Mod: `claude plugin test config/claude-mods/usage-meter`.

Mods brauchen Claude Code ab 2.1.287. Dafür installiert Homebrew das Cask
`claude-code@latest` statt des langsameren Stable-Casks `claude-code`. Mods
laufen mit den eigenen Rechten und ohne Sandbox. Vor einem Pin-Update
`claude plugin validate` auf die neuen Store-Pfade anwenden und die `hooks:`-
und `calls:`-Zeilen prüfen. Update mit `nix flake update claude-code-playground`
oder `nix-config-update all`, danach Preflight und Apply. Kontrolle mit
`claude plugin list`.

## Lokale Meeting-Transkription

Auf Apple Silicon installiert Home Manager die Befehle `qwen-meeting` und
`qwen-meeting-setup` samt unveränderlicher Python-Laufzeit im Nix Store.
[`packages/qwen-meeting-runtime`](packages/qwen-meeting-runtime/default.nix)
bezieht die Python-3.13-Wheels aus dem committed `uv.lock` mit ihren Hashes;
Installation und Abhängigkeitsprüfung im Paket erfolgen offline. Nix lädt die
Wheels beim Build. Die Wrapper referenzieren die Laufzeit ihrer Generation,
sodass ein Rollback auch die Python-Abhängigkeiten wiederherstellt.

Nur die großen Modellgewichte werden durch den ausdrücklichen Setup-Aufruf
geladen:

```bash
qwen-meeting-setup
```

Er lädt mit der Nix-Laufzeit exakt diese Modellrevisionen:

- Qwen3-ASR-1.7B: `7278e1e70fe206f11671096ffdd38061171dd6e5`
- Qwen3-ForcedAligner-0.6B: `c7cbfc2048c462b0d63a45797104fc9db3ad62b7`

Eine vorhandene `~/.venvs/qwen3-asr` wird weder verändert noch entfernt und
von den neuen Wrappern nicht mehr verwendet. Modelle und Transkripte bleiben
außerhalb des Nix Stores. Die Modellrevisionen werden weiterhin separat durch
Setup verwaltet; ein Runtime-Rollback lädt oder ersetzt keine Modellgewichte.

Transkriptionsläufe verwenden danach nur lokale Modellpfade und
`HF_HUB_OFFLINE=1`:

```bash
qwen-meeting "/vollständiger/Pfad/aufnahme.m4a" [auto|de|en]
qwen-meeting --copy "/vollständiger/Pfad/aufnahme.m4a" auto
```

Der Ausgabeordner öffnet sich standardmäßig im Finder. Das Transkript wird
nicht ins Terminal geschrieben und nur mit `--copy` in die Zwischenablage
kopiert. Neue Verzeichnisse erhalten Modus `0700`, neue Dateien `0600`.
Vorhandene unsichere Verzeichnisse werden mit einem Hinweis abgelehnt und nicht
automatisch umgestellt. Das verwaltete Vokabular liegt in
[`config/qwen-meeting/context.txt`](config/qwen-meeting/context.txt).

## Raycast und Teams

Die persönliche Kontaktliste bleibt bewusst außerhalb von Git und Nix Store:

```text
~/.config/raycast/teams-people.csv
name,email,tenantId
```

Das Verzeichnis muss `0700`, die CSV `0600` haben. Das Skript ändert bestehende
Rechte nicht rückwirkend. Es protokolliert weder Namen noch E-Mail-Adressen,
Tenant-IDs oder Deep Links. Statt des früheren globalen `/tmp`-Logs schreibt es
nur eine generische, atomar ersetzte Statuszeile in eine private Datei. Das
alte `/tmp/raycast-teams-video-call.log` wird nicht automatisch gelöscht.

## Tests und CI

Lokal:

```bash
nix flake check --all-systems --no-build
nix flake check
bash tests/run-local-tools-tests.sh
bash tests/nix-config-helpers.sh
nix fmt -- --check
git diff --check
```

GitHub Actions wertet und baut auf `ubuntu-24.04` und `macos-26`. CI hat nur
`contents: read` und führt keine Systemaktivierung, Homebrew-Upgrades oder
Zap-Bereinigung aus.

## Bewusst akzeptierte Risiken und erhaltene Integrationen

- Der lokale Benutzer bleibt ein vertrauenswürdiger Nix-Benutzer und Nix-
  Sandboxing bleibt deaktiviert.
- Die macOS Application Firewall und Stealth Mode bleiben deaktiviert. Das ist
  ein bewusst akzeptiertes Restrisiko; die Konfiguration aktiviert sie nicht.
- Minutes bleibt als Cask `silverstein/tap/minutes` erhalten. Die GUI erhält
  weiterhin `MINUTES_FFMPEG` aus dem Nix-Benutzerprofil.
- WireGuard bleibt als App-Store-App deklariert.
- Die SSH-Reconciliation behält dynamische Coder-Blöcke und verwaltet nur den
  stabilen Include-Teil.
- `mas` und Docker Credential Helpers kommen ausschließlich aus Nix.
- Persönliche Transkripte, vorhandene CSV-Rechte und das alte Teams-Log werden
  ohne separate Freigabe weder migriert noch gelöscht.

Weitere manuelle Einrichtung: Bartender-Lizenz. Pakete lassen sich über
[search.nixos.org](https://search.nixos.org) suchen.
