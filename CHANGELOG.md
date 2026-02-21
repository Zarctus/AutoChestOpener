# Auto Chest Opener

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