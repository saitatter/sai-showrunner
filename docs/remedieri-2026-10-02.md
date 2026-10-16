# Remedieri și comparație UI — 2 octombrie 2026

Acest raport urmărește cele 25 de puncte din [auditul inițial](audit-2026-10-02.md). Verificarea inițială folosește Windows, Flutter 3.44.0 / Dart 3.12.0 și Node 22. Modificările, aflate atunci în working tree, au fost ulterior incluse în commituri; ultimele schimbări de infrastructură și dovezile auditului au fost comise pe 16 octombrie 2026. Nu au fost publicate prin această intervenție.

## Remedieri

| Audit | Modificare și verificare |
| --- | --- |
| A01 | Assets și media folosesc containment canonic, inclusiv pentru strămoși existenți și junction-uri Windows. Traversal-ul URL și identificatorii invalizi sunt respinși. Serverul ascultă implicit doar pe loopback. Teste de persistență și rețea. |
| A02 | Updaterul respinge directoare suprapuse în ambele sensuri, rădăcini de disc și strămoși reparse în helperul PowerShell. Instalarea și rollback-ul au fost executate local cu un bundle real. |
| A03 | Encoder YAML comun, recursiv, cu chei și scalari citați corect. Testele verifică tipuri, multiline, colecții goale și valori null după round-trip. |
| A04 | Resursele YAML păstrează configurația compatibilă cu formatul vechi; starea este persistată în `.state/<id>.json`, eliminată când devine goală și curățată la ștergere. |
| A05 | Scrierile au temporare unice și serializare per fișier; operațiile read/modify/write relevante folosesc aceeași protecție. Download-ul updaterului serializează accesul la `.part`. Teste de concurență. |
| A06 | Validator comun de identificatori și containment pentru resource repository, queue config, secret settings și data service. Testele includ ieșirea prin junction și căi către fișiere încă inexistente. |
| A07 | Shutdown remote idempotent și notificări oprite după dispose. Teste pentru dispose în timpul funcționării și callback-uri târzii. |
| A08 | Teardown închide peer/channel și termină apelurile pending; send failure trece prin cleanup. Stop încearcă toate operațiile de curățare chiar dacă una eșuează. |
| A09 | Repository-ul raportează separat intrările corupte; catalogul afișează avertizare și explicație. Erorile DPAPI ajung în log cu stack; salvarea refuză suprascrierea unui fișier de secrete care nu poate fi decriptat. |
| A10 | Exit code verificat imediat după comenzile native din CI, nightly și packaging. Release-ul depinde de verificările Windows înainte de publicare. |
| A11 | Contract parity blochează contracte absente și regresii; product parity cere dovezi în fișiere existente, cu marker verificabil. Meniurile Edit/View au fost completate. Teste ale gate-ului. |
| A12 | Gate vizual separat, cu baseline Flutter versionat și prag de diferență. Captura nouă trece; captura Flutter anterioară ajustărilor e respinsă. Comparația Electron/Flutter rămâne o comparație între implementări, nu un test de identitate pixel cu pixel. |
| A13 | Typecheck real pentru toate cele 10 workspaces menținute care conțin TypeScript. Schema și bibliotecile shared folosesc configurația comună. |
| A14 | Registry-ul de editoare a fost împărțit în module pe resurse, inclusiv canvas, inspector și configurarea overlay. Modelul overlay face snapshot-uri independente și păstrează câmpurile necunoscute și starea. Testele overlay au propriul fișier. |
| A15 | Fluxurile de documente, proiect și smoke au fost extrase din `main.dart`. Manager separat pentru resurse și dirty state; Save All, închiderea taburilor și ieșirea cer salvare când e necesar. Close Others elimină și snapshot-urile abandonate. |
| A16 | Programul graph, compilerul și VM-ul sunt module distincte; fabrica de prototipuri a fost extrasă din adaptor. Interpreterul rămâne oracle pentru teste. Părțile adaptorului care împart stare rămân în aceeași bibliotecă Dart. |
| A17 | Înregistrările UI fără dependențe de servicii folosesc o fabrică comună; înregistrările cu servicii păstrează dependențele explicite. Testul catalogului verifică protejarea setărilor secrete. |
| A18 | Politică HTTP comună pentru timeout, limite și erori; retry limitat la GET/HEAD după 429. Updaterul are limite separate pentru metadata și artefacte. Teste pentru răspunsuri mari, retry și conexiuni blocate. |
| A19 | Boundary de erori, limită de body, deadline și verificare Origin înainte de upgrade WebSocket. Cererile întrerupte nu produc erori asincrone necontrolate. Accesul LAN necesită `allowRemoteAccess`; acest opt-in nu introduce autentificare prin token. |
| A20 | Log JSONL persistent cu rotație, stack traces și redacția secretelor; capturarea erorilor Flutter și platformă este instalată devreme, iar shutdown face flush. Teste pentru scriere, redacție și rotație. |
| A21 | Workspace-ul nefolosit `showrunner-ws-rpc`, codul și referințele sale au fost eliminate. |
| A22 | Configurațiile Electron/ESLint și launch scaffolding devenite inutile au fost eliminate, împreună cu manifestele părinte fără rol. Runtime-ul browser pentru OBS, datele utilizatorului și referința pentru comparații au fost păstrate. |
| A23 | Node 22 aliniat în setup și CI, wildcard-uri înlocuite cu versiunile deja rezolvate, lockfile verificat immutable. Gate pentru concordanța versiunii aplicației/updaterului/package-ului. README și instrucțiunile de branch protection actualizate. Proveniența licențelor este documentată separat. |
| A24 | Teste permanente pentru defectele reproduse, snapshot-uri overlay și invalidarea cache-ului. Smoke în Chrome real verifică DOM, compilarea shaderului WebGL, update, eliminare și stop. Integrarea Windows și smoke-ul bundle-ului au fost executate. |
| A25 | Cache-ul programului ignoră pozițiile de layout, păstrând câmpurile care influențează programul și metadata. Teste pentru mutare fără recompilare și redenumire cu recompilare. Nightly produce cinci măsurători/scenariu, mediană și p95, cu artefacte păstrate 30 de zile. |

Implementările principale sunt în [persistence](../packages/showrunner-flutter/lib/persistence/), [HTTP policy](../packages/showrunner-flutter/lib/services/http_policy.dart), [document commands](../packages/showrunner-flutter/lib/app/showrunner_document_commands.dart), [overlay editor](../packages/showrunner-flutter/lib/features/resources/overlay/) și [runtime](../packages/showrunner-flutter/lib/runtime/).

## Overlay inspector: Electron/Vue și Flutter

Deschide [comparația side by side](ui-comparison/overlay-inspector.html). Include inspectorul, popup-ul de font/stroke/shadow, zoom și captura Flutter de dinainte. Sunt capturi reale ale aceleiași resurse și aceluiași widget, la 1440 × 900.

Inspectorul Flutter are acum aceeași ordine principală: Text, preview Font, aliniere orizontală și verticală, X/Y, Width/Height. Câmpul Text este compact și crește când este necesar. Transformările folosesc câmpuri cu unitatea px și controale incrementale. Numele widgetului și reordonarea rămân disponibile mai jos și în listă. Transformările se sincronizează cu mutările pe canvas și validează valorile finite și dimensiunile pozitive.

Capturi: [Electron inspector](ui-comparison/electron-overlay-inspector-label.png), [Flutter inspector](ui-comparison/flutter-overlay-inspector-label.png), [Electron font](ui-comparison/electron-overlay-inspector-font.png), [Flutter font](ui-comparison/flutter-overlay-inspector-font.png).

La ajustarea următoare, popup-ul Font a fost adus la 640px, cu fundal gri, inputuri conturate, preview al familiei de font și bare de culoare. Stroke și Shadow au etichetele în stânga, câmpurile grupate și butoanele de eliminare în dreapta; valorile numerice au unitatea px și controale de incrementare. Grila canvasului și alinierea au griurile din varianta veche. Testul editorului verifică și adăugarea/eliminarea efectelor.

Diferențele intenționate rămase sunt shell-ul Flutter, rasterizarea fonturilor și selecția canvasului. Compararea screenshot-urilor întregi ar măsura și sidebar-ul și shell-ul aplicației; gate-ul verifică regiunile inspectorului și popup-ului față de baseline-ul Flutter versionat în repository.

## Verificări locale

| Verificare | Rezultat |
| --- | --- |
| Flutter analyze | Fără probleme |
| Flutter unit/widget tests | 667 teste trecute |
| Integrare Windows | 14 fișiere inițiale / 25 scenarii, plus testul nou de popup Windows / 1 scenariu, trecute |
| TypeScript | 10 workspaces trecute |
| JavaScript | 98 teste în 17 fișiere, trecute |
| Yarn install immutable | Trecut |
| Overlay build și Chrome DOM/WebGL smoke | Trecute |
| Contract parity | 26 improved, 6 equivalent; gate trecut |
| Product parity | 16 workspaces; gate trecut |
| Capturi Flutter regenerate independent | Inspector și popup: 0% diferență față de baseline |
| Control negativ al gate-ului vizual | Flutter anterior: 55,219% diferență în inspector față de baseline-ul final, respins |
| Windows Release bundle | Build, packaging și cele 8 smoke-uri trecute |
| Updater local | Instalare și rollback reale, trecute |
| Benchmark-uri | 5 probe pentru fiecare dintre cele 9 scenarii/dimensiuni; mediană și p95 generate |

Benchmark-urile sunt măsurători locale, nu dovadă de speedup general și nu un prag stabil de performanță. Regresia cache-ului este verificată prin comportament, separat de timpi.

Pentru artefactul raportat ulterior în comparația live, vezi [corecțiile popup-ului și limitele verificării](overlay-popup-rendering-2026-10-02.md).

## Limite de validare externă

Instalarea locală folosește bundle nesemnat. Certificatul de distribuție, lanțul de încredere Windows și publicarea unui release semnat necesită secretele de signing ale proiectului; nu au fost validate aici. Product parity păstrează această excepție explicită, cu cerințele externe. Conexiunile cu conturi live ale furnizorilor și un soak test îndelungat WebRTC nu sunt înlocuite de fixture-urile și smoke-urile locale.

Licența repository-ului și declarațiile ISC moștenite în unele manifeste au fost păstrate, cu [proveniența documentată](dependency-provenance.md). Corectarea juridică a acestei discrepanțe la publicarea separată a pachetelor necesită evidența contribuțiilor; această intervenție nu pretinde o relicențiere.
