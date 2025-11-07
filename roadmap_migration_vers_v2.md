Voici une roadmap claire, étape par étape, pour terminer la migration de votre base de données de `integer` vers `uuid_type`, en ciblant spécifiquement les points 3 (Clés Étrangères), 4 (Séquences) et 5 (Contraintes et Index) à partir du dump fourni.

**Objectif Final :** Toutes les clés primaires et étrangères dans la base de données doivent utiliser le type `public.uuid_type` avec `uuid_generate_v4()` comme valeur par défaut. Les séquences `integer` associées aux anciennes colonnes doivent être supprimées. Toutes les contraintes et index doivent être cohérents avec les nouveaux types.

---

### **Roadmap de Migration : Étapes Clés**

#### **Étape 0 : Préparation Critique (À FAIRE AVANT TOUT)**

1.  **Créez une sauvegarde complète de la base de données actuelle.**
    *   `pg_dump -U votre_utilisateur -d nom_de_votre_base > sauvegarde_avant_migration.sql`
    *   **Raison :** Cette migration est invasive. Une sauvegarde vous permet de revenir en arrière en cas de problème.
2.  **Identifiez les tables "hors-sujet" :**
    *   Analysez les deux fichiers. Certaines tables contiennent encore des colonnes `integer` pour des identifiants qui ne sont *pas* des clés primaires ou étrangères vers une autre table de la base (ex: `attendance_codes.table_name`, `food_service_staff_transaction_items.item_id`, `wx_appreciations.grade_id`).
    *   **Action :** Créez une liste de ces colonnes `integer` "isolées". **Ne les modifiez pas pendant cette migration.** Elles sont des données de référence ou des codes externes. Vous les laisserez en `integer` pour le moment. **Votre focus est uniquement sur les clés primaires/étrangères.**
3.  **Vérifiez les dépendances de vos fonctions et vues :**
    *   Les fonctions comme `calc_gpa_mp`, `credit`, `set_class_rank_mp` et les vues comme `transcript_grades`, `course_details`, `enroll_grade` contiennent des jointures et des références aux colonnes d'identifiants.
    *   **Action :** Notez les noms de toutes les fonctions et vues qui utilisent des colonnes d'identifiants. Vous devrez les recompiler après la migration. **Ne les modifiez pas encore.**

#### **Étape 1 : Création du Domaine et des Extensions (Déjà fait dans le Fichier 2)**

*   **Vérification :** Le fichier 2 contient déjà les éléments essentiels :
    *   `CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA public;`
    *   `CREATE DOMAIN public.uuid_type AS uuid NOT NULL DEFAULT public.uuid_generate_v4();`
*   **Action :** Assurez-vous que ces deux lignes sont présentes dans votre base de données cible. Si ce n'est pas le cas, exécutez-les immédiatement. C'est la base de toute la migration.

#### **Étape 2 : Migration des Clés Primaires (PK) et des Séquences (Point 4)**

*   **Principe :** Pour chaque table, vous allez :
    1.  Modifier la colonne de clé primaire de `integer` vers `uuid_type`.
    2.  Supprimer la séquence `integer` associée.
    3.  Vérifier que la colonne a bien `DEFAULT public.uuid_generate_v4()`.

*   **Procédure (Répétez pour chaque table listée ci-dessous) :**
    1.  **Identifiez la colonne PK et la séquence :** Trouvez la colonne `id`, `xxx_id`, etc., dans la table. Notez le nom de la séquence (ex: `accounting_categories_id_seq` pour `accounting_categories.id`).
    2.  **Modifiez la colonne :** Convertissez-la en `uuid_type`.
        ```sql
        ALTER TABLE public.nom_de_la_table ALTER COLUMN nom_de_la_colonne_pk TYPE public.uuid_type USING nom_de_la_colonne_pk::uuid;
        ```
        *   **Exemple :** `ALTER TABLE public.accounting_categories ALTER COLUMN id TYPE public.uuid_type USING id::uuid;`
    3.  **Supprimez la séquence :**
        ```sql
        DROP SEQUENCE public.nom_de_la_sequence CASCADE;
        ```
        *   **Exemple :** `DROP SEQUENCE public.accounting_categories_id_seq CASCADE;`
        *   **Important :** Le `CASCADE` supprime aussi les dépendances, ce qui est nécessaire ici car la séquence est liée à la colonne.
    4.  **Vérifiez le DEFAULT :** Assurez-vous que la colonne a bien `DEFAULT public.uuid_generate_v4()`. Si ce n'est pas le cas, ajoutez-le :
        ```sql
        ALTER TABLE public.nom_de_la_table ALTER COLUMN nom_de_la_colonne_pk SET DEFAULT public.uuid_generate_v4();
        ```

*   **Liste des Tables à Traiter (Clés Primaires) :**
    *   `accounting_categories` (id)
    *   `accounting_incomes` (id)
    *   `accounting_payments` (id)
    *   `accounting_salaries` (id)
    *   `address` (address_id)
    *   `address_field_categories` (id)
    *   `address_fields` (id)
    *   `attendance_calendars` (calendar_id)
    *   `attendance_code_categories` (id)
    *   `attendance_codes` (id)
    *   `billing_fees` (id)
    *   `billing_payments` (id)
    *   `bordereaux_details` (id)
    *   `calendar_events` (id)
    *   `course_period_school_periods` (course_period_school_periods_id)
    *   `course_periods` (course_period_id)
    *   `course_subjects` (subject_id)
    *   `courses` (course_id)
    *   `custom_fields` (id)
    *   `discipline_field_usage` (id)
    *   `discipline_fields` (id)
    *   `discipline_referrals` (id)
    *   `eligibility_activities` (id)
    *   `food_service_categories` (category_id)
    *   `food_service_items` (item_id)
    *   `food_service_menu_items` (menu_item_id)
    *   `food_service_menus` (menu_id)
    *   `food_service_staff_transactions` (transaction_id)
    *   `food_service_transactions` (transaction_id)
    *   `grade_levels` (id)
    *   `gradebook_assignment_types` (assignment_type_id)
    *   `gradebook_assignments` (assignment_id)
    *   `messages` (message_id)
    *   `people` (person_id)
    *   `people_field_categories` (id)
    *   `people_fields` (id)
    *   `people_join_contacts` (id)
    *   `portal_notes` (id)
    *   `portal_poll_questions` (id)
    *   `portal_polls` (id)
    *   `report_card_comment_categories` (id)
    *   `report_card_comment_code_scales` (id)
    *   `report_card_comment_codes` (id)
    *   `report_card_comments` (id)
    *   `report_card_grade_scales` (id)
    *   `report_card_grades` (id)
    *   `resources` (id)
    *   `schedule_requests` (request_id)
    *   `school_fields` (id)
    *   `school_gradelevels` (id)
    *   `school_marking_periods` (marking_period_id)
    *   `school_periods` (period_id)
    *   `schools` (id)
    *   `staff` (staff_id)
    *   `staff_field_categories` (id)
    *   `staff_fields` (id)
    *   `student_enrollment` (id)
    *   `student_enrollment_codes` (id)
    *   `student_enrollment_course_periods` (id)
    *   `student_field_categories` (id)
    *   `student_medical` (id)
    *   `student_medical_alerts` (id)
    *   `student_medical_visits` (id)
    *   `student_report_card_grades` (id)
    *   `students` (student_id)
    *   `students_join_address` (id)
    *   `students_join_people` (id)
    *   `user_profiles` (id)
    *   `wx_appreciations` (id)
    *   `wx_config_publication_resultats` (id)
    *   `wx_course_periods_gradelevels` (wx_course_periods_gradelevels_id)
    *   `wx_course_periods_subjects` (wx_course_periods_subjects_id)
    *   `wx_course_periods_subjects_periods` (wx_course_periods_subjects_periods_id)
    *   `wx_course_subjects_gradelevels` (wx_course_subjects_gradelevels_id)
    *   `wx_custom_configuration_school` (id_custom_configuration_school)
    *   `wx_echelle_notation_appreciation` (id)
    *   `wx_families` (id)
    *   `wx_family_members` (id)
    *   `wx_gradel_period_evaluation` (id_gradel_period_evaluation)
    *   `wx_moyennes_finales_students` (id)
    *   `wx_moyennes_validation_gradelevel` (id)
    *   `wx_notes_details` (id_notes_details)
    *   `wx_notes_student_details` (id_notes_student_details)
    *   `wx_reduction_eleve` (id)
    *   `wx_reduction_members` (id)
    *   `wx_rules_school` (id)
    *   `wx_teacher_attendance` (id)
    *   `wx_ues` (id)
    *   `wx_ues_subjects` (id) <-- *Note : Cette table est particulière, voir Étape 3.*

#### **Étape 3 : Migration des Clés Étrangères (FK) (Point 3)**

*   **Principe :** Pour chaque colonne de clé étrangère dans une table, vous devez :
    1.  La modifier pour qu'elle soit de type `uuid_type`.
    2.  Recréer la contrainte de clé étrangère pour qu'elle pointe vers la nouvelle colonne de la table parente (qui est maintenant en `uuid_type`).

*   **Procédure (Répétez pour chaque relation) :**
    1.  **Identifiez la relation FK :** Trouvez les colonnes dans les tables qui sont des clés étrangères vers les colonnes que vous avez modifiées en Étape 2. Par exemple, `accounting_incomes.category_id` pointe vers `accounting_categories.id`.
    2.  **Modifiez la colonne FK :** Convertissez-la en `uuid_type`.
        ```sql
        ALTER TABLE public.table_enfant ALTER COLUMN colonne_fk TYPE public.uuid_type USING colonne_fk::uuid;
        ```
        *   **Exemple :** `ALTER TABLE public.accounting_incomes ALTER COLUMN category_id TYPE public.uuid_type USING category_id::uuid;`
    3.  **Supprimez l'ancienne contrainte FK :** Trouvez le nom de la contrainte. Il est généralement de la forme `nom_de_la_table_colonne_fk_fkey`. Supprimez-la.
        ```sql
        ALTER TABLE public.table_enfant DROP CONSTRAINT nom_de_la_contrainte_fkey;
        ```
        *   **Exemple :** `ALTER TABLE public.accounting_incomes DROP CONSTRAINT accounting_incomes_category_id_fkey;`
    4.  **Recréez la contrainte FK :** Créez une nouvelle contrainte qui référence la colonne parente modifiée.
        ```sql
        ALTER TABLE public.table_enfant ADD CONSTRAINT nom_de_la_contrainte_fkey FOREIGN KEY (colonne_fk) REFERENCES public.table_parente (colonne_pk);
        ```
        *   **Exemple :** `ALTER TABLE public.accounting_incomes ADD CONSTRAINT accounting_incomes_category_id_fkey FOREIGN KEY (category_id) REFERENCES public.accounting_categories(id);`

*   **Liste des Relations Clés Étrangères à Mettre à Jour (Exemples) :**
    *   `accounting_incomes.category_id` -> `accounting_categories.id`
    *   `accounting_incomes.school_id` -> `schools.id`
    *   `accounting_payments.category_id` -> `accounting_categories.id`
    *   `accounting_payments.school_id` -> `schools.id`
    *   `accounting_payments.staff_id` -> `staff.staff_id`
    *   `accounting_salaries.staff_id` -> `staff.staff_id`
    *   `accounting_salaries.school_id` -> `schools.id`
    *   `attendance_calendar.calendar_id` -> `attendance_calendars.calendar_id`
    *   `attendance_calendar.school_id` -> `schools.id`
    *   `attendance_code_categories.school_id` -> `schools.id`
    *   `attendance_codes.school_id` -> `schools.id`
    *   `attendance_period.student_id` -> `students.student_id`
    *   `attendance_period.course_period_id` -> `course_periods.course_period_id`
    *   `attendance_period.marking_period_id` -> `school_marking_periods.marking_period_id`
    *   `billing_fees.student_id` -> `students.student_id`
    *   `billing_fees.school_id` -> `schools.id`
    *   `billing_payments.student_id` -> `students.student_id`
    *   `billing_payments.school_id` -> `schools.id`
    *   `calendar_events.school_id` -> `schools.id`
    *   `course_period_school_periods.course_period_id` -> `course_periods.course_period_id`
    *   `course_period_school_periods.period_id` -> `school_periods.period_id`
    *   `course_periods.course_id` -> `courses.course_id`
    *   `course_periods.marking_period_id` -> `school_marking_periods.marking_period_id`
    *   `course_periods.teacher_id` -> `staff.staff_id`
    *   `course_periods.secondary_teacher_id` -> `staff.staff_id`
    *   `course_periods.school_id` -> `schools.id`
    *   `course_subjects.school_id` -> `schools.id`
    *   `courses.school_id` -> `schools.id`
    *   `courses.subject_id` -> `course_subjects.subject_id`
    *   `discipline_field_usage.school_id` -> `schools.id`
    *   `discipline_referrals.school_id` -> `schools.id`
    *   `discipline_referrals.student_id` -> `students.student_id`
    *   `discipline_referrals.staff_id` -> `staff.staff_id`
    *   `eligibility_activities.school_id` -> `schools.id`
    *   `eligibility.student_id` -> `students.student_id`
    *   `eligibility.course_period_id` -> `course_periods.course_period_id`
    *   `food_service_categories.school_id` -> `schools.id`
    *   `food_service_categories.menu_id` -> `food_service_menus.menu_id`
    *   `food_service_items.school_id` -> `schools.id`
    *   `food_service_menu_items.school_id` -> `schools.id`
    *   `food_service_menu_items.menu_id` -> `food_service_menus.menu_id`
    *   `food_service_menu_items.item_id` -> `food_service_items.item_id`
    *   `food_service_menu_items.category_id` -> `food_service_categories.category_id`
    *   `food_service_staff_accounts.staff_id` -> `staff.staff_id`
    *   `food_service_staff_transactions.staff_id` -> `staff.staff_id`
    *   `food_service_staff_transactions.school_id` -> `schools.id`
    *   `food_service_student_accounts.student_id` -> `students.student_id`
    *   `food_service_student_accounts.account_id` -> `food_service_accounts.account_id`
    *   `food_service_transactions.student_id` -> `students.student_id`
    *   `food_service_transactions.school_id` -> `schools.id`
    *   `food_service_transactions.account_id` -> `food_service_accounts.account_id`
    *   `gradebook_assignment_types.staff_id` -> `staff.staff_id`
    *   `gradebook_assignment_types.course_id` -> `courses.course_id`
    *   `gradebook_assignments.staff_id` -> `staff.staff_id`
    *   `gradebook_assignments.course_id` -> `courses.course_id`
    *   `gradebook_assignments.course_period_id` -> `course_periods.course_period_id`
    *   `gradebook_assignments.marking_period_id` -> `school_marking_periods.marking_period_id`
    *   `gradebook_assignments.assignment_type_id` -> `gradebook_assignment_types.assignment_type_id`
    *   `gradebook_grades.student_id` -> `students.student_id`
    *   `gradebook_grades.course_period_id` -> `course_periods.course_period_id`
    *   `gradebook_grades.assignment_id` -> `gradebook_assignments.assignment_id`
    *   `grades_completed.staff_id` -> `staff.staff_id`
    *   `grades_completed.course_period_id` -> `course_periods.course_period_id`
    *   `grades_completed.marking_period_id` -> `school_marking_periods.marking_period_id`
    *   `lunch_period.student_id` -> `students.student_id`
    *   `lunch_period.course_period_id` -> `course_periods.course_period_id`
    *   `lunch_period.marking_period_id` -> `school_marking_periods.marking_period_id`
    *   `messages.school_id` -> `schools.id`
    *   `messagexuser.message_id` -> `messages.message_id`
    *   `people_join_contacts.person_id` -> `people.person_id`
    *   `portal_notes.school_id` -> `schools.id`
    *   `portal_polls.school_id` -> `schools.id`
    *   `portal_poll_questions.portal_poll_id` -> `portal_polls.portal_poll_id`
    *   `profile_exceptions.profile_id` -> `user_profiles.id`
    *   `program_config.school_id` -> `schools.id`
    *   `program_user_config.school_id` -> `schools.id`
    *   `report_card_comment_categories.school_id` -> `schools.id`
    *   `report_card_comment_categories.course_id` -> `courses.course_id`
    *   `report_card_comment_code_scales.school_id` -> `schools.id`
    *   `report_card_comment_codes.scale_id` -> `report_card_comment_code_scales.scale_id`
    *   `report_card_comments.school_id` -> `schools.id`
    *   `report_card_comments.category_id` -> `report_card_comment_categories.category_id`
    *   `report_card_comments.scale_id` -> `report_card_comment_code_scales.scale_id`
    *   `report_card_grade_scales.school_id` -> `schools.id`
    *   `report_card_grades.school_id` -> `schools.id`
    *   `report_card_grades.grade_scale_id` -> `report_card_grade_scales.grade_scale_id`
    *   `schedule.course_id` -> `courses.course_id`
    *   `schedule.course_period_id` -> `course_periods.course_period_id`
    *   `schedule.student_id` -> `students.student_id`
    *   `schedule.marking_period_id` -> `school_marking_periods.marking_period_id`
    *   `schedule_requests.student_id` -> `students.student_id`
    *   `schedule_requests.course_id` -> `courses.course_id`
    *   `schedule_requests.marking_period_id` -> `school_marking_periods.marking_period_id`
    *   `school_marking_periods.school_id` -> `schools.id`
    *   `school_marking_periods.parent_id` -> `school_marking_periods.marking_period_id` (auto-référentielle)
    *   `school_periods.school_id` -> `schools.id`
    *   `staff.current_school_id` -> `schools.id`
    *   `staff.profile_id` -> `user_profiles.id`
    *   `staff_exceptions.user_id` -> `staff.staff_id`
    *   `student_assignments.student_id` -> `students.student_id`
    *   `student_eligibility_activities.student_id` -> `students.student_id`
    *   `student_enrollment.school_id` -> `schools.id`
    *   `student_enrollment.student_id` -> `students.student_id`
    *   `student_enrollment.grade_id` -> `school_gradelevels.gradelevel_id`
    *   `student_enrollment.second_grade_id` -> `school_gradelevels.gradelevel_id`
    *   `student_enrollment.calendar_id` -> `attendance_calendars.calendar_id`
    *   `student_enrollment.course_period_id` -> `course_periods.course_period_id`
    *   `student_enrollment.second_course_period_id` -> `course_periods.course_period_id`
    *   `student_enrollment_course_periods.student_enrollment_id` -> `student_enrollment.id`
    *   `student_enrollment_course_periods.course_period_id` -> `course_periods.course_period_id`
    *   `student_medical.student_id` -> `students.student_id`
    *   `student_medical_alerts.student_id` -> `students.student_id`
    *   `student_medical_visits.student_id` -> `students.student_id`
    *   `student_mp_comments.student_id` -> `students.student_id`
    *   `student_mp_comments.marking_period_id` -> `school_marking_periods.marking_period_id`
    *   `student_mp_stats.student_id` -> `students.student_id`
    *   `student_mp_stats.marking_period_id` -> `school_marking_periods.marking_period_id`
    *   `student_report_card_comments.student_id` -> `students.student_id`
    *   `student_report_card_comments.course_period_id` -> `course_periods.course_period_id`
    *   `student_report_card_comments.marking_period_id` -> `school_marking_periods.marking_period_id`
    *   `student_report_card_grades.student_id` -> `students.student_id`
    *   `student_report_card_grades.course_period_id` -> `course_periods.course_period_id`
    *   `student_report_card_grades.marking_period_id` -> `school_marking_periods.marking_period_id`
    *   `student_report_card_grades.report_card_grade_id` -> `report_card_grades.report_card_grade_id`
    *   `student_report_card_grades.report_card_comment_id` -> `report_card_comments.report_card_comment_id`
    *   `students_join_address.student_id` -> `students.student_id`
    *   `students_join_address.address_id` -> `address.address_id`
    *   `students_join_people.student_id` -> `students.student_id`
    *   `students_join_people.person_id` -> `people.person_id`
    *   `students_join_people.address_id` -> `address.address_id`
    *   `students_join_users.student_id` -> `students.student_id`
    *   `students_join_users.staff_id` -> `staff.staff_id`
    *   `wx_course_periods_gradelevels.course_periods_id` -> `course_periods.course_period_id`
    *   `wx_course_periods_gradelevels.school_gradelevels_id` -> `school_gradelevels.gradelevel_id`
    *   `wx_course_periods_subjects.course_periods_id` -> `course_periods.course_period_id`
    *   `wx_course_periods_subjects.course_subjects_id` -> `course_subjects.subject_id`
    *   `wx_course_periods_subjects.teacher_id` -> `staff.staff_id`
    *   `wx_course_periods_subjects.secondary_teacher_id` -> `staff.staff_id`
    *   `wx_course_periods_subjects.ue_id` -> `wx_ues.ue_id`
    *   `wx_course_periods_subjects_periods.wx_course_periods_subjects_id` -> `wx_course_periods_subjects.wx_course_periods_subjects_id`
    *   `wx_course_subjects_gradelevels.course_subjects_id` -> `course_subjects.subject_id`
    *   `wx_course_subjects_gradelevels.school_gradelevels_id` -> `school_gradelevels.gradelevel_id`
    *   `wx_custom_configuration_school.school_id` -> `schools.school_id`
    *   `wx_echelle_notation_appreciation.school_id` -> `schools.school_id`
    *   `wx_families.school_id` -> `schools.school_id`
    *   `wx_family_members.family_id` -> `wx_families.wx_family_id`
    *   `wx_family_members.student_id` -> `students.student_id`
    *   `wx_gradel_period_evaluation.school_gradelevels_id` -> `school_gradelevels.gradelevel_id`
    *   `wx_moyennes_finales_students.student_enrollment_id` -> `student_enrollment.id`
    *   `wx_moyennes_validation_gradelevel.school_gradelevels_id` -> `school_gradelevels.gradelevel_id`
    *   `wx_notes_details.course_period_id` -> `course_periods.course_period_id`
    *   `wx_notes_student_details.wx_course_periods_subjects_id` -> `wx_course_periods_subjects.wx_course_periods_subjects_id`
    *   `wx_notes_student_details.student_id` -> `students.student_id`
    *   `wx_notes_student_details.course_period_id` -> `course_periods.course_period_id`
    *   `wx_reduction_eleve.school_id` -> `schools.school_id`
    *   `wx_reduction_members.reduction_id` -> `wx_reduction_eleve.wx_reduction_eleve_id`
    *   `wx_reduction_members.student_id` -> `students.student_id`
    *   `wx_teacher_attendance.staff_id` -> `staff.staff_id`
    *   `wx_ues.school_id` -> `schools.school_id`
    *   `wx_ues.gradelevel_id` -> `school_gradelevels.gradelevel_id`
    *   `wx_ues.course_period_id` -> `course_periods.course_period_id`
    *   `wx_ues_subjects.ue_id` -> `wx_ues.ue_id`
    *   `wx_ues_subjects.subject_id` -> `course_subjects.subject_id`

#### **Étape 4 : Migration des Index et Vérification des Contraintes (Point 5)**

*   **Principe :** Les index sur les colonnes modifiées doivent être recréés. Les contraintes uniques doivent être vérifiées.
*   **Procédure :**
    1.  **Identifiez les index :** Utilisez la commande `\d nom_de_la_table` dans `psql` ou examinez le dump pour voir les index sur les colonnes que vous avez modifiées.
    2.  **Supprimez les anciens index :** Supprimez les index qui pointent vers les colonnes converties.
        ```sql
        DROP INDEX public.nom_de_l_index;
        ```
        *   **Exemple :** `DROP INDEX public.accounting_incomes_ind1;`
    3.  **Recréez les index :** Recréez-les sur les nouvelles colonnes `uuid_type`.
        ```sql
        CREATE INDEX nom_de_l_index ON public.table USING btree (colonne);
        ```
        *   **Exemple :** `CREATE INDEX accounting_incomes_ind1 ON public.accounting_incomes USING btree (category_id);`
    4.  **Vérifiez les contraintes uniques :** Assurez-vous que les contraintes `UNIQUE` (ex: `unique_student_exam`, `wx_family_members_student_id_key`) sont toujours présentes et correctes. Elles devraient fonctionner automatiquement avec `uuid_type`, mais vérifiez leur existence.

#### **Étape 5 : Mise à Jour des Fonctions et Vues (Point Critique)**

*   **Principe :** Les fonctions et vues contiennent des expressions SQL qui font référence aux anciens types `integer`. Elles doivent être recompilées pour qu'elles comprennent les `uuid_type`.
*   **Procédure :**
    1.  **Modifiez les fonctions :** Pour chaque fonction listée à l'Étape 0 (ex: `calc_gpa_mp`, `credit`, `set_class_rank_mp`), ouvrez son code.
        *   **Modifiez les paramètres :** Changez `integer` en `uuid_type`.
            *   `CREATE FUNCTION public.calc_gpa_mp(s_id integer, mp_id integer) ...` devient `CREATE FUNCTION public.calc_gpa_mp(s_id uuid_type, mp_id uuid_type) ...`
        *   **Modifiez les déclarations de variables :** Si une variable est déclarée comme `integer`, changez-la en `uuid_type` ou `uuid`.
        *   **Modifiez les comparaisons dans les `WHERE` :** Assurez-vous que les comparaisons entre `uuid_type` et `uuid` sont cohérentes. Parfois, un cast explicite `::uuid` est nécessaire, mais en général, PostgreSQL gère bien la conversion entre `uuid_type` et `uuid`.
        *   **Exemple :** Dans `credit`, la ligne `select * into course_detail from course_periods where course_period_id = cp_id;` est correcte car `cp_id` est maintenant `uuid_type` et `course_period_id` est `uuid_type`.
    2.  **Modifiez les vues :** Pour chaque vue (ex: `transcript_grades`, `course_details`, `enroll_grade`), modifiez les jointures.
        *   **Ajoutez des casts explicites si nécessaire :** Les vues ont souvent des jointures comme `ON (e.grade_id = sg.id)`. Dans la vue `enroll_grade`, il y a déjà un cast `((e.grade_id)::uuid = (sg.gradelevel_id)::uuid)`. **Vérifiez que tous les `JOIN` dans les vues ont des types compatibles.** Si vous voyez une comparaison entre un `integer` et un `uuid_type`, vous devez ajouter `::uuid` ou `::uuid_type` à la colonne `integer` pour la convertir. **Dans votre cas, toutes les colonnes concernées sont déjà en `uuid_type`, donc les `JOIN` doivent fonctionner sans cast.**
        *   **Exemple :** Dans `transcript_grades`, la jointure `JOIN public.student_report_card_grades srcg ON ((mp.marking_period_id)::uuid = (srcg.marking_period_id)::uuid)` est correcte. Le `::uuid` est superflu car les deux colonnes sont `uuid_type`, mais il ne fait pas de mal. Vous pouvez le supprimer pour plus de clarté.
    3.  **Recompilez les fonctions et vues :** Une fois les modifications effectuées, supprimez et recréez les fonctions et vues avec leur code mis à jour.

#### **Étape 6 : Vérification Finale et Test**

1.  **Testez les opérations courantes :**
    *   Insérez un nouvel utilisateur, un nouvel élève, un nouveau cours.
    *   Créez une relation entre un élève et un cours.
    *   Exécutez une requête complexe qui utilise plusieurs jointures (ex: récupérer les notes d'un élève avec son nom, son cours et son professeur).
2.  **Vérifiez les déclencheurs :** Assurez-vous que les déclencheurs `set_updated_at` fonctionnent toujours.
3.  **Vérifiez les vues :** Vérifiez que les vues `transcript_grades`, `course_details`, etc., retournent des résultats corrects.
4.  **Testez les fonctions :** Exécutez manuellement les fonctions `calc_gpa_mp`, `set_class_rank_mp` avec des données de test.
5.  **Vérifiez les contraintes :** Essayez de supprimer un élève qui a des notes ou des inscriptions. La contrainte de clé étrangère doit empêcher la suppression.

---

### **Résumé de la Séquence d'Exécution**

1.  **Sauvegarde.**
2.  **Créez `uuid_type` et `uuid-ossp` (si absent).**
3.  **Migrez les Clés Primaires + Supprimez les Séquences (Étape 2).**
4.  **Migrez les Clés Étrangères (Étape 3).**
5.  **Mettez à jour les Index (Étape 4).**
6.  **Mettez à jour les Fonctions et Vues (Étape 5).**
7.  **Testez intensivement (Étape 6).**

**Conseil :** Travaillez sur une copie de votre base de données de production. Appliquez les étapes une par une, en testant après chaque étape. Ne passez pas à l'étape suivante tant que l'étape précédente n'est pas vérifiée.
