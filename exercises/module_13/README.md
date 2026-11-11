# Exercice du module 13

Le site d'inscription n'a plus besoin du catalogue répliqué. Retirez toute la réplication du
labo, sur les trois instances, sans perdre les données que l'abonné a reçues, et prouvez qu'il
ne reste rien.

## Le départ

```bash
./exercises/module_13/1-start.sh       # avec Podman : ENGINE=podman ./exercises/module_13/1-start.sh
./exercises/module_13/check.sh         # sort en 1 et dit ce qui reste
```

`1-start.sh` retire toute réplication du labo (`demos/module_13/99-cleanup.sh`), monte le
distributeur sur `rpllab2` et publie le catalogue de `PachadataTraining` par `ex_pubCatalog`
vers `ex_catalog` sur `rpllab3`, comme le corrigé de l'exercice 4, puis attend la livraison
de l'instantané. Comptez une minute. `demos/module_13/99-cleanup.sh` retire tout à la fin,
`ex_catalog` comprise.

## La consigne

1. Retirez la réplication avec les procédures de la réplication, dans un ordre qu'elles
   acceptent, sans `@no_checks` ni `@ignore_distributor`, et sans `setup/repl-remove.sh`.
2. Ne supprimez ni `PachadataTraining` sur `rpllab1`, ni `ex_catalog` sur `rpllab3` : les
   données de l'abonné restent.
3. Lancez `check.sh` : il sort en 0 quand il ne reste rien.

`check.sh` lit un état, instance par instance : `is_distributor`, `is_published` et
`is_merge_published` dans `sys.databases`, les travaux de catégorie `REPL-%`, `sys.servers`
hors l'instance elle-même, la connexion `distributor_admin`, `msdb.dbo.MSdistpublishers` ;
sur `rpllab1`, `sp_get_distributor` ; sur `rpllab3`, la table `dbo.MSreplication_subscriptions`
de chaque base. Chacune de ces lectures doit revenir vide. Il vérifie enfin que `ex_catalog` a autant
de sessions que `PachadataTraining`.

## À réfléchir

- Pourquoi `check.sh` ne lit-il pas la colonne `is_subscribed` de `sys.databases` sur
  `rpllab3` ?
- Que reste-t-il sur `rpllab3` après `sp_dropsubscription` sur l'éditeur ?
- Dans quel ordre l'éditeur et le distributeur doivent-ils se détacher l'un de l'autre, et
  qu'est-ce qui reste ensuite sur chacun ?

## Le corrigé

`solution/` contient quatre scripts SQL, à jouer dans l'ordre de leur nom, chacun sur
l'instance que sa première ligne nomme. Essayez avant de les lire.
