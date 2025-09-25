-- 1. Active l'extension uuid-ossp
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- 2. Ajouter des colonnes UUID pour PK avec backup
DO $$
DECLARE
    t RECORD;
BEGIN
    FOR t IN
        SELECT table_schema, table_name, column_name
        FROM information_schema.table_constraints tc
        JOIN information_schema.key_column_usage kcu
        USING (constraint_name, table_schema)
        WHERE constraint_type = 'PRIMARY KEY'
    LOOP
        -- Ajouter la colonne UUID avec valeur par défaut
        EXECUTE format('ALTER TABLE %I.%I ADD COLUMN %I_uuid UUID DEFAULT uuid_generate_v4();',
                       t.table_schema, t.table_name, t.column_name);
        -- Backup de l'ancienne colonne
        EXECUTE format('ALTER TABLE %I.%I RENAME COLUMN %I TO %I_old;',
                       t.table_schema, t.table_name, t.column_name, t.column_name);
        -- Renommer UUID en nom original
        EXECUTE format('ALTER TABLE %I.%I RENAME COLUMN %I_uuid TO %I;',
                       t.table_schema, t.table_name, t.column_name, t.column_name);
    END LOOP;
END $$;

-- 3. Ajouter des colonnes UUID pour FK et remplir
DO $$
DECLARE
    fk RECORD;
BEGIN
    FOR fk IN
        SELECT
            tc.constraint_name,
            tc.table_schema,
            tc.table_name AS child_table,
            kcu.column_name AS child_column,
            ccu.table_schema AS parent_schema,
            ccu.table_name AS parent_table,
            ccu.column_name AS parent_column
        FROM information_schema.table_constraints AS tc
        JOIN information_schema.key_column_usage AS kcu
          ON tc.constraint_name = kcu.constraint_name
          AND tc.table_schema = kcu.table_schema
        JOIN information_schema.constraint_column_usage AS ccu
          ON ccu.constraint_name = tc.constraint_name
          AND ccu.table_schema = tc.table_schema
        WHERE tc.constraint_type = 'FOREIGN KEY'
    LOOP
        -- Ajouter la colonne UUID FK
        EXECUTE format('ALTER TABLE %I.%I ADD COLUMN %I_uuid UUID;',
                       fk.table_schema, fk.child_table, fk.child_column);

        -- Remplir avec la valeur correspondante
        EXECUTE format(
            'UPDATE %I.%I c
             SET %I_uuid = p.%I
             FROM %I.%I p
             WHERE c.%I = p.%I_old;',
            fk.table_schema, fk.child_table, fk.child_column, fk.parent_column,
            fk.parent_schema, fk.parent_table, fk.child_column, fk.parent_column
        );

        -- Backup ancienne colonne
        EXECUTE format('ALTER TABLE %I.%I RENAME COLUMN %I TO %I_old;',
                       fk.table_schema, fk.child_table, fk.child_column, fk.child_column);

        -- Renommer la colonne UUID
        EXECUTE format('ALTER TABLE %I.%I RENAME COLUMN %I_uuid TO %I;',
                       fk.table_schema, fk.child_table, fk.child_column, fk.child_column);
    END LOOP;
END $$;

-- 4. Supprimer contraintes PK/FK existantes
DO $$
DECLARE
    c RECORD;
BEGIN
    FOR c IN
        SELECT table_schema, table_name, constraint_name
        FROM information_schema.table_constraints
        WHERE constraint_type IN ('PRIMARY KEY','FOREIGN KEY')
    LOOP
        EXECUTE format('ALTER TABLE %I.%I DROP CONSTRAINT %I;',
                       c.table_schema, c.table_name, c.constraint_name);
    END LOOP;
END $$;

-- 5. Recréer PK sur UUID et indexer
DO $$
DECLARE
    t RECORD;
BEGIN
    FOR t IN
        SELECT tc.table_schema, tc.table_name, kcu.column_name
        FROM information_schema.table_constraints tc
        JOIN information_schema.key_column_usage kcu
          ON tc.constraint_name = kcu.constraint_name
          AND tc.table_schema = kcu.table_schema
        WHERE tc.constraint_type = 'PRIMARY KEY'
    LOOP
        EXECUTE format('ALTER TABLE %I.%I ADD PRIMARY KEY (%I);',
                       t.table_schema, t.table_name, t.column_name);
        EXECUTE format('CREATE INDEX IF NOT EXISTS idx_%I_%I_%I ON %I.%I (%I);',
                       t.table_schema, t.table_name, t.column_name, t.table_schema, t.table_name, t.column_name);
    END LOOP;
END $$;

-- 6. Recréer FK sur UUID
DO $$
DECLARE
    fk RECORD;
BEGIN
    FOR fk IN
        SELECT
            tc.constraint_name,
            tc.table_schema,
            tc.table_name AS child_table,
            kcu.column_name AS child_column,
            ccu.table_schema AS parent_schema,
            ccu.table_name AS parent_table,
            ccu.column_name AS parent_column
        FROM information_schema.table_constraints AS tc
        JOIN information_schema.key_column_usage AS kcu
          ON tc.constraint_name = kcu.constraint_name
          AND tc.table_schema = kcu.table_schema
        JOIN information_schema.constraint_column_usage AS ccu
          ON ccu.constraint_name = tc.constraint_name
          AND ccu.table_schema = tc.table_schema
        WHERE tc.constraint_type = 'FOREIGN KEY'
    LOOP
        EXECUTE format(
            'ALTER TABLE %I.%I ADD CONSTRAINT %I_uuid FOREIGN KEY (%I) REFERENCES %I.%I(%I);',
            fk.table_schema, fk.child_table, fk.constraint_name, fk.child_column,
            fk.parent_schema, fk.parent_table, fk.parent_column
        );
    END LOOP;
END $$;

-- 7. Passer toutes les colonnes UUID en NOT NULL
DO $$
DECLARE
    col RECORD;
BEGIN
    FOR col IN
        SELECT table_schema, table_name, column_name
        FROM information_schema.columns
        WHERE data_type='uuid' AND column_name NOT LIKE '%_old'
    LOOP
        EXECUTE format('ALTER TABLE %I.%I ALTER COLUMN %I SET NOT NULL;',
                       col.table_schema, col.table_name, col.column_name);
    END LOOP;
END $$;

-- 8. Créer trigger pour générer automatiquement UUID à l'insertion
DO $$
DECLARE
    t RECORD;
BEGIN
    FOR t IN
        SELECT table_schema, table_name, column_name
        FROM information_schema.columns
        WHERE data_type='uuid'
          AND column_default LIKE '%uuid_generate_v4()%'
    LOOP
        EXECUTE format('
            CREATE OR REPLACE FUNCTION %I.%I_generate_uuid()
            RETURNS TRIGGER AS $$
            BEGIN
                IF NEW.%I IS NULL THEN
                    NEW.%I := uuid_generate_v4();
                END IF;
                RETURN NEW;
            END;
            $$ LANGUAGE plpgsql;',
            t.table_schema, t.table_name, t.column_name, t.column_name
        );

        EXECUTE format('
            DROP TRIGGER IF EXISTS trigger_%I_%I_uuid ON %I.%I;
            CREATE TRIGGER trigger_%I_%I_uuid
            BEFORE INSERT ON %I.%I
            FOR EACH ROW
            EXECUTE FUNCTION %I.%I_generate_uuid();',
            t.table_name, t.column_name, t.table_schema, t.table_name,
            t.table_name, t.column_name, t.table_schema, t.table_name,
            t.table_schema, t.table_name
        );
    END LOOP;
END $$;
