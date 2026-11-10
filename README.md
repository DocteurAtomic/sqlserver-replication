# SQL Server, la réplication

Code et données du cours en ligne « SQL Server, la réplication » de Docteur Atomic
(https://www.docteuratomic.com) : le labo, les démonstrations de chaque module, les exercices,
leurs corrigés et leurs contrôles.

## Le labo

Trois instances SQL Server 2025 Developer en conteneurs, aux rôles fixés :

| Conteneur | Rôle | Port sur l'hôte |
|---|---|---|
| `rpllab1` | éditeur, base `PachadataTraining` | 14731 |
| `rpllab2` | distributeur | 14732 |
| `rpllab3` | abonné | 14733 |

Il faut Docker (Docker Desktop sous Windows ou macOS sur processeur x86-64) ou Podman, environ
7 Go de mémoire libre et 4 Go de disque. Les images de SQL Server 2025 ne sont prises en charge
que sur un hôte Linux x86-64 : un Mac Apple Silicon ne convient pas.

    ./setup/install.sh                                    # Docker
    COMPOSE="podman compose" ENGINE=podman ./setup/install.sh   # Podman
    ./setup/test-lab.sh                                   # contrôle
    ./setup/stop.sh                                       # arrêt propre

`install.sh` télécharge la sauvegarde de `PachadataTraining` (600 Mo), vérifie sa somme, démarre
les trois instances et restaure la base sur `rpllab1`. Le labo est livré sans réplication :
chaque module construit ce dont il a besoin par son `demos/module_NN/00-setup.sh`, et le défait
par son `99-cleanup.sh`.

Le mot de passe `sa` du labo est écrit en clair dans `compose.yaml` : c'est un labo, ne le
réutilisez nulle part.

`docker stop` tue SQL Server sans lui laisser fermer ses bases : arrêtez le labo par
`./setup/stop.sh`.

Si une connexion au distributeur échoue en Msg 17803 ou en délai de connexion, `rpllab2` manque
de mémoire : trop d'agents continus tournent (une publication oubliée par un exercice, par
exemple). `./setup/repl-remove.sh` retire toute la réplication du labo ; au besoin, redémarrez
d'abord `rpllab2` (`docker restart rpllab2`).

## Les conventions

- Un script SQL dit sur quelle instance il tourne dans ses cinq premières lignes
  (`-- instance: rpllab2`) ; une scène à plusieurs instances est un script shell.
- Les agents de réplication travaillent à leur rythme : les scripts attendent un état
  (`wait_for` de `setup/lib.sh`), jamais une durée fixe.
- Chaque exercice a son énoncé (`README.md`), ses fichiers de départ, un corrigé dans
  `solution/`, et un `check.sh` qui sort en 0 quand l'état demandé est atteint et en 1 sinon.
- `./setup/run-scripts.sh` rejoue tout, module par module ; l'intégration continue le lance à
  chaque push.

Licence MIT.

---

# SQL Server Replication

Code and data of the Docteur Atomic online course "SQL Server Replication": the lab, the
demos of each module, the exercises, their solutions and their checks.

## The lab

Three SQL Server 2025 Developer instances in containers, with fixed roles: `rpllab1`
publisher (database `PachadataTraining`, port 14731), `rpllab2` distributor (14732), `rpllab3`
subscriber (14733). You need Docker (Docker Desktop on Windows or on an x86-64 Mac) or Podman,
about 7 GB of free memory and 4 GB of disk. SQL Server 2025 images are supported on x86-64
Linux hosts only: an Apple Silicon Mac does not fit.

    ./setup/install.sh                                    # Docker
    COMPOSE="podman compose" ENGINE=podman ./setup/install.sh   # Podman
    ./setup/test-lab.sh                                   # check
    ./setup/stop.sh                                       # clean stop

The lab comes without replication: each module builds what it needs with its
`demos/module_NN/00-setup.sh` and removes it with its `99-cleanup.sh`. The `sa` password is in
clear text in `compose.yaml`: it is a lab, do not reuse it anywhere. Stop the lab with
`./setup/stop.sh`, never `docker stop`, which kills SQL Server.

MIT License.
