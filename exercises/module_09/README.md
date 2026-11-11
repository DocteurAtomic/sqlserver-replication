# Exercice du module 9 : le profil de la clôture mensuelle

Le service financier ferme le mois dans `ex_billing` sur `rpllab1` : 200 000 lignes de facture
changent de statut, en 2 000 transactions de 100 lignes. La clôture tombe pendant la fenêtre de
maintenance du serveur de rapports, l'agent de distribution est arrêté, et 200 000 commandes
attendent dans la base `distribution`. À la reprise, avec le profil par défaut, la copie
`ex_billing` de `rpllab3` met plus d'une minute à recevoir la clôture complète (73 à 84 s sur le
labo du cours, trois conteneurs sur une machine). Donnez à cet agent un profil fait pour ce
rattrapage.

## Le départ

```bash
./exercises/module_09/1-start.sh             # avec Podman : ENGINE=podman ./exercises/module_09/1-start.sh
./exercises/module_09/check.sh               # sort en 1 et dit ce qui manque
./exercises/module_09/tools/month-end.sh     # joue la clôture et mesure le rattrapage
```

`1-start.sh` retire toute réplication du labo (`demos/module_09/99-cleanup.sh`), monte le
distributeur, crée `ex_billing` sur `rpllab1` (200 000 lignes copiées de
`Enrollment.InvoiceLine`) et la publie par `ex_pubBilling` vers `ex_billing` sur `rpllab3`.
Comptez une minute. `demos/module_09/99-cleanup.sh` retire tout à la fin, profils
compris.

`tools/month-end.sh` arrête l'agent de distribution de `ex_billing`, joue la clôture, attend
que les 200 000 commandes soient dans `distribution`, relance l'agent, puis lit chaque seconde
les commandes en attente jusqu'à ce que l'abonné ait tout. Il affiche le compte 20 secondes
après la relance et la durée du rattrapage. Lancez-le avant de toucher à quoi que ce soit.

## La consigne

- Créez, sur le distributeur, un profil d'agent de distribution à vous. Le nom est libre.
- Réglez-y au moins un des paramètres que le module a mesurés : `-CommitBatchSize` à 1 000 ou
  plus, `-CommitBatchThreshold` à 10 000 ou plus, ou `-SubscriptionStreams` à 2 ou plus. Sur
  le labo, chacun a ramené le rattrapage de plus de 70 secondes à moins de 25.
- Affectez ce profil à l'agent de distribution de `ex_billing`, et faites-le prendre en compte.
- Ne mettez aucun de ces paramètres sur la commande du travail de l'agent : le réglage doit
  vivre dans le profil.
- Rejouez `tools/month-end.sh` et comparez.
- Lancez `check.sh`. Il répond « The Distribution Agent of ex_billing applies the month-end
  closing with its own profile. » et sort en 0 quand tout tient.

`check.sh` lit un état : le profil de l'agent de `ex_billing` est un profil utilisateur
(`type` 1), il a au moins un des trois réglages, la commande du travail ne le contredit pas, et
l'agent tourne. Puis il joue la clôture et attend que les 200 000 lignes arrivent sans commande
en attente, cinq minutes au plus. Le compte de commandes en attente à 20 secondes est affiché,
pas jugé : il dépend de la machine. Moins d'une minute sur le labo.

## À réfléchir

- Avec le profil par défaut, que vaut le compte de commandes en attente 20 secondes après la
  relance ? Les lignes sont-elles lisibles chez l'abonné à ce moment ? Essayez une lecture en
  `READ UNCOMMITTED` puis une lecture normale.
- Dans quelle base trouvez-vous votre profil, et pourquoi pas dans `distribution` ?
- Si vous aviez mis `-CommitBatchSize 50` sur la commande du travail, quelle valeur l'agent
  aurait-il prise ?
