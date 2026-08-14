# Auto Chest Opener 3.2.0 — compatibilité Retail 12.1.0

Cible : **Interface 120100**.

La 3.2 conserve le portage API réalisé en 3.1.1 et concentre les changements sur la fiabilité de la file et le respect des actions protégées.

## API principales utilisées

- `C_Container.GetContainerItemInfo`
- `C_Container.GetContainerNumSlots`
- `C_Container.UseContainerItem`
- `C_Item.GetItemIconByID`
- `C_Item.GetItemInfo`
- `C_Item.GetItemInfoInstant`
- `C_Item.GetItemNameByID`
- `C_Item.GetItemSpell`
- `C_Item.IsItemDataCachedByID`
- `C_Item.RequestLoadItemDataByID`
- `C_TooltipInfo.GetItemByID`
- `C_AddOns.GetAddOnMetadata`

La valeur vendeur continue d'être obtenue via le résultat `sellPrice` de `C_Item.GetItemInfo`; le code ne dépend pas de `C_Item.GetItemSellPrice`.

## Valeurs potentiellement protégées

Les textes/couleurs de tooltip et les valeurs monétaires sont validés avant comparaison ou calcul. En 3.2, les chemins de suivi d'or utilisent également un accès défensif : si `GetMoney()` renvoie une valeur inaccessible, le delta d'or est ignoré plutôt que de provoquer une opération Lua sur cette valeur.

## Politique d'actions protégées

- **Automatique** : utilisation de l'API publique uniquement, suivie d'une vérification réelle de consommation.
- **Assisté** : bouton visible `SecureActionButtonTemplate`, préparé hors combat et déclenché par un clic matériel du joueur.
- Aucun appel programmatique à `Button:Click()` n'est utilisé pour tenter de provoquer une action sécurisée.
- Un refus de l'API automatique devient un échec explicite et peut orienter le joueur vers le mode Assisté.

## Confirmation stricte

La réussite dépend uniquement d'une diminution observée de la quantité de l'Item ID concerné. Une API qui ne lève aucune erreur n'est pas considérée comme preuve de réussite.

La file est sérialisée pendant cette vérification afin d'éviter qu'une diminution issue d'une autre action soit attribuée au mauvais élément.

## SavedVariables

Schéma **5**. La migration depuis le schéma 4 conserve les données existantes et initialise uniquement les nouveaux paramètres de fiabilité, de widget et de circuit anti-boucle.
