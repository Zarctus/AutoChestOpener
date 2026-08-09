# Auto Chest Opener

**Retail 12.0.7 · Interface 120007 · English & Français**

Auto Chest Opener watches the containers you choose in your bags and opens them through a **safe, verifiable queue** — never before the game confirms an item was actually consumed. No protected-action bypass, no taint tricks.

---

## English

### What it does
You pick which containers to track (chests, bags, crates, lockboxes, gifts, caches…). The addon queues them and opens each one when it is safe to do so, then verifies the result before counting it as a success.

### Highlights
- **Queue Center** — a real opening queue with live states (waiting, delay, blocked, opening, verifying, retry, click required, paused, failed), the exact reason for each block or failure, attempt count, and an estimated wait time.
- **Automatic & Assisted modes** — switch globally between fully automatic opening and an **Assisted** mode that prepares the next item on a visible secure button requiring a real hardware click.
- **Per-container rules** — for each tracked item: automatic opening on/off, custom delay, per-session limit, queue priority (-10 to 10), temporary block, permanent block, source and note.
- **Verified results** — an item is only recorded as opened after its real consumption is confirmed; limited retries with clear failure reasons.
- **Tracking & data** — tracked and blocked item lists, search, import/export, opening history, loot and gold statistics, per-container success/failure diagnostics.
- **Safety first** — pauses around combat and sensitive interfaces: merchant, trade, auction house, mail, bank, guild bank, void storage, loot and scrapping.
- **Localization** — full English and French support.

### Modes
- **Automatic** — eligible tracked containers are queued and opened for you, respecting your delays and limits.
- **Assisted** — when the client refuses automatic use of an item, the next container is armed on a `SecureActionButton`; you press **Open Next** with a real click. This provides a reliable path without ever bypassing Blizzard's protections.

The secure button is available both in the **Waiting** tab and in the floating queue widget when the main window is closed.

### Commands
- `/aco` — open the interface.
- `/aco openall` — queue eligible tracked containers.
- `/aco mode auto` — automatic queue mode.
- `/aco mode assisted` — secure click-assisted mode.
- `/aco queue` — open the Queue Center.
- `/aco next` — prepare/open the next queued item.
- `/aco rules <itemID>` — edit the rules of one container.
- `/aco diag` — print compatibility and queue diagnostics.

### Installation
Extract the `AutoChestOpener` folder into:

`World of Warcraft/_retail_/Interface/AddOns/`

Then restart the client or type `/reload`.

### Notes
- The addon does not bypass the protected-action system. It verifies real item consumption before recording a success and offers Assisted mode when a hardware click is required.
- Settings persist in `AutoChestOpenerDB` (SavedVariables schema 4).
- Optional integrations: ElvUI, LibDataBroker-1.1, Zarctus_Gold.

---

## Français

### Ce que fait l'addon
Vous choisissez les conteneurs à suivre (coffres, sacs, caisses, boîtes verrouillées, cadeaux, caches…). L'addon les met en file et ouvre chacun quand c'est sûr, puis **vérifie le résultat** avant de le compter comme réussi.

### Points forts
- **Centre de file** — une véritable file d'ouverture avec états en direct (attente, délai, blocage, ouverture, vérification, nouvel essai, clic requis, pause, échec), la raison exacte de chaque blocage ou échec, le nombre de tentatives et une estimation du délai restant.
- **Modes Automatique & Assisté** — bascule globale entre ouverture entièrement automatique et un mode **Assisté** qui prépare le prochain objet sur un bouton sécurisé visible nécessitant un vrai clic matériel.
- **Règles par conteneur** — pour chaque objet suivi : ouverture automatique activée/désactivée, délai spécifique, limite par session, priorité de file (-10 à 10), blocage temporaire, blocage permanent, source et note.
- **Résultats vérifiés** — un objet n'est comptabilisé comme ouvert qu'après confirmation de sa consommation réelle ; nouvelles tentatives limitées avec raisons d'échec claires.
- **Suivi & données** — listes des objets suivis et bloqués, recherche, import/export, historique des ouvertures, statistiques de butin et d'or, diagnostics de réussite/échec par conteneur.
- **Sécurité d'abord** — mise en pause pendant le combat et les interfaces sensibles : marchand, échange, hôtel des ventes, courrier, banque, banque de guilde, chambre du Vide, butin et recyclage.
- **Localisation** — prise en charge complète du français et de l'anglais.

### Modes
- **Automatique** — les conteneurs suivis et éligibles sont mis en file et ouverts pour vous, dans le respect de vos délais et limites.
- **Assisté** — lorsque le client refuse l'utilisation automatique d'un objet, le prochain conteneur est armé sur un `SecureActionButton` ; vous pressez **Ouvrir le suivant** d'un vrai clic. Un chemin fiable, sans jamais contourner les protections de Blizzard.

Le bouton sécurisé est disponible dans l'onglet **En attente** et dans le widget flottant de file lorsque la fenêtre principale est fermée.

### Commandes
- `/aco` — ouvrir l'interface.
- `/aco openall` — mettre en file les conteneurs suivis et éligibles.
- `/aco mode auto` — mode automatique.
- `/aco mode assisted` — mode assisté par clic sécurisé.
- `/aco queue` — ouvrir le centre de file.
- `/aco next` — préparer/ouvrir le prochain élément de la file.
- `/aco rules <itemID>` — modifier les règles d'un conteneur.
- `/aco diag` — afficher les diagnostics de compatibilité et de file.

### Installation
Extraire le dossier `AutoChestOpener` dans :

`World of Warcraft/_retail_/Interface/AddOns/`

Puis relancer le client ou taper `/reload`.

### Notes
- L'addon ne contourne pas le système d'actions protégées. Il vérifie la consommation réelle d'un objet avant d'enregistrer une réussite et propose le mode Assisté lorsqu'un clic matériel est nécessaire.
- Les réglages sont conservés dans `AutoChestOpenerDB` (schéma SavedVariables 4).
- Intégrations optionnelles : ElvUI, LibDataBroker-1.1, Zarctus_Gold.
