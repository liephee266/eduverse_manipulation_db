# eduverse_manipulation_db

Voici une explication claire de l'objectif de ces 6 fichiers SQL :

## 🎯 Objectif Global
Migrer une base de données PostgreSQL pour remplacer les clés primaires et étrangères existantes par des UUID, tout en conservant l'intégrité des relations entre les tables.

---

## 📊 Détail de chaque fichier :

### 1. seq1.sql - Préparation des données
- Objectif : Ajouter des colonnes UUID et préparer la transition
- Actions :
  - Ajoute une colonne id_uuid à toutes les tables avec clé primaire
  - Sauvegarde les anciennes colonnes clés en les renommant avec _old
  - Met à jour les clés étrangères avec les nouveaux UUID

### 2. seq2.sql - Suppression des contraintes
- Objectif : Nettoyer les anciennes relations
- Actions :
  - Supprime toutes les contraintes de clés étrangères existantes
  - *Permet de recréer des relations propres ensuite*

### 3. seq3.sql - Nouveaux identifiants primaires
- Objectif : Établir les nouvelles clés primaires
- Actions :
  - Supprime les anciennes clés primaires
  - Définit id_uuid comme nouvelle clé primaire pour chaque table

### 4. seq4.sql - Rétablissement des relations
- Objectif : Recréer les liens entre les tables
- Actions :
  - Recrée les contraintes de clés étrangères en utilisant les UUID
  - *Assure que les relations parent-enfant fonctionnent avec les nouveaux identifiants*

### 5. seq5.sql - Automatisation
- Objectif : Garantir la génération automatique des UUID
- Actions :
  - Crée un trigger pour générer automatiquement des UUID à l'insertion
  - *S'assure que chaque nouvelle ligne aura son UUID sans intervention manuelle*

### 6. seq6.sql - Optimisation
- Objectif : Finaliser et optimiser la structure
- Actions :
  - Rend la colonne id_uuid obligatoire (NOT NULL)
  - Crée des index sur les UUID pour améliorer les performances

---

## 🏗 Avantages de cette migration :
- ✅ Universalité : Les UUID sont uniques across toutes les bases
- ✅ Sécurité : Plus difficiles à deviner que des IDs séquentiels
- ✅ Réplication : Meilleur pour les systèmes distribués
- ✅ Intégrité : Conservation de toutes les relations existantes

C'est une migration complète et sécurisée qui préserve les données tout en modernisant la structure d'identification.
