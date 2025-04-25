# Identifier l'utilisation mémoire d'un processus `sh` consommant 105MB

Plusieurs méthodes permettent d'identifier et d'analyser pourquoi un processus `sh` utilise 105MB de mémoire, ce qui est inhabituellement élevé pour un shell basique.

## 1. Outils de base pour mesurer l'utilisation mémoire

### Avec `ps`
```bash
ps -eo pid,comm,rss,vsz,args | grep -w sh | sort -k3 -n
```
- **RSS** (Resident Set Size): Mémoire physique utilisée (en KB)
- **VSZ** (Virtual Memory Size): Mémoire virtuelle totale (en KB)

### Avec `top` ou `htop`
```bash
top -p $(pgrep -d',' -f "sh")
# ou
htop -p $(pgrep -d',' -f "sh")
```

## 2. Outils avancés d'analyse mémoire

### `pmap` (détail de l'allocation mémoire)
```bash
pmap -x $(pgrep -f "sh.*105MB") | less
```
Affiche le détail des zones mémoire avec tailles et permissions.

### `/proc/<PID>/smaps` (analyse fine)
```bash
cat /proc/$(pgrep -f "sh.*105MB")/smaps | awk '/Size/{print $2}'
```

## 3. Identifier la cause de la consommation

### Vérifier les variables d'environnement
```bash
# Afficher les variables d'environnement du processus
xargs -0 -L1 -a /proc/$(pgrep -f "sh.*105MB")/environ
```

### Analyser le script en cours d'exécution
```bash
# Trouver le script associé
ls -l /proc/$(pgrep -f "sh.*105MB")/fd/ | grep -E '\.sh$|\.bash$'

# Voir le contenu du script
cat $(ls -l /proc/$(pgrep -f "sh.*105MB")/fd/ | awk '/\.sh$|\.bash$/{print $11}')
```

### Vérifier les allocations mémoire dynamiques
```bash
# Utiliser strace pour voir les allocations mémoire
strace -p $(pgrep -f "sh.*105MB") -e brk,mmap
```

## 4. Script d'analyse automatique

```bash
#!/bin/bash

PID=$(pgrep -f "sh.*105MB")

if [ -z "$PID" ]; then
    echo "Aucun processus sh consommant ~105MB trouvé"
    exit 1
fi

echo "Analyse du processus sh (PID: $PID) consommant 105MB"

echo -e "\n1. Informations de base (ps):"
ps -p $PID -o pid,ppid,user,%mem,%cpu,rss,vsz,cmd

echo -e "\n2. Détail de la mémoire (pmap):"
pmap -x $PID | tail -n1

echo -e "\n3. Fichiers ouverts:"
ls -l /proc/$PID/fd

echo -e "\n4. Variables d'environnement:"
xargs -0 -L1 -a /proc/$PID/environ | grep -vE '^(LS_COLORS|PATH|TERM|LANG|SSH)'

echo -e "\n5. Stack trace (peut nécessiter les droits root):"
pstack $PID 2>/dev/null || echo "pstack non disponible - essayez 'sudo gdb -p $PID'"
```

## 5. Causes possibles de haute consommation

1. **Grandes variables stockées**:
   - Tableaux/strings volumineux dans le script
   - Historique de commandes étendu (`HISTSIZE` trop grand)

2. **Fuites mémoire**:
   - Commandes internes ou externes qui fuient
   - Sous-processus accumulant de la mémoire

3. **Script mal écrit**:
   - Accumulation de données dans des variables
   - Fichiers chargés en mémoire

4. **Problèmes système**:
   - Fragmentation mémoire
   - Comportement anormal du kernel

Pour un processus `sh` standard, 105MB est exceptionnellement élevé et mérite une investigation approfondie.

# Simulation de consommation mémoire du processus `sh`

Voici des scripts et paramètres kernel pour faire varier la consommation mémoire du processus `sh` entre ~5MB et ~20MB.

## Scripts de test

### Script pour consommation minimale (~5MB)
```bash
#!/bin/sh
# Script minimal - mem_low.sh
while true; do
    sleep 1
done
```

### Script pour consommation moyenne (~10MB)
```bash
#!/bin/sh
# Script moyen - mem_medium.sh
VAR=$(seq 1 10000 | tr '\n' ' ')
while true; do
    echo "$VAR" > /dev/null
    sleep 1
done
```

### Script pour consommation élevée (~20MB)
```bash
#!/bin/sh
# Script gourmand - mem_high.sh
LARGE_VAR=$(dd if=/dev/urandom bs=1M count=15 2>/dev/null | base64)
while true; do
    echo "${LARGE_VAR:0:1000}" > /dev/null
    sleep 1
done
```

## Paramètres kernel influençant la mémoire

Vous pouvez ajuster ces paramètres pour influencer la consommation mémoire:

```bash
# Afficher les paramètres actuels
sysctl vm.overcommit_memory vm.overcommit_ratio vm.swappiness

# Modifier temporairement les paramètres
sudo sysctl -w vm.overcommit_memory=2       # Strict overcommit
sudo sysctl -w vm.overcommit_ratio=50      # 50% de RAM disponible
sudo sysctl -w vm.swappiness=10            # Moins enclin à swapper

# Pour des changements permanents, ajoutez à /etc/sysctl.conf:
# vm.overcommit_memory=2
# vm.overcommit_ratio=50
# vm.swappiness=10
```

## Script de surveillance
Pour surveiller la consommation mémoire de `sh`:

```bash
#!/bin/bash
PID=$(pgrep -f "sh ./mem_.*\.sh")
while true; do
    ps -p $PID -o pid,vsz,rss,cmd
    sleep 1
done
```

## Explication

1. **Scripts**:
   - Le script minimal maintient juste le shell en vie
   - Le script moyen stocke des données en mémoire
   - Le script gourmand alloue explicitement plus de mémoire

2. **Paramètres kernel**:
   - `vm.overcommit_memory`: Contrôle la politique d'allocation mémoire
   - `vm.overcommit_ratio`: Pourcentage de RAM disponible pour overcommit
   - `vm.swappiness`: Tendence à utiliser le swap plutôt que la RAM

Pour obtenir des valeurs précises de 5MB et 20MB, vous pourriez avoir besoin d'ajuster les tailles des variables dans les scripts en fonction de votre système spécifique.