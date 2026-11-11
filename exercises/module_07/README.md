# Exercice du module 7 : la requête du matin et l'échec d'un agent

L'équipe veut savoir chaque matin, sans ouvrir de moniteur, si la copie de test du site
d'inscription, `ex_catalog`, est à jour, et être prévenue quand son agent de distribution
échoue. Écrivez la requête de surveillance, activez l'alerte d'échec d'agent, et mettez en
place ce qui la remplace sous Linux.

## Le départ

```bash
./exercises/module_07/1-start.sh       # avec Podman : ENGINE=podman ./exercises/module_07/1-start.sh
./exercises/module_07/check.sh         # sort en 1 et dit ce qui manque
```

`1-start.sh` retire toute réplication du labo (`demos/module_07/99-cleanup.sh`), puis rejoue
l'exercice 4 et son corrigé : `ex_pubCatalog` livrée en push à `ex_catalog` sur `rpllab3`.
Comptez un peu plus d'une minute. `demos/module_07/99-cleanup.sh` retire tout à la fin, la base
`ex_monitor` et le travail de l'exercice compris.

## La consigne

Tout se fait sur `rpllab2`, le distributeur.

1. Créez une base `ex_monitor`, et dedans une procédure `dbo.ReplHealth` qui rend une ligne par
   abonnement du distributeur, avec ces cinq colonnes, dans cet ordre : `publication`,
   `subscriber_db`, `agent_status` (le `runstatus` de la dernière ligne d'historique de l'agent
   de distribution), `latency_seconds` (la latence de la dernière livraison, en secondes) et
   `pending_commands` (les commandes pas encore livrées). Lisez les tables de la base
   `distribution` : `sp_replmonitorhelpsubscription` ne se capture pas par `INSERT ... EXEC`
   (Msg 8164), et `check.sh` capture votre procédure de cette façon.
2. Activez l'alerte `Replication: agent failure` (message 14151).
3. Créez dans `ex_monitor` une table `dbo.AgentFailure`, et un travail de l'Agent nommé
   `ex_agent_failure_watch`, planifié au moins toutes les cinq minutes, qui y copie les échecs
   d'agents (14151) que les agents écrivent dans `msdb.dbo.sysreplicationalerts`. La table doit
   avoir au moins les colonnes `time` et `subscriber_db`.
4. Lancez `check.sh`. Il répond « The morning query sees the subscription of ex_catalog, and
   the failure of its agent reached ex_monitor.dbo.AgentFailure. » et sort en 0 quand tout
   tient.

`check.sh` lit d'abord l'état : l'alerte, le travail et sa planification, la procédure et la
table. S'il manque quelque chose, il le dit et s'arrête sans rien provoquer. Sinon, il vérifie
que `ReplHealth` voit l'agent de `ex_catalog` en marche sans commande en attente, puis il met
`ex_catalog` hors ligne et insère la catégorie `X7` sur `rpllab1`. `ReplHealth` doit alors
rendre l'agent en échec (6) avec au moins une commande en attente, et une ligne de
`ex_catalog` doit arriver dans `AgentFailure`. Il remet ensuite `ex_catalog` en ligne et
supprime `X7`, quoi qu'il arrive, et attend que l'agent soit reparti. Comptez une à trois
minutes : votre travail ne tourne qu'une fois par minute.

## À réfléchir

- Après le contrôle, que vaut `occurrence_count` de l'alerte 14151 dans `msdb.dbo.sysalerts` ?
  Que dit `/var/opt/mssql/log/sqlagent.out` au démarrage de l'Agent ?
- Pourquoi le travail marque-t-il les lignes copiées (`status = 1`) au lieu de relire toute la
  table à chaque passage ?
- Que rend `sp_replmonitorhelpsubscription` pendant que `ex_catalog` est hors ligne, et dans
  quel ordre range-t-il les abonnements ?
