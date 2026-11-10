# Exercice du module 2 : le distributeur

Montez vous-même le distributeur du cours sur `rpllab2`, avec une base de distribution qui garde
les transactions 48 heures au plus et l'historique des agents quatre jours, puis enregistrez
`rpllab1` comme éditeur.

## Le départ

```bash
./exercises/module_02/1-start.sh       # avec Podman : ENGINE=podman ./exercises/module_02/1-start.sh
./exercises/module_02/check.sh         # sort en 1 et dit ce qui manque
```

`1-start.sh` retire toute réplication du labo (`setup/repl-remove.sh`), y compris le
distributeur que les démonstrations du module laissent. L'exercice ne crée rien d'autre ;
`demos/module_02/99-cleanup.sh` retire votre distributeur à la fin.

## La consigne

1. Sur `rpllab2`, déclarez l'instance comme distributeur. Choisissez le mot de passe de
   `distributor_admin` et notez-le.
2. Créez la base de distribution `ex_distribution`, avec une rétention maximale des transactions
   de 48 heures et un historique de quatre jours.
3. Enregistrez `rpllab1` comme éditeur de `ex_distribution`, avec le dossier d'instantané
   `/var/opt/mssql/share/repldata`, les agents se connectant à l'éditeur en authentification
   SQL Server (`sa` et le mot de passe du labo).
4. Sur `rpllab1`, déclarez `rpllab2` comme distributeur, par son nom.
5. Lancez `check.sh` : il sort en 0 quand tout tient.

`check.sh` lit l'état des deux instances : `sp_get_distributor` sur chacune,
`msdb.dbo.MSdistributiondbs` et `msdb.dbo.MSdistpublishers` sur `rpllab2`, le serveur lié
`repl_distributor` sur `rpllab1`. Il ne lit jamais vos commandes.

Un corrigé est dans `solution/`, un script par instance. Essayez d'abord sans lui.

---

# Exercise of module 2: the distributor

Build the course distributor on `rpllab2` yourself, with a distribution database that keeps
transactions 48 hours at most and agent history four days (96 hours), named `ex_distribution`,
then register `rpllab1` as its publisher (snapshot folder `/var/opt/mssql/share/repldata`,
agents connecting with a SQL Server login), and register `rpllab2` as the distributor of
`rpllab1`, by its name. `1-start.sh` gives the lab back without replication, `check.sh` exits
with 0 when the state holds and with 1 otherwise. The solution is in `solution/`.
