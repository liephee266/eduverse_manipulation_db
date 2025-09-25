-- 1. Activer l'extension uuid-ossp
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- 2. Créer tables temporaires pour PK et FK composites et simples
DROP TABLE IF EXISTS tmp_pk;
CREATE TEMP TABLE tmp_pk AS
SELECT
    tc.table_schema,
    tc.table_name,
    tc.constraint_name,
    array_agg(kcu.column_name ORDER BY kcu.ordinal_position) AS pk_columns,
    count(*) AS pk_column_count
FROM information_schema.table_constraints tc
JOIN information_schema.key_column_usage kcu
  ON tc.constraint_name = kcu.constraint_name
 AND tc.table_schema = kcu.table_schema
WHERE tc.constraint_type = 'PRIMARY KEY'
GROUP BY tc.table_schema, tc.table_name, tc.constraint_name;

DROP TABLE IF EXISTS tmp_fk;
CREATE TEMP TABLE tmp_fk AS
SELECT
    tc.table_schema AS child_schema,
    tc.table_name AS child_table,
    tc.constraint_name,
    array_agg(kcu.column_name ORDER BY kcu.ordinal_position) AS fk_columns,
    ccu.table_schema AS parent_schema,
    ccu.table_name AS parent_table,
    array_agg(ccu.column_name ORDER BY kcu.ordinal_position) AS referenced_columns,
    count(*) AS fk_column_count
FROM information_schema.table_constraints tc
JOIN information_schema.key_column_usage kcu
  ON tc.constraint_name = kcu.constraint_name
 AND tc.table_schema = kcu.table_schema
JOIN information_schema.constraint_column_usage ccu
  ON ccu.constraint_name = tc.constraint_name
 AND ccu.table_schema = tc.table_schema
WHERE tc.constraint_type = 'FOREIGN KEY'
GROUP BY tc.table_schema, tc.table_name, tc.constraint_name,
         ccu.table_schema, ccu.table_name;

-- 3. Créer colonne UUID pour toutes les PK (simples et composites)
DO $$
DECLARE
    r RECORD;
    col TEXT;
BEGIN
    FOR r IN SELECT * FROM tmp_pk LOOP
        -- Ajouter colonne UUID globale
        EXECUTE format('ALTER TABLE %I.%I ADD COLUMN id_uuid UUID DEFAULT uuid_generate_v4();',
                       r.table_schema, r.table_name);
        -- Définir cette colonne comme PK
        EXECUTE format('ALTER TABLE %I.%I ADD PRIMARY KEY (id_uuid);',
                       r.table_schema, r.table_name);
        -- Backup des colonnes existantes
        FOREACH col IN ARRAY r.pk_columns LOOP
            EXECUTE format('ALTER TABLE %I.%I RENAME COLUMN %I TO %I_old;',
                           r.table_schema, r.table_name, col, col);
        END LOOP;
    END LOOP;
END $$;

-- 4. Créer colonnes UUID dans tables enfants pour toutes les FK
DO $$
DECLARE
    fk RECORD;
    i INT;
    col TEXT;
    where_clause TEXT;
BEGIN
    FOR fk IN SELECT * FROM tmp_fk LOOP
        -- Ajouter nouvelle colonne UUID dans table enfant
        EXECUTE format('ALTER TABLE %I.%I ADD COLUMN %I_uuid UUID;',
                       fk.child_schema, fk.child_table, fk.constraint_name);

        -- Construire clause WHERE pour FK composite ou simple
        where_clause := '';
        FOR i IN 1..array_length(fk.fk_columns,1) LOOP
            IF i=1 THEN
                where_clause := format('c.%I = p.%I_old', fk.fk_columns[i], fk.referenced_columns[i]);
            ELSE
                where_clause := where_clause || format(' AND c.%I = p.%I_old', fk.fk_columns[i], fk.referenced_columns[i]);
            END IF;
        END LOOP;

        -- Mettre à jour UUID FK
        EXECUTE format('UPDATE %I.%I c SET %I_uuid = p.id_uuid FROM %I.%I p WHERE %s;',
                       fk.child_schema, fk.child_table, fk.constraint_name,
                       fk.parent_schema, fk.parent_table, where_clause);

        -- Backup anciennes colonnes FK
        FOREACH col IN ARRAY fk.fk_columns LOOP
            EXECUTE format('ALTER TABLE %I.%I RENAME COLUMN %I TO %I_old;',
                           fk.child_schema, fk.child_table, col, col);
        END LOOP;

        -- Renommer colonne UUID pour correspondre au nom original
        EXECUTE format('ALTER TABLE %I.%I RENAME COLUMN %I_uuid TO %I;',
                       fk.child_schema, fk.child_table, fk.constraint_name, fk.constraint_name);
    END LOOP;
END $$;

-- 5. Supprimer contraintes FK et PK existantes (anciennes)
DO $$
DECLARE
    c RECORD;
BEGIN
    FOR c IN SELECT table_schema, table_name, constraint_name FROM information_schema.table_constraints
             WHERE constraint_type IN ('PRIMARY KEY','FOREIGN KEY') LOOP
        EXECUTE format('ALTER TABLE %I.%I DROP CONSTRAINT %I;', c.table_schema, c.table_name, c.constraint_name);
    END LOOP;
END $$;

-- 6. Ajouter trigger pour génération automatique UUID
DO $$
DECLARE
    t RECORD;
BEGIN
    FOR t IN SELECT table_schema, table_name FROM tmp_pk LOOP
        -- Créer la fonction pour générer UUID
        EXECUTE format($func$
            CREATE OR REPLACE FUNCTION %I_generate_uuid()
            RETURNS TRIGGER AS $$
            BEGIN
                IF NEW.id_uuid IS NULL THEN
                    NEW.id_uuid := uuid_generate_v4();
                END IF;
                RETURN NEW;
            END;
            $$ LANGUAGE plpgsql;
        $func$, t.table_name);

        -- Créer le trigger
        EXECUTE format('
            DROP TRIGGER IF EXISTS trigger_%I_id_uuid ON %I.%I;
            CREATE TRIGGER trigger_%I_id_uuid
            BEFORE INSERT ON %I.%I
            FOR EACH ROW
            EXECUTE FUNCTION %I_generate_uuid();',
            t.table_name, t.table_schema, t.table_name,
            t.table_name, t.table_schema, t.table_name,
            t.table_name
        );
    END LOOP;
END $$;

-- 7. Passer toutes les colonnes UUID en NOT NULL et indexer
DO $$
DECLARE
    t RECORD;
BEGIN
    FOR t IN SELECT table_schema, table_name FROM tmp_pk LOOP
        EXECUTE format('ALTER TABLE %I.%I ALTER COLUMN id_uuid SET NOT NULL;', t.table_schema, t.table_name);
        EXECUTE format('CREATE INDEX IF NOT EXISTS idx_%I_%I_id_uuid ON %I.%I(id_uuid);',
                       t.table_schema, t.table_name, t.table_schema, t.table_name);
    END LOOP;
END $$;

-- 8. Optionnel : supprimer anciennes colonnes après validation
-- ALTER TABLE schema_name.table_name DROP COLUMN col_old;
