# Exercice du module 12

Objectif : lire ce qu'une topologie peer-to-peer laisse derrière elle (l'erreur de l'agent de
distribution, les tables de conflits des deux politiques, les colonnes cachées, les réponses
des nœuds) et répondre à dix questions dont `check.sh` contrôle les réponses.

SQL Server sous Linux ne prend pas en charge la réplication peer-to-peer. L'exercice se fait
donc sur les sorties réelles des démonstrations du module, relevées sur deux instances SQL
Server 2025 pour Windows (SQL01, le nœud de Paris, et SQL02, celui de Lyon, chacun son propre
distributeur) et livrées dans [`data/windows/module_12`](../../data/windows/module_12). Il ne
touche pas au labo.

## Les fichiers de données

| Fichier | Ce qu'il contient | Script qui l'a produit |
|---|---|---|
| `reconnect_sql01.txt` | l'agent de distribution de Paris vers Lyon qui rencontre le conflit sur le cours 4, politique par défaut | `demos/module_12/12-reconnect.sql` sur SQL01 |
| `conflict_course_sql01.csv`, `conflict_course_sql02.csv` | la table de conflits de `Course` sur chaque nœud, après la reprise | `export/1-export.sql`, `PART=course` |
| `conflict_session_sql01.csv`, `conflict_session_sql02.csv` | la table de conflits de `Session`, politique du dernier écrivain, avec l'heure UTC de chaque écriture | `export/1-export.sql`, `PART=session` |
| `publications_sql01.csv`, `publications_sql02.csv` | les publications de chaque nœud, leur identifiant d'origine, leur politique | `export/1-export.sql`, `PART=publications` |
| `hidden_columns_sql01.txt` | les colonnes cachées lues par la connexion administrateur dédiée | `demos/module_12/20-hidden-columns.sql` |
| `peer_request_sql01.txt`, `peer_responses_sql01.txt` | une demande de réponse pendant que l'agent de Lyon est arrêté, puis après son redémarrage | `22-request-response.sql`, `24-read-responses.sql` |
| `requirements_sql01.txt` | ce qu'une publication peer-to-peer refuse | `09b-requirements.sql` |

Les CSV sortent de `sqlcmd -s ","` : une ligne d'en-tête, une ligne de tirets, puis les lignes.
Les virgules des textes de raison y sont remplacées par des points-virgules. Dans les tables de
conflits, `origin` est l'identifiant d'origine du nœud qui a écrit la version, `is_winner` vaut
1 pour la version gardée.

```bash
./exercises/module_12/1-start.sh
# remplissez exercises/module_12/work/answers.csv
./exercises/module_12/check.sh
```

## Les questions

Une réponse par ligne, après le point-virgule, sans espace ni texte autour.

| Question | Ce qu'on demande |
|---|---|
| `1-conflict-error` | Quel numéro d'erreur l'agent de distribution a-t-il reçu en rencontrant le conflit sur le cours 4 ? |
| `2-conflict-kind` | Quel type de conflit le message nomme-t-il ? Recopiez-le tel qu'il est écrit. |
| `3-originator-winner` | Politique par défaut : quel identifiant d'origine a écrit la version gagnante du cours 4 ? |
| `4-course-4-price` | Quel prix le cours 4 a-t-il gardé sur les deux nœuds ? Écrivez-le comme dans le fichier. |
| `5-lastwriter-seats` | Politique du dernier écrivain : combien de places la session 110 a-t-elle gardées ? |
| `6-lastwriter-origin` | Quel identifiant d'origine a écrit cette version ? |
| `7-delete-update-type-paris` | La session 121 a été supprimée à Lyon, puis modifiée plus tard à Paris. Quel type de conflit (un nombre) Paris a-t-il enregistré ? |
| `8-p2p-cd-id-course-4` | D'après le premier octet de `$sys_p2p_cd_id`, quel identifiant d'origine a écrit la ligne du cours 4 qui est en place ? |
| `9-response-before-restart` | Que vaut `received_date` de la réponse de Lyon tant que son agent est arrêté ? |
| `10-filter-error` | Quel numéro d'erreur reçoit un filtre de lignes sur un article peer-to-peer ? |

`check.sh` lit la valeur attendue dans les fichiers de `data/windows/module_12` à chaque
lancement, jamais dans le corrigé. Sur l'état de départ, il signale dix questions sans réponse
et sort en 1 ; il répond « The answers hold. » et sort en 0 quand les dix tiennent.
`solution/answers.csv` est le corrigé, à lire après avoir cherché ; `solution/2-solution.sh`
le recopie dans `work/answers.csv`.

## Pour qui a un Windows

Avec deux instances SQL Server 2025 pour Windows en édition Enterprise ou Developer, dans un
domaine, rejouez les démonstrations de `demos/module_12` dans l'ordre de leurs numéros (voir
le `README.md` de ce dossier), puis produisez vos propres fichiers avec `export/1-export.sql`
sur chaque nœud. Vos identifiants de transaction et vos horodatages différeront ; les numéros
d'erreur, les types de conflit, les gagnants et les comptes de lignes, non.

## À réfléchir

- Les questions 3 et 6 donnent deux gagnants différents pour deux conflits de même forme.
  Qu'est-ce qui a décidé dans chaque cas, et lequel des deux aurait changé si Paris avait
  écrit en premier ?
- La session 121 a disparu des deux nœuds alors que la modification de Paris était la plus
  récente. Est-ce un défaut de la politique, ou une règle à connaître avant de la choisir ?
- Pourquoi la question 9 aurait-elle bloqué un changement de schéma de `Course` ?
