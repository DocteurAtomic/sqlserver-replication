# Exercice du module 4 : une publication transactionnelle

Le site d'inscription veut une seconde copie du catalogue, pour ses tests. Publiez
`Course.Category`, `Course.Course` et `Course.Session` par réplication transactionnelle vers une
base `ex_catalog` de `rpllab3`, faites une modification sur l'éditeur, et prouvez qu'elle est
arrivée, puis mesurez la latence par un jeton de suivi.

## Le départ

```bash
./exercises/module_04/1-start.sh       # avec Podman : ENGINE=podman ./exercises/module_04/1-start.sh
./exercises/module_04/check.sh         # sort en 1 et dit ce qui manque
```

`1-start.sh` retire toute réplication du labo et remet le catalogue de `PachadataTraining` dans
son état d'origine (`demos/module_04/99-cleanup.sh`), remonte le distributeur du module 2
(`setup/repl-distributor.sh`) et crée sur `rpllab3` la base `ex_catalog`, vide.
`demos/module_04/99-cleanup.sh` retire tout à la fin, `ex_catalog` et la catégorie `EX` comprises.

## La consigne

1. Sur `rpllab1`, créez l'agent de lecture du journal de `PachadataTraining`, puis une
   publication transactionnelle nommée `ex_pubCatalog`, active, en `concurrent`, qui accepte
   le pull, avec les trois tables pour articles.
2. Abonnez `ex_catalog` en push. L'agent de distribution se connecte à l'abonné en
   authentification SQL Server (`sa` et le mot de passe du labo) et tourne en continu.
3. Livrez l'instantané initial. Si la livraison échoue, lisez `MSdistribution_history` et
   `MSrepl_errors` dans la base `distribution` de `rpllab2`.
4. Sur `rpllab1`, ajoutez à `Course.Category` la catégorie `EX`, libellé `Exercise`,
   description `Category of the exercise of module 4`, et vérifiez qu'elle arrive dans
   `ex_catalog`.
5. Postez un jeton de suivi sur `ex_pubCatalog` et lisez sa latence.
6. Lancez `check.sh` : il sort en 0 quand tout tient.

`check.sh` lit l'état des trois instances : `syspublications`, `sysarticles` et
`Course.Category` sur `rpllab1` ; la planification, l'activité et l'historique de l'agent de
distribution, et les jetons de suivi, sur `rpllab2` ; sur `rpllab3`, la catégorie `EX` et, table
par table, le nombre de lignes et une somme de contrôle (`CHECKSUM_AGG(BINARY_CHECKSUM(*))`)
comparés à ceux de l'éditeur. Il ne lit jamais vos commandes.

Un corrigé est dans `solution/`. Essayez d'abord sans lui.

---

# Exercise of module 4: a transactional publication

Publish `Course.Category`, `Course.Course` and `Course.Session` by transactional replication
(publication `ex_pubCatalog`, active, concurrent snapshot processing, pull allowed) to the
database `ex_catalog` on `rpllab3`, push subscription with a SQL Server login and a continuous
Distribution Agent. Deliver the initial snapshot, insert the category `EX` (`Exercise`,
`Category of the exercise of module 4`) on the publisher and check that it arrives, then post a
tracer token. `1-start.sh` builds the distributor and an empty `ex_catalog`, `check.sh` exits
with 0 when the state holds and with 1 otherwise. The solution is in `solution/`.
