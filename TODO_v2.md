# Roadmap d'Achèvement de la Migration vers UUID

Ce fichier détaille les tâches restantes pour finaliser la migration de la base de données vers l'utilisation d'UUID, en se basant sur le fichier `structure_uuid.sql` et la `roadmap_migration_vers_v2.md`.

## Phase 1 : Ajout des Tables Manquantes

Les tables suivantes sont présentes dans `schema_sans_uuid.sql` et listées dans la roadmap, mais absentes de `structure_uuid.sql`. Elles doivent être créées avec la nouvelle structure `uuid_type`.

- [ ] **Table `bordereaux_details`**
    - [ ] Définir la clé primaire `id` en `public.uuid_type`.
    - [ ] Changer la clé étrangère `staff_id` en `public.uuid_type`.
    - [ ] Ajouter la contrainte de clé étrangère vers `staff(staff_id)`.
    - [ ] Ajouter un index sur `staff_id`.

- [ ] **Table `wx_reduction_eleve`**
    - [ ] Définir la clé primaire `id` en `public.uuid_type`.
    - [ ] Changer la clé étrangère `school_id` en `public.uuid_type`.
    - [ ] Ajouter la contrainte de clé étrangère vers `schools(id)`.
    - [ ] Ajouter un index sur `school_id`.

- [ ] **Table `wx_reduction_members`**
    - [ ] Définir la clé primaire `id` en `public.uuid_type`.
    - [ ] Changer les clés étrangères `reduction_id` et `student_id` en `public.uuid_type`.
    - [ ] Ajouter les contraintes de clés étrangères vers `wx_reduction_eleve(id)` et `students(student_id)`.
    - [ ] Ajouter des index sur `reduction_id` et `student_id`.

## Phase 2 : Audit des Clés Étrangères et des Index

Cette phase consiste à vérifier systématiquement que toutes les clés étrangères et les index sont correctement migrés, comme décrit dans la roadmap.

- [ ] **Audit systématique des tables :** Pour chaque table listée dans `structure_uuid.sql` :
    - [ ] **Vérifier les Clés Étrangères (FK) :** Confirmer que chaque colonne de clé étrangère est de type `public.uuid_type` et qu'une contrainte `FOREIGN KEY` est bien définie vers la table parente correspondante.
    - [ ] **Vérifier les Index :** S'assurer qu'un index `btree` existe pour chaque colonne de clé étrangère afin de garantir les performances des jointures.

### Exemples de points de contrôle prioritaires :

- [ ] **Table `course_periods` :**
    - [ ] Vérifier les FK : `course_id`, `marking_period_id`, `teacher_id`, `secondary_teacher_id`, `school_id`.
    - [ ] Vérifier les index sur ces mêmes colonnes.

- [ ] **Table `student_enrollment` :**
    - [ ] Vérifier les FK : `school_id`, `student_id`, `grade_id`, `second_grade_id`, `course_period_id`, `second_course_period_id`.
    - [ ] Vérifier les index sur ces mêmes colonnes.

- [ ] **Table `student_report_card_grades` :**
    - [ ] Vérifier les FK : `student_id`, `course_period_id`, `marking_period_id`, `report_card_grade_id`, `report_card_comment_id`.
    - [ ] Vérifier les index sur ces mêmes colonnes.

- [ ] **... (continuer pour toutes les tables listées dans l'Étape 3 de la roadmap).**

## Phase 3 : Validation des Vues et Fonctions

- [ ] **Revue des Fonctions :**
    - [ ] Tester chaque fonction (`calc_cum_cr_gpa`, `calc_cum_gpa`, `calc_gpa_mp`, `credit`, `set_class_rank_mp`) avec des entrées de type `uuid` pour confirmer qu'elles s'exécutent sans erreur et retournent des résultats corrects.

- [ ] **Revue des Vues :**
    - [ ] Analyser la définition de la vue `marking_periods` pour s'assurer que l'UNION entre `school_marking_periods` et `history_marking_periods` gère correctement les `uuid`.
    - [ ] Analyser la vue `course_details` et s'assurer que la jointure sur `course_id` est correcte.
    - [ ] Analyser la vue `enroll_grade` et s'assurer que la jointure sur `grade_id` / `gradelevel_id` est correcte.
    - [ ] **(Ajouter ici toute autre vue à vérifier)**

## Phase 4 : Nettoyage et Finalisation

- [ ] **Suppression des Séquences :** Une fois que toutes les clés primaires sont migrées, s'assurer qu'aucune séquence (`_seq`) de l'ancien schéma `integer` ne subsiste.
- [ ] **Vérification du propriétaire :** Confirmer que tous les objets de la base de données (tables, vues, fonctions) appartiennent bien à l'utilisateur `wxu_school`, comme c'est le cas dans `structure_uuid.sql`.
