# Audit de compatibilité Retail 12.1.0

Cible de cette version : **Interface 120100**.

Référence vérifiée pendant la mise à jour : client Retail **12.1.0 build 69273** et définitions API générées de la branche live correspondante.

## API utilisées par l'addon

Les appels suivants ont été comparés aux définitions 12.1.0 actuelles :

- `C_Container.GetContainerItemInfo` — OK
- `C_Container.GetContainerNumSlots` — OK
- `C_Container.UseContainerItem` — OK
- `C_Item.GetItemIconByID` — OK
- `C_Item.GetItemInfo` — OK
- `C_Item.GetItemInfoInstant` — OK
- `C_Item.GetItemNameByID` — OK
- `C_Item.GetItemSpell` — OK
- `C_Item.IsItemDataCachedByID` — OK
- `C_Item.RequestLoadItemDataByID` — OK
- `C_TooltipInfo.GetItemByID` — OK
- `C_AddOns.GetAddOnMetadata` — OK

## Correction API effectuée

`C_Item.GetItemSellPrice` n'est pas présent dans la documentation API Retail 12.1 générée. Le code de valeur vendeur n'en dépend plus : il récupère `sellPrice` depuis le 11e résultat de `C_Item.GetItemInfo`, qui est documenté en 12.1.

## Valeurs secrètes et 12.1

12.1 étend l'usage des protections de valeurs secrètes dans l'interface. L'addon ne lit pas les auras de combat et n'utilise ni `C_UnitAuras`, ni `UnitAura`, ni `AuraUtil`.

Des gardes ont néanmoins été ajoutés avant :

- la normalisation de texte de tooltip ;
- les comparaisons de composantes de couleur de tooltip ;
- les calculs utilisant la valeur vendeur d'un objet.

L'objectif est qu'une valeur marquée secrète par un futur hotfix soit ignorée plutôt que comparée, concaténée ou utilisée dans un calcul Lua non sécurisé.

## Actions protégées

L'ouverture reste volontairement conçue en deux chemins :

- mode automatique : tentative via l'API puis vérification réelle de consommation ;
- mode assisté : bouton `SecureActionButtonTemplate` nécessitant un clic matériel du joueur.

Aucune ouverture n'est comptabilisée tant que la diminution de la pile n'a pas été confirmée.

## SavedVariables

Le schéma reste **4**. La 3.1.1 ne nécessite aucune remise à zéro et conserve les données de la 3.1.0.
