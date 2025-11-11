-- 🔧 PHASE 2: EXTENSIONS ET DOMAINES
-- =============================================
-- Activer les extensions nécessaires
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";
CREATE EXTENSION IF NOT EXISTS "unaccent";

-- Commentaires des extensions
COMMENT ON EXTENSION pg_trgm IS 'text similarity measurement and index searching based on trigrams';
COMMENT ON EXTENSION unaccent IS 'text search dictionary that removes accents';

-- Créer le domaine UUID standard - CORRIGÉ AVEC OR REPLACE
CREATE OR REPLACE DOMAIN uuid_type AS UUID NOT NULL DEFAULT uuid_generate_v4();

-- Message de confirmation pour cette étape
DO $$
BEGIN
    RAISE NOTICE '✅ Étape 2 (Extensions et Domaine) terminée avec succès.';
END $$;