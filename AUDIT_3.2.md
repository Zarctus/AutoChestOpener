# Audit de valeur — Auto Chest Opener 3.2.0

## Critère de décision

La roadmap a été classée selon quatre critères : impact sur la fiabilité, capacité à expliquer un échec, risque d'introduire du taint/des actions protégées, et charge visuelle supplémentaire.

| Élément | Valeur immédiate | Décision 3.2 |
|---|---:|---|
| Profils Prudent / Normal / Rapide | Élevée | Implémenté |
| Import/export versionné des règles | Élevée | Implémenté |
| Filtres de file | Moyenne à élevée | Implémenté |
| Widget compact près des sacs | Moyenne | Widget existant rendu facultatif, pas de nouveau panneau |
| Export CSV de l'historique | Faible pour la fiabilité | Différé |
| Tris visuels supplémentaires | Faible / potentiellement trompeur | Différé |

## Changements ajoutés hors roadmap initiale

Deux faiblesses avaient plus de valeur à corriger que le CSV ou un nouveau widget :

1. **Sérialisation des confirmations** : tant qu'une utilisation n'est pas confirmée ou échouée, aucune seconde utilisation n'est lancée. Cela protège l'attribution de la diminution de pile.
2. **Circuit anti-boucle par Item ID** : des échecs automatiques répétés suspendent temporairement les nouvelles tentatives de cet objet et retirent ses doublons automatiques déjà en attente.

## Politique sécurisée

La 3.2 supprime le fallback historique qui tentait un clic sécurisé programmatique. Le chemin Assisté est uniquement un bouton visible, préparé hors combat et activé par une action matérielle réelle du joueur.

Les contrôles sécurisés ne sont plus reconfigurés/masqués pendant le combat. Les changements nécessaires sont différés jusqu'à la sortie de combat.

## Résultat

La 3.2 augmente volontairement le temps minimal entre deux ouvertures par rapport à une file agressive, mais supprime une ambiguïté importante : une action suivante ne peut plus être lancée pendant que la précédente attend encore sa preuve de consommation.
