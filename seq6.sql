DO $$
DECLARE
    t RECORD;
BEGIN
    FOR t IN
        SELECT table_schema, table_name
        FROM information_schema.tables
        WHERE table_schema NOT IN ('pg_catalog','information_schema')
          AND table_type = 'BASE TABLE'
    LOOP
        EXECUTE format('ALTER TABLE %I.%I ALTER COLUMN id_uuid SET NOT NULL;', t.table_schema, t.table_name);
        EXECUTE format('CREATE INDEX IF NOT EXISTS idx_%I_%I_id_uuid ON %I.%I(id_uuid);',
                       t.table_schema, t.table_name, t.table_schema, t.table_name);
    END LOOP;
END $$;
