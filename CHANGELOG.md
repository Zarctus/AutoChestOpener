# Auto Chest Opener

## 3.1.0 — Centre de file, règles et mode assisté

### Centre de file
- L’onglet En attente affiche les vraies entrées de la file, les vérifications actives et les échecs de la session.
- Nouveaux états : attente, délai, blocage, ouverture, vérification, nouvel essai, clic requis, pause et échec.
- Affichage du motif, des tentatives et de l’ETA.
- Actions Ouvrir le suivant, Pause/Reprise, Vider la file, Réessayer et Retirer.
- Historique persistant borné des 50 derniers échecs.

### Mode assisté
- Nouveau mode global Automatique/Assisté, conservé dans les SavedVariables.
- Boutons visibles basés sur `SecureActionButtonTemplate` dans l’onglet de file et le widget flottant.
- Utilisation sécurisée par Item ID afin d’éviter d’agir sur un emplacement de sac devenu obsolète.
- La consommation reste vérifiée après le clic avant toute statistique.
- Nouveau raccourci pour préparer/ouvrir le prochain élément de la file.

### Règles par conteneur
- Éditeur accessible depuis l’engrenage de chaque conteneur suivi.
- Activation automatique, délai spécifique, limite par session, priorité, blocage temporaire, source et note.
- Blocage permanent disponible depuis l’éditeur.
- Les limites sont vérifiées à la mise en file et avant l’ouverture.
- Le tri privilégie les éléments prêts : un délai ou blocage futur ne retient pas le reste de la file.

### Fiabilité et données
- SavedVariables migrées vers le schéma 4.
- Statistiques de réussite et d’échec par conteneur.
- `Ouvrir tout` développe désormais toutes les unités d’une pile.
- Les délais décimaux sont correctement formatés dans les notifications.
- Nouvelles commandes `/aco mode`, `/aco next`, `/aco queue` et `/aco rules`.

## 3.0.3 — Correctif des cartes KPI

### Interface
- Les trois cartes KPI utilisent désormais des zones verticales explicites pour le titre, la valeur et le détail.
- Le sous-texte ne dépend plus de la hauteur réelle de la police et ne peut plus sortir sous la carte.
- Les lignes KPI sont limitées à une seule ligne, sans retour automatique.
- Les cartes masquent par sécurité tout rendu situé hors de leurs limites.
- Les icônes et chiffres ont été légèrement recalibrés afin de conserver une bonne lisibilité à forte échelle d’interface.
- La hauteur globale du bandeau reste inchangée afin de ne pas réduire la zone principale.

## 3.0.2 — Correctif de débordement du panneau gauche

### Interface
- Les interrupteurs des paramètres utilisent désormais la largeur intérieure réelle du panneau.
- Le curseur de délai est ancré aux deux marges et ne dépasse plus du cadre.
- Le champ Item ID et le bouton Ajouter sont maintenant distribués dynamiquement entre les marges.
- Le correctif reste valide à la largeur minimale de la fenêtre et avec les traductions longues.

## 3.0.1 — Midnight 2.0 UI Polish

### Lisibilité de la liste
- Lignes plus hautes, icônes plus grandes et noms forcés sur une seule ligne.
- Colonnes explicites pour la quantité en sac et la valeur moyenne estimée.
- Les conteneurs absents des sacs sont visuellement atténués ; les quantités présentes sont mises en évidence.
- Valeurs moyennes raccourcies pour éviter tout chevauchement avec les actions.

### Ergonomie
- Champ de recherche adaptatif, plus large, avec icône et bouton d'effacement.
- Bouton « Ouvrir tout » renforcé et actions de bas de fenêtre agrandies.
- KPI plus lisibles avec chiffres plus grands et détails placés sur une ligne dédiée.
- Curseur de délai modernisé avec saisie numérique directe et bornes visibles.
- Colonne de paramètres compactée et zone de dépôt agrandie.
- Badge Midnight rendu volontairement discret pour ne plus ressembler à un bouton.

### Compatibilité
- Cible Retail conservée sur `120007`.
- Aucun changement de schéma de SavedVariables : mise à jour directe depuis 3.0.0.

## 3.0.0 — Retail 12.0.7 / Midnight 2.0

### Compatibilité et fiabilité
- Interface TOC mise à jour vers `120007`.
- Ajout d'une validation des API critiques au chargement et de `/aco diag`.
- Nouveau schéma de SavedVariables version 3 avec migration profonde et normalisation des IDs.
- Les ouvertures ne sont plus comptabilisées avant confirmation de la consommation réelle de l'objet.
- Nouveau moteur de vérification : attente des locks, retries limités, raisons d'échec et statistiques d'échec.
- Correction du suivi de l'or et du butin lors des lots rapides et des retries.
- Les timers de nettoyage ne suppriment plus les trackers créés par des ouvertures plus récentes.
- Protection renforcée des enums de tooltip pouvant varier entre builds mineurs.

### Interface Concept 1
- Nouvelle fenêtre Midnight 2.0 en deux colonnes.
- Bandeau KPI : or de session, ouvertures confirmées et file active.
- Interrupteurs modernes, onglets adaptatifs et actions regroupées en bas.
- Taille, position, onglet, recherche et vue Suivis/Bloqués persistants.
- Ajout de `/aco resetui`.
- Liste triée et quantité actuellement présente dans les sacs affichée.

### Qualité
- Correction de la capture `CHAT_MSG_LOOT` qui n'était pas toujours persistée.
- Correction du formatage hexadécimal des couleurs avec des valeurs flottantes.
- Ajout de `TESTING.md`.

## 2.2.4 — Midnight Compatibility
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