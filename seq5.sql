CREATE OR REPLACE FUNCTION generate_uuid_trigger()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.id_uuid IS NULL THEN
        NEW.id_uuid := uuid_generate_v4();
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

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
        EXECUTE format('
            DROP TRIGGER IF EXISTS trigger_%I_id_uuid ON %I.%I;
            CREATE TRIGGER trigger_%I_id_uuid
            BEFORE INSERT ON %I.%I
            FOR EACH ROW
            EXECUTE FUNCTION generate_uuid_trigger();',
            t.table_name, t.table_schema, t.table_name,
            t.table_name, t.table_schema, t.table_name
        );
    END LOOP;
END $$;
