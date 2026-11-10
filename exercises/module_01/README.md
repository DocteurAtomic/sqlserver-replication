# Exercice du module 1

Objectif : pour six demandes de PachaData, choisir la technique qui y répond (une réplication
ou une de ses voisines) et dire pourquoi, puis faire contrôler ses choix.

L'exercice ne touche pas au labo : il se joue dans un fichier.

## Les six demandes

| Demande | Ce que l'équipe demande |
|---|---|
| `1-registration-catalog` | Le site d'inscription lit les catégories, les cours et les sessions (`Course.Category`, `Course.Course`, `Course.Session`) en interrogeant la production. Il veut ces trois tables dans sa propre base, sur une autre instance, en lecture seule, avec quelques secondes de retard au plus. |
| `2-finance-references` | Le service financier veut chaque nuit les pays, les villes et les taux de TVA (`Reference.Country`, `Reference.City`, `Reference.VatRate`) dans la base de son serveur de rapports. Une journée de retard ne le gêne pas. |
| `3-reporting-whole-database` | L'équipe des rapports veut une copie lisible de toute la base `PachadataTraining`, et la direction veut que cette copie prenne le relais, sans restauration, si le serveur de production s'arrête. |
| `4-analytics-in-fabric` | L'équipe d'analyse veut les tables de `PachadataTraining` dans Microsoft Fabric, mises à jour en continu, sans écrire de chargement. |
| `5-two-sites-writing` | Les centres de Paris et de Lyon veulent chacun leur serveur, et écrire tous les deux dans le même catalogue ; chaque site doit voir les écritures de l'autre. |
| `6-crm-changed-rows` | Un travail de synchronisation pousse les contacts vers le CRM par son API. Il veut savoir quelles lignes de `Contact.Contact` ont changé depuis son dernier passage, puis les lire lui-même. |

## Les fichiers

- `techniques.csv` : les codes des techniques parmi lesquelles choisir.
- `answers-template.csv` : les six demandes, sans choix.
- `1-start.sh` copie le modèle dans `work/answers.csv`, le fichier que vous remplissez. Le
  relancer repart de zéro ; vos réponses précédentes sont gardées dans
  `work/answers.csv.bak`.
- `check.sh` contrôle vos choix et dit ce qui ne tient pas.
- `solution/answers.csv` est un corrigé, à lire après avoir cherché ; `solution/2-solution.sh`
  le recopie dans `work/answers.csv`. D'autres réponses sont justes : `check.sh` les accepte.

```bash
./exercises/module_01/1-start.sh
# remplissez exercises/module_01/work/answers.csv
./exercises/module_01/check.sh
```

## La consigne

1. Lisez `techniques.csv`.
2. Dans `work/answers.csv`, pour chaque demande, écrivez le code de la technique dans la
   deuxième colonne et la raison en une ou deux phrases dans la troisième. Le séparateur est
   le point-virgule : n'en mettez pas dans la raison.
3. Lancez `check.sh`. Sur l'état de départ, il signale six demandes sans choix et sort en 1.
   Corrigez jusqu'à ce qu'il réponde « The choices hold. » et sorte en 0.

`check.sh` refuse un code absent de `techniques.csv`, une raison de moins de vingt caractères
et une technique qui ne répond pas à la demande. Quand plusieurs techniques y répondent, il
les accepte toutes, et c'est votre raison qui départage.

## À réfléchir

- Les demandes 1 et 4 visent la même base. Sous SQL Server 2025, que dit la
  documentation de Fabric d'une base déjà publiée ? Quelle demande faudrait-il servir
  autrement, et comment ?
- Pour la demande 5, la réplication d'égal à égal demande l'édition Enterprise. Si PachaData
  paie l'édition Standard, que reste-t-il, et que doit alors faire l'application ?
- Pour la demande 2, une réplication transactionnelle tiendrait aussi. Qu'est-ce qui la rend
  plus lourde à exploiter qu'un instantané par nuit ?
- Pour la demande 6, quelle différence fait-il, pour le travail du CRM, entre savoir qu'une
  ligne a changé (suivi des modifications) et lire chaque version qu'elle a eue (capture des
  changements de données) ?
