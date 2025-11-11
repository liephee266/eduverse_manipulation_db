-- 🗑️ PHASE 1: SUPPRESSION COMPLÈTE
-- =============================================
-- Désactiver les contraintes pour faciliter le DROP
SET session_replication_role = replica;

-- Supprimer les vues d'abord (dépendances)
DROP VIEW IF EXISTS public.transcript_grades CASCADE;
DROP VIEW IF EXISTS public.marking_periods CASCADE;
DROP VIEW IF EXISTS public.enroll_grade CASCADE;
DROP VIEW IF EXISTS public.course_details CASCADE;
DROP VIEW IF EXISTS public.dual CASCADE;

-- Supprimer les fonctions
DROP FUNCTION IF EXISTS public.calc_cum_cr_gpa(integer, integer) CASCADE;
DROP FUNCTION IF EXISTS public.calc_cum_gpa(integer, integer) CASCADE;
DROP FUNCTION IF EXISTS public.calc_gpa_mp(integer, integer) CASCADE;
DROP FUNCTION IF EXISTS public.credit(integer, integer) CASCADE;
DROP FUNCTION IF EXISTS public.immutable_unaccent(text) CASCADE;
DROP FUNCTION IF EXISTS public.set_class_rank_mp(integer) CASCADE;
DROP FUNCTION IF EXISTS public.set_updated_at() CASCADE;
DROP FUNCTION IF EXISTS public.t_update_mp_stats() CASCADE;

-- Supprimer les tables custom (wx_*) en premier
DROP TABLE IF EXISTS public.wx_ues_subjects CASCADE;
DROP TABLE IF EXISTS public.wx_ues CASCADE;
DROP TABLE IF EXISTS public.wx_teacher_attendance CASCADE;
DROP TABLE IF EXISTS public.wx_notes_student_details CASCADE;
DROP TABLE IF EXISTS public.wx_notes_details CASCADE;
DROP TABLE IF EXISTS public.wx_moyennes_validation_gradelevel CASCADE;
DROP TABLE IF EXISTS public.wx_moyennes_finales_students CASCADE;
DROP TABLE IF EXISTS public.wx_gradel_period_evaluation CASCADE;
DROP TABLE IF EXISTS public.wx_family_members CASCADE;
DROP TABLE IF EXISTS public.wx_families CASCADE;
DROP TABLE IF EXISTS public.wx_echelle_notation_appreciation CASCADE;
DROP TABLE IF EXISTS public.wx_custom_configuration_school CASCADE;
DROP TABLE IF EXISTS public.wx_course_subjects_gradelevels CASCADE;
DROP TABLE IF EXISTS public.wx_course_periods_subjects_periods CASCADE;
DROP TABLE IF EXISTS public.wx_course_periods_subjects CASCADE;
DROP TABLE IF EXISTS public.wx_course_periods_gradelevels CASCADE;
DROP TABLE IF EXISTS public.wx_config_publication_resultats CASCADE;
DROP TABLE IF EXISTS public.wx_appreciations CASCADE;
DROP TABLE IF EXISTS public.wx_rules_school CASCADE;

-- Supprimer les tables de jointure
DROP TABLE IF EXISTS public.students_join_users CASCADE;
DROP TABLE IF EXISTS public.students_join_people CASCADE;
DROP TABLE IF EXISTS public.students_join_address CASCADE;
DROP TABLE IF EXISTS public.student_enrollment_course_periods CASCADE;
DROP TABLE IF EXISTS public.people_join_contacts CASCADE;
DROP TABLE IF EXISTS public.messagexuser CASCADE;
DROP TABLE IF EXISTS public.moodlexrosario CASCADE;
DROP TABLE IF EXISTS public.course_period_school_periods CASCADE;
DROP TABLE IF EXISTS public.gradebook_grades CASCADE;

-- Supprimer les tables principales (ordre inverse des dépendances)
DROP TABLE IF EXISTS public.student_report_card_grades CASCADE;
DROP TABLE IF EXISTS public.student_report_card_comments CASCADE;
DROP TABLE IF EXISTS public.student_mp_comments CASCADE;
DROP TABLE IF EXISTS public.student_mp_stats CASCADE;
DROP TABLE IF EXISTS public.student_medical_visits CASCADE;
DROP TABLE IF EXISTS public.student_medical_alerts CASCADE;
DROP TABLE IF EXISTS public.student_medical CASCADE;
DROP TABLE IF EXISTS public.student_eligibility_activities CASCADE;
DROP TABLE IF EXISTS public.student_assignments CASCADE;
DROP TABLE IF EXISTS public.student_enrollment CASCADE;
DROP TABLE IF EXISTS public.student_enrollment_codes CASCADE;
DROP TABLE IF EXISTS public.students CASCADE;
DROP TABLE IF EXISTS public.gradebook_assignments CASCADE;
DROP TABLE IF EXISTS public.gradebook_assignment_types CASCADE;
DROP TABLE IF EXISTS public.grades_completed CASCADE;
DROP TABLE IF EXISTS public.schedule_requests CASCADE;
DROP TABLE IF EXISTS public.schedule CASCADE;
DROP TABLE IF EXISTS public.eligibility_completed CASCADE;
DROP TABLE IF EXISTS public.eligibility_activities CASCADE;
DROP TABLE IF EXISTS public.eligibility CASCADE;
DROP TABLE IF EXISTS public.lunch_period CASCADE;
DROP TABLE IF EXISTS public.attendance_period CASCADE;
DROP TABLE IF EXISTS public.attendance_day CASCADE;
DROP TABLE IF EXISTS public.attendance_completed CASCADE;
DROP TABLE IF EXISTS public.attendance_codes CASCADE;
DROP TABLE IF EXISTS public.attendance_code_categories CASCADE;
DROP TABLE IF EXISTS public.attendance_calendar CASCADE;
DROP TABLE IF EXISTS public.attendance_calendars CASCADE;
DROP TABLE IF EXISTS public.course_periods CASCADE;
DROP TABLE IF EXISTS public.courses CASCADE;
DROP TABLE IF EXISTS public.course_subjects CASCADE;
DROP TABLE IF EXISTS public.school_marking_periods CASCADE;
DROP TABLE IF EXISTS public.history_marking_periods CASCADE;
DROP TABLE IF EXISTS public.school_periods CASCADE;
DROP TABLE IF EXISTS public.school_gradelevels CASCADE;
DROP TABLE IF EXISTS public.schools CASCADE;
DROP TABLE IF EXISTS public.staff_exceptions CASCADE;
DROP TABLE IF EXISTS public.staff CASCADE;
DROP TABLE IF EXISTS public.people CASCADE;
DROP TABLE IF EXISTS public.address CASCADE;

-- Supprimer les tables de configuration
DROP TABLE IF EXISTS public.user_profiles CASCADE;
DROP TABLE IF EXISTS public.templates CASCADE;
DROP TABLE IF EXISTS public.student_field_categories CASCADE;
DROP TABLE IF EXISTS public.staff_fields CASCADE;
DROP TABLE IF EXISTS public.staff_field_categories CASCADE;
DROP TABLE IF EXISTS public.school_fields CASCADE;
DROP TABLE IF EXISTS public.resources CASCADE;
DROP TABLE IF EXISTS public.report_card_grades CASCADE;
DROP TABLE IF EXISTS public.report_card_grade_scales CASCADE;
DROP TABLE IF EXISTS public.report_card_comments CASCADE;
DROP TABLE IF EXISTS public.report_card_comment_codes CASCADE;
DROP TABLE IF EXISTS public.report_card_comment_code_scales CASCADE;
DROP TABLE IF EXISTS public.report_card_comment_categories CASCADE;
DROP TABLE IF EXISTS public.program_user_config CASCADE;
DROP TABLE IF EXISTS public.program_config CASCADE;
DROP TABLE IF EXISTS public.profile_exceptions CASCADE;
DROP TABLE IF EXISTS public.portal_polls CASCADE;
DROP TABLE IF EXISTS public.portal_poll_questions CASCADE;
DROP TABLE IF EXISTS public.portal_notes CASCADE;
DROP TABLE IF EXISTS public.people_fields CASCADE;
DROP TABLE IF EXISTS public.people_field_categories CASCADE;
DROP TABLE IF EXISTS public.messages CASCADE;
DROP TABLE IF EXISTS public.grade_levels CASCADE;
DROP TABLE IF EXISTS public.food_service_transactions CASCADE;
DROP TABLE IF EXISTS public.food_service_transaction_items CASCADE;
DROP TABLE IF EXISTS public.food_service_student_accounts CASCADE;
DROP TABLE IF EXISTS public.food_service_staff_transactions CASCADE;
DROP TABLE IF EXISTS public.food_service_staff_transaction_items CASCADE;
DROP TABLE IF EXISTS public.food_service_staff_accounts CASCADE;
DROP TABLE IF EXISTS public.food_service_menus CASCADE;
DROP TABLE IF EXISTS public.food_service_menu_items CASCADE;
DROP TABLE IF EXISTS public.food_service_items CASCADE;
DROP TABLE IF EXISTS public.food_service_categories CASCADE;
DROP TABLE IF EXISTS public.food_service_accounts CASCADE;
DROP TABLE IF EXISTS public.discipline_referrals CASCADE;
DROP TABLE IF EXISTS public.discipline_fields CASCADE;
DROP TABLE IF EXISTS public.discipline_field_usage CASCADE;
DROP TABLE IF EXISTS public.custom_fields CASCADE;
DROP TABLE IF EXISTS public.config CASCADE;
DROP TABLE IF EXISTS public.calendar_events CASCADE;
DROP TABLE IF EXISTS public.billing_payments CASCADE;
DROP TABLE IF EXISTS public.billing_fees CASCADE;
DROP TABLE IF EXISTS public.accounting_salaries CASCADE;
DROP TABLE IF EXISTS public.accounting_payments CASCADE;
DROP TABLE IF EXISTS public.accounting_incomes CASCADE;
DROP TABLE IF EXISTS public.accounting_categories CASCADE;
DROP TABLE IF EXISTS public.access_log CASCADE;
DROP TABLE IF EXISTS public.address_fields CASCADE;
DROP TABLE IF EXISTS public.address_field_categories CASCADE;

-- Supprimer les séquences
DROP SEQUENCE IF EXISTS public.wx_ues_subjects_id_seq CASCADE;
DROP SEQUENCE IF EXISTS public.wx_ues_id_seq CASCADE;
DROP SEQUENCE IF EXISTS public.wx_teacher_attendance_id_seq CASCADE;
DROP SEQUENCE IF EXISTS public.wx_notes_student_details_id_notes_student_details_seq CASCADE;
DROP SEQUENCE IF EXISTS public.wx_notes_details_id_notes_details_seq CASCADE;
DROP SEQUENCE IF EXISTS public.wx_moyennes_validation_gradelevel_id_seq CASCADE;
DROP SEQUENCE IF EXISTS public.wx_moyennes_finales_students_id_seq CASCADE;
DROP SEQUENCE IF EXISTS public.wx_gradel_period_evaluation_id_gradel_period_evaluation_seq CASCADE;
DROP SEQUENCE IF EXISTS public.wx_family_members_id_seq CASCADE;
DROP SEQUENCE IF EXISTS public.wx_families_id_seq CASCADE;
DROP SEQUENCE IF EXISTS public.wx_echelle_notation_appreciation_id_seq CASCADE;
DROP SEQUENCE IF EXISTS public.wx_custom_configuration_schoo_id_custom_configuration_schoo_seq CASCADE;
DROP SEQUENCE IF EXISTS public.wx_course_subjects_gradelevel_wx_course_subjects_gradelevel_seq CASCADE;
DROP SEQUENCE IF EXISTS public.wx_course_periods_subjects_pe_wx_course_periods_subjects_pe_seq CASCADE;
DROP SEQUENCE IF EXISTS public.wx_course_periods_subjects_wx_course_periods_subjects_id_seq CASCADE;
DROP SEQUENCE IF EXISTS public.wx_course_periods_gradelevels_wx_course_periods_gradelevels_seq CASCADE;
DROP SEQUENCE IF EXISTS public.wx_config_publication_resultats_id_seq CASCADE;
DROP SEQUENCE IF EXISTS public.wx_appreciations_id_seq CASCADE;
DROP SEQUENCE IF EXISTS public.rules_school_id_seq CASCADE;

-- Supprimer le domaine UUID s'il existe
DROP DOMAIN IF EXISTS public.uuid_type CASCADE;

-- Réactiver les contraintes
SET session_replication_role = DEFAULT;

-- Message de confirmation pour cette étape
DO $$
BEGIN
    RAISE NOTICE '✅ Étape 1 (Suppression des objets) terminée avec succès.';
END $$;