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