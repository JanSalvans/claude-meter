<h1 align="center">Claude Meter</h1>

<p align="center">
  El teu ús de Claude a la barra de menú de macOS, amb una barra de color.<br>
  <a href="#english">English below</a>
</p>

---

## Què fa

Per saber quants crèdits et queden a Claude has d'obrir Claude Code i escriure `/usage`. O sigui que normalment descobreixes que has cremat la finestra quan ja te l'has cremada.

Claude Meter posa aquest número a la barra de menú, al costat de la bateria i el wifi:

```
▰▰▱ 43%
```

La barra i el percentatge són els de la finestra de sessió (5 h). La barra canvia de color amb l'ús: verd, groc, taronja i vermell. En clicar-hi s'obre el detall:

- **sessió**: percentatge, barra, dia i hora del restabliment i quant falta ("es restableix demà a la 1.00 h, falten 4 h 13 min")
- **setmana**: el mateix per a la finestra de 7 dies
- **setmana, opus**: només si el teu pla en té una de separada
- origen de les dades i quan es van llegir

I t'avisa amb una notificació del sistema en creuar el **25 %, el 50 % i el 75 %** de la finestra de sessió. Cada llindar salta un sol cop per finestra, i es rearmen sols quan la finestra es reinicia. Si en obrir l'app ja estàs per sobre d'un llindar, no rebràs l'allau d'avisos endarrerits.

## D'on surten les dades

Claude Meter llegeix el mateix que llegeix el `/usage` de Claude Code: fa una petició a l'endpoint OAuth d'Anthropic amb el token que Claude Code ja té desat al teu clauer. El token no surt mai de la teva màquina, no es registra enlloc i l'app no té cap servidor al darrere.

Si l'endpoint no respon o el token ha caducat, l'app cau a una **estimació local**: suma els tokens dels transcripts de `~/.claude/projects` dins de les finestres de 5 h i 7 dies. És aproximada, i quan està en aquest mode el percentatge surt amb una titlla al davant (`~43%`) i el menú ho diu clarament.

## Requisits

- macOS 13 o superior
- Claude Code instal·lat i amb la sessió iniciada (és d'on surt el token)
- Swift 6 de les Command Line Tools de Xcode. **No cal Xcode**

## Instal·lació

```bash
git clone https://github.com/JanSalvans/claude-meter.git
cd claude-meter
./Scripts/bundle.sh --open
```

L'script compila, munta `Claude Meter.app`, la signa amb identitat ad hoc i la instal·la a `~/Applications`.

El primer cop macOS et demanarà dues coses:

1. **Accés al clauer**, per llegir la credencial de Claude Code. Tria "Permet sempre" o t'ho preguntarà a cada consulta.
2. **Permís de notificacions**, per als avisos del 25, 50 i 75 %.

Per obrir-la sola en iniciar sessió, activa-ho a Preferències dins del menú de l'app.

## Desenvolupament

```bash
swift build          # compila
./Scripts/test.sh    # 41 proves en 4 suites
./Scripts/bundle.sh  # munta i instal·la l'app
```

`Scripts/test.sh` existeix perquè amb Command Line Tools i sense Xcode, SwiftPM no troba sol el `Testing.framework`: l'script li passa els camins i els rpath que li falten.

Per provar els avisos sense esperar cinc hores:

```bash
"/Users/$USER/Applications/Claude Meter.app/Contents/MacOS/ClaudeMeter" --simulate 30,55,80
```

### Estructura

| carpeta | què hi ha |
|---|---|
| `Sources/ClaudeMeterCore/Usage` | clauer, client de l'endpoint, estimador local i poller |
| `Sources/ClaudeMeterCore/UI` | barra d'ús, barra de menú, desplegable i preferències |
| `Sources/ClaudeMeterCore/Notifications` | llindars del 25, 50 i 75 % |
| `Sources/ClaudeMeter` | arrencada i cablejat |
| `Scripts` | compilació, proves i sonda de l'endpoint |

El format de resposta de l'endpoint no està documentat per Anthropic, o sigui que `UsagePayloadParser` és deliberadament tolerant: busca les claus de manera recursiva i normalitza percentatges i dates vinguin com vinguin. Si el format canvia, és l'únic lloc que s'ha de tocar. `Scripts/probe-usage.sh` imprimeix l'estructura de la resposta real sense ensenyar el token.

## Avís

Projecte personal, no oficial i sense cap relació amb Anthropic. Fa servir un endpoint intern que pot canviar sense previ avís.

## Llicència

MIT.

---

<h2 id="english">English</h2>

### What it does

To check how much Claude usage you have left, you have to open Claude Code and type `/usage`. Which means you usually find out you burned through your window after you already burned through it.

Claude Meter puts that number in the macOS menu bar, next to the battery and the wifi:

```
▰▰▱ 43%
```

The bar and the percentage show your session window (5 h), and the bar turns green, yellow, orange and red as you use it. Click it for the breakdown: session, week, and the separate Opus weekly window if your plan has one, each with a progress bar, the day and time it resets, and how long is left.

It also sends a system notification when you cross **25 %, 50 % and 75 %** of the session window. Each threshold fires once per window and re-arms itself when the window resets. If you are already past a threshold when the app starts, you will not get a backlog of stale alerts.

### Where the data comes from

Claude Meter reads exactly what Claude Code's `/usage` reads: it calls Anthropic's OAuth usage endpoint using the token Claude Code already stores in your keychain. The token never leaves your machine, is never logged, and there is no server behind this app.

If the endpoint fails or the token has expired, the app falls back to a **local estimate** built from the token counts in your `~/.claude/projects` transcripts. That estimate is approximate, so the percentage shows a tilde (`~43%`) and the menu says so.

### Requirements

macOS 13+, Claude Code installed and signed in, and Swift 6 from the Xcode Command Line Tools. Xcode itself is not required.

### Install

```bash
git clone https://github.com/JanSalvans/claude-meter.git
cd claude-meter
./Scripts/bundle.sh --open
```

macOS will ask for keychain access (choose "Always Allow") and notification permission on first launch.

### Development

```bash
swift build
./Scripts/test.sh    # 41 tests across 4 suites
./Scripts/bundle.sh
```

Simulate the alerts without waiting five hours:

```bash
"/Users/$USER/Applications/Claude Meter.app/Contents/MacOS/ClaudeMeter" --simulate 30,55,80
```

### Disclaimer

Personal project, unofficial, not affiliated with Anthropic. It relies on an internal endpoint that may change without notice.

### License

MIT.
