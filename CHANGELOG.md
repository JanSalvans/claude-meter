# Notes de versió · Changelog

La més nova a dalt. Newest first.

## 1.1.1 · 08/10/2026

**Català**

- Corregit: l'app ja no demana la contrasenya del clauer cada dos per tres. Ara llegeix la credencial amb l'eina `security` del sistema, que no perd el permís en recompilar l'app ni quan Claude Code renova el token.

**English**

- Fixed: the app no longer keeps asking for the keychain password. It now reads the credential through the system `security` tool, which does not lose its permission when the app is rebuilt or when Claude Code refreshes the token.

## 1.1.0 · 26/09/2026

**Català**

- La bateria de la barra de menú passa a ser una barra horitzontal de color, amb el percentatge al costat.
- El desplegable diu quin dia i a quina hora es restableix cada finestra ("es restableix demà a la 1.00 h") i quant falta ("falten 4 h 13 min"). El compte enrere es recalcula cada cop que s'obre el menú.
- Corregit: les files del desplegable sortien tallades, amb l'última línia aixafada.
- Corregit: els títols "sessió" i "setmana" es podien tallar.
- Corregit: el text de reinici deia "a les les".
- Verificat el format real de l'endpoint d'ús, amb una prova nova.

**English**

- The menu bar battery is now a horizontal colour bar, with the percentage next to it.
- The dropdown shows the day and time each window resets and how long is left. The countdown is recalculated every time the menu opens.
- Fixed: dropdown rows were cut off, with the last line squashed.
- Fixed: the "session" and "week" titles could be clipped.
- Fixed: a duplicated word in the reset text.
- Checked the real shape of the usage endpoint, with a new test.

## 1.0.0 · 26/09/2026

Primera versió: percentatge d'ús a la barra de menú, desplegable amb sessió, setmana i Opus, avisos al 25, 50 i 75 %, endpoint oficial amb estimació local de reserva.

First release: usage percentage in the menu bar, dropdown with session, week and Opus, alerts at 25, 50 and 75 %, official endpoint with a local estimate as fallback.
