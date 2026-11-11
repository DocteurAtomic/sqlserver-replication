# Exercice du module 5 : un abonnement pull

Le serveur de rapports veut sa copie du catalogue de l'exercice 4, mais il veut la tirer
lui-même, avec son propre agent. Abonnez une base `ex_pull` de `rpllab3` en pull à la
publication `ex_pubCatalog`, livrez l'instantané, faites une modification sur l'éditeur et
prouvez qu'elle arrive par l'agent de l'abonné.

## Le départ

```bash
./exercises/module_05/1-start.sh       # avec Podman : ENGINE=podman ./exercises/module_05/1-start.sh
./exercises/module_05/check.sh         # sort en 1 et dit ce qui manque
```

`1-start.sh` retire toute réplication du labo (`demos/module_05/99-cleanup.sh`), puis rejoue
l'exercice 4 et son corrigé : le distributeur, la publication `ex_pubCatalog` (active,
`concurrent`, pull accepté) livrée en push à `ex_catalog`, la catégorie `EX` et un jeton de
suivi. Il crée enfin sur `rpllab3` la base `ex_pull`, vide. Comptez une minute et demie.
`demos/module_05/99-cleanup.sh` retire tout à la fin, `ex_pull` et les catégories comprises.

## La consigne

1. Sur `rpllab1`, déclarez l'abonnement pull de `ex_pull` à `ex_pubCatalog`.
2. Sur `rpllab3`, dans `ex_pull`, créez ce que l'instantané ne crée pas, puis l'abonnement pull
   et son agent de distribution, en continu. L'agent se connecte au distributeur `rpllab2` en
   authentification SQL Server (`sa` et le mot de passe du labo).
3. Livrez l'instantané. Si la livraison n'arrive pas, lisez l'historique du travail de l'agent
   dans le `msdb` de `rpllab3`, puis `MSdistribution_history` dans la base `distribution` de
   `rpllab2`.
4. Une fois l'instantané livré, ajoutez sur `rpllab1` la catégorie `PL`, libellé `Pull`,
   description `Category of the exercise of module 5`, et vérifiez qu'elle arrive dans
   `ex_pull`.
5. Postez un jeton de suivi sur `ex_pubCatalog` et vérifiez qu'il atteint `ex_pull`.
6. Lancez `check.sh` : il sort en 0 quand tout tient.

`check.sh` lit l'état des trois instances : `Course.Category` sur `rpllab1` ; sur `rpllab2`, le
type de l'abonnement dans `MSsubscriptions`, l'absence de travail d'agent pour `ex_pull` sur le
distributeur, l'historique de l'agent et les jetons de suivi qu'il a livrés ; sur `rpllab3`, le
travail de l'agent en cours d'exécution, la catégorie `PL` et, table par table, le nombre de
lignes et une somme de contrôle (`CHECKSUM_AGG(BINARY_CHECKSUM(*))`) comparés à ceux de
l'éditeur. Il ne lit jamais vos commandes.

Un corrigé est dans `solution/`. Essayez d'abord sans lui.

---

# Exercise of module 5: a pull subscription

Subscribe the database `ex_pull` on `rpllab3` to the publication `ex_pubCatalog` of exercise 4
with a pull subscription: registered at the publisher, then created at the subscriber with a
continuous Distribution Agent that connects to the distributor `rpllab2` with a SQL Server
login. Deliver the snapshot, insert the category `PL` (`Pull`, `Category of the exercise of
module 5`) on the publisher, check that it arrives, and post a tracer token that reaches
`ex_pull`. `1-start.sh` builds the end state of exercise 4 and an empty `ex_pull`; `check.sh`
exits with 0 when the state holds and with 1 otherwise. The solution is in `solution/`.
