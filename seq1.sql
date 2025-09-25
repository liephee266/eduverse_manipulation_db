-- Ajouter colonne UUID aux tables PK
DO $$
DECLARE
    r RECORD;
    col TEXT;
BEGIN
    FOR r IN
        SELECT table_schema, table_name,
               array_agg(column_name ORDER BY ordinal_position) AS pk_columns
        FROM information_schema.key_column_usage kcu
        JOIN information_schema.table_constraints tc
          ON kcu.constraint_name = tc.constraint_name
         AND kcu.table_schema = tc.table_schema
        WHERE tc.constraint_type = 'PRIMARY KEY'
          AND kcu.table_schema NOT IN ('pg_catalog','information_schema')
        GROUP BY table_schema, table_name
    LOOP
        -- Ajouter colonne UUID
        EXECUTE format('ALTER TABLE %I.%I ADD COLUMN id_uuid UUID DEFAULT uuid_generate_v4();',
                       r.table_schema, r.table_name);

        -- Backup des colonnes existantes
        FOREACH col IN ARRAY r.pk_columns LOOP
            EXECUTE format('ALTER TABLE %I.%I RENAME COLUMN %I TO %I_old;',
                           r.table_schema, r.table_name, col, col);
        END LOOP;
    END LOOP;
END $$;

-- Ajouter colonne UUID aux tables enfants FK
DO $$
DECLARE
    fk RECORD;
    i INT;
    where_clause TEXT;
BEGIN
    FOR fk IN
        SELECT tc.table_schema AS child_schema,
               tc.table_name AS child_table,
               tc.constraint_name,
               array_agg(kcu.column_name ORDER BY kcu.ordinal_position) AS fk_columns,
               ccu.table_schema AS parent_schema,
               ccu.table_name AS parent_table,
               array_agg(ccu.column_name ORDER BY kcu.ordinal_position) AS referenced_columns
        FROM information_schema.table_constraints tc
        JOIN information_schema.key_column_usage kcu
          ON tc.constraint_name = kcu.constraint_name
         AND tc.table_schema = kcu.table_schema
        JOIN information_schema.constraint_column_usage ccu
          ON ccu.constraint_name = tc.constraint_name
         AND ccu.table_schema = tc.table_schema
        WHERE tc.constraint_type = 'FOREIGN KEY'
          AND tc.table_schema NOT IN ('pg_catalog','information_schema')
        GROUP BY tc.table_schema, tc.table_name, tc.constraint_name,
                 ccu.table_schema, ccu.table_name
    LOOP
        -- Ajouter colonne UUID dans la table enfant
        EXECUTE format('ALTER TABLE %I.%I ADD COLUMN %I_uuid UUID;',
                       fk.child_schema, fk.child_table, fk.constraint_name);

        -- Construire clause WHERE pour la mise à jour
        where_clause := '';
        FOR i IN 1..array_length(fk.fk_columns,1) LOOP
            IF i = 1 THEN
                where_clause := format('c.%I = p.%I_old', fk.fk_columns[i], fk.referenced_columns[i]);
            ELSE
                where_clause := where_clause || format(' AND c.%I = p.%I_old', fk.fk_columns[i], fk.referenced_columns[i]);
            END IF;
        END LOOP;

        -- Mettre à jour la colonne UUID
        EXECUTE format('UPDATE %I.%I c SET %I_uuid = p.id_uuid FROM %I.%I p WHERE %s;',
                       fk.child_schema, fk.child_table, fk.constraint_name,
                       fk.parent_schema, fk.parent_table, where_clause);

        -- Backup colonnes FK
        FOREACH col IN ARRAY fk.fk_columns LOOP
            EXECUTE format('ALTER TABLE %I.%I RENAME COLUMN %I TO %I_old;',
                           fk.child_schema, fk.child_table, col, col);
        END LOOP;

        -- Renommer la colonne UUID
        EXECUTE format('ALTER TABLE %I.%I RENAME COLUMN %I_uuid TO %I;',
                       fk.child_schema, fk.child_table, fk.constraint_name, fk.constraint_name);
    END LOOP;
END $$;
