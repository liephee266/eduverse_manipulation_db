--
-- PostgreSQL database dump
--

\restrict 0G8XNJt8yFCev1APVXTZ2BZ11jTqNtoVOkXTbZSRKB83Aqpw57JRhk2gyaT6HcF

-- Dumped from database version 17.6
-- Dumped by pg_dump version 17.6

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
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
-- Name: calc_cum_cr_gpa(integer, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.calc_cum_cr_gpa(mp_id integer, s_id integer) RETURNS integer
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


ALTER FUNCTION public.calc_cum_cr_gpa(mp_id integer, s_id integer) OWNER TO postgres;

--
-- Name: calc_cum_gpa(integer, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.calc_cum_gpa(mp_id integer, s_id integer) RETURNS integer
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


ALTER FUNCTION public.calc_cum_gpa(mp_id integer, s_id integer) OWNER TO postgres;

--
-- Name: calc_gpa_mp(integer, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.calc_gpa_mp(s_id integer, mp_id integer) RETURNS integer
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


ALTER FUNCTION public.calc_gpa_mp(s_id integer, mp_id integer) OWNER TO postgres;

--
-- Name: credit(integer, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.credit(cp_id integer, mp_id integer) RETURNS numeric
    LANGUAGE plpgsql
    AS $$
DECLARE
    course_detail RECORD;
    mp_detail RECORD;
    val RECORD;
BEGIN
select * into course_detail from course_periods where course_period_id = cp_id;
select * into mp_detail from marking_periods where marking_period_id = mp_id;

IF course_detail.marking_period_id = mp_detail.marking_period_id THEN
    return course_detail.credits;
ELSIF course_detail.mp = 'FY' AND mp_detail.mp_type = 'semester' THEN
    select into val count(*) as mp_count from marking_periods where parent_id = course_detail.marking_period_id group by parent_id;
ELSIF course_detail.mp = 'FY' and mp_detail.mp_type = 'quarter' THEN
    select into val count(*) as mp_count from marking_periods where grandparent_id = course_detail.marking_period_id group by grandparent_id;
ELSIF course_detail.mp = 'SEM' and mp_detail.mp_type = 'quarter' THEN
    select into val count(*) as mp_count from marking_periods where parent_id = course_detail.marking_period_id group by parent_id;
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


ALTER FUNCTION public.credit(cp_id integer, mp_id integer) OWNER TO postgres;

--
-- Name: immutable_unaccent(text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.immutable_unaccent(text) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $_$
    SELECT unaccent($1)
$_$;


ALTER FUNCTION public.immutable_unaccent(text) OWNER TO postgres;

--
-- Name: set_class_rank_mp(integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.set_class_rank_mp(mp_id integer) RETURNS integer
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
    from student_enrollment se, student_mp_stats sgm, marking_periods mp
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


ALTER FUNCTION public.set_class_rank_mp(mp_id integer) OWNER TO postgres;

--
-- Name: set_updated_at(); Type: FUNCTION; Schema: public; Owner: postgres
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


ALTER FUNCTION public.set_updated_at() OWNER TO postgres;

--
-- Name: t_update_mp_stats(); Type: FUNCTION; Schema: public; Owner: postgres
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
    --IF tg_op = 'INSERT' THEN
        --we need to do stuff here to gather other information since it's a new record.
    --ELSE
        --if report_card_grade_id changes, then we need to reset gp values
    --  IF NOT NEW.report_card_grade_id = OLD.report_card_grade_id THEN
            --
    PERFORM calc_gpa_mp(NEW.student_id, NEW.marking_period_id);
    PERFORM calc_cum_gpa(NEW.marking_period_id, NEW.student_id);
    PERFORM calc_cum_cr_gpa(NEW.marking_period_id, NEW.student_id);
  END IF;
  RETURN NULL;
END;
$$;


ALTER FUNCTION public.t_update_mp_stats() OWNER TO postgres;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: access_log; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.access_log (
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


ALTER TABLE public.access_log OWNER TO postgres;

--
-- Name: accounting_categories; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.accounting_categories (
    id integer NOT NULL,
    school_id integer NOT NULL,
    title text NOT NULL,
    short_name character varying(10),
    type character varying(100),
    sort_order numeric,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.accounting_categories OWNER TO postgres;

--
-- Name: accounting_categories_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.accounting_categories_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.accounting_categories_id_seq OWNER TO postgres;

--
-- Name: accounting_categories_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.accounting_categories_id_seq OWNED BY public.accounting_categories.id;


--
-- Name: accounting_incomes; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.accounting_incomes (
    assigned_date date,
    comments text,
    id integer NOT NULL,
    title text NOT NULL,
    category_id integer,
    amount numeric(14,2) NOT NULL,
    file_attached text,
    school_id integer NOT NULL,
    syear numeric(4,0) NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.accounting_incomes OWNER TO postgres;

--
-- Name: accounting_incomes_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.accounting_incomes_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.accounting_incomes_id_seq OWNER TO postgres;

--
-- Name: accounting_incomes_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.accounting_incomes_id_seq OWNED BY public.accounting_incomes.id;


--
-- Name: accounting_payments; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.accounting_payments (
    id integer NOT NULL,
    syear numeric(4,0) NOT NULL,
    school_id integer NOT NULL,
    staff_id integer,
    title text,
    category_id integer,
    amount numeric(14,2) NOT NULL,
    payment_date date,
    comments text,
    file_attached text,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.accounting_payments OWNER TO postgres;

--
-- Name: accounting_payments_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.accounting_payments_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.accounting_payments_id_seq OWNER TO postgres;

--
-- Name: accounting_payments_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.accounting_payments_id_seq OWNED BY public.accounting_payments.id;


--
-- Name: accounting_salaries; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.accounting_salaries (
    staff_id integer NOT NULL,
    assigned_date date,
    due_date date,
    comments text,
    id integer NOT NULL,
    title text NOT NULL,
    amount numeric(14,2) NOT NULL,
    file_attached text,
    school_id integer NOT NULL,
    syear numeric(4,0) NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.accounting_salaries OWNER TO postgres;

--
-- Name: accounting_salaries_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.accounting_salaries_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.accounting_salaries_id_seq OWNER TO postgres;

--
-- Name: accounting_salaries_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.accounting_salaries_id_seq OWNED BY public.accounting_salaries.id;


--
-- Name: address; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.address (
    address_id integer NOT NULL,
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


ALTER TABLE public.address OWNER TO postgres;

--
-- Name: address_address_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.address_address_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.address_address_id_seq OWNER TO postgres;

--
-- Name: address_address_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.address_address_id_seq OWNED BY public.address.address_id;


--
-- Name: address_field_categories; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.address_field_categories (
    id integer NOT NULL,
    title text NOT NULL,
    sort_order numeric,
    residence character(1),
    mailing character(1),
    bus character(1),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.address_field_categories OWNER TO postgres;

--
-- Name: address_field_categories_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.address_field_categories_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.address_field_categories_id_seq OWNER TO postgres;

--
-- Name: address_field_categories_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.address_field_categories_id_seq OWNED BY public.address_field_categories.id;


--
-- Name: address_fields; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.address_fields (
    id integer NOT NULL,
    type character varying(10) NOT NULL,
    title text NOT NULL,
    sort_order numeric,
    select_options text,
    category_id integer,
    required character varying(1),
    default_selection text,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.address_fields OWNER TO postgres;

--
-- Name: address_fields_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.address_fields_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.address_fields_id_seq OWNER TO postgres;

--
-- Name: address_fields_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.address_fields_id_seq OWNED BY public.address_fields.id;


--
-- Name: attendance_calendar; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.attendance_calendar (
    syear numeric(4,0) NOT NULL,
    school_id integer NOT NULL,
    school_date date NOT NULL,
    minutes integer,
    block character varying(10),
    calendar_id integer NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.attendance_calendar OWNER TO postgres;

--
-- Name: attendance_calendars; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.attendance_calendars (
    school_id integer NOT NULL,
    title character varying(100) NOT NULL,
    syear numeric(4,0) NOT NULL,
    calendar_id integer NOT NULL,
    default_calendar character varying(1),
    rollover_id integer,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.attendance_calendars OWNER TO postgres;

--
-- Name: attendance_calendars_calendar_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.attendance_calendars_calendar_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.attendance_calendars_calendar_id_seq OWNER TO postgres;

--
-- Name: attendance_calendars_calendar_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.attendance_calendars_calendar_id_seq OWNED BY public.attendance_calendars.calendar_id;


--
-- Name: attendance_code_categories; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.attendance_code_categories (
    id integer NOT NULL,
    syear numeric(4,0) NOT NULL,
    school_id integer NOT NULL,
    title text NOT NULL,
    sort_order numeric,
    rollover_id integer,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.attendance_code_categories OWNER TO postgres;

--
-- Name: attendance_code_categories_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.attendance_code_categories_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.attendance_code_categories_id_seq OWNER TO postgres;

--
-- Name: attendance_code_categories_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.attendance_code_categories_id_seq OWNED BY public.attendance_code_categories.id;


--
-- Name: attendance_codes; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.attendance_codes (
    id integer NOT NULL,
    syear numeric(4,0) NOT NULL,
    school_id integer NOT NULL,
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


ALTER TABLE public.attendance_codes OWNER TO postgres;

--
-- Name: attendance_codes_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.attendance_codes_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.attendance_codes_id_seq OWNER TO postgres;

--
-- Name: attendance_codes_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.attendance_codes_id_seq OWNED BY public.attendance_codes.id;


--
-- Name: attendance_completed; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.attendance_completed (
    staff_id integer NOT NULL,
    school_date date NOT NULL,
    period_id integer NOT NULL,
    table_name integer NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.attendance_completed OWNER TO postgres;

--
-- Name: attendance_day; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.attendance_day (
    student_id integer NOT NULL,
    school_date date NOT NULL,
    minutes_present integer,
    state_value numeric(2,1),
    syear numeric(4,0),
    marking_period_id integer,
    comment text,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.attendance_day OWNER TO postgres;

--
-- Name: attendance_period; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.attendance_period (
    student_id integer NOT NULL,
    school_date date NOT NULL,
    period_id integer,
    attendance_code integer,
    attendance_teacher_code integer,
    attendance_reason character varying(100),
    admin character varying(1),
    course_period_id integer,
    marking_period_id integer,
    comment character varying(100),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone,
    my_period_id integer
);


ALTER TABLE public.attendance_period OWNER TO postgres;

--
-- Name: billing_fees; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.billing_fees (
    student_id integer NOT NULL,
    assigned_date date,
    due_date date,
    comments text,
    id integer NOT NULL,
    title text,
    amount numeric(14,2) NOT NULL,
    file_attached text,
    school_id integer NOT NULL,
    syear numeric(4,0) NOT NULL,
    waived_fee_id integer,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone,
    month character varying(5)
);


ALTER TABLE public.billing_fees OWNER TO postgres;

--
-- Name: billing_fees_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.billing_fees_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.billing_fees_id_seq OWNER TO postgres;

--
-- Name: billing_fees_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.billing_fees_id_seq OWNED BY public.billing_fees.id;


--
-- Name: billing_payments; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.billing_payments (
    id integer NOT NULL,
    syear numeric(4,0) NOT NULL,
    school_id integer NOT NULL,
    student_id integer NOT NULL,
    amount numeric(14,2) NOT NULL,
    payment_date date,
    comments text,
    refunded_payment_id integer,
    lunch_payment character varying(1),
    file_attached text,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone,
    month character varying(5),
    intitule_caissier character varying(255),
    imprimer character varying(10)
);


ALTER TABLE public.billing_payments OWNER TO postgres;

--
-- Name: billing_payments_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.billing_payments_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.billing_payments_id_seq OWNER TO postgres;

--
-- Name: billing_payments_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.billing_payments_id_seq OWNED BY public.billing_payments.id;


--
-- Name: bordereaux_details; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.bordereaux_details (
    id integer NOT NULL,
    staff_id integer NOT NULL,
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


ALTER TABLE public.bordereaux_details OWNER TO postgres;

--
-- Name: bordereaux_details_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.bordereaux_details_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.bordereaux_details_id_seq OWNER TO postgres;

--
-- Name: bordereaux_details_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.bordereaux_details_id_seq OWNED BY public.bordereaux_details.id;


--
-- Name: calendar_events; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.calendar_events (
    id integer NOT NULL,
    syear numeric(4,0) NOT NULL,
    school_id integer NOT NULL,
    school_date date,
    title character varying(50) NOT NULL,
    description text,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.calendar_events OWNER TO postgres;

--
-- Name: calendar_events_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.calendar_events_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.calendar_events_id_seq OWNER TO postgres;

--
-- Name: calendar_events_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.calendar_events_id_seq OWNED BY public.calendar_events.id;


--
-- Name: config; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.config (
    school_id integer NOT NULL,
    title character varying(100) NOT NULL,
    config_value text,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.config OWNER TO postgres;

--
-- Name: course_periods; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.course_periods (
    syear numeric(4,0) NOT NULL,
    school_id integer NOT NULL,
    course_period_id integer NOT NULL,
    course_id integer,
    title text,
    short_name character varying(25) NOT NULL,
    mp character varying(3),
    marking_period_id integer,
    teacher_id integer,
    secondary_teacher_id integer,
    room character varying(10),
    total_seats numeric,
    filled_seats numeric,
    does_attendance text,
    does_honor_roll character varying(1),
    does_class_rank character varying(1),
    gender_restriction character varying(1),
    house_restriction character varying(1),
    availability numeric,
    parent_id integer,
    calendar_id integer,
    half_day character varying(1),
    does_breakoff character varying(1),
    rollover_id integer,
    grade_scale_id integer,
    credits numeric(6,2),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone,
    echelle_notation integer,
    semester_type character varying(20) DEFAULT 'pair'::character varying,
    frais_classe numeric(10,2),
    total_mentant integer,
    frais_classe_plein_temps numeric(10,2)
);


ALTER TABLE public.course_periods OWNER TO postgres;

--
-- Name: courses; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.courses (
    syear numeric(4,0) NOT NULL,
    course_id integer NOT NULL,
    subject_id integer NOT NULL,
    school_id integer NOT NULL,
    grade_level integer,
    title character varying(100) NOT NULL,
    short_name character varying(25),
    rollover_id integer,
    credit_hours numeric(6,2),
    description text,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.courses OWNER TO postgres;

--
-- Name: course_details; Type: VIEW; Schema: public; Owner: postgres
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
  WHERE (cp.course_id = c.course_id);


ALTER VIEW public.course_details OWNER TO postgres;

--
-- Name: course_period_school_periods; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.course_period_school_periods (
    course_period_school_periods_id integer NOT NULL,
    course_period_id integer NOT NULL,
    period_id integer NOT NULL,
    days character varying(7),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.course_period_school_periods OWNER TO postgres;

--
-- Name: course_period_school_periods_course_period_school_periods_i_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.course_period_school_periods_course_period_school_periods_i_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.course_period_school_periods_course_period_school_periods_i_seq OWNER TO postgres;

--
-- Name: course_period_school_periods_course_period_school_periods_i_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.course_period_school_periods_course_period_school_periods_i_seq OWNED BY public.course_period_school_periods.course_period_school_periods_id;


--
-- Name: course_periods_course_period_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.course_periods_course_period_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.course_periods_course_period_id_seq OWNER TO postgres;

--
-- Name: course_periods_course_period_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.course_periods_course_period_id_seq OWNED BY public.course_periods.course_period_id;


--
-- Name: course_subjects; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.course_subjects (
    syear numeric(4,0) NOT NULL,
    school_id integer NOT NULL,
    subject_id integer NOT NULL,
    title character varying(100) NOT NULL,
    short_name character varying(25),
    sort_order numeric,
    rollover_id integer,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.course_subjects OWNER TO postgres;

--
-- Name: course_subjects_subject_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.course_subjects_subject_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.course_subjects_subject_id_seq OWNER TO postgres;

--
-- Name: course_subjects_subject_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.course_subjects_subject_id_seq OWNED BY public.course_subjects.subject_id;


--
-- Name: courses_course_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.courses_course_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.courses_course_id_seq OWNER TO postgres;

--
-- Name: courses_course_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.courses_course_id_seq OWNED BY public.courses.course_id;


--
-- Name: custom_fields; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.custom_fields (
    id integer NOT NULL,
    type character varying(10) NOT NULL,
    title text NOT NULL,
    sort_order numeric,
    select_options text,
    category_id integer,
    required character varying(1),
    default_selection text,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.custom_fields OWNER TO postgres;

--
-- Name: custom_fields_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.custom_fields_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.custom_fields_id_seq OWNER TO postgres;

--
-- Name: custom_fields_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.custom_fields_id_seq OWNED BY public.custom_fields.id;


--
-- Name: discipline_field_usage; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.discipline_field_usage (
    id integer NOT NULL,
    discipline_field_id integer NOT NULL,
    syear numeric(4,0) NOT NULL,
    school_id integer NOT NULL,
    title text NOT NULL,
    select_options text,
    sort_order numeric,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.discipline_field_usage OWNER TO postgres;

--
-- Name: discipline_field_usage_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.discipline_field_usage_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.discipline_field_usage_id_seq OWNER TO postgres;

--
-- Name: discipline_field_usage_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.discipline_field_usage_id_seq OWNED BY public.discipline_field_usage.id;


--
-- Name: discipline_fields; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.discipline_fields (
    id integer NOT NULL,
    title text NOT NULL,
    short_name character varying(20),
    data_type character varying(30) NOT NULL,
    column_name text NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.discipline_fields OWNER TO postgres;

--
-- Name: discipline_fields_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.discipline_fields_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.discipline_fields_id_seq OWNER TO postgres;

--
-- Name: discipline_fields_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.discipline_fields_id_seq OWNED BY public.discipline_fields.id;


--
-- Name: discipline_referrals; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.discipline_referrals (
    id integer NOT NULL,
    syear numeric(4,0) NOT NULL,
    student_id integer NOT NULL,
    school_id integer NOT NULL,
    staff_id integer,
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


ALTER TABLE public.discipline_referrals OWNER TO postgres;

--
-- Name: discipline_referrals_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.discipline_referrals_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.discipline_referrals_id_seq OWNER TO postgres;

--
-- Name: discipline_referrals_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.discipline_referrals_id_seq OWNED BY public.discipline_referrals.id;


--
-- Name: dual; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.dual AS
 SELECT 'X'::text AS dummy;


ALTER VIEW public.dual OWNER TO postgres;

--
-- Name: eligibility; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.eligibility (
    student_id integer NOT NULL,
    syear numeric(4,0),
    school_date date,
    period_id integer,
    eligibility_code character varying(20),
    course_period_id integer NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.eligibility OWNER TO postgres;

--
-- Name: eligibility_activities; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.eligibility_activities (
    id integer NOT NULL,
    syear numeric(4,0) NOT NULL,
    school_id integer NOT NULL,
    title text NOT NULL,
    start_date date,
    end_date date,
    comment text,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.eligibility_activities OWNER TO postgres;

--
-- Name: eligibility_activities_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.eligibility_activities_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.eligibility_activities_id_seq OWNER TO postgres;

--
-- Name: eligibility_activities_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.eligibility_activities_id_seq OWNED BY public.eligibility_activities.id;


--
-- Name: eligibility_completed; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.eligibility_completed (
    staff_id integer NOT NULL,
    school_date date NOT NULL,
    period_id integer NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.eligibility_completed OWNER TO postgres;

--
-- Name: school_gradelevels; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.school_gradelevels (
    id integer NOT NULL,
    school_id integer NOT NULL,
    short_name character varying(3),
    title character varying(50) NOT NULL,
    next_grade_id integer,
    sort_order numeric,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone,
    marking_period_type character varying(20)
);


ALTER TABLE public.school_gradelevels OWNER TO postgres;

--
-- Name: student_enrollment; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.student_enrollment (
    id integer NOT NULL,
    syear numeric(4,0) NOT NULL,
    school_id integer NOT NULL,
    student_id integer NOT NULL,
    grade_id integer,
    start_date date,
    end_date date,
    enrollment_code integer,
    drop_code integer,
    next_school integer,
    calendar_id integer,
    last_school integer,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone,
    second_course_period_id integer,
    semester character varying(10),
    second_semester character varying(10),
    course_period_id integer,
    second_grade_id integer
);


ALTER TABLE public.student_enrollment OWNER TO postgres;

--
-- Name: enroll_grade; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.enroll_grade AS
 SELECT e.id,
    e.syear,
    e.school_id,
    e.student_id,
    e.start_date,
    e.end_date,
    sg.short_name,
    sg.title
   FROM public.student_enrollment e,
    public.school_gradelevels sg
  WHERE (e.grade_id = sg.id);


ALTER VIEW public.enroll_grade OWNER TO postgres;

--
-- Name: food_service_accounts; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.food_service_accounts (
    account_id integer NOT NULL,
    balance numeric(9,2) NOT NULL,
    transaction_id integer,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.food_service_accounts OWNER TO postgres;

--
-- Name: food_service_categories; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.food_service_categories (
    category_id integer NOT NULL,
    school_id integer NOT NULL,
    menu_id integer NOT NULL,
    title character varying(25) NOT NULL,
    sort_order numeric,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.food_service_categories OWNER TO postgres;

--
-- Name: food_service_categories_category_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.food_service_categories_category_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.food_service_categories_category_id_seq OWNER TO postgres;

--
-- Name: food_service_categories_category_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.food_service_categories_category_id_seq OWNED BY public.food_service_categories.category_id;


--
-- Name: food_service_items; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.food_service_items (
    item_id integer NOT NULL,
    school_id integer NOT NULL,
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


ALTER TABLE public.food_service_items OWNER TO postgres;

--
-- Name: food_service_items_item_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.food_service_items_item_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.food_service_items_item_id_seq OWNER TO postgres;

--
-- Name: food_service_items_item_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.food_service_items_item_id_seq OWNED BY public.food_service_items.item_id;


--
-- Name: food_service_menu_items; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.food_service_menu_items (
    menu_item_id integer NOT NULL,
    school_id integer NOT NULL,
    menu_id integer NOT NULL,
    item_id integer NOT NULL,
    category_id integer,
    sort_order numeric,
    does_count character varying(1),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.food_service_menu_items OWNER TO postgres;

--
-- Name: food_service_menu_items_menu_item_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.food_service_menu_items_menu_item_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.food_service_menu_items_menu_item_id_seq OWNER TO postgres;

--
-- Name: food_service_menu_items_menu_item_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.food_service_menu_items_menu_item_id_seq OWNED BY public.food_service_menu_items.menu_item_id;


--
-- Name: food_service_menus; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.food_service_menus (
    menu_id integer NOT NULL,
    school_id integer NOT NULL,
    title character varying(25) NOT NULL,
    sort_order numeric,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.food_service_menus OWNER TO postgres;

--
-- Name: food_service_menus_menu_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.food_service_menus_menu_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.food_service_menus_menu_id_seq OWNER TO postgres;

--
-- Name: food_service_menus_menu_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.food_service_menus_menu_id_seq OWNED BY public.food_service_menus.menu_id;


--
-- Name: food_service_staff_accounts; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.food_service_staff_accounts (
    staff_id integer NOT NULL,
    status character varying(25),
    barcode character varying(50),
    balance numeric(9,2) NOT NULL,
    transaction_id integer,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.food_service_staff_accounts OWNER TO postgres;

--
-- Name: food_service_staff_transaction_items; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.food_service_staff_transaction_items (
    item_id integer NOT NULL,
    transaction_id integer NOT NULL,
    amount numeric(9,2),
    short_name character varying(25),
    description character varying(50),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.food_service_staff_transaction_items OWNER TO postgres;

--
-- Name: food_service_staff_transactions; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.food_service_staff_transactions (
    transaction_id integer NOT NULL,
    staff_id integer NOT NULL,
    school_id integer NOT NULL,
    syear numeric(4,0) NOT NULL,
    balance numeric(9,2),
    "timestamp" timestamp without time zone,
    short_name character varying(25),
    description character varying(50),
    seller_id integer,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.food_service_staff_transactions OWNER TO postgres;

--
-- Name: food_service_staff_transactions_transaction_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.food_service_staff_transactions_transaction_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.food_service_staff_transactions_transaction_id_seq OWNER TO postgres;

--
-- Name: food_service_staff_transactions_transaction_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.food_service_staff_transactions_transaction_id_seq OWNED BY public.food_service_staff_transactions.transaction_id;


--
-- Name: food_service_student_accounts; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.food_service_student_accounts (
    student_id integer NOT NULL,
    account_id integer NOT NULL,
    discount character varying(25),
    status character varying(25),
    barcode character varying(50),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.food_service_student_accounts OWNER TO postgres;

--
-- Name: food_service_transaction_items; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.food_service_transaction_items (
    item_id integer NOT NULL,
    transaction_id integer NOT NULL,
    amount numeric(9,2),
    discount character varying(25),
    short_name character varying(25),
    description character varying(50),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.food_service_transaction_items OWNER TO postgres;

--
-- Name: food_service_transactions; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.food_service_transactions (
    transaction_id integer NOT NULL,
    account_id integer NOT NULL,
    student_id integer,
    school_id integer NOT NULL,
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


ALTER TABLE public.food_service_transactions OWNER TO postgres;

--
-- Name: food_service_transactions_transaction_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.food_service_transactions_transaction_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.food_service_transactions_transaction_id_seq OWNER TO postgres;

--
-- Name: food_service_transactions_transaction_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.food_service_transactions_transaction_id_seq OWNED BY public.food_service_transactions.transaction_id;


--
-- Name: grade_levels; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.grade_levels (
    id integer NOT NULL,
    title character varying(100) NOT NULL,
    sort_order integer DEFAULT 0
);


ALTER TABLE public.grade_levels OWNER TO postgres;

--
-- Name: grade_levels_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.grade_levels_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.grade_levels_id_seq OWNER TO postgres;

--
-- Name: grade_levels_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.grade_levels_id_seq OWNED BY public.grade_levels.id;


--
-- Name: gradebook_assignment_types; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.gradebook_assignment_types (
    assignment_type_id integer NOT NULL,
    staff_id integer NOT NULL,
    course_id integer NOT NULL,
    title text NOT NULL,
    final_grade_percent numeric(6,5),
    sort_order numeric,
    color character varying(30),
    created_mp integer,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.gradebook_assignment_types OWNER TO postgres;

--
-- Name: gradebook_assignment_types_assignment_type_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.gradebook_assignment_types_assignment_type_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.gradebook_assignment_types_assignment_type_id_seq OWNER TO postgres;

--
-- Name: gradebook_assignment_types_assignment_type_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.gradebook_assignment_types_assignment_type_id_seq OWNED BY public.gradebook_assignment_types.assignment_type_id;


--
-- Name: gradebook_assignments; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.gradebook_assignments (
    assignment_id integer NOT NULL,
    staff_id integer NOT NULL,
    marking_period_id integer NOT NULL,
    course_period_id integer,
    course_id integer,
    assignment_type_id integer NOT NULL,
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


ALTER TABLE public.gradebook_assignments OWNER TO postgres;

--
-- Name: gradebook_assignments_assignment_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.gradebook_assignments_assignment_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.gradebook_assignments_assignment_id_seq OWNER TO postgres;

--
-- Name: gradebook_assignments_assignment_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.gradebook_assignments_assignment_id_seq OWNED BY public.gradebook_assignments.assignment_id;


--
-- Name: gradebook_grades; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.gradebook_grades (
    student_id integer NOT NULL,
    period_id integer,
    course_period_id integer NOT NULL,
    assignment_id integer NOT NULL,
    points numeric(6,2),
    comment text,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.gradebook_grades OWNER TO postgres;

--
-- Name: grades_completed; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.grades_completed (
    staff_id integer NOT NULL,
    marking_period_id integer NOT NULL,
    course_period_id integer NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.grades_completed OWNER TO postgres;

--
-- Name: school_marking_periods; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.school_marking_periods (
    marking_period_id integer NOT NULL,
    syear numeric(4,0) NOT NULL,
    mp character varying(3) NOT NULL,
    school_id integer NOT NULL,
    parent_id integer,
    title character varying(50) NOT NULL,
    short_name character varying(10),
    sort_order numeric,
    start_date date NOT NULL,
    end_date date NOT NULL,
    post_start_date date,
    post_end_date date,
    does_grades character varying(1),
    does_comments character varying(1),
    rollover_id integer,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.school_marking_periods OWNER TO postgres;

--
-- Name: school_marking_periods_marking_period_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.school_marking_periods_marking_period_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.school_marking_periods_marking_period_id_seq OWNER TO postgres;

--
-- Name: school_marking_periods_marking_period_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.school_marking_periods_marking_period_id_seq OWNED BY public.school_marking_periods.marking_period_id;


--
-- Name: history_marking_periods; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.history_marking_periods (
    parent_id integer,
    mp_type character varying(20),
    name character varying(50) NOT NULL,
    short_name character varying(10),
    post_end_date date,
    school_id integer NOT NULL,
    syear numeric(4,0),
    marking_period_id integer DEFAULT nextval('public.school_marking_periods_marking_period_id_seq'::regclass) NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.history_marking_periods OWNER TO postgres;

--
-- Name: lunch_period; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.lunch_period (
    student_id integer NOT NULL,
    school_date date NOT NULL,
    period_id integer NOT NULL,
    attendance_code integer,
    attendance_teacher_code integer,
    attendance_reason character varying(100),
    admin character varying(1),
    course_period_id integer,
    marking_period_id integer,
    comment character varying(100),
    table_name integer,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.lunch_period OWNER TO postgres;

--
-- Name: marking_periods; Type: VIEW; Schema: public; Owner: postgres
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
            WHEN ((school_marking_periods.parent_id)::numeric > (0)::numeric) THEN (school_marking_periods.parent_id)::numeric
            ELSE ('-1'::integer)::numeric
        END AS parent_id,
        CASE
            WHEN ((( SELECT smp.parent_id
               FROM public.school_marking_periods smp
              WHERE (smp.marking_period_id = school_marking_periods.parent_id)))::numeric > (0)::numeric) THEN (( SELECT smp.parent_id
               FROM public.school_marking_periods smp
              WHERE (smp.marking_period_id = school_marking_periods.parent_id)))::numeric
            ELSE ('-1'::integer)::numeric
        END AS grandparent_id,
    school_marking_periods.start_date,
    school_marking_periods.end_date,
    school_marking_periods.post_start_date,
    school_marking_periods.post_end_date,
    school_marking_periods.does_grades,
    school_marking_periods.does_comments
   FROM public.school_marking_periods
UNION
 SELECT history_marking_periods.marking_period_id,
    'History'::text AS mp_source,
    history_marking_periods.syear,
    history_marking_periods.school_id,
    history_marking_periods.mp_type,
    history_marking_periods.name AS title,
    history_marking_periods.short_name,
    NULL::numeric AS sort_order,
    history_marking_periods.parent_id,
    '-1'::integer AS grandparent_id,
    NULL::date AS start_date,
    history_marking_periods.post_end_date AS end_date,
    NULL::date AS post_start_date,
    history_marking_periods.post_end_date,
    'Y'::character varying AS does_grades,
    NULL::character varying AS does_comments
   FROM public.history_marking_periods;


ALTER VIEW public.marking_periods OWNER TO postgres;

--
-- Name: messages; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.messages (
    message_id integer NOT NULL,
    syear numeric(4,0) NOT NULL,
    school_id integer NOT NULL,
    "from" character varying(255),
    recipients text,
    subject character varying(100),
    data text,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.messages OWNER TO postgres;

--
-- Name: messages_message_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.messages_message_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.messages_message_id_seq OWNER TO postgres;

--
-- Name: messages_message_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.messages_message_id_seq OWNED BY public.messages.message_id;


--
-- Name: messagexuser; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.messagexuser (
    user_id integer NOT NULL,
    key character varying(10),
    message_id integer NOT NULL,
    status character varying(10) NOT NULL
);


ALTER TABLE public.messagexuser OWNER TO postgres;

--
-- Name: moodlexrosario; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.moodlexrosario (
    "column" character varying(100) NOT NULL,
    rosario_id integer NOT NULL,
    moodle_id integer NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.moodlexrosario OWNER TO postgres;

--
-- Name: people; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.people (
    person_id integer NOT NULL,
    last_name character varying(50) NOT NULL,
    first_name character varying(50) NOT NULL,
    middle_name character varying(50),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.people OWNER TO postgres;

--
-- Name: people_field_categories; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.people_field_categories (
    id integer NOT NULL,
    title text NOT NULL,
    sort_order numeric,
    custody character(1),
    emergency character(1),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.people_field_categories OWNER TO postgres;

--
-- Name: people_field_categories_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.people_field_categories_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.people_field_categories_id_seq OWNER TO postgres;

--
-- Name: people_field_categories_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.people_field_categories_id_seq OWNED BY public.people_field_categories.id;


--
-- Name: people_fields; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.people_fields (
    id integer NOT NULL,
    type character varying(10),
    title text NOT NULL,
    sort_order numeric,
    select_options text,
    category_id integer,
    required character varying(1),
    default_selection text,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.people_fields OWNER TO postgres;

--
-- Name: people_fields_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.people_fields_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.people_fields_id_seq OWNER TO postgres;

--
-- Name: people_fields_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.people_fields_id_seq OWNED BY public.people_fields.id;


--
-- Name: people_join_contacts; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.people_join_contacts (
    id integer NOT NULL,
    person_id integer,
    title character varying(100),
    value character varying(100),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.people_join_contacts OWNER TO postgres;

--
-- Name: people_join_contacts_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.people_join_contacts_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.people_join_contacts_id_seq OWNER TO postgres;

--
-- Name: people_join_contacts_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.people_join_contacts_id_seq OWNED BY public.people_join_contacts.id;


--
-- Name: people_person_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.people_person_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.people_person_id_seq OWNER TO postgres;

--
-- Name: people_person_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.people_person_id_seq OWNED BY public.people.person_id;


--
-- Name: portal_notes; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.portal_notes (
    id integer NOT NULL,
    school_id integer NOT NULL,
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


ALTER TABLE public.portal_notes OWNER TO postgres;

--
-- Name: portal_notes_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.portal_notes_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.portal_notes_id_seq OWNER TO postgres;

--
-- Name: portal_notes_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.portal_notes_id_seq OWNED BY public.portal_notes.id;


--
-- Name: portal_poll_questions; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.portal_poll_questions (
    id integer NOT NULL,
    portal_poll_id integer NOT NULL,
    question text NOT NULL,
    type character varying(20),
    options text,
    votes text,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.portal_poll_questions OWNER TO postgres;

--
-- Name: portal_poll_questions_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.portal_poll_questions_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.portal_poll_questions_id_seq OWNER TO postgres;

--
-- Name: portal_poll_questions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.portal_poll_questions_id_seq OWNED BY public.portal_poll_questions.id;


--
-- Name: portal_polls; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.portal_polls (
    id integer NOT NULL,
    school_id integer NOT NULL,
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


ALTER TABLE public.portal_polls OWNER TO postgres;

--
-- Name: portal_polls_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.portal_polls_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.portal_polls_id_seq OWNER TO postgres;

--
-- Name: portal_polls_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.portal_polls_id_seq OWNED BY public.portal_polls.id;


--
-- Name: profile_exceptions; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.profile_exceptions (
    profile_id integer NOT NULL,
    modname character varying(150) NOT NULL,
    can_use character varying(1),
    can_edit character varying(1),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.profile_exceptions OWNER TO postgres;

--
-- Name: program_config; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.program_config (
    syear numeric(4,0) NOT NULL,
    school_id integer NOT NULL,
    program character varying(100) NOT NULL,
    title character varying(100) NOT NULL,
    value text,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.program_config OWNER TO postgres;

--
-- Name: program_user_config; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.program_user_config (
    user_id integer NOT NULL,
    program character varying(100) NOT NULL,
    title character varying(100) NOT NULL,
    value text,
    school_id integer,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.program_user_config OWNER TO postgres;

--
-- Name: report_card_comment_categories; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.report_card_comment_categories (
    id integer NOT NULL,
    syear numeric(4,0) NOT NULL,
    school_id integer NOT NULL,
    course_id integer,
    sort_order numeric,
    title text NOT NULL,
    rollover_id integer,
    color character varying(30),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.report_card_comment_categories OWNER TO postgres;

--
-- Name: report_card_comment_categories_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.report_card_comment_categories_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.report_card_comment_categories_id_seq OWNER TO postgres;

--
-- Name: report_card_comment_categories_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.report_card_comment_categories_id_seq OWNED BY public.report_card_comment_categories.id;


--
-- Name: report_card_comment_code_scales; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.report_card_comment_code_scales (
    id integer NOT NULL,
    school_id integer NOT NULL,
    title character varying(25) NOT NULL,
    comment character varying(100),
    sort_order numeric,
    rollover_id integer,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.report_card_comment_code_scales OWNER TO postgres;

--
-- Name: report_card_comment_code_scales_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.report_card_comment_code_scales_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.report_card_comment_code_scales_id_seq OWNER TO postgres;

--
-- Name: report_card_comment_code_scales_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.report_card_comment_code_scales_id_seq OWNED BY public.report_card_comment_code_scales.id;


--
-- Name: report_card_comment_codes; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.report_card_comment_codes (
    id integer NOT NULL,
    school_id integer NOT NULL,
    scale_id integer NOT NULL,
    title character varying(5) NOT NULL,
    short_name character varying(100),
    comment character varying(100),
    sort_order numeric,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.report_card_comment_codes OWNER TO postgres;

--
-- Name: report_card_comment_codes_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.report_card_comment_codes_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.report_card_comment_codes_id_seq OWNER TO postgres;

--
-- Name: report_card_comment_codes_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.report_card_comment_codes_id_seq OWNED BY public.report_card_comment_codes.id;


--
-- Name: report_card_comments; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.report_card_comments (
    id integer NOT NULL,
    syear numeric(4,0) NOT NULL,
    school_id integer NOT NULL,
    course_id integer,
    category_id integer,
    scale_id integer,
    sort_order numeric,
    title text NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.report_card_comments OWNER TO postgres;

--
-- Name: report_card_comments_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.report_card_comments_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.report_card_comments_id_seq OWNER TO postgres;

--
-- Name: report_card_comments_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.report_card_comments_id_seq OWNED BY public.report_card_comments.id;


--
-- Name: report_card_grade_scales; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.report_card_grade_scales (
    id integer NOT NULL,
    syear numeric(4,0) NOT NULL,
    school_id integer NOT NULL,
    title text NOT NULL,
    comment text,
    hhr_gpa_value numeric(7,2),
    hr_gpa_value numeric(7,2),
    sort_order numeric,
    rollover_id integer,
    gp_scale numeric(7,2) NOT NULL,
    gp_passing_value numeric(7,2),
    hrs_gpa_value numeric(7,2),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.report_card_grade_scales OWNER TO postgres;

--
-- Name: report_card_grade_scales_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.report_card_grade_scales_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.report_card_grade_scales_id_seq OWNER TO postgres;

--
-- Name: report_card_grade_scales_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.report_card_grade_scales_id_seq OWNED BY public.report_card_grade_scales.id;


--
-- Name: report_card_grades; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.report_card_grades (
    id integer NOT NULL,
    syear numeric(4,0) NOT NULL,
    school_id integer NOT NULL,
    title character varying(5) NOT NULL,
    sort_order numeric,
    gpa_value numeric(7,2),
    break_off numeric(7,2),
    comment text,
    grade_scale_id integer,
    unweighted_gp numeric(7,2),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.report_card_grades OWNER TO postgres;

--
-- Name: report_card_grades_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.report_card_grades_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.report_card_grades_id_seq OWNER TO postgres;

--
-- Name: report_card_grades_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.report_card_grades_id_seq OWNED BY public.report_card_grades.id;


--
-- Name: resources; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.resources (
    id integer NOT NULL,
    school_id integer NOT NULL,
    title text NOT NULL,
    link text,
    published_profiles text,
    published_grade_levels text,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.resources OWNER TO postgres;

--
-- Name: resources_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.resources_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.resources_id_seq OWNER TO postgres;

--
-- Name: resources_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.resources_id_seq OWNED BY public.resources.id;


--
-- Name: wx_rules_school; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.wx_rules_school (
    id integer NOT NULL,
    title character varying(255) NOT NULL,
    config_value text,
    year numeric(4,0),
    school_id integer NOT NULL
);


ALTER TABLE public.wx_rules_school OWNER TO postgres;

--
-- Name: rules_school_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.rules_school_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.rules_school_id_seq OWNER TO postgres;

--
-- Name: rules_school_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.rules_school_id_seq OWNED BY public.wx_rules_school.id;


--
-- Name: schedule; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.schedule (
    syear numeric(4,0) NOT NULL,
    school_id integer NOT NULL,
    student_id integer NOT NULL,
    start_date date NOT NULL,
    end_date date,
    modified_date date,
    modified_by character varying(255),
    course_id integer NOT NULL,
    course_period_id integer NOT NULL,
    mp character varying(3),
    marking_period_id integer,
    scheduler_lock character varying(1),
    id integer,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.schedule OWNER TO postgres;

--
-- Name: schedule_requests; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.schedule_requests (
    syear numeric(4,0) NOT NULL,
    school_id integer NOT NULL,
    request_id integer NOT NULL,
    student_id integer NOT NULL,
    subject_id integer,
    course_id integer,
    marking_period_id integer,
    priority integer,
    with_teacher_id integer,
    not_teacher_id integer,
    with_period_id integer,
    not_period_id integer,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.schedule_requests OWNER TO postgres;

--
-- Name: schedule_requests_request_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.schedule_requests_request_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.schedule_requests_request_id_seq OWNER TO postgres;

--
-- Name: schedule_requests_request_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.schedule_requests_request_id_seq OWNED BY public.schedule_requests.request_id;


--
-- Name: school_fields; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.school_fields (
    id integer NOT NULL,
    type character varying(10) NOT NULL,
    title text NOT NULL,
    sort_order numeric,
    select_options text,
    required character varying(1),
    default_selection text,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.school_fields OWNER TO postgres;

--
-- Name: school_fields_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.school_fields_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.school_fields_id_seq OWNER TO postgres;

--
-- Name: school_fields_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.school_fields_id_seq OWNED BY public.school_fields.id;


--
-- Name: school_gradelevels_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.school_gradelevels_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.school_gradelevels_id_seq OWNER TO postgres;

--
-- Name: school_gradelevels_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.school_gradelevels_id_seq OWNED BY public.school_gradelevels.id;


--
-- Name: school_periods; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.school_periods (
    period_id integer NOT NULL,
    syear numeric(4,0) NOT NULL,
    school_id integer NOT NULL,
    sort_order numeric,
    title character varying(100) NOT NULL,
    short_name character varying(10),
    length integer,
    start_time character varying(10),
    end_time character varying(10),
    block character varying(10),
    attendance character varying(1),
    rollover_id integer,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.school_periods OWNER TO postgres;

--
-- Name: school_periods_period_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.school_periods_period_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.school_periods_period_id_seq OWNER TO postgres;

--
-- Name: school_periods_period_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.school_periods_period_id_seq OWNED BY public.school_periods.period_id;


--
-- Name: schools; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.schools (
    syear numeric(4,0) NOT NULL,
    id integer NOT NULL,
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


ALTER TABLE public.schools OWNER TO postgres;

--
-- Name: schools_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.schools_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.schools_id_seq OWNER TO postgres;

--
-- Name: schools_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.schools_id_seq OWNED BY public.schools.id;


--
-- Name: staff; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.staff (
    syear numeric(4,0) NOT NULL,
    staff_id integer NOT NULL,
    current_school_id integer,
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
    profile_id integer,
    rollover_id integer,
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
    CONSTRAINT staff_a_salaire_fixe_check CHECK ((a_salaire_fixe = ANY (ARRAY['Y'::bpchar, 'N'::bpchar])))
);


ALTER TABLE public.staff OWNER TO postgres;

--
-- Name: staff_exceptions; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.staff_exceptions (
    user_id integer NOT NULL,
    modname character varying(150) NOT NULL,
    can_use character varying(1),
    can_edit character varying(1),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.staff_exceptions OWNER TO postgres;

--
-- Name: staff_field_categories; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.staff_field_categories (
    id integer NOT NULL,
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


ALTER TABLE public.staff_field_categories OWNER TO postgres;

--
-- Name: staff_field_categories_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.staff_field_categories_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.staff_field_categories_id_seq OWNER TO postgres;

--
-- Name: staff_field_categories_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.staff_field_categories_id_seq OWNED BY public.staff_field_categories.id;


--
-- Name: staff_fields; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.staff_fields (
    id integer NOT NULL,
    type character varying(10) NOT NULL,
    title text NOT NULL,
    sort_order numeric,
    select_options text,
    category_id integer,
    required character varying(1),
    default_selection text,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.staff_fields OWNER TO postgres;

--
-- Name: staff_fields_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.staff_fields_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.staff_fields_id_seq OWNER TO postgres;

--
-- Name: staff_fields_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.staff_fields_id_seq OWNED BY public.staff_fields.id;


--
-- Name: staff_staff_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.staff_staff_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.staff_staff_id_seq OWNER TO postgres;

--
-- Name: staff_staff_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.staff_staff_id_seq OWNED BY public.staff.staff_id;


--
-- Name: student_assignments; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.student_assignments (
    assignment_id integer NOT NULL,
    student_id integer NOT NULL,
    data text,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.student_assignments OWNER TO postgres;

--
-- Name: student_eligibility_activities; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.student_eligibility_activities (
    syear numeric(4,0),
    student_id integer NOT NULL,
    activity_id integer NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.student_eligibility_activities OWNER TO postgres;

--
-- Name: student_enrollment_codes; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.student_enrollment_codes (
    id integer NOT NULL,
    syear numeric(4,0) NOT NULL,
    title character varying(100) NOT NULL,
    short_name character varying(10),
    type character varying(4),
    default_code character varying(1),
    sort_order numeric,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.student_enrollment_codes OWNER TO postgres;

--
-- Name: student_enrollment_codes_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.student_enrollment_codes_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.student_enrollment_codes_id_seq OWNER TO postgres;

--
-- Name: student_enrollment_codes_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.student_enrollment_codes_id_seq OWNED BY public.student_enrollment_codes.id;


--
-- Name: student_enrollment_course_periods; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.student_enrollment_course_periods (
    id integer NOT NULL,
    student_enrollment_id integer NOT NULL,
    course_period_id integer NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE public.student_enrollment_course_periods OWNER TO postgres;

--
-- Name: student_enrollment_course_periods_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.student_enrollment_course_periods_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.student_enrollment_course_periods_id_seq OWNER TO postgres;

--
-- Name: student_enrollment_course_periods_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.student_enrollment_course_periods_id_seq OWNED BY public.student_enrollment_course_periods.id;


--
-- Name: student_enrollment_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.student_enrollment_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.student_enrollment_id_seq OWNER TO postgres;

--
-- Name: student_enrollment_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.student_enrollment_id_seq OWNED BY public.student_enrollment.id;


--
-- Name: student_field_categories; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.student_field_categories (
    id integer NOT NULL,
    title text NOT NULL,
    sort_order numeric,
    columns numeric(4,0),
    include character varying(100),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.student_field_categories OWNER TO postgres;

--
-- Name: student_field_categories_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.student_field_categories_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.student_field_categories_id_seq OWNER TO postgres;

--
-- Name: student_field_categories_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.student_field_categories_id_seq OWNED BY public.student_field_categories.id;


--
-- Name: student_medical; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.student_medical (
    id integer NOT NULL,
    student_id integer NOT NULL,
    type character varying(25),
    medical_date date,
    comments character varying(100),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.student_medical OWNER TO postgres;

--
-- Name: student_medical_alerts; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.student_medical_alerts (
    id integer NOT NULL,
    student_id integer NOT NULL,
    title character varying(100),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.student_medical_alerts OWNER TO postgres;

--
-- Name: student_medical_alerts_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.student_medical_alerts_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.student_medical_alerts_id_seq OWNER TO postgres;

--
-- Name: student_medical_alerts_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.student_medical_alerts_id_seq OWNED BY public.student_medical_alerts.id;


--
-- Name: student_medical_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.student_medical_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.student_medical_id_seq OWNER TO postgres;

--
-- Name: student_medical_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.student_medical_id_seq OWNED BY public.student_medical.id;


--
-- Name: student_medical_visits; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.student_medical_visits (
    id integer NOT NULL,
    student_id integer NOT NULL,
    school_date date,
    time_in character varying(20),
    time_out character varying(20),
    reason character varying(100),
    result character varying(100),
    comments text,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.student_medical_visits OWNER TO postgres;

--
-- Name: student_medical_visits_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.student_medical_visits_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.student_medical_visits_id_seq OWNER TO postgres;

--
-- Name: student_medical_visits_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.student_medical_visits_id_seq OWNED BY public.student_medical_visits.id;


--
-- Name: student_mp_comments; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.student_mp_comments (
    student_id integer NOT NULL,
    syear numeric(4,0) NOT NULL,
    marking_period_id integer NOT NULL,
    comment text,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.student_mp_comments OWNER TO postgres;

--
-- Name: student_mp_stats; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.student_mp_stats (
    student_id integer NOT NULL,
    marking_period_id integer NOT NULL,
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


ALTER TABLE public.student_mp_stats OWNER TO postgres;

--
-- Name: student_report_card_comments; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.student_report_card_comments (
    syear numeric(4,0) NOT NULL,
    school_id integer NOT NULL,
    student_id integer NOT NULL,
    course_period_id integer NOT NULL,
    report_card_comment_id integer NOT NULL,
    comment character varying(5),
    marking_period_id integer NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.student_report_card_comments OWNER TO postgres;

--
-- Name: student_report_card_grades; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.student_report_card_grades (
    syear numeric(4,0) NOT NULL,
    school_id integer NOT NULL,
    student_id integer NOT NULL,
    course_period_id integer,
    report_card_grade_id integer,
    report_card_comment_id integer,
    comment text,
    grade_percent numeric(4,1),
    marking_period_id integer NOT NULL,
    grade_letter character varying(5),
    weighted_gp numeric(7,2),
    unweighted_gp numeric(7,2),
    gp_scale numeric(7,2),
    credit_attempted numeric,
    credit_earned numeric,
    credit_category character varying(10),
    course_title text NOT NULL,
    id integer NOT NULL,
    school text,
    class_rank character varying(1),
    credit_hours numeric(6,2),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.student_report_card_grades OWNER TO postgres;

--
-- Name: student_report_card_grades_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.student_report_card_grades_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.student_report_card_grades_id_seq OWNER TO postgres;

--
-- Name: student_report_card_grades_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.student_report_card_grades_id_seq OWNED BY public.student_report_card_grades.id;


--
-- Name: students; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.students (
    student_id integer NOT NULL,
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


ALTER TABLE public.students OWNER TO postgres;

--
-- Name: students_join_address; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.students_join_address (
    id integer NOT NULL,
    student_id integer NOT NULL,
    address_id integer NOT NULL,
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


ALTER TABLE public.students_join_address OWNER TO postgres;

--
-- Name: students_join_address_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.students_join_address_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.students_join_address_id_seq OWNER TO postgres;

--
-- Name: students_join_address_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.students_join_address_id_seq OWNED BY public.students_join_address.id;


--
-- Name: students_join_people; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.students_join_people (
    id integer NOT NULL,
    student_id integer NOT NULL,
    person_id integer NOT NULL,
    address_id integer,
    custody character varying(1),
    emergency character varying(1),
    student_relation character varying(100),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.students_join_people OWNER TO postgres;

--
-- Name: students_join_people_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.students_join_people_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.students_join_people_id_seq OWNER TO postgres;

--
-- Name: students_join_people_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.students_join_people_id_seq OWNED BY public.students_join_people.id;


--
-- Name: students_join_users; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.students_join_users (
    student_id integer NOT NULL,
    staff_id integer NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.students_join_users OWNER TO postgres;

--
-- Name: students_student_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.students_student_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.students_student_id_seq OWNER TO postgres;

--
-- Name: students_student_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.students_student_id_seq OWNED BY public.students.student_id;


--
-- Name: templates; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.templates (
    modname character varying(150) NOT NULL,
    staff_id integer NOT NULL,
    template text,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.templates OWNER TO postgres;

--
-- Name: transcript_grades; Type: VIEW; Schema: public; Owner: postgres
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
             JOIN public.marking_periods mp2 ON ((mp2.marking_period_id = student_report_card_grades.marking_period_id)))
          WHERE ((student_report_card_grades.student_id = sms.student_id) AND (((student_report_card_grades.marking_period_id)::numeric = mp.parent_id) OR ((student_report_card_grades.marking_period_id)::numeric = mp.grandparent_id)) AND (student_report_card_grades.course_title = srcg.course_title))
          ORDER BY mp2.end_date
         LIMIT 1) AS parent_end_date,
    mp.end_date,
    sms.student_id,
    (sms.cum_weighted_factor * COALESCE(schools.reporting_gp_scale, ( SELECT schools_1.reporting_gp_scale
           FROM public.schools schools_1
          WHERE (mp.school_id = schools_1.id)
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
     LEFT JOIN public.schools ON ((((mp.school_id = schools.id) AND ((mp.mp_source <> 'History'::text) AND (mp.syear = schools.syear))) OR ((mp.mp_source = 'History'::text) AND (mp.syear = ( SELECT schools_1.syear
           FROM public.schools schools_1
          WHERE (mp.school_id = schools_1.id)
          ORDER BY schools_1.syear
         LIMIT 1))))))
  ORDER BY srcg.course_period_id;


ALTER VIEW public.transcript_grades OWNER TO postgres;

--
-- Name: user_profiles; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.user_profiles (
    id integer NOT NULL,
    profile character varying(30),
    title text NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);


ALTER TABLE public.user_profiles OWNER TO postgres;

--
-- Name: user_profiles_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.user_profiles_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.user_profiles_id_seq OWNER TO postgres;

--
-- Name: user_profiles_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.user_profiles_id_seq OWNED BY public.user_profiles.id;


--
-- Name: wx_appreciations; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.wx_appreciations (
    id integer NOT NULL,
    grade_id integer NOT NULL,
    appreciation character varying(255) NOT NULL,
    note_1 character varying(255),
    note_2 character varying(255)
);


ALTER TABLE public.wx_appreciations OWNER TO postgres;

--
-- Name: wx_appreciations_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.wx_appreciations_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.wx_appreciations_id_seq OWNER TO postgres;

--
-- Name: wx_appreciations_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.wx_appreciations_id_seq OWNED BY public.wx_appreciations.id;


--
-- Name: wx_config_publication_resultats; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.wx_config_publication_resultats (
    id integer NOT NULL,
    school_gradelevels_id integer NOT NULL,
    period character varying(50),
    valeur integer,
    syear numeric(4,0)
);


ALTER TABLE public.wx_config_publication_resultats OWNER TO postgres;

--
-- Name: wx_config_publication_resultats_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.wx_config_publication_resultats_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.wx_config_publication_resultats_id_seq OWNER TO postgres;

--
-- Name: wx_config_publication_resultats_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.wx_config_publication_resultats_id_seq OWNED BY public.wx_config_publication_resultats.id;


--
-- Name: wx_course_periods_gradelevels; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.wx_course_periods_gradelevels (
    wx_course_periods_gradelevels_id integer NOT NULL,
    course_periods_id integer NOT NULL,
    school_gradelevels_id integer NOT NULL
);


ALTER TABLE public.wx_course_periods_gradelevels OWNER TO postgres;

--
-- Name: wx_course_periods_gradelevels_wx_course_periods_gradelevels_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.wx_course_periods_gradelevels_wx_course_periods_gradelevels_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.wx_course_periods_gradelevels_wx_course_periods_gradelevels_seq OWNER TO postgres;

--
-- Name: wx_course_periods_gradelevels_wx_course_periods_gradelevels_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.wx_course_periods_gradelevels_wx_course_periods_gradelevels_seq OWNED BY public.wx_course_periods_gradelevels.wx_course_periods_gradelevels_id;


--
-- Name: wx_course_periods_subjects; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.wx_course_periods_subjects (
    wx_course_periods_subjects_id integer NOT NULL,
    course_periods_id integer NOT NULL,
    course_subjects_id integer NOT NULL,
    coefficient character varying(10) DEFAULT 1 NOT NULL,
    teacher_id integer NOT NULL,
    secondary_teacher_id integer,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    ue_id integer,
    period_position character varying(255),
    taux_horaires numeric(10,2),
    ue_compensation character varying(10) DEFAULT false,
    CONSTRAINT chk_taux_horaires_positive CHECK ((taux_horaires >= (0)::numeric))
);


ALTER TABLE public.wx_course_periods_subjects OWNER TO postgres;

--
-- Name: wx_course_periods_subjects_periods; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.wx_course_periods_subjects_periods (
    wx_course_periods_subjects_periods_id integer NOT NULL,
    wx_course_periods_subjects_id integer NOT NULL,
    day character(1) NOT NULL,
    start_time character varying(10) NOT NULL,
    end_time character varying(10) NOT NULL
);


ALTER TABLE public.wx_course_periods_subjects_periods OWNER TO postgres;

--
-- Name: wx_course_periods_subjects_pe_wx_course_periods_subjects_pe_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.wx_course_periods_subjects_pe_wx_course_periods_subjects_pe_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.wx_course_periods_subjects_pe_wx_course_periods_subjects_pe_seq OWNER TO postgres;

--
-- Name: wx_course_periods_subjects_pe_wx_course_periods_subjects_pe_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.wx_course_periods_subjects_pe_wx_course_periods_subjects_pe_seq OWNED BY public.wx_course_periods_subjects_periods.wx_course_periods_subjects_periods_id;


--
-- Name: wx_course_periods_subjects_wx_course_periods_subjects_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.wx_course_periods_subjects_wx_course_periods_subjects_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.wx_course_periods_subjects_wx_course_periods_subjects_id_seq OWNER TO postgres;

--
-- Name: wx_course_periods_subjects_wx_course_periods_subjects_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.wx_course_periods_subjects_wx_course_periods_subjects_id_seq OWNED BY public.wx_course_periods_subjects.wx_course_periods_subjects_id;


--
-- Name: wx_course_subjects_gradelevels; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.wx_course_subjects_gradelevels (
    wx_course_subjects_gradelevels_id integer NOT NULL,
    course_subjects_id integer NOT NULL,
    school_gradelevels_id integer NOT NULL,
    coefficient numeric(5,2) DEFAULT 1.00,
    semester_type character varying(10)
);


ALTER TABLE public.wx_course_subjects_gradelevels OWNER TO postgres;

--
-- Name: wx_course_subjects_gradelevel_wx_course_subjects_gradelevel_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.wx_course_subjects_gradelevel_wx_course_subjects_gradelevel_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.wx_course_subjects_gradelevel_wx_course_subjects_gradelevel_seq OWNER TO postgres;

--
-- Name: wx_course_subjects_gradelevel_wx_course_subjects_gradelevel_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.wx_course_subjects_gradelevel_wx_course_subjects_gradelevel_seq OWNED BY public.wx_course_subjects_gradelevels.wx_course_subjects_gradelevels_id;


--
-- Name: wx_custom_configuration_school; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.wx_custom_configuration_school (
    id_custom_configuration_school integer NOT NULL,
    school_id integer NOT NULL,
    type_school character varying(255)
);


ALTER TABLE public.wx_custom_configuration_school OWNER TO postgres;

--
-- Name: wx_custom_configuration_schoo_id_custom_configuration_schoo_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.wx_custom_configuration_schoo_id_custom_configuration_schoo_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.wx_custom_configuration_schoo_id_custom_configuration_schoo_seq OWNER TO postgres;

--
-- Name: wx_custom_configuration_schoo_id_custom_configuration_schoo_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.wx_custom_configuration_schoo_id_custom_configuration_schoo_seq OWNED BY public.wx_custom_configuration_school.id_custom_configuration_school;


--
-- Name: wx_echelle_notation_appreciation; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.wx_echelle_notation_appreciation (
    id integer NOT NULL,
    note_debut double precision NOT NULL,
    note_fin double precision NOT NULL,
    echelle_notation integer NOT NULL,
    appreciation character varying(5),
    year numeric(4,0),
    school_id integer NOT NULL
);


ALTER TABLE public.wx_echelle_notation_appreciation OWNER TO postgres;

--
-- Name: wx_echelle_notation_appreciation_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.wx_echelle_notation_appreciation_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.wx_echelle_notation_appreciation_id_seq OWNER TO postgres;

--
-- Name: wx_echelle_notation_appreciation_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.wx_echelle_notation_appreciation_id_seq OWNED BY public.wx_echelle_notation_appreciation.id;


--
-- Name: wx_families; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.wx_families (
    id integer NOT NULL,
    name character varying(100) NOT NULL,
    amount numeric(10,2) DEFAULT 0.00 NOT NULL,
    school_id integer NOT NULL,
    syear integer NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.wx_families OWNER TO postgres;

--
-- Name: wx_families_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.wx_families_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.wx_families_id_seq OWNER TO postgres;

--
-- Name: wx_families_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.wx_families_id_seq OWNED BY public.wx_families.id;


--
-- Name: wx_family_members; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.wx_family_members (
    id integer NOT NULL,
    family_id integer NOT NULL,
    student_id integer NOT NULL,
    is_representative boolean DEFAULT false NOT NULL
);


ALTER TABLE public.wx_family_members OWNER TO postgres;

--
-- Name: wx_family_members_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.wx_family_members_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.wx_family_members_id_seq OWNER TO postgres;

--
-- Name: wx_family_members_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.wx_family_members_id_seq OWNED BY public.wx_family_members.id;


--
-- Name: wx_gradel_period_evaluation; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.wx_gradel_period_evaluation (
    id_gradel_period_evaluation integer NOT NULL,
    school_gradelevels_id integer NOT NULL,
    type_period_evaluation character varying(20),
    year numeric(4,0) NOT NULL,
    allow_debt_passage boolean DEFAULT false,
    debt_passage_percentage numeric(5,2) DEFAULT 0.00,
    eliminatory_note numeric(5,2) DEFAULT 0.00,
    debt_passage_percentage_devoir numeric(5,2) DEFAULT 0,
    debt_passage_percentage_session numeric(5,2) DEFAULT 0,
    eliminatory_mark numeric(5,2) DEFAULT 0,
    is_passage_with_debt character varying(1) DEFAULT 0,
    percentage_of_credit_for_passage numeric(5,2) DEFAULT 0,
    is_compensable character varying(1) DEFAULT 0
);


ALTER TABLE public.wx_gradel_period_evaluation OWNER TO postgres;

--
-- Name: wx_gradel_period_evaluation_id_gradel_period_evaluation_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.wx_gradel_period_evaluation_id_gradel_period_evaluation_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.wx_gradel_period_evaluation_id_gradel_period_evaluation_seq OWNER TO postgres;

--
-- Name: wx_gradel_period_evaluation_id_gradel_period_evaluation_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.wx_gradel_period_evaluation_id_gradel_period_evaluation_seq OWNED BY public.wx_gradel_period_evaluation.id_gradel_period_evaluation;


--
-- Name: wx_moyennes_finales_students; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.wx_moyennes_finales_students (
    id integer NOT NULL,
    student_enrollment_id integer NOT NULL,
    moyenne double precision NOT NULL,
    exam_type character varying(10)
);


ALTER TABLE public.wx_moyennes_finales_students OWNER TO postgres;

--
-- Name: wx_moyennes_finales_students_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.wx_moyennes_finales_students_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.wx_moyennes_finales_students_id_seq OWNER TO postgres;

--
-- Name: wx_moyennes_finales_students_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.wx_moyennes_finales_students_id_seq OWNED BY public.wx_moyennes_finales_students.id;


--
-- Name: wx_moyennes_validation_gradelevel; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.wx_moyennes_validation_gradelevel (
    id integer NOT NULL,
    school_gradelevels_id integer NOT NULL,
    moyenne double precision NOT NULL,
    syear numeric(4,0)
);


ALTER TABLE public.wx_moyennes_validation_gradelevel OWNER TO postgres;

--
-- Name: wx_moyennes_validation_gradelevel_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.wx_moyennes_validation_gradelevel_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.wx_moyennes_validation_gradelevel_id_seq OWNER TO postgres;

--
-- Name: wx_moyennes_validation_gradelevel_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.wx_moyennes_validation_gradelevel_id_seq OWNED BY public.wx_moyennes_validation_gradelevel.id;


--
-- Name: wx_notes_details; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.wx_notes_details (
    id_notes_details integer NOT NULL,
    type_dev character varying(255) NOT NULL,
    numero_dev integer NOT NULL,
    course_period_id integer NOT NULL,
    mounth character varying(3) NOT NULL,
    discipline integer NOT NULL,
    date_dev timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE public.wx_notes_details OWNER TO postgres;

--
-- Name: wx_notes_details_id_notes_details_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.wx_notes_details_id_notes_details_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.wx_notes_details_id_notes_details_seq OWNER TO postgres;

--
-- Name: wx_notes_details_id_notes_details_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.wx_notes_details_id_notes_details_seq OWNED BY public.wx_notes_details.id_notes_details;


--
-- Name: wx_notes_student_details; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.wx_notes_student_details (
    id_notes_student_details integer NOT NULL,
    wx_course_periods_subjects_id integer NOT NULL,
    type_dev character varying(255) NOT NULL,
    numero_dev integer NOT NULL,
    student_id integer NOT NULL,
    course_period_id integer NOT NULL,
    mounth character varying(3) NOT NULL,
    discipline integer NOT NULL,
    note double precision
);


ALTER TABLE public.wx_notes_student_details OWNER TO postgres;

--
-- Name: wx_notes_student_details_id_notes_student_details_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.wx_notes_student_details_id_notes_student_details_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.wx_notes_student_details_id_notes_student_details_seq OWNER TO postgres;

--
-- Name: wx_notes_student_details_id_notes_student_details_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.wx_notes_student_details_id_notes_student_details_seq OWNED BY public.wx_notes_student_details.id_notes_student_details;


--
-- Name: wx_reduction_eleve; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.wx_reduction_eleve (
    id integer NOT NULL,
    name character varying(100) NOT NULL,
    amount numeric(10,2) DEFAULT 0.00 NOT NULL,
    school_id integer NOT NULL,
    syear integer NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.wx_reduction_eleve OWNER TO postgres;

--
-- Name: wx_reduction_eleve_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.wx_reduction_eleve_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.wx_reduction_eleve_id_seq OWNER TO postgres;

--
-- Name: wx_reduction_eleve_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.wx_reduction_eleve_id_seq OWNED BY public.wx_reduction_eleve.id;


--
-- Name: wx_reduction_members; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.wx_reduction_members (
    id integer NOT NULL,
    reduction_id integer NOT NULL,
    student_id integer NOT NULL
);


ALTER TABLE public.wx_reduction_members OWNER TO postgres;

--
-- Name: wx_reduction_members_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.wx_reduction_members_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.wx_reduction_members_id_seq OWNER TO postgres;

--
-- Name: wx_reduction_members_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.wx_reduction_members_id_seq OWNED BY public.wx_reduction_members.id;


--
-- Name: wx_teacher_attendance; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.wx_teacher_attendance (
    id integer NOT NULL,
    staff_id integer NOT NULL,
    date date NOT NULL,
    start_time time without time zone NOT NULL,
    end_time time without time zone NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    done boolean DEFAULT true NOT NULL,
    comments text,
    hour_type character varying DEFAULT 'non_programmed'::character varying NOT NULL
);


ALTER TABLE public.wx_teacher_attendance OWNER TO postgres;

--
-- Name: wx_teacher_attendance_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.wx_teacher_attendance_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.wx_teacher_attendance_id_seq OWNER TO postgres;

--
-- Name: wx_teacher_attendance_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.wx_teacher_attendance_id_seq OWNED BY public.wx_teacher_attendance.id;


--
-- Name: wx_ues; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.wx_ues (
    id integer NOT NULL,
    title character varying(100),
    gradelevel_id integer,
    is_required character(1) DEFAULT 'N'::bpchar,
    credit double precision,
    syear integer,
    school_id integer,
    course_period_id integer
);


ALTER TABLE public.wx_ues OWNER TO postgres;

--
-- Name: wx_ues_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.wx_ues_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.wx_ues_id_seq OWNER TO postgres;

--
-- Name: wx_ues_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.wx_ues_id_seq OWNED BY public.wx_ues.id;


--
-- Name: wx_ues_subjects; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.wx_ues_subjects (
    id integer NOT NULL,
    ue_id integer,
    subject_id integer
);


ALTER TABLE public.wx_ues_subjects OWNER TO postgres;

--
-- Name: wx_ues_subjects_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.wx_ues_subjects_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.wx_ues_subjects_id_seq OWNER TO postgres;

--
-- Name: wx_ues_subjects_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.wx_ues_subjects_id_seq OWNED BY public.wx_ues_subjects.id;


--
-- Name: accounting_categories id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.accounting_categories ALTER COLUMN id SET DEFAULT nextval('public.accounting_categories_id_seq'::regclass);


--
-- Name: accounting_incomes id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.accounting_incomes ALTER COLUMN id SET DEFAULT nextval('public.accounting_incomes_id_seq'::regclass);


--
-- Name: accounting_payments id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.accounting_payments ALTER COLUMN id SET DEFAULT nextval('public.accounting_payments_id_seq'::regclass);


--
-- Name: accounting_salaries id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.accounting_salaries ALTER COLUMN id SET DEFAULT nextval('public.accounting_salaries_id_seq'::regclass);


--
-- Name: address address_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.address ALTER COLUMN address_id SET DEFAULT nextval('public.address_address_id_seq'::regclass);


--
-- Name: address_field_categories id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.address_field_categories ALTER COLUMN id SET DEFAULT nextval('public.address_field_categories_id_seq'::regclass);


--
-- Name: address_fields id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.address_fields ALTER COLUMN id SET DEFAULT nextval('public.address_fields_id_seq'::regclass);


--
-- Name: attendance_calendars calendar_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.attendance_calendars ALTER COLUMN calendar_id SET DEFAULT nextval('public.attendance_calendars_calendar_id_seq'::regclass);


--
-- Name: attendance_code_categories id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.attendance_code_categories ALTER COLUMN id SET DEFAULT nextval('public.attendance_code_categories_id_seq'::regclass);


--
-- Name: attendance_codes id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.attendance_codes ALTER COLUMN id SET DEFAULT nextval('public.attendance_codes_id_seq'::regclass);


--
-- Name: billing_fees id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.billing_fees ALTER COLUMN id SET DEFAULT nextval('public.billing_fees_id_seq'::regclass);


--
-- Name: billing_payments id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.billing_payments ALTER COLUMN id SET DEFAULT nextval('public.billing_payments_id_seq'::regclass);


--
-- Name: bordereaux_details id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.bordereaux_details ALTER COLUMN id SET DEFAULT nextval('public.bordereaux_details_id_seq'::regclass);


--
-- Name: calendar_events id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.calendar_events ALTER COLUMN id SET DEFAULT nextval('public.calendar_events_id_seq'::regclass);


--
-- Name: course_period_school_periods course_period_school_periods_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.course_period_school_periods ALTER COLUMN course_period_school_periods_id SET DEFAULT nextval('public.course_period_school_periods_course_period_school_periods_i_seq'::regclass);


--
-- Name: course_periods course_period_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.course_periods ALTER COLUMN course_period_id SET DEFAULT nextval('public.course_periods_course_period_id_seq'::regclass);


--
-- Name: course_subjects subject_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.course_subjects ALTER COLUMN subject_id SET DEFAULT nextval('public.course_subjects_subject_id_seq'::regclass);


--
-- Name: courses course_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.courses ALTER COLUMN course_id SET DEFAULT nextval('public.courses_course_id_seq'::regclass);


--
-- Name: custom_fields id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.custom_fields ALTER COLUMN id SET DEFAULT nextval('public.custom_fields_id_seq'::regclass);


--
-- Name: discipline_field_usage id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.discipline_field_usage ALTER COLUMN id SET DEFAULT nextval('public.discipline_field_usage_id_seq'::regclass);


--
-- Name: discipline_fields id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.discipline_fields ALTER COLUMN id SET DEFAULT nextval('public.discipline_fields_id_seq'::regclass);


--
-- Name: discipline_referrals id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.discipline_referrals ALTER COLUMN id SET DEFAULT nextval('public.discipline_referrals_id_seq'::regclass);


--
-- Name: eligibility_activities id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.eligibility_activities ALTER COLUMN id SET DEFAULT nextval('public.eligibility_activities_id_seq'::regclass);


--
-- Name: food_service_categories category_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.food_service_categories ALTER COLUMN category_id SET DEFAULT nextval('public.food_service_categories_category_id_seq'::regclass);


--
-- Name: food_service_items item_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.food_service_items ALTER COLUMN item_id SET DEFAULT nextval('public.food_service_items_item_id_seq'::regclass);


--
-- Name: food_service_menu_items menu_item_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.food_service_menu_items ALTER COLUMN menu_item_id SET DEFAULT nextval('public.food_service_menu_items_menu_item_id_seq'::regclass);


--
-- Name: food_service_menus menu_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.food_service_menus ALTER COLUMN menu_id SET DEFAULT nextval('public.food_service_menus_menu_id_seq'::regclass);


--
-- Name: food_service_staff_transactions transaction_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.food_service_staff_transactions ALTER COLUMN transaction_id SET DEFAULT nextval('public.food_service_staff_transactions_transaction_id_seq'::regclass);


--
-- Name: food_service_transactions transaction_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.food_service_transactions ALTER COLUMN transaction_id SET DEFAULT nextval('public.food_service_transactions_transaction_id_seq'::regclass);


--
-- Name: grade_levels id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.grade_levels ALTER COLUMN id SET DEFAULT nextval('public.grade_levels_id_seq'::regclass);


--
-- Name: gradebook_assignment_types assignment_type_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.gradebook_assignment_types ALTER COLUMN assignment_type_id SET DEFAULT nextval('public.gradebook_assignment_types_assignment_type_id_seq'::regclass);


--
-- Name: gradebook_assignments assignment_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.gradebook_assignments ALTER COLUMN assignment_id SET DEFAULT nextval('public.gradebook_assignments_assignment_id_seq'::regclass);


--
-- Name: messages message_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.messages ALTER COLUMN message_id SET DEFAULT nextval('public.messages_message_id_seq'::regclass);


--
-- Name: people person_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.people ALTER COLUMN person_id SET DEFAULT nextval('public.people_person_id_seq'::regclass);


--
-- Name: people_field_categories id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.people_field_categories ALTER COLUMN id SET DEFAULT nextval('public.people_field_categories_id_seq'::regclass);


--
-- Name: people_fields id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.people_fields ALTER COLUMN id SET DEFAULT nextval('public.people_fields_id_seq'::regclass);


--
-- Name: people_join_contacts id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.people_join_contacts ALTER COLUMN id SET DEFAULT nextval('public.people_join_contacts_id_seq'::regclass);


--
-- Name: portal_notes id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.portal_notes ALTER COLUMN id SET DEFAULT nextval('public.portal_notes_id_seq'::regclass);


--
-- Name: portal_poll_questions id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.portal_poll_questions ALTER COLUMN id SET DEFAULT nextval('public.portal_poll_questions_id_seq'::regclass);


--
-- Name: portal_polls id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.portal_polls ALTER COLUMN id SET DEFAULT nextval('public.portal_polls_id_seq'::regclass);


--
-- Name: report_card_comment_categories id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.report_card_comment_categories ALTER COLUMN id SET DEFAULT nextval('public.report_card_comment_categories_id_seq'::regclass);


--
-- Name: report_card_comment_code_scales id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.report_card_comment_code_scales ALTER COLUMN id SET DEFAULT nextval('public.report_card_comment_code_scales_id_seq'::regclass);


--
-- Name: report_card_comment_codes id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.report_card_comment_codes ALTER COLUMN id SET DEFAULT nextval('public.report_card_comment_codes_id_seq'::regclass);


--
-- Name: report_card_comments id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.report_card_comments ALTER COLUMN id SET DEFAULT nextval('public.report_card_comments_id_seq'::regclass);


--
-- Name: report_card_grade_scales id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.report_card_grade_scales ALTER COLUMN id SET DEFAULT nextval('public.report_card_grade_scales_id_seq'::regclass);


--
-- Name: report_card_grades id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.report_card_grades ALTER COLUMN id SET DEFAULT nextval('public.report_card_grades_id_seq'::regclass);


--
-- Name: resources id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.resources ALTER COLUMN id SET DEFAULT nextval('public.resources_id_seq'::regclass);


--
-- Name: schedule_requests request_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.schedule_requests ALTER COLUMN request_id SET DEFAULT nextval('public.schedule_requests_request_id_seq'::regclass);


--
-- Name: school_fields id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.school_fields ALTER COLUMN id SET DEFAULT nextval('public.school_fields_id_seq'::regclass);


--
-- Name: school_gradelevels id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.school_gradelevels ALTER COLUMN id SET DEFAULT nextval('public.school_gradelevels_id_seq'::regclass);


--
-- Name: school_marking_periods marking_period_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.school_marking_periods ALTER COLUMN marking_period_id SET DEFAULT nextval('public.school_marking_periods_marking_period_id_seq'::regclass);


--
-- Name: school_periods period_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.school_periods ALTER COLUMN period_id SET DEFAULT nextval('public.school_periods_period_id_seq'::regclass);


--
-- Name: schools id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.schools ALTER COLUMN id SET DEFAULT nextval('public.schools_id_seq'::regclass);


--
-- Name: staff staff_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.staff ALTER COLUMN staff_id SET DEFAULT nextval('public.staff_staff_id_seq'::regclass);


--
-- Name: staff_field_categories id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.staff_field_categories ALTER COLUMN id SET DEFAULT nextval('public.staff_field_categories_id_seq'::regclass);


--
-- Name: staff_fields id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.staff_fields ALTER COLUMN id SET DEFAULT nextval('public.staff_fields_id_seq'::regclass);


--
-- Name: student_enrollment id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.student_enrollment ALTER COLUMN id SET DEFAULT nextval('public.student_enrollment_id_seq'::regclass);


--
-- Name: student_enrollment_codes id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.student_enrollment_codes ALTER COLUMN id SET DEFAULT nextval('public.student_enrollment_codes_id_seq'::regclass);


--
-- Name: student_enrollment_course_periods id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.student_enrollment_course_periods ALTER COLUMN id SET DEFAULT nextval('public.student_enrollment_course_periods_id_seq'::regclass);


--
-- Name: student_field_categories id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.student_field_categories ALTER COLUMN id SET DEFAULT nextval('public.student_field_categories_id_seq'::regclass);


--
-- Name: student_medical id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.student_medical ALTER COLUMN id SET DEFAULT nextval('public.student_medical_id_seq'::regclass);


--
-- Name: student_medical_alerts id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.student_medical_alerts ALTER COLUMN id SET DEFAULT nextval('public.student_medical_alerts_id_seq'::regclass);


--
-- Name: student_medical_visits id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.student_medical_visits ALTER COLUMN id SET DEFAULT nextval('public.student_medical_visits_id_seq'::regclass);


--
-- Name: student_report_card_grades id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.student_report_card_grades ALTER COLUMN id SET DEFAULT nextval('public.student_report_card_grades_id_seq'::regclass);


--
-- Name: students student_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.students ALTER COLUMN student_id SET DEFAULT nextval('public.students_student_id_seq'::regclass);


--
-- Name: students_join_address id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.students_join_address ALTER COLUMN id SET DEFAULT nextval('public.students_join_address_id_seq'::regclass);


--
-- Name: students_join_people id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.students_join_people ALTER COLUMN id SET DEFAULT nextval('public.students_join_people_id_seq'::regclass);


--
-- Name: user_profiles id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_profiles ALTER COLUMN id SET DEFAULT nextval('public.user_profiles_id_seq'::regclass);


--
-- Name: wx_appreciations id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wx_appreciations ALTER COLUMN id SET DEFAULT nextval('public.wx_appreciations_id_seq'::regclass);


--
-- Name: wx_config_publication_resultats id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wx_config_publication_resultats ALTER COLUMN id SET DEFAULT nextval('public.wx_config_publication_resultats_id_seq'::regclass);


--
-- Name: wx_course_periods_gradelevels wx_course_periods_gradelevels_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wx_course_periods_gradelevels ALTER COLUMN wx_course_periods_gradelevels_id SET DEFAULT nextval('public.wx_course_periods_gradelevels_wx_course_periods_gradelevels_seq'::regclass);


--
-- Name: wx_course_periods_subjects wx_course_periods_subjects_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wx_course_periods_subjects ALTER COLUMN wx_course_periods_subjects_id SET DEFAULT nextval('public.wx_course_periods_subjects_wx_course_periods_subjects_id_seq'::regclass);


--
-- Name: wx_course_periods_subjects_periods wx_course_periods_subjects_periods_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wx_course_periods_subjects_periods ALTER COLUMN wx_course_periods_subjects_periods_id SET DEFAULT nextval('public.wx_course_periods_subjects_pe_wx_course_periods_subjects_pe_seq'::regclass);


--
-- Name: wx_course_subjects_gradelevels wx_course_subjects_gradelevels_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wx_course_subjects_gradelevels ALTER COLUMN wx_course_subjects_gradelevels_id SET DEFAULT nextval('public.wx_course_subjects_gradelevel_wx_course_subjects_gradelevel_seq'::regclass);


--
-- Name: wx_custom_configuration_school id_custom_configuration_school; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wx_custom_configuration_school ALTER COLUMN id_custom_configuration_school SET DEFAULT nextval('public.wx_custom_configuration_schoo_id_custom_configuration_schoo_seq'::regclass);


--
-- Name: wx_echelle_notation_appreciation id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wx_echelle_notation_appreciation ALTER COLUMN id SET DEFAULT nextval('public.wx_echelle_notation_appreciation_id_seq'::regclass);


--
-- Name: wx_families id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wx_families ALTER COLUMN id SET DEFAULT nextval('public.wx_families_id_seq'::regclass);


--
-- Name: wx_family_members id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wx_family_members ALTER COLUMN id SET DEFAULT nextval('public.wx_family_members_id_seq'::regclass);


--
-- Name: wx_gradel_period_evaluation id_gradel_period_evaluation; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wx_gradel_period_evaluation ALTER COLUMN id_gradel_period_evaluation SET DEFAULT nextval('public.wx_gradel_period_evaluation_id_gradel_period_evaluation_seq'::regclass);


--
-- Name: wx_moyennes_finales_students id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wx_moyennes_finales_students ALTER COLUMN id SET DEFAULT nextval('public.wx_moyennes_finales_students_id_seq'::regclass);


--
-- Name: wx_moyennes_validation_gradelevel id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wx_moyennes_validation_gradelevel ALTER COLUMN id SET DEFAULT nextval('public.wx_moyennes_validation_gradelevel_id_seq'::regclass);


--
-- Name: wx_notes_details id_notes_details; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wx_notes_details ALTER COLUMN id_notes_details SET DEFAULT nextval('public.wx_notes_details_id_notes_details_seq'::regclass);


--
-- Name: wx_notes_student_details id_notes_student_details; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wx_notes_student_details ALTER COLUMN id_notes_student_details SET DEFAULT nextval('public.wx_notes_student_details_id_notes_student_details_seq'::regclass);


--
-- Name: wx_reduction_eleve id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wx_reduction_eleve ALTER COLUMN id SET DEFAULT nextval('public.wx_reduction_eleve_id_seq'::regclass);


--
-- Name: wx_reduction_members id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wx_reduction_members ALTER COLUMN id SET DEFAULT nextval('public.wx_reduction_members_id_seq'::regclass);


--
-- Name: wx_rules_school id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wx_rules_school ALTER COLUMN id SET DEFAULT nextval('public.rules_school_id_seq'::regclass);


--
-- Name: wx_teacher_attendance id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wx_teacher_attendance ALTER COLUMN id SET DEFAULT nextval('public.wx_teacher_attendance_id_seq'::regclass);


--
-- Name: wx_ues id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wx_ues ALTER COLUMN id SET DEFAULT nextval('public.wx_ues_id_seq'::regclass);


--
-- Name: wx_ues_subjects id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wx_ues_subjects ALTER COLUMN id SET DEFAULT nextval('public.wx_ues_subjects_id_seq'::regclass);


--
-- Name: accounting_categories accounting_categories_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.accounting_categories
    ADD CONSTRAINT accounting_categories_pkey PRIMARY KEY (id);


--
-- Name: accounting_incomes accounting_incomes_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.accounting_incomes
    ADD CONSTRAINT accounting_incomes_pkey PRIMARY KEY (id);


--
-- Name: accounting_payments accounting_payments_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.accounting_payments
    ADD CONSTRAINT accounting_payments_pkey PRIMARY KEY (id);


--
-- Name: accounting_salaries accounting_salaries_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.accounting_salaries
    ADD CONSTRAINT accounting_salaries_pkey PRIMARY KEY (id);


--
-- Name: address_field_categories address_field_categories_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.address_field_categories
    ADD CONSTRAINT address_field_categories_pkey PRIMARY KEY (id);


--
-- Name: address_fields address_fields_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.address_fields
    ADD CONSTRAINT address_fields_pkey PRIMARY KEY (id);


--
-- Name: address address_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.address
    ADD CONSTRAINT address_pkey PRIMARY KEY (address_id);


--
-- Name: attendance_calendar attendance_calendar_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.attendance_calendar
    ADD CONSTRAINT attendance_calendar_pkey PRIMARY KEY (syear, school_id, school_date, calendar_id);


--
-- Name: attendance_calendars attendance_calendars_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.attendance_calendars
    ADD CONSTRAINT attendance_calendars_pkey PRIMARY KEY (calendar_id);


--
-- Name: attendance_code_categories attendance_code_categories_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.attendance_code_categories
    ADD CONSTRAINT attendance_code_categories_pkey PRIMARY KEY (id);


--
-- Name: attendance_codes attendance_codes_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.attendance_codes
    ADD CONSTRAINT attendance_codes_pkey PRIMARY KEY (id);


--
-- Name: attendance_completed attendance_completed_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.attendance_completed
    ADD CONSTRAINT attendance_completed_pkey PRIMARY KEY (staff_id, school_date, period_id, table_name);


--
-- Name: attendance_day attendance_day_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.attendance_day
    ADD CONSTRAINT attendance_day_pkey PRIMARY KEY (student_id, school_date);


--
-- Name: billing_fees billing_fees_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.billing_fees
    ADD CONSTRAINT billing_fees_pkey PRIMARY KEY (id);


--
-- Name: billing_payments billing_payments_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.billing_payments
    ADD CONSTRAINT billing_payments_pkey PRIMARY KEY (id);


--
-- Name: bordereaux_details bordereaux_details_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.bordereaux_details
    ADD CONSTRAINT bordereaux_details_pkey PRIMARY KEY (id);


--
-- Name: bordereaux_details bordereaux_details_staff_id_month_year_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.bordereaux_details
    ADD CONSTRAINT bordereaux_details_staff_id_month_year_key UNIQUE (staff_id, month, year);


--
-- Name: calendar_events calendar_events_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.calendar_events
    ADD CONSTRAINT calendar_events_pkey PRIMARY KEY (id);


--
-- Name: course_period_school_periods course_period_school_periods_course_period_id_period_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.course_period_school_periods
    ADD CONSTRAINT course_period_school_periods_course_period_id_period_id_key UNIQUE (course_period_id, period_id);


--
-- Name: course_period_school_periods course_period_school_periods_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.course_period_school_periods
    ADD CONSTRAINT course_period_school_periods_pkey PRIMARY KEY (course_period_school_periods_id);


--
-- Name: course_periods course_periods_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.course_periods
    ADD CONSTRAINT course_periods_pkey PRIMARY KEY (course_period_id);


--
-- Name: course_subjects course_subjects_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.course_subjects
    ADD CONSTRAINT course_subjects_pkey PRIMARY KEY (subject_id);


--
-- Name: courses courses_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.courses
    ADD CONSTRAINT courses_pkey PRIMARY KEY (course_id);


--
-- Name: custom_fields custom_fields_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.custom_fields
    ADD CONSTRAINT custom_fields_pkey PRIMARY KEY (id);


--
-- Name: discipline_field_usage discipline_field_usage_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.discipline_field_usage
    ADD CONSTRAINT discipline_field_usage_pkey PRIMARY KEY (id);


--
-- Name: discipline_fields discipline_fields_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.discipline_fields
    ADD CONSTRAINT discipline_fields_pkey PRIMARY KEY (id);


--
-- Name: discipline_referrals discipline_referrals_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.discipline_referrals
    ADD CONSTRAINT discipline_referrals_pkey PRIMARY KEY (id);


--
-- Name: eligibility_activities eligibility_activities_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.eligibility_activities
    ADD CONSTRAINT eligibility_activities_pkey PRIMARY KEY (id);


--
-- Name: eligibility_completed eligibility_completed_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.eligibility_completed
    ADD CONSTRAINT eligibility_completed_pkey PRIMARY KEY (staff_id, school_date, period_id);


--
-- Name: food_service_accounts food_service_accounts_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.food_service_accounts
    ADD CONSTRAINT food_service_accounts_pkey PRIMARY KEY (account_id);


--
-- Name: food_service_categories food_service_categories_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.food_service_categories
    ADD CONSTRAINT food_service_categories_pkey PRIMARY KEY (category_id);


--
-- Name: food_service_items food_service_items_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.food_service_items
    ADD CONSTRAINT food_service_items_pkey PRIMARY KEY (item_id);


--
-- Name: food_service_menu_items food_service_menu_items_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.food_service_menu_items
    ADD CONSTRAINT food_service_menu_items_pkey PRIMARY KEY (menu_item_id);


--
-- Name: food_service_menus food_service_menus_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.food_service_menus
    ADD CONSTRAINT food_service_menus_pkey PRIMARY KEY (menu_id);


--
-- Name: food_service_staff_accounts food_service_staff_accounts_barcode_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.food_service_staff_accounts
    ADD CONSTRAINT food_service_staff_accounts_barcode_key UNIQUE (barcode);


--
-- Name: food_service_staff_accounts food_service_staff_accounts_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.food_service_staff_accounts
    ADD CONSTRAINT food_service_staff_accounts_pkey PRIMARY KEY (staff_id);


--
-- Name: food_service_staff_transaction_items food_service_staff_transaction_items_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.food_service_staff_transaction_items
    ADD CONSTRAINT food_service_staff_transaction_items_pkey PRIMARY KEY (item_id, transaction_id);


--
-- Name: food_service_staff_transactions food_service_staff_transactions_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.food_service_staff_transactions
    ADD CONSTRAINT food_service_staff_transactions_pkey PRIMARY KEY (transaction_id);


--
-- Name: food_service_student_accounts food_service_student_accounts_barcode_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.food_service_student_accounts
    ADD CONSTRAINT food_service_student_accounts_barcode_key UNIQUE (barcode);


--
-- Name: food_service_student_accounts food_service_student_accounts_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.food_service_student_accounts
    ADD CONSTRAINT food_service_student_accounts_pkey PRIMARY KEY (student_id);


--
-- Name: food_service_transaction_items food_service_transaction_items_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.food_service_transaction_items
    ADD CONSTRAINT food_service_transaction_items_pkey PRIMARY KEY (item_id, transaction_id);


--
-- Name: food_service_transactions food_service_transactions_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.food_service_transactions
    ADD CONSTRAINT food_service_transactions_pkey PRIMARY KEY (transaction_id);


--
-- Name: grade_levels grade_levels_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.grade_levels
    ADD CONSTRAINT grade_levels_pkey PRIMARY KEY (id);


--
-- Name: gradebook_assignment_types gradebook_assignment_types_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.gradebook_assignment_types
    ADD CONSTRAINT gradebook_assignment_types_pkey PRIMARY KEY (assignment_type_id);


--
-- Name: gradebook_assignments gradebook_assignments_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.gradebook_assignments
    ADD CONSTRAINT gradebook_assignments_pkey PRIMARY KEY (assignment_id);


--
-- Name: gradebook_grades gradebook_grades_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.gradebook_grades
    ADD CONSTRAINT gradebook_grades_pkey PRIMARY KEY (student_id, assignment_id, course_period_id);


--
-- Name: grades_completed grades_completed_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.grades_completed
    ADD CONSTRAINT grades_completed_pkey PRIMARY KEY (staff_id, marking_period_id, course_period_id);


--
-- Name: history_marking_periods history_marking_periods_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.history_marking_periods
    ADD CONSTRAINT history_marking_periods_pkey PRIMARY KEY (marking_period_id);


--
-- Name: lunch_period lunch_period_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.lunch_period
    ADD CONSTRAINT lunch_period_pkey PRIMARY KEY (student_id, school_date, period_id);


--
-- Name: messages messages_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.messages
    ADD CONSTRAINT messages_pkey PRIMARY KEY (message_id);


--
-- Name: moodlexrosario moodlexrosario_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.moodlexrosario
    ADD CONSTRAINT moodlexrosario_pkey PRIMARY KEY ("column", rosario_id);


--
-- Name: people_field_categories people_field_categories_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.people_field_categories
    ADD CONSTRAINT people_field_categories_pkey PRIMARY KEY (id);


--
-- Name: people_fields people_fields_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.people_fields
    ADD CONSTRAINT people_fields_pkey PRIMARY KEY (id);


--
-- Name: people_join_contacts people_join_contacts_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.people_join_contacts
    ADD CONSTRAINT people_join_contacts_pkey PRIMARY KEY (id);


--
-- Name: people people_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.people
    ADD CONSTRAINT people_pkey PRIMARY KEY (person_id);


--
-- Name: portal_notes portal_notes_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.portal_notes
    ADD CONSTRAINT portal_notes_pkey PRIMARY KEY (id);


--
-- Name: portal_poll_questions portal_poll_questions_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.portal_poll_questions
    ADD CONSTRAINT portal_poll_questions_pkey PRIMARY KEY (id);


--
-- Name: portal_polls portal_polls_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.portal_polls
    ADD CONSTRAINT portal_polls_pkey PRIMARY KEY (id);


--
-- Name: profile_exceptions profile_exceptions_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.profile_exceptions
    ADD CONSTRAINT profile_exceptions_pkey PRIMARY KEY (profile_id, modname);


--
-- Name: report_card_comment_categories report_card_comment_categories_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.report_card_comment_categories
    ADD CONSTRAINT report_card_comment_categories_pkey PRIMARY KEY (id);


--
-- Name: report_card_comment_code_scales report_card_comment_code_scales_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.report_card_comment_code_scales
    ADD CONSTRAINT report_card_comment_code_scales_pkey PRIMARY KEY (id);


--
-- Name: report_card_comment_codes report_card_comment_codes_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.report_card_comment_codes
    ADD CONSTRAINT report_card_comment_codes_pkey PRIMARY KEY (id);


--
-- Name: report_card_comments report_card_comments_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.report_card_comments
    ADD CONSTRAINT report_card_comments_pkey PRIMARY KEY (id);


--
-- Name: report_card_grade_scales report_card_grade_scales_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.report_card_grade_scales
    ADD CONSTRAINT report_card_grade_scales_pkey PRIMARY KEY (id);


--
-- Name: report_card_grades report_card_grades_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.report_card_grades
    ADD CONSTRAINT report_card_grades_pkey PRIMARY KEY (id);


--
-- Name: resources resources_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.resources
    ADD CONSTRAINT resources_pkey PRIMARY KEY (id);


--
-- Name: wx_rules_school rules_school_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wx_rules_school
    ADD CONSTRAINT rules_school_pkey PRIMARY KEY (id);


--
-- Name: schedule_requests schedule_requests_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.schedule_requests
    ADD CONSTRAINT schedule_requests_pkey PRIMARY KEY (request_id);


--
-- Name: school_fields school_fields_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.school_fields
    ADD CONSTRAINT school_fields_pkey PRIMARY KEY (id);


--
-- Name: school_gradelevels school_gradelevels_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.school_gradelevels
    ADD CONSTRAINT school_gradelevels_pkey PRIMARY KEY (id);


--
-- Name: school_marking_periods school_marking_periods_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.school_marking_periods
    ADD CONSTRAINT school_marking_periods_pkey PRIMARY KEY (marking_period_id);


--
-- Name: school_periods school_periods_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.school_periods
    ADD CONSTRAINT school_periods_pkey PRIMARY KEY (period_id);


--
-- Name: schools schools_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.schools
    ADD CONSTRAINT schools_pkey PRIMARY KEY (id, syear);


--
-- Name: staff_exceptions staff_exceptions_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.staff_exceptions
    ADD CONSTRAINT staff_exceptions_pkey PRIMARY KEY (user_id, modname);


--
-- Name: staff_field_categories staff_field_categories_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.staff_field_categories
    ADD CONSTRAINT staff_field_categories_pkey PRIMARY KEY (id);


--
-- Name: staff_fields staff_fields_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.staff_fields
    ADD CONSTRAINT staff_fields_pkey PRIMARY KEY (id);


--
-- Name: staff staff_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.staff
    ADD CONSTRAINT staff_pkey PRIMARY KEY (staff_id);


--
-- Name: student_assignments student_assignments_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.student_assignments
    ADD CONSTRAINT student_assignments_pkey PRIMARY KEY (assignment_id, student_id);


--
-- Name: student_enrollment_codes student_enrollment_codes_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.student_enrollment_codes
    ADD CONSTRAINT student_enrollment_codes_pkey PRIMARY KEY (id);


--
-- Name: student_enrollment_course_periods student_enrollment_course_periods_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.student_enrollment_course_periods
    ADD CONSTRAINT student_enrollment_course_periods_pkey PRIMARY KEY (id);


--
-- Name: student_enrollment student_enrollment_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.student_enrollment
    ADD CONSTRAINT student_enrollment_pkey PRIMARY KEY (id);


--
-- Name: student_field_categories student_field_categories_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.student_field_categories
    ADD CONSTRAINT student_field_categories_pkey PRIMARY KEY (id);


--
-- Name: student_medical_alerts student_medical_alerts_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.student_medical_alerts
    ADD CONSTRAINT student_medical_alerts_pkey PRIMARY KEY (id);


--
-- Name: student_medical student_medical_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.student_medical
    ADD CONSTRAINT student_medical_pkey PRIMARY KEY (id);


--
-- Name: student_medical_visits student_medical_visits_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.student_medical_visits
    ADD CONSTRAINT student_medical_visits_pkey PRIMARY KEY (id);


--
-- Name: student_mp_comments student_mp_comments_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.student_mp_comments
    ADD CONSTRAINT student_mp_comments_pkey PRIMARY KEY (student_id, syear, marking_period_id);


--
-- Name: student_mp_stats student_mp_stats_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.student_mp_stats
    ADD CONSTRAINT student_mp_stats_pkey PRIMARY KEY (student_id, marking_period_id);


--
-- Name: student_report_card_comments student_report_card_comments_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.student_report_card_comments
    ADD CONSTRAINT student_report_card_comments_pkey PRIMARY KEY (syear, student_id, course_period_id, marking_period_id, report_card_comment_id);


--
-- Name: student_report_card_grades student_report_card_grades_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.student_report_card_grades
    ADD CONSTRAINT student_report_card_grades_pkey PRIMARY KEY (id);


--
-- Name: students_join_address students_join_address_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.students_join_address
    ADD CONSTRAINT students_join_address_pkey PRIMARY KEY (id);


--
-- Name: students_join_people students_join_people_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.students_join_people
    ADD CONSTRAINT students_join_people_pkey PRIMARY KEY (id);


--
-- Name: students_join_users students_join_users_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.students_join_users
    ADD CONSTRAINT students_join_users_pkey PRIMARY KEY (student_id, staff_id);


--
-- Name: students students_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.students
    ADD CONSTRAINT students_pkey PRIMARY KEY (student_id);


--
-- Name: students students_username_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.students
    ADD CONSTRAINT students_username_key UNIQUE (username);


--
-- Name: templates templates_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.templates
    ADD CONSTRAINT templates_pkey PRIMARY KEY (modname, staff_id);


--
-- Name: wx_moyennes_finales_students unique_student_exam; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wx_moyennes_finales_students
    ADD CONSTRAINT unique_student_exam UNIQUE (student_enrollment_id, exam_type);


--
-- Name: user_profiles user_profiles_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_profiles
    ADD CONSTRAINT user_profiles_pkey PRIMARY KEY (id);


--
-- Name: wx_appreciations wx_appreciations_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wx_appreciations
    ADD CONSTRAINT wx_appreciations_pkey PRIMARY KEY (id);


--
-- Name: wx_config_publication_resultats wx_config_publication_resultats_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wx_config_publication_resultats
    ADD CONSTRAINT wx_config_publication_resultats_pkey PRIMARY KEY (id);


--
-- Name: wx_course_periods_gradelevels wx_course_periods_gradelevels_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wx_course_periods_gradelevels
    ADD CONSTRAINT wx_course_periods_gradelevels_pkey PRIMARY KEY (wx_course_periods_gradelevels_id);


--
-- Name: wx_course_periods_subjects_periods wx_course_periods_subjects_periods_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wx_course_periods_subjects_periods
    ADD CONSTRAINT wx_course_periods_subjects_periods_pkey PRIMARY KEY (wx_course_periods_subjects_periods_id);


--
-- Name: wx_course_periods_subjects wx_course_periods_subjects_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wx_course_periods_subjects
    ADD CONSTRAINT wx_course_periods_subjects_pkey PRIMARY KEY (wx_course_periods_subjects_id);


--
-- Name: wx_course_subjects_gradelevels wx_course_subjects_gradelevels_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wx_course_subjects_gradelevels
    ADD CONSTRAINT wx_course_subjects_gradelevels_pkey PRIMARY KEY (wx_course_subjects_gradelevels_id);


--
-- Name: wx_custom_configuration_school wx_custom_configuration_school_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wx_custom_configuration_school
    ADD CONSTRAINT wx_custom_configuration_school_pkey PRIMARY KEY (id_custom_configuration_school);


--
-- Name: wx_echelle_notation_appreciation wx_echelle_notation_appreciation_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wx_echelle_notation_appreciation
    ADD CONSTRAINT wx_echelle_notation_appreciation_pkey PRIMARY KEY (id);


--
-- Name: wx_families wx_families_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wx_families
    ADD CONSTRAINT wx_families_pkey PRIMARY KEY (id);


--
-- Name: wx_family_members wx_family_members_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wx_family_members
    ADD CONSTRAINT wx_family_members_pkey PRIMARY KEY (id);


--
-- Name: wx_family_members wx_family_members_student_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wx_family_members
    ADD CONSTRAINT wx_family_members_student_id_key UNIQUE (student_id);


--
-- Name: wx_gradel_period_evaluation wx_gradel_period_evaluation_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wx_gradel_period_evaluation
    ADD CONSTRAINT wx_gradel_period_evaluation_pkey PRIMARY KEY (id_gradel_period_evaluation);


--
-- Name: wx_moyennes_finales_students wx_moyennes_finales_students_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wx_moyennes_finales_students
    ADD CONSTRAINT wx_moyennes_finales_students_pkey PRIMARY KEY (id);


--
-- Name: wx_moyennes_validation_gradelevel wx_moyennes_validation_gradelevel_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wx_moyennes_validation_gradelevel
    ADD CONSTRAINT wx_moyennes_validation_gradelevel_pkey PRIMARY KEY (id);


--
-- Name: wx_notes_details wx_notes_details_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wx_notes_details
    ADD CONSTRAINT wx_notes_details_pkey PRIMARY KEY (id_notes_details);


--
-- Name: wx_notes_student_details wx_notes_student_details_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wx_notes_student_details
    ADD CONSTRAINT wx_notes_student_details_pkey PRIMARY KEY (id_notes_student_details);


--
-- Name: wx_reduction_eleve wx_reduction_eleve_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wx_reduction_eleve
    ADD CONSTRAINT wx_reduction_eleve_pkey PRIMARY KEY (id);


--
-- Name: wx_reduction_members wx_reduction_members_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wx_reduction_members
    ADD CONSTRAINT wx_reduction_members_pkey PRIMARY KEY (id);


--
-- Name: wx_reduction_members wx_reduction_members_student_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wx_reduction_members
    ADD CONSTRAINT wx_reduction_members_student_id_key UNIQUE (student_id);


--
-- Name: wx_teacher_attendance wx_teacher_attendance_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wx_teacher_attendance
    ADD CONSTRAINT wx_teacher_attendance_pkey PRIMARY KEY (id);


--
-- Name: wx_ues wx_ues_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wx_ues
    ADD CONSTRAINT wx_ues_pkey PRIMARY KEY (id);


--
-- Name: wx_ues_subjects wx_ues_subjects_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wx_ues_subjects
    ADD CONSTRAINT wx_ues_subjects_pkey PRIMARY KEY (id);


--
-- Name: accounting_payments_ind1; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX accounting_payments_ind1 ON public.accounting_payments USING btree (staff_id);


--
-- Name: accounting_payments_ind2; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX accounting_payments_ind2 ON public.accounting_payments USING btree (amount);


--
-- Name: address_3; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX address_3 ON public.address USING btree (zipcode);


--
-- Name: address_4; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX address_4 ON public.address USING btree (street);


--
-- Name: address_desc_ind2; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX address_desc_ind2 ON public.address_fields USING btree (type);


--
-- Name: address_fields_ind3; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX address_fields_ind3 ON public.address_fields USING btree (category_id);


--
-- Name: attendance_code_categories_ind2; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX attendance_code_categories_ind2 ON public.attendance_code_categories USING btree (syear, school_id);


--
-- Name: attendance_codes_ind2; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX attendance_codes_ind2 ON public.attendance_codes USING btree (syear, school_id);


--
-- Name: attendance_codes_ind3; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX attendance_codes_ind3 ON public.attendance_codes USING btree (short_name);


--
-- Name: attendance_period_ind1; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX attendance_period_ind1 ON public.attendance_period USING btree (student_id);


--
-- Name: attendance_period_ind2; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX attendance_period_ind2 ON public.attendance_period USING btree (period_id);


--
-- Name: attendance_period_ind4; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX attendance_period_ind4 ON public.attendance_period USING btree (school_date);


--
-- Name: attendance_period_ind5; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX attendance_period_ind5 ON public.attendance_period USING btree (attendance_code);


--
-- Name: billing_payments_ind1; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX billing_payments_ind1 ON public.billing_payments USING btree (student_id);


--
-- Name: billing_payments_ind2; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX billing_payments_ind2 ON public.billing_payments USING btree (amount);


--
-- Name: billing_payments_ind3; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX billing_payments_ind3 ON public.billing_payments USING btree (refunded_payment_id);


--
-- Name: course_periods_ind2; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX course_periods_ind2 ON public.course_periods USING btree (syear, school_id);


--
-- Name: course_subjects_ind1; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX course_subjects_ind1 ON public.course_subjects USING btree (syear, school_id);


--
-- Name: courses_ind1; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX courses_ind1 ON public.courses USING btree (syear, school_id);


--
-- Name: courses_ind2; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX courses_ind2 ON public.courses USING btree (subject_id);


--
-- Name: custom_desc_ind2; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX custom_desc_ind2 ON public.custom_fields USING btree (type);


--
-- Name: custom_fields_ind3; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX custom_fields_ind3 ON public.custom_fields USING btree (category_id);


--
-- Name: eligibility_activities_ind1; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX eligibility_activities_ind1 ON public.eligibility_activities USING btree (school_id, syear);


--
-- Name: eligibility_ind1; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX eligibility_ind1 ON public.eligibility USING btree (student_id, course_period_id, school_date);


--
-- Name: food_service_categories_title; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX food_service_categories_title ON public.food_service_categories USING btree (school_id, menu_id, title);


--
-- Name: food_service_items_short_name; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX food_service_items_short_name ON public.food_service_items USING btree (school_id, short_name);


--
-- Name: food_service_menus_title; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX food_service_menus_title ON public.food_service_menus USING btree (school_id, title);


--
-- Name: food_service_staff_transaction_items_ind1; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX food_service_staff_transaction_items_ind1 ON public.food_service_staff_transaction_items USING btree (transaction_id);


--
-- Name: food_service_transaction_items_ind1; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX food_service_transaction_items_ind1 ON public.food_service_transaction_items USING btree (transaction_id);


--
-- Name: gradebook_assignment_types_ind1; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX gradebook_assignment_types_ind1 ON public.gradebook_assignments USING btree (staff_id, course_id);


--
-- Name: gradebook_assignments_ind1; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX gradebook_assignments_ind1 ON public.gradebook_assignments USING btree (staff_id, marking_period_id);


--
-- Name: gradebook_assignments_ind3; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX gradebook_assignments_ind3 ON public.gradebook_assignments USING btree (assignment_type_id);


--
-- Name: gradebook_grades_ind1; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX gradebook_grades_ind1 ON public.gradebook_grades USING btree (assignment_id);


--
-- Name: history_marking_period_ind1; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX history_marking_period_ind1 ON public.history_marking_periods USING btree (school_id);


--
-- Name: history_marking_period_ind2; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX history_marking_period_ind2 ON public.history_marking_periods USING btree (syear);


--
-- Name: lunch_period_ind1; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX lunch_period_ind1 ON public.lunch_period USING btree (student_id);


--
-- Name: lunch_period_ind2; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX lunch_period_ind2 ON public.lunch_period USING btree (period_id);


--
-- Name: lunch_period_ind3; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX lunch_period_ind3 ON public.lunch_period USING btree (attendance_code);


--
-- Name: lunch_period_ind4; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX lunch_period_ind4 ON public.lunch_period USING btree (school_date);


--
-- Name: messages_ind; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX messages_ind ON public.messages USING btree (syear, school_id);


--
-- Name: messagexuser_ind; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX messagexuser_ind ON public.messagexuser USING btree (user_id, key, status);


--
-- Name: name; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX name ON public.students USING btree (last_name, first_name, middle_name);


--
-- Name: people_1; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX people_1 ON public.people USING btree (last_name, first_name);


--
-- Name: people_desc_ind2; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX people_desc_ind2 ON public.people_fields USING btree (type);


--
-- Name: people_fields_ind3; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX people_fields_ind3 ON public.people_fields USING btree (category_id);


--
-- Name: people_join_contacts_ind1; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX people_join_contacts_ind1 ON public.people_join_contacts USING btree (person_id);


--
-- Name: program_config_ind1; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX program_config_ind1 ON public.program_config USING btree (school_id, syear);


--
-- Name: program_user_config_ind1; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX program_user_config_ind1 ON public.program_user_config USING btree (user_id, program);


--
-- Name: relations_meets_2; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX relations_meets_2 ON public.students_join_people USING btree (address_id);


--
-- Name: report_card_comment_categories_ind1; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX report_card_comment_categories_ind1 ON public.report_card_comment_categories USING btree (syear, school_id);


--
-- Name: report_card_comment_codes_ind1; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX report_card_comment_codes_ind1 ON public.report_card_comment_codes USING btree (school_id);


--
-- Name: report_card_comments_ind1; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX report_card_comments_ind1 ON public.report_card_comments USING btree (syear, school_id);


--
-- Name: report_card_grades_ind1; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX report_card_grades_ind1 ON public.report_card_grades USING btree (syear, school_id);


--
-- Name: schedule_ind1; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX schedule_ind1 ON public.schedule USING btree (course_id);


--
-- Name: schedule_ind2; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX schedule_ind2 ON public.schedule USING btree (course_period_id);


--
-- Name: schedule_ind3; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX schedule_ind3 ON public.schedule USING btree (student_id, marking_period_id, start_date, end_date);


--
-- Name: schedule_ind4; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX schedule_ind4 ON public.schedule USING btree (syear, school_id);


--
-- Name: schedule_requests_ind1; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX schedule_requests_ind1 ON public.schedule_requests USING btree (student_id, course_id, syear);


--
-- Name: schedule_requests_ind2; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX schedule_requests_ind2 ON public.schedule_requests USING btree (syear, school_id);


--
-- Name: school_desc_ind2; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX school_desc_ind2 ON public.school_fields USING btree (type);


--
-- Name: school_gradelevels_ind1; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX school_gradelevels_ind1 ON public.school_gradelevels USING btree (school_id);


--
-- Name: school_marking_periods_ind1; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX school_marking_periods_ind1 ON public.school_marking_periods USING btree (parent_id);


--
-- Name: school_marking_periods_ind2; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX school_marking_periods_ind2 ON public.school_marking_periods USING btree (syear, school_id, start_date, end_date);


--
-- Name: school_periods_ind1; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX school_periods_ind1 ON public.school_periods USING btree (syear, school_id);


--
-- Name: schools_ind1; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX schools_ind1 ON public.schools USING btree (syear);


--
-- Name: staff_desc_ind2; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX staff_desc_ind2 ON public.staff_fields USING btree (type);


--
-- Name: staff_fields_ind3; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX staff_fields_ind3 ON public.staff_fields USING btree (category_id);


--
-- Name: staff_idx200000002; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX staff_idx200000002 ON public.staff USING btree (custom_200000002);


--
-- Name: staff_idx200000003; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX staff_idx200000003 ON public.staff USING btree (custom_200000003);


--
-- Name: staff_ind1; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX staff_ind1 ON public.staff USING btree (staff_id, syear);


--
-- Name: staff_ind2; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX staff_ind2 ON public.staff USING btree (last_name, first_name);


--
-- Name: staff_ind3; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX staff_ind3 ON public.staff USING btree (schools);


--
-- Name: staff_ind4; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX staff_ind4 ON public.staff USING btree (username, syear);


--
-- Name: stu_addr_meets_2; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX stu_addr_meets_2 ON public.students_join_address USING btree (address_id);


--
-- Name: student_eligibility_activities_ind1; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX student_eligibility_activities_ind1 ON public.student_eligibility_activities USING btree (student_id);


--
-- Name: student_enrollment_2; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX student_enrollment_2 ON public.student_enrollment USING btree (grade_id);


--
-- Name: student_enrollment_3; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX student_enrollment_3 ON public.student_enrollment USING btree (syear, student_id, school_id);


--
-- Name: student_enrollment_4; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX student_enrollment_4 ON public.student_enrollment USING btree (start_date, end_date);


--
-- Name: student_medical_alerts_ind1; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX student_medical_alerts_ind1 ON public.student_medical_alerts USING btree (student_id);


--
-- Name: student_medical_ind1; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX student_medical_ind1 ON public.student_medical USING btree (student_id);


--
-- Name: student_medical_visits_ind1; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX student_medical_visits_ind1 ON public.student_medical_visits USING btree (student_id);


--
-- Name: student_report_card_comments_ind1; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX student_report_card_comments_ind1 ON public.student_report_card_comments USING btree (syear, school_id);


--
-- Name: student_report_card_grades_ind2; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX student_report_card_grades_ind2 ON public.student_report_card_grades USING btree (student_id);


--
-- Name: student_report_card_grades_ind3; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX student_report_card_grades_ind3 ON public.student_report_card_grades USING btree (course_period_id);


--
-- Name: student_report_card_grades_ind4; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX student_report_card_grades_ind4 ON public.student_report_card_grades USING btree (marking_period_id);


--
-- Name: students_join_address_ind1; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX students_join_address_ind1 ON public.students_join_address USING btree (student_id);


--
-- Name: students_join_people_ind1; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX students_join_people_ind1 ON public.students_join_people USING btree (student_id);


--
-- Name: access_log set_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.access_log FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: accounting_categories set_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.accounting_categories FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: accounting_incomes set_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.accounting_incomes FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: accounting_payments set_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.accounting_payments FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: accounting_salaries set_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.accounting_salaries FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: address set_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.address FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: address_field_categories set_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.address_field_categories FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: address_fields set_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.address_fields FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: attendance_calendar set_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.attendance_calendar FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: attendance_calendars set_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.attendance_calendars FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: attendance_code_categories set_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.attendance_code_categories FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: attendance_codes set_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.attendance_codes FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: attendance_completed set_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.attendance_completed FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: attendance_day set_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.attendance_day FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: attendance_period set_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.attendance_period FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: billing_fees set_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.billing_fees FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: billing_payments set_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.billing_payments FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: calendar_events set_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.calendar_events FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: config set_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.config FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: course_period_school_periods set_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.course_period_school_periods FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: course_periods set_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.course_periods FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: course_subjects set_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.course_subjects FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: courses set_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.courses FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: custom_fields set_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.custom_fields FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: discipline_field_usage set_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.discipline_field_usage FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: discipline_fields set_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.discipline_fields FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: discipline_referrals set_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.discipline_referrals FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: eligibility set_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.eligibility FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: eligibility_activities set_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.eligibility_activities FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: eligibility_completed set_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.eligibility_completed FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: food_service_accounts set_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.food_service_accounts FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: food_service_categories set_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.food_service_categories FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: food_service_items set_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.food_service_items FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: food_service_menu_items set_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.food_service_menu_items FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: food_service_menus set_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.food_service_menus FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: food_service_staff_accounts set_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.food_service_staff_accounts FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: food_service_staff_transaction_items set_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.food_service_staff_transaction_items FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: food_service_staff_transactions set_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.food_service_staff_transactions FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: food_service_student_accounts set_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.food_service_student_accounts FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: food_service_transaction_items set_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.food_service_transaction_items FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: food_service_transactions set_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.food_service_transactions FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: gradebook_assignment_types set_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.gradebook_assignment_types FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: gradebook_assignments set_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.gradebook_assignments FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: gradebook_grades set_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.gradebook_grades FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: grades_completed set_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.grades_completed FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: history_marking_periods set_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.history_marking_periods FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: lunch_period set_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.lunch_period FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: moodlexrosario set_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.moodlexrosario FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: people set_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.people FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: people_field_categories set_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.people_field_categories FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: people_fields set_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.people_fields FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: people_join_contacts set_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.people_join_contacts FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: portal_notes set_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.portal_notes FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: portal_poll_questions set_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.portal_poll_questions FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: portal_polls set_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.portal_polls FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: profile_exceptions set_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.profile_exceptions FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: program_config set_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.program_config FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: program_user_config set_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.program_user_config FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: report_card_comment_categories set_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.report_card_comment_categories FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: report_card_comment_code_scales set_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.report_card_comment_code_scales FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: report_card_comment_codes set_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.report_card_comment_codes FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: report_card_comments set_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.report_card_comments FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: report_card_grade_scales set_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.report_card_grade_scales FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: report_card_grades set_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.report_card_grades FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: resources set_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.resources FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: schedule set_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.schedule FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: schedule_requests set_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.schedule_requests FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: school_fields set_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.school_fields FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: school_gradelevels set_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.school_gradelevels FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: school_marking_periods set_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.school_marking_periods FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: school_periods set_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.school_periods FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: schools set_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.schools FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: staff set_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.staff FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: staff_exceptions set_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.staff_exceptions FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: staff_field_categories set_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.staff_field_categories FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: staff_fields set_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.staff_fields FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: student_assignments set_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.student_assignments FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: student_eligibility_activities set_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.student_eligibility_activities FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: student_enrollment set_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.student_enrollment FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: student_enrollment_codes set_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.student_enrollment_codes FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: student_field_categories set_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.student_field_categories FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: student_medical set_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.student_medical FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: student_medical_alerts set_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.student_medical_alerts FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: student_medical_visits set_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.student_medical_visits FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: student_mp_comments set_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.student_mp_comments FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: student_mp_stats set_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.student_mp_stats FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: student_report_card_comments set_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.student_report_card_comments FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: student_report_card_grades set_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.student_report_card_grades FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: students set_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.students FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: students_join_address set_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.students_join_address FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: students_join_people set_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.students_join_people FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: students_join_users set_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.students_join_users FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: templates set_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.templates FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: user_profiles set_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.user_profiles FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: student_report_card_grades srcg_mp_stats_update; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER srcg_mp_stats_update AFTER INSERT OR DELETE OR UPDATE ON public.student_report_card_grades FOR EACH ROW EXECUTE FUNCTION public.t_update_mp_stats();


--
-- Name: accounting_incomes accounting_incomes_category_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.accounting_incomes
    ADD CONSTRAINT accounting_incomes_category_id_fkey FOREIGN KEY (category_id) REFERENCES public.accounting_categories(id);


--
-- Name: accounting_incomes accounting_incomes_school_id_syear_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.accounting_incomes
    ADD CONSTRAINT accounting_incomes_school_id_syear_fkey FOREIGN KEY (school_id, syear) REFERENCES public.schools(id, syear);


--
-- Name: accounting_payments accounting_payments_category_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.accounting_payments
    ADD CONSTRAINT accounting_payments_category_id_fkey FOREIGN KEY (category_id) REFERENCES public.accounting_categories(id);


--
-- Name: accounting_payments accounting_payments_school_id_syear_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.accounting_payments
    ADD CONSTRAINT accounting_payments_school_id_syear_fkey FOREIGN KEY (school_id, syear) REFERENCES public.schools(id, syear);


--
-- Name: accounting_payments accounting_payments_staff_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.accounting_payments
    ADD CONSTRAINT accounting_payments_staff_id_fkey FOREIGN KEY (staff_id) REFERENCES public.staff(staff_id);


--
-- Name: accounting_salaries accounting_salaries_school_id_syear_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.accounting_salaries
    ADD CONSTRAINT accounting_salaries_school_id_syear_fkey FOREIGN KEY (school_id, syear) REFERENCES public.schools(id, syear);


--
-- Name: accounting_salaries accounting_salaries_staff_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.accounting_salaries
    ADD CONSTRAINT accounting_salaries_staff_id_fkey FOREIGN KEY (staff_id) REFERENCES public.staff(staff_id);


--
-- Name: attendance_calendar attendance_calendar_school_id_syear_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.attendance_calendar
    ADD CONSTRAINT attendance_calendar_school_id_syear_fkey FOREIGN KEY (school_id, syear) REFERENCES public.schools(id, syear);


--
-- Name: attendance_calendars attendance_calendars_school_id_syear_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.attendance_calendars
    ADD CONSTRAINT attendance_calendars_school_id_syear_fkey FOREIGN KEY (school_id, syear) REFERENCES public.schools(id, syear);


--
-- Name: attendance_code_categories attendance_code_categories_school_id_syear_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.attendance_code_categories
    ADD CONSTRAINT attendance_code_categories_school_id_syear_fkey FOREIGN KEY (school_id, syear) REFERENCES public.schools(id, syear);


--
-- Name: attendance_codes attendance_codes_school_id_syear_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.attendance_codes
    ADD CONSTRAINT attendance_codes_school_id_syear_fkey FOREIGN KEY (school_id, syear) REFERENCES public.schools(id, syear);


--
-- Name: attendance_completed attendance_completed_staff_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.attendance_completed
    ADD CONSTRAINT attendance_completed_staff_id_fkey FOREIGN KEY (staff_id) REFERENCES public.staff(staff_id);


--
-- Name: attendance_day attendance_day_marking_period_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.attendance_day
    ADD CONSTRAINT attendance_day_marking_period_id_fkey FOREIGN KEY (marking_period_id) REFERENCES public.school_marking_periods(marking_period_id);


--
-- Name: attendance_day attendance_day_student_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.attendance_day
    ADD CONSTRAINT attendance_day_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.students(student_id);


--
-- Name: attendance_period attendance_period_course_period_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.attendance_period
    ADD CONSTRAINT attendance_period_course_period_id_fkey FOREIGN KEY (course_period_id) REFERENCES public.course_periods(course_period_id);


--
-- Name: attendance_period attendance_period_marking_period_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.attendance_period
    ADD CONSTRAINT attendance_period_marking_period_id_fkey FOREIGN KEY (marking_period_id) REFERENCES public.school_marking_periods(marking_period_id);


--
-- Name: attendance_period attendance_period_student_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.attendance_period
    ADD CONSTRAINT attendance_period_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.students(student_id);


--
-- Name: billing_fees billing_fees_school_id_syear_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.billing_fees
    ADD CONSTRAINT billing_fees_school_id_syear_fkey FOREIGN KEY (school_id, syear) REFERENCES public.schools(id, syear);


--
-- Name: billing_fees billing_fees_student_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.billing_fees
    ADD CONSTRAINT billing_fees_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.students(student_id);


--
-- Name: billing_payments billing_payments_school_id_syear_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.billing_payments
    ADD CONSTRAINT billing_payments_school_id_syear_fkey FOREIGN KEY (school_id, syear) REFERENCES public.schools(id, syear);


--
-- Name: billing_payments billing_payments_student_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.billing_payments
    ADD CONSTRAINT billing_payments_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.students(student_id);


--
-- Name: calendar_events calendar_events_school_id_syear_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.calendar_events
    ADD CONSTRAINT calendar_events_school_id_syear_fkey FOREIGN KEY (school_id, syear) REFERENCES public.schools(id, syear);


--
-- Name: course_period_school_periods course_period_school_periods_course_period_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.course_period_school_periods
    ADD CONSTRAINT course_period_school_periods_course_period_id_fkey FOREIGN KEY (course_period_id) REFERENCES public.course_periods(course_period_id);


--
-- Name: course_periods course_periods_course_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.course_periods
    ADD CONSTRAINT course_periods_course_id_fkey FOREIGN KEY (course_id) REFERENCES public.courses(course_id);


--
-- Name: course_periods course_periods_marking_period_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.course_periods
    ADD CONSTRAINT course_periods_marking_period_id_fkey FOREIGN KEY (marking_period_id) REFERENCES public.school_marking_periods(marking_period_id);


--
-- Name: course_periods course_periods_school_id_syear_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.course_periods
    ADD CONSTRAINT course_periods_school_id_syear_fkey FOREIGN KEY (school_id, syear) REFERENCES public.schools(id, syear);


--
-- Name: course_periods course_periods_secondary_teacher_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.course_periods
    ADD CONSTRAINT course_periods_secondary_teacher_id_fkey FOREIGN KEY (secondary_teacher_id) REFERENCES public.staff(staff_id);


--
-- Name: course_periods course_periods_teacher_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.course_periods
    ADD CONSTRAINT course_periods_teacher_id_fkey FOREIGN KEY (teacher_id) REFERENCES public.staff(staff_id) ON DELETE CASCADE;


--
-- Name: course_subjects course_subjects_school_id_syear_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.course_subjects
    ADD CONSTRAINT course_subjects_school_id_syear_fkey FOREIGN KEY (school_id, syear) REFERENCES public.schools(id, syear);


--
-- Name: courses courses_school_id_syear_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.courses
    ADD CONSTRAINT courses_school_id_syear_fkey FOREIGN KEY (school_id, syear) REFERENCES public.schools(id, syear);


--
-- Name: discipline_field_usage discipline_field_usage_school_id_syear_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.discipline_field_usage
    ADD CONSTRAINT discipline_field_usage_school_id_syear_fkey FOREIGN KEY (school_id, syear) REFERENCES public.schools(id, syear);


--
-- Name: discipline_referrals discipline_referrals_school_id_syear_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.discipline_referrals
    ADD CONSTRAINT discipline_referrals_school_id_syear_fkey FOREIGN KEY (school_id, syear) REFERENCES public.schools(id, syear);


--
-- Name: discipline_referrals discipline_referrals_staff_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.discipline_referrals
    ADD CONSTRAINT discipline_referrals_staff_id_fkey FOREIGN KEY (staff_id) REFERENCES public.staff(staff_id);


--
-- Name: discipline_referrals discipline_referrals_student_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.discipline_referrals
    ADD CONSTRAINT discipline_referrals_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.students(student_id);


--
-- Name: eligibility_activities eligibility_activities_school_id_syear_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.eligibility_activities
    ADD CONSTRAINT eligibility_activities_school_id_syear_fkey FOREIGN KEY (school_id, syear) REFERENCES public.schools(id, syear);


--
-- Name: eligibility_completed eligibility_completed_staff_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.eligibility_completed
    ADD CONSTRAINT eligibility_completed_staff_id_fkey FOREIGN KEY (staff_id) REFERENCES public.staff(staff_id);


--
-- Name: eligibility eligibility_course_period_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.eligibility
    ADD CONSTRAINT eligibility_course_period_id_fkey FOREIGN KEY (course_period_id) REFERENCES public.course_periods(course_period_id);


--
-- Name: eligibility eligibility_student_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.eligibility
    ADD CONSTRAINT eligibility_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.students(student_id);


--
-- Name: attendance_period fk_attendance_period_my_period; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.attendance_period
    ADD CONSTRAINT fk_attendance_period_my_period FOREIGN KEY (my_period_id) REFERENCES public.wx_course_periods_subjects_periods(wx_course_periods_subjects_periods_id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: wx_course_periods_subjects fk_course_periods; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wx_course_periods_subjects
    ADD CONSTRAINT fk_course_periods FOREIGN KEY (course_periods_id) REFERENCES public.course_periods(course_period_id) ON DELETE CASCADE;


--
-- Name: wx_course_periods_gradelevels fk_course_periods; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wx_course_periods_gradelevels
    ADD CONSTRAINT fk_course_periods FOREIGN KEY (course_periods_id) REFERENCES public.course_periods(course_period_id) ON DELETE CASCADE;


--
-- Name: student_enrollment_course_periods fk_course_periods; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.student_enrollment_course_periods
    ADD CONSTRAINT fk_course_periods FOREIGN KEY (course_period_id) REFERENCES public.course_periods(course_period_id) ON DELETE CASCADE;


--
-- Name: wx_course_periods_subjects fk_course_subjects; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wx_course_periods_subjects
    ADD CONSTRAINT fk_course_subjects FOREIGN KEY (course_subjects_id) REFERENCES public.course_subjects(subject_id) ON DELETE CASCADE;


--
-- Name: wx_course_subjects_gradelevels fk_course_subjects; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wx_course_subjects_gradelevels
    ADD CONSTRAINT fk_course_subjects FOREIGN KEY (course_subjects_id) REFERENCES public.course_subjects(subject_id) ON DELETE CASCADE;


--
-- Name: wx_course_periods_gradelevels fk_school_gradelevels; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wx_course_periods_gradelevels
    ADD CONSTRAINT fk_school_gradelevels FOREIGN KEY (school_gradelevels_id) REFERENCES public.school_gradelevels(id) ON DELETE CASCADE;


--
-- Name: wx_course_subjects_gradelevels fk_school_gradelevels; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wx_course_subjects_gradelevels
    ADD CONSTRAINT fk_school_gradelevels FOREIGN KEY (school_gradelevels_id) REFERENCES public.school_gradelevels(id) ON DELETE CASCADE;


--
-- Name: wx_moyennes_validation_gradelevel fk_school_gradelevels_id; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wx_moyennes_validation_gradelevel
    ADD CONSTRAINT fk_school_gradelevels_id FOREIGN KEY (school_gradelevels_id) REFERENCES public.school_gradelevels(id) ON DELETE CASCADE;


--
-- Name: wx_teacher_attendance fk_staff; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wx_teacher_attendance
    ADD CONSTRAINT fk_staff FOREIGN KEY (staff_id) REFERENCES public.staff(staff_id) ON DELETE CASCADE;


--
-- Name: wx_moyennes_finales_students fk_student_enrollment_id; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wx_moyennes_finales_students
    ADD CONSTRAINT fk_student_enrollment_id FOREIGN KEY (student_enrollment_id) REFERENCES public.student_enrollment(id) ON DELETE CASCADE;


--
-- Name: student_enrollment_course_periods fk_student_enrollment_id; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.student_enrollment_course_periods
    ADD CONSTRAINT fk_student_enrollment_id FOREIGN KEY (student_enrollment_id) REFERENCES public.student_enrollment(id) ON DELETE CASCADE;


--
-- Name: wx_course_periods_subjects_periods fk_wx_course_periods_subjects; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wx_course_periods_subjects_periods
    ADD CONSTRAINT fk_wx_course_periods_subjects FOREIGN KEY (wx_course_periods_subjects_id) REFERENCES public.wx_course_periods_subjects(wx_course_periods_subjects_id) ON DELETE CASCADE;


--
-- Name: food_service_staff_accounts food_service_staff_accounts_staff_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.food_service_staff_accounts
    ADD CONSTRAINT food_service_staff_accounts_staff_id_fkey FOREIGN KEY (staff_id) REFERENCES public.staff(staff_id);


--
-- Name: food_service_staff_transactions food_service_staff_transactions_school_id_syear_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.food_service_staff_transactions
    ADD CONSTRAINT food_service_staff_transactions_school_id_syear_fkey FOREIGN KEY (school_id, syear) REFERENCES public.schools(id, syear);


--
-- Name: food_service_staff_transactions food_service_staff_transactions_staff_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.food_service_staff_transactions
    ADD CONSTRAINT food_service_staff_transactions_staff_id_fkey FOREIGN KEY (staff_id) REFERENCES public.staff(staff_id);


--
-- Name: food_service_student_accounts food_service_student_accounts_student_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.food_service_student_accounts
    ADD CONSTRAINT food_service_student_accounts_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.students(student_id);


--
-- Name: food_service_transactions food_service_transactions_school_id_syear_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.food_service_transactions
    ADD CONSTRAINT food_service_transactions_school_id_syear_fkey FOREIGN KEY (school_id, syear) REFERENCES public.schools(id, syear);


--
-- Name: food_service_transactions food_service_transactions_student_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.food_service_transactions
    ADD CONSTRAINT food_service_transactions_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.students(student_id);


--
-- Name: gradebook_assignment_types gradebook_assignment_types_course_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.gradebook_assignment_types
    ADD CONSTRAINT gradebook_assignment_types_course_id_fkey FOREIGN KEY (course_id) REFERENCES public.courses(course_id);


--
-- Name: gradebook_assignment_types gradebook_assignment_types_staff_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.gradebook_assignment_types
    ADD CONSTRAINT gradebook_assignment_types_staff_id_fkey FOREIGN KEY (staff_id) REFERENCES public.staff(staff_id);


--
-- Name: gradebook_assignments gradebook_assignments_course_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.gradebook_assignments
    ADD CONSTRAINT gradebook_assignments_course_id_fkey FOREIGN KEY (course_id) REFERENCES public.courses(course_id);


--
-- Name: gradebook_assignments gradebook_assignments_course_period_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.gradebook_assignments
    ADD CONSTRAINT gradebook_assignments_course_period_id_fkey FOREIGN KEY (course_period_id) REFERENCES public.course_periods(course_period_id);


--
-- Name: gradebook_assignments gradebook_assignments_marking_period_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.gradebook_assignments
    ADD CONSTRAINT gradebook_assignments_marking_period_id_fkey FOREIGN KEY (marking_period_id) REFERENCES public.school_marking_periods(marking_period_id);


--
-- Name: gradebook_assignments gradebook_assignments_staff_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.gradebook_assignments
    ADD CONSTRAINT gradebook_assignments_staff_id_fkey FOREIGN KEY (staff_id) REFERENCES public.staff(staff_id);


--
-- Name: gradebook_grades gradebook_grades_course_period_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.gradebook_grades
    ADD CONSTRAINT gradebook_grades_course_period_id_fkey FOREIGN KEY (course_period_id) REFERENCES public.course_periods(course_period_id);


--
-- Name: gradebook_grades gradebook_grades_student_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.gradebook_grades
    ADD CONSTRAINT gradebook_grades_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.students(student_id);


--
-- Name: grades_completed grades_completed_course_period_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.grades_completed
    ADD CONSTRAINT grades_completed_course_period_id_fkey FOREIGN KEY (course_period_id) REFERENCES public.course_periods(course_period_id);


--
-- Name: grades_completed grades_completed_marking_period_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.grades_completed
    ADD CONSTRAINT grades_completed_marking_period_id_fkey FOREIGN KEY (marking_period_id) REFERENCES public.school_marking_periods(marking_period_id);


--
-- Name: grades_completed grades_completed_staff_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.grades_completed
    ADD CONSTRAINT grades_completed_staff_id_fkey FOREIGN KEY (staff_id) REFERENCES public.staff(staff_id);


--
-- Name: lunch_period lunch_period_course_period_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.lunch_period
    ADD CONSTRAINT lunch_period_course_period_id_fkey FOREIGN KEY (course_period_id) REFERENCES public.course_periods(course_period_id);


--
-- Name: lunch_period lunch_period_marking_period_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.lunch_period
    ADD CONSTRAINT lunch_period_marking_period_id_fkey FOREIGN KEY (marking_period_id) REFERENCES public.school_marking_periods(marking_period_id);


--
-- Name: lunch_period lunch_period_student_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.lunch_period
    ADD CONSTRAINT lunch_period_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.students(student_id);


--
-- Name: messages messages_school_id_syear_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.messages
    ADD CONSTRAINT messages_school_id_syear_fkey FOREIGN KEY (school_id, syear) REFERENCES public.schools(id, syear);


--
-- Name: portal_notes portal_notes_school_id_syear_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.portal_notes
    ADD CONSTRAINT portal_notes_school_id_syear_fkey FOREIGN KEY (school_id, syear) REFERENCES public.schools(id, syear);


--
-- Name: portal_polls portal_polls_school_id_syear_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.portal_polls
    ADD CONSTRAINT portal_polls_school_id_syear_fkey FOREIGN KEY (school_id, syear) REFERENCES public.schools(id, syear);


--
-- Name: program_config program_config_school_id_syear_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.program_config
    ADD CONSTRAINT program_config_school_id_syear_fkey FOREIGN KEY (school_id, syear) REFERENCES public.schools(id, syear);


--
-- Name: report_card_comment_categories report_card_comment_categories_course_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.report_card_comment_categories
    ADD CONSTRAINT report_card_comment_categories_course_id_fkey FOREIGN KEY (course_id) REFERENCES public.courses(course_id);


--
-- Name: report_card_comment_categories report_card_comment_categories_school_id_syear_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.report_card_comment_categories
    ADD CONSTRAINT report_card_comment_categories_school_id_syear_fkey FOREIGN KEY (school_id, syear) REFERENCES public.schools(id, syear);


--
-- Name: report_card_comments report_card_comments_school_id_syear_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.report_card_comments
    ADD CONSTRAINT report_card_comments_school_id_syear_fkey FOREIGN KEY (school_id, syear) REFERENCES public.schools(id, syear);


--
-- Name: report_card_grade_scales report_card_grade_scales_school_id_syear_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.report_card_grade_scales
    ADD CONSTRAINT report_card_grade_scales_school_id_syear_fkey FOREIGN KEY (school_id, syear) REFERENCES public.schools(id, syear);


--
-- Name: report_card_grades report_card_grades_school_id_syear_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.report_card_grades
    ADD CONSTRAINT report_card_grades_school_id_syear_fkey FOREIGN KEY (school_id, syear) REFERENCES public.schools(id, syear);


--
-- Name: schedule schedule_course_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.schedule
    ADD CONSTRAINT schedule_course_id_fkey FOREIGN KEY (course_id) REFERENCES public.courses(course_id);


--
-- Name: schedule schedule_course_period_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.schedule
    ADD CONSTRAINT schedule_course_period_id_fkey FOREIGN KEY (course_period_id) REFERENCES public.course_periods(course_period_id);


--
-- Name: schedule schedule_marking_period_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.schedule
    ADD CONSTRAINT schedule_marking_period_id_fkey FOREIGN KEY (marking_period_id) REFERENCES public.school_marking_periods(marking_period_id);


--
-- Name: schedule_requests schedule_requests_course_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.schedule_requests
    ADD CONSTRAINT schedule_requests_course_id_fkey FOREIGN KEY (course_id) REFERENCES public.courses(course_id);


--
-- Name: schedule_requests schedule_requests_marking_period_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.schedule_requests
    ADD CONSTRAINT schedule_requests_marking_period_id_fkey FOREIGN KEY (marking_period_id) REFERENCES public.school_marking_periods(marking_period_id);


--
-- Name: schedule_requests schedule_requests_school_id_syear_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.schedule_requests
    ADD CONSTRAINT schedule_requests_school_id_syear_fkey FOREIGN KEY (school_id, syear) REFERENCES public.schools(id, syear);


--
-- Name: schedule_requests schedule_requests_student_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.schedule_requests
    ADD CONSTRAINT schedule_requests_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.students(student_id);


--
-- Name: schedule schedule_school_id_syear_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.schedule
    ADD CONSTRAINT schedule_school_id_syear_fkey FOREIGN KEY (school_id, syear) REFERENCES public.schools(id, syear);


--
-- Name: schedule schedule_student_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.schedule
    ADD CONSTRAINT schedule_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.students(student_id);


--
-- Name: school_marking_periods school_marking_periods_school_id_syear_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.school_marking_periods
    ADD CONSTRAINT school_marking_periods_school_id_syear_fkey FOREIGN KEY (school_id, syear) REFERENCES public.schools(id, syear);


--
-- Name: school_periods school_periods_school_id_syear_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.school_periods
    ADD CONSTRAINT school_periods_school_id_syear_fkey FOREIGN KEY (school_id, syear) REFERENCES public.schools(id, syear);


--
-- Name: staff_exceptions staff_exceptions_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.staff_exceptions
    ADD CONSTRAINT staff_exceptions_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.staff(staff_id);


--
-- Name: student_assignments student_assignments_student_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.student_assignments
    ADD CONSTRAINT student_assignments_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.students(student_id);


--
-- Name: student_eligibility_activities student_eligibility_activities_student_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.student_eligibility_activities
    ADD CONSTRAINT student_eligibility_activities_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.students(student_id);


--
-- Name: student_enrollment student_enrollment_school_id_syear_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.student_enrollment
    ADD CONSTRAINT student_enrollment_school_id_syear_fkey FOREIGN KEY (school_id, syear) REFERENCES public.schools(id, syear);


--
-- Name: student_enrollment student_enrollment_student_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.student_enrollment
    ADD CONSTRAINT student_enrollment_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.students(student_id);


--
-- Name: student_medical_alerts student_medical_alerts_student_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.student_medical_alerts
    ADD CONSTRAINT student_medical_alerts_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.students(student_id);


--
-- Name: student_medical student_medical_student_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.student_medical
    ADD CONSTRAINT student_medical_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.students(student_id);


--
-- Name: student_medical_visits student_medical_visits_student_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.student_medical_visits
    ADD CONSTRAINT student_medical_visits_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.students(student_id);


--
-- Name: student_mp_comments student_mp_comments_marking_period_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.student_mp_comments
    ADD CONSTRAINT student_mp_comments_marking_period_id_fkey FOREIGN KEY (marking_period_id) REFERENCES public.school_marking_periods(marking_period_id);


--
-- Name: student_mp_comments student_mp_comments_student_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.student_mp_comments
    ADD CONSTRAINT student_mp_comments_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.students(student_id);


--
-- Name: student_mp_stats student_mp_stats_student_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.student_mp_stats
    ADD CONSTRAINT student_mp_stats_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.students(student_id);


--
-- Name: student_report_card_comments student_report_card_comments_course_period_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.student_report_card_comments
    ADD CONSTRAINT student_report_card_comments_course_period_id_fkey FOREIGN KEY (course_period_id) REFERENCES public.course_periods(course_period_id);


--
-- Name: student_report_card_comments student_report_card_comments_marking_period_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.student_report_card_comments
    ADD CONSTRAINT student_report_card_comments_marking_period_id_fkey FOREIGN KEY (marking_period_id) REFERENCES public.school_marking_periods(marking_period_id);


--
-- Name: student_report_card_comments student_report_card_comments_school_id_syear_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.student_report_card_comments
    ADD CONSTRAINT student_report_card_comments_school_id_syear_fkey FOREIGN KEY (school_id, syear) REFERENCES public.schools(id, syear);


--
-- Name: student_report_card_comments student_report_card_comments_student_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.student_report_card_comments
    ADD CONSTRAINT student_report_card_comments_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.students(student_id);


--
-- Name: student_report_card_grades student_report_card_grades_course_period_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.student_report_card_grades
    ADD CONSTRAINT student_report_card_grades_course_period_id_fkey FOREIGN KEY (course_period_id) REFERENCES public.course_periods(course_period_id);


--
-- Name: student_report_card_grades student_report_card_grades_student_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.student_report_card_grades
    ADD CONSTRAINT student_report_card_grades_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.students(student_id);


--
-- Name: students_join_address students_join_address_student_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.students_join_address
    ADD CONSTRAINT students_join_address_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.students(student_id);


--
-- Name: students_join_people students_join_people_student_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.students_join_people
    ADD CONSTRAINT students_join_people_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.students(student_id);


--
-- Name: students_join_users students_join_users_staff_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.students_join_users
    ADD CONSTRAINT students_join_users_staff_id_fkey FOREIGN KEY (staff_id) REFERENCES public.staff(staff_id);


--
-- Name: students_join_users students_join_users_student_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.students_join_users
    ADD CONSTRAINT students_join_users_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.students(student_id);


--
-- Name: wx_family_members wx_family_members_family_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wx_family_members
    ADD CONSTRAINT wx_family_members_family_id_fkey FOREIGN KEY (family_id) REFERENCES public.wx_families(id) ON DELETE CASCADE;


--
-- Name: wx_family_members wx_family_members_student_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wx_family_members
    ADD CONSTRAINT wx_family_members_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.students(student_id) ON DELETE CASCADE;


--
-- Name: wx_notes_student_details wx_notes_student_details_student_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wx_notes_student_details
    ADD CONSTRAINT wx_notes_student_details_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.students(student_id);


--
-- Name: wx_notes_student_details wx_notes_student_details_wx_course_periods_subjects_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wx_notes_student_details
    ADD CONSTRAINT wx_notes_student_details_wx_course_periods_subjects_id_fkey FOREIGN KEY (wx_course_periods_subjects_id) REFERENCES public.wx_course_periods_subjects(wx_course_periods_subjects_id) ON DELETE CASCADE;


--
-- Name: wx_reduction_members wx_reduction_members_reduction_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wx_reduction_members
    ADD CONSTRAINT wx_reduction_members_reduction_id_fkey FOREIGN KEY (reduction_id) REFERENCES public.wx_reduction_eleve(id) ON DELETE CASCADE;


--
-- Name: wx_reduction_members wx_reduction_members_student_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wx_reduction_members
    ADD CONSTRAINT wx_reduction_members_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.students(student_id) ON DELETE CASCADE;


--
-- Name: wx_ues_subjects wx_ues_subjects_subject_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wx_ues_subjects
    ADD CONSTRAINT wx_ues_subjects_subject_id_fkey FOREIGN KEY (subject_id) REFERENCES public.course_subjects(subject_id);


--
-- Name: wx_ues_subjects wx_ues_subjects_ue_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wx_ues_subjects
    ADD CONSTRAINT wx_ues_subjects_ue_id_fkey FOREIGN KEY (ue_id) REFERENCES public.wx_ues(id) ON DELETE CASCADE;


--
-- PostgreSQL database dump complete
--

\unrestrict 0G8XNJt8yFCev1APVXTZ2BZ11jTqNtoVOkXTbZSRKB83Aqpw57JRhk2gyaT6HcF

