# Auto Chest Opener 3.1.0

## English

Auto Chest Opener tracks selected container items in the player's bags and manages their opening through a safe, verifiable queue.

### Highlights
- Retail **12.0.7 / Interface 120007** support.
- Automatic and assisted queue modes.
- Assisted opening through a visible secure button requiring a real player click.
- Queue center with status, blockers, retries, failures and estimated wait.
- Per-container rules: automatic opening, custom delay, session limit, priority, temporary block, source and note.
- Persistent success/failure diagnostics per container.
- Tracked and blocked item lists, search, import/export, history, loot and gold statistics.
- Protection around combat, merchant, trade, auction house, mail, bank, guild bank, void storage, loot and scrapping interfaces.
- English and French localization.

The addon does not bypass Blizzard's protected-action system. It verifies that an item was actually consumed before recording a successful opening and offers Assisted mode when a hardware click is required.

### Installation
Extract the `AutoChestOpener` folder into:

`World of Warcraft/_retail_/Interface/AddOns/`

Then restart the client or use `/reload`.

### Useful commands
- `/aco` — Open the interface.
- `/aco openall` — Queue eligible tracked containers.
- `/aco mode auto` — Automatic queue mode.
- `/aco mode assisted` — Secure click-assisted mode.
- `/aco queue` — Open the queue center.
- `/aco rules <itemID>` — Edit rules for one container.
- `/aco diag` — Print compatibility and queue diagnostics.

---

## Français

Auto Chest Opener surveille les conteneurs sélectionnés dans les sacs du joueur et gère leur ouverture dans une file fiable et vérifiable.

### Points forts
- Compatibilité Retail **12.0.7 / Interface 120007**.
- Modes de file Automatique et Assisté.
- Ouverture assistée avec un bouton sécurisé visible nécessitant un vrai clic du joueur.
- Centre de file avec états, blocages, tentatives, échecs et délai estimé.
- Règles par conteneur : ouverture automatique, délai spécifique, limite par session, priorité, blocage temporaire, source et note.
- Diagnostics persistants des réussites et échecs par conteneur.
- Listes des objets suivis et bloqués, recherche, import/export, historique, butin et statistiques d'or.
- Protection pendant le combat et lorsque les interfaces sensibles sont ouvertes : marchand, échange, hôtel des ventes, courrier, banque, banque de guilde, chambre du Vide, butin et recyclage.
- Localisation française et anglaise.

L'addon ne contourne pas le système d'actions protégées de Blizzard. Il vérifie qu'un objet a réellement été consommé avant d'enregistrer une réussite et propose le mode Assisté lorsqu'un clic matériel est nécessaire.

### Installation
Extraire le dossier `AutoChestOpener` dans :

`World of Warcraft/_retail_/Interface/AddOns/`

Puis relancer le client ou utiliser `/reload`.

### Commandes utiles
- `/aco` — Ouvrir l'interface.
- `/aco openall` — Mettre en file les conteneurs suivis et éligibles.
- `/aco mode auto` — Mode automatique.
- `/aco mode assisted` — Mode assisté par clic sécurisé.
- `/aco queue` — Ouvrir le centre de file.
- `/aco rules <itemID>` — Modifier les règles d'un conteneur.
- `/aco diag` — Afficher les diagnostics de compatibilité et de file.
