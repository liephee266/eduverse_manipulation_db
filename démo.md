Voici un **exemple concret de configuration** d’une règle d’accès dans l’application SMEO, étape par étape, pour **autoriser les utilisateurs ayant la fonction "Manager" à modifier le champ R d’un macroprocessus**.

---

### 🎯 Objectif  
Permettre aux **Managers** de **modifier le champ R** (Responsable ?) dans les macroprocessus.

---

## 🔧 Étapes de configuration

### ✅ Étape 1 : Vérifier l’action technique dans `only_action` *(réservé aux développeurs)*
#### Si cette est vide, Accédez à  :  
🔗 `https://api.app1.webard.fr/public/action_access_rule//debug/init-access/{id_society}`
avec {id_society} l'id de la société correspondante  


La table `only_action` **doit déjà contenir** l’action suivante (elle est normalement préchargée) :

| `nom_tech`     | `libelle`                                |
|----------------|------------------------------------------|
| `update_r`     | Modifier le champ R d’un macroprocessus  |

> ⚠️ Cette table **n’est pas modifiable** via l’interface admin. Si l’action n’existe pas, il faut contacter un développeur.

---

### ✅ Étape 2 : Créer une règle métier dans `action_access_rule`

Accédez à l’interface :  
🔗 `https://app1.webard.fr/portail-administration/gestion-des-bases-de-donnees/action_access_rule`

Créez une nouvelle ligne avec les valeurs suivantes :

| Champ                      | Valeur à saisir                                      |
|---------------------------|------------------------------------------------------|
| **Action**                | `update_r` *(sélectionnée depuis la liste de `only_action`)* |
| **Libellé**               | `Qui peut modifier le champ R d’un macroprocessus ?` |
| **Champs**                | *(laisser vide ou indiquer `r` si utilisé plus tard)* |

> 💡 Ce libellé apparaîtra dans l’interface de gestion des règles (`access_rule`) pour aider l’administrateur à comprendre le sens de la règle.

---

### ✅ Étape 3 : Créer la règle d’accès finale dans `access_rule`

Accédez à :  
🔗 `https://app1.webard.fr/portail-administration/gestion-des-bases-de-donnees/access_rule`

Créez une nouvelle règle avec :

| Champ                        | Valeur à saisir                                      |
|-----------------------------|------------------------------------------------------|
| **Thème**                   | `macroprocessus` *(nom technique de la table concernée)* |
| **Fonction de l'application** | Sélectionnez la ligne créée à l’étape 2 : *« Qui peut modifier le champ R… »* |
| **Qui (Fonction)**          | `Manager` *(sélectionnez la fonction dans la liste)* |
| **Fonction par défaut**     | `admin` *(optionnel, mais recommandé comme fallback)* |
| **Sinon**                   | *(non implémenté – laisser vide)* |
| **Page**                    | *(non implémenté – laisser vide)* |

> ✅ Une fois sauvegardée, **tous les utilisateurs ayant la fonction "Manager"** pourront **modifier le champ R** des macroprocessus.  
> Les autres utilisateurs (sans cette fonction) ne verront pas le champ en édition (ou recevront une erreur, selon l’implémentation actuelle).

---

### 🔍 Résumé visuel du flux

```
only_action (dev)
   ↓
action_access_rule → "Qui peut modifier le champ R ?" ← lié à update_r
   ↓
access_rule → Thème = macroprocessus, Fonction = Manager
```

---

### ⚠️ Bonnes pratiques & pièges à éviter

- **Ne pas modifier** `only_action` manuellement → risque de casser des règles.
- **Vérifier l’orthographe exacte** du `nom_tech` (ex. pas d’espace, pas de majuscule inattendue).
- **Tester avec un utilisateur "Manager"** après configuration.
- Si plusieurs rôles doivent avoir accès (ex. Manager + Superviseur), listez-les tous dans le champ **"Qui (Fonction)"**.
- les fonctions admins qui sont prises en compte actuellement sont : **Administrateur WebArd SMEO**, **Administrateur WebArd**, **Responsable SMEO**, **Resp Infogérance**
- 

