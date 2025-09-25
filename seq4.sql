DO $$
DECLARE
    fk RECORD;
BEGIN
    FOR fk IN
        SELECT tc.table_schema AS child_schema,
               tc.table_name AS child_table,
               tc.constraint_name,
               ccu.table_schema AS parent_schema,
               ccu.table_name AS parent_table
        FROM information_schema.table_constraints tc
        JOIN information_schema.constraint_column_usage ccu
          ON ccu.constraint_name = tc.constraint_name
         AND ccu.table_schema = tc.table_schema
        WHERE tc.constraint_type = 'FOREIGN KEY'
          AND tc.table_schema NOT IN ('pg_catalog','information_schema')
    LOOP
        EXECUTE format('ALTER TABLE %I.%I ADD CONSTRAINT %I FOREIGN KEY (%I) REFERENCES %I.%I(id_uuid);',
                       fk.child_schema, fk.child_table, fk.constraint_name,
                       fk.constraint_name, fk.parent_schema, fk.parent_table);
    END LOOP;
END $$;
