# Exercice du module 11

Objectif : lire ce qu'une réplication de fusion laisse derrière elle (tables de conflits,
sessions de l'agent de fusion, partitions, plages d'identité) et répondre à dix questions
dont `check.sh` contrôle les réponses.

SQL Server sous Linux ne prend pas en charge la réplication de fusion. L'exercice se fait donc
sur les sorties réelles des démonstrations du module, relevées sur deux instances SQL Server
2025 pour Windows (SQL01, éditeur et distributeur local, et SQL02, qui héberge les bases des
deux centres) et livrées dans
[`data/windows/module_11`](../../data/windows/module_11). Il ne touche pas au labo.

## Les fichiers de données

| Fichier | Ce qu'il contient | Script qui l'a produit |
|---|---|---|
| `conflicts_info.csv` | `MSmerge_conflicts_info` de `m11_pubCentres` : un conflit par ligne, son type, son code, sa raison | `export/1-conflicts.sql`, après la démonstration 17 |
| `conflict_session.csv` | la table de conflits de l'article `Session` : la version perdante de chaque ligne | idem |
| `merge_sessions.csv` | les synchronisations de `m11_pubByCentre`, centre par centre, dans l'ordre (`sync_number`) | `export/2-merge.sql`, à la fin |
| `partition_groups.csv` | les partitions de `m11_pubByCentre` et la valeur de `HOST_NAME()` de chacune | idem |
| `identity_ranges.csv` | les plages d'identité de `Attendance` après la démonstration 33 | idem |
| `articles.csv` | les articles des publications, avec leur suivi, leurs options de chargement et leur filtre | idem |
| `exhaust_range.txt` | la sortie de `demos/module_11/31-exhaust-range.sql` sur SQL02 | la démonstration elle-même |
| `centre_partition.txt` | la sortie de `demos/module_11/24-centre-partition.sql` sur SQL02 | idem |

Les CSV sortent de `sqlcmd -s ","` : une ligne d'en-tête, une ligne de tirets, puis les lignes.
Les virgules des textes de raison y sont remplacées par des points-virgules.

```bash
./exercises/module_11/1-start.sh
# remplissez exercises/module_11/work/answers.csv
./exercises/module_11/check.sh
```

## Les questions

Une réponse par ligne, après le point-virgule, sans espace ni texte autour.

| Question | Ce qu'on demande |
|---|---|
| `1-row-conflict-winner` | Session 1002 : l'éditeur a changé la salle, Lille le nombre de places. Quelle source de données le résolveur a-t-il retenue ? |
| `2-lost-seats-1002` | Quel nombre de places Lille a-t-il perdu sur la session 1002 ? |
| `3-insert-conflict-types` | Session 2001, créée des deux côtés avec la même clé : quels types de conflit sont enregistrés ? Écrivez les deux nombres séparés par une espace, du plus petit au plus grand. |
| `4-late-column-tracking-type` | Le dernier conflit est survenu après le passage de `Session` au suivi par colonne, sur deux colonnes différentes. Quel est son type ? |
| `5-lille-first-download` | Combien de lignes la première synchronisation de Lille sur `m11_pubByCentre` a-t-elle insérées chez Lille ? |
| `6-move-deletes-lille` | La session 1004 passe de Lille à Genève. Combien de lignes la synchronisation suivante a-t-elle supprimées chez Lille ? |
| `7-lille-host-name` | Quelle valeur de `HOST_NAME()` désigne la partition de Lille ? |
| `8-rows-before-548` | Combien de lignes Lille a-t-il insérées hors ligne avant l'erreur 548 ? |
| `9-lille-new-range` | Après la synchronisation, à quelle valeur commence la nouvelle plage de Lille (`range_begin`) ? |
| `10-download-only-error` | Quel numéro d'erreur reçoit une mise à jour de `Centre` chez Lille ? |

`check.sh` lit la valeur attendue dans les fichiers de `data/windows/module_11` à chaque
lancement, jamais dans le corrigé. Sur l'état de départ, il signale dix questions sans réponse
et sort en 1 ; il répond « The answers hold. » et sort en 0 quand les dix tiennent.
`solution/answers.csv` est le corrigé, à lire après avoir cherché ; `solution/2-solution.sh`
le recopie dans `work/answers.csv`.

## Pour qui a un Windows

Avec deux instances SQL Server 2025 pour Windows (Developer convient) dans un domaine, ou une
seule instance qui joue les deux rôles, rejouez les démonstrations de `demos/module_11` dans
l'ordre de leurs numéros (voir le `README.md` de ce dossier), puis produisez vos propres
fichiers avec les deux scripts de `export/`. Vos chiffres d'identité et vos horodatages
différeront ; les types de conflit, les codes d'erreur et les comptes de lignes, non.

## À réfléchir

- La question 3 laisse deux versions différentes de la session 2001 sur deux nœuds. Laquelle
  des deux a fini par gagner, et par quel geste ? (Relisez la vidéo sur les conflits.)
- La question 4 montre un conflit que le suivi par colonne aurait dû éviter. Quelle différence
  y a-t-il avec la publication `m11_pubByCentre`, où le même geste n'en produit aucun ?
- Le filtre de `HOST_NAME()` est surchargé par `@hostname`. Que se passe-t-il si un centre
  se synchronise avec la valeur d'un autre ? Le filtre est-il une sécurité ?
