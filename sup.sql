-- 1. Ajouter la nouvelle colonne 'id' avec le type uuid_type (auto-génération)
ALTER TABLE user_profiles ADD COLUMN id uuid_type;

-- 2. Copier les valeurs de l'ancienne clé primaire vers la nouvelle colonne
UPDATE user_profiles SET id = user_profile_id;

-- 3. Supprimer l'ancienne contrainte de clé primaire (nom standard)
ALTER TABLE user_profiles DROP CONSTRAINT user_profiles_pkey;

-- 4. Supprimer l'ancienne colonne 'user_profile_id'
ALTER TABLE user_profiles DROP COLUMN user_profile_id;

-- 5. Renommer la nouvelle colonne 'id' pour s'assurer qu'elle porte le bon nom (facultatif si le nom est déjà correct)
-- ALTER TABLE user_profiles RENAME COLUMN id TO id; -- Déjà le bon nom, donc inutile

-- 6. Ajouter la nouvelle contrainte de clé primaire sur la colonne 'id' (nom standard)
ALTER TABLE user_profiles ADD CONSTRAINT user_profiles_pkey PRIMARY KEY (id);

-- Message de confirmation
DO $$
BEGIN
    RAISE NOTICE '✅ Colonne user_profile_id de la table user_profiles renommée en id avec succès.';
END $$;
