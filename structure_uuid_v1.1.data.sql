--
-- PostgreSQL database dump
--

-- Dumped from database version 15.8 (Debian 15.8-1.pgdg120+1)
-- Dumped by pg_dump version 15.8 (Debian 15.8-1.pgdg120+1)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: pg_trgm; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pg_trgm WITH SCHEMA public;


--
-- Name: EXTENSION pg_trgm; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION pg_trgm IS 'text similarity measurement and index searching based on trigrams';


--
-- Name: unaccent; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS unaccent WITH SCHEMA public;


--
-- Name: EXTENSION unaccent; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION unaccent IS 'text search dictionary that removes accents';


--
-- Name: uuid-ossp; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA public;


--
-- Name: EXTENSION "uuid-ossp"; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION "uuid-ossp" IS 'generate universally unique identifiers (UUIDs)';


--
-- Name: uuid_type; Type: DOMAIN; Schema: public; Owner: wxu_school
--

CREATE DOMAIN public.uuid_type AS uuid NOT NULL DEFAULT public.uuid_generate_v4();


ALTER DOMAIN public.uuid_type OWNER TO wxu_school;

--
-- Name: calc_cum_cr_gpa(uuid, uuid); Type: FUNCTION; Schema: public; Owner: wxu_school
--

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


ALTER FUNCTION public.calc_cum_cr_gpa(mp_id uuid, s_id uuid) OWNER TO wxu_school;

--
-- Name: calc_cum_gpa(uuid, uuid); Type: FUNCTION; Schema: public; Owner: wxu_school
--

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


ALTER FUNCTION public.calc_cum_gpa(mp_id uuid, s_id uuid) OWNER TO wxu_school;

--
-- Name: calc_gpa_mp(uuid, uuid); Type: FUNCTION; Schema: public; Owner: wxu_school
--

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


ALTER FUNCTION public.calc_gpa_mp(s_id uuid, mp_id uuid) OWNER TO wxu_school;

--
-- Name: credit(uuid, uuid); Type: FUNCTION; Schema: public; Owner: wxu_school
--

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


ALTER FUNCTION public.credit(cp_id uuid, mp_id uuid) OWNER TO wxu_school;

--
-- Name: immutable_unaccent(text); Type: FUNCTION; Schema: public; Owner: wxu_school
--

CREATE FUNCTION public.immutable_unaccent(text) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $_$
    SELECT unaccent($1)
$_$;


ALTER FUNCTION public.immutable_unaccent(text) OWNER TO wxu_school;

--
-- Name: set_class_rank_mp(uuid); Type: FUNCTION; Schema: public; Owner: wxu_school
--

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


ALTER FUNCTION public.set_class_rank_mp(mp_id uuid) OWNER TO wxu_school;

--
-- Name: set_updated_at(); Type: FUNCTION; Schema: public; Owner: wxu_school
--

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


ALTER FUNCTION public.set_updated_at() OWNER TO wxu_school;

--
-- Name: t_update_mp_stats(); Type: FUNCTION; Schema: public; Owner: wxu_school
--

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


ALTER FUNCTION public.t_update_mp_stats() OWNER TO wxu_school;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: access_log; Type: TABLE; Schema: public; Owner: wxu_school
--

CREATE TABLE public.access_log (
    access_log_id public.uuid_type NOT NULL,
    syear numeric(4,0) NOT NULL,
    username character varying(100),
    profile character varying(30),
    login_time timestamp without time zone,
    ip_address character varying(50),
    user_agent text,
    status character varying(50),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.access_log OWNER TO wxu_school;

--
-- Name: accounting_categories; Type: TABLE; Schema: public; Owner: wxu_school
--

CREATE TABLE public.accounting_categories (
    accounting_category_id public.uuid_type NOT NULL,
    school_id public.uuid_type NOT NULL,
    title text NOT NULL,
    short_name character varying(10),
    type character varying(100),
    sort_order numeric,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.accounting_categories OWNER TO wxu_school;

--
-- Name: accounting_incomes; Type: TABLE; Schema: public; Owner: wxu_school
--

CREATE TABLE public.accounting_incomes (
    accounting_income_id public.uuid_type NOT NULL,
    assigned_date date,
    comments text,
    title text NOT NULL,
    category_id public.uuid_type,
    amount numeric(14,2) NOT NULL,
    file_attached text,
    school_id public.uuid_type NOT NULL,
    syear numeric(4,0) NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.accounting_incomes OWNER TO wxu_school;

--
-- Name: accounting_payments; Type: TABLE; Schema: public; Owner: wxu_school
--

CREATE TABLE public.accounting_payments (
    accounting_payment_id public.uuid_type NOT NULL,
    syear numeric(4,0) NOT NULL,
    school_id public.uuid_type NOT NULL,
    staff_id public.uuid_type,
    title text,
    category_id public.uuid_type,
    amount numeric(14,2) NOT NULL,
    payment_date date,
    comments text,
    file_attached text,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.accounting_payments OWNER TO wxu_school;

--
-- Name: accounting_salaries; Type: TABLE; Schema: public; Owner: wxu_school
--

CREATE TABLE public.accounting_salaries (
    accounting_salary_id public.uuid_type NOT NULL,
    staff_id public.uuid_type NOT NULL,
    assigned_date date,
    due_date date,
    comments text,
    title text NOT NULL,
    amount numeric(14,2) NOT NULL,
    file_attached text,
    school_id public.uuid_type NOT NULL,
    syear numeric(4,0) NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.accounting_salaries OWNER TO wxu_school;

--
-- Name: address; Type: TABLE; Schema: public; Owner: wxu_school
--

CREATE TABLE public.address (
    address_id public.uuid_type NOT NULL,
    house_no numeric(5,0),
    direction character varying(2),
    street character varying(30),
    apt character varying(5),
    zipcode character varying(10),
    city text,
    state character varying(50),
    mail_street character varying(30),
    mail_city text,
    mail_state character varying(50),
    mail_zipcode character varying(10),
    address text,
    mail_address text,
    phone character varying(30),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.address OWNER TO wxu_school;

--
-- Name: address_field_categories; Type: TABLE; Schema: public; Owner: wxu_school
--

CREATE TABLE public.address_field_categories (
    address_field_category_id public.uuid_type NOT NULL,
    title text NOT NULL,
    sort_order numeric,
    residence character(1),
    mailing character(1),
    bus character(1),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.address_field_categories OWNER TO wxu_school;

--
-- Name: address_fields; Type: TABLE; Schema: public; Owner: wxu_school
--

CREATE TABLE public.address_fields (
    address_field_id public.uuid_type NOT NULL,
    type character varying(10) NOT NULL,
    title text NOT NULL,
    sort_order numeric,
    select_options text,
    category_id public.uuid_type,
    required character varying(1),
    default_selection text,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.address_fields OWNER TO wxu_school;

--
-- Name: attendance_calendar; Type: TABLE; Schema: public; Owner: wxu_school
--

CREATE TABLE public.attendance_calendar (
    attendance_calendar_id public.uuid_type NOT NULL,
    syear numeric(4,0) NOT NULL,
    school_id public.uuid_type NOT NULL,
    school_date date NOT NULL,
    minutes integer,
    block character varying(10),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone,
    calendar_id public.uuid_type
);


ALTER TABLE public.attendance_calendar OWNER TO wxu_school;

--
-- Name: attendance_calendars; Type: TABLE; Schema: public; Owner: wxu_school
--

CREATE TABLE public.attendance_calendars (
    calendar_id public.uuid_type NOT NULL,
    school_id public.uuid_type NOT NULL,
    title character varying(100) NOT NULL,
    syear numeric(4,0) NOT NULL,
    default_calendar character varying(1),
    rollover_id public.uuid_type,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.attendance_calendars OWNER TO wxu_school;

--
-- Name: attendance_code_categories; Type: TABLE; Schema: public; Owner: wxu_school
--

CREATE TABLE public.attendance_code_categories (
    attendance_code_category_id public.uuid_type NOT NULL,
    syear numeric(4,0) NOT NULL,
    school_id public.uuid_type NOT NULL,
    title text NOT NULL,
    sort_order numeric,
    rollover_id public.uuid_type,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.attendance_code_categories OWNER TO wxu_school;

--
-- Name: attendance_codes; Type: TABLE; Schema: public; Owner: wxu_school
--

CREATE TABLE public.attendance_codes (
    attendance_code_id public.uuid_type NOT NULL,
    syear numeric(4,0) NOT NULL,
    school_id public.uuid_type NOT NULL,
    title text NOT NULL,
    short_name character varying(10),
    type character varying(10),
    state_code character varying(1),
    default_code character varying(1),
    table_name integer,
    sort_order numeric,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.attendance_codes OWNER TO wxu_school;

--
-- Name: attendance_completed; Type: TABLE; Schema: public; Owner: wxu_school
--

CREATE TABLE public.attendance_completed (
    attendance_completed_id public.uuid_type NOT NULL,
    staff_id public.uuid_type NOT NULL,
    school_date date NOT NULL,
    period_id public.uuid_type NOT NULL,
    table_name integer NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.attendance_completed OWNER TO wxu_school;

--
-- Name: attendance_day; Type: TABLE; Schema: public; Owner: wxu_school
--

CREATE TABLE public.attendance_day (
    attendance_day_id public.uuid_type NOT NULL,
    student_id public.uuid_type NOT NULL,
    school_date date NOT NULL,
    minutes_present integer,
    state_value numeric(2,1),
    syear numeric(4,0),
    marking_period_id public.uuid_type,
    comment text,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.attendance_day OWNER TO wxu_school;

--
-- Name: attendance_period; Type: TABLE; Schema: public; Owner: wxu_school
--

CREATE TABLE public.attendance_period (
    attendance_period_id public.uuid_type NOT NULL,
    student_id public.uuid_type NOT NULL,
    school_date date NOT NULL,
    period_id public.uuid_type,
    attendance_code integer,
    attendance_teacher_code integer,
    attendance_reason character varying(100),
    admin character varying(1),
    course_period_id public.uuid_type,
    marking_period_id public.uuid_type,
    comment character varying(100),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone,
    my_period_id public.uuid_type
);


ALTER TABLE public.attendance_period OWNER TO wxu_school;

--
-- Name: billing_fees; Type: TABLE; Schema: public; Owner: wxu_school
--

CREATE TABLE public.billing_fees (
    billing_fee_id public.uuid_type NOT NULL,
    student_id public.uuid_type NOT NULL,
    assigned_date date,
    due_date date,
    comments text,
    title text,
    amount numeric(14,2) NOT NULL,
    file_attached text,
    school_id public.uuid_type NOT NULL,
    syear numeric(4,0) NOT NULL,
    waived_fee_id public.uuid_type,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone,
    month character varying(5)
);


ALTER TABLE public.billing_fees OWNER TO wxu_school;

--
-- Name: billing_payments; Type: TABLE; Schema: public; Owner: wxu_school
--

CREATE TABLE public.billing_payments (
    billing_payment_id public.uuid_type NOT NULL,
    syear numeric(4,0) NOT NULL,
    school_id public.uuid_type NOT NULL,
    student_id public.uuid_type NOT NULL,
    amount numeric(14,2) NOT NULL,
    payment_date date,
    comments text,
    refunded_payment_id public.uuid_type,
    lunch_payment character varying(1),
    file_attached text,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone,
    month character varying(5),
    intitule_caissier character varying(255),
    imprimer character varying(10)
);


ALTER TABLE public.billing_payments OWNER TO wxu_school;

--
-- Name: bordereaux_details; Type: TABLE; Schema: public; Owner: wxu_school
--

CREATE TABLE public.bordereaux_details (
    id public.uuid_type NOT NULL,
    staff_id public.uuid_type NOT NULL,
    month integer NOT NULL,
    year integer NOT NULL,
    autres_cycles numeric(10,2) DEFAULT 0,
    indemnites_responsabilite numeric(10,2) DEFAULT 0,
    prime_transport numeric(10,2) DEFAULT 0,
    prime_salissure numeric(10,2) DEFAULT 0,
    prime_encouragement numeric(10,2) DEFAULT 0,
    prime_anciennete numeric(10,2) DEFAULT 0,
    enfant_charge numeric(10,2) DEFAULT 0,
    assurances numeric(10,2) DEFAULT 0,
    autres numeric(10,2) DEFAULT 0,
    acomptes numeric(10,2) DEFAULT 0,
    cnss_employeur numeric(10,2) DEFAULT 0,
    cnss_employe numeric(10,2) DEFAULT 0,
    irpp_employe numeric(10,2) DEFAULT 0,
    net_payer numeric(10,2) DEFAULT 0,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.bordereaux_details OWNER TO wxu_school;

--
-- Name: calendar_events; Type: TABLE; Schema: public; Owner: wxu_school
--

CREATE TABLE public.calendar_events (
    calendar_event_id public.uuid_type NOT NULL,
    syear numeric(4,0) NOT NULL,
    school_id public.uuid_type NOT NULL,
    school_date date,
    title character varying(50) NOT NULL,
    description text,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.calendar_events OWNER TO wxu_school;

--
-- Name: config; Type: TABLE; Schema: public; Owner: wxu_school
--

CREATE TABLE public.config (
    config_id public.uuid_type NOT NULL,
    title character varying(100) NOT NULL,
    config_value text,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone,
    school_id public.uuid_type
);


ALTER TABLE public.config OWNER TO wxu_school;

--
-- Name: course_periods; Type: TABLE; Schema: public; Owner: wxu_school
--

CREATE TABLE public.course_periods (
    course_period_id public.uuid_type NOT NULL,
    syear numeric(4,0) NOT NULL,
    school_id public.uuid_type NOT NULL,
    course_id public.uuid_type,
    title text,
    short_name character varying(25) NOT NULL,
    mp character varying(3),
    marking_period_id public.uuid_type,
    teacher_id public.uuid_type,
    secondary_teacher_id public.uuid_type,
    room character varying(10),
    total_seats numeric,
    filled_seats numeric,
    does_attendance text,
    does_honor_roll character varying(1),
    does_class_rank character varying(1),
    gender_restriction character varying(1),
    house_restriction character varying(1),
    availability numeric,
    parent_id public.uuid_type,
    calendar_id integer,
    half_day character varying(1),
    does_breakoff character varying(1),
    rollover_id public.uuid_type,
    grade_scale_id integer,
    credits numeric(6,2),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone,
    echelle_notation integer,
    semester_type character varying(20) DEFAULT 'pair'::character varying,
    frais_classe numeric(10,2),
    total_mentant integer
);


ALTER TABLE public.course_periods OWNER TO wxu_school;

--
-- Name: courses; Type: TABLE; Schema: public; Owner: wxu_school
--

CREATE TABLE public.courses (
    course_id public.uuid_type NOT NULL,
    syear numeric(4,0) NOT NULL,
    subject_id public.uuid_type NOT NULL,
    school_id public.uuid_type NOT NULL,
    title character varying(100) NOT NULL,
    short_name character varying(25),
    rollover_id public.uuid_type,
    credit_hours numeric(6,2),
    description text,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone,
    grade_level uuid
);


ALTER TABLE public.courses OWNER TO wxu_school;

--
-- Name: course_details; Type: VIEW; Schema: public; Owner: wxu_school
--

CREATE VIEW public.course_details AS
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
  WHERE ((cp.course_id)::uuid = (c.course_id)::uuid);


ALTER TABLE public.course_details OWNER TO wxu_school;

--
-- Name: course_period_school_periods; Type: TABLE; Schema: public; Owner: wxu_school
--

CREATE TABLE public.course_period_school_periods (
    course_period_school_periods_id public.uuid_type NOT NULL,
    course_period_id public.uuid_type NOT NULL,
    period_id public.uuid_type NOT NULL,
    days character varying(7),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.course_period_school_periods OWNER TO wxu_school;

--
-- Name: course_subjects; Type: TABLE; Schema: public; Owner: wxu_school
--

CREATE TABLE public.course_subjects (
    subject_id public.uuid_type NOT NULL,
    syear numeric(4,0) NOT NULL,
    school_id public.uuid_type NOT NULL,
    title character varying(100) NOT NULL,
    short_name character varying(25),
    sort_order numeric,
    rollover_id public.uuid_type,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.course_subjects OWNER TO wxu_school;

--
-- Name: custom_fields; Type: TABLE; Schema: public; Owner: wxu_school
--

CREATE TABLE public.custom_fields (
    custom_field_id public.uuid_type NOT NULL,
    type character varying(10) NOT NULL,
    title text NOT NULL,
    sort_order numeric,
    select_options text,
    category_id public.uuid_type,
    required character varying(1),
    default_selection text,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.custom_fields OWNER TO wxu_school;

--
-- Name: discipline_field_usage; Type: TABLE; Schema: public; Owner: wxu_school
--

CREATE TABLE public.discipline_field_usage (
    discipline_field_usage_id public.uuid_type NOT NULL,
    discipline_field_id public.uuid_type NOT NULL,
    syear numeric(4,0) NOT NULL,
    school_id public.uuid_type NOT NULL,
    title text NOT NULL,
    select_options text,
    sort_order numeric,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.discipline_field_usage OWNER TO wxu_school;

--
-- Name: discipline_fields; Type: TABLE; Schema: public; Owner: wxu_school
--

CREATE TABLE public.discipline_fields (
    discipline_field_id public.uuid_type NOT NULL,
    title text NOT NULL,
    short_name character varying(20),
    data_type character varying(30) NOT NULL,
    column_name text NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.discipline_fields OWNER TO wxu_school;

--
-- Name: discipline_referrals; Type: TABLE; Schema: public; Owner: wxu_school
--

CREATE TABLE public.discipline_referrals (
    discipline_referral_id public.uuid_type NOT NULL,
    syear numeric(4,0) NOT NULL,
    student_id public.uuid_type NOT NULL,
    school_id public.uuid_type NOT NULL,
    staff_id public.uuid_type,
    entry_date date,
    referral_date date,
    category_1 text,
    category_2 text,
    category_3 character varying(1),
    category_4 text,
    category_5 text,
    category_6 text,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone,
    category_7 text
);


ALTER TABLE public.discipline_referrals OWNER TO wxu_school;

--
-- Name: dual; Type: VIEW; Schema: public; Owner: wxu_school
--

CREATE VIEW public.dual AS
 SELECT 'X'::text AS dummy;


ALTER TABLE public.dual OWNER TO wxu_school;

--
-- Name: eligibility; Type: TABLE; Schema: public; Owner: wxu_school
--

CREATE TABLE public.eligibility (
    eligibility_id public.uuid_type NOT NULL,
    student_id public.uuid_type NOT NULL,
    syear numeric(4,0),
    school_date date,
    period_id public.uuid_type,
    eligibility_code character varying(20),
    course_period_id public.uuid_type NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.eligibility OWNER TO wxu_school;

--
-- Name: eligibility_activities; Type: TABLE; Schema: public; Owner: wxu_school
--

CREATE TABLE public.eligibility_activities (
    eligibility_activity_id public.uuid_type NOT NULL,
    syear numeric(4,0) NOT NULL,
    school_id public.uuid_type NOT NULL,
    title text NOT NULL,
    start_date date,
    end_date date,
    comment text,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.eligibility_activities OWNER TO wxu_school;

--
-- Name: eligibility_completed; Type: TABLE; Schema: public; Owner: wxu_school
--

CREATE TABLE public.eligibility_completed (
    eligibility_completed_id public.uuid_type NOT NULL,
    staff_id public.uuid_type NOT NULL,
    school_date date NOT NULL,
    period_id public.uuid_type NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.eligibility_completed OWNER TO wxu_school;

--
-- Name: school_gradelevels; Type: TABLE; Schema: public; Owner: wxu_school
--

CREATE TABLE public.school_gradelevels (
    gradelevel_id public.uuid_type NOT NULL,
    school_id public.uuid_type NOT NULL,
    short_name character varying(3),
    title character varying(50) NOT NULL,
    next_grade_id public.uuid_type,
    sort_order numeric,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone,
    marking_period_type character varying(20)
);


ALTER TABLE public.school_gradelevels OWNER TO wxu_school;

--
-- Name: student_enrollment; Type: TABLE; Schema: public; Owner: wxu_school
--

CREATE TABLE public.student_enrollment (
    enrollment_id public.uuid_type NOT NULL,
    syear numeric(4,0) NOT NULL,
    school_id public.uuid_type NOT NULL,
    student_id public.uuid_type NOT NULL,
    grade_id public.uuid_type,
    start_date date,
    end_date date,
    next_school integer,
    calendar_id integer,
    last_school integer,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone,
    second_course_period_id public.uuid_type,
    semester character varying(10),
    second_semester character varying(10),
    course_period_id public.uuid_type,
    second_grade_id public.uuid_type,
    enrollment_code uuid,
    drop_code uuid
);


ALTER TABLE public.student_enrollment OWNER TO wxu_school;

--
-- Name: enroll_grade; Type: VIEW; Schema: public; Owner: wxu_school
--

CREATE VIEW public.enroll_grade AS
 SELECT e.enrollment_id AS id,
    e.syear,
    e.school_id,
    e.student_id,
    e.start_date,
    e.end_date,
    sg.short_name,
    sg.title
   FROM public.student_enrollment e,
    public.school_gradelevels sg
  WHERE ((e.grade_id)::uuid = (sg.gradelevel_id)::uuid);


ALTER TABLE public.enroll_grade OWNER TO wxu_school;

--
-- Name: food_service_accounts; Type: TABLE; Schema: public; Owner: wxu_school
--

CREATE TABLE public.food_service_accounts (
    account_id public.uuid_type NOT NULL,
    balance numeric(9,2) NOT NULL,
    transaction_id integer,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.food_service_accounts OWNER TO wxu_school;

--
-- Name: food_service_categories; Type: TABLE; Schema: public; Owner: wxu_school
--

CREATE TABLE public.food_service_categories (
    category_id public.uuid_type NOT NULL,
    school_id public.uuid_type NOT NULL,
    menu_id public.uuid_type NOT NULL,
    title character varying(25) NOT NULL,
    sort_order numeric,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.food_service_categories OWNER TO wxu_school;

--
-- Name: food_service_items; Type: TABLE; Schema: public; Owner: wxu_school
--

CREATE TABLE public.food_service_items (
    item_id public.uuid_type NOT NULL,
    school_id public.uuid_type NOT NULL,
    short_name character varying(25),
    sort_order numeric,
    description character varying(25),
    icon character varying(50),
    price numeric(9,2) NOT NULL,
    price_reduced numeric(9,2),
    price_free numeric(9,2),
    price_staff numeric(9,2) NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.food_service_items OWNER TO wxu_school;

--
-- Name: food_service_menu_items; Type: TABLE; Schema: public; Owner: wxu_school
--

CREATE TABLE public.food_service_menu_items (
    menu_item_id public.uuid_type NOT NULL,
    school_id public.uuid_type NOT NULL,
    menu_id public.uuid_type NOT NULL,
    item_id public.uuid_type NOT NULL,
    category_id public.uuid_type,
    sort_order numeric,
    does_count character varying(1),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.food_service_menu_items OWNER TO wxu_school;

--
-- Name: food_service_menus; Type: TABLE; Schema: public; Owner: wxu_school
--

CREATE TABLE public.food_service_menus (
    menu_id public.uuid_type NOT NULL,
    school_id public.uuid_type NOT NULL,
    title character varying(25) NOT NULL,
    sort_order numeric,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.food_service_menus OWNER TO wxu_school;

--
-- Name: food_service_staff_accounts; Type: TABLE; Schema: public; Owner: wxu_school
--

CREATE TABLE public.food_service_staff_accounts (
    staff_account_id public.uuid_type NOT NULL,
    staff_id public.uuid_type NOT NULL,
    status character varying(25),
    barcode character varying(50),
    balance numeric(9,2) NOT NULL,
    transaction_id integer,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.food_service_staff_accounts OWNER TO wxu_school;

--
-- Name: food_service_staff_transaction_items; Type: TABLE; Schema: public; Owner: wxu_school
--

CREATE TABLE public.food_service_staff_transaction_items (
    staff_transaction_item_id public.uuid_type NOT NULL,
    item_id integer NOT NULL,
    transaction_id integer NOT NULL,
    amount numeric(9,2),
    short_name character varying(25),
    description character varying(50),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.food_service_staff_transaction_items OWNER TO wxu_school;

--
-- Name: food_service_staff_transactions; Type: TABLE; Schema: public; Owner: wxu_school
--

CREATE TABLE public.food_service_staff_transactions (
    transaction_id public.uuid_type NOT NULL,
    staff_id public.uuid_type NOT NULL,
    school_id public.uuid_type NOT NULL,
    syear numeric(4,0) NOT NULL,
    balance numeric(9,2),
    "timestamp" timestamp without time zone,
    short_name character varying(25),
    description character varying(50),
    seller_id integer,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.food_service_staff_transactions OWNER TO wxu_school;

--
-- Name: food_service_student_accounts; Type: TABLE; Schema: public; Owner: wxu_school
--

CREATE TABLE public.food_service_student_accounts (
    student_account_id public.uuid_type NOT NULL,
    student_id public.uuid_type NOT NULL,
    account_id public.uuid_type NOT NULL,
    discount character varying(25),
    status character varying(25),
    barcode character varying(50),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.food_service_student_accounts OWNER TO wxu_school;

--
-- Name: food_service_transaction_items; Type: TABLE; Schema: public; Owner: wxu_school
--

CREATE TABLE public.food_service_transaction_items (
    transaction_item_id public.uuid_type NOT NULL,
    item_id integer NOT NULL,
    transaction_id integer NOT NULL,
    amount numeric(9,2),
    discount character varying(25),
    short_name character varying(25),
    description character varying(50),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.food_service_transaction_items OWNER TO wxu_school;

--
-- Name: food_service_transactions; Type: TABLE; Schema: public; Owner: wxu_school
--

CREATE TABLE public.food_service_transactions (
    transaction_id public.uuid_type NOT NULL,
    account_id public.uuid_type NOT NULL,
    student_id public.uuid_type,
    school_id public.uuid_type NOT NULL,
    syear numeric(4,0) NOT NULL,
    discount character varying(25),
    balance numeric(9,2),
    "timestamp" timestamp without time zone,
    short_name character varying(25),
    description character varying(50),
    seller_id integer,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.food_service_transactions OWNER TO wxu_school;

--
-- Name: grade_levels; Type: TABLE; Schema: public; Owner: wxu_school
--

CREATE TABLE public.grade_levels (
    grade_level_id public.uuid_type NOT NULL,
    title character varying(100) NOT NULL,
    sort_order integer DEFAULT 0
);


ALTER TABLE public.grade_levels OWNER TO wxu_school;

--
-- Name: gradebook_assignment_types; Type: TABLE; Schema: public; Owner: wxu_school
--

CREATE TABLE public.gradebook_assignment_types (
    assignment_type_id public.uuid_type NOT NULL,
    staff_id public.uuid_type NOT NULL,
    course_id public.uuid_type NOT NULL,
    title text NOT NULL,
    final_grade_percent numeric(6,5),
    sort_order numeric,
    color character varying(30),
    created_mp integer,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.gradebook_assignment_types OWNER TO wxu_school;

--
-- Name: gradebook_assignments; Type: TABLE; Schema: public; Owner: wxu_school
--

CREATE TABLE public.gradebook_assignments (
    assignment_id public.uuid_type NOT NULL,
    staff_id public.uuid_type NOT NULL,
    marking_period_id public.uuid_type NOT NULL,
    course_period_id public.uuid_type,
    course_id public.uuid_type,
    assignment_type_id public.uuid_type NOT NULL,
    title text NOT NULL,
    assigned_date date,
    due_date date,
    points integer NOT NULL,
    description text,
    file text,
    default_points integer,
    submission character varying(1),
    weight integer,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.gradebook_assignments OWNER TO wxu_school;

--
-- Name: gradebook_grades; Type: TABLE; Schema: public; Owner: wxu_school
--

CREATE TABLE public.gradebook_grades (
    gradebook_grade_id public.uuid_type NOT NULL,
    student_id public.uuid_type NOT NULL,
    period_id public.uuid_type,
    course_period_id public.uuid_type NOT NULL,
    assignment_id public.uuid_type NOT NULL,
    points numeric(6,2),
    comment text,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.gradebook_grades OWNER TO wxu_school;

--
-- Name: grades_completed; Type: TABLE; Schema: public; Owner: wxu_school
--

CREATE TABLE public.grades_completed (
    grades_completed_id public.uuid_type NOT NULL,
    staff_id public.uuid_type NOT NULL,
    marking_period_id public.uuid_type NOT NULL,
    course_period_id public.uuid_type NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.grades_completed OWNER TO wxu_school;

--
-- Name: history_marking_periods; Type: TABLE; Schema: public; Owner: wxu_school
--

CREATE TABLE public.history_marking_periods (
    history_marking_period_id public.uuid_type NOT NULL,
    parent_id public.uuid_type,
    mp_type character varying(20),
    name character varying(50) NOT NULL,
    short_name character varying(10),
    post_end_date date,
    school_id public.uuid_type NOT NULL,
    syear numeric(4,0),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.history_marking_periods OWNER TO wxu_school;

--
-- Name: lunch_period; Type: TABLE; Schema: public; Owner: wxu_school
--

CREATE TABLE public.lunch_period (
    lunch_period_id public.uuid_type NOT NULL,
    student_id public.uuid_type NOT NULL,
    school_date date NOT NULL,
    period_id public.uuid_type NOT NULL,
    attendance_code integer,
    attendance_teacher_code integer,
    attendance_reason character varying(100),
    admin character varying(1),
    course_period_id public.uuid_type,
    marking_period_id public.uuid_type,
    comment character varying(100),
    table_name integer,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.lunch_period OWNER TO wxu_school;

--
-- Name: school_marking_periods; Type: TABLE; Schema: public; Owner: wxu_school
--

CREATE TABLE public.school_marking_periods (
    marking_period_id public.uuid_type NOT NULL,
    syear numeric(4,0) NOT NULL,
    mp character varying(3) NOT NULL,
    school_id public.uuid_type NOT NULL,
    parent_id public.uuid_type,
    title character varying(50) NOT NULL,
    short_name character varying(10),
    sort_order numeric,
    start_date date NOT NULL,
    end_date date NOT NULL,
    post_start_date date,
    post_end_date date,
    does_grades character varying(1),
    does_comments character varying(1),
    rollover_id public.uuid_type,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.school_marking_periods OWNER TO wxu_school;

--
-- Name: marking_periods; Type: VIEW; Schema: public; Owner: wxu_school
--

CREATE VIEW public.marking_periods AS
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
              WHERE ((smp.marking_period_id)::uuid = (school_marking_periods.parent_id)::uuid)))::uuid IS NOT NULL) THEN (( SELECT smp.parent_id
               FROM public.school_marking_periods smp
              WHERE ((smp.marking_period_id)::uuid = (school_marking_periods.parent_id)::uuid)))::text
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
 SELECT history_marking_periods.history_marking_period_id AS marking_period_id,
    'History'::text AS mp_source,
    history_marking_periods.syear,
    history_marking_periods.school_id,
    history_marking_periods.mp_type,
    history_marking_periods.name AS title,
    history_marking_periods.short_name,
    NULL::numeric AS sort_order,
    (history_marking_periods.parent_id)::text AS parent_id,
    '-1'::text AS grandparent_id,
    NULL::date AS start_date,
    history_marking_periods.post_end_date AS end_date,
    NULL::date AS post_start_date,
    history_marking_periods.post_end_date,
    'Y'::character varying AS does_grades,
    NULL::character varying AS does_comments
   FROM public.history_marking_periods;


ALTER TABLE public.marking_periods OWNER TO wxu_school;

--
-- Name: messages; Type: TABLE; Schema: public; Owner: wxu_school
--

CREATE TABLE public.messages (
    message_id public.uuid_type NOT NULL,
    syear numeric(4,0) NOT NULL,
    school_id public.uuid_type NOT NULL,
    "from" character varying(255),
    recipients text,
    subject character varying(100),
    data text,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.messages OWNER TO wxu_school;

--
-- Name: messagexuser; Type: TABLE; Schema: public; Owner: wxu_school
--

CREATE TABLE public.messagexuser (
    messagexuser_id public.uuid_type NOT NULL,
    user_id integer NOT NULL,
    key character varying(10),
    message_id public.uuid_type NOT NULL,
    status character varying(10) NOT NULL
);


ALTER TABLE public.messagexuser OWNER TO wxu_school;

--
-- Name: moodlexrosario; Type: TABLE; Schema: public; Owner: wxu_school
--

CREATE TABLE public.moodlexrosario (
    moodlexrosario_id public.uuid_type NOT NULL,
    "column" character varying(100) NOT NULL,
    rosario_id integer NOT NULL,
    moodle_id integer NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.moodlexrosario OWNER TO wxu_school;

--
-- Name: people; Type: TABLE; Schema: public; Owner: wxu_school
--

CREATE TABLE public.people (
    person_id public.uuid_type NOT NULL,
    last_name character varying(50) NOT NULL,
    first_name character varying(50) NOT NULL,
    middle_name character varying(50),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.people OWNER TO wxu_school;

--
-- Name: people_field_categories; Type: TABLE; Schema: public; Owner: wxu_school
--

CREATE TABLE public.people_field_categories (
    people_field_category_id public.uuid_type NOT NULL,
    title text NOT NULL,
    sort_order numeric,
    custody character(1),
    emergency character(1),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.people_field_categories OWNER TO wxu_school;

--
-- Name: people_fields; Type: TABLE; Schema: public; Owner: wxu_school
--

CREATE TABLE public.people_fields (
    people_field_id public.uuid_type NOT NULL,
    type character varying(10),
    title text NOT NULL,
    sort_order numeric,
    select_options text,
    category_id public.uuid_type,
    required character varying(1),
    default_selection text,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.people_fields OWNER TO wxu_school;

--
-- Name: people_join_contacts; Type: TABLE; Schema: public; Owner: wxu_school
--

CREATE TABLE public.people_join_contacts (
    people_join_contact_id public.uuid_type NOT NULL,
    person_id public.uuid_type,
    title character varying(100),
    value character varying(100),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.people_join_contacts OWNER TO wxu_school;

--
-- Name: portal_notes; Type: TABLE; Schema: public; Owner: wxu_school
--

CREATE TABLE public.portal_notes (
    portal_note_id public.uuid_type NOT NULL,
    school_id public.uuid_type NOT NULL,
    syear numeric(4,0) NOT NULL,
    title text NOT NULL,
    content text,
    sort_order numeric,
    published_user integer,
    published_date timestamp without time zone,
    start_date date,
    end_date date,
    published_profiles text,
    file_attached text,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.portal_notes OWNER TO wxu_school;

--
-- Name: portal_poll_questions; Type: TABLE; Schema: public; Owner: wxu_school
--

CREATE TABLE public.portal_poll_questions (
    portal_poll_question_id public.uuid_type NOT NULL,
    portal_poll_id public.uuid_type NOT NULL,
    question text NOT NULL,
    type character varying(20),
    options text,
    votes text,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.portal_poll_questions OWNER TO wxu_school;

--
-- Name: portal_polls; Type: TABLE; Schema: public; Owner: wxu_school
--

CREATE TABLE public.portal_polls (
    portal_poll_id public.uuid_type NOT NULL,
    school_id public.uuid_type NOT NULL,
    syear numeric(4,0) NOT NULL,
    title text NOT NULL,
    votes_number integer,
    display_votes character varying(1),
    sort_order numeric,
    published_user integer,
    published_date timestamp without time zone,
    start_date date,
    end_date date,
    published_profiles text,
    students_teacher_id integer,
    excluded_users text,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.portal_polls OWNER TO wxu_school;

--
-- Name: profile_exceptions; Type: TABLE; Schema: public; Owner: wxu_school
--

CREATE TABLE public.profile_exceptions (
    profile_exception_id public.uuid_type NOT NULL,
    profile_id integer NOT NULL,
    modname character varying(150) NOT NULL,
    can_use character varying(1),
    can_edit character varying(1),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.profile_exceptions OWNER TO wxu_school;

--
-- Name: program_config; Type: TABLE; Schema: public; Owner: wxu_school
--

CREATE TABLE public.program_config (
    program_config_id public.uuid_type NOT NULL,
    syear numeric(4,0) NOT NULL,
    school_id public.uuid_type NOT NULL,
    program character varying(100) NOT NULL,
    title character varying(100) NOT NULL,
    value text,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.program_config OWNER TO wxu_school;

--
-- Name: program_user_config; Type: TABLE; Schema: public; Owner: wxu_school
--

CREATE TABLE public.program_user_config (
    program_user_config_id public.uuid_type NOT NULL,
    user_id integer NOT NULL,
    program character varying(100) NOT NULL,
    title character varying(100) NOT NULL,
    value text,
    school_id public.uuid_type,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.program_user_config OWNER TO wxu_school;

--
-- Name: report_card_comment_categories; Type: TABLE; Schema: public; Owner: wxu_school
--

CREATE TABLE public.report_card_comment_categories (
    report_card_comment_category_id public.uuid_type NOT NULL,
    syear numeric(4,0) NOT NULL,
    school_id public.uuid_type NOT NULL,
    course_id public.uuid_type,
    sort_order numeric,
    title text NOT NULL,
    rollover_id public.uuid_type,
    color character varying(30),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.report_card_comment_categories OWNER TO wxu_school;

--
-- Name: report_card_comment_code_scales; Type: TABLE; Schema: public; Owner: wxu_school
--

CREATE TABLE public.report_card_comment_code_scales (
    report_card_comment_code_scale_id public.uuid_type NOT NULL,
    school_id public.uuid_type NOT NULL,
    title character varying(25) NOT NULL,
    comment character varying(100),
    sort_order numeric,
    rollover_id public.uuid_type,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.report_card_comment_code_scales OWNER TO wxu_school;

--
-- Name: report_card_comment_codes; Type: TABLE; Schema: public; Owner: wxu_school
--

CREATE TABLE public.report_card_comment_codes (
    report_card_comment_code_id public.uuid_type NOT NULL,
    school_id public.uuid_type NOT NULL,
    scale_id public.uuid_type NOT NULL,
    title character varying(5) NOT NULL,
    short_name character varying(100),
    comment character varying(100),
    sort_order numeric,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.report_card_comment_codes OWNER TO wxu_school;

--
-- Name: report_card_comments; Type: TABLE; Schema: public; Owner: wxu_school
--

CREATE TABLE public.report_card_comments (
    report_card_comment_id public.uuid_type NOT NULL,
    syear numeric(4,0) NOT NULL,
    school_id public.uuid_type NOT NULL,
    course_id public.uuid_type,
    category_id public.uuid_type,
    scale_id public.uuid_type,
    sort_order numeric,
    title text NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.report_card_comments OWNER TO wxu_school;

--
-- Name: report_card_grade_scales; Type: TABLE; Schema: public; Owner: wxu_school
--

CREATE TABLE public.report_card_grade_scales (
    report_card_grade_scale_id public.uuid_type NOT NULL,
    syear numeric(4,0) NOT NULL,
    school_id public.uuid_type NOT NULL,
    title text NOT NULL,
    comment text,
    hhr_gpa_value numeric(7,2),
    hr_gpa_value numeric(7,2),
    sort_order numeric,
    rollover_id public.uuid_type,
    gp_scale numeric(7,2) NOT NULL,
    gp_passing_value numeric(7,2),
    hrs_gpa_value numeric(7,2),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.report_card_grade_scales OWNER TO wxu_school;

--
-- Name: report_card_grades; Type: TABLE; Schema: public; Owner: wxu_school
--

CREATE TABLE public.report_card_grades (
    report_card_grade_id public.uuid_type NOT NULL,
    syear numeric(4,0) NOT NULL,
    school_id public.uuid_type NOT NULL,
    title character varying(5) NOT NULL,
    sort_order numeric,
    gpa_value numeric(7,2),
    break_off numeric(7,2),
    comment text,
    grade_scale_id public.uuid_type,
    unweighted_gp numeric(7,2),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.report_card_grades OWNER TO wxu_school;

--
-- Name: resources; Type: TABLE; Schema: public; Owner: wxu_school
--

CREATE TABLE public.resources (
    resource_id public.uuid_type NOT NULL,
    school_id public.uuid_type NOT NULL,
    title text NOT NULL,
    link text,
    published_profiles text,
    published_grade_levels text,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.resources OWNER TO wxu_school;

--
-- Name: schedule; Type: TABLE; Schema: public; Owner: wxu_school
--

CREATE TABLE public.schedule (
    schedule_id public.uuid_type NOT NULL,
    syear numeric(4,0) NOT NULL,
    school_id public.uuid_type NOT NULL,
    student_id public.uuid_type NOT NULL,
    start_date date NOT NULL,
    end_date date,
    modified_date date,
    modified_by character varying(255),
    course_id public.uuid_type NOT NULL,
    course_period_id public.uuid_type NOT NULL,
    mp character varying(3),
    marking_period_id public.uuid_type,
    scheduler_lock character varying(1),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.schedule OWNER TO wxu_school;

--
-- Name: schedule_requests; Type: TABLE; Schema: public; Owner: wxu_school
--

CREATE TABLE public.schedule_requests (
    schedule_request_id public.uuid_type NOT NULL,
    syear numeric(4,0) NOT NULL,
    school_id public.uuid_type NOT NULL,
    student_id public.uuid_type NOT NULL,
    subject_id public.uuid_type,
    course_id public.uuid_type,
    marking_period_id public.uuid_type,
    priority integer,
    with_teacher_id public.uuid_type,
    not_teacher_id public.uuid_type,
    with_period_id public.uuid_type,
    not_period_id public.uuid_type,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.schedule_requests OWNER TO wxu_school;

--
-- Name: school_fields; Type: TABLE; Schema: public; Owner: wxu_school
--

CREATE TABLE public.school_fields (
    school_field_id public.uuid_type NOT NULL,
    type character varying(10) NOT NULL,
    title text NOT NULL,
    sort_order numeric,
    select_options text,
    required character varying(1),
    default_selection text,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.school_fields OWNER TO wxu_school;

--
-- Name: school_periods; Type: TABLE; Schema: public; Owner: wxu_school
--

CREATE TABLE public.school_periods (
    period_id public.uuid_type NOT NULL,
    syear numeric(4,0) NOT NULL,
    school_id public.uuid_type NOT NULL,
    sort_order numeric,
    title character varying(100) NOT NULL,
    short_name character varying(10),
    length integer,
    start_time character varying(10),
    end_time character varying(10),
    block character varying(10),
    attendance character varying(1),
    rollover_id public.uuid_type,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.school_periods OWNER TO wxu_school;

--
-- Name: schools; Type: TABLE; Schema: public; Owner: wxu_school
--

CREATE TABLE public.schools (
    school_id public.uuid_type NOT NULL,
    syear numeric(4,0) NOT NULL,
    title character varying(100) NOT NULL,
    address character varying(100),
    city character varying(100),
    state character varying(10),
    zipcode character varying(10),
    phone character varying(30),
    principal character varying(100),
    www_address text,
    school_number character varying(50),
    short_name character varying(25),
    reporting_gp_scale numeric(10,3),
    number_days_rotation numeric(1,0),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.schools OWNER TO wxu_school;

--
-- Name: staff; Type: TABLE; Schema: public; Owner: wxu_school
--

CREATE TABLE public.staff (
    staff_id public.uuid_type NOT NULL,
    syear numeric(4,0) NOT NULL,
    current_school_id public.uuid_type,
    title character varying(5),
    first_name character varying(100) NOT NULL,
    last_name character varying(100) NOT NULL,
    middle_name character varying(100),
    name_suffix character varying(3),
    username character varying(100),
    password character varying(106),
    email character varying(255),
    custom_200000001 text,
    profile character varying(30),
    homeroom character varying(5),
    schools character varying(150),
    last_login timestamp without time zone,
    failed_login integer,
    rollover_id public.uuid_type,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone,
    custom_200000002 character varying(1),
    custom_200000003 text,
    custom_200000004 text,
    custom_200000005 date,
    a_salaire_fixe character(1),
    salaire_fixe numeric(12,2),
    date_debut_contrat date,
    date_fin_contrat date,
    profile_id public.uuid_type
);


ALTER TABLE public.staff OWNER TO wxu_school;

--
-- Name: staff_exceptions; Type: TABLE; Schema: public; Owner: wxu_school
--

CREATE TABLE public.staff_exceptions (
    staff_exception_id public.uuid_type NOT NULL,
    user_id integer NOT NULL,
    modname character varying(150) NOT NULL,
    can_use character varying(1),
    can_edit character varying(1),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.staff_exceptions OWNER TO wxu_school;

--
-- Name: staff_field_categories; Type: TABLE; Schema: public; Owner: wxu_school
--

CREATE TABLE public.staff_field_categories (
    staff_field_category_id public.uuid_type NOT NULL,
    title text NOT NULL,
    sort_order numeric,
    columns numeric(4,0),
    include character varying(100),
    admin character(1),
    teacher character(1),
    parent character(1),
    "none" character(1),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.staff_field_categories OWNER TO wxu_school;

--
-- Name: staff_fields; Type: TABLE; Schema: public; Owner: wxu_school
--

CREATE TABLE public.staff_fields (
    staff_field_id public.uuid_type NOT NULL,
    type character varying(10) NOT NULL,
    title text NOT NULL,
    sort_order numeric,
    select_options text,
    category_id public.uuid_type,
    required character varying(1),
    default_selection text,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.staff_fields OWNER TO wxu_school;

--
-- Name: student_assignments; Type: TABLE; Schema: public; Owner: wxu_school
--

CREATE TABLE public.student_assignments (
    student_assignment_id public.uuid_type NOT NULL,
    assignment_id integer NOT NULL,
    student_id public.uuid_type NOT NULL,
    data text,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.student_assignments OWNER TO wxu_school;

--
-- Name: student_eligibility_activities; Type: TABLE; Schema: public; Owner: wxu_school
--

CREATE TABLE public.student_eligibility_activities (
    student_eligibility_activity_id public.uuid_type NOT NULL,
    syear numeric(4,0),
    student_id public.uuid_type NOT NULL,
    activity_id public.uuid_type NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.student_eligibility_activities OWNER TO wxu_school;

--
-- Name: student_enrollment_codes; Type: TABLE; Schema: public; Owner: wxu_school
--

CREATE TABLE public.student_enrollment_codes (
    student_enrollment_code_id public.uuid_type NOT NULL,
    syear numeric(4,0) NOT NULL,
    title character varying(100) NOT NULL,
    short_name character varying(10),
    type character varying(4),
    default_code character varying(1),
    sort_order numeric,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.student_enrollment_codes OWNER TO wxu_school;

--
-- Name: student_enrollment_course_periods; Type: TABLE; Schema: public; Owner: wxu_school
--

CREATE TABLE public.student_enrollment_course_periods (
    student_enrollment_course_period_id public.uuid_type NOT NULL,
    student_enrollment_id public.uuid_type NOT NULL,
    course_period_id public.uuid_type NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE public.student_enrollment_course_periods OWNER TO wxu_school;

--
-- Name: student_field_categories; Type: TABLE; Schema: public; Owner: wxu_school
--

CREATE TABLE public.student_field_categories (
    student_field_category_id public.uuid_type NOT NULL,
    title text NOT NULL,
    sort_order numeric,
    columns numeric(4,0),
    include character varying(100),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.student_field_categories OWNER TO wxu_school;

--
-- Name: student_medical; Type: TABLE; Schema: public; Owner: wxu_school
--

CREATE TABLE public.student_medical (
    student_medical_id public.uuid_type NOT NULL,
    student_id public.uuid_type NOT NULL,
    type character varying(25),
    medical_date date,
    comments character varying(100),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.student_medical OWNER TO wxu_school;

--
-- Name: student_medical_alerts; Type: TABLE; Schema: public; Owner: wxu_school
--

CREATE TABLE public.student_medical_alerts (
    student_medical_alert_id public.uuid_type NOT NULL,
    student_id public.uuid_type NOT NULL,
    title character varying(100),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.student_medical_alerts OWNER TO wxu_school;

--
-- Name: student_medical_visits; Type: TABLE; Schema: public; Owner: wxu_school
--

CREATE TABLE public.student_medical_visits (
    student_medical_visit_id public.uuid_type NOT NULL,
    student_id public.uuid_type NOT NULL,
    school_date date,
    time_in character varying(20),
    time_out character varying(20),
    reason character varying(100),
    result character varying(100),
    comments text,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.student_medical_visits OWNER TO wxu_school;

--
-- Name: student_mp_comments; Type: TABLE; Schema: public; Owner: wxu_school
--

CREATE TABLE public.student_mp_comments (
    student_mp_comment_id public.uuid_type NOT NULL,
    student_id public.uuid_type NOT NULL,
    syear numeric(4,0) NOT NULL,
    marking_period_id public.uuid_type NOT NULL,
    comment text,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.student_mp_comments OWNER TO wxu_school;

--
-- Name: student_mp_stats; Type: TABLE; Schema: public; Owner: wxu_school
--

CREATE TABLE public.student_mp_stats (
    student_mp_stat_id public.uuid_type NOT NULL,
    student_id public.uuid_type NOT NULL,
    marking_period_id public.uuid_type NOT NULL,
    cum_weighted_factor numeric,
    cum_unweighted_factor numeric,
    cum_rank integer,
    mp_rank integer,
    class_size integer,
    sum_weighted_factors numeric,
    sum_unweighted_factors numeric,
    count_weighted_factors integer,
    count_unweighted_factors integer,
    grade_level_short character varying(3),
    cr_weighted_factors numeric,
    cr_unweighted_factors numeric,
    count_cr_factors integer,
    cum_cr_weighted_factor numeric,
    cum_cr_unweighted_factor numeric,
    credit_attempted numeric,
    credit_earned numeric,
    gp_credits numeric,
    cr_credits numeric,
    comments character varying(75),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.student_mp_stats OWNER TO wxu_school;

--
-- Name: student_report_card_comments; Type: TABLE; Schema: public; Owner: wxu_school
--

CREATE TABLE public.student_report_card_comments (
    student_report_card_comment_id public.uuid_type NOT NULL,
    syear numeric(4,0) NOT NULL,
    school_id public.uuid_type NOT NULL,
    student_id public.uuid_type NOT NULL,
    course_period_id public.uuid_type NOT NULL,
    comment character varying(5),
    marking_period_id public.uuid_type NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone,
    report_card_comment_id uuid
);


ALTER TABLE public.student_report_card_comments OWNER TO wxu_school;

--
-- Name: student_report_card_grades; Type: TABLE; Schema: public; Owner: wxu_school
--

CREATE TABLE public.student_report_card_grades (
    student_report_card_grade_id public.uuid_type NOT NULL,
    syear numeric(4,0) NOT NULL,
    school_id public.uuid_type NOT NULL,
    student_id public.uuid_type NOT NULL,
    course_period_id public.uuid_type,
    report_card_grade_id integer,
    report_card_comment_id public.uuid_type,
    comment text,
    grade_percent numeric(4,1),
    marking_period_id public.uuid_type NOT NULL,
    grade_letter character varying(5),
    weighted_gp numeric(7,2),
    unweighted_gp numeric(7,2),
    gp_scale numeric(7,2),
    credit_attempted numeric,
    credit_earned numeric,
    credit_category character varying(10),
    course_title text NOT NULL,
    school text,
    class_rank character varying(1),
    credit_hours numeric(6,2),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.student_report_card_grades OWNER TO wxu_school;

--
-- Name: students; Type: TABLE; Schema: public; Owner: wxu_school
--

CREATE TABLE public.students (
    student_id public.uuid_type NOT NULL,
    last_name character varying(50) NOT NULL,
    first_name character varying(50) NOT NULL,
    middle_name character varying(50),
    name_suffix character varying(3),
    username character varying(100),
    password character varying(106),
    last_login timestamp without time zone,
    failed_login integer,
    custom_200000000 text,
    custom_200000001 text,
    custom_200000002 text,
    custom_200000003 text,
    custom_200000004 date,
    custom_200000005 text,
    custom_200000006 text,
    custom_200000007 text,
    custom_200000008 text,
    custom_200000009 text,
    custom_200000010 character(1),
    custom_200000011 text,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone,
    frais_inscriptions numeric(10,2),
    reinscription numeric(10,2) DEFAULT 0
);


ALTER TABLE public.students OWNER TO wxu_school;

--
-- Name: students_join_address; Type: TABLE; Schema: public; Owner: wxu_school
--

CREATE TABLE public.students_join_address (
    student_join_address_id public.uuid_type NOT NULL,
    student_id public.uuid_type NOT NULL,
    address_id public.uuid_type NOT NULL,
    contact_seq numeric(10,0),
    gets_mail character varying(1),
    primary_residence character varying(1),
    legal_residence character varying(1),
    am_bus character varying(1),
    pm_bus character varying(1),
    mailing character varying(1),
    residence character varying(1),
    bus character varying(1),
    bus_pickup character varying(1),
    bus_dropoff character varying(1),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.students_join_address OWNER TO wxu_school;

--
-- Name: students_join_people; Type: TABLE; Schema: public; Owner: wxu_school
--

CREATE TABLE public.students_join_people (
    student_join_people_id public.uuid_type NOT NULL,
    student_id public.uuid_type NOT NULL,
    person_id public.uuid_type NOT NULL,
    address_id public.uuid_type,
    custody character varying(1),
    emergency character varying(1),
    student_relation character varying(100),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.students_join_people OWNER TO wxu_school;

--
-- Name: students_join_users; Type: TABLE; Schema: public; Owner: wxu_school
--

CREATE TABLE public.students_join_users (
    student_join_user_id public.uuid_type NOT NULL,
    student_id public.uuid_type NOT NULL,
    staff_id public.uuid_type NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.students_join_users OWNER TO wxu_school;

--
-- Name: templates; Type: TABLE; Schema: public; Owner: wxu_school
--

CREATE TABLE public.templates (
    template_id public.uuid_type NOT NULL,
    modname character varying(150) NOT NULL,
    staff_id public.uuid_type NOT NULL,
    template text,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.templates OWNER TO wxu_school;

--
-- Name: transcript_grades; Type: VIEW; Schema: public; Owner: wxu_school
--

CREATE VIEW public.transcript_grades AS
 SELECT mp.syear,
    mp.school_id,
    mp.marking_period_id,
    mp.mp_type,
    mp.short_name,
    mp.parent_id,
    mp.grandparent_id,
    ( SELECT mp2.end_date
           FROM (public.student_report_card_grades
             JOIN public.marking_periods mp2 ON (((mp2.marking_period_id)::uuid = (student_report_card_grades.marking_period_id)::uuid)))
          WHERE (((student_report_card_grades.student_id)::uuid = (sms.student_id)::uuid) AND (((student_report_card_grades.marking_period_id)::uuid = (mp.parent_id)::uuid) OR ((student_report_card_grades.marking_period_id)::uuid = (mp.grandparent_id)::uuid)) AND (student_report_card_grades.course_title = srcg.course_title))
          ORDER BY mp2.end_date
         LIMIT 1) AS parent_end_date,
    mp.end_date,
    sms.student_id,
    (sms.cum_weighted_factor * COALESCE(schools.reporting_gp_scale, ( SELECT schools_1.reporting_gp_scale
           FROM public.schools schools_1
          WHERE ((mp.school_id)::uuid = (schools_1.school_id)::uuid)
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
     JOIN public.student_report_card_grades srcg ON (((mp.marking_period_id)::uuid = (srcg.marking_period_id)::uuid)))
     JOIN public.student_mp_stats sms ON ((((sms.marking_period_id)::uuid = (mp.marking_period_id)::uuid) AND ((sms.student_id)::uuid = (srcg.student_id)::uuid))))
     LEFT JOIN public.schools ON (((((mp.school_id)::uuid = (schools.school_id)::uuid) AND ((mp.mp_source <> 'History'::text) AND (mp.syear = schools.syear))) OR ((mp.mp_source = 'History'::text) AND (mp.syear = ( SELECT schools_1.syear
           FROM public.schools schools_1
          WHERE ((mp.school_id)::uuid = (schools_1.school_id)::uuid)
          ORDER BY schools_1.syear
         LIMIT 1))))))
  ORDER BY srcg.course_period_id;


ALTER TABLE public.transcript_grades OWNER TO wxu_school;

--
-- Name: user_profiles; Type: TABLE; Schema: public; Owner: wxu_school
--

CREATE TABLE public.user_profiles (
    profile character varying(30),
    title text NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone,
    id public.uuid_type NOT NULL
);


ALTER TABLE public.user_profiles OWNER TO wxu_school;

--
-- Name: wx_appreciations; Type: TABLE; Schema: public; Owner: wxu_school
--

CREATE TABLE public.wx_appreciations (
    wx_appreciation_id public.uuid_type NOT NULL,
    grade_id integer NOT NULL,
    appreciation character varying(255) NOT NULL,
    note_1 character varying(255),
    note_2 character varying(255)
);


ALTER TABLE public.wx_appreciations OWNER TO wxu_school;

--
-- Name: wx_config_publication_resultats; Type: TABLE; Schema: public; Owner: wxu_school
--

CREATE TABLE public.wx_config_publication_resultats (
    wx_config_publication_resultat_id public.uuid_type NOT NULL,
    school_gradelevels_id public.uuid_type NOT NULL,
    period character varying(50),
    valeur integer,
    syear numeric(4,0)
);


ALTER TABLE public.wx_config_publication_resultats OWNER TO wxu_school;

--
-- Name: wx_course_periods_gradelevels; Type: TABLE; Schema: public; Owner: wxu_school
--

CREATE TABLE public.wx_course_periods_gradelevels (
    wx_course_periods_gradelevels_id public.uuid_type NOT NULL,
    course_periods_id public.uuid_type NOT NULL,
    school_gradelevels_id public.uuid_type NOT NULL
);


ALTER TABLE public.wx_course_periods_gradelevels OWNER TO wxu_school;

--
-- Name: wx_course_periods_subjects; Type: TABLE; Schema: public; Owner: wxu_school
--

CREATE TABLE public.wx_course_periods_subjects (
    wx_course_periods_subjects_id public.uuid_type NOT NULL,
    course_periods_id public.uuid_type NOT NULL,
    course_subjects_id public.uuid_type NOT NULL,
    coefficient character varying(10) DEFAULT '1'::character varying NOT NULL,
    teacher_id public.uuid_type NOT NULL,
    secondary_teacher_id public.uuid_type,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    ue_id public.uuid_type,
    period_position character varying(255),
    taux_horaires numeric(10,2),
    ue_compensation character varying(10) DEFAULT 'false'::character varying,
    CONSTRAINT chk_taux_horaires_positive CHECK ((taux_horaires >= (0)::numeric))
);


ALTER TABLE public.wx_course_periods_subjects OWNER TO wxu_school;

--
-- Name: wx_course_periods_subjects_periods; Type: TABLE; Schema: public; Owner: wxu_school
--

CREATE TABLE public.wx_course_periods_subjects_periods (
    wx_course_periods_subjects_periods_id public.uuid_type NOT NULL,
    wx_course_periods_subjects_id public.uuid_type NOT NULL,
    day character(1) NOT NULL,
    start_time character varying(10) NOT NULL,
    end_time character varying(10) NOT NULL
);


ALTER TABLE public.wx_course_periods_subjects_periods OWNER TO wxu_school;

--
-- Name: wx_course_subjects_gradelevels; Type: TABLE; Schema: public; Owner: wxu_school
--

CREATE TABLE public.wx_course_subjects_gradelevels (
    wx_course_subjects_gradelevels_id public.uuid_type NOT NULL,
    course_subjects_id public.uuid_type NOT NULL,
    school_gradelevels_id public.uuid_type NOT NULL,
    coefficient numeric(5,2) DEFAULT 1.00,
    semester_type character varying(10)
);


ALTER TABLE public.wx_course_subjects_gradelevels OWNER TO wxu_school;

--
-- Name: wx_custom_configuration_school; Type: TABLE; Schema: public; Owner: wxu_school
--

CREATE TABLE public.wx_custom_configuration_school (
    id_custom_configuration_school public.uuid_type NOT NULL,
    school_id public.uuid_type NOT NULL,
    type_school character varying(255)
);


ALTER TABLE public.wx_custom_configuration_school OWNER TO wxu_school;

--
-- Name: wx_echelle_notation_appreciation; Type: TABLE; Schema: public; Owner: wxu_school
--

CREATE TABLE public.wx_echelle_notation_appreciation (
    wx_echelle_notation_appreciation_id public.uuid_type NOT NULL,
    note_debut double precision NOT NULL,
    note_fin double precision NOT NULL,
    echelle_notation integer NOT NULL,
    appreciation character varying(5),
    year numeric(4,0),
    school_id public.uuid_type NOT NULL
);


ALTER TABLE public.wx_echelle_notation_appreciation OWNER TO wxu_school;

--
-- Name: wx_families; Type: TABLE; Schema: public; Owner: wxu_school
--

CREATE TABLE public.wx_families (
    wx_family_id public.uuid_type NOT NULL,
    name character varying(100) NOT NULL,
    amount numeric(10,2) DEFAULT 0.00 NOT NULL,
    school_id public.uuid_type NOT NULL,
    syear integer NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.wx_families OWNER TO wxu_school;

--
-- Name: wx_family_members; Type: TABLE; Schema: public; Owner: wxu_school
--

CREATE TABLE public.wx_family_members (
    wx_family_member_id public.uuid_type NOT NULL,
    family_id public.uuid_type NOT NULL,
    student_id public.uuid_type NOT NULL,
    is_representative boolean DEFAULT false NOT NULL
);


ALTER TABLE public.wx_family_members OWNER TO wxu_school;

--
-- Name: wx_gradel_period_evaluation; Type: TABLE; Schema: public; Owner: wxu_school
--

CREATE TABLE public.wx_gradel_period_evaluation (
    id_gradel_period_evaluation public.uuid_type NOT NULL,
    school_gradelevels_id public.uuid_type NOT NULL,
    type_period_evaluation character varying(20),
    year numeric(4,0) NOT NULL,
    allow_debt_passage boolean DEFAULT false,
    debt_passage_percentage numeric(5,2) DEFAULT 0.00,
    eliminatory_note numeric(5,2) DEFAULT 0.00,
    debt_passage_percentage_devoir numeric(5,2) DEFAULT 0,
    debt_passage_percentage_session numeric(5,2) DEFAULT 0,
    eliminatory_mark numeric(5,2) DEFAULT 0,
    is_passage_with_debt character varying(1) DEFAULT '0'::character varying,
    percentage_of_credit_for_passage numeric(5,2) DEFAULT 0,
    is_compensable character varying(1) DEFAULT '0'::character varying
);


ALTER TABLE public.wx_gradel_period_evaluation OWNER TO wxu_school;

--
-- Name: wx_moyennes_finales_students; Type: TABLE; Schema: public; Owner: wxu_school
--

CREATE TABLE public.wx_moyennes_finales_students (
    wx_moyenne_finale_student_id public.uuid_type NOT NULL,
    student_enrollment_id public.uuid_type NOT NULL,
    moyenne double precision NOT NULL,
    exam_type character varying(10)
);


ALTER TABLE public.wx_moyennes_finales_students OWNER TO wxu_school;

--
-- Name: wx_moyennes_validation_gradelevel; Type: TABLE; Schema: public; Owner: wxu_school
--

CREATE TABLE public.wx_moyennes_validation_gradelevel (
    wx_moyenne_validation_gradelevel_id public.uuid_type NOT NULL,
    school_gradelevels_id public.uuid_type NOT NULL,
    moyenne double precision NOT NULL,
    syear numeric(4,0)
);


ALTER TABLE public.wx_moyennes_validation_gradelevel OWNER TO wxu_school;

--
-- Name: wx_notes_details; Type: TABLE; Schema: public; Owner: wxu_school
--

CREATE TABLE public.wx_notes_details (
    id_notes_details public.uuid_type NOT NULL,
    type_dev character varying(255) NOT NULL,
    numero_dev integer NOT NULL,
    course_period_id public.uuid_type NOT NULL,
    mounth character varying(3) NOT NULL,
    discipline integer NOT NULL,
    date_dev timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE public.wx_notes_details OWNER TO wxu_school;

--
-- Name: wx_notes_student_details; Type: TABLE; Schema: public; Owner: wxu_school
--

CREATE TABLE public.wx_notes_student_details (
    id_notes_student_details public.uuid_type NOT NULL,
    wx_course_periods_subjects_id public.uuid_type NOT NULL,
    type_dev character varying(255) NOT NULL,
    numero_dev integer NOT NULL,
    student_id public.uuid_type NOT NULL,
    course_period_id public.uuid_type NOT NULL,
    mounth character varying(3) NOT NULL,
    discipline integer NOT NULL,
    note double precision
);


ALTER TABLE public.wx_notes_student_details OWNER TO wxu_school;

--
-- Name: wx_reduction_eleve; Type: TABLE; Schema: public; Owner: wxu_school
--

CREATE TABLE public.wx_reduction_eleve (
    id public.uuid_type NOT NULL,
    school_id public.uuid_type NOT NULL,
    name character varying(255) NOT NULL,
    reduction numeric(5,2) NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.wx_reduction_eleve OWNER TO wxu_school;

--
-- Name: wx_reduction_members; Type: TABLE; Schema: public; Owner: wxu_school
--

CREATE TABLE public.wx_reduction_members (
    id public.uuid_type NOT NULL,
    reduction_id public.uuid_type NOT NULL,
    student_id public.uuid_type NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.wx_reduction_members OWNER TO wxu_school;

--
-- Name: wx_rules_school; Type: TABLE; Schema: public; Owner: wxu_school
--

CREATE TABLE public.wx_rules_school (
    wx_rule_school_id public.uuid_type NOT NULL,
    title character varying(255) NOT NULL,
    config_value text,
    year numeric(4,0),
    school_id public.uuid_type NOT NULL
);


ALTER TABLE public.wx_rules_school OWNER TO wxu_school;

--
-- Name: wx_teacher_attendance; Type: TABLE; Schema: public; Owner: wxu_school
--

CREATE TABLE public.wx_teacher_attendance (
    wx_teacher_attendance_id public.uuid_type NOT NULL,
    staff_id public.uuid_type NOT NULL,
    date date NOT NULL,
    start_time time without time zone NOT NULL,
    end_time time without time zone NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    done boolean DEFAULT true NOT NULL,
    comments text,
    hour_type character varying DEFAULT 'non_programmed'::character varying NOT NULL
);


ALTER TABLE public.wx_teacher_attendance OWNER TO wxu_school;

--
-- Name: wx_ues; Type: TABLE; Schema: public; Owner: wxu_school
--

CREATE TABLE public.wx_ues (
    ue_id public.uuid_type NOT NULL,
    title character varying(100),
    gradelevel_id public.uuid_type,
    is_required character(1) DEFAULT 'N'::bpchar,
    credit double precision,
    syear integer,
    school_id public.uuid_type,
    course_period_id public.uuid_type
);


ALTER TABLE public.wx_ues OWNER TO wxu_school;

--
-- Name: wx_ues_subjects; Type: TABLE; Schema: public; Owner: wxu_school
--

CREATE TABLE public.wx_ues_subjects (
    id uuid NOT NULL,
    wx_ues_subjects_subject_id_fkey_uuid uuid,
    wx_ues_subjects_ue_id_fkey_uuid uuid,
    subject_id uuid,
    ue_id uuid
);


ALTER TABLE public.wx_ues_subjects OWNER TO wxu_school;

--
-- Data for Name: access_log; Type: TABLE DATA; Schema: public; Owner: wxu_school
--

COPY public.access_log (access_log_id, syear, username, profile, login_time, ip_address, user_agent, status, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: accounting_categories; Type: TABLE DATA; Schema: public; Owner: wxu_school
--

COPY public.accounting_categories (accounting_category_id, school_id, title, short_name, type, sort_order, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: accounting_incomes; Type: TABLE DATA; Schema: public; Owner: wxu_school
--

COPY public.accounting_incomes (accounting_income_id, assigned_date, comments, title, category_id, amount, file_attached, school_id, syear, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: accounting_payments; Type: TABLE DATA; Schema: public; Owner: wxu_school
--

COPY public.accounting_payments (accounting_payment_id, syear, school_id, staff_id, title, category_id, amount, payment_date, comments, file_attached, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: accounting_salaries; Type: TABLE DATA; Schema: public; Owner: wxu_school
--

COPY public.accounting_salaries (accounting_salary_id, staff_id, assigned_date, due_date, comments, title, amount, file_attached, school_id, syear, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: address; Type: TABLE DATA; Schema: public; Owner: wxu_school
--

COPY public.address (address_id, house_no, direction, street, apt, zipcode, city, state, mail_street, mail_city, mail_state, mail_zipcode, address, mail_address, phone, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: address_field_categories; Type: TABLE DATA; Schema: public; Owner: wxu_school
--

COPY public.address_field_categories (address_field_category_id, title, sort_order, residence, mailing, bus, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: address_fields; Type: TABLE DATA; Schema: public; Owner: wxu_school
--

COPY public.address_fields (address_field_id, type, title, sort_order, select_options, category_id, required, default_selection, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: attendance_calendar; Type: TABLE DATA; Schema: public; Owner: wxu_school
--

COPY public.attendance_calendar (attendance_calendar_id, syear, school_id, school_date, minutes, block, created_at, updated_at, calendar_id) FROM stdin;
\.


--
-- Data for Name: attendance_calendars; Type: TABLE DATA; Schema: public; Owner: wxu_school
--

COPY public.attendance_calendars (calendar_id, school_id, title, syear, default_calendar, rollover_id, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: attendance_code_categories; Type: TABLE DATA; Schema: public; Owner: wxu_school
--

COPY public.attendance_code_categories (attendance_code_category_id, syear, school_id, title, sort_order, rollover_id, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: attendance_codes; Type: TABLE DATA; Schema: public; Owner: wxu_school
--

COPY public.attendance_codes (attendance_code_id, syear, school_id, title, short_name, type, state_code, default_code, table_name, sort_order, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: attendance_completed; Type: TABLE DATA; Schema: public; Owner: wxu_school
--

COPY public.attendance_completed (attendance_completed_id, staff_id, school_date, period_id, table_name, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: attendance_day; Type: TABLE DATA; Schema: public; Owner: wxu_school
--

COPY public.attendance_day (attendance_day_id, student_id, school_date, minutes_present, state_value, syear, marking_period_id, comment, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: attendance_period; Type: TABLE DATA; Schema: public; Owner: wxu_school
--

COPY public.attendance_period (attendance_period_id, student_id, school_date, period_id, attendance_code, attendance_teacher_code, attendance_reason, admin, course_period_id, marking_period_id, comment, created_at, updated_at, my_period_id) FROM stdin;
\.


--
-- Data for Name: billing_fees; Type: TABLE DATA; Schema: public; Owner: wxu_school
--

COPY public.billing_fees (billing_fee_id, student_id, assigned_date, due_date, comments, title, amount, file_attached, school_id, syear, waived_fee_id, created_at, updated_at, month) FROM stdin;
\.


--
-- Data for Name: billing_payments; Type: TABLE DATA; Schema: public; Owner: wxu_school
--

COPY public.billing_payments (billing_payment_id, syear, school_id, student_id, amount, payment_date, comments, refunded_payment_id, lunch_payment, file_attached, created_at, updated_at, month, intitule_caissier, imprimer) FROM stdin;
\.


--
-- Data for Name: bordereaux_details; Type: TABLE DATA; Schema: public; Owner: wxu_school
--

COPY public.bordereaux_details (id, staff_id, month, year, autres_cycles, indemnites_responsabilite, prime_transport, prime_salissure, prime_encouragement, prime_anciennete, enfant_charge, assurances, autres, acomptes, cnss_employeur, cnss_employe, irpp_employe, net_payer, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: calendar_events; Type: TABLE DATA; Schema: public; Owner: wxu_school
--

COPY public.calendar_events (calendar_event_id, syear, school_id, school_date, title, description, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: config; Type: TABLE DATA; Schema: public; Owner: wxu_school
--

COPY public.config (config_id, title, config_value, created_at, updated_at, school_id) FROM stdin;
\.


--
-- Data for Name: course_period_school_periods; Type: TABLE DATA; Schema: public; Owner: wxu_school
--

COPY public.course_period_school_periods (course_period_school_periods_id, course_period_id, period_id, days, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: course_periods; Type: TABLE DATA; Schema: public; Owner: wxu_school
--

COPY public.course_periods (course_period_id, syear, school_id, course_id, title, short_name, mp, marking_period_id, teacher_id, secondary_teacher_id, room, total_seats, filled_seats, does_attendance, does_honor_roll, does_class_rank, gender_restriction, house_restriction, availability, parent_id, calendar_id, half_day, does_breakoff, rollover_id, grade_scale_id, credits, created_at, updated_at, echelle_notation, semester_type, frais_classe, total_mentant) FROM stdin;
\.


--
-- Data for Name: course_subjects; Type: TABLE DATA; Schema: public; Owner: wxu_school
--

COPY public.course_subjects (subject_id, syear, school_id, title, short_name, sort_order, rollover_id, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: courses; Type: TABLE DATA; Schema: public; Owner: wxu_school
--

COPY public.courses (course_id, syear, subject_id, school_id, title, short_name, rollover_id, credit_hours, description, created_at, updated_at, grade_level) FROM stdin;
\.


--
-- Data for Name: custom_fields; Type: TABLE DATA; Schema: public; Owner: wxu_school
--

COPY public.custom_fields (custom_field_id, type, title, sort_order, select_options, category_id, required, default_selection, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: discipline_field_usage; Type: TABLE DATA; Schema: public; Owner: wxu_school
--

COPY public.discipline_field_usage (discipline_field_usage_id, discipline_field_id, syear, school_id, title, select_options, sort_order, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: discipline_fields; Type: TABLE DATA; Schema: public; Owner: wxu_school
--

COPY public.discipline_fields (discipline_field_id, title, short_name, data_type, column_name, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: discipline_referrals; Type: TABLE DATA; Schema: public; Owner: wxu_school
--

COPY public.discipline_referrals (discipline_referral_id, syear, student_id, school_id, staff_id, entry_date, referral_date, category_1, category_2, category_3, category_4, category_5, category_6, created_at, updated_at, category_7) FROM stdin;
\.


--
-- Data for Name: eligibility; Type: TABLE DATA; Schema: public; Owner: wxu_school
--

COPY public.eligibility (eligibility_id, student_id, syear, school_date, period_id, eligibility_code, course_period_id, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: eligibility_activities; Type: TABLE DATA; Schema: public; Owner: wxu_school
--

COPY public.eligibility_activities (eligibility_activity_id, syear, school_id, title, start_date, end_date, comment, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: eligibility_completed; Type: TABLE DATA; Schema: public; Owner: wxu_school
--

COPY public.eligibility_completed (eligibility_completed_id, staff_id, school_date, period_id, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: food_service_accounts; Type: TABLE DATA; Schema: public; Owner: wxu_school
--

COPY public.food_service_accounts (account_id, balance, transaction_id, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: food_service_categories; Type: TABLE DATA; Schema: public; Owner: wxu_school
--

COPY public.food_service_categories (category_id, school_id, menu_id, title, sort_order, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: food_service_items; Type: TABLE DATA; Schema: public; Owner: wxu_school
--

COPY public.food_service_items (item_id, school_id, short_name, sort_order, description, icon, price, price_reduced, price_free, price_staff, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: food_service_menu_items; Type: TABLE DATA; Schema: public; Owner: wxu_school
--

COPY public.food_service_menu_items (menu_item_id, school_id, menu_id, item_id, category_id, sort_order, does_count, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: food_service_menus; Type: TABLE DATA; Schema: public; Owner: wxu_school
--

COPY public.food_service_menus (menu_id, school_id, title, sort_order, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: food_service_staff_accounts; Type: TABLE DATA; Schema: public; Owner: wxu_school
--

COPY public.food_service_staff_accounts (staff_account_id, staff_id, status, barcode, balance, transaction_id, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: food_service_staff_transaction_items; Type: TABLE DATA; Schema: public; Owner: wxu_school
--

COPY public.food_service_staff_transaction_items (staff_transaction_item_id, item_id, transaction_id, amount, short_name, description, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: food_service_staff_transactions; Type: TABLE DATA; Schema: public; Owner: wxu_school
--

COPY public.food_service_staff_transactions (transaction_id, staff_id, school_id, syear, balance, "timestamp", short_name, description, seller_id, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: food_service_student_accounts; Type: TABLE DATA; Schema: public; Owner: wxu_school
--

COPY public.food_service_student_accounts (student_account_id, student_id, account_id, discount, status, barcode, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: food_service_transaction_items; Type: TABLE DATA; Schema: public; Owner: wxu_school
--

COPY public.food_service_transaction_items (transaction_item_id, item_id, transaction_id, amount, discount, short_name, description, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: food_service_transactions; Type: TABLE DATA; Schema: public; Owner: wxu_school
--

COPY public.food_service_transactions (transaction_id, account_id, student_id, school_id, syear, discount, balance, "timestamp", short_name, description, seller_id, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: grade_levels; Type: TABLE DATA; Schema: public; Owner: wxu_school
--

COPY public.grade_levels (grade_level_id, title, sort_order) FROM stdin;
\.


--
-- Data for Name: gradebook_assignment_types; Type: TABLE DATA; Schema: public; Owner: wxu_school
--

COPY public.gradebook_assignment_types (assignment_type_id, staff_id, course_id, title, final_grade_percent, sort_order, color, created_mp, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: gradebook_assignments; Type: TABLE DATA; Schema: public; Owner: wxu_school
--

COPY public.gradebook_assignments (assignment_id, staff_id, marking_period_id, course_period_id, course_id, assignment_type_id, title, assigned_date, due_date, points, description, file, default_points, submission, weight, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: gradebook_grades; Type: TABLE DATA; Schema: public; Owner: wxu_school
--

COPY public.gradebook_grades (gradebook_grade_id, student_id, period_id, course_period_id, assignment_id, points, comment, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: grades_completed; Type: TABLE DATA; Schema: public; Owner: wxu_school
--

COPY public.grades_completed (grades_completed_id, staff_id, marking_period_id, course_period_id, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: history_marking_periods; Type: TABLE DATA; Schema: public; Owner: wxu_school
--

COPY public.history_marking_periods (history_marking_period_id, parent_id, mp_type, name, short_name, post_end_date, school_id, syear, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: lunch_period; Type: TABLE DATA; Schema: public; Owner: wxu_school
--

COPY public.lunch_period (lunch_period_id, student_id, school_date, period_id, attendance_code, attendance_teacher_code, attendance_reason, admin, course_period_id, marking_period_id, comment, table_name, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: messages; Type: TABLE DATA; Schema: public; Owner: wxu_school
--

COPY public.messages (message_id, syear, school_id, "from", recipients, subject, data, created_at) FROM stdin;
\.


--
-- Data for Name: messagexuser; Type: TABLE DATA; Schema: public; Owner: wxu_school
--

COPY public.messagexuser (messagexuser_id, user_id, key, message_id, status) FROM stdin;
\.


--
-- Data for Name: moodlexrosario; Type: TABLE DATA; Schema: public; Owner: wxu_school
--

COPY public.moodlexrosario (moodlexrosario_id, "column", rosario_id, moodle_id, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: people; Type: TABLE DATA; Schema: public; Owner: wxu_school
--

COPY public.people (person_id, last_name, first_name, middle_name, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: people_field_categories; Type: TABLE DATA; Schema: public; Owner: wxu_school
--

COPY public.people_field_categories (people_field_category_id, title, sort_order, custody, emergency, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: people_fields; Type: TABLE DATA; Schema: public; Owner: wxu_school
--

COPY public.people_fields (people_field_id, type, title, sort_order, select_options, category_id, required, default_selection, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: people_join_contacts; Type: TABLE DATA; Schema: public; Owner: wxu_school
--

COPY public.people_join_contacts (people_join_contact_id, person_id, title, value, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: portal_notes; Type: TABLE DATA; Schema: public; Owner: wxu_school
--

COPY public.portal_notes (portal_note_id, school_id, syear, title, content, sort_order, published_user, published_date, start_date, end_date, published_profiles, file_attached, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: portal_poll_questions; Type: TABLE DATA; Schema: public; Owner: wxu_school
--

COPY public.portal_poll_questions (portal_poll_question_id, portal_poll_id, question, type, options, votes, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: portal_polls; Type: TABLE DATA; Schema: public; Owner: wxu_school
--

COPY public.portal_polls (portal_poll_id, school_id, syear, title, votes_number, display_votes, sort_order, published_user, published_date, start_date, end_date, published_profiles, students_teacher_id, excluded_users, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: profile_exceptions; Type: TABLE DATA; Schema: public; Owner: wxu_school
--

COPY public.profile_exceptions (profile_exception_id, profile_id, modname, can_use, can_edit, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: program_config; Type: TABLE DATA; Schema: public; Owner: wxu_school
--

COPY public.program_config (program_config_id, syear, school_id, program, title, value, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: program_user_config; Type: TABLE DATA; Schema: public; Owner: wxu_school
--

COPY public.program_user_config (program_user_config_id, user_id, program, title, value, school_id, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: report_card_comment_categories; Type: TABLE DATA; Schema: public; Owner: wxu_school
--

COPY public.report_card_comment_categories (report_card_comment_category_id, syear, school_id, course_id, sort_order, title, rollover_id, color, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: report_card_comment_code_scales; Type: TABLE DATA; Schema: public; Owner: wxu_school
--

COPY public.report_card_comment_code_scales (report_card_comment_code_scale_id, school_id, title, comment, sort_order, rollover_id, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: report_card_comment_codes; Type: TABLE DATA; Schema: public; Owner: wxu_school
--

COPY public.report_card_comment_codes (report_card_comment_code_id, school_id, scale_id, title, short_name, comment, sort_order, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: report_card_comments; Type: TABLE DATA; Schema: public; Owner: wxu_school
--

COPY public.report_card_comments (report_card_comment_id, syear, school_id, course_id, category_id, scale_id, sort_order, title, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: report_card_grade_scales; Type: TABLE DATA; Schema: public; Owner: wxu_school
--

COPY public.report_card_grade_scales (report_card_grade_scale_id, syear, school_id, title, comment, hhr_gpa_value, hr_gpa_value, sort_order, rollover_id, gp_scale, gp_passing_value, hrs_gpa_value, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: report_card_grades; Type: TABLE DATA; Schema: public; Owner: wxu_school
--

COPY public.report_card_grades (report_card_grade_id, syear, school_id, title, sort_order, gpa_value, break_off, comment, grade_scale_id, unweighted_gp, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: resources; Type: TABLE DATA; Schema: public; Owner: wxu_school
--

COPY public.resources (resource_id, school_id, title, link, published_profiles, published_grade_levels, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: schedule; Type: TABLE DATA; Schema: public; Owner: wxu_school
--

COPY public.schedule (schedule_id, syear, school_id, student_id, start_date, end_date, modified_date, modified_by, course_id, course_period_id, mp, marking_period_id, scheduler_lock, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: schedule_requests; Type: TABLE DATA; Schema: public; Owner: wxu_school
--

COPY public.schedule_requests (schedule_request_id, syear, school_id, student_id, subject_id, course_id, marking_period_id, priority, with_teacher_id, not_teacher_id, with_period_id, not_period_id, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: school_fields; Type: TABLE DATA; Schema: public; Owner: wxu_school
--

COPY public.school_fields (school_field_id, type, title, sort_order, select_options, required, default_selection, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: school_gradelevels; Type: TABLE DATA; Schema: public; Owner: wxu_school
--

COPY public.school_gradelevels (gradelevel_id, school_id, short_name, title, next_grade_id, sort_order, created_at, updated_at, marking_period_type) FROM stdin;
\.


--
-- Data for Name: school_marking_periods; Type: TABLE DATA; Schema: public; Owner: wxu_school
--

COPY public.school_marking_periods (marking_period_id, syear, mp, school_id, parent_id, title, short_name, sort_order, start_date, end_date, post_start_date, post_end_date, does_grades, does_comments, rollover_id, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: school_periods; Type: TABLE DATA; Schema: public; Owner: wxu_school
--

COPY public.school_periods (period_id, syear, school_id, sort_order, title, short_name, length, start_time, end_time, block, attendance, rollover_id, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: schools; Type: TABLE DATA; Schema: public; Owner: wxu_school
--

COPY public.schools (school_id, syear, title, address, city, state, zipcode, phone, principal, www_address, school_number, short_name, reporting_gp_scale, number_days_rotation, created_at, updated_at) FROM stdin;
eb8eb2cb-f066-4839-975a-917b49e0c985	2025	ECOLE EDUVERSE	64 Rue Mpangala	Ouénzé Brazzaville	POOL	75001	\N	M. Principal	\N	1	ECOLE MODELE	20.000	1	2023-08-22 19:19:27.310741	2025-10-08 10:04:32.039041
\.


--
-- Data for Name: staff; Type: TABLE DATA; Schema: public; Owner: wxu_school
--

COPY public.staff (staff_id, syear, current_school_id, title, first_name, last_name, middle_name, name_suffix, username, password, email, custom_200000001, profile, homeroom, schools, last_login, failed_login, rollover_id, created_at, updated_at, custom_200000002, custom_200000003, custom_200000004, custom_200000005, a_salaire_fixe, salaire_fixe, date_debut_contrat, date_fin_contrat, profile_id) FROM stdin;
212cb471-1d18-485c-bf86-ba4cc1762922	2025	eb8eb2cb-f066-4839-975a-917b49e0c985	Mr	Super	Admin	\N	\N	admin	$6$8feef8e679ca880d$JpsUJKuSu7v5FUEo25np1/eWKzUTwA5M5SlrfsKX0rX7psiFP6YwW0pNUvnspRXgYahhLKB2EefIroNm5ocSH/	\N	\N	admin	\N	,eb8eb2cb-f066-4839-975a-917b49e0c985,16,17,18,19,1961-10-18,	2025-09-17 13:21:55.33511	\N	eb8eb2cb-f066-4839-975a-917b49e0c985	2023-08-01 22:43:31.104393	2025-10-08 10:04:35.924045	\N	\N	\N	1961-10-18	\N	\N	\N	\N	c857fcdb-26f6-4da5-b358-9d4cf43ea1e2
\.


--
-- Data for Name: staff_exceptions; Type: TABLE DATA; Schema: public; Owner: wxu_school
--

COPY public.staff_exceptions (staff_exception_id, user_id, modname, can_use, can_edit, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: staff_field_categories; Type: TABLE DATA; Schema: public; Owner: wxu_school
--

COPY public.staff_field_categories (staff_field_category_id, title, sort_order, columns, include, admin, teacher, parent, "none", created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: staff_fields; Type: TABLE DATA; Schema: public; Owner: wxu_school
--

COPY public.staff_fields (staff_field_id, type, title, sort_order, select_options, category_id, required, default_selection, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: student_assignments; Type: TABLE DATA; Schema: public; Owner: wxu_school
--

COPY public.student_assignments (student_assignment_id, assignment_id, student_id, data, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: student_eligibility_activities; Type: TABLE DATA; Schema: public; Owner: wxu_school
--

COPY public.student_eligibility_activities (student_eligibility_activity_id, syear, student_id, activity_id, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: student_enrollment; Type: TABLE DATA; Schema: public; Owner: wxu_school
--

COPY public.student_enrollment (enrollment_id, syear, school_id, student_id, grade_id, start_date, end_date, next_school, calendar_id, last_school, created_at, updated_at, second_course_period_id, semester, second_semester, course_period_id, second_grade_id, enrollment_code, drop_code) FROM stdin;
\.


--
-- Data for Name: student_enrollment_codes; Type: TABLE DATA; Schema: public; Owner: wxu_school
--

COPY public.student_enrollment_codes (student_enrollment_code_id, syear, title, short_name, type, default_code, sort_order, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: student_enrollment_course_periods; Type: TABLE DATA; Schema: public; Owner: wxu_school
--

COPY public.student_enrollment_course_periods (student_enrollment_course_period_id, student_enrollment_id, course_period_id, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: student_field_categories; Type: TABLE DATA; Schema: public; Owner: wxu_school
--

COPY public.student_field_categories (student_field_category_id, title, sort_order, columns, include, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: student_medical; Type: TABLE DATA; Schema: public; Owner: wxu_school
--

COPY public.student_medical (student_medical_id, student_id, type, medical_date, comments, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: student_medical_alerts; Type: TABLE DATA; Schema: public; Owner: wxu_school
--

COPY public.student_medical_alerts (student_medical_alert_id, student_id, title, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: student_medical_visits; Type: TABLE DATA; Schema: public; Owner: wxu_school
--

COPY public.student_medical_visits (student_medical_visit_id, student_id, school_date, time_in, time_out, reason, result, comments, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: student_mp_comments; Type: TABLE DATA; Schema: public; Owner: wxu_school
--

COPY public.student_mp_comments (student_mp_comment_id, student_id, syear, marking_period_id, comment, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: student_mp_stats; Type: TABLE DATA; Schema: public; Owner: wxu_school
--

COPY public.student_mp_stats (student_mp_stat_id, student_id, marking_period_id, cum_weighted_factor, cum_unweighted_factor, cum_rank, mp_rank, class_size, sum_weighted_factors, sum_unweighted_factors, count_weighted_factors, count_unweighted_factors, grade_level_short, cr_weighted_factors, cr_unweighted_factors, count_cr_factors, cum_cr_weighted_factor, cum_cr_unweighted_factor, credit_attempted, credit_earned, gp_credits, cr_credits, comments, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: student_report_card_comments; Type: TABLE DATA; Schema: public; Owner: wxu_school
--

COPY public.student_report_card_comments (student_report_card_comment_id, syear, school_id, student_id, course_period_id, comment, marking_period_id, created_at, updated_at, report_card_comment_id) FROM stdin;
\.


--
-- Data for Name: student_report_card_grades; Type: TABLE DATA; Schema: public; Owner: wxu_school
--

COPY public.student_report_card_grades (student_report_card_grade_id, syear, school_id, student_id, course_period_id, report_card_grade_id, report_card_comment_id, comment, grade_percent, marking_period_id, grade_letter, weighted_gp, unweighted_gp, gp_scale, credit_attempted, credit_earned, credit_category, course_title, school, class_rank, credit_hours, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: students; Type: TABLE DATA; Schema: public; Owner: wxu_school
--

COPY public.students (student_id, last_name, first_name, middle_name, name_suffix, username, password, last_login, failed_login, custom_200000000, custom_200000001, custom_200000002, custom_200000003, custom_200000004, custom_200000005, custom_200000006, custom_200000007, custom_200000008, custom_200000009, custom_200000010, custom_200000011, created_at, updated_at, frais_inscriptions, reinscription) FROM stdin;
\.


--
-- Data for Name: students_join_address; Type: TABLE DATA; Schema: public; Owner: wxu_school
--

COPY public.students_join_address (student_join_address_id, student_id, address_id, contact_seq, gets_mail, primary_residence, legal_residence, am_bus, pm_bus, mailing, residence, bus, bus_pickup, bus_dropoff, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: students_join_people; Type: TABLE DATA; Schema: public; Owner: wxu_school
--

COPY public.students_join_people (student_join_people_id, student_id, person_id, address_id, custody, emergency, student_relation, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: students_join_users; Type: TABLE DATA; Schema: public; Owner: wxu_school
--

COPY public.students_join_users (student_join_user_id, student_id, staff_id, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: templates; Type: TABLE DATA; Schema: public; Owner: wxu_school
--

COPY public.templates (template_id, modname, staff_id, template, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: user_profiles; Type: TABLE DATA; Schema: public; Owner: wxu_school
--

COPY public.user_profiles (profile, title, created_at, updated_at, id) FROM stdin;
admin	Admin	2025-10-16 14:55:35.331031	\N	c857fcdb-26f6-4da5-b358-9d4cf43ea1e2
\.


--
-- Data for Name: wx_appreciations; Type: TABLE DATA; Schema: public; Owner: wxu_school
--

COPY public.wx_appreciations (wx_appreciation_id, grade_id, appreciation, note_1, note_2) FROM stdin;
\.


--
-- Data for Name: wx_config_publication_resultats; Type: TABLE DATA; Schema: public; Owner: wxu_school
--

COPY public.wx_config_publication_resultats (wx_config_publication_resultat_id, school_gradelevels_id, period, valeur, syear) FROM stdin;
\.


--
-- Data for Name: wx_course_periods_gradelevels; Type: TABLE DATA; Schema: public; Owner: wxu_school
--

COPY public.wx_course_periods_gradelevels (wx_course_periods_gradelevels_id, course_periods_id, school_gradelevels_id) FROM stdin;
\.


--
-- Data for Name: wx_course_periods_subjects; Type: TABLE DATA; Schema: public; Owner: wxu_school
--

COPY public.wx_course_periods_subjects (wx_course_periods_subjects_id, course_periods_id, course_subjects_id, coefficient, teacher_id, secondary_teacher_id, created_at, updated_at, ue_id, period_position, taux_horaires, ue_compensation) FROM stdin;
\.


--
-- Data for Name: wx_course_periods_subjects_periods; Type: TABLE DATA; Schema: public; Owner: wxu_school
--

COPY public.wx_course_periods_subjects_periods (wx_course_periods_subjects_periods_id, wx_course_periods_subjects_id, day, start_time, end_time) FROM stdin;
\.


--
-- Data for Name: wx_course_subjects_gradelevels; Type: TABLE DATA; Schema: public; Owner: wxu_school
--

COPY public.wx_course_subjects_gradelevels (wx_course_subjects_gradelevels_id, course_subjects_id, school_gradelevels_id, coefficient, semester_type) FROM stdin;
\.


--
-- Data for Name: wx_custom_configuration_school; Type: TABLE DATA; Schema: public; Owner: wxu_school
--

COPY public.wx_custom_configuration_school (id_custom_configuration_school, school_id, type_school) FROM stdin;
\.


--
-- Data for Name: wx_echelle_notation_appreciation; Type: TABLE DATA; Schema: public; Owner: wxu_school
--

COPY public.wx_echelle_notation_appreciation (wx_echelle_notation_appreciation_id, note_debut, note_fin, echelle_notation, appreciation, year, school_id) FROM stdin;
\.


--
-- Data for Name: wx_families; Type: TABLE DATA; Schema: public; Owner: wxu_school
--

COPY public.wx_families (wx_family_id, name, amount, school_id, syear, created_at) FROM stdin;
\.


--
-- Data for Name: wx_family_members; Type: TABLE DATA; Schema: public; Owner: wxu_school
--

COPY public.wx_family_members (wx_family_member_id, family_id, student_id, is_representative) FROM stdin;
\.


--
-- Data for Name: wx_gradel_period_evaluation; Type: TABLE DATA; Schema: public; Owner: wxu_school
--

COPY public.wx_gradel_period_evaluation (id_gradel_period_evaluation, school_gradelevels_id, type_period_evaluation, year, allow_debt_passage, debt_passage_percentage, eliminatory_note, debt_passage_percentage_devoir, debt_passage_percentage_session, eliminatory_mark, is_passage_with_debt, percentage_of_credit_for_passage, is_compensable) FROM stdin;
\.


--
-- Data for Name: wx_moyennes_finales_students; Type: TABLE DATA; Schema: public; Owner: wxu_school
--

COPY public.wx_moyennes_finales_students (wx_moyenne_finale_student_id, student_enrollment_id, moyenne, exam_type) FROM stdin;
\.


--
-- Data for Name: wx_moyennes_validation_gradelevel; Type: TABLE DATA; Schema: public; Owner: wxu_school
--

COPY public.wx_moyennes_validation_gradelevel (wx_moyenne_validation_gradelevel_id, school_gradelevels_id, moyenne, syear) FROM stdin;
\.


--
-- Data for Name: wx_notes_details; Type: TABLE DATA; Schema: public; Owner: wxu_school
--

COPY public.wx_notes_details (id_notes_details, type_dev, numero_dev, course_period_id, mounth, discipline, date_dev) FROM stdin;
\.


--
-- Data for Name: wx_notes_student_details; Type: TABLE DATA; Schema: public; Owner: wxu_school
--

COPY public.wx_notes_student_details (id_notes_student_details, wx_course_periods_subjects_id, type_dev, numero_dev, student_id, course_period_id, mounth, discipline, note) FROM stdin;
\.


--
-- Data for Name: wx_reduction_eleve; Type: TABLE DATA; Schema: public; Owner: wxu_school
--

COPY public.wx_reduction_eleve (id, school_id, name, reduction, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: wx_reduction_members; Type: TABLE DATA; Schema: public; Owner: wxu_school
--

COPY public.wx_reduction_members (id, reduction_id, student_id, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: wx_rules_school; Type: TABLE DATA; Schema: public; Owner: wxu_school
--

COPY public.wx_rules_school (wx_rule_school_id, title, config_value, year, school_id) FROM stdin;
\.


--
-- Data for Name: wx_teacher_attendance; Type: TABLE DATA; Schema: public; Owner: wxu_school
--

COPY public.wx_teacher_attendance (wx_teacher_attendance_id, staff_id, date, start_time, end_time, created_at, done, comments, hour_type) FROM stdin;
\.


--
-- Data for Name: wx_ues; Type: TABLE DATA; Schema: public; Owner: wxu_school
--

COPY public.wx_ues (ue_id, title, gradelevel_id, is_required, credit, syear, school_id, course_period_id) FROM stdin;
\.


--
-- Data for Name: wx_ues_subjects; Type: TABLE DATA; Schema: public; Owner: wxu_school
--

COPY public.wx_ues_subjects (id, wx_ues_subjects_subject_id_fkey_uuid, wx_ues_subjects_ue_id_fkey_uuid, subject_id, ue_id) FROM stdin;
\.


--
-- Name: access_log access_log_pkey; Type: CONSTRAINT; Schema: public; Owner: wxu_school
--

ALTER TABLE ONLY public.access_log
    ADD CONSTRAINT access_log_pkey PRIMARY KEY (access_log_id);


--
-- Name: accounting_categories accounting_categories_pkey; Type: CONSTRAINT; Schema: public; Owner: wxu_school
--

ALTER TABLE ONLY public.accounting_categories
    ADD CONSTRAINT accounting_categories_pkey PRIMARY KEY (accounting_category_id);


--
-- Name: accounting_incomes accounting_incomes_pkey; Type: CONSTRAINT; Schema: public; Owner: wxu_school
--

ALTER TABLE ONLY public.accounting_incomes
    ADD CONSTRAINT accounting_incomes_pkey PRIMARY KEY (accounting_income_id);


--
-- Name: accounting_payments accounting_payments_pkey; Type: CONSTRAINT; Schema: public; Owner: wxu_school
--

ALTER TABLE ONLY public.accounting_payments
    ADD CONSTRAINT accounting_payments_pkey PRIMARY KEY (accounting_payment_id);


--
-- Name: accounting_salaries accounting_salaries_pkey; Type: CONSTRAINT; Schema: public; Owner: wxu_school
--

ALTER TABLE ONLY public.accounting_salaries
    ADD CONSTRAINT accounting_salaries_pkey PRIMARY KEY (accounting_salary_id);


--
-- Name: address_field_categories address_field_categories_pkey; Type: CONSTRAINT; Schema: public; Owner: wxu_school
--

ALTER TABLE ONLY public.address_field_categories
    ADD CONSTRAINT address_field_categories_pkey PRIMARY KEY (address_field_category_id);


--
-- Name: address_fields address_fields_pkey; Type: CONSTRAINT; Schema: public; Owner: wxu_school
--

ALTER TABLE ONLY public.address_fields
    ADD CONSTRAINT address_fields_pkey PRIMARY KEY (address_field_id);


--
-- Name: address address_pkey; Type: CONSTRAINT; Schema: public; Owner: wxu_school
--

ALTER TABLE ONLY public.address
    ADD CONSTRAINT address_pkey PRIMARY KEY (address_id);


--
-- Name: attendance_calendar attendance_calendar_pkey; Type: CONSTRAINT; Schema: public; Owner: wxu_school
--

ALTER TABLE ONLY public.attendance_calendar
    ADD CONSTRAINT attendance_calendar_pkey PRIMARY KEY (attendance_calendar_id);


--
-- Name: attendance_calendars attendance_calendars_pkey; Type: CONSTRAINT; Schema: public; Owner: wxu_school
--

ALTER TABLE ONLY public.attendance_calendars
    ADD CONSTRAINT attendance_calendars_pkey PRIMARY KEY (calendar_id);


--
-- Name: attendance_code_categories attendance_code_categories_pkey; Type: CONSTRAINT; Schema: public; Owner: wxu_school
--

ALTER TABLE ONLY public.attendance_code_categories
    ADD CONSTRAINT attendance_code_categories_pkey PRIMARY KEY (attendance_code_category_id);


--
-- Name: attendance_codes attendance_codes_pkey; Type: CONSTRAINT; Schema: public; Owner: wxu_school
--

ALTER TABLE ONLY public.attendance_codes
    ADD CONSTRAINT attendance_codes_pkey PRIMARY KEY (attendance_code_id);


--
-- Name: attendance_completed attendance_completed_pkey; Type: CONSTRAINT; Schema: public; Owner: wxu_school
--

ALTER TABLE ONLY public.attendance_completed
    ADD CONSTRAINT attendance_completed_pkey PRIMARY KEY (attendance_completed_id);


--
-- Name: attendance_day attendance_day_pkey; Type: CONSTRAINT; Schema: public; Owner: wxu_school
--

ALTER TABLE ONLY public.attendance_day
    ADD CONSTRAINT attendance_day_pkey PRIMARY KEY (attendance_day_id);


--
-- Name: attendance_period attendance_period_pkey; Type: CONSTRAINT; Schema: public; Owner: wxu_school
--

ALTER TABLE ONLY public.attendance_period
    ADD CONSTRAINT attendance_period_pkey PRIMARY KEY (attendance_period_id);


--
-- Name: billing_fees billing_fees_pkey; Type: CONSTRAINT; Schema: public; Owner: wxu_school
--

ALTER TABLE ONLY public.billing_fees
    ADD CONSTRAINT billing_fees_pkey PRIMARY KEY (billing_fee_id);


--
-- Name: billing_payments billing_payments_pkey; Type: CONSTRAINT; Schema: public; Owner: wxu_school
--

ALTER TABLE ONLY public.billing_payments
    ADD CONSTRAINT billing_payments_pkey PRIMARY KEY (billing_payment_id);


--
-- Name: bordereaux_details bordereaux_details_pkey; Type: CONSTRAINT; Schema: public; Owner: wxu_school
--

ALTER TABLE ONLY public.bordereaux_details
    ADD CONSTRAINT bordereaux_details_pkey PRIMARY KEY (id);


--
-- Name: calendar_events calendar_events_pkey; Type: CONSTRAINT; Schema: public; Owner: wxu_school
--

ALTER TABLE ONLY public.calendar_events
    ADD CONSTRAINT calendar_events_pkey PRIMARY KEY (calendar_event_id);


--
-- Name: config config_pkey; Type: CONSTRAINT; Schema: public; Owner: wxu_school
--

ALTER TABLE ONLY public.config
    ADD CONSTRAINT config_pkey PRIMARY KEY (config_id);


--
-- Name: course_period_school_periods course_period_school_periods_pkey; Type: CONSTRAINT; Schema: public; Owner: wxu_school
--

ALTER TABLE ONLY public.course_period_school_periods
    ADD CONSTRAINT course_period_school_periods_pkey PRIMARY KEY (course_period_school_periods_id);


--
-- Name: course_periods course_periods_pkey; Type: CONSTRAINT; Schema: public; Owner: wxu_school
--

ALTER TABLE ONLY public.course_periods
    ADD CONSTRAINT course_periods_pkey PRIMARY KEY (course_period_id);


--
-- Name: course_subjects course_subjects_pkey; Type: CONSTRAINT; Schema: public; Owner: wxu_school
--

ALTER TABLE ONLY public.course_subjects
    ADD CONSTRAINT course_subjects_pkey PRIMARY KEY (subject_id);


--
-- Name: courses courses_pkey; Type: CONSTRAINT; Schema: public; Owner: wxu_school
--

ALTER TABLE ONLY public.courses
    ADD CONSTRAINT courses_pkey PRIMARY KEY (course_id);


--
-- Name: custom_fields custom_fields_pkey; Type: CONSTRAINT; Schema: public; Owner: wxu_school
--

ALTER TABLE ONLY public.custom_fields
    ADD CONSTRAINT custom_fields_pkey PRIMARY KEY (custom_field_id);


--
-- Name: discipline_field_usage discipline_field_usage_pkey; Type: CONSTRAINT; Schema: public; Owner: wxu_school
--

ALTER TABLE ONLY public.discipline_field_usage
    ADD CONSTRAINT discipline_field_usage_pkey PRIMARY KEY (discipline_field_usage_id);


--
-- Name: discipline_fields discipline_fields_pkey; Type: CONSTRAINT; Schema: public; Owner: wxu_school
--

ALTER TABLE ONLY public.discipline_fields
    ADD CONSTRAINT discipline_fields_pkey PRIMARY KEY (discipline_field_id);


--
-- Name: discipline_referrals discipline_referrals_pkey; Type: CONSTRAINT; Schema: public; Owner: wxu_school
--

ALTER TABLE ONLY public.discipline_referrals
    ADD CONSTRAINT discipline_referrals_pkey PRIMARY KEY (discipline_referral_id);


--
-- Name: eligibility_activities eligibility_activities_pkey; Type: CONSTRAINT; Schema: public; Owner: wxu_school
--

ALTER TABLE ONLY public.eligibility_activities
    ADD CONSTRAINT eligibility_activities_pkey PRIMARY KEY (eligibility_activity_id);


--
-- Name: eligibility_completed eligibility_completed_pkey; Type: CONSTRAINT; Schema: public; Owner: wxu_school
--

ALTER TABLE ONLY public.eligibility_completed
    ADD CONSTRAINT eligibility_completed_pkey PRIMARY KEY (eligibility_completed_id);


--
-- Name: eligibility eligibility_pkey; Type: CONSTRAINT; Schema: public; Owner: wxu_school
--

ALTER TABLE ONLY public.eligibility
    ADD CONSTRAINT eligibility_pkey PRIMARY KEY (eligibility_id);


--
-- Name: food_service_accounts food_service_accounts_pkey; Type: CONSTRAINT; Schema: public; Owner: wxu_school
--

ALTER TABLE ONLY public.food_service_accounts
    ADD CONSTRAINT food_service_accounts_pkey PRIMARY KEY (account_id);


--
-- Name: food_service_categories food_service_categories_pkey; Type: CONSTRAINT; Schema: public; Owner: wxu_school
--

ALTER TABLE ONLY public.food_service_categories
    ADD CONSTRAINT food_service_categories_pkey PRIMARY KEY (category_id);


--
-- Name: food_service_items food_service_items_pkey; Type: CONSTRAINT; Schema: public; Owner: wxu_school
--

ALTER TABLE ONLY public.food_service_items
    ADD CONSTRAINT food_service_items_pkey PRIMARY KEY (item_id);


--
-- Name: food_service_menu_items food_service_menu_items_pkey; Type: CONSTRAINT; Schema: public; Owner: wxu_school
--

ALTER TABLE ONLY public.food_service_menu_items
    ADD CONSTRAINT food_service_menu_items_pkey PRIMARY KEY (menu_item_id);


--
-- Name: food_service_menus food_service_menus_pkey; Type: CONSTRAINT; Schema: public; Owner: wxu_school
--

ALTER TABLE ONLY public.food_service_menus
    ADD CONSTRAINT food_service_menus_pkey PRIMARY KEY (menu_id);


--
-- Name: food_service_staff_accounts food_service_staff_accounts_pkey; Type: CONSTRAINT; Schema: public; Owner: wxu_school
--

ALTER TABLE ONLY public.food_service_staff_accounts
    ADD CONSTRAINT food_service_staff_accounts_pkey PRIMARY KEY (staff_account_id);


--
-- Name: food_service_staff_transaction_items food_service_staff_transaction_items_pkey; Type: CONSTRAINT; Schema: public; Owner: wxu_school
--

ALTER TABLE ONLY public.food_service_staff_transaction_items
    ADD CONSTRAINT food_service_staff_transaction_items_pkey PRIMARY KEY (staff_transaction_item_id);


--
-- Name: food_service_staff_transactions food_service_staff_transactions_pkey; Type: CONSTRAINT; Schema: public; Owner: wxu_school
--

ALTER TABLE ONLY public.food_service_staff_transactions
    ADD CONSTRAINT food_service_staff_transactions_pkey PRIMARY KEY (transaction_id);


--
-- Name: food_service_student_accounts food_service_student_accounts_pkey; Type: CONSTRAINT; Schema: public; Owner: wxu_school
--

ALTER TABLE ONLY public.food_service_student_accounts
    ADD CONSTRAINT food_service_student_accounts_pkey PRIMARY KEY (student_account_id);


--
-- Name: food_service_transaction_items food_service_transaction_items_pkey; Type: CONSTRAINT; Schema: public; Owner: wxu_school
--

ALTER TABLE ONLY public.food_service_transaction_items
    ADD CONSTRAINT food_service_transaction_items_pkey PRIMARY KEY (transaction_item_id);


--
-- Name: food_service_transactions food_service_transactions_pkey; Type: CONSTRAINT; Schema: public; Owner: wxu_school
--

ALTER TABLE ONLY public.food_service_transactions
    ADD CONSTRAINT food_service_transactions_pkey PRIMARY KEY (transaction_id);


--
-- Name: grade_levels grade_levels_pkey; Type: CONSTRAINT; Schema: public; Owner: wxu_school
--

ALTER TABLE ONLY public.grade_levels
    ADD CONSTRAINT grade_levels_pkey PRIMARY KEY (grade_level_id);


--
-- Name: gradebook_assignment_types gradebook_assignment_types_pkey; Type: CONSTRAINT; Schema: public; Owner: wxu_school
--

ALTER TABLE ONLY public.gradebook_assignment_types
    ADD CONSTRAINT gradebook_assignment_types_pkey PRIMARY KEY (assignment_type_id);


--
-- Name: gradebook_assignments gradebook_assignments_pkey; Type: CONSTRAINT; Schema: public; Owner: wxu_school
--

ALTER TABLE ONLY public.gradebook_assignments
    ADD CONSTRAINT gradebook_assignments_pkey PRIMARY KEY (assignment_id);


--
-- Name: gradebook_grades gradebook_grades_pkey; Type: CONSTRAINT; Schema: public; Owner: wxu_school
--

ALTER TABLE ONLY public.gradebook_grades
    ADD CONSTRAINT gradebook_grades_pkey PRIMARY KEY (gradebook_grade_id);


--
-- Name: grades_completed grades_completed_pkey; Type: CONSTRAINT; Schema: public; Owner: wxu_school
--

ALTER TABLE ONLY public.grades_completed
    ADD CONSTRAINT grades_completed_pkey PRIMARY KEY (grades_completed_id);


--
-- Name: history_marking_periods history_marking_periods_pkey; Type: CONSTRAINT; Schema: public; Owner: wxu_school
--

ALTER TABLE ONLY public.history_marking_periods
    ADD CONSTRAINT history_marking_periods_pkey PRIMARY KEY (history_marking_period_id);


--
-- Name: lunch_period lunch_period_pkey; Type: CONSTRAINT; Schema: public; Owner: wxu_school
--

ALTER TABLE ONLY public.lunch_period
    ADD CONSTRAINT lunch_period_pkey PRIMARY KEY (lunch_period_id);


--
-- Name: messages messages_pkey; Type: CONSTRAINT; Schema: public; Owner: wxu_school
--

ALTER TABLE ONLY public.messages
    ADD CONSTRAINT messages_pkey PRIMARY KEY (message_id);


--
-- Name: messagexuser messagexuser_pkey; Type: CONSTRAINT; Schema: public; Owner: wxu_school
--

ALTER TABLE ONLY public.messagexuser
    ADD CONSTRAINT messagexuser_pkey PRIMARY KEY (messagexuser_id);


--
-- Name: moodlexrosario moodlexrosario_pkey; Type: CONSTRAINT; Schema: public; Owner: wxu_school
--

ALTER TABLE ONLY public.moodlexrosario
    ADD CONSTRAINT moodlexrosario_pkey PRIMARY KEY (moodlexrosario_id);


--
-- Name: people_field_categories people_field_categories_pkey; Type: CONSTRAINT; Schema: public; Owner: wxu_school
--

ALTER TABLE ONLY public.people_field_categories
    ADD CONSTRAINT people_field_categories_pkey PRIMARY KEY (people_field_category_id);


--
-- Name: people_fields people_fields_pkey; Type: CONSTRAINT; Schema: public; Owner: wxu_school
--

ALTER TABLE ONLY public.people_fields
    ADD CONSTRAINT people_fields_pkey PRIMARY KEY (people_field_id);


--
-- Name: people_join_contacts people_join_contacts_pkey; Type: CONSTRAINT; Schema: public; Owner: wxu_school
--

ALTER TABLE ONLY public.people_join_contacts
    ADD CONSTRAINT people_join_contacts_pkey PRIMARY KEY (people_join_contact_id);


--
-- Name: people people_pkey; Type: CONSTRAINT; Schema: public; Owner: wxu_school
--

ALTER TABLE ONLY public.people
    ADD CONSTRAINT people_pkey PRIMARY KEY (person_id);


--
-- Name: portal_notes portal_notes_pkey; Type: CONSTRAINT; Schema: public; Owner: wxu_school
--

ALTER TABLE ONLY public.portal_notes
    ADD CONSTRAINT portal_notes_pkey PRIMARY KEY (portal_note_id);


--
-- Name: portal_poll_questions portal_poll_questions_pkey; Type: CONSTRAINT; Schema: public; Owner: wxu_school
--

ALTER TABLE ONLY public.portal_poll_questions
    ADD CONSTRAINT portal_poll_questions_pkey PRIMARY KEY (portal_poll_question_id);


--
-- Name: portal_polls portal_polls_pkey; Type: CONSTRAINT; Schema: public; Owner: wxu_school
--

ALTER TABLE ONLY public.portal_polls
    ADD CONSTRAINT portal_polls_pkey PRIMARY KEY (portal_poll_id);


--
-- Name: profile_exceptions profile_exceptions_pkey; Type: CONSTRAINT; Schema: public; Owner: wxu_school
--

ALTER TABLE ONLY public.profile_exceptions
    ADD CONSTRAINT profile_exceptions_pkey PRIMARY KEY (profile_exception_id);


--
-- Name: program_config program_config_pkey; Type: CONSTRAINT; Schema: public; Owner: wxu_school
--

ALTER TABLE ONLY public.program_config
    ADD CONSTRAINT program_config_pkey PRIMARY KEY (program_config_id);


--
-- Name: program_user_config program_user_config_pkey; Type: CONSTRAINT; Schema: public; Owner: wxu_school
--

ALTER TABLE ONLY public.program_user_config
    ADD CONSTRAINT program_user_config_pkey PRIMARY KEY (program_user_config_id);


--
-- Name: report_card_comment_categories report_card_comment_categories_pkey; Type: CONSTRAINT; Schema: public; Owner: wxu_school
--

ALTER TABLE ONLY public.report_card_comment_categories
    ADD CONSTRAINT report_card_comment_categories_pkey PRIMARY KEY (report_card_comment_category_id);


--
-- Name: report_card_comment_code_scales report_card_comment_code_scales_pkey; Type: CONSTRAINT; Schema: public; Owner: wxu_school
--

ALTER TABLE ONLY public.report_card_comment_code_scales
    ADD CONSTRAINT report_card_comment_code_scales_pkey PRIMARY KEY (report_card_comment_code_scale_id);


--
-- Name: report_card_comment_codes report_card_comment_codes_pkey; Type: CONSTRAINT; Schema: public; Owner: wxu_school
--

ALTER TABLE ONLY public.report_card_comment_codes
    ADD CONSTRAINT report_card_comment_codes_pkey PRIMARY KEY (report_card_comment_code_id);


--
-- Name: report_card_comments report_card_comments_pkey; Type: CONSTRAINT; Schema: public; Owner: wxu_school
--

ALTER TABLE ONLY public.report_card_comments
    ADD CONSTRAINT report_card_comments_pkey PRIMARY KEY (report_card_comment_id);


--
-- Name: report_card_grade_scales report_card_grade_scales_pkey; Type: CONSTRAINT; Schema: public; Owner: wxu_school
--

ALTER TABLE ONLY public.report_card_grade_scales
    ADD CONSTRAINT report_card_grade_scales_pkey PRIMARY KEY (report_card_grade_scale_id);


--
-- Name: report_card_grades report_card_grades_pkey; Type: CONSTRAINT; Schema: public; Owner: wxu_school
--

ALTER TABLE ONLY public.report_card_grades
    ADD CONSTRAINT report_card_grades_pkey PRIMARY KEY (report_card_grade_id);


--
-- Name: resources resources_pkey; Type: CONSTRAINT; Schema: public; Owner: wxu_school
--

ALTER TABLE ONLY public.resources
    ADD CONSTRAINT resources_pkey PRIMARY KEY (resource_id);


--
-- Name: schedule schedule_pkey; Type: CONSTRAINT; Schema: public; Owner: wxu_school
--

ALTER TABLE ONLY public.schedule
    ADD CONSTRAINT schedule_pkey PRIMARY KEY (schedule_id);


--
-- Name: schedule_requests schedule_requests_pkey; Type: CONSTRAINT; Schema: public; Owner: wxu_school
--

ALTER TABLE ONLY public.schedule_requests
    ADD CONSTRAINT schedule_requests_pkey PRIMARY KEY (schedule_request_id);


--
-- Name: school_fields school_fields_pkey; Type: CONSTRAINT; Schema: public; Owner: wxu_school
--

ALTER TABLE ONLY public.school_fields
    ADD CONSTRAINT school_fields_pkey PRIMARY KEY (school_field_id);


--
-- Name: school_gradelevels school_gradelevels_pkey; Type: CONSTRAINT; Schema: public; Owner: wxu_school
--

ALTER TABLE ONLY public.school_gradelevels
    ADD CONSTRAINT school_gradelevels_pkey PRIMARY KEY (gradelevel_id);


--
-- Name: school_marking_periods school_marking_periods_pkey; Type: CONSTRAINT; Schema: public; Owner: wxu_school
--

ALTER TABLE ONLY public.school_marking_periods
    ADD CONSTRAINT school_marking_periods_pkey PRIMARY KEY (marking_period_id);


--
-- Name: school_periods school_periods_pkey; Type: CONSTRAINT; Schema: public; Owner: wxu_school
--

ALTER TABLE ONLY public.school_periods
    ADD CONSTRAINT school_periods_pkey PRIMARY KEY (period_id);


--
-- Name: schools schools_pkey; Type: CONSTRAINT; Schema: public; Owner: wxu_school
--

ALTER TABLE ONLY public.schools
    ADD CONSTRAINT schools_pkey PRIMARY KEY (school_id);


--
-- Name: staff_exceptions staff_exceptions_pkey; Type: CONSTRAINT; Schema: public; Owner: wxu_school
--

ALTER TABLE ONLY public.staff_exceptions
    ADD CONSTRAINT staff_exceptions_pkey PRIMARY KEY (staff_exception_id);


--
-- Name: staff_field_categories staff_field_categories_pkey; Type: CONSTRAINT; Schema: public; Owner: wxu_school
--

ALTER TABLE ONLY public.staff_field_categories
    ADD CONSTRAINT staff_field_categories_pkey PRIMARY KEY (staff_field_category_id);


--
-- Name: staff_fields staff_fields_pkey; Type: CONSTRAINT; Schema: public; Owner: wxu_school
--

ALTER TABLE ONLY public.staff_fields
    ADD CONSTRAINT staff_fields_pkey PRIMARY KEY (staff_field_id);


--
-- Name: staff staff_pkey; Type: CONSTRAINT; Schema: public; Owner: wxu_school
--

ALTER TABLE ONLY public.staff
    ADD CONSTRAINT staff_pkey PRIMARY KEY (staff_id);


--
-- Name: student_assignments student_assignments_pkey; Type: CONSTRAINT; Schema: public; Owner: wxu_school
--

ALTER TABLE ONLY public.student_assignments
    ADD CONSTRAINT student_assignments_pkey PRIMARY KEY (student_assignment_id);


--
-- Name: student_eligibility_activities student_eligibility_activities_pkey; Type: CONSTRAINT; Schema: public; Owner: wxu_school
--

ALTER TABLE ONLY public.student_eligibility_activities
    ADD CONSTRAINT student_eligibility_activities_pkey PRIMARY KEY (student_eligibility_activity_id);


--
-- Name: student_enrollment_codes student_enrollment_codes_pkey; Type: CONSTRAINT; Schema: public; Owner: wxu_school
--

ALTER TABLE ONLY public.student_enrollment_codes
    ADD CONSTRAINT student_enrollment_codes_pkey PRIMARY KEY (student_enrollment_code_id);


--
-- Name: student_enrollment_course_periods student_enrollment_course_periods_pkey; Type: CONSTRAINT; Schema: public; Owner: wxu_school
--

ALTER TABLE ONLY public.student_enrollment_course_periods
    ADD CONSTRAINT student_enrollment_course_periods_pkey PRIMARY KEY (student_enrollment_course_period_id);


--
-- Name: student_enrollment student_enrollment_pkey; Type: CONSTRAINT; Schema: public; Owner: wxu_school
--

ALTER TABLE ONLY public.student_enrollment
    ADD CONSTRAINT student_enrollment_pkey PRIMARY KEY (enrollment_id);


--
-- Name: student_field_categories student_field_categories_pkey; Type: CONSTRAINT; Schema: public; Owner: wxu_school
--

ALTER TABLE ONLY public.student_field_categories
    ADD CONSTRAINT student_field_categories_pkey PRIMARY KEY (student_field_category_id);


--
-- Name: student_medical_alerts student_medical_alerts_pkey; Type: CONSTRAINT; Schema: public; Owner: wxu_school
--

ALTER TABLE ONLY public.student_medical_alerts
    ADD CONSTRAINT student_medical_alerts_pkey PRIMARY KEY (student_medical_alert_id);


--
-- Name: student_medical student_medical_pkey; Type: CONSTRAINT; Schema: public; Owner: wxu_school
--

ALTER TABLE ONLY public.student_medical
    ADD CONSTRAINT student_medical_pkey PRIMARY KEY (student_medical_id);


--
-- Name: student_medical_visits student_medical_visits_pkey; Type: CONSTRAINT; Schema: public; Owner: wxu_school
--

ALTER TABLE ONLY public.student_medical_visits
    ADD CONSTRAINT student_medical_visits_pkey PRIMARY KEY (student_medical_visit_id);


--
-- Name: student_mp_comments student_mp_comments_pkey; Type: CONSTRAINT; Schema: public; Owner: wxu_school
--

ALTER TABLE ONLY public.student_mp_comments
    ADD CONSTRAINT student_mp_comments_pkey PRIMARY KEY (student_mp_comment_id);


--
-- Name: student_mp_stats student_mp_stats_pkey; Type: CONSTRAINT; Schema: public; Owner: wxu_school
--

ALTER TABLE ONLY public.student_mp_stats
    ADD CONSTRAINT student_mp_stats_pkey PRIMARY KEY (student_mp_stat_id);


--
-- Name: student_report_card_comments student_report_card_comments_pkey; Type: CONSTRAINT; Schema: public; Owner: wxu_school
--

ALTER TABLE ONLY public.student_report_card_comments
    ADD CONSTRAINT student_report_card_comments_pkey PRIMARY KEY (student_report_card_comment_id);


--
-- Name: student_report_card_grades student_report_card_grades_pkey; Type: CONSTRAINT; Schema: public; Owner: wxu_school
--

ALTER TABLE ONLY public.student_report_card_grades
    ADD CONSTRAINT student_report_card_grades_pkey PRIMARY KEY (student_report_card_grade_id);


--
-- Name: students_join_address students_join_address_pkey; Type: CONSTRAINT; Schema: public; Owner: wxu_school
--

ALTER TABLE ONLY public.students_join_address
    ADD CONSTRAINT students_join_address_pkey PRIMARY KEY (student_join_address_id);


--
-- Name: students_join_people students_join_people_pkey; Type: CONSTRAINT; Schema: public; Owner: wxu_school
--

ALTER TABLE ONLY public.students_join_people
    ADD CONSTRAINT students_join_people_pkey PRIMARY KEY (student_join_people_id);


--
-- Name: students_join_users students_join_users_pkey; Type: CONSTRAINT; Schema: public; Owner: wxu_school
--

ALTER TABLE ONLY public.students_join_users
    ADD CONSTRAINT students_join_users_pkey PRIMARY KEY (student_join_user_id);


--
-- Name: students students_pkey; Type: CONSTRAINT; Schema: public; Owner: wxu_school
--

ALTER TABLE ONLY public.students
    ADD CONSTRAINT students_pkey PRIMARY KEY (student_id);


--
-- Name: templates templates_pkey; Type: CONSTRAINT; Schema: public; Owner: wxu_school
--

ALTER TABLE ONLY public.templates
    ADD CONSTRAINT templates_pkey PRIMARY KEY (template_id);


--
-- Name: user_profiles user_profiles_pkey; Type: CONSTRAINT; Schema: public; Owner: wxu_school
--

ALTER TABLE ONLY public.user_profiles
    ADD CONSTRAINT user_profiles_pkey PRIMARY KEY (id);


--
-- Name: wx_appreciations wx_appreciations_pkey; Type: CONSTRAINT; Schema: public; Owner: wxu_school
--

ALTER TABLE ONLY public.wx_appreciations
    ADD CONSTRAINT wx_appreciations_pkey PRIMARY KEY (wx_appreciation_id);


--
-- Name: wx_config_publication_resultats wx_config_publication_resultats_pkey; Type: CONSTRAINT; Schema: public; Owner: wxu_school
--

ALTER TABLE ONLY public.wx_config_publication_resultats
    ADD CONSTRAINT wx_config_publication_resultats_pkey PRIMARY KEY (wx_config_publication_resultat_id);


--
-- Name: wx_course_periods_gradelevels wx_course_periods_gradelevels_pkey; Type: CONSTRAINT; Schema: public; Owner: wxu_school
--

ALTER TABLE ONLY public.wx_course_periods_gradelevels
    ADD CONSTRAINT wx_course_periods_gradelevels_pkey PRIMARY KEY (wx_course_periods_gradelevels_id);


--
-- Name: wx_course_periods_subjects_periods wx_course_periods_subjects_periods_pkey; Type: CONSTRAINT; Schema: public; Owner: wxu_school
--

ALTER TABLE ONLY public.wx_course_periods_subjects_periods
    ADD CONSTRAINT wx_course_periods_subjects_periods_pkey PRIMARY KEY (wx_course_periods_subjects_periods_id);


--
-- Name: wx_course_periods_subjects wx_course_periods_subjects_pkey; Type: CONSTRAINT; Schema: public; Owner: wxu_school
--

ALTER TABLE ONLY public.wx_course_periods_subjects
    ADD CONSTRAINT wx_course_periods_subjects_pkey PRIMARY KEY (wx_course_periods_subjects_id);


--
-- Name: wx_course_subjects_gradelevels wx_course_subjects_gradelevels_pkey; Type: CONSTRAINT; Schema: public; Owner: wxu_school
--

ALTER TABLE ONLY public.wx_course_subjects_gradelevels
    ADD CONSTRAINT wx_course_subjects_gradelevels_pkey PRIMARY KEY (wx_course_subjects_gradelevels_id);


--
-- Name: wx_custom_configuration_school wx_custom_configuration_school_pkey; Type: CONSTRAINT; Schema: public; Owner: wxu_school
--

ALTER TABLE ONLY public.wx_custom_configuration_school
    ADD CONSTRAINT wx_custom_configuration_school_pkey PRIMARY KEY (id_custom_configuration_school);


--
-- Name: wx_echelle_notation_appreciation wx_echelle_notation_appreciation_pkey; Type: CONSTRAINT; Schema: public; Owner: wxu_school
--

ALTER TABLE ONLY public.wx_echelle_notation_appreciation
    ADD CONSTRAINT wx_echelle_notation_appreciation_pkey PRIMARY KEY (wx_echelle_notation_appreciation_id);


--
-- Name: wx_families wx_families_pkey; Type: CONSTRAINT; Schema: public; Owner: wxu_school
--

ALTER TABLE ONLY public.wx_families
    ADD CONSTRAINT wx_families_pkey PRIMARY KEY (wx_family_id);


--
-- Name: wx_family_members wx_family_members_pkey; Type: CONSTRAINT; Schema: public; Owner: wxu_school
--

ALTER TABLE ONLY public.wx_family_members
    ADD CONSTRAINT wx_family_members_pkey PRIMARY KEY (wx_family_member_id);


--
-- Name: wx_gradel_period_evaluation wx_gradel_period_evaluation_pkey; Type: CONSTRAINT; Schema: public; Owner: wxu_school
--

ALTER TABLE ONLY public.wx_gradel_period_evaluation
    ADD CONSTRAINT wx_gradel_period_evaluation_pkey PRIMARY KEY (id_gradel_period_evaluation);


--
-- Name: wx_moyennes_finales_students wx_moyennes_finales_students_pkey; Type: CONSTRAINT; Schema: public; Owner: wxu_school
--

ALTER TABLE ONLY public.wx_moyennes_finales_students
    ADD CONSTRAINT wx_moyennes_finales_students_pkey PRIMARY KEY (wx_moyenne_finale_student_id);


--
-- Name: wx_moyennes_validation_gradelevel wx_moyennes_validation_gradelevel_pkey; Type: CONSTRAINT; Schema: public; Owner: wxu_school
--

ALTER TABLE ONLY public.wx_moyennes_validation_gradelevel
    ADD CONSTRAINT wx_moyennes_validation_gradelevel_pkey PRIMARY KEY (wx_moyenne_validation_gradelevel_id);


--
-- Name: wx_notes_details wx_notes_details_pkey; Type: CONSTRAINT; Schema: public; Owner: wxu_school
--

ALTER TABLE ONLY public.wx_notes_details
    ADD CONSTRAINT wx_notes_details_pkey PRIMARY KEY (id_notes_details);


--
-- Name: wx_notes_student_details wx_notes_student_details_pkey; Type: CONSTRAINT; Schema: public; Owner: wxu_school
--

ALTER TABLE ONLY public.wx_notes_student_details
    ADD CONSTRAINT wx_notes_student_details_pkey PRIMARY KEY (id_notes_student_details);


--
-- Name: wx_reduction_eleve wx_reduction_eleve_pkey; Type: CONSTRAINT; Schema: public; Owner: wxu_school
--

ALTER TABLE ONLY public.wx_reduction_eleve
    ADD CONSTRAINT wx_reduction_eleve_pkey PRIMARY KEY (id);


--
-- Name: wx_reduction_members wx_reduction_members_pkey; Type: CONSTRAINT; Schema: public; Owner: wxu_school
--

ALTER TABLE ONLY public.wx_reduction_members
    ADD CONSTRAINT wx_reduction_members_pkey PRIMARY KEY (id);


--
-- Name: wx_rules_school wx_rules_school_pkey; Type: CONSTRAINT; Schema: public; Owner: wxu_school
--

ALTER TABLE ONLY public.wx_rules_school
    ADD CONSTRAINT wx_rules_school_pkey PRIMARY KEY (wx_rule_school_id);


--
-- Name: wx_teacher_attendance wx_teacher_attendance_pkey; Type: CONSTRAINT; Schema: public; Owner: wxu_school
--

ALTER TABLE ONLY public.wx_teacher_attendance
    ADD CONSTRAINT wx_teacher_attendance_pkey PRIMARY KEY (wx_teacher_attendance_id);


--
-- Name: wx_ues wx_ues_pkey; Type: CONSTRAINT; Schema: public; Owner: wxu_school
--

ALTER TABLE ONLY public.wx_ues
    ADD CONSTRAINT wx_ues_pkey PRIMARY KEY (ue_id);


--
-- Name: wx_ues_subjects wx_ues_subjects_pkey; Type: CONSTRAINT; Schema: public; Owner: wxu_school
--

ALTER TABLE ONLY public.wx_ues_subjects
    ADD CONSTRAINT wx_ues_subjects_pkey PRIMARY KEY (id);


--
-- Name: idx_bordereaux_details_staff_id; Type: INDEX; Schema: public; Owner: wxu_school
--

CREATE INDEX idx_bordereaux_details_staff_id ON public.bordereaux_details USING btree (staff_id);


--
-- Name: idx_course_periods_secondary_teacher_id; Type: INDEX; Schema: public; Owner: wxu_school
--

CREATE INDEX idx_course_periods_secondary_teacher_id ON public.course_periods USING btree (secondary_teacher_id);


--
-- Name: idx_student_enrollment_second_course_period_id; Type: INDEX; Schema: public; Owner: wxu_school
--

CREATE INDEX idx_student_enrollment_second_course_period_id ON public.student_enrollment USING btree (second_course_period_id);


--
-- Name: idx_student_enrollment_second_grade_id; Type: INDEX; Schema: public; Owner: wxu_school
--

CREATE INDEX idx_student_enrollment_second_grade_id ON public.student_enrollment USING btree (second_grade_id);


--
-- Name: idx_student_report_card_grades_report_card_comment_id; Type: INDEX; Schema: public; Owner: wxu_school
--

CREATE INDEX idx_student_report_card_grades_report_card_comment_id ON public.student_report_card_grades USING btree (report_card_comment_id);


--
-- Name: idx_wx_reduction_eleve_school_id; Type: INDEX; Schema: public; Owner: wxu_school
--

CREATE INDEX idx_wx_reduction_eleve_school_id ON public.wx_reduction_eleve USING btree (school_id);


--
-- Name: idx_wx_reduction_members_reduction_id; Type: INDEX; Schema: public; Owner: wxu_school
--

CREATE INDEX idx_wx_reduction_members_reduction_id ON public.wx_reduction_members USING btree (reduction_id);


--
-- Name: idx_wx_reduction_members_student_id; Type: INDEX; Schema: public; Owner: wxu_school
--

CREATE INDEX idx_wx_reduction_members_student_id ON public.wx_reduction_members USING btree (student_id);


--
-- Name: idx_wx_ues_subjects_id; Type: INDEX; Schema: public; Owner: wxu_school
--

CREATE UNIQUE INDEX idx_wx_ues_subjects_id ON public.wx_ues_subjects USING btree (id);


--
-- Name: attendance_calendar fk_attendance_calendar_calendar_id; Type: FK CONSTRAINT; Schema: public; Owner: wxu_school
--

ALTER TABLE ONLY public.attendance_calendar
    ADD CONSTRAINT fk_attendance_calendar_calendar_id FOREIGN KEY (calendar_id) REFERENCES public.attendance_calendars(calendar_id);


--
-- Name: attendance_period fk_attendance_period_my_period; Type: FK CONSTRAINT; Schema: public; Owner: wxu_school
--

ALTER TABLE ONLY public.attendance_period
    ADD CONSTRAINT fk_attendance_period_my_period FOREIGN KEY (my_period_id) REFERENCES public.school_periods(period_id);


--
-- Name: config fk_config_school_id; Type: FK CONSTRAINT; Schema: public; Owner: wxu_school
--

ALTER TABLE ONLY public.config
    ADD CONSTRAINT fk_config_school_id FOREIGN KEY (school_id) REFERENCES public.schools(school_id);


--
-- Name: course_periods fk_course_periods_secondary_teacher; Type: FK CONSTRAINT; Schema: public; Owner: wxu_school
--

ALTER TABLE ONLY public.course_periods
    ADD CONSTRAINT fk_course_periods_secondary_teacher FOREIGN KEY (secondary_teacher_id) REFERENCES public.staff(staff_id);


--
-- Name: courses fk_courses_school_gradelevel_id; Type: FK CONSTRAINT; Schema: public; Owner: wxu_school
--

ALTER TABLE ONLY public.courses
    ADD CONSTRAINT fk_courses_school_gradelevel_id FOREIGN KEY (grade_level) REFERENCES public.school_gradelevels(gradelevel_id);


--
-- Name: wx_reduction_members fk_reduction; Type: FK CONSTRAINT; Schema: public; Owner: wxu_school
--

ALTER TABLE ONLY public.wx_reduction_members
    ADD CONSTRAINT fk_reduction FOREIGN KEY (reduction_id) REFERENCES public.wx_reduction_eleve(id);


--
-- Name: wx_reduction_eleve fk_schools; Type: FK CONSTRAINT; Schema: public; Owner: wxu_school
--

ALTER TABLE ONLY public.wx_reduction_eleve
    ADD CONSTRAINT fk_schools FOREIGN KEY (school_id) REFERENCES public.schools(school_id);


--
-- Name: student_report_card_comments fk_srcc_report_card_comment_id; Type: FK CONSTRAINT; Schema: public; Owner: wxu_school
--

ALTER TABLE ONLY public.student_report_card_comments
    ADD CONSTRAINT fk_srcc_report_card_comment_id FOREIGN KEY (report_card_comment_id) REFERENCES public.report_card_comments(report_card_comment_id);


--
-- Name: bordereaux_details fk_staff; Type: FK CONSTRAINT; Schema: public; Owner: wxu_school
--

ALTER TABLE ONLY public.bordereaux_details
    ADD CONSTRAINT fk_staff FOREIGN KEY (staff_id) REFERENCES public.staff(staff_id);


--
-- Name: wx_reduction_members fk_student; Type: FK CONSTRAINT; Schema: public; Owner: wxu_school
--

ALTER TABLE ONLY public.wx_reduction_members
    ADD CONSTRAINT fk_student FOREIGN KEY (student_id) REFERENCES public.students(student_id);


--
-- Name: student_enrollment fk_student_enrollment_code; Type: FK CONSTRAINT; Schema: public; Owner: wxu_school
--

ALTER TABLE ONLY public.student_enrollment
    ADD CONSTRAINT fk_student_enrollment_code FOREIGN KEY (enrollment_code) REFERENCES public.student_enrollment_codes(student_enrollment_code_id);


--
-- Name: student_enrollment fk_student_enrollment_drop_code; Type: FK CONSTRAINT; Schema: public; Owner: wxu_school
--

ALTER TABLE ONLY public.student_enrollment
    ADD CONSTRAINT fk_student_enrollment_drop_code FOREIGN KEY (drop_code) REFERENCES public.student_enrollment_codes(student_enrollment_code_id);


--
-- Name: student_enrollment fk_student_enrollment_second_course_period; Type: FK CONSTRAINT; Schema: public; Owner: wxu_school
--

ALTER TABLE ONLY public.student_enrollment
    ADD CONSTRAINT fk_student_enrollment_second_course_period FOREIGN KEY (second_course_period_id) REFERENCES public.course_periods(course_period_id);


--
-- Name: student_enrollment fk_student_enrollment_second_grade; Type: FK CONSTRAINT; Schema: public; Owner: wxu_school
--

ALTER TABLE ONLY public.student_enrollment
    ADD CONSTRAINT fk_student_enrollment_second_grade FOREIGN KEY (second_grade_id) REFERENCES public.school_gradelevels(gradelevel_id);


--
-- Name: student_report_card_grades fk_student_report_card_grades_comment; Type: FK CONSTRAINT; Schema: public; Owner: wxu_school
--

ALTER TABLE ONLY public.student_report_card_grades
    ADD CONSTRAINT fk_student_report_card_grades_comment FOREIGN KEY (report_card_comment_id) REFERENCES public.report_card_comments(report_card_comment_id);


--
-- PostgreSQL database dump complete
--

