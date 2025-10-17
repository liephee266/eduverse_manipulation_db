--Étape 1 : Enregistrer une suppression dans la table de log
-- Table pour enregistrer les suppressions locales à synchroniser
CREATE TABLE IF NOT EXISTS local_deletion_log (
    log_id uuid PRIMARY KEY DEFAULT uuid_generate_v4(), -- Clé primaire auto-générée pour le log lui-même
    deleted_id uuid NOT NULL,          -- L'UUID de la ligne supprimée
    table_name text NOT NULL,          -- Le nom de la table d'origine
    deleted_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP -- Date/heure de la suppression
);


-- Index pour optimiser la lecture par table_name et deleted_at (utile pour la synchro incrémentielle)
CREATE INDEX IF NOT EXISTS idx_local_deletion_log_table_time ON local_deletion_log (table_name, deleted_at);
-- Index pour optimiser la suppression des logs traités
CREATE INDEX IF NOT EXISTS idx_local_deletion_log_id ON local_deletion_log (log_id);

--FIN Étape 1 : Enregistrer une suppression


-- Début Étape 2 : Fonction et trigger pour enregistrer les suppressions

-- Fonction qui enregistre l'UUID de la ligne supprimée dans la table de log
-- Reçoit le nom de la colonne de la clé primaire en argument
CREATE OR REPLACE FUNCTION log_deletion()
RETURNS TRIGGER AS $$
DECLARE
    pk_value UUID;
    pk_column_name TEXT;
BEGIN
    -- Récupérer le nom de la colonne de clé primaire depuis les arguments du trigger
    -- On suppose que le premier argument est le nom de la colonne PK
    pk_column_name := TG_ARGV[0];

    -- Récupérer la valeur de la clé primaire de la ligne supprimée (OLD)
    -- On utilise dynamic SQL pour accéder à la colonne nommée dynamiquement
    EXECUTE format('SELECT $1.%I', pk_column_name) USING OLD INTO pk_value;

    -- Vérifier que la valeur récupérée est non nulle (devrait l'être pour une PK)
    IF pk_value IS NOT NULL THEN
        -- Insérer l'UUID de la ligne supprimée et le nom de la table dans la table de log
        INSERT INTO local_deletion_log (deleted_id, table_name)
        VALUES (pk_value, TG_TABLE_NAME);
    ELSE
        -- Optionnel : Lever une exception ou logguer si la PK est nulle (ce qui ne devrait pas arriver)
        RAISE WARNING 'La clé primaire de la ligne supprimée dans % est NULL.', TG_TABLE_NAME;
    END IF;

    -- Pour AFTER triggers, on ne retourne rien
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

--FIN Étape 2 : Fonction et trigger pour enregistrer les suppressions

-- Début Étape 3 : Création des triggers pour les tables concernées

-- Exemples de création de triggers pour quelques tables (à adapter et répéter pour toutes les tables synchronisées)
-- Pour la table students (clé primaire : student_id)
CREATE TRIGGER trigger_log_student_deletion
AFTER DELETE ON students
FOR EACH ROW
EXECUTE FUNCTION log_deletion('student_id');

-- Pour la table staff (clé primaire : staff_id)
CREATE TRIGGER trigger_log_staff_deletion
AFTER DELETE ON staff
FOR EACH ROW
EXECUTE FUNCTION log_deletion('staff_id');

-- Pour la table courses (clé primaire : course_id)
CREATE TRIGGER trigger_log_course_deletion
AFTER DELETE ON courses
FOR EACH ROW
EXECUTE FUNCTION log_deletion('course_id');

-- Pour la table course_periods (clé primaire : course_period_id)
CREATE TRIGGER trigger_log_course_period_deletion
AFTER DELETE ON course_periods
FOR EACH ROW
EXECUTE FUNCTION log_deletion('course_period_id');

-- Pour la table student_enrollment (clé primaire : enrollment_id)
CREATE TRIGGER trigger_log_student_enrollment_deletion
AFTER DELETE ON student_enrollment
FOR EACH ROW
EXECUTE FUNCTION log_deletion('enrollment_id');

-- Pour la table attendance_period (clé primaire : attendance_period_id)
CREATE TRIGGER trigger_log_attendance_period_deletion
AFTER DELETE ON attendance_period
FOR EACH ROW
EXECUTE FUNCTION log_deletion('attendance_period_id');

-- Pour la table student_report_card_grades (clé primaire : student_report_card_grade_id)
CREATE TRIGGER trigger_log_student_report_card_grade_deletion
AFTER DELETE ON student_report_card_grades
FOR EACH ROW
EXECUTE FUNCTION log_deletion('student_report_card_grade_id');

-- ... et ainsi de suite pour toutes les tables que vous synchronisez.

-- Exemple pour une table custom
-- Pour la table wx_rules_school (clé primaire : wx_rule_school_id)
CREATE TRIGGER trigger_log_wx_rules_school_deletion
AFTER DELETE ON wx_rules_school
FOR EACH ROW
EXECUTE FUNCTION log_deletion('wx_rule_school_id');

-- ... (répétez pour toutes les tables concernées par la synchronisation)

--FIN Étape 3 : Création des triggers pour les tables concernées