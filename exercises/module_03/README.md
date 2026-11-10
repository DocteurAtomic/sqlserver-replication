# Exercice du module 3 : une publication d'instantané

La finance veut aussi, chaque nuit, trois autres tables de référence : `Reference.Currency`,
`Reference.PaymentMethod` et `Reference.Holiday`. Publiez-les par instantané vers une base
`ex_ref` de `rpllab3`, avec des agents qui tournent une fois par nuit, et livrez un premier
instantané sans attendre la nuit.

## Le départ

```bash
./exercises/module_03/1-start.sh       # avec Podman : ENGINE=podman ./exercises/module_03/1-start.sh
./exercises/module_03/check.sh         # sort en 1 et dit ce qui manque
```

`1-start.sh` retire toute réplication du labo (`setup/repl-remove.sh`), remonte le distributeur
du module 2 (`setup/repl-distributor.sh`) et crée sur `rpllab3` la base `ex_ref`, vide.
`demos/module_03/99-cleanup.sh` retire tout à la fin, `ex_ref` comprise.

## La consigne

1. Sur `rpllab1`, créez dans `PachadataTraining` une publication d'instantané nommée
   `ex_pubRef`, active, avec les trois tables pour articles.
2. Planifiez son agent d'instantané chaque nuit à 01:00, une seule fois.
3. Abonnez `ex_ref` sur `rpllab3` en push. L'agent de distribution se connecte à l'abonné en
   authentification SQL Server (`sa` et le mot de passe du labo) et tourne chaque nuit à 02:00,
   une seule fois.
4. Livrez un premier instantané tout de suite : lancez l'agent d'instantané, puis l'agent de
   distribution. Si la livraison échoue, lisez `MSdistribution_history` et `MSrepl_errors` dans
   la base `distribution` de `rpllab2`.
5. Lancez `check.sh` : il sort en 0 quand tout tient.

`check.sh` lit l'état des trois instances : `syspublications` et `sysarticles` sur `rpllab1`,
la planification des deux travaux et `MSdistribution_history` sur `rpllab2`, les nombres de
lignes de `ex_ref` sur `rpllab3`, comparés à ceux de l'éditeur. Il ne lit jamais vos commandes.

Un corrigé est dans `solution/`. Essayez d'abord sans lui.

---

# Exercise of module 3: a snapshot publication

Publish `Reference.Currency`, `Reference.PaymentMethod` and `Reference.Holiday` by snapshot
(publication `ex_pubRef`, active) to the database `ex_ref` on `rpllab3`, push subscription with
a SQL Server login, the Snapshot Agent once a night at 01:00 and the Distribution Agent once a
night at 02:00, then deliver a first snapshot without waiting for the night. `1-start.sh` builds
the distributor and an empty `ex_ref`, `check.sh` exits with 0 when the state holds and with 1
otherwise. The solution is in `solution/`.
