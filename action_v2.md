# Procédure de Migration de la Base de Données vers v2

Ce document détaille les étapes pour finaliser la migration de la base de données `eduverse` vers une structure utilisant des UUIDs comme clés primaires.

## Prérequis : Création du Rôle et de la Base de Données

Avant de commencer, vous devez créer le rôle `wxu_school` qui sera le propriétaire de la base de données, puis créer la base de données elle-même et y charger le schéma initial.

**Note :** Les commandes suivantes utilisent `postgres` comme superutilisateur. Si votre superutilisateur a un nom différent, veuillez l'adapter.

1.  **Connectez-vous à PostgreSQL en tant que superutilisateur :**

    ```bash
    psql -U postgres
    ```

2.  **Créez le rôle `wxu_school` (depuis l'interpréteur `psql`) :**
    *Remplacez 'mot_de_passe_securise' par un mot de passe de votre choix.*

    ```sql
    CREATE ROLE wxu_school WITH LOGIN PASSWORD 'mot_de_passe_securise';
    ```

3.  **Quittez `psql` :**

    ```sql
    \q
    ```

4.  **Créez la nouvelle base de données (depuis votre terminal) :**

    ```bash
    createdb -U postgres -O wxu_school structure_uuid_v2
    ```

5.  **Chargez le schéma de base `structure_uuid.sql` dans la nouvelle base de données :**

    ```bash
    psql -U postgres -d structure_uuid_v2 -f structure_uuid.sql
    ```
    
    ---
    
    ## Application des Correctifs
    
    Maintenant, connectez-vous à votre base de données pour exécuter les commandes de migration.
    
    ```bash
    psql -U postgres -d structure_uuid_v2
    ```
    
    ### Phase 1.5 : Correction du type de données de la clé étrangère
    
    Copiez et exécutez la commande SQL suivante dans votre session `psql` pour corriger une incohérence de type de données qui empêche la création d'une clé étrangère.
    
    ```sql
    ALTER TABLE public.student_report_card_grades
    ALTER COLUMN report_card_comment_id TYPE public.uuid_type
    USING report_card_comment_id::text::uuid;
    ```
    ### Phase 1 : Ajout des Tables Manquantes

Copiez et exécutez les commandes SQL suivantes dans votre session `psql`.

#### Création de la table `bordereaux_details`

```sql
CREATE TABLE public.bordereaux_details (
    id public.uuid_type NOT NULL,
    staff_id public.uuid_type NOT NULL,
    month integer NOT NULL,
    year integer NOT NULL,
    autres_cycles numeric(10,2) DEFAULT 0,
    indemnites_responsabilite numeric(10,2) DEFAULT 0,
    prime_transport numeric(10,2) DEFAULT 0,
    prime_salissure numeric(10,2) DEFAULT 0,
    prime_encouragement numeric(10,2) DEFAULT 0,
    prime_anciennete numeric(10,2) DEFAULT 0,
    enfant_charge numeric(10,2) DEFAULT 0,
    assurances numeric(10,2) DEFAULT 0,
    autres numeric(10,2) DEFAULT 0,
    acomptes numeric(10,2) DEFAULT 0,
    cnss_employeur numeric(10,2) DEFAULT 0,
    cnss_employe numeric(10,2) DEFAULT 0,
    irpp_employe numeric(10,2) DEFAULT 0,
    net_payer numeric(10,2) DEFAULT 0,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT bordereaux_details_pkey PRIMARY KEY (id),
    CONSTRAINT fk_staff FOREIGN KEY (staff_id) REFERENCES public.staff(staff_id)
);
CREATE INDEX idx_bordereaux_details_staff_id ON public.bordereaux_details USING btree (staff_id);
ALTER TABLE public.bordereaux_details OWNER TO wxu_school;
```

#### Création de la table `wx_reduction_eleve`

```sql
CREATE TABLE public.wx_reduction_eleve (
    id public.uuid_type NOT NULL,
    school_id public.uuid_type NOT NULL,
    name character varying(255) NOT NULL,
    reduction numeric(5,2) NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT wx_reduction_eleve_pkey PRIMARY KEY (id),
    CONSTRAINT fk_schools FOREIGN KEY (school_id) REFERENCES public.schools(school_id)
);
CREATE INDEX idx_wx_reduction_eleve_school_id ON public.wx_reduction_eleve USING btree (school_id);
ALTER TABLE public.wx_reduction_eleve OWNER TO wxu_school;
```

#### Création de la table `wx_reduction_members`

```sql
CREATE TABLE public.wx_reduction_members (
    id public.uuid_type NOT NULL,
    reduction_id public.uuid_type NOT NULL,
    student_id public.uuid_type NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT wx_reduction_members_pkey PRIMARY KEY (id),
    CONSTRAINT fk_reduction FOREIGN KEY (reduction_id) REFERENCES public.wx_reduction_eleve(id),
    CONSTRAINT fk_student FOREIGN KEY (student_id) REFERENCES public.students(student_id)
);
CREATE INDEX idx_wx_reduction_members_reduction_id ON public.wx_reduction_members USING btree (reduction_id);
CREATE INDEX idx_wx_reduction_members_student_id ON public.wx_reduction_members USING btree (student_id);
ALTER TABLE public.wx_reduction_members OWNER TO wxu_school;
```

### Phase 2 : Audit des Clés Étrangères et des Index

#### Table `course_periods`

```sql
ALTER TABLE ONLY public.course_periods
    ADD CONSTRAINT fk_course_periods_secondary_teacher FOREIGN KEY (secondary_teacher_id) REFERENCES public.staff(staff_id);
CREATE INDEX idx_course_periods_secondary_teacher_id ON public.course_periods USING btree (secondary_teacher_id);
```

#### Table `student_enrollment`

```sql
ALTER TABLE ONLY public.student_enrollment
    ADD CONSTRAINT fk_student_enrollment_second_grade FOREIGN KEY (second_grade_id) REFERENCES public.school_gradelevels(gradelevel_id);
CREATE INDEX idx_student_enrollment_second_grade_id ON public.student_enrollment USING btree (second_grade_id);

ALTER TABLE ONLY public.student_enrollment
    ADD CONSTRAINT fk_student_enrollment_second_course_period FOREIGN KEY (second_course_period_id) REFERENCES public.course_periods(course_period_id);
CREATE INDEX idx_student_enrollment_second_course_period_id ON public.student_enrollment USING btree (second_course_period_id);
```

#### Table `student_report_card_grades`

```sql
ALTER TABLE ONLY public.student_report_card_grades
    ADD CONSTRAINT fk_student_report_card_grades_comment FOREIGN KEY (report_card_comment_id) REFERENCES public.report_card_comments(report_card_comment_id);
CREATE INDEX idx_student_report_card_grades_report_card_comment_id ON public.student_report_card_grades USING btree (report_card_comment_id);
```

### Phase 3 : Validation des Vues et Fonctions (Vérification)

Vous pouvez inspecter les définitions pour confirmer qu'elles utilisent bien les `UUID`.

```sql
\df+ public.calc_gpa_mp
\d+ public.marking_periods
```

### Phase 4 : Nettoyage et Finalisation (Vérification)

Les requêtes suivantes ne devraient retourner aucune ligne.

```sql
-- Vérifier l'absence de séquences
SELECT c.relname FROM pg_class c WHERE c.relkind = 'S';

-- Vérifier que tous les objets appartiennent à wxu_school (version corrigée)
SELECT n.nspname as schema_name, c.relname as table_name, pg_get_userbyid(c.relowner) as owner
FROM pg_class c
LEFT JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname NOT IN ('pg_catalog', 'information_schema', 'pg_toast')
  AND pg_get_userbyid(c.relowner) <> 'wxu_school';
```

---

## Étape Finale : Exportation de la Base de Données Corrigée

Une fois toutes les étapes terminées, quittez `psql` (avec `\q`) et exécutez la commande suivante depuis votre terminal pour sauvegarder le schéma final.

```bash
pg_dump -U postgres -d structure_uuid_v2 --schema-only > structure_uuid_v2_final.sql
```

Ce fichier `structure_uuid_v2_final.sql` contiendra le schéma complet et corrigé.
