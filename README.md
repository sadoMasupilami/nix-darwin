# nix-darwin und Home Manager

[![Flake checks](https://github.com/sadomasupilami/nix-darwin/actions/workflows/flake-checks.yml/badge.svg?branch=main)](https://github.com/sadomasupilami/nix-darwin/actions/workflows/flake-checks.yml)

Dieses Repository verwaltet dieselbe Benutzerumgebung aus einer gemeinsamen
Flake für:

- macOS mit nix-darwin und Home Manager,
- Linux mit Home Manager,
- Homebrew einschließlich aller Tap-Quellen,
- Shell, Git und Kommandozeilenwerkzeuge auf beiden Plattformen,
- lokale Qwen-Transkription und den Raycast-Teams-Aufruf.

Benutzername, Plattformen, Home-Verzeichnisse, Hostname, Checkout-Pfade und
State-Versionen stehen ausschließlich in
[`machine-config.nix`](machine-config.nix). Die State-Versionen (`stateVersion`
für nix-darwin, `homeStateVersion` für Home Manager) gehören zur jeweiligen
Maschine: für einen bestehenden Host nie erhöhen, ein neuer Host erhält das
dann aktuelle Release. Die Konfiguration ist in kleine Dateien unter
[`modules/`](modules/) aufgeteilt; [`home.nix`](home.nix) ist der gemeinsame
Home-Manager-Einstieg für macOS und Linux.

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

Vor einer Aktivierung immer den read-only Preflight ausführen, als normaler
Benutzer und nicht über `sudo`:

```bash
./config/nix-config/nix-config-preflight
```

Er führt `nix flake check` auf dem Snapshot aus und baut damit die
Konfiguration samt aller Checks dieses Systems. Danach wertet er ein nicht
leeres Brewfile aus, schützt `chatgpt` und Minutes, parst alle installierten
Formeln und Casks, prüft jede deklarierte Formel und jeden deklarierten Cask
gegen die gelockten Taps, prüft Homebrew Bundle und zeigt mit `--all --zap` die
geplante Bereinigung ohne `--force`. Dafür verwendet er bereits das aus dem
gemeinsamen Lockfile gebaute Homebrew und nicht die eventuell noch ältere
Live-Installation. Der Preflight führt weder Upgrades noch Löschungen oder eine
Aktivierung aus.

Hat Homebrew einen deklarierten Cask oder eine deklarierte Formel deaktiviert
(`disable!`), stoppt der Preflight mit einer Meldung, die den Eintrag nennt:
Ein frisches System könnte ihn nicht mehr installieren, also muss er aus
[`modules/homebrew.nix`](modules/homebrew.nix) entfernt werden. Veraltete oder
erst künftig deaktivierte Einträge erzeugen nur eine Warnung.

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
`$snapshot` ist dabei der zuvor geprüfte Nix-Store-Snapshot. Davor führt
Apply nur die Prüfungen der neuen Generation aus, ohne etwas zu aktivieren
(siehe [Homebrew-Bereinigung und Rollbacks](#homebrew-bereinigung-und-rollbacks)).
`sudo` ist für die Systemaktivierung erforderlich; die App und ihre Version
stammen weiterhin aus dem gemeinsamen Lockfile. `nix-config-apply` selbst
läuft als normaler Benutzer, dem `/opt/homebrew` gehört, und nicht über
`sudo`; es fragt für Prüfung und Switch selbst nach dem Passwort.

Ein echter Apply bleibt eine gesondert zu bestätigende Aktion. Er aktualisiert
deklarierte Homebrew- und App-Store-Apps. Nicht deklarierte Homebrew-Apps samt
Zap-Daten entfernt er nur nach ausdrücklicher Freigabe (siehe
[Homebrew-Bereinigung und Rollbacks](#homebrew-bereinigung-und-rollbacks)). Ein
Nix-Rollback stellt weder Homebrew-Upgrades noch gezappte Daten wieder her.

### Erste Schritte nach dem ersten Apply

- Eine vorhandene `~/.gitconfig` sichern und leeren, aber nicht löschen (siehe
  [Git](#git)).
- Prüfen, ob der Zertifikats-Daemon das Benutzer-Vertrauen auswerten kann
  (siehe [Zertifikate aus dem Schlüsselbund](#zertifikate-aus-dem-schlüsselbund)).
- Im Checkout einmal `nix develop -c pre-commit install` ausführen (siehe
  [pre-commit](#pre-commit)).

## Updates und Apply-Helfer

Nach der ersten Home-Manager-Aktivierung liegen diese Befehle in `~/.bin`.
Ihre Implementierung und Hilfsprogramme kommen aus dem Nix Store; Änderungen
im Checkout ändern die installierten Helfer erst beim nächsten Apply:

```bash
nix-config-update [--yes] [all|homebrew]
nix-config-preflight
nix-config-apply [--gc] [--accept-zap HASH]
```

**Einmalig beim Umstieg auf die Homebrew-Prüfung in der Aktivierung** (siehe
[Homebrew-Bereinigung und Rollbacks](#homebrew-bereinigung-und-rollbacks)):
Bis zum ersten Apply mit dieser Prüfung stammen die Helfer in `~/.bin` aus
einer älteren Generation. Deren `nix-config-apply` entfernt die freigegebene
Liste nicht selbst und ruft direkt `darwin-rebuild switch` auf. Ist etwas zu
entfernen (derzeit UltraStar Deluxe), bricht die neue Prüfung diesen Switch
ab, nachdem er das Systemprofil schon umgestellt hat. Den ersten Apply nach
der Umstellung deshalb mit den Helfern aus dem Checkout ausführen:

```bash
cd ~/.config/nix-darwin
./config/nix-config/nix-config-preflight
./config/nix-config/nix-config-apply --accept-zap HASH
```

Aus dem Checkout gestartet nennt der Preflight den vollen Pfad dieses
`nix-config-apply`. Ist ein Apply mit dem alten Helfer bereits abgebrochen,
vor dem nächsten Neustart das Systemprofil zurücksetzen wie unter
[Homebrew-Bereinigung und Rollbacks](#homebrew-bereinigung-und-rollbacks)
beschrieben. Nach dem ersten erfolgreichen Apply sind die Helfer in `~/.bin`
auf dem neuen Stand.

- `nix-config-update all` aktualisiert alle Root-Flake-Inputs und führt danach
  den Preflight aus.
- `nix-config-update homebrew` aktualisiert `nix-homebrew` und alle
  `homebrew-*`-Inputs aus `flake.lock` (derzeit Core, Cask sowie die Azure- und
  Silverstein-Taps) als gemeinsame Gruppe und führt danach den Preflight aus.
  Ein neuer Tap-Input mit diesem Präfix gehört automatisch zur Gruppe.
- Ändert ein Update einen Drittanbieter-Tap (jeden `homebrew-*`-Input, der
  nicht Homebrew selbst gehört, derzeit `Azure/homebrew-azd` und
  `silverstein/homebrew-tap`), zeigt `nix-config-update` alte und neue Revision
  samt GitHub-Compare-Link und fragt `Continue with the preflight? [y/N]`, bevor
  Code aus dem Tap läuft. Ein Nein oder ein nicht interaktiver Lauf endet mit
  Exitcode 1; das neue `flake.lock` bleibt liegen. Nach der Prüfung dann
  `nix-config-preflight` ausführen oder `flake.lock` zurücksetzen. `--yes`
  überspringt die Frage für unbeaufsichtigte Läufe, die Liste wird trotzdem
  ausgegeben.
- `nix-config-update` gibt den Exitcode des Preflights weiter. Exitcode 3
  bedeutet nur, dass die angezeigte Bereinigungsliste freigegeben werden muss.
  Jeder andere fehlgeschlagene Preflight lässt das neue `flake.lock` zur Prüfung
  liegen, blockiert aber den Apply.
- Preflight und Apply erfassen die getrackten Working-Tree-Dateien einmal als
  unveränderlichen Nix-Store-Snapshot. Prüfung und Aktivierung verwenden genau
  diesen Stand, auch wenn der Checkout inzwischen geändert wird. Ein sauberer
  Checkout gibt seinen Commit als `configurationRevision` an die Generation
  weiter; ein Checkout mit lokalen Änderungen bleibt unbeschriftet. Snapshot
  und gepinntes Homebrew bleiben während des Laufs als temporäre GC-Roots
  registriert, damit eine parallel laufende Garbage Collection sie nicht löscht.
- Der Preflight vergleicht deklarierte Formula-Taps mit den installierten
  Receipts, damit Alias-Konflikte vor der Aktivierung auffallen. `azd` bleibt
  explizit `azure/azd/azd`; Minutes verwendet wegen des gleichnamigen Formula-
  Eintrags einen separaten Cask-Installationspfad.
- Exitcodes des Preflights: 0 bestanden, 3 Bereinigung braucht eine Freigabe,
  jeder andere Wert ist ein Fehler. Stürzt Homebrew mit Status 1 ab, meldet der
  Preflight das als Fehler (Exitcode 2) und gibt keinen Freigabe-Hash aus.
- Ein nicht leerer Zap-Preview (auch nur alte Versionen oder Cache-Dateien)
  stoppt mit Exitcode 3. Nach Prüfung der Liste kann der ausgegebene Befehl
  `nix-config-apply --accept-zap HASH` ausgeführt werden; aus dem Checkout
  gestartet nennt der Preflight den vollen Pfad des zugehörigen Helfers. Die
  Freigabe gilt nur für genau diese Liste und diesen Snapshot;
  geänderte Dateien oder eine andere Entfernungsliste benötigen eine neue
  Freigabe. Während des Apply keine parallelen Homebrew-Änderungen vornehmen.
- `nix-config-apply --gc` führt ein vollständiges `nix-collect-garbage` aus,
  weiterhin ohne Löschen alter Generationen und ohne Schonfrist für kürzlich
  entstandene Pfade (siehe unten). Ein separates `mas upgrade` gibt es nicht mehr.
- Neue Quelldateien müssen vor dem Preflight mit `git add` getrackt werden;
  ignorierte und ungetrackte Dateien gehören bewusst nicht zum Snapshot.

## Homebrew-Bereinigung und Rollbacks

Die Aktivierung selbst entfernt nichts mehr
(`homebrew.onActivation.cleanup = "none"`). Stattdessen führt eine Prüfung in
[`modules/homebrew.nix`](modules/homebrew.nix) ganz am Anfang von `activate`,
vor jeder Änderung, `brew bundle cleanup --all --zap` ohne `--force` aus und
bricht die Aktivierung mit
`found Homebrew packages not listed in the Brewfile, aborting activation` ab,
solange das Brewfile etwas deinstallieren würde: nicht deklarierte Formeln,
Casks, App-Store-Apps oder andere von Homebrew Bundle verwaltete Einträge.
Alte Versionen und Cache-Dateien lösen keinen Abbruch aus. Endet Homebrew mit
einem Fehler statt mit einer Entfernungsliste, bricht die Aktivierung mit
`brew bundle cleanup failed` ab, ohne auf eine Freigabe zu verweisen.

Die Prüfung ersetzt nix-darwins `cleanup = "check"` aus zwei Gründen:

- `"check"` steht in `system.checks`, und diese Checks bettet nix-darwin auch
  in den Boot-Daemon `org.nixos.activate-system` ein. Homebrew liefe damit bei
  jedem Start und bei jedem Neuladen dieses Daemons, und ein Fund, etwa eine
  nicht deklarierte App-Store-App, würde dort das Neuverlinken von `/etc`
  überspringen. Die Prüfung hier steht in
  `system.activationScripts.preActivation` und läuft nur in `activate`.
- `"check"` verwendet das Live-Homebrew, das bis zum späteren Umschalten der
  Taps in `activate` noch die Taps der vorherigen Generation kennt. Benennt
  ein Tap-Update ein deklariertes Paket um, berechnet es eine andere Liste als
  die Vorschau. Die Prüfung verwendet deshalb denselben gepinnten Homebrew wie
  der Preflight, mit den Taps dieser Generation; Vorschau, Nachkontrolle in
  Apply und Aktivierung berechnen dieselbe Liste.

Entfernt wird ausschließlich in `nix-config-apply`:

1. Der Preflight zeigt die Entfernungsliste und stoppt mit Exitcode 3 und
   einem Hash.
2. Nach Prüfung der Liste `nix-config-apply --accept-zap HASH` ausführen.
3. Apply entfernt genau die freigegebene Liste mit
   `brew bundle cleanup --all --zap --force`, und zwar mit dem gepinnten
   Homebrew, den gelockten Taps und dem Brewfile, aus denen die Vorschau
   stammt, nicht mit dem Live-Homebrew unter `/opt/homebrew`. Deinstallations-
   schritte einzelner Casks können dabei nach dem `sudo`-Passwort fragen.
4. Danach prüft Apply mit einer erneuten Vorschau, dass nichts übrig ist.
   Bleibt etwas übrig oder scheitert die erzwungene Bereinigung selbst, endet
   es mit Exitcode 2, ohne etwas zu aktivieren.
5. Apply baut die neue Generation und führt ihr `activate` im Prüfmodus aus:
   nur die Homebrew-Prüfung und nix-darwins Checks, ohne das Systemprofil
   anzufassen. Schlägt das fehl, endet Apply, ohne etwas zu aktivieren.
   `darwin-rebuild check` taugt dafür nicht: Die erste Zeile von `activate`
   (`#!/usr/bin/env -i`) leert die Umgebung und damit auch das
   `checkActivation=1`, das `darwin-rebuild check` setzt. Es führt deshalb die
   komplette Aktivierung aus, nur ohne das Profil umzustellen. Apply ruft
   stattdessen den Interpreter aus dieser Zeile direkt mit leerer Umgebung und
   `checkActivation=1` auf.
6. Erst dann folgt `darwin-rebuild switch`.

Ist die Vorschau leer, ruft Apply dafür kein Homebrew auf. Die erzwungene
Bereinigung räumt `~/Library/Caches/Homebrew` nicht auf; das übernimmt Homebrew
periodisch selbst.

Ein direktes `sudo darwin-rebuild switch` oder ein Rollback auf eine Generation
mit dieser Prüfung entfernt deshalb nie Apps, sondern bricht ab, wenn das
Brewfile dieser Generation etwas deinstallieren würde. Die gemeldeten Pakete
dann nicht von Hand mit `brew bundle cleanup --force` entfernen. Nach einem
abgebrochenen direkten Switch stattdessen Preflight und
`nix-config-apply --accept-zap HASH` verwenden. Beide Helfer bauen immer den
Checkout, nie eine vorhandene Generation. Für einen Rollback deshalb zuerst das
Profil zurücksetzen wie unten beschrieben, dann den Commit der Zielgeneration
auschecken und Preflight und `nix-config-apply --accept-zap HASH` aus diesem
Checkout ausführen. Den Commit nennt read-only
`jq -r .configurationRevision /nix/var/nix/profiles/system-N-link/darwin-version.json`;
`darwin-version` zeigt nur den der laufenden Generation. Endet er auf `-dirty`
oder fehlt er, enthielt die Generation lokale Änderungen, die sich so nicht
wiederherstellen lassen.

**Achtung:** `switch` und `--rollback` stellen das Systemprofil
`/nix/var/nix/profiles/system` schon vor `activate` um. Nach einem solchen
Abbruch zeigt es auf eine Generation, die nie aktiviert wurde, und der
Boot-Daemon würde beim nächsten Start deren `/etc` verlinken, während Dienste,
Homebrew und Home Manager auf dem alten Stand bleiben. `nix-config-apply`
vermeidet das, weil es die Prüfungen vorher allein ausführt (Schritt 5);
`darwin-rebuild check` ist dafür kein Ersatz. Bricht die Prüfung außerhalb
dieses Prüfmodus ab, nennt ihre Meldung den folgenden Befehl. Nach einem
abgebrochenen direkten Aufruf das Profil vor dem nächsten Neustart ohne
Aktivierung zurücksetzen:

```bash
sudo nix-env -p /nix/var/nix/profiles/system --set "$(readlink -f /run/current-system)"
```

Nach einem Neustart zeigt `/run/current-system` bereits auf die abgelehnte
Generation. Dann die zuletzt aktivierte Generation mit
`nix-env -p /nix/var/nix/profiles/system --list-generations` heraussuchen und
mit `sudo nix-env -p /nix/var/nix/profiles/system --switch-generation N`
setzen; der nächste erfolgreiche Apply verlinkt `/etc` wieder passend. Nicht
`darwin-rebuild --rollback` verwenden: Es aktiviert die vorherige Generation
erneut und zappt bei den unten genannten alten Generationen ohne Vorschau.

**Ausnahme:** Generationen, die vor dieser Umstellung mit `cleanup = "zap"`
gebaut wurden (auf dieser Maschine derzeit `system-25` bis `system-182`), haben
`brew bundle --file=… --cleanup --zap` (`system-25` bis `system-124`) oder
`brew bundle --file=… --zap --force-cleanup` (`system-125` bis `system-182`)
fest in ihrem `activate`-Skript. Ein
Rollback oder Switch auf eine davon zappt weiterhin ohne Vorschau alle seither
hinzugekommenen Casks samt ihrer Daten, bis diese Generationen gelöscht und
eingesammelt sind. Welche Generationen das betrifft, zeigt read-only:

```bash
grep -lE -- '--cleanup --zap|--force-cleanup' /nix/var/nix/profiles/system-*-link/activate
```

Homebrew-Casks und App-Store-Apps bleiben bewusst nativ verwaltet. Gepinnte
Tap-Quellen fixieren die Paketdefinitionen; App-eigene Updater und App-Store-
Versionen können davon unabhängig sein. Nix-Rollbacks rollen diese Apps nicht
zurück.

Die gewählte Homebrew-Politik ist `autoUpdate = false`, `upgrade = true` und
`cleanup = "none"` mit der Prüfung oben; gezappt wird nur über die Freigabe in
`nix-config-apply`.
Die Homebrew-Version wird aus `flake.lock` abgeleitet. `chatgpt` ist der
[aktuelle Desktop-Weg mit integriertem Codex](https://learn.chatgpt.com/docs/app).
Das Verhalten der unforced Cleanup-Vorschau entspricht der
[Homebrew-Manpage](https://docs.brew.sh/Manpage.html).

`mas` erkennt installierte App-Store-Apps über Spotlight. Der read-only
Preflight unterbindet die automatische Indexierung durch `mas`; meldet er eine
vorhandene und deklarierte App trotzdem als fehlend, muss der Spotlight-Index
repariert werden, nicht die App zusätzlich als Cask deklariert werden. Siehe
die [Spotlight-Hinweise von mas](https://github.com/mas-cli/mas#spotlight) und
[Apples Anleitung zum Neuaufbau des Index](https://support.apple.com/102321).

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
nicht kürzlich ausgeführte. Ein Pfad, der erst nach der Liste toter Pfade
registriert wird und keinen eigenen Root hat, ist nicht geschützt; deshalb
halten Preflight und Apply ihren Snapshot selbst als GC-Root.

Ein sammelnder Lauf nimmt eine Sperre auf `/var/run/nix-gc-recent.lock`
(Kernel-Lock über `lockf`, bleibt nach einem Abbruch nie hängen); `--dry-run`
braucht keine. Überschneidet
sich ein manuelles `sudo nix-gc-recent --force` mit dem stündlichen Lauf, meldet
es `another run is active, skipping` und endet mit Exitcode 0.

Protokoll: `/var/log/nix-gc-recent.log`, von newsyslog ab 1 MB rotiert (fünf
bzip2-Archive). Prüfen ohne Root und ohne Änderung:

```bash
nix-gc-recent --force --dry-run
```

Schonfrist und Schwellen stehen oben in `modules/nix-gc.nix`.

## Zertifikate aus dem Schlüsselbund

[`modules/certificates.nix`](modules/certificates.nix) spiegelt unter macOS die
CA-Zertifikate, denen macOS für den primären Benutzer vertraut, nach
`/etc/ssl/certs/keychain-ca.pem` und zusammen mit dem Mozilla-Bundle aus
`security.pki` nach
`/etc/ssl/certs/ca-bundle-full.crt`. `SSL_CERT_FILE`, `NIX_SSL_CERT_FILE` und
`REQUESTS_CA_BUNDLE` zeigen auf das volle Bundle, `NODE_EXTRA_CA_CERTS` auf die
Schlüsselbund-Zertifikate. curl und git lesen den Schlüsselbund weiterhin
selbst.

- Übernommen werden CA-Zertifikate (`CA:TRUE`) aus dem System-Schlüsselbund,
  die für diesen Benutzer verifizieren. Damit zählen Benutzer-, Admin- und
  System-Vertrauen, und „Niemals vertrauen“ wird beachtet. Ebenso übernommen
  werden echt selbstsignierte Zertifikate, denen er vertraut, etwa ein mit
  „Immer vertrauen“ markiertes selbstsigniertes Serverzertifikat oder eine
  v1-Root ohne Erweiterungen; ihre Selbstsignatur muss gültig sein. Aus dem
  Anmelde-Schlüsselbund kommen nur Zertifikate mit eigener „Immer
  vertrauen“- oder Admin-Einstellung dazu; S/MIME-Zertifikate aus Mail bleiben
  draußen.
- Maschinen- und Geräteidentitäten werden nicht übernommen: Sie sind keine
  CAs und von einer anderen CA ausgestellt, oder macOS vertraut ihnen nicht.
- Der LaunchDaemon `org.nixos.refresh-ca-bundle` aktualisiert die Bundles bei
  jeder Änderung des System-Schlüsselbunds, mindestens stündlich und beim
  Start. Entfernte oder misstraute Zertifikate erreichen wget, Python, requests
  und Node also ohne Apply. Die Bundles werden atomar und nur bei geändertem
  Inhalt geschrieben.
- Kann das Skript das Vertrauen nicht als dieser Benutzer auswerten, bricht es
  ab und lässt vorhandene Bundles unverändert. Nur wenn noch keine Bundles
  existieren, schreibt es sie stattdessen aus der Sicht von root, also nur mit
  Admin- und System-Vertrauen und ohne die CAs des Benutzers, und meldet
  `admin and system trust settings`; erst ein späterer erfolgreicher Lauf
  ergänzt diese CAs. Hat der Benutzer keine Anmeldesitzung, etwa beim Start
  vor dem Login, bleiben vorhandene Bundles unverändert bis zum nächsten Lauf.
- Schlägt die Aktualisierung während der Aktivierung fehl, gibt es nur eine
  Warnung; die bisherigen Bundles bleiben bestehen und der Switch läuft weiter.
- Protokoll: `/var/log/refresh-ca-bundle.log`, von newsyslog rotiert.

```bash
refresh-ca-bundle --dry-run   # ohne sudo: zeigt, was gespiegelt würde
sudo refresh-ca-bundle        # sofort aktualisieren
```

Nach dem ersten Apply prüfen, ob der Daemon das Vertrauen aus dem
Systemkontext von launchd als Benutzer auswerten kann. Dafür seine Zählung mit
einem Probelauf im eigenen Terminal vergleichen:

```bash
sudo launchctl kickstart -k system/org.nixos.refresh-ca-bundle
sleep 5; tail -n 3 /var/log/refresh-ca-bundle.log
refresh-ca-bundle --dry-run | tail -n 1
```

Die letzte Protokollzeile und die Zeile des Probelaufs müssen beide
`from the trust settings of <Benutzer>` und dieselbe Zahl vor
`keychain CA certificate(s)` nennen. Der Text allein genügt nicht: Sieht der
Daemon die Vertrauenseinstellungen des Benutzers als leer, meldet er denselben
Text mit einer kleineren Zahl, und die CAs des Benutzers fehlen im Bundle.

- `cannot evaluate trust as <Benutzer>`: Der Daemon konnte das
  Benutzer-Vertrauen nicht auswerten; die bisherigen Bundles bleiben erhalten.
- `admin and system trust settings`: erscheint nur, wenn noch keine Bundles
  existierten. Dann wurden Bundles ohne die CAs des Benutzers geschrieben.
- `has no login session` trotz Anmeldung: Der Daemon erkennt die Sitzung
  nicht und lässt die Bundles dauerhaft unverändert.

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

Statt des macOS-Daemons startet unter Linux ein wöchentlicher
systemd-User-Timer ([`modules/linux-gc.nix`](modules/linux-gc.nix))
`nix-collect-garbage --delete-older-than 14d`. Er löscht Profilgenerationen
dieses Benutzers, die älter als 14 Tage sind, auch die von Home Manager, und
danach alle unerreichbaren Store-Pfade. Der Timer braucht eine
systemd-User-Session, sonst ist er zwar installiert, läuft aber nie. Unter WSL
dafür `systemd=true` im Abschnitt `[boot]` von `/etc/wsl.conf` setzen.
Kontrolle:

```bash
systemctl --user list-timers nix-gc.timer
```

Die öffentlichen Flake-Ausgaben sind:

```text
darwinConfigurations.macos
homeConfigurations.default
homeConfigurations.michaelklug
packages.aarch64-darwin.homebrew-preflight
packages.aarch64-darwin.qwen-meeting-runtime
apps.aarch64-darwin.darwin-rebuild
apps.<system>.home-manager
devShells.<system>.default
checks.<system>.<name>
formatter.<system>
overlays.default
```

`overlays.default` ([`overlays/kcat.nix`](overlays/kcat.nix)) repariert
den Build von kcat: libserdes gegen fmt 12 auf macOS und Linux; mit GCC 16 nur
auf Linux zusätzlich avro-cpp (neue Warnungen, die avro-cpp per `-Werror` zu
Fehlern macht; das `-Werror` wird entfernt) und libserdes' mitgeliefertes
tinycthread (Konflikt mit den C23-Deklarationen von `once_flag`/`call_once` in
glibc; ein Patch nutzt dann die Versionen der C-Bibliothek).
Die Auswertung warnt, sobald nixpkgs ein anderes avro-cpp als 1.12.0 liefert;
dann prüfen, ob die beiden Korrekturen noch nötig sind.

## Shell, Git und Werkzeuge

### Git

- Global gilt die Arbeitsidentität aus [`modules/shell.nix`](modules/shell.nix).
  Repositories mit einem Remote unter `github.com/sadoMasupilami/` oder
  `github.com/sadomasupilami/`, in der Form `https://github.com/…` oder
  `git@github.com:…`, verwenden automatisch die persönliche Identität
  (`includeIf "hasconfig:remote.*.url:…"`). `ssh://`-URLs und andere
  Schreibweisen des Namens sind nicht abgedeckt.
- Neue Repositories starten auf `main`, `git pull` rebased.
- Maschinenlokale Einstellungen, die nicht veröffentlicht werden dürfen, etwa
  `http.<url>.sslVerify=false` für Kunden-GitLab-Hosts, gehören in die nicht
  verwaltete Datei `~/.config/git/local.conf` (auf dieser Maschine bereits
  angelegt). Die verwaltete Konfiguration bindet sie als Letztes ein, sie
  überschreibt also alles in `~/.config/git/config`. Fehlt die Datei, ignoriert
  git den Include. Neue Einträge dieser Art direkt dort eintragen:

```bash
git config --file ~/.config/git/local.conf <schlüssel> <wert>
```

- `~/.gitconfig` wird nicht verwaltet, muss aber als Datei bestehen bleiben:
  `~/.config/git/config` ist ein schreibgeschützter Link in den Nix Store. Ohne
  `~/.gitconfig` schreibt `git config --global` dorthin und scheitert mit
  `could not lock config file …/.config/git/config: Permission denied`;
  dasselbe gilt für Werkzeuge, die die globale Konfiguration schreiben, etwa
  `gh auth setup-git` oder die Git-Einrichtung in `gh auth login` und
  `glab auth login`. Mit vorhandener `~/.gitconfig` schreiben sie dorthin.
- git liest `~/.gitconfig` nach `~/.config/git/config`, alles darin
  überschreibt also die verwaltete Konfiguration samt `local.conf`; ein
  `user.email` dort gälte etwa sowohl für Arbeits- als auch für persönliche
  Repositories. In `~/.gitconfig` gehören deshalb nur Einträge, die solche
  Werkzeuge selbst schreiben. Identität, `init.defaultBranch` und `pull.rebase`
  kommen jetzt aus Home Manager, die nicht veröffentlichten Einstellungen für
  Kunden-Hosts aus `~/.config/git/local.conf`. Nach dem ersten Apply die
  vorhandene Datei deshalb sichern und leeren, aber nicht löschen:

```bash
cp ~/.gitconfig ~/.gitconfig.before-home-manager
: > ~/.gitconfig
```

- Prüfen, woher die Identität kommt, einmal in diesem Checkout und einmal in
  einem Arbeits-Clone:

```bash
git config --show-origin --get user.email
```

  In diesem Checkout muss die persönliche, in einem Arbeits-Clone die
  Arbeitsadresse erscheinen, jeweils aus einer Datei im Nix Store oder aus
  `~/.config/git/config`, nie aus `~/.gitconfig`.

- difftastic: `git diff`, `git show` und `git log -p` liefern normale Patches.
  Strukturelle Diffs gibt es mit `git dft` (gleiche Argumente wie `git diff`)
  oder `git difftool`.

### Kommandozeile

- `nix-locate`, der zsh-Hinweis bei unbekannten Befehlen und comma
  (`, <befehl>` startet ein Programm aus nixpkgs ohne Installation) nutzen auf
  beiden Plattformen die vorgebaute Datenbank aus dem Flake-Input
  `nix-index-database` (rund 65 MB, wird beim ersten Apply geladen). Lokal
  indexiert nichts mehr; die Datenbank wandert mit `flake.lock` und wird mit
  `nix flake update nix-index-database` oder `nix-config-update all`
  aktualisiert.
- kubeswitch heißt weiterhin `switch` und hat Tab-Vervollständigung; die
  Shell-Funktion entsteht beim Build statt bei jedem Shell-Start. kubectx und
  kubens sind entfernt: `switch` wechselt den Kontext, `switch ns` den
  Namespace.
- Die zsh-History speichert Befehle mit führendem Leerzeichen nicht.
- macOS: `ifconfig`, `netstat`, `ping`, `traceroute`, `hostname`, `whois` und
  `logger` sind wieder Apples Versionen; aus GNU inetutils ist nur `telnet`
  installiert. Linux behält die vollständigen inetutils.
- Das Nix-Profil enthält unter macOS kein `python` und kein `python3.13` mehr;
  `python3` kommt von Homebrew oder aus `/usr/bin`. Die lokalen Tests laufen
  über `nix develop` (siehe [Entwicklung, Tests und CI](#entwicklung-tests-und-ci)).
- Die Home-Manager-Manpage `man home-configuration.nix` ist abgeschaltet, weil
  sie jede Auswertung bremste und `nix flake check` warnen ließ. Optionen
  stattdessen in der
  [Home-Manager-Optionsübersicht](https://nix-community.github.io/home-manager/options.xhtml)
  nachschlagen.

## GitLab-Gruppen spiegeln

`glab-sync` ([`config/glab-sync/glab-sync`](config/glab-sync/glab-sync), auf
beiden Plattformen installiert) klont alle nicht archivierten Projekte einer
GitLab-Gruppe samt Untergruppen per HTTPS und spult vorhandene Clones per
Fast-Forward vor. Die Anmeldung läuft über `glab auth git-credential`:

```bash
glab-sync [-d DIR] [GROUP]
```

- Geklont oder aktualisiert werden nur Projekte der Gruppe selbst und ihrer
  Untergruppen. Projekte, die nur mit der Gruppe geteilt sind, erscheinen nicht;
  ein Pfad außerhalb der Gruppe wird mit einer Warnung übersprungen.
- Ohne `GROUP` ermittelt das Skript die Gruppe aus dem flachsten passenden
  Clone unterhalb des aktuellen Verzeichnisses, in einem Durchlauf bis zu
  7 Ebenen tief. Es steigt dabei nie in einen Clone hinab; Clones innerhalb des
  Arbeitsbaums eines anderen Clones werden ignoriert.
- `GITLAB_HOST` überschreibt den GitLab-Host.

## Claude-Code-Anweisungen

[`modules/claude.nix`](modules/claude.nix) verlinkt
[`config/claude/CLAUDE.md`](config/claude/CLAUDE.md) nach `~/.claude/CLAUDE.md`.
Claude Code lädt die Datei in jeder Session. Sie sagt Claude, dass fehlende Tools
per `nix shell nixpkgs#<paket>` geholt werden statt global installiert. Der
Abschnitt „Attribution“ legt fest, was in Commits, Pull Requests und anderen
veröffentlichten Texten nicht stehen darf.

## Claude-Mods

Der Flake-Input `claude-code-playground` pinnt die offiziellen Sample-Mods von
Anthropic in `flake.lock`. [`modules/claude-mods.nix`](modules/claude-mods.nix)
verlinkt `token-weather` (Kontextfenster-Prognose über dem Prompt) nach
`~/.claude/skills`. Den Sample-Mod `blast-radius` nutzt diese Config nicht.
Dazu kommt der eigene Mod `usage-meter` aus
[`config/claude-mods/usage-meter/`](config/claude-mods/usage-meter/): Er zeigt
die Rate-Limit-Fenster (5h, 7d) und die Session-Kosten in der Statuszeile, mit
`/usage-meter` als Pane mit Balken und Reset-Zeiten, und warnt per Toast ab 80 %
und 95 %. Claude Code lädt diese Ordner in jeder Session automatisch als Plugin
`<name>@skills-dir`; `~/.claude/settings.json` bleibt unangetastet.

Mods brauchen Claude Code ab 2.1.287. Dafür installiert Homebrew das Cask
`claude-code@latest` statt des langsameren Stable-Casks `claude-code`. Mods
laufen mit den eigenen Rechten und ohne Sandbox.

Der Check `claude-mods` (nur Apple Silicon) führt mit dem Claude Code aus
nixpkgs `claude plugin test` und `claude plugin validate` für `usage-meter`
sowie `claude plugin validate` für `token-weather` aus. Ein Pin-Update wird
damit automatisch validiert; die `hooks:`- und `calls:`-Zeilen der neuen
Version bleiben von Hand zu prüfen. Der Check braucht einen Build ohne
Nix-Sandbox, den Standard unter macOS. Einzeln:
`nix build -L .#checks.aarch64-darwin.claude-mods`. Update mit
`nix flake update claude-code-playground` oder `nix-config-update all`, danach
Preflight und Apply. Kontrolle mit `claude plugin list`.

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

Setup und Transkription verwenden denselben privaten Hugging-Face-Ort
(`HF_HOME=~/.local/state/qwen-meeting/huggingface`, einschließlich des
Xet-Caches), ohne Telemetrie und ohne einen gespeicherten Token zu senden.
`~/.cache/huggingface` wird weder verwendet noch gelöscht.

Eine vorhandene `~/.venvs/qwen3-asr` wird weder verändert noch entfernt und
von den neuen Wrappern nicht mehr verwendet. Modelle und Transkripte bleiben
außerhalb des Nix Stores. Die Modellrevisionen werden weiterhin separat durch
Setup verwaltet; ein Runtime-Rollback lädt oder ersetzt keine Modellgewichte.

Transkriptionsläufe verwenden danach nur lokale Modellpfade und
`HF_HUB_OFFLINE=1`:

```bash
qwen-meeting "/vollständiger/Pfad/aufnahme.m4a" [auto|de|en]
qwen-meeting --copy "/vollständiger/Pfad/aufnahme.m4a" auto
qwen-meeting -- -aufnahme-mit-bindestrich.m4a
```

Die Spracherkennung erhält immer den absoluten Pfad; Dateinamen, die mit `-`
beginnen, gehören hinter `--`. Der Ausgabeordner öffnet sich standardmäßig im
Finder. Das Transkript wird nicht ins Terminal geschrieben und nur mit
`--copy` in die Zwischenablage kopiert. Neue Verzeichnisse erhalten Modus
`0700`, neue Dateien `0600`. Vorhandene unsichere Verzeichnisse werden mit
einem Hinweis abgelehnt und nicht automatisch umgestellt. Das verwaltete
Vokabular liegt in
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

- Die Kopfzeile `name,email,tenantId` darf stehen bleiben; sie wird
  übersprungen.
- Felder dürfen in Anführungszeichen stehen (`"Doe, John"`, `""` für ein
  wörtliches Anführungszeichen).
- Fehlerhafte Zeilen (nicht geschlossenes Anführungszeichen, weniger als drei
  Felder, ungültige E-Mail-Adresse) werden mit einer Warnung übersprungen, die
  nur die Zeilennummer nennt.
- Auch ein einzelner Treffer öffnet die Auswahl, mit der Person vorausgewählt;
  ein Anruf startet erst nach Bestätigung.
- Adressen mit Nicht-ASCII-Zeichen werden in jeder Locale korrekt als UTF-8
  kodiert.

## Entwicklung, Tests und CI

`nix develop` stellt auf macOS und Linux alle Werkzeuge bereit, die die Checks
und lokalen Tests aufrufen, unter anderem bash, git, jq, Python 3.13 mit mypy,
uv, zsh, nixfmt, shellcheck, statix, deadnix und pre-commit.

Lokal:

```bash
nix flake check --all-systems --no-build
nix flake check -L --keep-going
nix develop -c bash tests/run-local-tools-tests.sh
nix develop -c bash tests/nix-config-helpers.sh
nix develop -c bash tests/nix-gc-recent.sh
nix develop -c bash tests/glab-sync.sh
nix develop -c bash tests/ssh-config-reconcile.sh
nix fmt -- --check
git diff --check
```

`nix flake check -L --keep-going` baut alle Checks des eigenen Systems und
meldet alle defekten Derivations in einem Lauf. Einzelne Checks:
`nix build -L .#checks.<system>.<name>`.

- Auf beiden Systemen: `evaluation`, `formatting` (nixfmt), `nix-lint` (statix
  und deadnix über alle `.nix`-Dateien), `python-types` (`mypy --strict` für
  `config/qwen-meeting/runtime/fetch-models.py` und `tests/*.py`; neue
  Python-Tests müssen das bestehen), `shell` (shellcheck ab Schweregrad
  `warning` für alle bash- und sh-Skripte unter `config/`, `tests/` und
  `.github/hooks/`, `zsh -n` für zsh-Skripte, mit denselben Regeln wie der
  pre-commit-Hook; meldet alle Fehler eines Laufs) und `nix-config-helpers` (die
  Testskripte `nix-config-helpers.sh`, `nix-gc-recent.sh`, `glab-sync.sh` und
  `ssh-config-reconcile.sh`).
- Nur Apple Silicon: `darwin` (das komplette System), `homebrew-preflight`,
  `local-private-tools` (`tests/run-local-tools-tests.sh`),
  `qwen-meeting-runtime` und `claude-mods`.
- Nur Linux: `linux-home-manager`.

### pre-commit

Einmal pro Checkout:

```bash
nix develop -c pre-commit install
```

Das installiert den pre-commit- und den commit-msg-Hook aus
[`.pre-commit-config.yaml`](.pre-commit-config.yaml) nach `.git/hooks`. Es
scheitert, wenn ein globales `core.hooksPath` gesetzt ist; diese Konfiguration
setzt bewusst keines. Alle Hooks auf einmal:
`nix develop -c pre-commit run --all-files`.

- Die Lint-Hooks (nixfmt, statix, deadnix sowie shellcheck und `zsh -n` über
  `.github/hooks/check-shell.sh`) brauchen die Werkzeuge aus `nix develop`.
  Commits daher aus `nix develop` heraus erstellen, sonst melden die Hooks
  fehlende Programme.
- Die commit-msg-Hooks brauchen keine Werkzeuge. Sie verlangen einen Betreff der
  Form `type(scope)!: description` mit `feat`, `fix`, `refactor`, `perf`,
  `docs`, `chore`, `test`, `ci`, `build`, `style` oder `revert` und lehnen
  Co-Author-Trailer und „Generated with …“-Fußzeilen von Code-Assistenten ab.
  Merge-Commits, `Revert "…"` sowie `fixup!`, `squash!` und `amend!` bleiben
  erlaubt.
- Notfall: `git commit --no-verify`.

### GitHub Actions

Der Workflow „Flake checks“
([`.github/workflows/flake-checks.yml`](.github/workflows/flake-checks.yml))
läuft bei Pushes auf `main`, bei Pull Requests und manuell. Branch-Pushes laufen
nicht doppelt, sie sind über ihren Pull Request abgedeckt.

- „Evaluate every system“ (`ubuntu-24.04`) wertet mit
  `nix flake check --all-systems --no-build` alle Systeme aus.
- „Linux Home Manager and static checks“ (`ubuntu-24.04`) und „Apple Silicon
  nix-darwin and static checks“ (`macos-26`) führen jeweils
  `nix flake check -L --keep-going` aus. Jeder Runner baut damit automatisch
  jeden Check seines Systems aus `flake.nix`; neue Checks brauchen keine
  Workflow-Änderung.
- CI hat nur `contents: read` und führt keine Systemaktivierung,
  Homebrew-Upgrades oder Zap-Bereinigung aus.
- Nix-Store-Cache: `nix-community/cache-nix-action` im GitHub-Actions-Cache,
  ohne Secret. Der Schlüssel besteht aus Betriebssystem und Hash von
  `flake.lock`. Nur Pushes auf `main` speichern; Pull Requests und der
  Wochenlauf stellen nur wieder her. Vor dem Speichern wird der Store auf 6 GB
  (Linux) bzw. 8 GB (macOS) gekürzt, die aktuellen Check-Ergebnisse bleiben
  dabei erhalten. Der erste Lauf nach jeder Änderung von `flake.lock` baut ohne
  exakten Cache-Treffer und dauert entsprechend länger.
- Alle Actions sind auf Commit-SHAs gepinnt. Dependabot
  ([`.github/dependabot.yml`](.github/dependabot.yml)) schlägt einmal pro Woche
  einen gebündelten `ci:`-PR für Action-Updates vor, jeweils frühestens sieben
  Tage nach einem Release.

Der wöchentliche Frühwarnlauf „Flake input update“
([`.github/workflows/flake-input-update.yml`](.github/workflows/flake-input-update.yml))
läuft montags um 05:17 UTC und manuell. Er aktualisiert im Runner alle
Flake-Inputs außer den `homebrew-*`-Taps, committet nichts und führt dieselben
Checks mit dem aktualisierten Lock aus. Die Job-Zusammenfassung zeigt, welche
Inputs sich bewegt haben. Echte Updates laufen weiterhin über
`nix-config-update` mit lokalem Preflight. Die Taps sind ausgenommen, weil nur
der lokale Preflight gegen `/opt/homebrew` sie beurteilen kann; `nix-homebrew`
selbst wird mit aktualisiert. GitHub deaktiviert geplante Workflows eines
öffentlichen Repositorys nach 60 Tagen ohne Aktivität; dann im Actions-Tab
wieder aktivieren.

Den Status von `main` zeigt das Badge oben. Damit ein roter Lauf auffällt, in
den persönlichen GitHub-Einstellungen unter Notifications → Actions „Only
notify for failed workflows“ aktivieren und prüfen, dass Dependabot-
Versionsupdates für das Repository nicht deaktiviert sind.

## Bewusst akzeptierte Risiken und erhaltene Integrationen

- Der lokale Benutzer bleibt ein vertrauenswürdiger Nix-Benutzer und Nix-
  Sandboxing bleibt deaktiviert. Diese Determinate-Nix-Einstellungen stehen in
  [`modules/nix-settings.nix`](modules/nix-settings.nix); als Binary Caches
  sind nur `cache.nixos.org` und `devenv.cachix.org` eingetragen.
- Die macOS Application Firewall und Stealth Mode bleiben deaktiviert. Das ist
  ein bewusst akzeptiertes Restrisiko; die Konfiguration aktiviert sie nicht.
- Minutes bleibt als Cask `silverstein/tap/minutes` erhalten. Die GUI erhält
  weiterhin `MINUTES_FFMPEG` aus dem Nix-Benutzerprofil.
- Minutes und Muesli bleiben beide bewusst installiert: Beide nehmen Meetings
  lokal auf, Muesli deckt zusätzlich Diktat ab. `qwen-meeting` nimmt nicht
  auf, sondern transkribiert vorhandene Aufnahmen nach
  `~/Documents/Muesli-Transcripts` neu.
- WireGuard bleibt als App-Store-App deklariert.
- Die SSH-Reconciliation
  ([`config/ssh/reconcile-ssh-config.awk`](config/ssh/reconcile-ssh-config.awk))
  behält dynamische Coder-Blöcke unverändert und verwaltet nur den stabilen
  Include-Teil. Der verwaltete Include bleibt stehen, wenn er vor der ersten
  `Host`- oder `Match`-Zeile steht, sonst wird er oben eingefügt oder dorthin
  verschoben. Der DevPod-Include und `SetEnv TERM=xterm-256color` in
  Inline-`Host *`-Blöcken werden entfernt. `~/.ssh/config` wird nur bei
  tatsächlich geändertem Inhalt neu geschrieben. Modus `0700` setzt die
  Aktivierung nur, wenn sie `~/.ssh` anlegt; ein bestehendes Verzeichnis
  bleibt, wie es ist.
- `mas` und Docker Credential Helpers kommen ausschließlich aus Nix.
- Persönliche Transkripte, vorhandene CSV-Rechte und das alte Teams-Log werden
  ohne separate Freigabe weder migriert noch gelöscht.

Weitere manuelle Einrichtung: Bartender-Lizenz. UltraStar Deluxe ist kein
deklarierter Cask mehr: Homebrew hat ihn am 2026-09-01 deaktiviert, weil er die
Gatekeeper-Prüfung nicht besteht. Die freigegebene Bereinigung zappt die
installierte Kopie; wer die App behalten will, installiert sie danach manuell
von [usdx.eu](https://usdx.eu/). Pakete lassen sich über
[search.nixos.org](https://search.nixos.org) suchen.
