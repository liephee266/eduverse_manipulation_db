-- Suppression des anciennes contraintes de clé étrangère
-- Les noms des contraintes sont déduits du fichier 2, adaptés au format standard de PostgreSQL pour les tables enfants du fichier 1.
-- Si le nom exact diffère, il faudra l'identifier via \d nom_de_la_table dans psql.

-- Suppression des contraintes dans le fichier 1 (base source actuelle)
-- Table accounting_incomes
ALTER TABLE public.accounting_incomes DROP CONSTRAINT IF EXISTS accounting_incomes_category_id_fkey;
ALTER TABLE public.accounting_incomes DROP CONSTRAINT IF EXISTS accounting_incomes_school_id_syear_fkey; -- Note: school_id, syear -> school_id (uuid)
-- Table accounting_payments
ALTER TABLE public.accounting_payments DROP CONSTRAINT IF EXISTS accounting_payments_category_id_fkey;
ALTER TABLE public.accounting_payments DROP CONSTRAINT IF EXISTS accounting_payments_school_id_syear_fkey; -- Note: school_id, syear -> school_id (uuid)
ALTER TABLE public.accounting_payments DROP CONSTRAINT IF EXISTS accounting_payments_staff_id_fkey; -- Note: staff_id -> staff_id (uuid)
-- Table accounting_salaries
ALTER TABLE public.accounting_salaries DROP CONSTRAINT IF EXISTS accounting_salaries_school_id_syear_fkey; -- Note: school_id, syear -> school_id (uuid)
ALTER TABLE public.accounting_salaries DROP CONSTRAINT IF EXISTS accounting_salaries_staff_id_fkey; -- Note: staff_id -> staff_id (uuid)
-- Table attendance_calendar
ALTER TABLE public.attendance_calendar DROP CONSTRAINT IF EXISTS attendance_calendar_school_id_syear_fkey; -- Note: school_id, syear -> school_id (uuid)
ALTER TABLE public.attendance_calendar DROP CONSTRAINT IF EXISTS attendance_calendar_calendar_id_fkey; -- Note: calendar_id -> calendar_id (uuid)
-- Table attendance_calendars
ALTER TABLE public.attendance_calendars DROP CONSTRAINT IF EXISTS attendance_calendars_school_id_syear_fkey; -- Note: school_id, syear -> school_id (uuid)
-- Table attendance_code_categories
ALTER TABLE public.attendance_code_categories DROP CONSTRAINT IF EXISTS attendance_code_categories_school_id_syear_fkey; -- Note: school_id, syear -> school_id (uuid)
-- Table attendance_codes
ALTER TABLE public.attendance_codes DROP CONSTRAINT IF EXISTS attendance_codes_school_id_syear_fkey; -- Note: school_id, syear -> school_id (uuid)
-- Table attendance_completed
ALTER TABLE public.attendance_completed DROP CONSTRAINT IF EXISTS attendance_completed_staff_id_fkey; -- Note: staff_id -> staff_id (uuid)
-- Table attendance_day
ALTER TABLE public.attendance_day DROP CONSTRAINT IF EXISTS attendance_day_marking_period_id_fkey; -- Note: marking_period_id -> marking_period_id (uuid)
ALTER TABLE public.attendance_day DROP CONSTRAINT IF EXISTS attendance_day_student_id_fkey; -- Note: student_id -> student_id (uuid)
-- Table attendance_period
ALTER TABLE public.attendance_period DROP CONSTRAINT IF EXISTS attendance_period_course_period_id_fkey; -- Note: course_period_id -> course_period_id (uuid)
ALTER TABLE public.attendance_period DROP CONSTRAINT IF EXISTS attendance_period_marking_period_id_fkey; -- Note: marking_period_id -> marking_period_id (uuid)
ALTER TABLE public.attendance_period DROP CONSTRAINT IF EXISTS attendance_period_student_id_fkey; -- Note: student_id -> student_id (uuid)
-- Table billing_fees
ALTER TABLE public.billing_fees DROP CONSTRAINT IF EXISTS billing_fees_school_id_syear_fkey; -- Note: school_id, syear -> school_id (uuid)
ALTER TABLE public.billing_fees DROP CONSTRAINT IF EXISTS billing_fees_student_id_fkey; -- Note: student_id -> student_id (uuid)
-- Table billing_payments
ALTER TABLE public.billing_payments DROP CONSTRAINT IF EXISTS billing_payments_school_id_syear_fkey; -- Note: school_id, syear -> school_id (uuid)
ALTER TABLE public.billing_payments DROP CONSTRAINT IF EXISTS billing_payments_student_id_fkey; -- Note: student_id -> student_id (uuid)
-- Table calendar_events
ALTER TABLE public.calendar_events DROP CONSTRAINT IF EXISTS calendar_events_school_id_syear_fkey; -- Note: school_id, syear -> school_id (uuid)
-- Table course_period_school_periods
ALTER TABLE public.course_period_school_periods DROP CONSTRAINT IF EXISTS course_period_school_periods_course_period_id_fkey; -- Note: course_period_id -> course_period_id (uuid)
-- Table course_periods
ALTER TABLE public.course_periods DROP CONSTRAINT IF EXISTS course_periods_course_id_fkey; -- Note: course_id -> course_id (uuid)
ALTER TABLE public.course_periods DROP CONSTRAINT IF EXISTS course_periods_marking_period_id_fkey; -- Note: marking_period_id -> marking_period_id (uuid)
ALTER TABLE public.course_periods DROP CONSTRAINT IF EXISTS course_periods_school_id_syear_fkey; -- Note: school_id, syear -> school_id (uuid)
ALTER TABLE public.course_periods DROP CONSTRAINT IF EXISTS course_periods_secondary_teacher_id_fkey; -- Note: secondary_teacher_id -> staff_id (uuid)
ALTER TABLE public.course_periods DROP CONSTRAINT IF EXISTS course_periods_teacher_id_fkey; -- Note: teacher_id -> staff_id (uuid)
-- Table course_subjects
ALTER TABLE public.course_subjects DROP CONSTRAINT IF EXISTS course_subjects_school_id_syear_fkey; -- Note: school_id, syear -> school_id (uuid)
-- Table courses
ALTER TABLE public.courses DROP CONSTRAINT IF EXISTS courses_school_id_syear_fkey; -- Note: school_id, syear -> school_id (uuid)
ALTER TABLE public.courses DROP CONSTRAINT IF EXISTS courses_subject_id_fkey; -- Note: subject_id -> subject_id (uuid)
-- Table discipline_field_usage
ALTER TABLE public.discipline_field_usage DROP CONSTRAINT IF EXISTS discipline_field_usage_school_id_syear_fkey; -- Note: school_id, syear -> school_id (uuid)
-- Table discipline_referrals
ALTER TABLE public.discipline_referrals DROP CONSTRAINT IF EXISTS discipline_referrals_school_id_syear_fkey; -- Note: school_id, syear -> school_id (uuid)
ALTER TABLE public.discipline_referrals DROP CONSTRAINT IF EXISTS discipline_referrals_staff_id_fkey; -- Note: staff_id -> staff_id (uuid)
ALTER TABLE public.discipline_referrals DROP CONSTRAINT IF EXISTS discipline_referrals_student_id_fkey; -- Note: student_id -> student_id (uuid)
-- Table eligibility_activities
ALTER TABLE public.eligibility_activities DROP CONSTRAINT IF EXISTS eligibility_activities_school_id_syear_fkey; -- Note: school_id, syear -> school_id (uuid)
-- Table eligibility_completed
ALTER TABLE public.eligibility_completed DROP CONSTRAINT IF EXISTS eligibility_completed_staff_id_fkey; -- Note: staff_id -> staff_id (uuid)
-- Table eligibility
ALTER TABLE public.eligibility DROP CONSTRAINT IF EXISTS eligibility_course_period_id_fkey; -- Note: course_period_id -> course_period_id (uuid)
ALTER TABLE public.eligibility DROP CONSTRAINT IF EXISTS eligibility_student_id_fkey; -- Note: student_id -> student_id (uuid)
-- Table food_service_staff_accounts
ALTER TABLE public.food_service_staff_accounts DROP CONSTRAINT IF EXISTS food_service_staff_accounts_staff_id_fkey; -- Note: staff_id -> staff_id (uuid)
-- Table food_service_staff_transactions
ALTER TABLE public.food_service_staff_transactions DROP CONSTRAINT IF EXISTS food_service_staff_transactions_school_id_syear_fkey; -- Note: school_id, syear -> school_id (uuid)
ALTER TABLE public.food_service_staff_transactions DROP CONSTRAINT IF EXISTS food_service_staff_transactions_staff_id_fkey; -- Note: staff_id -> staff_id (uuid)
-- Table food_service_student_accounts
ALTER TABLE public.food_service_student_accounts DROP CONSTRAINT IF EXISTS food_service_student_accounts_student_id_fkey; -- Note: student_id -> student_id (uuid)
-- Table food_service_transactions
ALTER TABLE public.food_service_transactions DROP CONSTRAINT IF EXISTS food_service_transactions_school_id_syear_fkey; -- Note: school_id, syear -> school_id (uuid)
ALTER TABLE public.food_service_transactions DROP CONSTRAINT IF EXISTS food_service_transactions_student_id_fkey; -- Note: student_id -> student_id (uuid)
-- Table gradebook_assignment_types
ALTER TABLE public.gradebook_assignment_types DROP CONSTRAINT IF EXISTS gradebook_assignment_types_course_id_fkey; -- Note: course_id -> course_id (uuid)
ALTER TABLE public.gradebook_assignment_types DROP CONSTRAINT IF EXISTS gradebook_assignment_types_staff_id_fkey; -- Note: staff_id -> staff_id (uuid)
-- Table gradebook_assignments
ALTER TABLE public.gradebook_assignments DROP CONSTRAINT IF EXISTS gradebook_assignments_course_id_fkey; -- Note: course_id -> course_id (uuid)
ALTER TABLE public.gradebook_assignments DROP CONSTRAINT IF EXISTS gradebook_assignments_course_period_id_fkey; -- Note: course_period_id -> course_period_id (uuid)
ALTER TABLE public.gradebook_assignments DROP CONSTRAINT IF EXISTS gradebook_assignments_marking_period_id_fkey; -- Note: marking_period_id -> marking_period_id (uuid)
ALTER TABLE public.gradebook_assignments DROP CONSTRAINT IF EXISTS gradebook_assignments_staff_id_fkey; -- Note: staff_id -> staff_id (uuid)
-- Table gradebook_grades
ALTER TABLE public.gradebook_grades DROP CONSTRAINT IF EXISTS gradebook_grades_course_period_id_fkey; -- Note: course_period_id -> course_period_id (uuid)
ALTER TABLE public.gradebook_grades DROP CONSTRAINT IF EXISTS gradebook_grades_student_id_fkey; -- Note: student_id -> student_id (uuid)
-- Table grades_completed
ALTER TABLE public.grades_completed DROP CONSTRAINT IF EXISTS grades_completed_course_period_id_fkey; -- Note: course_period_id -> course_period_id (uuid)
ALTER TABLE public.grades_completed DROP CONSTRAINT IF EXISTS grades_completed_marking_period_id_fkey; -- Note: marking_period_id -> marking_period_id (uuid)
ALTER TABLE public.grades_completed DROP CONSTRAINT IF EXISTS grades_completed_staff_id_fkey; -- Note: staff_id -> staff_id (uuid)
-- Table lunch_period
ALTER TABLE public.lunch_period DROP CONSTRAINT IF EXISTS lunch_period_course_period_id_fkey; -- Note: course_period_id -> course_period_id (uuid)
ALTER TABLE public.lunch_period DROP CONSTRAINT IF EXISTS lunch_period_marking_period_id_fkey; -- Note: marking_period_id -> marking_period_id (uuid)
ALTER TABLE public.lunch_period DROP CONSTRAINT IF EXISTS lunch_period_student_id_fkey; -- Note: student_id -> student_id (uuid)
-- Table messages
ALTER TABLE public.messages DROP CONSTRAINT IF EXISTS messages_school_id_syear_fkey; -- Note: school_id, syear -> school_id (uuid)
-- Table portal_notes
ALTER TABLE public.portal_notes DROP CONSTRAINT IF EXISTS portal_notes_school_id_syear_fkey; -- Note: school_id, syear -> school_id (uuid)
-- Table portal_polls
ALTER TABLE public.portal_polls DROP CONSTRAINT IF EXISTS portal_polls_school_id_syear_fkey; -- Note: school_id, syear -> school_id (uuid)
-- Table program_config
ALTER TABLE public.program_config DROP CONSTRAINT IF EXISTS program_config_school_id_syear_fkey; -- Note: school_id, syear -> school_id (uuid)
-- Table report_card_comment_categories
ALTER TABLE public.report_card_comment_categories DROP CONSTRAINT IF EXISTS report_card_comment_categories_course_id_fkey; -- Note: course_id -> course_id (uuid)
ALTER TABLE public.report_card_comment_categories DROP CONSTRAINT IF EXISTS report_card_comment_categories_school_id_syear_fkey; -- Note: school_id, syear -> school_id (uuid)
-- Table report_card_comments
ALTER TABLE public.report_card_comments DROP CONSTRAINT IF EXISTS report_card_comments_school_id_syear_fkey; -- Note: school_id, syear -> school_id (uuid)
-- Table report_card_grade_scales
ALTER TABLE public.report_card_grade_scales DROP CONSTRAINT IF EXISTS report_card_grade_scales_school_id_syear_fkey; -- Note: school_id, syear -> school_id (uuid)
-- Table report_card_grades
ALTER TABLE public.report_card_grades DROP CONSTRAINT IF EXISTS report_card_grades_school_id_syear_fkey; -- Note: school_id, syear -> school_id (uuid)
-- Table schedule
ALTER TABLE public.schedule DROP CONSTRAINT IF EXISTS schedule_course_id_fkey; -- Note: course_id -> course_id (uuid)
ALTER TABLE public.schedule DROP CONSTRAINT IF EXISTS schedule_course_period_id_fkey; -- Note: course_period_id -> course_period_id (uuid)
ALTER TABLE public.schedule DROP CONSTRAINT IF EXISTS schedule_marking_period_id_fkey; -- Note: marking_period_id -> marking_period_id (uuid)
ALTER TABLE public.schedule DROP CONSTRAINT IF EXISTS schedule_school_id_syear_fkey; -- Note: school_id, syear -> school_id (uuid)
ALTER TABLE public.schedule DROP CONSTRAINT IF EXISTS schedule_student_id_fkey; -- Note: student_id -> student_id (uuid)
-- Table schedule_requests
ALTER TABLE public.schedule_requests DROP CONSTRAINT IF EXISTS schedule_requests_course_id_fkey; -- Note: course_id -> course_id (uuid)
ALTER TABLE public.schedule_requests DROP CONSTRAINT IF EXISTS schedule_requests_marking_period_id_fkey; -- Note: marking_period_id -> marking_period_id (uuid)
ALTER TABLE public.schedule_requests DROP CONSTRAINT IF EXISTS schedule_requests_school_id_syear_fkey; -- Note: school_id, syear -> school_id (uuid)
ALTER TABLE public.schedule_requests DROP CONSTRAINT IF EXISTS schedule_requests_student_id_fkey; -- Note: student_id -> student_id (uuid)
-- Table school_marking_periods
ALTER TABLE public.school_marking_periods DROP CONSTRAINT IF EXISTS school_marking_periods_school_id_syear_fkey; -- Note: school_id, syear -> school_id (uuid)
-- Table school_periods
ALTER TABLE public.school_periods DROP CONSTRAINT IF EXISTS school_periods_school_id_syear_fkey; -- Note: school_id, syear -> school_id (uuid)
-- Table staff_exceptions
ALTER TABLE public.staff_exceptions DROP CONSTRAINT IF EXISTS staff_exceptions_user_id_fkey; -- Note: user_id -> staff_id (uuid)
-- Table student_assignments
ALTER TABLE public.student_assignments DROP CONSTRAINT IF EXISTS student_assignments_student_id_fkey; -- Note: student_id -> student_id (uuid)
-- Table student_eligibility_activities
ALTER TABLE public.student_eligibility_activities DROP CONSTRAINT IF EXISTS student_eligibility_activities_student_id_fkey; -- Note: student_id -> student_id (uuid)
-- Table student_enrollment
ALTER TABLE public.student_enrollment DROP CONSTRAINT IF EXISTS student_enrollment_school_id_syear_fkey; -- Note: school_id, syear -> school_id (uuid)
ALTER TABLE public.student_enrollment DROP CONSTRAINT IF EXISTS student_enrollment_student_id_fkey; -- Note: student_id -> student_id (uuid)
ALTER TABLE public.student_enrollment DROP CONSTRAINT IF EXISTS student_enrollment_grade_id_fkey; -- Note: grade_id -> gradelevel_id (uuid)
ALTER TABLE public.student_enrollment DROP CONSTRAINT IF EXISTS student_enrollment_course_period_id_fkey; -- Note: course_period_id -> course_period_id (uuid)
ALTER TABLE public.student_enrollment DROP CONSTRAINT IF EXISTS student_enrollment_second_course_period_id_fkey; -- Note: second_course_period_id -> course_period_id (uuid)
ALTER TABLE public.student_enrollment DROP CONSTRAINT IF EXISTS student_enrollment_second_grade_id_fkey; -- Note: second_grade_id -> gradelevel_id (uuid)
-- Table student_medical_alerts
ALTER TABLE public.student_medical_alerts DROP CONSTRAINT IF EXISTS student_medical_alerts_student_id_fkey; -- Note: student_id -> student_id (uuid)
-- Table student_medical
ALTER TABLE public.student_medical DROP CONSTRAINT IF EXISTS student_medical_student_id_fkey; -- Note: student_id -> student_id (uuid)
-- Table student_medical_visits
ALTER TABLE public.student_medical_visits DROP CONSTRAINT IF EXISTS student_medical_visits_student_id_fkey; -- Note: student_id -> student_id (uuid)
-- Table student_mp_comments
ALTER TABLE public.student_mp_comments DROP CONSTRAINT IF EXISTS student_mp_comments_marking_period_id_fkey; -- Note: marking_period_id -> marking_period_id (uuid)
ALTER TABLE public.student_mp_comments DROP CONSTRAINT IF EXISTS student_mp_comments_student_id_fkey; -- Note: student_id -> student_id (uuid)
-- Table student_mp_stats
ALTER TABLE public.student_mp_stats DROP CONSTRAINT IF EXISTS student_mp_stats_student_id_fkey; -- Note: student_id -> student_id (uuid)
-- Table student_report_card_comments
ALTER TABLE public.student_report_card_comments DROP CONSTRAINT IF EXISTS student_report_card_comments_course_period_id_fkey; -- Note: course_period_id -> course_period_id (uuid)
ALTER TABLE public.student_report_card_comments DROP CONSTRAINT IF EXISTS student_report_card_comments_marking_period_id_fkey; -- Note: marking_period_id -> marking_period_id (uuid)
ALTER TABLE public.student_report_card_comments DROP CONSTRAINT IF EXISTS student_report_card_comments_school_id_syear_fkey; -- Note: school_id, syear -> school_id (uuid)
ALTER TABLE public.student_report_card_comments DROP CONSTRAINT IF EXISTS student_report_card_comments_student_id_fkey; -- Note: student_id -> student_id (uuid)
-- Table student_report_card_grades
ALTER TABLE public.student_report_card_grades DROP CONSTRAINT IF EXISTS student_report_card_grades_course_period_id_fkey; -- Note: course_period_id -> course_period_id (uuid)
ALTER TABLE public.student_report_card_grades DROP CONSTRAINT IF EXISTS student_report_card_grades_student_id_fkey; -- Note: student_id -> student_id (uuid)
-- Table students_join_address
ALTER TABLE public.students_join_address DROP CONSTRAINT IF EXISTS students_join_address_student_id_fkey; -- Note: student_id -> student_id (uuid)
-- Table students_join_people
ALTER TABLE public.students_join_people DROP CONSTRAINT IF EXISTS students_join_people_student_id_fkey; -- Note: student_id -> student_id (uuid)
-- Table students_join_users
ALTER TABLE public.students_join_users DROP CONSTRAINT IF EXISTS students_join_users_staff_id_fkey; -- Note: staff_id -> staff_id (uuid)
ALTER TABLE public.students_join_users DROP CONSTRAINT IF EXISTS students_join_users_student_id_fkey; -- Note: student_id -> student_id (uuid)
-- Table wx_course_periods_gradelevels
ALTER TABLE public.wx_course_periods_gradelevels DROP CONSTRAINT IF EXISTS fk_course_periods; -- Note: course_periods_id -> course_period_id (uuid)
ALTER TABLE public.wx_course_periods_gradelevels DROP CONSTRAINT IF EXISTS fk_school_gradelevels; -- Note: school_gradelevels_id -> gradelevel_id (uuid)
-- Table wx_course_periods_subjects
ALTER TABLE public.wx_course_periods_subjects DROP CONSTRAINT IF EXISTS fk_course_periods; -- Note: course_periods_id -> course_period_id (uuid)
ALTER TABLE public.wx_course_periods_subjects DROP CONSTRAINT IF EXISTS fk_course_subjects; -- Note: course_subjects_id -> subject_id (uuid)
-- Table wx_course_subjects_gradelevels
ALTER TABLE public.wx_course_subjects_gradelevels DROP CONSTRAINT IF EXISTS fk_course_subjects; -- Note: course_subjects_id -> subject_id (uuid)
ALTER TABLE public.wx_course_subjects_gradelevels DROP CONSTRAINT IF EXISTS fk_school_gradelevels; -- Note: school_gradelevels_id -> gradelevel_id (uuid)
-- Table wx_family_members
ALTER TABLE public.wx_family_members DROP CONSTRAINT IF EXISTS wx_family_members_family_id_fkey; -- Note: family_id -> wx_family_id (uuid)
ALTER TABLE public.wx_family_members DROP CONSTRAINT IF EXISTS wx_family_members_student_id_fkey; -- Note: student_id -> student_id (uuid)
-- Table wx_moyennes_finales_students
ALTER TABLE public.wx_moyennes_finales_students DROP CONSTRAINT IF EXISTS fk_student_enrollment_id; -- Note: student_enrollment_id -> enrollment_id (uuid)
-- Table wx_moyennes_validation_gradelevel
ALTER TABLE public.wx_moyennes_validation_gradelevel DROP CONSTRAINT IF EXISTS fk_school_gradelevels_id; -- Note: school_gradelevels_id -> gradelevel_id (uuid)
-- Table wx_notes_student_details
ALTER TABLE public.wx_notes_student_details DROP CONSTRAINT IF EXISTS wx_notes_student_details_student_id_fkey; -- Note: student_id -> student_id (uuid)
ALTER TABLE public.wx_notes_student_details DROP CONSTRAINT IF EXISTS wx_notes_student_details_wx_course_periods_subjects_id_fkey; -- Note: wx_course_periods_subjects_id -> wx_course_periods_subjects_id (uuid)
-- Table wx_reduction_members
ALTER TABLE public.wx_reduction_members DROP CONSTRAINT IF EXISTS wx_reduction_members_reduction_id_fkey; -- Note: reduction_id -> wx_reduction_eleve_id (uuid)
ALTER TABLE public.wx_reduction_members DROP CONSTRAINT IF EXISTS wx_reduction_members_student_id_fkey; -- Note: student_id -> student_id (uuid)
-- Table wx_teacher_attendance
ALTER TABLE public.wx_teacher_attendance DROP CONSTRAINT IF EXISTS fk_staff; -- Note: staff_id -> staff_id (uuid)
-- Table wx_ues_subjects
ALTER TABLE public.wx_ues_subjects DROP CONSTRAINT IF EXISTS wx_ues_subjects_subject_id_fkey; -- Note: subject_id -> subject_id (uuid)
ALTER TABLE public.wx_ues_subjects DROP CONSTRAINT IF EXISTS wx_ues_subjects_ue_id_fkey; -- Note: ue_id -> ue_id (uuid)

-- Modification des colonnes de clé étrangère pour utiliser uuid_type
-- Les colonnes sont converties de integer vers uuid_type en les castant via ::uuid.
-- Si des données ne sont pas convertibles, cela échouera et devra être corrigé manuellement.

-- Table accounting_incomes
ALTER TABLE public.accounting_incomes ALTER COLUMN category_id TYPE public.uuid_type USING category_id::public.uuid_type;
ALTER TABLE public.accounting_incomes ALTER COLUMN school_id TYPE public.uuid_type USING school_id::public.uuid_type;
-- Table accounting_payments
ALTER TABLE public.accounting_payments ALTER COLUMN category_id TYPE public.uuid_type USING category_id::public.uuid_type;
ALTER TABLE public.accounting_payments ALTER COLUMN school_id TYPE public.uuid_type USING school_id::public.uuid_type;
ALTER TABLE public.accounting_payments ALTER COLUMN staff_id TYPE public.uuid_type USING staff_id::public.uuid_type;
-- Table accounting_salaries
ALTER TABLE public.accounting_salaries ALTER COLUMN school_id TYPE public.uuid_type USING school_id::public.uuid_type;
ALTER TABLE public.accounting_salaries ALTER COLUMN staff_id TYPE public.uuid_type USING staff_id::public.uuid_type;
-- Table attendance_calendar
ALTER TABLE public.attendance_calendar ALTER COLUMN school_id TYPE public.uuid_type USING school_id::public.uuid_type;
ALTER TABLE public.attendance_calendar ALTER COLUMN calendar_id TYPE public.uuid_type USING calendar_id::public.uuid_type;
-- Table attendance_calendars
ALTER TABLE public.attendance_calendars ALTER COLUMN school_id TYPE public.uuid_type USING school_id::public.uuid_type;
-- Table attendance_code_categories
ALTER TABLE public.attendance_code_categories ALTER COLUMN school_id TYPE public.uuid_type USING school_id::public.uuid_type;
-- Table attendance_codes
ALTER TABLE public.attendance_codes ALTER COLUMN school_id TYPE public.uuid_type USING school_id::public.uuid_type;
-- Table attendance_completed
ALTER TABLE public.attendance_completed ALTER COLUMN staff_id TYPE public.uuid_type USING staff_id::public.uuid_type;
-- Table attendance_day
ALTER TABLE public.attendance_day ALTER COLUMN marking_period_id TYPE public.uuid_type USING marking_period_id::public.uuid_type;
ALTER TABLE public.attendance_day ALTER COLUMN student_id TYPE public.uuid_type USING student_id::public.uuid_type;
-- Table attendance_period
ALTER TABLE public.attendance_period ALTER COLUMN course_period_id TYPE public.uuid_type USING course_period_id::public.uuid_type;
ALTER TABLE public.attendance_period ALTER COLUMN marking_period_id TYPE public.uuid_type USING marking_period_id::public.uuid_type;
ALTER TABLE public.attendance_period ALTER COLUMN student_id TYPE public.uuid_type USING student_id::public.uuid_type;
-- Table billing_fees
ALTER TABLE public.billing_fees ALTER COLUMN school_id TYPE public.uuid_type USING school_id::public.uuid_type;
ALTER TABLE public.billing_fees ALTER COLUMN student_id TYPE public.uuid_type USING student_id::public.uuid_type;
-- Table billing_payments
ALTER TABLE public.billing_payments ALTER COLUMN school_id TYPE public.uuid_type USING school_id::public.uuid_type;
ALTER TABLE public.billing_payments ALTER COLUMN student_id TYPE public.uuid_type USING student_id::public.uuid_type;
-- Table calendar_events
ALTER TABLE public.calendar_events ALTER COLUMN school_id TYPE public.uuid_type USING school_id::public.uuid_type;
-- Table course_period_school_periods
ALTER TABLE public.course_period_school_periods ALTER COLUMN course_period_id TYPE public.uuid_type USING course_period_id::public.uuid_type;
-- Table course_periods
ALTER TABLE public.course_periods ALTER COLUMN course_id TYPE public.uuid_type USING course_id::public.uuid_type;
ALTER TABLE public.course_periods ALTER COLUMN marking_period_id TYPE public.uuid_type USING marking_period_id::public.uuid_type;
ALTER TABLE public.course_periods ALTER COLUMN school_id TYPE public.uuid_type USING school_id::public.uuid_type;
ALTER TABLE public.course_periods ALTER COLUMN secondary_teacher_id TYPE public.uuid_type USING secondary_teacher_id::public.uuid_type;
ALTER TABLE public.course_periods ALTER COLUMN teacher_id TYPE public.uuid_type USING teacher_id::public.uuid_type;
-- Table course_subjects
ALTER TABLE public.course_subjects ALTER COLUMN school_id TYPE public.uuid_type USING school_id::public.uuid_type;
-- Table courses
ALTER TABLE public.courses ALTER COLUMN school_id TYPE public.uuid_type USING school_id::public.uuid_type;
ALTER TABLE public.courses ALTER COLUMN subject_id TYPE public.uuid_type USING subject_id::public.uuid_type;
-- Table discipline_field_usage
ALTER TABLE public.discipline_field_usage ALTER COLUMN school_id TYPE public.uuid_type USING school_id::public.uuid_type;
-- Table discipline_referrals
ALTER TABLE public.discipline_referrals ALTER COLUMN school_id TYPE public.uuid_type USING school_id::public.uuid_type;
ALTER TABLE public.discipline_referrals ALTER COLUMN staff_id TYPE public.uuid_type USING staff_id::public.uuid_type;
ALTER TABLE public.discipline_referrals ALTER COLUMN student_id TYPE public.uuid_type USING student_id::public.uuid_type;
-- Table eligibility_activities
ALTER TABLE public.eligibility_activities ALTER COLUMN school_id TYPE public.uuid_type USING school_id::public.uuid_type;
-- Table eligibility_completed
ALTER TABLE public.eligibility_completed ALTER COLUMN staff_id TYPE public.uuid_type USING staff_id::public.uuid_type;
-- Table eligibility
ALTER TABLE public.eligibility ALTER COLUMN course_period_id TYPE public.uuid_type USING course_period_id::public.uuid_type;
ALTER TABLE public.eligibility ALTER COLUMN student_id TYPE public.uuid_type USING student_id::public.uuid_type;
-- Table food_service_staff_accounts
ALTER TABLE public.food_service_staff_accounts ALTER COLUMN staff_id TYPE public.uuid_type USING staff_id::public.uuid_type;
-- Table food_service_staff_transactions
ALTER TABLE public.food_service_staff_transactions ALTER COLUMN school_id TYPE public.uuid_type USING school_id::public.uuid_type;
ALTER TABLE public.food_service_staff_transactions ALTER COLUMN staff_id TYPE public.uuid_type USING staff_id::public.uuid_type;
-- Table food_service_student_accounts
ALTER TABLE public.food_service_student_accounts ALTER COLUMN student_id TYPE public.uuid_type USING student_id::public.uuid_type;
-- Table food_service_transactions
ALTER TABLE public.food_service_transactions ALTER COLUMN school_id TYPE public.uuid_type USING school_id::public.uuid_type;
ALTER TABLE public.food_service_transactions ALTER COLUMN student_id TYPE public.uuid_type USING student_id::public.uuid_type;
-- Table gradebook_assignment_types
ALTER TABLE public.gradebook_assignment_types ALTER COLUMN course_id TYPE public.uuid_type USING course_id::public.uuid_type;
ALTER TABLE public.gradebook_assignment_types ALTER COLUMN staff_id TYPE public.uuid_type USING staff_id::public.uuid_type;
-- Table gradebook_assignments
ALTER TABLE public.gradebook_assignments ALTER COLUMN course_id TYPE public.uuid_type USING course_id::public.uuid_type;
ALTER TABLE public.gradebook_assignments ALTER COLUMN course_period_id TYPE public.uuid_type USING course_period_id::public.uuid_type;
ALTER TABLE public.gradebook_assignments ALTER COLUMN marking_period_id TYPE public.uuid_type USING marking_period_id::public.uuid_type;
ALTER TABLE public.gradebook_assignments ALTER COLUMN staff_id TYPE public.uuid_type USING staff_id::public.uuid_type;
-- Table gradebook_grades
ALTER TABLE public.gradebook_grades ALTER COLUMN course_period_id TYPE public.uuid_type USING course_period_id::public.uuid_type;
ALTER TABLE public.gradebook_grades ALTER COLUMN student_id TYPE public.uuid_type USING student_id::public.uuid_type;
-- Table grades_completed
ALTER TABLE public.grades_completed ALTER COLUMN course_period_id TYPE public.uuid_type USING course_period_id::public.uuid_type;
ALTER TABLE public.grades_completed ALTER COLUMN marking_period_id TYPE public.uuid_type USING marking_period_id::public.uuid_type;
ALTER TABLE public.grades_completed ALTER COLUMN staff_id TYPE public.uuid_type USING staff_id::public.uuid_type;
-- Table lunch_period
ALTER TABLE public.lunch_period ALTER COLUMN course_period_id TYPE public.uuid_type USING course_period_id::public.uuid_type;
ALTER TABLE public.lunch_period ALTER COLUMN marking_period_id TYPE public.uuid_type USING marking_period_id::public.uuid_type;
ALTER TABLE public.lunch_period ALTER COLUMN student_id TYPE public.uuid_type USING student_id::public.uuid_type;
-- Table messages
ALTER TABLE public.messages ALTER COLUMN school_id TYPE public.uuid_type USING school_id::public.uuid_type;
-- Table portal_notes
ALTER TABLE public.portal_notes ALTER COLUMN school_id TYPE public.uuid_type USING school_id::public.uuid_type;
-- Table portal_polls
ALTER TABLE public.portal_polls ALTER COLUMN school_id TYPE public.uuid_type USING school_id::public.uuid_type;
-- Table program_config
ALTER TABLE public.program_config ALTER COLUMN school_id TYPE public.uuid_type USING school_id::public.uuid_type;
-- Table report_card_comment_categories
ALTER TABLE public.report_card_comment_categories ALTER COLUMN course_id TYPE public.uuid_type USING course_id::public.uuid_type;
ALTER TABLE public.report_card_comment_categories ALTER COLUMN school_id TYPE public.uuid_type USING school_id::public.uuid_type;
-- Table report_card_comments
ALTER TABLE public.report_card_comments ALTER COLUMN school_id TYPE public.uuid_type USING school_id::public.uuid_type;
-- Table report_card_grade_scales
ALTER TABLE public.report_card_grade_scales ALTER COLUMN school_id TYPE public.uuid_type USING school_id::public.uuid_type;
-- Table report_card_grades
ALTER TABLE public.report_card_grades ALTER COLUMN school_id TYPE public.uuid_type USING school_id::public.uuid_type;
-- Table schedule
ALTER TABLE public.schedule ALTER COLUMN course_id TYPE public.uuid_type USING course_id::public.uuid_type;
ALTER TABLE public.schedule ALTER COLUMN course_period_id TYPE public.uuid_type USING course_period_id::public.uuid_type;
ALTER TABLE public.schedule ALTER COLUMN marking_period_id TYPE public.uuid_type USING marking_period_id::public.uuid_type;
ALTER TABLE public.schedule ALTER COLUMN school_id TYPE public.uuid_type USING school_id::public.uuid_type;
ALTER TABLE public.schedule ALTER COLUMN student_id TYPE public.uuid_type USING student_id::public.uuid_type;
-- Table schedule_requests
ALTER TABLE public.schedule_requests ALTER COLUMN course_id TYPE public.uuid_type USING course_id::public.uuid_type;
ALTER TABLE public.schedule_requests ALTER COLUMN marking_period_id TYPE public.uuid_type USING marking_period_id::public.uuid_type;
ALTER TABLE public.schedule_requests ALTER COLUMN school_id TYPE public.uuid_type USING school_id::public.uuid_type;
ALTER TABLE public.schedule_requests ALTER COLUMN student_id TYPE public.uuid_type USING student_id::public.uuid_type;
-- Table school_marking_periods
ALTER TABLE public.school_marking_periods ALTER COLUMN school_id TYPE public.uuid_type USING school_id::public.uuid_type;
-- Table school_periods
ALTER TABLE public.school_periods ALTER COLUMN school_id TYPE public.uuid_type USING school_id::public.uuid_type;
-- Table staff_exceptions
ALTER TABLE public.staff_exceptions ALTER COLUMN user_id TYPE public.uuid_type USING user_id::public.uuid_type;
-- Table student_assignments
ALTER TABLE public.student_assignments ALTER COLUMN student_id TYPE public.uuid_type USING student_id::public.uuid_type;
-- Table student_eligibility_activities
ALTER TABLE public.student_eligibility_activities ALTER COLUMN student_id TYPE public.uuid_type USING student_id::public.uuid_type;
-- Table student_enrollment
ALTER TABLE public.student_enrollment ALTER COLUMN school_id TYPE public.uuid_type USING school_id::public.uuid_type;
ALTER TABLE public.student_enrollment ALTER COLUMN student_id TYPE public.uuid_type USING student_id::public.uuid_type;
ALTER TABLE public.student_enrollment ALTER COLUMN grade_id TYPE public.uuid_type USING grade_id::public.uuid_type;
ALTER TABLE public.student_enrollment ALTER COLUMN course_period_id TYPE public.uuid_type USING course_period_id::public.uuid_type;
ALTER TABLE public.student_enrollment ALTER COLUMN second_course_period_id TYPE public.uuid_type USING second_course_period_id::public.uuid_type;
ALTER TABLE public.student_enrollment ALTER COLUMN second_grade_id TYPE public.uuid_type USING second_grade_id::public.uuid_type;
-- Table student_medical_alerts
ALTER TABLE public.student_medical_alerts ALTER COLUMN student_id TYPE public.uuid_type USING student_id::public.uuid_type;
-- Table student_medical
ALTER TABLE public.student_medical ALTER COLUMN student_id TYPE public.uuid_type USING student_id::public.uuid_type;
-- Table student_medical_visits
ALTER TABLE public.student_medical_visits ALTER COLUMN student_id TYPE public.uuid_type USING student_id::public.uuid_type;
-- Table student_mp_comments
ALTER TABLE public.student_mp_comments ALTER COLUMN marking_period_id TYPE public.uuid_type USING marking_period_id::public.uuid_type;
ALTER TABLE public.student_mp_comments ALTER COLUMN student_id TYPE public.uuid_type USING student_id::public.uuid_type;
-- Table student_mp_stats
ALTER TABLE public.student_mp_stats ALTER COLUMN student_id TYPE public.uuid_type USING student_id::public.uuid_type;
-- Table student_report_card_comments
ALTER TABLE public.student_report_card_comments ALTER COLUMN course_period_id TYPE public.uuid_type USING course_period_id::public.uuid_type;
ALTER TABLE public.student_report_card_comments ALTER COLUMN marking_period_id TYPE public.uuid_type USING marking_period_id::public.uuid_type;
ALTER TABLE public.student_report_card_comments ALTER COLUMN school_id TYPE public.uuid_type USING school_id::public.uuid_type;
ALTER TABLE public.student_report_card_comments ALTER COLUMN student_id TYPE public.uuid_type USING student_id::public.uuid_type;
-- Table student_report_card_grades
ALTER TABLE public.student_report_card_grades ALTER COLUMN course_period_id TYPE public.uuid_type USING course_period_id::public.uuid_type;
ALTER TABLE public.student_report_card_grades ALTER COLUMN student_id TYPE public.uuid_type USING student_id::public.uuid_type;
-- Table students_join_address
ALTER TABLE public.students_join_address ALTER COLUMN student_id TYPE public.uuid_type USING student_id::public.uuid_type;
-- Table students_join_people
ALTER TABLE public.students_join_people ALTER COLUMN student_id TYPE public.uuid_type USING student_id::public.uuid_type;
-- Table students_join_users
ALTER TABLE public.students_join_users ALTER COLUMN staff_id TYPE public.uuid_type USING staff_id::public.uuid_type;
ALTER TABLE public.students_join_users ALTER COLUMN student_id TYPE public.uuid_type USING student_id::public.uuid_type;
-- Table wx_course_periods_gradelevels
ALTER TABLE public.wx_course_periods_gradelevels ALTER COLUMN course_periods_id TYPE public.uuid_type USING course_periods_id::public.uuid_type;
ALTER TABLE public.wx_course_periods_gradelevels ALTER COLUMN school_gradelevels_id TYPE public.uuid_type USING school_gradelevels_id::public.uuid_type;
-- Table wx_course_periods_subjects
ALTER TABLE public.wx_course_periods_subjects ALTER COLUMN course_periods_id TYPE public.uuid_type USING course_periods_id::public.uuid_type;
ALTER TABLE public.wx_course_periods_subjects ALTER COLUMN course_subjects_id TYPE public.uuid_type USING course_subjects_id::public.uuid_type;
-- Table wx_course_subjects_gradelevels
ALTER TABLE public.wx_course_subjects_gradelevels ALTER COLUMN course_subjects_id TYPE public.uuid_type USING course_subjects_id::public.uuid_type;
ALTER TABLE public.wx_course_subjects_gradelevels ALTER COLUMN school_gradelevels_id TYPE public.uuid_type USING school_gradelevels_id::public.uuid_type;
-- Table wx_family_members
ALTER TABLE public.wx_family_members ALTER COLUMN family_id TYPE public.uuid_type USING family_id::public.uuid_type;
ALTER TABLE public.wx_family_members ALTER COLUMN student_id TYPE public.uuid_type USING student_id::public.uuid_type;
-- Table wx_moyennes_finales_students
ALTER TABLE public.wx_moyennes_finales_students ALTER COLUMN student_enrollment_id TYPE public.uuid_type USING student_enrollment_id::public.uuid_type;
-- Table wx_moyennes_validation_gradelevel
ALTER TABLE public.wx_moyennes_validation_gradelevel ALTER COLUMN school_gradelevels_id TYPE public.uuid_type USING school_gradelevels_id::public.uuid_type;
-- Table wx_notes_student_details
ALTER TABLE public.wx_notes_student_details ALTER COLUMN student_id TYPE public.uuid_type USING student_id::public.uuid_type;
ALTER TABLE public.wx_notes_student_details ALTER COLUMN wx_course_periods_subjects_id TYPE public.uuid_type USING wx_course_periods_subjects_id::public.uuid_type;
-- Table wx_reduction_members
ALTER TABLE public.wx_reduction_members ALTER COLUMN reduction_id TYPE public.uuid_type USING reduction_id::public.uuid_type;
ALTER TABLE public.wx_reduction_members ALTER COLUMN student_id TYPE public.uuid_type USING student_id::public.uuid_type;
-- Table wx_teacher_attendance
ALTER TABLE public.wx_teacher_attendance ALTER COLUMN staff_id TYPE public.uuid_type USING staff_id::public.uuid_type;
-- Table wx_ues_subjects
ALTER TABLE public.wx_ues_subjects ALTER COLUMN subject_id TYPE public.uuid_type USING subject_id::public.uuid_type;
ALTER TABLE public.wx_ues_subjects ALTER COLUMN ue_id TYPE public.uuid_type USING ue_id::public.uuid_type;

-- Recréation des contraintes de clé étrangère
-- Les contraintes sont recréées pour pointer vers les colonnes uuid_type des tables parentes.

-- Table accounting_incomes
ALTER TABLE public.accounting_incomes ADD CONSTRAINT accounting_incomes_category_id_fkey FOREIGN KEY (category_id) REFERENCES public.accounting_categories(accounting_category_id);
ALTER TABLE public.accounting_incomes ADD CONSTRAINT accounting_incomes_school_id_fkey FOREIGN KEY (school_id) REFERENCES public.schools(school_id);
-- Table accounting_payments
ALTER TABLE public.accounting_payments ADD CONSTRAINT accounting_payments_category_id_fkey FOREIGN KEY (category_id) REFERENCES public.accounting_categories(accounting_category_id);
ALTER TABLE public.accounting_payments ADD CONSTRAINT accounting_payments_school_id_fkey FOREIGN KEY (school_id) REFERENCES public.schools(school_id);
ALTER TABLE public.accounting_payments ADD CONSTRAINT accounting_payments_staff_id_fkey FOREIGN KEY (staff_id) REFERENCES public.staff(staff_id);
-- Table accounting_salaries
ALTER TABLE public.accounting_salaries ADD CONSTRAINT accounting_salaries_school_id_fkey FOREIGN KEY (school_id) REFERENCES public.schools(school_id);
ALTER TABLE public.accounting_salaries ADD CONSTRAINT accounting_salaries_staff_id_fkey FOREIGN KEY (staff_id) REFERENCES public.staff(staff_id);
-- Table attendance_calendar
ALTER TABLE public.attendance_calendar ADD CONSTRAINT attendance_calendar_school_id_fkey FOREIGN KEY (school_id) REFERENCES public.schools(school_id);
ALTER TABLE public.attendance_calendar ADD CONSTRAINT attendance_calendar_calendar_id_fkey FOREIGN KEY (calendar_id) REFERENCES public.attendance_calendars(calendar_id);
-- Table attendance_calendars
ALTER TABLE public.attendance_calendars ADD CONSTRAINT attendance_calendars_school_id_fkey FOREIGN KEY (school_id) REFERENCES public.schools(school_id);
-- Table attendance_code_categories
ALTER TABLE public.attendance_code_categories ADD CONSTRAINT attendance_code_categories_school_id_fkey FOREIGN KEY (school_id) REFERENCES public.schools(school_id);
-- Table attendance_codes
ALTER TABLE public.attendance_codes ADD CONSTRAINT attendance_codes_school_id_fkey FOREIGN KEY (school_id) REFERENCES public.schools(school_id);
-- Table attendance_completed
ALTER TABLE public.attendance_completed ADD CONSTRAINT attendance_completed_staff_id_fkey FOREIGN KEY (staff_id) REFERENCES public.staff(staff_id);
-- Table attendance_day
ALTER TABLE public.attendance_day ADD CONSTRAINT attendance_day_marking_period_id_fkey FOREIGN KEY (marking_period_id) REFERENCES public.school_marking_periods(marking_period_id);
ALTER TABLE public.attendance_day ADD CONSTRAINT attendance_day_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.students(student_id);
-- Table attendance_period
ALTER TABLE public.attendance_period ADD CONSTRAINT attendance_period_course_period_id_fkey FOREIGN KEY (course_period_id) REFERENCES public.course_periods(course_period_id);
ALTER TABLE public.attendance_period ADD CONSTRAINT attendance_period_marking_period_id_fkey FOREIGN KEY (marking_period_id) REFERENCES public.school_marking_periods(marking_period_id);
ALTER TABLE public.attendance_period ADD CONSTRAINT attendance_period_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.students(student_id);
-- Table billing_fees
ALTER TABLE public.billing_fees ADD CONSTRAINT billing_fees_school_id_fkey FOREIGN KEY (school_id) REFERENCES public.schools(school_id);
ALTER TABLE public.billing_fees ADD CONSTRAINT billing_fees_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.students(student_id);
-- Table billing_payments
ALTER TABLE public.billing_payments ADD CONSTRAINT billing_payments_school_id_fkey FOREIGN KEY (school_id) REFERENCES public.schools(school_id);
ALTER TABLE public.billing_payments ADD CONSTRAINT billing_payments_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.students(student_id);
-- Table calendar_events
ALTER TABLE public.calendar_events ADD CONSTRAINT calendar_events_school_id_fkey FOREIGN KEY (school_id) REFERENCES public.schools(school_id);
-- Table course_period_school_periods
ALTER TABLE public.course_period_school_periods ADD CONSTRAINT course_period_school_periods_course_period_id_fkey FOREIGN KEY (course_period_id) REFERENCES public.course_periods(course_period_id);
-- Table course_periods
ALTER TABLE public.course_periods ADD CONSTRAINT course_periods_course_id_fkey FOREIGN KEY (course_id) REFERENCES public.courses(course_id);
ALTER TABLE public.course_periods ADD CONSTRAINT course_periods_marking_period_id_fkey FOREIGN KEY (marking_period_id) REFERENCES public.school_marking_periods(marking_period_id);
ALTER TABLE public.course_periods ADD CONSTRAINT course_periods_school_id_fkey FOREIGN KEY (school_id) REFERENCES public.schools(school_id);
ALTER TABLE public.course_periods ADD CONSTRAINT course_periods_secondary_teacher_id_fkey FOREIGN KEY (secondary_teacher_id) REFERENCES public.staff(staff_id);
ALTER TABLE public.course_periods ADD CONSTRAINT course_periods_teacher_id_fkey FOREIGN KEY (teacher_id) REFERENCES public.staff(staff_id);
-- Table course_subjects
ALTER TABLE public.course_subjects ADD CONSTRAINT course_subjects_school_id_fkey FOREIGN KEY (school_id) REFERENCES public.schools(school_id);
-- Table courses
ALTER TABLE public.courses ADD CONSTRAINT courses_school_id_fkey FOREIGN KEY (school_id) REFERENCES public.schools(school_id);
ALTER TABLE public.courses ADD CONSTRAINT courses_subject_id_fkey FOREIGN KEY (subject_id) REFERENCES public.course_subjects(subject_id);
-- Table discipline_field_usage
ALTER TABLE public.discipline_field_usage ADD CONSTRAINT discipline_field_usage_school_id_fkey FOREIGN KEY (school_id) REFERENCES public.schools(school_id);
-- Table discipline_referrals
ALTER TABLE public.discipline_referrals ADD CONSTRAINT discipline_referrals_school_id_fkey FOREIGN KEY (school_id) REFERENCES public.schools(school_id);
ALTER TABLE public.discipline_referrals ADD CONSTRAINT discipline_referrals_staff_id_fkey FOREIGN KEY (staff_id) REFERENCES public.staff(staff_id);
ALTER TABLE public.discipline_referrals ADD CONSTRAINT discipline_referrals_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.students(student_id);
-- Table eligibility_activities
ALTER TABLE public.eligibility_activities ADD CONSTRAINT eligibility_activities_school_id_fkey FOREIGN KEY (school_id) REFERENCES public.schools(school_id);
-- Table eligibility_completed
ALTER TABLE public.eligibility_completed ADD CONSTRAINT eligibility_completed_staff_id_fkey FOREIGN KEY (staff_id) REFERENCES public.staff(staff_id);
-- Table eligibility
ALTER TABLE public.eligibility ADD CONSTRAINT eligibility_course_period_id_fkey FOREIGN KEY (course_period_id) REFERENCES public.course_periods(course_period_id);
ALTER TABLE public.eligibility ADD CONSTRAINT eligibility_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.students(student_id);
-- Table food_service_staff_accounts
ALTER TABLE public.food_service_staff_accounts ADD CONSTRAINT food_service_staff_accounts_staff_id_fkey FOREIGN KEY (staff_id) REFERENCES public.staff(staff_id);
-- Table food_service_staff_transactions
ALTER TABLE public.food_service_staff_transactions ADD CONSTRAINT food_service_staff_transactions_school_id_fkey FOREIGN KEY (school_id) REFERENCES public.schools(school_id);
ALTER TABLE public.food_service_staff_transactions ADD CONSTRAINT food_service_staff_transactions_staff_id_fkey FOREIGN KEY (staff_id) REFERENCES public.staff(staff_id);
-- Table food_service_student_accounts
ALTER TABLE public.food_service_student_accounts ADD CONSTRAINT food_service_student_accounts_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.students(student_id);
-- Table food_service_transactions
ALTER TABLE public.food_service_transactions ADD CONSTRAINT food_service_transactions_school_id_fkey FOREIGN KEY (school_id) REFERENCES public.schools(school_id);
ALTER TABLE public.food_service_transactions ADD CONSTRAINT food_service_transactions_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.students(student_id);
-- Table gradebook_assignment_types
ALTER TABLE public.gradebook_assignment_types ADD CONSTRAINT gradebook_assignment_types_course_id_fkey FOREIGN KEY (course_id) REFERENCES public.courses(course_id);
ALTER TABLE public.gradebook_assignment_types ADD CONSTRAINT gradebook_assignment_types_staff_id_fkey FOREIGN KEY (staff_id) REFERENCES public.staff(staff_id);
-- Table gradebook_assignments
ALTER TABLE public.gradebook_assignments ADD CONSTRAINT gradebook_assignments_course_id_fkey FOREIGN KEY (course_id) REFERENCES public.courses(course_id);
ALTER TABLE public.gradebook_assignments ADD CONSTRAINT gradebook_assignments_course_period_id_fkey FOREIGN KEY (course_period_id) REFERENCES public.course_periods(course_period_id);
ALTER TABLE public.gradebook_assignments ADD CONSTRAINT gradebook_assignments_marking_period_id_fkey FOREIGN KEY (marking_period_id) REFERENCES public.school_marking_periods(marking_period_id);
ALTER TABLE public.gradebook_assignments ADD CONSTRAINT gradebook_assignments_staff_id_fkey FOREIGN KEY (staff_id) REFERENCES public.staff(staff_id);
-- Table gradebook_grades
ALTER TABLE public.gradebook_grades ADD CONSTRAINT gradebook_grades_course_period_id_fkey FOREIGN KEY (course_period_id) REFERENCES public.course_periods(course_period_id);
ALTER TABLE public.gradebook_grades ADD CONSTRAINT gradebook_grades_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.students(student_id);
-- Table grades_completed
ALTER TABLE public.grades_completed ADD CONSTRAINT grades_completed_course_period_id_fkey FOREIGN KEY (course_period_id) REFERENCES public.course_periods(course_period_id);
ALTER TABLE public.grades_completed ADD CONSTRAINT grades_completed_marking_period_id_fkey FOREIGN KEY (marking_period_id) REFERENCES public.school_marking_periods(marking_period_id);
ALTER TABLE public.grades_completed ADD CONSTRAINT grades_completed_staff_id_fkey FOREIGN KEY (staff_id) REFERENCES public.staff(staff_id);
-- Table lunch_period
ALTER TABLE public.lunch_period ADD CONSTRAINT lunch_period_course_period_id_fkey FOREIGN KEY (course_period_id) REFERENCES public.course_periods(course_period_id);
ALTER TABLE public.lunch_period ADD CONSTRAINT lunch_period_marking_period_id_fkey FOREIGN KEY (marking_period_id) REFERENCES public.school_marking_periods(marking_period_id);
ALTER TABLE public.lunch_period ADD CONSTRAINT lunch_period_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.students(student_id);
-- Table messages
ALTER TABLE public.messages ADD CONSTRAINT messages_school_id_fkey FOREIGN KEY (school_id) REFERENCES public.schools(school_id);
-- Table portal_notes
ALTER TABLE public.portal_notes ADD CONSTRAINT portal_notes_school_id_fkey FOREIGN KEY (school_id) REFERENCES public.schools(school_id);
-- Table portal_polls
ALTER TABLE public.portal_polls ADD CONSTRAINT portal_polls_school_id_fkey FOREIGN KEY (school_id) REFERENCES public.schools(school_id);
-- Table program_config
ALTER TABLE public.program_config ADD CONSTRAINT program_config_school_id_fkey FOREIGN KEY (school_id) REFERENCES public.schools(school_id);
-- Table report_card_comment_categories
ALTER TABLE public.report_card_comment_categories ADD CONSTRAINT report_card_comment_categories_course_id_fkey FOREIGN KEY (course_id) REFERENCES public.courses(course_id);
ALTER TABLE public.report_card_comment_categories ADD CONSTRAINT report_card_comment_categories_school_id_fkey FOREIGN KEY (school_id) REFERENCES public.schools(school_id);
-- Table report_card_comments
ALTER TABLE public.report_card_comments ADD CONSTRAINT report_card_comments_school_id_fkey FOREIGN KEY (school_id) REFERENCES public.schools(school_id);
-- Table report_card_grade_scales
ALTER TABLE public.report_card_grade_scales ADD CONSTRAINT report_card_grade_scales_school_id_fkey FOREIGN KEY (school_id) REFERENCES public.schools(school_id);
-- Table report_card_grades
ALTER TABLE public.report_card_grades ADD CONSTRAINT report_card_grades_school_id_fkey FOREIGN KEY (school_id) REFERENCES public.schools(school_id);
-- Table schedule
ALTER TABLE public.schedule ADD CONSTRAINT schedule_course_id_fkey FOREIGN KEY (course_id) REFERENCES public.courses(course_id);
ALTER TABLE public.schedule ADD CONSTRAINT schedule_course_period_id_fkey FOREIGN KEY (course_period_id) REFERENCES public.course_periods(course_period_id);
ALTER TABLE public.schedule ADD CONSTRAINT schedule_marking_period_id_fkey FOREIGN KEY (marking_period_id) REFERENCES public.school_marking_periods(marking_period_id);
ALTER TABLE public.schedule ADD CONSTRAINT schedule_school_id_fkey FOREIGN KEY (school_id) REFERENCES public.schools(school_id);
ALTER TABLE public.schedule ADD CONSTRAINT schedule_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.students(student_id);
-- Table schedule_requests
ALTER TABLE public.schedule_requests ADD CONSTRAINT schedule_requests_course_id_fkey FOREIGN KEY (course_id) REFERENCES public.courses(course_id);
ALTER TABLE public.schedule_requests ADD CONSTRAINT schedule_requests_marking_period_id_fkey FOREIGN KEY (marking_period_id) REFERENCES public.school_marking_periods(marking_period_id);
ALTER TABLE public.schedule_requests ADD CONSTRAINT schedule_requests_school_id_fkey FOREIGN KEY (school_id) REFERENCES public.schools(school_id);
ALTER TABLE public.schedule_requests ADD CONSTRAINT schedule_requests_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.students(student_id);
-- Table school_marking_periods
ALTER TABLE public.school_marking_periods ADD CONSTRAINT school_marking_periods_school_id_fkey FOREIGN KEY (school_id) REFERENCES public.schools(school_id);
-- Table school_periods
ALTER TABLE public.school_periods ADD CONSTRAINT school_periods_school_id_fkey FOREIGN KEY (school_id) REFERENCES public.schools(school_id);
-- Table staff_exceptions
ALTER TABLE public.staff_exceptions ADD CONSTRAINT staff_exceptions_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.staff(staff_id);
-- Table student_assignments
ALTER TABLE public.student_assignments ADD CONSTRAINT student_assignments_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.students(student_id);
-- Table student_eligibility_activities
ALTER TABLE public.student_eligibility_activities ADD CONSTRAINT student_eligibility_activities_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.students(student_id);
-- Table student_enrollment
ALTER TABLE public.student_enrollment ADD CONSTRAINT student_enrollment_school_id_fkey FOREIGN KEY (school_id) REFERENCES public.schools(school_id);
ALTER TABLE public.student_enrollment ADD CONSTRAINT student_enrollment_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.students(student_id);
ALTER TABLE public.student_enrollment ADD CONSTRAINT student_enrollment_grade_id_fkey FOREIGN KEY (grade_id) REFERENCES public.school_gradelevels(gradelevel_id);
ALTER TABLE public.student_enrollment ADD CONSTRAINT student_enrollment_course_period_id_fkey FOREIGN KEY (course_period_id) REFERENCES public.course_periods(course_period_id);
ALTER TABLE public.student_enrollment ADD CONSTRAINT student_enrollment_second_course_period_id_fkey FOREIGN KEY (second_course_period_id) REFERENCES public.course_periods(course_period_id);
ALTER TABLE public.student_enrollment ADD CONSTRAINT student_enrollment_second_grade_id_fkey FOREIGN KEY (second_grade_id) REFERENCES public.school_gradelevels(gradelevel_id);
-- Table student_medical_alerts
ALTER TABLE public.student_medical_alerts ADD CONSTRAINT student_medical_alerts_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.students(student_id);
-- Table student_medical
ALTER TABLE public.student_medical ADD CONSTRAINT student_medical_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.students(student_id);
-- Table student_medical_visits
ALTER TABLE public.student_medical_visits ADD CONSTRAINT student_medical_visits_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.students(student_id);
-- Table student_mp_comments
ALTER TABLE public.student_mp_comments ADD CONSTRAINT student_mp_comments_marking_period_id_fkey FOREIGN KEY (marking_period_id) REFERENCES public.school_marking_periods(marking_period_id);
ALTER TABLE public.student_mp_comments ADD CONSTRAINT student_mp_comments_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.students(student_id);
-- Table student_mp_stats
ALTER TABLE public.student_mp_stats ADD CONSTRAINT student_mp_stats_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.students(student_id);
-- Table student_report_card_comments
ALTER TABLE public.student_report_card_comments ADD CONSTRAINT student_report_card_comments_course_period_id_fkey FOREIGN KEY (course_period_id) REFERENCES public.course_periods(course_period_id);
ALTER TABLE public.student_report_card_comments ADD CONSTRAINT student_report_card_comments_marking_period_id_fkey FOREIGN KEY (marking_period_id) REFERENCES public.school_marking_periods(marking_period_id);
ALTER TABLE public.student_report_card_comments ADD CONSTRAINT student_report_card_comments_school_id_fkey FOREIGN KEY (school_id) REFERENCES public.schools(school_id);
ALTER TABLE public.student_report_card_comments ADD CONSTRAINT student_report_card_comments_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.students(student_id);
-- Table student_report_card_grades
ALTER TABLE public.student_report_card_grades ADD CONSTRAINT student_report_card_grades_course_period_id_fkey FOREIGN KEY (course_period_id) REFERENCES public.course_periods(course_period_id);
ALTER TABLE public.student_report_card_grades ADD CONSTRAINT student_report_card_grades_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.students(student_id);
-- Table students_join_address
ALTER TABLE public.students_join_address ADD CONSTRAINT students_join_address_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.students(student_id);
-- Table students_join_people
ALTER TABLE public.students_join_people ADD CONSTRAINT students_join_people_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.students(student_id);
-- Table students_join_users
ALTER TABLE public.students_join_users ADD CONSTRAINT students_join_users_staff_id_fkey FOREIGN KEY (staff_id) REFERENCES public.staff(staff_id);
ALTER TABLE public.students_join_users ADD CONSTRAINT students_join_users_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.students(student_id);
-- Table wx_course_periods_gradelevels
ALTER TABLE public.wx_course_periods_gradelevels ADD CONSTRAINT wx_course_periods_gradelevels_course_periods_id_fkey FOREIGN KEY (course_periods_id) REFERENCES public.course_periods(course_period_id);
ALTER TABLE public.wx_course_periods_gradelevels ADD CONSTRAINT wx_course_periods_gradelevels_school_gradelevels_id_fkey FOREIGN KEY (school_gradelevels_id) REFERENCES public.school_gradelevels(gradelevel_id);
-- Table wx_course_periods_subjects
ALTER TABLE public.wx_course_periods_subjects ADD CONSTRAINT wx_course_periods_subjects_course_periods_id_fkey FOREIGN KEY (course_periods_id) REFERENCES public.course_periods(course_period_id);
ALTER TABLE public.wx_course_periods_subjects ADD CONSTRAINT wx_course_periods_subjects_course_subjects_id_fkey FOREIGN KEY (course_subjects_id) REFERENCES public.course_subjects(subject_id);
-- Table wx_course_subjects_gradelevels
ALTER TABLE public.wx_course_subjects_gradelevels ADD CONSTRAINT wx_course_subjects_gradelevels_course_subjects_id_fkey FOREIGN KEY (course_subjects_id) REFERENCES public.course_subjects(subject_id);
ALTER TABLE public.wx_course_subjects_gradelevels ADD CONSTRAINT wx_course_subjects_gradelevels_school_gradelevels_id_fkey FOREIGN KEY (school_gradelevels_id) REFERENCES public.school_gradelevels(gradelevel_id);
-- Table wx_family_members
ALTER TABLE public.wx_family_members ADD CONSTRAINT wx_family_members_family_id_fkey FOREIGN KEY (family_id) REFERENCES public.wx_families(wx_family_id);
ALTER TABLE public.wx_family_members ADD CONSTRAINT wx_family_members_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.students(student_id);
-- Table wx_moyennes_finales_students
ALTER TABLE public.wx_moyennes_finales_students ADD CONSTRAINT wx_moyennes_finales_students_student_enrollment_id_fkey FOREIGN KEY (student_enrollment_id) REFERENCES public.student_enrollment(enrollment_id);
-- Table wx_moyennes_validation_gradelevel
ALTER TABLE public.wx_moyennes_validation_gradelevel ADD CONSTRAINT wx_moyennes_validation_gradelevel_school_gradelevels_id_fkey FOREIGN KEY (school_gradelevels_id) REFERENCES public.school_gradelevels(gradelevel_id);
-- Table wx_notes_student_details
ALTER TABLE public.wx_notes_student_details ADD CONSTRAINT wx_notes_student_details_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.students(student_id);
ALTER TABLE public.wx_notes_student_details ADD CONSTRAINT wx_notes_student_details_wx_course_periods_subjects_id_fkey FOREIGN KEY (wx_course_periods_subjects_id) REFERENCES public.wx_course_periods_subjects(wx_course_periods_subjects_id);
-- Table wx_reduction_members
ALTER TABLE public.wx_reduction_members ADD CONSTRAINT wx_reduction_members_reduction_id_fkey FOREIGN KEY (reduction_id) REFERENCES public.wx_reduction_eleve(wx_reduction_eleve_id);
ALTER TABLE public.wx_reduction_members ADD CONSTRAINT wx_reduction_members_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.students(student_id);
-- Table wx_teacher_attendance
ALTER TABLE public.wx_teacher_attendance ADD CONSTRAINT wx_teacher_attendance_staff_id_fkey FOREIGN KEY (staff_id) REFERENCES public.staff(staff_id);
-- Table wx_ues_subjects
ALTER TABLE public.wx_ues_subjects ADD CONSTRAINT wx_ues_subjects_subject_id_fkey FOREIGN KEY (subject_id) REFERENCES public.course_subjects(subject_id);
ALTER TABLE public.wx_ues_subjects ADD CONSTRAINT wx_ues_subjects_ue_id_fkey FOREIGN KEY (ue_id) REFERENCES public.wx_ues(ue_id);

