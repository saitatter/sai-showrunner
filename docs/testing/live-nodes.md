# Testarea funcțională a nodurilor

Catalogul generat din manifestele aplicației are **33 de pluginuri, 166 de acțiuni și 51 de triggeri**, inclusiv triggerii disponibili numai când există event hub. [Inventarul JSON](node-catalog.json) enumeră ID-urile exacte, configurațiile, rezultatele și resursele.

Toate cele 217 tipuri de noduri trec testul de inserare și salvare/redeschidere. Acesta este un test de contract al editorului, nu dovada executării fiecărei integrări live. Testele de runtime și plugin folosesc și servicii simulate. Verificările locale suplimentare execută VM-ul de producție cu HTTP real și OBS WebSocket real către servere locale de test; testul Discord verifică citirea unui răspuns transmis în bucăți, fără să trimită mesaje pe Discord.

## Fișierul de completat

Editează `packages/showrunner-flutter/test/live/connections.local.yml`. Este ignorat de Git. Șablonul versionat este [connections.example.yml](../../packages/showrunner-flutter/test/live/connections.example.yml); conține setările tuturor integrărilor și câte un scenariu pentru fiecare acțiune. Numai conversia locală este activă inițial.

1. Adaugă ID-ul integrării în `enabled_plugins`.
2. Completează blocul său din `plugin_settings` și resursele de test necesare.
3. Completează `config` pentru acțiunea dorită și schimbă scenariul în `enabled: true`. Valorile generate sunt puncte de pornire, nu configurații valide pentru toate serviciile.
4. Adaugă `expect` cu câmpurile care trebuie să apară în rezultat; comparația permite câmpuri suplimentare. Fără `expect`, se verifică doar finalizarea grafului.

Exemplu pentru un secret furnizat din mediul procesului:

```yaml
plugin_settings:
  obs:
    host: 127.0.0.1
    port: 4455
    password: env:SHOWRUNNER_TEST_OBS_PASSWORD
```

Nu este nevoie să trimiți parolele în conversație. Poți pune valorile în fișierul local sau în variabile de mediu. Runnerul nu afișează configurațiile și rezultatele providerilor în log.

Din rădăcina repository-ului:

```powershell
.\scripts\test-live-nodes.ps1 -ConfigPath .\packages\showrunner-flutter\test\live\connections.local.yml
```

Pentru BLE, input, audio sau alte funcții care cer pluginurile native Windows:

```powershell
.\scripts\test-live-nodes.ps1 -ConfigPath .\packages\showrunner-flutter\test\live\connections.local.yml -Native
```

Ambele moduri au fost verificate cu scenariul local de conversie. Runnerul folosește registrul configurat și motorul de graf din aplicație, într-un profil temporar separat, pe care îl elimină la final. ID-urile de resurse din `config` trebuie să corespundă secțiunii `resources` din același fișier. Profilul tău normal nu este importat automat. Scenariile se execută în ordine; o eroare oprește runda.

Activarea unui scenariu execută acțiunea reală. De exemplu, un scenariu de chat poate trimite mesajul configurat, iar unul de streaming poate porni/opri transmisia. Toate aceste scenarii sunt dezactivate în șablon.

## Datele necesare pentru conexiuni

| Integrare | Ce trebuie completat/pregătit |
| --- | --- |
| OBS | OBS pornit, WebSocket activ, host, port (implicit 4455), parolă; numele scenei/sursei/filtrului pentru scenariile respective. `getInputSettings` este un prim test de citire. |
| Aitum / ADVSS | Aceeași conexiune OBS și extensia respectivă instalată, plus numele macro-urilor/vertical scenes folosite. |
| Twitch | Client ID, Client Secret dacă folosești refresh, access token, refresh token, broadcaster ID și moderator/sender ID. ID-ul expeditorului trebuie să corespundă tokenului. Pentru început se poate activa `listChannelPointRewards`. Unele acțiuni cer canal afiliat/partener sau drepturi de moderator. |
| YouTube | Client ID/Secret, access/refresh token și un `liveChatId` de test. Acțiunile expuse sunt de scriere/moderare; testele live trebuie pregătite pe un chat de test. |
| Discord | O resursă `DiscordWebhook`, cu URL-ul webhook-ului unui canal de test; opțional fișiere locale pentru atașamente. |
| Bluesky | Handle/DID, app password și service URL; postarea live necesită contul ales pentru test. |
| DonorDrive | API base URL, participant ID și evenimente/donații de test pentru triggeri. |
| Govee | API key și ID/model de dispozitiv; `listDevices` este primul test de citire. |
| Philips Hue | IP-ul bridge-ului și application key; `listLights`/`listGroups` sunt teste de citire. |
| Elgato Key Light | IP și port (implicit 9123), tip/număr de lumini. |
| TP-Link/Kasa | IP, port (implicit 9999), dispozitiv accesibil în LAN. |
| LIFX | IP, port (implicit 56700), eventual MAC target. |
| Twinkly | IP-urile și dispozitivele din resursele de lumini, accesibile în LAN. |
| Wyze | Key ID, API key, access/refresh token și ID-urile dispozitivelor. |
| IoT generic | Resurse `Light`/`Plug` cu providerul corect și datele necesare acelui provider. |
| Minecraft/RCON | Resursă `RCONConnection`: host, port, parolă; un server de test și comanda dorită. |
| VoiceMod | Aplicația pornită, host, port (implicit 59129), ID-uri de voci disponibile. |
| Heart Rate | Pentru hardware: senzor BLE, Bluetooth și device ID. Simularea se poate verifica fără senzor, în modul nativ. |
| Sound / TTS | Fișiere locale, dispozitiv de ieșire și/sau resurse TTSVoice/TTSVoiceProvider; unele voci sunt locale, altele cer configurația providerului. |
| HTTP | URL, metodă, headers/auth și payload pentru endpointul de test. |
| Remote / Dashboards / SpellCast | Host/port sau serviciul de semnalizare/cloud configurat, tokenurile relevante și un al doilea client pentru testarea interacțiunilor. |
| ShowRunner / Variables / Random / Time / Overlays / Stream Plans | În principal resurse locale și ID-uri de cozi/automatizări/variabile/widgeturi/planuri. Pentru apariția efectivă în OBS este necesară și sursa Browser; pentru Sound/Input/OS contează permisiunile și mediul Windows. |

Pentru Twitch, aplicația cere acum și scope-urile moderne `user:read:chat` și `user:write:chat`, pe lângă permisiunile existente. Conturile autorizate anterior trebuie reconectate pentru noile permisiuni. Cerința de trimitere și potrivirea dintre sender ID și token sunt descrise în [documentația Twitch Send Chat Message](https://dev.twitch.tv/docs/api/reference/#send-chat-message). YouTube solicită în aplicație `youtube.readonly` și `youtube.force-ssl`.

## Ce mai trebuie validat live

Testele nu marchează automat toate acțiunile ca funcționale live. Catalogul păstrează explicit `liveStatus: pending`. Pentru triggeri trebuie generat evenimentul real: mesaj chat, follow/subscription, eveniment OBS, cerere HTTP, puls de la senzor etc. Runnerul YAML execută acțiuni; nu pretinde că a verificat livrarea tuturor celor 51 de triggeri live.

Validarea acestei runde: **698 de teste automate trecute**, un test live omis intenționat când lipsește configurația, plus teste native Windows pentru scenariul YAML local, fluxul editorului și deschiderea documentului în aplicația completă. Analiza statică și verificările vizuale sunt separate de validarea conturilor reale.

Propunerea pentru prima rundă este: **OBS + Twitch + un overlay de test**. Sunt suficiente datele OBS și OAuth/ID-urile Twitch de mai sus. După aceea putem adăuga serviciile și dispozitivele pe care le folosești efectiv.

Regenerarea catalogului și șablonului (nu modifică fișierul local):

```powershell
cd packages/showrunner-flutter
flutter test test/live/catalog_contract_test.dart --dart-define=SHOWRUNNER_EXPORT_CATALOG=true
```
