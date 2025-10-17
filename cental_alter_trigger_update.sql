SELECT
    t.tgname AS trigger_name,
    tbl.relname AS table_name
FROM
    pg_trigger t
JOIN
    pg_proc p ON t.tgfoid = p.oid -- Jointure pour trouver la fonction appelée
JOIN
    pg_namespace nsp ON p.pronamespace = nsp.oid -- Espace de nom de la fonction
JOIN
    pg_class tbl ON t.tgrelid = tbl.oid -- Jointure pour trouver la table cible
WHERE
    nsp.nspname = 'public' -- Espace de nom de la fonction, souvent 'public'
    AND p.proname = 'set_updated_at' -- Nom exact de la fonction
    AND t.tgenabled = 'O' -- 'O' signifie 'originally enabled' (actif)
ORDER BY
    tbl.relname, t.tgname; -- Tri par nom de table et de trigger

-- 2. Désactiver les triggers :

-- Pour chaque résultat (trigger_name, table_name) de la requête précédente, exécutez la commande suivante sur la base de données centrale :
-- Par exemple, si la requête retourne trigger_name: set_updated_at_before_update et table_name: students, vous exécuterez :

ALTER TRIGGER set_updated_at_before_update ON students DISABLE;


