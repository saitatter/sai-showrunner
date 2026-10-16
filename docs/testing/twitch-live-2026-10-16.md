# Twitch — verificare live, 16 octombrie 2026

Autorizarea contului prin aplicația Public a reușit. Client ID-ul, identitatea
tokenului și cele 20 de permisiuni au fost validate la Twitch. Tokenul și ID-urile
numerice au fost salvate în `connections.local.yml`, ignorat de Git, și în
profilul izolat de test. Nu este necesar Client Secret pentru acest flux.

Au trecut citirea dashboardului canalului, setările chatului, urmăritorii și
crearea tuturor celor **21 de abonamente EventSub**, fără respingeri.
Citirea programului de reclame a fost acceptată de API. Citirea recompenselor
prin nodul compilat a primit `403`; această funcție rămâne nevalidată pentru
canalul configurat și trebuie verificată eligibilitatea lui.
Acceptarea unui abonament nu validează producerea și recepția evenimentului.
Pentru primirea efectivă a unui mesaj și executarea grafului se folosește proba
manuală descrisă mai jos. Nu au fost trimise mesaje din cont și nu au fost
executate reclame, raiduri, sancțiuni sau modificări ale canalului.

Defecte corectate în această rundă:

- deschiderea prin Explorer putea ignora URL-ul lung de autorizare; se folosește
  acum handlerul URL Windows prin Start-Process, cu parametrul citat;
- testele OAuth utilizau portul autentificării reale; folosesc acum un port
  efemer și verifică separat adresa fixă a produsului;
- butonul Authorize din setările generice Twitch cerea încă secret și folosea
  fluxul vechi; utilizează acum serviciul de cont Public;
- identitatea Twitch returnează `display_name` și `broadcaster_type`; acestea
  sunt convertite pentru modelul de cont;
- lipseau scope-urile `channel:moderate` și `bits:read`;
- shoutout primit necesita și `moderator_user_id`; banul folosește condiția
  broadcasterului și distinge timeout-ul prin `ends_at`/`is_permanent`;
- mesajele EventSub au un obiect `message.text`, nu un șir direct;
- `channel.ad_break.end` și `channel.ad_schedule` nu sunt abonamente EventSub
  documentate: finalul reclamei este derivat din început/durată, iar programul
  reclamelor este citit periodic din Helix. Aceste două fluxuri au teste locale,
  nu o verificare cu reclame reale;
- nodurile fără ID explicit foloseau șiruri goale; transportul configurat
  completează broadcaster/sender/moderator din setări, păstrând suprascrierile;
- un GET din nodurile provider scria corpul `{}` și eșua în HttpClient înainte
  să ajungă la Twitch; GET/HEAD nu mai trimit acel corp;
- runnerul YAML activa interceptarea HTTP din Flutter test, blocând conexiunile
  reale; această inițializare a fost eliminată din runnerul fără interfață.
- nodul de variabile încerca să modifice harta nemodificabilă din snapshot-ul
  registry-ului; contextul păstrează acum propria copie. Același graf de test
  este verificat local pentru mesaje potrivite și nepotrivite.

Verificare finală: **707 teste trecute**, trei probe live sărite fără opt-in,
analiză statică fără probleme. Raportul live fără mesaj manual este în
`packages/showrunner-flutter/.tmp/twitch-proof-1792120719295/report.json`.
Proba manuală ulterioară a trecut: mesajul `showrunner-test` trimis de utilizator
a fost recepționat prin EventSub, decodat de contractul triggerului Twitch și
procesat de graful compilat; condiția a selectat ramura corectă, iar nodul de
variabile a păstrat textul mesajului. Raportul este în
`packages/showrunner-flutter/.tmp/twitch-proof-1792121107165/report.json`,
cu `liveChatTriggerGraph: PASS`. Listenerul a fost oprit la finalul probei.

## Chat → graf → overlay → OBS portabil: PASS

Proba completă a trecut cu mesajul real trimis de utilizator: EventSub →
contractul triggerului → condiția din graful compilat → variabilă → acțiunea
`overlays.pushChatMessage` → WebSocket-ul aplicației → rendererul real în browser
source OBS. Captura OBS arată `SaiTatter` și `showrunner-test`.

Raportul este în
`packages/showrunner-flutter/.tmp/chat-overlay-proof-1792121400628/report.json`.
[Înainte](twitch-overlay-2026-10-16/before.png) și
[după](twitch-overlay-2026-10-16/after.png) sunt capturi din sursa OBS, nu mockup-uri.
Testul verifică schimbarea PNG-ului; rezultatul a fost inspectat și vizual.

Testul refuză rularea dacă procesul care ascultă pe 4456 nu este executabilul
`.tmp/obs-portable/bin/64bit/obs64.exe` din workspace. Creează numai un overlay,
o scenă și o sursă temporare; restaurează scena anterioară și elimină scena de
test la final. Nu modifică profiluri, rezoluții sau ieșiri OBS.

Pentru repetare, pornește copia OBS portabilă pe portul 4456 și compilează
rendererul dacă sursele lui s-au schimbat:

```powershell
node .yarn/releases/yarn-4.1.0.cjs overlay:build
./scripts/test-live-twitch-overlay.ps1
```

După `READY`, trimite din nou `showrunner-test` în chat. Proba așteaptă patru
minute. `-LocalPrecheck` verifică graful, overlay-ul și captura OBS cu un mesaj
local, fără să valideze recepția unui eveniment Twitch real. Raportul distinge
explicit sursa `local fixture` de `live Twitch EventSub`.

Contractele și permisiunile au fost verificate în
[documentația EventSub](https://dev.twitch.tv/docs/eventsub/eventsub-subscription-types/)
și [validarea tokenurilor](https://dev.twitch.tv/docs/authentication/validate-tokens/).

## Repetare

Din rădăcina repo, pentru verificările fără modificări ale canalului:

```powershell
./scripts/test-live-twitch.ps1
```

Pentru proba mesaj real → trigger Twitch → condiție în Graph Editor → variabilă:

```powershell
./scripts/test-live-twitch.ps1 -WaitChatSeconds 180
```

După mesajul `READY`, scrie exact `showrunner-test` în chatul canalului
configurat. Testul verifică textul decodat de contractul triggerului și rezultatul
motorului compilat. Dacă mesajul nu ajunge în interval, proba expiră; nu este
marcată ca funcțională automat. Raportul fără tokenuri este salvat în
`packages/showrunner-flutter/.tmp/twitch-proof-*/report.json`.

Nu rula două probe EventSub simultan cu aceeași configurație: Twitch poate
respinge abonamentele duplicate cât timp primul listener este încă activ.
Funcțiile cu efecte publice și cele care cer un stream live/monetizare rămân
pentru o rundă separată, cu ținte de test. OBS-ul principal nu este folosit;
viitoarele teste OBS folosesc exclusiv copia portabilă.
Configurația locală OBS de test indică portul 4456 al copiei portabile;
scenariul vechi care citea o sursă din instanța principală a fost dezactivat.
