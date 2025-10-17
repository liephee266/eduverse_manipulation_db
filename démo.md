Résumé des points à traiter avant le code Go :

Implémenter les triggers de suppression locale. ✅

Créer les fichiers de configuration (tables à synchroniser, ordonnancement).

Corriger les incohérences de clés étrangères dans la structure de la base de données. Cela est primordial. Les tables listées dans le point 4 de l'analyse des FK --doivent être modifiées pour que les colonnes de clés étrangères soient du bon type(uuid_type) et réfèrent les bonnes colonnes (UUID).

Désactiver les triggers de type set_updated_at sur la base centrale.