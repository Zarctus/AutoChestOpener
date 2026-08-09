# Auto Chest Opener 3.1 — état d’implémentation

Le périmètre décidé pour la 3.1 est implémenté :

- centre de file avec états, raisons, ETA et actions ;
- mode assisté reposant sur un bouton sécurisé visible ;
- règles par conteneur : auto, délai, limite, priorité, blocage temporaire, source et note ;
- statistiques de succès/échec par conteneur ;
- migration de base vers le schéma 4.

Les profils Prudent/Normal/Rapide et le panneau compact près des sacs sont volontairement reportés afin de tester d’abord le moteur de file et le mode assisté en conditions réelles.
