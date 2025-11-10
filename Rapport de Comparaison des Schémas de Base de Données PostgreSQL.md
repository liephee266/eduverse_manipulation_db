# Rapport de Comparaison des Schémas de Base de Données PostgreSQL

Ce rapport détaille les différences structurelles entre deux versions d'un schéma de base de données PostgreSQL, fournies dans les fichiers `schema_sans_uuid.sql` et `structure_uuid.sql`. L'analyse révèle que la différence fondamentale réside dans la **migration du type de données des clés primaires et étrangères de `integer` vers `UUID` (Universally Unique Identifier)**.

## 1. Différence Structurelle Majeure : Migration vers UUID

La version `structure_uuid.sql` a été mise à jour pour utiliser des UUIDs comme identifiants pour de nombreuses colonnes qui utilisaient des entiers (`integer`) dans la version `schema_sans_uuid.sql`.

### 1.1. Introduction du Type `UUID`

Le fichier `structure_uuid.sql` introduit les éléments suivants pour supporter les UUIDs :

| Élément | Description | Fichier |
| :--- | :--- | :--- |
| **Extension** | `uuid-ossp` | `structure_uuid.sql` |
| **Domaine** | `uuid_type` | `structure_uuid.sql` |

- **`uuid-ossp` Extension** : Cette extension est ajoutée pour fournir la fonction `uuid_generate_v4()`, nécessaire pour générer des UUIDs aléatoires.
- **`uuid_type` Domaine** : Un nouveau domaine est créé pour simplifier la définition des colonnes UUID :
  ```sql
  CREATE DOMAIN public.uuid_type AS uuid NOT NULL DEFAULT public.uuid_generate_v4();
  ```
  Ceci garantit que toutes les colonnes utilisant ce domaine sont non-nulles et reçoivent une valeur UUID par défaut lors de l'insertion.

### 1.2. Impact sur les Fonctions Stockées

Les fonctions PostgreSQL ont été modifiées pour accepter des arguments de type `uuid` au lieu de `integer`.

| Fonction | Arguments dans `schema_sans_uuid.sql` | Arguments dans `structure_uuid.sql` |
| :--- | :--- | :--- |
| `calc_cum_cr_gpa` | `(mp_id integer, s_id integer)` | `(mp_id uuid, s_id uuid)` |
| `calc_cum_gpa` | `(mp_id integer, s_id integer)` | `(mp_id uuid, s_id uuid)` |
| `calc_gpa_mp` | `(s_id integer, mp_id integer)` | `(s_id uuid, mp_id uuid)` |
| `credit` | `(cp_id integer, mp_id integer)` | `(cp_id uuid, mp_id uuid)` |
| `set_class_rank_mp` | `(mp_id integer)` | `(mp_id uuid)` |

### 1.3. Impact sur les Définitions de Tables

La migration vers UUID a un impact direct sur les colonnes d'identification (clés primaires et étrangères) dans de nombreuses tables.

**Exemple de la table `school_marking_periods` :**

| Colonne | Type dans `schema_sans_uuid.sql` | Type dans `structure_uuid.sql` |
| :--- | :--- | :--- |
| `marking_period_id` | `integer NOT NULL` | `public.uuid_type NOT NULL` |
| `school_id` | `integer NOT NULL` | `public.uuid_type NOT NULL` |
| `parent_id` | `integer` | `public.uuid_type` |
| `rollover_id` | `integer` | `public.uuid_type` |

Dans `schema_sans_uuid.sql`, la colonne `marking_period_id` utilise une séquence (`school_marking_periods_marking_period_id_seq`) pour l'auto-incrémentation, typique des clés primaires de type `integer`. Dans `structure_uuid.sql`, cette séquence est remplacée par le domaine `public.uuid_type` qui utilise `uuid_generate_v4()` comme valeur par défaut.

## 2. Différences Structurelles Secondaires

### 2.1. Vues (`VIEW`)

La vue `public.marking_periods` est présente dans les deux schémas, mais sa définition est ajustée dans `structure_uuid.sql` pour refléter les changements de type de données et de noms de tables.

- **`schema_sans_uuid.sql`** : La vue utilise la table `marking_periods` (qui est une vue dans `structure_uuid.sql` et une table dans `schema_sans_uuid.sql` - *Note: une analyse plus approfondie a montré que `marking_periods` est une vue dans les deux cas, mais la source de la vue change*). La vue dans `schema_sans_uuid.sql` fait référence à la table `school_marking_periods` et à la table `history_marking_periods`.
- **`structure_uuid.sql`** : La vue est ajustée pour gérer les colonnes de type `uuid` et les conversions de type (`::uuid`, `::text`) dans ses clauses `CASE` et ses jointures.

### 2.2. Nommage des Tables et des Vues

Une différence subtile est observée dans le nommage ou la présence de certaines tables/vues :

| Élément | `schema_sans_uuid.sql` | `structure_uuid.sql` | Note |
| :--- | :--- | :--- | :--- |
| `marking_periods` | Présente (Vue) | Présente (Vue) | La vue est présente dans les deux, mais la définition interne est modifiée pour gérer les UUIDs. |
| `bordereaux_details` | Présente (Table) | Absente (Table) | La table `bordereaux_details` est présente dans `schema_sans_uuid.sql` mais absente dans la liste des `CREATE TABLE` de `structure_uuid.sql`. |
| `wx_rules_school` | Présente (Table) | Présente (Table) | Présente dans les deux. |
| `wx_reduction_eleve` | Présente (Table) | Absente (Table) | La table `wx_reduction_eleve` est présente dans `schema_sans_uuid.sql` mais absente dans la liste des `CREATE TABLE` de `structure_uuid.sql`. |
| `wx_reduction_members` | Présente (Table) | Absente (Table) | La table `wx_reduction_members` est présente dans `schema_sans_uuid.sql` mais absente dans la liste des `CREATE TABLE` de `structure_uuid.sql`. |

### 2.3. Autres Différences Mineures

- **Propriétaire des Objets** : Dans `schema_sans_uuid.sql`, le propriétaire des objets est `postgres`. Dans `structure_uuid.sql`, le propriétaire est `wxu_school`.
- **Version de PostgreSQL** : `schema_sans_uuid.sql` a été dumpé de la version 17.6, tandis que `structure_uuid.sql` a été dumpé de la version 15.8.

## Conclusion

La différence structurelle la plus significative entre les deux schémas est la **transition d'un modèle d'identification basé sur des entiers auto-incrémentés (`integer`) à un modèle basé sur des identifiants universellement uniques (`UUID`)**. Cette modification est implémentée par l'ajout de l'extension `uuid-ossp` et la création du domaine `uuid_type`, et se répercute sur les signatures de fonctions et les définitions de colonnes dans l'ensemble du schéma.

De plus, il y a des différences dans l'ensemble des tables, avec l'absence de `bordereaux_details`, `wx_reduction_eleve`, et `wx_reduction_members` dans la version `structure_uuid.sql`, suggérant une possible refactorisation ou suppression de fonctionnalités liées à ces tables.

***

### Références

[1] `schema_sans_uuid.sql` : Fichier de schéma de base de données original.
[2] `structure_uuid.sql` : Fichier de schéma de base de données mis à jour avec UUID.
[3] `structure_diff.txt` : Résultat de la comparaison des définitions de haut niveau entre les deux fichiers.
[4] `schema_structure.txt` : Liste des définitions de haut niveau extraites de `schema_sans_uuid.sql`.
[5] `structure_uuid_structure.txt` : Liste des définitions de haut niveau extraites de `structure_uuid.sql`.
[6] `school_marking_periods_schema.txt` : Définition de la table `school_marking_periods` dans `schema_sans_uuid.sql`.
[7] `school_marking_periods_uuid.txt` : Définition de la table `school_marking_periods` dans `structure_uuid.sql`.
