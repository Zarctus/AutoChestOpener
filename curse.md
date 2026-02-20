# Auto Chest Opener

## English

### Overview
Auto Chest Opener is a lightweight World of Warcraft add-on that automatically opens nearby chests, bags, and containers when they become available to the player. It streamlines looting by offering configurable filters, delays, and keybinds so you can focus on gameplay while ensuring valuable containers are opened reliably and safely.

### Key Features
- Automatic opening: Detects and opens eligible chests, crates, sacks, and other lootable containers automatically.
- Configurable filters: Include or exclude container types, specific items, or categories (e.g., profession caches, world treasure).
- Adjustable delay and throttling: Set delays between open attempts to mimic natural interaction and avoid client-side issues.
- Keybinds and manual override: Assign a keybind to toggle auto-opening or trigger a manual open sequence.
- UI integration: Minimal, non-intrusive configuration UI for enabling/disabling features and editing filters.
- Localization ready: Comes with localization support and language fallbacks.
- Optional integrations: Integrates nicely with ElvUI when available (optional dependencies).
- Safe behavior: Respects combat and other protected states; will not attempt prohibited actions during combat or restricted interactions.
- Persistent settings: Uses saved variables (`AutoChestOpenerDB`) to keep user preferences across sessions.
- Small footprint: Minimal memory and CPU overhead, designed to be unobtrusive and compatible with other addons.

### Installation
1. Place the `AutoChestOpener` folder in your `Interface/AddOns/` directory.
2. Ensure the folder contains `AutoChestOpener.toc` and the addon files (e.g., `Core.lua`, `UI.lua`, `Locales.lua`, `Libs/LibStub/LibStub.lua`).
3. (Optional) Install `ElvUI` to enable enhanced integrations.
4. Reload the UI (`/reload`) or restart the game client.

### Usage
- Enable or disable auto-opening through the addon's configuration panel.
- Configure filters to control which container types are auto-opened.
- Set a realistic delay value to avoid spamming open attempts.
- Use the configured keybind to temporarily toggle automated behavior or trigger manual opening.

### Configuration Options (examples)
- Enable auto-open: On / Off
- Delay between opens: 0.2 — 3.0 seconds
- Container whitelist / blacklist: specify names or types
- Ignore in combat: On (default)
- Integrate with ElvUI: On / Off
- Log opened containers: On / Off

### Compatibility & Technical Notes
- Interface: 120000 (as declared in `AutoChestOpener.toc`)
- SavedVariables: `AutoChestOpenerDB`
- License: MIT (see `AutoChestOpener.toc` X-License)
- Icon: `Interface\AddOns\AutoChestOpener\textures\treasure.tga`
- The addon avoids protected actions during combat and respects Blizzard API restrictions to prevent taint.

### FAQ
- Q: Will this open everything automatically and risk losing items?
  - A: No — use filters and whitelist/blacklist to control behavior precisely.
- Q: Does it work in combat?
  - A: By default it will not perform protected interactions during combat to avoid errors; this is configurable.
- Q: Can I temporarily disable it?
  - A: Yes — use the keybind or settings panel to toggle it.

---

## Français

### Aperçu
Auto Chest Opener est un addon léger pour World of Warcraft qui ouvre automatiquement les coffres, sacs et autres conteneurs à proximité lorsqu'ils deviennent disponibles. Il simplifie le butin grâce à des filtres configurables, des délais et des raccourcis clavier, vous permettant de rester concentré sur le jeu tout en ouvrant de façon fiable les conteneurs précieux.

### Fonctionnalités principales
- Ouverture automatique : détecte et ouvre automatiquement les coffres, caisses, sacs et autres conteneurs récupérables.
- Filtres configurables : inclure/exclure des types de conteneurs, des objets spécifiques ou des catégories (ex. caches de métier, trésors du monde).
- Délais réglables et limitation : définir des délais entre tentatives d'ouverture pour imiter une interaction naturelle.
- Raccourcis et override manuel : assigner un raccourci clavier pour activer/désactiver l'ouverture automatique ou déclencher une ouverture manuelle.
- Intégration UI : interface de configuration minimale et non intrusive pour activer/désactiver et éditer les filtres.
- Prêt pour la localisation : prise en charge des traductions et mécanismes de repli.
- Intégrations optionnelles : s'intègre avec ElvUI si présents.
- Comportement sûr : respecte le combat et les états protégés ; n'intervient pas pendant les interactions restreintes.
- Paramètres persistants : utilise `AutoChestOpenerDB` pour conserver les préférences.
- Faible empreinte : utilisation minimale de la mémoire et du CPU, conçu pour être discret et compatible.

### Installation
1. Déposez le dossier `AutoChestOpener` dans `Interface/AddOns/`.
2. Vérifiez la présence de `AutoChestOpener.toc` et des fichiers (par ex. `Core.lua`, `UI.lua`, `Locales.lua`, `Libs/LibStub/LibStub.lua`).
3. (Optionnel) Installez `ElvUI` pour activer les intégrations.
4. Rechargez l'UI (`/reload`) ou relancez le client.

### Utilisation
- Activez ou désactivez l'ouverture automatique via le panneau de configuration de l'addon.
- Configurez les filtres pour contrôler les types de conteneurs à ouvrir automatiquement.
- Réglez un délai réaliste pour éviter les tentatives trop rapprochées.
- Utilisez le raccourci configuré pour désactiver temporairement l'automatisation ou déclencher l'ouverture manuelle.

### Options de configuration (exemples)
- Activer l'ouverture automatique : On / Off
- Délai entre ouvertures : 0.2 — 3.0 secondes
- Liste blanche / noire de conteneurs : noms ou types
- Ignorer en combat : Activé (par défaut)
- Intégration ElvUI : On / Off
- Journaliser les ouvertures : On / Off

### Compatibilité et notes techniques
- Interface : 120000 (voir `AutoChestOpener.toc`)
- SavedVariables : `AutoChestOpenerDB`
- Licence : MIT (voir `AutoChestOpener.toc` X-License)
- Icône : `Interface\AddOns\AutoChestOpener\textures\treasure.tga`
- L'addon évite les actions protégées en combat et respecte les restrictions de l'API Blizzard.

### FAQ
- Q : Ouvre-t-il tout automatiquement et risque-t-on de perdre des objets ?
  - R : Non — utilisez les filtres et la whitelist/blacklist pour contrôler précisément le comportement.
- Q : Fonctionne-t-il en combat ?
  - R : Par défaut, il n'effectue pas d'interactions protégées en combat pour éviter les erreurs ; c'est configurable.
- Q : Puis-je le désactiver temporairement ?
  - R : Oui — utilisez le raccourci ou le panneau de configuration.
