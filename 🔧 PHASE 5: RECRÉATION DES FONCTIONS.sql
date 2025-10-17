-- 🔧 PHASE 5: RECRÉATION DES FONCTIONS
-- =============================================

CREATE FUNCTION public.calc_cum_cr_gpa(mp_id uuid, s_id uuid) RETURNS integer
    LANGUAGE plpgsql
    AS $$
BEGIN
    UPDATE student_mp_stats
    SET cum_cr_weighted_factor = cr_weighted_factors/cr_credits,
        cum_cr_unweighted_factor = cr_unweighted_factors/cr_credits
    WHERE student_mp_stats.student_id = s_id and student_mp_stats.marking_period_id = mp_id;
    RETURN 1;
END;
$$;

CREATE FUNCTION public.calc_cum_gpa(mp_id uuid, s_id uuid) RETURNS integer
    LANGUAGE plpgsql
    AS $$
BEGIN
    UPDATE student_mp_stats
    SET cum_weighted_factor = sum_weighted_factors/gp_credits,
        cum_unweighted_factor = sum_unweighted_factors/gp_credits
    WHERE student_mp_stats.student_id = s_id and student_mp_stats.marking_period_id = mp_id;
    RETURN 1;
END;
$$;

CREATE FUNCTION public.calc_gpa_mp(s_id uuid, mp_id uuid) RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE
    oldrec student_mp_stats%ROWTYPE;
BEGIN
  SELECT * INTO oldrec FROM student_mp_stats WHERE student_id = s_id and marking_period_id = mp_id;
  IF FOUND THEN
    UPDATE student_mp_stats SET
        sum_weighted_factors = rcg.sum_weighted_factors,
        sum_unweighted_factors = rcg.sum_unweighted_factors,
        cr_weighted_factors = rcg.cr_weighted,
        cr_unweighted_factors = rcg.cr_unweighted,
        gp_credits = rcg.gp_credits,
        cr_credits = rcg.cr_credits
    FROM (
    select
        sum(weighted_gp*credit_attempted/gp_scale) as sum_weighted_factors,
        sum(unweighted_gp*credit_attempted/gp_scale) as sum_unweighted_factors,
        sum(credit_attempted) as gp_credits,
        sum( case when class_rank = 'Y' THEN weighted_gp*credit_attempted/gp_scale END ) as cr_weighted,
        sum( case when class_rank = 'Y' THEN unweighted_gp*credit_attempted/gp_scale END ) as cr_unweighted,
        sum( case when class_rank = 'Y' THEN credit_attempted END) as cr_credits
    from student_report_card_grades where student_id = s_id
        and marking_period_id = mp_id
        and not gp_scale = 0 group by student_id, marking_period_id
    ) as rcg
    WHERE student_id = s_id and marking_period_id = mp_id;
    RETURN 1;
  ELSE
    INSERT INTO student_mp_stats (student_id, marking_period_id, sum_weighted_factors, sum_unweighted_factors, grade_level_short, cr_weighted_factors, cr_unweighted_factors, gp_credits, cr_credits)
        select
            srcg.student_id,
            srcg.marking_period_id,
            sum(weighted_gp*credit_attempted/gp_scale) as sum_weighted_factors,
            sum(unweighted_gp*credit_attempted/gp_scale) as sum_unweighted_factors,
            (select eg.short_name
                from enroll_grade eg, marking_periods mp
                where eg.student_id = s_id
                and eg.syear = mp.syear
                and eg.school_id = mp.school_id
                and eg.start_date <= mp.end_date
                and mp.marking_period_id = mp_id
                order by eg.start_date desc
                limit 1) as short_name,
            sum( case when class_rank = 'Y' THEN weighted_gp*credit_attempted/gp_scale END ) as cr_weighted,
            sum( case when class_rank = 'Y' THEN unweighted_gp*credit_attempted/gp_scale END ) as cr_unweighted,
            sum(credit_attempted) as gp_credits,
            sum(case when class_rank = 'Y' THEN credit_attempted END) as cr_credits
        from student_report_card_grades srcg
        where srcg.student_id = s_id and srcg.marking_period_id = mp_id and not srcg.gp_scale = 0
        group by srcg.student_id, srcg.marking_period_id, short_name;
  END IF;
  RETURN 0;
END;
$$;

CREATE FUNCTION public.credit(cp_id uuid, mp_id uuid) RETURNS numeric
    LANGUAGE plpgsql
    AS $$
DECLARE
    course_detail RECORD;
    mp_detail RECORD;
    val RECORD;
BEGIN
select * into course_detail from course_periods where course_period_id = cp_id;
select * into mp_detail from school_marking_periods where marking_period_id = mp_id;
IF course_detail.marking_period_id = mp_detail.marking_period_id THEN
    return course_detail.credits;
ELSIF course_detail.mp = 'FY' AND mp_detail.mp = 'SEM' THEN
    select into val count(*) as mp_count from school_marking_periods where parent_id = course_detail.marking_period_id group by parent_id;
ELSIF course_detail.mp = 'FY' and mp_detail.mp = 'QTR' THEN
    select into val count(*) as mp_count from school_marking_periods where parent_id in (select marking_period_id from school_marking_periods where parent_id = course_detail.marking_period_id) group by parent_id;
ELSIF course_detail.mp = 'SEM' and mp_detail.mp = 'QTR' THEN
    select into val count(*) as mp_count from school_marking_periods where parent_id = course_detail.marking_period_id group by parent_id;
ELSE
    return course_detail.credits;
END IF;
IF val.mp_count > 0 THEN
    return course_detail.credits/val.mp_count;
ELSE
    return course_detail.credits;
END IF;
END;
$$;

CREATE FUNCTION public.immutable_unaccent(text) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $_$
    SELECT unaccent($1)
$_$;

CREATE FUNCTION public.set_class_rank_mp(mp_id uuid) RETURNS integer
    LANGUAGE plpgsql
    AS $$
BEGIN
update student_mp_stats
set cum_rank = class_rank.class_rank, class_size = class_rank.class_size
from (select mp.marking_period_id, sgm.student_id,
    (select count(*)+1
        from student_mp_stats sgm3
        where sgm3.cum_cr_weighted_factor > sgm.cum_cr_weighted_factor
        and sgm3.marking_period_id = mp.marking_period_id
        and sgm3.student_id in (select distinct sgm2.student_id
            from student_mp_stats sgm2, student_enrollment se2
            where sgm2.student_id = se2.student_id
            and sgm2.marking_period_id = mp.marking_period_id
            and se2.grade_id = se.grade_id)) as class_rank,
    (select count(*)
        from student_mp_stats sgm4
        where sgm4.marking_period_id = mp.marking_period_id
        and sgm4.student_id in (select distinct sgm5.student_id
            from student_mp_stats sgm5, student_enrollment se3
            where sgm5.student_id = se3.student_id
            and sgm5.marking_period_id = mp.marking_period_id
            and se3.grade_id = se.grade_id)) as class_size
    from student_enrollment se, student_mp_stats sgm, school_marking_periods mp
    where se.student_id = sgm.student_id
    and sgm.marking_period_id = mp.marking_period_id
    and mp.marking_period_id = mp_id
    and se.syear = mp.syear
    and not sgm.cum_cr_weighted_factor is null) as class_rank
where student_mp_stats.marking_period_id = class_rank.marking_period_id
and student_mp_stats.student_id = class_rank.student_id;
RETURN 1;
END;
$$;

CREATE FUNCTION public.set_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF row(NEW.*) IS DISTINCT FROM row(OLD.*) THEN
    NEW.updated_at := CURRENT_TIMESTAMP;
    RETURN NEW;
  ELSE
    RETURN OLD;
  END IF;
END;
$$;

CREATE FUNCTION public.t_update_mp_stats() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF tg_op = 'DELETE' THEN
    PERFORM calc_gpa_mp(OLD.student_id, OLD.marking_period_id);
    PERFORM calc_cum_gpa(OLD.marking_period_id, OLD.student_id);
    PERFORM calc_cum_cr_gpa(OLD.marking_period_id, OLD.student_id);
  ELSE
    PERFORM calc_gpa_mp(NEW.student_id, NEW.marking_period_id);
    PERFORM calc_cum_gpa(NEW.marking_period_id, NEW.student_id);
    PERFORM calc_cum_cr_gpa(NEW.marking_period_id, NEW.student_id);
  END IF;
  RETURN NULL;
END;
$$;

-- Message de confirmation pour cette étape
DO $$
BEGIN
    RAISE NOTICE '✅ Étape 5 (Recréation des Fonctions) terminée avec succès.';
END $$;
