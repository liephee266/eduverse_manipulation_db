DROP VIEW IF EXISTS public.marking_periods CASCADE; -- Vue: marking_periods étape 4.1

CREATE VIEW public.marking_periods AS -- Vue: marking_periods étape 4.2
 SELECT school_marking_periods.marking_period_id,
    'Rosario'::text AS mp_source,
    school_marking_periods.syear,
    school_marking_periods.school_id,
        CASE
            WHEN ((school_marking_periods.mp)::text = 'FY'::text) THEN 'year'::text
            WHEN ((school_marking_periods.mp)::text = 'SEM'::text) THEN 'semester'::text
            WHEN ((school_marking_periods.mp)::text = 'QTR'::text) THEN 'quarter'::text
            ELSE NULL::text
        END AS mp_type,
    school_marking_periods.title,
    school_marking_periods.short_name,
    school_marking_periods.sort_order,
        CASE
            WHEN ((school_marking_periods.parent_id)::uuid IS NOT NULL) THEN (school_marking_periods.parent_id)::text
            ELSE ('-1'::integer)::text
        END AS parent_id,
        CASE
            WHEN ((( SELECT smp.parent_id
               FROM public.school_marking_periods smp
              WHERE (smp.marking_period_id = school_marking_periods.parent_id)))::uuid IS NOT NULL) THEN (( SELECT smp.parent_id
               FROM public.school_marking_periods smp
              WHERE (smp.marking_period_id = school_marking_periods.parent_id)))::text
            ELSE ('-1'::integer)::text
        END AS grandparent_id,
    school_marking_periods.start_date,
    school_marking_periods.end_date,
    school_marking_periods.post_start_date,
    school_marking_periods.post_end_date,
    school_marking_periods.does_grades,
    school_marking_periods.does_comments
   FROM public.school_marking_periods
UNION
 SELECT history_marking_periods.history_marking_period_id,
    'History'::text AS mp_source,
    history_marking_periods.syear,
    history_marking_periods.school_id,
    history_marking_periods.mp_type,
    history_marking_periods.name AS title,
    history_marking_periods.short_name,
    NULL::numeric AS sort_order,
    history_marking_periods.parent_id::text, -- Ici, parent_id est converti en text
    '-1'::text AS grandparent_id, -- Correction : '-1' est traité comme text
    NULL::date AS start_date,
    history_marking_periods.post_end_date AS end_date,
    NULL::date AS post_start_date,
    history_marking_periods.post_end_date,
    'Y'::character varying AS does_grades,
    NULL::character varying AS does_comments
   FROM public.history_marking_periods;

-- Message de confirmation pour cette étape (vue créée)
DO $$
BEGIN
    RAISE NOTICE '✅ Vue marking_periods recréée avec succès.';
END $$;


-- Vue: course_details
CREATE OR REPLACE VIEW public.course_details AS -- Vue: course_details étape 4.3
 SELECT cp.school_id,
    cp.syear,
    cp.marking_period_id,
    c.subject_id,
    cp.course_id,
    cp.course_period_id,
    cp.teacher_id,
    c.title AS course_title,
    cp.title AS cp_title,
    cp.grade_scale_id,
    cp.mp,
    cp.credits
   FROM public.course_periods cp,
    public.courses c
  WHERE (cp.course_id = c.course_id);

-- Vue: enroll_grade
CREATE OR REPLACE VIEW public.enroll_grade AS -- Vue: enroll_grade étape 4.4
 SELECT e.enrollment_id as id,
    e.syear,
    e.school_id,
    e.student_id,
    e.start_date,
    e.end_date,
    sg.short_name,
    sg.title
   FROM public.student_enrollment e,
    public.school_gradelevels sg
  WHERE (e.grade_id = sg.gradelevel_id);

-- Vue: dual
CREATE OR REPLACE VIEW public.dual AS -- Vue: dual étape 4.5
 SELECT 'X'::text AS dummy;

-- Vue: transcript_grades (adaptée pour UUID)
CREATE OR REPLACE VIEW public.transcript_grades AS -- Vue: transcript_grades étape 4.6
 SELECT mp.syear,
    mp.school_id,
    mp.marking_period_id,
    mp.mp_type,
    mp.short_name,
    mp.parent_id,
    mp.grandparent_id,
    ( SELECT mp2.end_date
           FROM (public.student_report_card_grades
             JOIN public.marking_periods mp2 ON ((mp2.marking_period_id = student_report_card_grades.marking_period_id)))
          WHERE ((student_report_card_grades.student_id = sms.student_id) AND ((student_report_card_grades.marking_period_id)::uuid = mp.parent_id::uuid OR (student_report_card_grades.marking_period_id)::uuid = mp.grandparent_id::uuid) AND (student_report_card_grades.course_title = srcg.course_title))
          ORDER BY mp2.end_date
         LIMIT 1) AS parent_end_date,
    mp.end_date,
    sms.student_id,
    (sms.cum_weighted_factor * COALESCE(schools.reporting_gp_scale, ( SELECT schools_1.reporting_gp_scale
           FROM public.schools schools_1
          WHERE (mp.school_id = schools_1.school_id)
          ORDER BY schools_1.syear
         LIMIT 1))) AS cum_weighted_gpa,
    (sms.cum_unweighted_factor * schools.reporting_gp_scale) AS cum_unweighted_gpa,
    sms.cum_rank,
    sms.mp_rank,
    sms.class_size,
    ((sms.sum_weighted_factors / (sms.count_weighted_factors)::numeric) * schools.reporting_gp_scale) AS weighted_gpa,
    ((sms.sum_unweighted_factors / (sms.count_unweighted_factors)::numeric) * schools.reporting_gp_scale) AS unweighted_gpa,
    sms.grade_level_short,
    srcg.comment,
    srcg.grade_percent,
    srcg.grade_letter,
    srcg.weighted_gp,
    srcg.unweighted_gp,
    srcg.gp_scale,
    srcg.credit_attempted,
    srcg.credit_earned,
    srcg.course_title,
    srcg.school AS school_name,
    schools.reporting_gp_scale AS school_scale,
    ((sms.cr_weighted_factors / (sms.count_cr_factors)::numeric) * schools.reporting_gp_scale) AS cr_weighted_gpa,
    ((sms.cr_unweighted_factors / (sms.count_cr_factors)::numeric) * schools.reporting_gp_scale) AS cr_unweighted_gpa,
    (sms.cum_cr_weighted_factor * schools.reporting_gp_scale) AS cum_cr_weighted_gpa,
    (sms.cum_cr_unweighted_factor * schools.reporting_gp_scale) AS cum_cr_unweighted_gpa,
    srcg.class_rank,
    sms.comments,
    srcg.credit_hours
   FROM (((public.marking_periods mp
     JOIN public.student_report_card_grades srcg ON ((mp.marking_period_id = srcg.marking_period_id)))
     JOIN public.student_mp_stats sms ON (((sms.marking_period_id = mp.marking_period_id) AND (sms.student_id = srcg.student_id))))
     LEFT JOIN public.schools ON ((((mp.school_id = schools.school_id) AND ((mp.mp_source <> 'History'::text) AND (mp.syear = schools.syear))) OR ((mp.mp_source = 'History'::text) AND (mp.syear = ( SELECT schools_1.syear
           FROM public.schools schools_1
          WHERE (mp.school_id = schools_1.school_id)
          ORDER BY schools_1.syear
         LIMIT 1))))))
  ORDER BY srcg.course_period_id;

-- Message de confirmation pour cette étape (vues créées)
DO $$
BEGIN
    RAISE NOTICE '✅ Étape 4 (Recréation des Vues) terminée avec succès.';
END $$;