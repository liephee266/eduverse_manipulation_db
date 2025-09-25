DO $$
DECLARE
    c RECORD;
BEGIN
    FOR c IN
        SELECT table_schema, table_name, constraint_name
        FROM information_schema.table_constraints
        WHERE constraint_type = 'FOREIGN KEY'
          AND table_schema NOT IN ('pg_catalog','information_schema')
    LOOP
        EXECUTE format('ALTER TABLE %I.%I DROP CONSTRAINT %I;',
                       c.table_schema, c.table_name, c.constraint_name);
    END LOOP;
END $$;
