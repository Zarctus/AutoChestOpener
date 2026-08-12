# Checklist de test Auto Chest Opener 3.1.1 — Retail 12.1.0

## Avant le test

- Sauvegarder `WTF/Account/.../SavedVariables/AutoChestOpener.lua`.
- Activer les erreurs Lua : `/console scriptErrors 1`.
- Installer la 3.1.1 puis faire `/reload`.
- Lancer `/aco diag` et vérifier : interface 120100, schéma DB 4, API critiques OK.
- Vérifier que `/aco diag` affiche `12.1.0`, le build du client et `OK` après la cible 120100.

## Migration 3.0.x / 3.1.0 → 3.1.1

- Vérifier que la liste de conteneurs, la blacklist, les statistiques et le butin sont conservés.
- Vérifier que le mode Automatique/Assisté précédemment choisi est conservé.
- Modifier une règle, faire `/reload`, puis confirmer sa persistance.

## Centre de file

- Ajouter plusieurs conteneurs, dont une pile.
- Ouvrir l’onglet En attente et vérifier les états Délai puis Ouverture/Vérification.
- Tester Pause, Reprise, Ouvrir le suivant et Vider la file.
- Retirer une entrée individuelle.
- Produire volontairement un échec avec un objet protégé, puis tester Réessayer et Effacer les échecs.
- Vérifier que la raison de blocage apparaît en combat, avec un marchand, une banque, le courrier et un objet sur le curseur.
- Vérifier qu’un élément en délai futur ne bloque pas un autre élément déjà prêt.

## Mode assisté

- Sélectionner Assisté dans l’onglet En attente.
- Mettre un conteneur en file et attendre l’état Clic requis.
- Cliquer sur Ouvrir le suivant dans la grande fenêtre.
- Refaire le test avec la grande fenêtre fermée et le widget flottant visible.
- Vérifier qu’un clic droit ne déclenche rien.
- Déplacer le conteneur dans un autre emplacement avant le clic : l’action doit continuer à cibler l’Item ID, pas l’ancien slot.
- Vérifier que les statistiques augmentent seulement après diminution réelle de la pile.
- Tester en combat : le bouton doit rester indisponible jusqu’à la sortie du combat.

## Règles par conteneur

Pour deux types de conteneurs différents :

- Désactiver l’ouverture automatique de l’un et confirmer qu’il n’est pas mis en file automatiquement.
- Définir un délai spécifique décimal, par exemple `0.5`.
- Fixer une limite de 2 par session avec une pile de 5 et vérifier que seuls deux exemplaires sont réservés.
- Donner une priorité élevée au premier et faible au second ; vérifier l’ordre lorsque les deux sont prêts.
- Appliquer un blocage temporaire et confirmer que l’autre conteneur continue à être traité.
- Saisir une source et une note, faire `/reload`, puis rouvrir l’éditeur.
- Réinitialiser les règles.
- Tester Bloquer définitivement et vérifier le passage dans la vue Bloqués.

## Ouverture et données

- Ouvrir l’onglet principal et vérifier que les valeurs moyennes/vendeur ne génèrent aucune erreur liée aux valeurs secrètes.
- Tester au moins un conteneur détecté via tooltip afin de valider `C_TooltipInfo.GetItemByID` sur 12.1.
- Tester `Ouvrir tout` avec une pile supérieure à 1.
- Vérifier Statistiques, Historique et Butin après une ouverture confirmée.
- Vérifier qu’un essai refusé ne crée ni ouverture, ni historique, ni butin confirmé.
- Vérifier le nombre de succès et d’échecs dans l’éditeur de règles.
- Tester `/aco mode auto`, `/aco mode assisted`, `/aco next`, `/aco queue` et `/aco rules <itemID>`.

## Interface

- Tester à la taille minimale 820 × 680 et à la taille maximale.
- Vérifier qu’aucun contrôle du centre de file ne se chevauche en français.
- Vérifier les trois cartes KPI à plusieurs échelles d’interface.
- Tester la recherche, les vues Suivis/Bloqués et le nouvel engrenage de règles.
- Tester `/aco resetui`.

## Rapport de bug utile

Inclure :

- la sortie de `/aco diag` ;
- l’erreur Lua complète ;
- l’Item ID ;
- le mode Automatique ou Assisté ;
- la règle configurée pour l’objet ;
- le contexte de blocage éventuel ;
- un test avec les autres addons désactivés si possible.
