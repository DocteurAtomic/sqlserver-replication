# Exercice du module 10 : les agents de l'audit

L'audit de sécurité refuse que les agents de réplication se connectent sous `sa`. Reprenez la
publication de l'exercice 4, `ex_pubCatalog`, qui livre le catalogue de `PachadataTraining` à
`ex_catalog` sur `rpllab3`, et donnez à chacun de ses agents sa propre connexion SQL Server,
avec le moindre privilège. Retirez aussi de la liste d'accès de la publication le compte de
l'outil de rapports qu'on y a ajouté.

## Le départ

```bash
./exercises/module_10/1-start.sh       # avec Podman : ENGINE=podman ./exercises/module_10/1-start.sh
./exercises/module_10/check.sh         # sort en 1 et dit ce qui manque
```

`1-start.sh` retire toute réplication du labo (`demos/module_10/99-cleanup.sh`), monte le
distributeur, publie le catalogue par `ex_pubCatalog` vers `ex_catalog` comme le corrigé de
l'exercice 4, ajoute la catégorie `EX` et met la connexion `ex_reporting` dans la liste d'accès
de la publication. Comptez une minute. Les trois agents se connectent à l'éditeur et à
l'abonné sous `sa`. `demos/module_10/99-cleanup.sh` retire tout à la fin, connexions `ex_`
comprises.

## La consigne

1. Sur `rpllab1`, créez deux connexions SQL Server dont le nom commence par `ex_` : une pour
   l'agent de lecture du journal de `PachadataTraining`, une pour l'agent d'instantané de
   `ex_pubCatalog`. Chacune a un utilisateur dans `PachadataTraining`, le rôle `db_owner` de
   cette base, et aucun rôle de serveur.
2. Sur `rpllab3`, une connexion `ex_` pour l'agent de distribution de `ex_catalog`, avec le
   rôle `db_owner` de `ex_catalog` et aucun rôle de serveur.
3. Donnez ces connexions aux trois agents, mot de passe compris, par les procédures de la
   réplication (lisez leur signature dans `sys.all_parameters`).
4. Retirez `ex_reporting` de la liste d'accès de `ex_pubCatalog`.
5. Faites prendre les nouvelles connexions aux agents, et vérifiez sur quelle connexion chacun
   tourne.
6. Lancez `check.sh` : il sort en 0 quand tout tient.

La connexion des agents au distributeur ne change pas : sous Linux, l'agent tourne dans
l'Agent SQL Server de `rpllab2` et s'y connecte par son compte de service,
`NT AUTHORITY\NETWORK SERVICE`, membre de `sysadmin`. Le labo ne permet pas de la remplacer
(`@job_login` y échoue, module 10, vidéo 10.1) ; sur Windows, on donne à chaque agent un compte
Windows à lui.

`check.sh` lit l'état des trois instances : dans la base `distribution` de `rpllab2`, la
connexion enregistrée pour chaque agent (authentification SQL Server, autre que `sa`, deux
connexions différentes pour l'agent de lecture du journal et l'agent d'instantané, un mot de
passe enregistré) ; sur `rpllab1` et `rpllab3`, les rôles de ces connexions, la connexion sur
laquelle tournent l'agent de lecture du journal et l'agent de distribution, et la liste d'accès
de `ex_pubCatalog`. Il change enfin la description de la catégorie `EX` sur `rpllab1` et attend
qu'elle arrive sur `rpllab3`, deux minutes au plus. Il ne lit jamais vos commandes.

Un corrigé est dans `solution/`. Essayez d'abord sans lui.

## À réfléchir

- Après l'appel qui change la connexion d'un agent, sur quelle connexion tourne-t-il encore ?
- Que devient le mot de passe enregistré si vous rappelez `sp_changelogreader_agent` avec la
  seule connexion ?
- Pourquoi `ex_reporting` a-t-il besoin d'un utilisateur dans `PachadataTraining` pour entrer
  dans la liste d'accès, et que lui donne cette liste ?

---

# Exercise of module 10: the agents and the audit

The security audit refuses replication agents connected as `sa`. Give each agent of
`ex_pubCatalog` (the publication of exercise 4, `PachadataTraining` to `ex_catalog` on
`rpllab3`) its own SQL Server login whose name starts with `ex_`: two on `rpllab1`, for the Log
Reader Agent and the Snapshot Agent, `db_owner` of `PachadataTraining`; one on `rpllab3` for the
Distribution Agent, `db_owner` of `ex_catalog`; none of them in a server role. Remove
`ex_reporting` from the publication access list, make the agents take their new logins, and run
`check.sh`. The connection to the distributor stays the SQL Server Agent service account under
Linux. `1-start.sh` builds the starting state, `check.sh` exits with 0 when the state holds and
with 1 otherwise. The solution is in `solution/`.
