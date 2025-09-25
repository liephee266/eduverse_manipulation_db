DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN
        SELECT tc.table_schema, tc.table_name, tc.constraint_name
        FROM information_schema.table_constraints tc
        WHERE constraint_type = 'PRIMARY KEY'
          AND table_schema NOT IN ('pg_catalog','information_schema')
    LOOP
        EXECUTE format('ALTER TABLE %I.%I DROP CONSTRAINT IF EXISTS %I;',
                       r.table_schema, r.table_name, r.constraint_name);

        EXECUTE format('ALTER TABLE %I.%I ADD PRIMARY KEY (id_uuid);',
                       r.table_schema, r.table_name);
    END LOOP;
END $$;
