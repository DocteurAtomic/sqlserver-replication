# Exercice du module 8 : trois pannes

La copie de test du site d'inscription, `ex_catalog` sur `rpllab3`, reçoit le catalogue par
`ex_pubCatalog`. Trois pannes vont la frapper, l'une après l'autre. Pour chacune, trouvez la
cause en lisant l'état, puis réparez sans réinitialiser l'abonnement et sans sauter d'erreur.

## Le départ

```bash
./exercises/module_08/1-start.sh       # avec Podman : ENGINE=podman ./exercises/module_08/1-start.sh
./exercises/module_08/check.sh         # sort en 1 et dit ce qui manque
```

`1-start.sh` retire toute réplication du labo (`demos/module_08/99-cleanup.sh`), rejoue
l'exercice 4 et son corrigé (`ex_pubCatalog` livrée en push à `ex_catalog`), crée sur
`rpllab1` une petite base `ex_incident` qui garde la trace des pannes jouées, puis joue la
première panne. Comptez un peu plus d'une minute. `demos/module_08/99-cleanup.sh` retire tout à
la fin, `ex_incident` comprise, et rend à `PachadataTraining` les valeurs que l'exercice a
changées.

## Les trois pannes

1. Jouée par `1-start.sh` : la catégorie `X1`, insérée sur `rpllab1`, n'arrive pas dans
   `ex_catalog`.
2. Jouée par `./exercises/module_08/incidents/2-row-not-found.sh`, qui refuse de partir tant
   que la première n'est pas réparée : le prix de la session 2000 change sur `rpllab1`.
3. Jouée par `./exercises/module_08/incidents/3-duplicate.sh`, qui refuse de partir tant que la
   deuxième n'est pas réparée : la catégorie `X3` est insérée sur `rpllab1`.

Après chaque panne, observez avant d'agir : l'historique des agents et `MSrepl_errors` sur
`rpllab2`, les commandes en attente, `sp_repltrans` sur `rpllab1`, et les lignes de
`ex_catalog`. L'agent de distribution réessaie seul pendant plus d'une minute avant d'écrire
son erreur : laissez-lui ce temps.

## La consigne

- Réparez chaque panne avant de jouer la suivante.
- Ne réinitialisez pas l'abonnement (`sp_reinitsubscription`), ne sautez aucune erreur (ni
  `-SkipErrors`, ni le profil « Continue on data consistency errors. »).
- L'éditeur fait foi : quand une ligne de `ex_catalog` contredit `rpllab1`, c'est `ex_catalog`
  qu'on corrige.
- Lancez `check.sh`. Il répond « The three incidents are repaired: ex_catalog has the rows of
  rpllab1, and its agents run. » et sort en 0 quand tout tient.

`check.sh` lit un état : les trois pannes jouées ; aucun instantané livré à `ex_catalog` depuis
la première (une réinitialisation en livrerait un) ; l'agent de lecture du journal de
`PachadataTraining` actif et en marche ; l'agent de distribution de `ex_catalog` sans
`-SkipErrors`, ni dans son profil ni sur la commande de son travail, en marche et sans commande
en attente ; `X1`, `X3` et la session 2000 identiques des deux côtés. Enfin il lance
`sp_publication_validation` avec `@rowcount_only = 2` et attend que les trois tables passent.
Moins d'une minute.

## À réfléchir

- Pendant la première panne, que rend `sp_replmonitorsubscriptionpendingcmds` pour
  `ex_catalog` ? Pourquoi la requête du matin du module 7 ne voit-elle rien ?
- Dans `MSrepl_errors`, quelle ligne donne le `xact_seqno` de la commande fautive ?
- La troisième panne échoue en 2601 et non en 2627 : pourquoi, et qu'est-ce que cela change à
  la liste d'un `-SkipErrors` ?
