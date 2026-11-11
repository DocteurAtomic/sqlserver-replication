# Exercice du module 6 : un article de plus et un filtre de lignes

La copie de test du site d'inscription, `ex_catalog`, veut aussi les titres des cours, et ne
doit plus voir les sessions annulées. Ajoutez `Course.CourseLanguage` à la publication
`ex_pubCatalog` de l'exercice 4 sans recopier `Course.Category` ni `Course.Course`, filtrez
`Course.Session` sur son statut, puis annulez une session et vérifiez qu'elle quitte l'abonné.

## Le départ

```bash
./exercises/module_06/1-start.sh       # avec Podman : ENGINE=podman ./exercises/module_06/1-start.sh
./exercises/module_06/check.sh         # sort en 1 et dit ce qui manque
```

`1-start.sh` retire toute réplication du labo et remet `PachadataTraining` dans son état
d'origine (`demos/module_06/99-cleanup.sh`), puis rejoue l'exercice 4 et son corrigé :
`ex_pubCatalog` (active, `concurrent`, `@immediate_sync` à `false`) livrée en push à
`ex_catalog` sur `rpllab3`. Comptez une minute et demie. `demos/module_06/99-cleanup.sh`
retire tout à la fin, `ex_catalog` et le statut de la session 17622 compris.

## La consigne

1. Sur `rpllab1`, ajoutez l'article `CourseLanguage` (table `Course.CourseLanguage`) à
   `ex_pubCatalog`, et abonnez-y `ex_catalog`.
2. Filtrez l'article `Session` : `ex_catalog` ne doit recevoir que les sessions dont le
   `StatusCode` n'est pas `CANCELED`, à l'instantané comme pour les modifications qui suivent.
3. Générez un instantané et vérifiez dans `MSdistribution_history` (base `distribution` de
   `rpllab2`) quelles tables il a copiées.
4. Sur `rpllab1`, annulez la session 17622 (`StatusCode = 'CANCELED'`) et vérifiez qu'elle
   disparaît de `ex_catalog`.
5. Lancez `check.sh` : il sort en 0 quand tout tient.

`check.sh` lit l'état des trois instances, jamais vos commandes. Sur `rpllab1`, les articles de
`ex_pubCatalog`, la procédure de filtre de l'article `Session` et le statut de la session
17622. Sur `rpllab2`, l'abonnement de `ex_catalog` à `CourseLanguage`, le nombre d'instantanés
appliqués à `Category` et à `Course` dans l'historique de l'agent de distribution (un seul :
celui de l'exercice 4), et l'état de l'agent. Sur `rpllab3`, le nombre de lignes et la somme de
contrôle (`CHECKSUM_AGG(BINARY_CHECKSUM(*))`) de `CourseLanguage`, et ceux de `Session`
comparés aux sessions non annulées de l'éditeur.

Un corrigé est dans `solution/`. Essayez d'abord sans lui.

---

# Exercise of module 6: one more article and a row filter

Add the article `CourseLanguage` (`Course.CourseLanguage`) to the publication `ex_pubCatalog`
of exercise 4 and subscribe `ex_catalog` to it, without copying `Course.Category` or
`Course.Course` again; filter the article `Session` so that canceled sessions
(`StatusCode = 'CANCELED'`) reach the subscriber neither through the snapshot nor through the
changes; generate a snapshot; cancel session 17622 on the publisher and check that it leaves
`ex_catalog`. `1-start.sh` rebuilds the end of exercise 4, `check.sh` exits with 0 when the
state holds and with 1 otherwise. The solution is in `solution/`.
