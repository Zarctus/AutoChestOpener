# Auto Chest Opener

## 2.2.3 — Midnight Compatibility
### Compatibilité Midnight (12.0+)
- **SecureActionButton fallback** : `C_Container.UseContainerItem` est désormais protégé en 12.0+. L'addon utilise maintenant un `SecureActionButtonTemplate` en fallback pour ouvrir les conteneurs hors combat.
- **Nouveau TooltipDataLineType** : détection améliorée via les nouveaux types de lignes de tooltip 12.0 (`FlavorText`, `ItemQuality`, `UsageRequirement`, `ErrorLine`, `DisabledLine`).
- **Mots-clés Midnight** : ajout de mots-clés pour les conteneurs de Midnight (Voidstorm, Haranir, Sunwell, Silvermoon, Amani, Zul'Aman, Quel'Thalas, Earthen, Arathi, Undermine, Venture...).

### Nouvelles fonctionnalités
- **Raccourcis clavier** : possibilité d'assigner des raccourcis via le menu Raccourcis de WoW pour « Ouvrir tous les conteneurs » et « Afficher/Masquer les options ».
- **LDB DataBroker** : plugin DataBroker pour les barres comme Titan Panel, Bazooka, ChocolateBar, etc. Affiche les stats et permet d'ouvrir l'interface en un clic.

### Optimisations
- **Cache conteneur limité** : le cache de détection des conteneurs est maintenant purgé automatiquement au-delà de 500 entrées pour éviter les fuites mémoire.
- **FormatRelativeTime localisé** : les temps relatifs (« Il y a 5 min », « Just now ») utilisent maintenant le système de locale au lieu d'être codés en dur en français.

## 2.1.0
### Détection universelle de conteneurs
- **Mots-clés étendus** : ajout massif de mots-clés pour détecter bien plus de conteneurs (coffres, caisses, boîtes, sacs de récompense, lockboxes PvP, cadeaux de fête, coquillages, tonneaux, urnes, paniers, et bien d'autres).
- **Support multi-langues étendu** : ajout du portugais (PT-BR), italien, chinois simplifié/traditionnel dans les patterns de détection.
- **Détection par classe d'objet améliorée** :
  - Consumable (classe 0) sous-classe Other (8) et Generic (0) avec sort d'ouverture.
  - Miscellaneous (classe 15) : exclut désormais correctement les mascottes, montures et équipements de monture.
  - Quest (classe 12) : détecte les conteneurs de quête avec sort d'ouverture.
- **API C_TooltipInfo moderne** : utilisation de l'API structurée (10.0.2+) pour scanner les infobulles de façon plus fiable, avec fallback sur l'ancienne méthode GameTooltip.
- **Détection du texte vert "Utiliser :"** dans les infobulles via C_TooltipInfo pour repérer les effets d'ouverture.
- **Mots-clés de tooltip étendus** : support DE, ES, PT, IT, RU pour "Clic droit pour ouvrir".
- **Ouvrir tout amélioré** : `/aco openall` détecte maintenant aussi les conteneurs auto-détectés, pas seulement ceux de la liste manuelle.
- **Auto-découverte simplifiée** : utilise désormais la même logique centralisée `IsContainerItem()` pour éviter les incohérences.

## 1.3.5 (local patch)
- Correction: certains conteneurs ne s'ouvraient pas si les données d'objet n'étaient pas encore en cache (ex: items nouveaux/non consultés). Désormais, l'addon diffère la classification et réessaie automatiquement dès que l'item est chargé.
- Amélioration: la file d'ouverture est maintenant triée par temps d'exécution (un item "manuel"/immédiat ne reste plus bloqué derrière un item retardé).
- Robustesse: détection texte en recherche "plain" + normalisation des apostrophes (’ vs ').
## 1.3.4 (local patch)
- Correction: enregistrement des événements en mode safe (évite l'erreur "unknown event" sur certaines versions, ex: VOID_STORAGE_CLOSE).

## 1.3.3 (local patch)
- Pause automatique de l'ouverture quand vous êtes en combat ou qu'une fenêtre sensible est ouverte (marchand/banque/courrier/HV/échange).
- Reprise automatique dès que possible, sans risque de vente/dépôt/attachement accidentel.

## [v1.3.2](https://github.com/Zarctus/AutoChestOpener/tree/v1.3.2) (2026-02-10)
[Full Changelog](https://github.com/Zarctus/AutoChestOpener/compare/v1.3.1...v1.3.2) [Previous Releases](https://github.com/Zarctus/AutoChestOpener/releases)

- Mise à jour de la version dans le fichier .toc et ajustement de la récupération de la version dans Core.lua  
- Mise à jour des permissions et ajout de la variable GITHUB\_OAUTH dans le workflow de publication  
- Mise à jour des variables d'environnement dans le workflow de publication pour utiliser le jeton WAGO au lieu du jeton GitHub.  
- Ajout de l'ID Wago dans le fichier .toc  
- Mise à jour du fichier .gitignore, ajout de l'ID de projet Curse dans le fichier .toc et création du workflow de publication dans release.yml  
- Merge branch 'main' of https://github.com/Zarctus/AutoChestOpener  
- Mise à jour de la version à 1.3.1, ajout de curse.md au .gitignore et amélioration de la logique de gestion des conteneurs  