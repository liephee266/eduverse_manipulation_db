--
-- PostgreSQL database dump
--

-- Dumped from database version 16.10 (Ubuntu 16.10-0ubuntu0.24.04.1)
-- Dumped by pg_dump version 17.5 (Ubuntu 17.5-1.pgdg24.04+1)

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
    total_mentant integer
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
    custom_200000005 date
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
    updated_at timestamp without time zone
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
-- Data for Name: access_log; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.access_log (syear, username, profile, login_time, ip_address, user_agent, status, created_at, updated_at) FROM stdin;
2024	admin	admin	\N	127.0.0.1	Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:132.0) Gecko/20100101 Firefox/132.0	Y	2024-11-07 17:05:22.656885	\N
2024	admin	\N	\N	2c0f:ef58:162b:8b00:c17a:dc85:865d:948b	Mozilla/5.0 (Linux; Android 13; 220333QAG Build/TKQ1.221114.001; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/130.0.6723.107 Mobile Safari/537.36	\N	2024-11-14 09:50:41.899123	\N
2024	huvmyo	\N	\N	70.32.128.243	Mozilla/5.0 (Linux; Android 11; moto g(20) Build/RTAS31.68-66-3; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/90.0.4430.210 Mobile Safari/537.36	\N	2024-11-14 10:14:26.215006	\N
2024	pquvwt	\N	\N	70.32.128.253	Mozilla/5.0 (Linux; Android 13; Redfin 64-bit only Build/TP1A.220624.014; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/101.0.4951.74 Mobile Safari/537.36	\N	2024-11-14 10:14:53.29795	\N
2024	bvhnuj	\N	\N	70.32.128.243	Mozilla/5.0 (Linux; Android 11; moto g(20) Build/RTAS31.68-66-3; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/90.0.4430.210 Mobile Safari/537.36	\N	2024-11-14 10:14:55.508056	\N
2024	uvwtsf	\N	\N	2001:4860:101d:fe07:5b55:9a10:fb85:d851	Mozilla/5.0 (Linux; Android 13; Pixel 7 Build/TQ3A.230605.012; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/109.0.5414.123 Mobile Safari/537.36	\N	2024-11-14 10:15:04.843225	\N
2024	ttlhdg	\N	\N	70.32.128.243	Mozilla/5.0 (Linux; Android 11; moto g(20) Build/RTAS31.68-66-3; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/90.0.4430.210 Mobile Safari/537.36	\N	2024-11-14 10:15:13.626628	\N
2024	sfjjqs	\N	\N	70.32.128.253	Mozilla/5.0 (Linux; Android 13; Redfin 64-bit only Build/TP1A.220624.014; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/101.0.4951.74 Mobile Safari/537.36	\N	2024-11-14 10:15:36.156852	\N
2024	bvhnuj	\N	\N	70.32.128.254	Mozilla/5.0 (Linux; Android 12; Pixel 6 Build/SQ1D.220205.004; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/91.0.4472.114 Mobile Safari/537.36	\N	2024-11-14 10:15:46.317952	\N
2024	tmjlwj	\N	\N	70.32.128.253	Mozilla/5.0 (Linux; Android 13; Redfin 64-bit only Build/TP1A.220624.014; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/101.0.4951.74 Mobile Safari/537.36	\N	2024-11-14 10:16:29.396462	\N
2024	imbamg	\N	\N	70.32.128.243	Mozilla/5.0 (Linux; Android 11; moto g(20) Build/RTAS31.68-66-3; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/90.0.4430.210 Mobile Safari/537.36	\N	2024-11-14 10:16:42.630503	\N
2024	bonaov	\N	\N	70.32.128.249	Mozilla/5.0 (Linux; Android 12; Pixel 6 Build/SQ1D.220205.004; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/91.0.4472.114 Mobile Safari/537.36	\N	2024-11-14 10:17:37.787375	\N
2024	wfsdts	\N	\N	66.249.84.32	Mozilla/5.0 (Linux; Android 11; OnePlus8Pro Build/QKR1.191246.002; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/90.0.4430.210 Mobile Safari/537.36	\N	2024-11-14 10:19:51.484746	\N
2024	admin	\N	\N	2c0f:ef58:162b:8b00:28e9:83a1:19ec:df65	Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:132.0) Gecko/20100101 Firefox/132.0	\N	2024-11-14 11:21:28.170199	\N
2024	admin	\N	\N	2c0f:ef58:162b:8b00:28e9:83a1:19ec:df65	Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:132.0) Gecko/20100101 Firefox/132.0	\N	2024-11-14 11:21:39.225388	\N
2024	webtinix	\N	\N	2c0f:ef58:162b:8b00:28e9:83a1:19ec:df65	Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:132.0) Gecko/20100101 Firefox/132.0	\N	2024-11-14 11:21:48.438665	\N
2024	admin	admin	\N	2c0f:ef58:162b:8b00:28e9:83a1:19ec:df65	Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:132.0) Gecko/20100101 Firefox/132.0	Y	2024-11-14 11:21:54.371883	\N
2024	admin	admin	\N	2c0f:ef58:162b:8b00:28e9:83a1:19ec:df65	Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:132.0) Gecko/20100101 Firefox/132.0	Y	2024-11-14 11:35:33.957329	\N
2024	admin	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:132.0) Gecko/20100101 Firefox/132.0	Y	2024-11-14 11:36:11.124621	\N
2024	eomsdv	\N	\N	2001:4860:1022:fe03:35d9:c038:d536:967a	Mozilla/5.0 (Linux; Android 11; Pixel 5 Build/RQ3A.211001.001; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/83.0.4103.106 Mobile Safari/537.36	\N	2024-11-14 12:42:11.424696	\N
2024	rblwal	\N	\N	74.125.212.195	Mozilla/5.0 (Linux; Android 11; OnePlus8Pro Build/QKR1.191246.002; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/90.0.4430.210 Mobile Safari/537.36	\N	2024-11-15 12:15:26.70596	\N
2024	admin	\N	\N	2c0f:ef58:162b:8b00:e8fe:4b3a:4f2:cf90	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36	\N	2024-11-21 08:42:12.080765	\N
2024	admin	\N	\N	2c0f:ef58:162b:8b00:e8fe:4b3a:4f2:cf90	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36	\N	2024-11-21 08:42:45.394957	\N
2024	admin	\N	\N	2c0f:ef58:162b:8b00:e8fe:4b3a:4f2:cf90	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36	\N	2024-11-21 08:43:31.734249	\N
2024	admin	\N	\N	2c0f:ef58:162b:8b00:e8fe:4b3a:4f2:cf90	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36	\N	2024-11-21 08:43:52.172775	\N
2024	Admin	\N	\N	2c0f:ef58:162b:8b00:e8fe:4b3a:4f2:cf90	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36	\N	2024-11-21 08:44:01.799824	\N
2024	admin	\N	\N	2c0f:ef58:162b:8b00:e8fe:4b3a:4f2:cf90	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36	\N	2024-11-21 08:44:17.65097	\N
2024	admin	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:132.0) Gecko/20100101 Firefox/132.0	Y	2024-11-21 08:47:04.452012	\N
2024	admin	\N	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:132.0) Gecko/20100101 Firefox/132.0	\N	2024-11-21 08:47:25.094323	\N
2024	admin	admin	\N	2c0f:ef58:162b:8b00:e8fe:4b3a:4f2:cf90	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36	Y	2024-11-21 08:48:34.260527	\N
2024	admin	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:132.0) Gecko/20100101 Firefox/132.0	Y	2024-11-21 08:50:32.405047	\N
2024	admin	admin	\N	160.113.1.151	Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:133.0) Gecko/20100101 Firefox/133.0	Y	2024-12-14 18:40:30.203315	\N
2024	admin	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:133.0) Gecko/20100101 Firefox/133.0	Y	2024-12-16 13:39:17.518531	\N
2024	madzousancty	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:133.0) Gecko/20100101 Firefox/133.0	Y	2024-12-16 13:52:06.619209	\N
2024	admin	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:133.0) Gecko/20100101 Firefox/133.0	Y	2024-12-16 13:55:57.427738	\N
2024	admin	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:133.0) Gecko/20100101 Firefox/133.0	Y	2024-12-16 13:56:58.315781	\N
2024	madzousancty	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:133.0) Gecko/20100101 Firefox/133.0	Y	2024-12-16 17:02:34.680901	\N
2024	madzousancty	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:133.0) Gecko/20100101 Firefox/133.0	Y	2024-12-17 11:28:40.602955	\N
2024	madzousancty	\N	\N	2c0f:ef58:162b:8b00:a924:8cfe:ae13:a7aa	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36	\N	2024-12-17 13:10:48.972326	\N
2024	madzousancty	admin	\N	2c0f:ef58:162b:8b00:a924:8cfe:ae13:a7aa	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36	Y	2024-12-17 13:11:43.216721	\N
2024	madzousancty	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:133.0) Gecko/20100101 Firefox/133.0	Y	2024-12-18 13:36:46.733928	\N
2024	admin	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:133.0) Gecko/20100101 Firefox/133.0	Y	2024-12-18 14:08:57.380286	\N
2024	madzousancty	\N	\N	2c0f:ef58:162b:8b00:80f8:5b7e:1d47:d381	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36	\N	2024-12-19 09:38:39.223722	\N
2024	madzousancty	admin	\N	2c0f:ef58:162b:8b00:80f8:5b7e:1d47:d381	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36	Y	2024-12-19 09:39:25.488285	\N
2024	madzousancty	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:133.0) Gecko/20100101 Firefox/133.0	Y	2024-12-26 11:14:51.560309	\N
2024	madzousancty	\N	\N	2c0f:ef58:162b:8b00:f113:ad18:9355:f547	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36	\N	2024-12-26 12:08:48.264088	\N
2024	madzousancty	\N	\N	2c0f:ef58:162b:8b00:f113:ad18:9355:f547	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36	\N	2024-12-26 12:09:18.245907	\N
2024	madzousancty	\N	\N	2c0f:ef58:162b:8b00:f113:ad18:9355:f547	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36	\N	2024-12-26 12:10:06.746751	\N
2024	madzousancty	\N	\N	2c0f:ef58:162b:8b00:f113:ad18:9355:f547	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36	\N	2024-12-26 12:10:59.573481	\N
2024	madzousancty	admin	\N	2c0f:ef58:162b:8b00:f113:ad18:9355:f547	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36	Y	2024-12-26 12:12:59.704736	\N
2024	madzousancty	admin	\N	2c0f:ef58:162b:8b00:850c:b142:d1c2:92c0	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36	Y	2024-12-27 09:43:04.287938	\N
2024	madzousancty	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:133.0) Gecko/20100101 Firefox/133.0	Y	2024-12-27 13:15:34.846204	\N
2024	madzousancty	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:133.0) Gecko/20100101 Firefox/133.0	Y	2024-12-27 16:34:52.846654	\N
2024	madzousancty	admin	\N	2c0f:ef58:162b:8b00:e5c3:34b5:3f3:9279	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36	Y	2025-01-06 10:39:23.299615	\N
2024	madzousancty	admin	\N	2c0f:ef58:162b:8b00:442f:c34c:d8a1:b616	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36	Y	2025-01-07 08:56:56.920275	\N
2024	madzousancty	admin	\N	2c0f:ef58:162b:8b00:6407:aad7:3cbb:cf51	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36	Y	2025-01-08 10:48:51.877017	\N
2024	madzousancty	admin	\N	2c0f:ef58:162b:8b00:e1b1:9e71:ae79:7a34	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36	Y	2025-01-09 11:07:03.057205	\N
2024	madzousancty	admin	\N	2c0f:ef58:162b:8b00:705b:42a8:9fa5:1fec	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36	Y	2025-01-10 09:00:45.350767	\N
2024	admin	\N	\N	2c0f:ef58:162b:8b00:66:4cf3:ba0a:b2a1	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36	\N	2025-01-10 09:20:09.498588	\N
2024	madzousancty	admin	\N	2c0f:ef58:162b:8b00:66:4cf3:ba0a:b2a1	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36	Y	2025-01-10 09:20:54.114278	\N
2024	admin	\N	\N	2c0f:ef58:162b:8b00:d09b:e56e:4b8e:9b24	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36	\N	2025-01-10 10:09:13.784182	\N
2024	madzousancty	admin	\N	2c0f:ef58:162b:8b00:384e:4023:7cce:ef81	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36	Y	2025-01-10 11:13:49.11138	\N
2024	madzousancty	admin	\N	2c0f:ef58:162b:8b00:d09b:e56e:4b8e:9b24	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36	Y	2025-01-10 16:06:42.972628	\N
2024	madzousancty	admin	\N	2c0f:ef58:162b:8b00:d49a:2f5e:f29d:8db6	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36	Y	2025-01-13 09:19:47.907782	\N
2024	madzousancty	admin	\N	2c0f:ef58:162b:8b00:418d:9512:a53:4611	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/132.0.0.0 Safari/537.36	Y	2025-01-15 12:54:15.14477	\N
2024	madzousancty	admin	\N	2c0f:ef58:162b:8b00:8158:e89:bc5d:f870	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36	Y	2025-01-16 09:11:37.824853	\N
2024	madzousancty	admin	\N	2c0f:ef58:1687:d600:2db1:2841:b92c:8ce2	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/132.0.0.0 Safari/537.36	Y	2025-01-16 13:07:59.677337	\N
2024	 madzousancty	\N	\N	2c0f:ef58:1687:d600:f5ca:7bca:44e8:7a71	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36	\N	2025-01-16 14:28:39.911177	\N
2024	 madzousancty	\N	\N	2c0f:ef58:1687:d600:f5ca:7bca:44e8:7a71	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36	\N	2025-01-16 14:29:34.662567	\N
2024	madzousancty	admin	\N	2c0f:ef58:1687:d600:f5ca:7bca:44e8:7a71	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36	Y	2025-01-16 14:30:05.986691	\N
2024	madzousancty	admin	\N	2c0f:ef58:162b:8b00:a470:163e:7675:66ce	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36	Y	2025-01-17 01:37:19.118111	\N
2024	madzousancty	admin	\N	2c0f:ef58:162b:8b00:78ab:4854:c20c:ff14	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36	Y	2025-01-17 15:29:37.567255	\N
2024	madzousancty	admin	\N	2c0f:ef58:162b:8b00:e002:8e92:dee3:ea2e	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36	Y	2025-01-19 13:49:22.560012	\N
2024	madzousancty	admin	\N	2c0f:ef58:1687:d600:e111:d008:cf48:c48c	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/132.0.0.0 Safari/537.36	Y	2025-01-20 09:07:35.674248	\N
2024	madzousancty	admin	\N	2c0f:ef58:1687:d600:e111:d008:cf48:c48c	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/132.0.0.0 Safari/537.36	Y	2025-01-20 09:07:35.936518	\N
2024	madzousancty	admin	\N	2c0f:ef58:1687:d600:946f:4c7c:9b2f:dd74	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36	Y	2025-01-20 09:07:45.924855	\N
2024	madzousancty	admin	\N	2c0f:ef58:1687:d600:e111:d008:cf48:c48c	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/132.0.0.0 Safari/537.36	Y	2025-01-20 09:15:13.67334	\N
2024	madzousancty	admin	\N	2c0f:ef58:1687:d600:e111:d008:cf48:c48c	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/132.0.0.0 Safari/537.36	Y	2025-01-20 09:15:13.836002	\N
2024	madzousancty	admin	\N	2c0f:ef58:1687:d600:e111:d008:cf48:c48c	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/132.0.0.0 Safari/537.36	Y	2025-01-20 09:16:00.098688	\N
2024	madzousancty	admin	\N	2c0f:ef58:1687:d600:e111:d008:cf48:c48c	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/132.0.0.0 Safari/537.36	Y	2025-01-20 09:16:00.304862	\N
2024	madzousancty	admin	\N	2c0f:ef58:1687:d600:e111:d008:cf48:c48c	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/132.0.0.0 Safari/537.36	Y	2025-01-20 09:19:12.805976	\N
2024	madzousancty	admin	\N	2c0f:ef58:1687:d600:e111:d008:cf48:c48c	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/132.0.0.0 Safari/537.36	Y	2025-01-20 09:56:08.435681	\N
2024	madzousancty	admin	\N	2c0f:ef58:1687:d600:e111:d008:cf48:c48c	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/132.0.0.0 Safari/537.36	Y	2025-01-20 09:56:08.647672	\N
2024	madzousancty	admin	\N	2c0f:ef58:1687:d600:e111:d008:cf48:c48c	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/132.0.0.0 Safari/537.36	Y	2025-01-20 10:07:07.895786	\N
2024	madzousancty	admin	\N	2c0f:ef58:1687:d600:e933:22b1:642c:abb6	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/132.0.0.0 Safari/537.36	Y	2025-01-21 09:31:42.161895	\N
2024	madzousancty	admin	\N	2c0f:ef58:1687:d600:e933:22b1:642c:abb6	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/132.0.0.0 Safari/537.36	Y	2025-01-21 09:31:42.33487	\N
2024	madzousancty	admin	\N	2c0f:ef58:1687:d600:d45d:8d1a:cf5d:9f68	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36	Y	2025-01-21 09:31:48.355568	\N
2024	madzousancty	admin	\N	2c0f:ef58:1687:d600:e933:22b1:642c:abb6	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/132.0.0.0 Safari/537.36	Y	2025-01-21 10:13:33.18763	\N
2024	madzousancty	admin	\N	2c0f:ef58:1687:d600:e933:22b1:642c:abb6	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/132.0.0.0 Safari/537.36	Y	2025-01-21 10:14:46.496299	\N
2024	madzousancty	admin	\N	2c0f:ef58:162b:8b00:7d9d:7ed5:b04d:73d7	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36	Y	2025-01-21 16:35:51.999345	\N
2024	madzousancty	admin	\N	2c0f:ef58:162b:8b00:5c37:aeea:f5b:c37f	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36	Y	2025-01-23 12:43:08.523134	\N
2024	admin	admin	\N	2c0f:ef58:162b:8b00:2d02:7136:3fda:5881	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36	Y	2025-01-23 14:22:31.190074	\N
2024	Marynat	admin	\N	2c0f:ef58:162b:8b00:2d02:7136:3fda:5881	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36	Y	2025-01-23 14:29:17.167481	\N
2024	marynat	admin	\N	2c0f:ef58:162b:8b00:7910:96e0:d85:6f19	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36	Y	2025-01-23 14:39:43.160384	\N
2024	Marynat	admin	\N	2c0f:ef58:162b:8b00:2d02:7136:3fda:5881	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36	Y	2025-01-23 16:33:40.563419	\N
2024	admin	admin	\N	2c0f:ef58:162b:8b00:2d02:7136:3fda:5881	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36	Y	2025-01-23 16:46:24.919461	\N
2024	admin	\N	\N	2c0f:ef58:162b:8b00:2d02:7136:3fda:5881	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36	\N	2025-01-23 17:10:19.033232	\N
2024	admin	admin	\N	2c0f:ef58:162b:8b00:2d02:7136:3fda:5881	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36	Y	2025-01-23 17:10:27.117151	\N
2024	marynat	admin	\N	2c0f:ef58:162b:8b00:3988:8381:2d76:3d38	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36	Y	2025-01-24 09:41:24.307013	\N
2024	admin	admin	\N	2c0f:ef58:162b:8b00:d0f3:84ca:1145:6caf	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36	Y	2025-01-24 15:06:46.082407	\N
2024	ange	\N	\N	2c0f:ef58:162b:8b00:c5e0:f269:908e:d9d4	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36	\N	2025-01-24 17:31:35.146866	\N
2024	ange	parent	\N	2c0f:ef58:162b:8b00:c5e0:f269:908e:d9d4	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36	Y	2025-01-24 17:31:50.515182	\N
2024	admin	admin	\N	2c0f:ef58:162b:8b00:c5e0:f269:908e:d9d4	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36	Y	2025-01-24 17:38:54.62639	\N
2024	ange	parent	\N	2c0f:ef58:162b:8b00:c5e0:f269:908e:d9d4	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36	Y	2025-01-24 17:43:11.617334	\N
2024	admin	\N	\N	2c0f:ef58:162b:8b00:c5e0:f269:908e:d9d4	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36	\N	2025-01-24 17:44:40.512515	\N
2024	admin	admin	\N	2c0f:ef58:162b:8b00:c5e0:f269:908e:d9d4	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36	Y	2025-01-24 17:44:53.848573	\N
2024	ange	parent	\N	2c0f:ef58:162b:8b00:c5e0:f269:908e:d9d4	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36	Y	2025-01-24 17:46:27.663895	\N
2024	admin	admin	\N	2c0f:ef58:162b:8b00:c5e0:f269:908e:d9d4	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36	Y	2025-01-24 17:47:37.51081	\N
2024	ange	parent	\N	2c0f:ef58:162b:8b00:c5e0:f269:908e:d9d4	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36	Y	2025-01-24 18:31:59.9605	\N
2024	marynat	\N	\N	2c0f:ef58:162b:8b00:891e:24b9:fcd9:5a8b	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36	\N	2025-01-27 12:02:43.257193	\N
2024	marynat	\N	\N	2c0f:ef58:162b:8b00:891e:24b9:fcd9:5a8b	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36	\N	2025-01-27 12:03:02.680084	\N
2024	marynat	admin	\N	2c0f:ef58:162b:8b00:891e:24b9:fcd9:5a8b	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36	Y	2025-01-27 12:03:55.825915	\N
2024	admin	\N	\N	2c0f:ef58:162b:8b00:d433:d69a:830a:3e39	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36	\N	2025-01-27 12:45:55.265775	\N
2024	admin	admin	\N	2c0f:ef58:162b:8b00:d433:d69a:830a:3e39	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36	Y	2025-01-27 12:46:04.719138	\N
2024	admin	admin	\N	2c0f:ef58:162b:8b00:d433:d69a:830a:3e39	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36	Y	2025-01-27 12:50:32.299127	\N
2024	admin	admin	\N	2c0f:ef58:162b:8b00:d433:d69a:830a:3e39	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36	Y	2025-01-27 12:50:51.086027	\N
2024	admin	admin	\N	2c0f:ef58:162b:8b00:d433:d69a:830a:3e39	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36	Y	2025-01-27 14:12:11.650221	\N
2024	admin	\N	\N	2c0f:ef58:162b:8b00:8d08:9e5c:e1c9:70c3	Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:134.0) Gecko/20100101 Firefox/134.0	\N	2025-01-27 14:18:10.810918	\N
2024	admin	\N	\N	2c0f:ef58:162b:8b00:8d08:9e5c:e1c9:70c3	Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:134.0) Gecko/20100101 Firefox/134.0	\N	2025-01-27 14:19:20.124194	\N
2024	admin	\N	\N	2c0f:ef58:162b:8b00:8d08:9e5c:e1c9:70c3	Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:134.0) Gecko/20100101 Firefox/134.0	\N	2025-01-27 14:20:33.002614	\N
2024	admin	\N	\N	2c0f:ef58:162b:8b00:8d08:9e5c:e1c9:70c3	Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:134.0) Gecko/20100101 Firefox/134.0	\N	2025-01-27 14:20:46.543139	\N
2024	admin	\N	\N	2c0f:ef58:162b:8b00:d433:d69a:830a:3e39	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36	\N	2025-01-27 14:21:10.124182	\N
2024	admin	\N	\N	2c0f:ef58:162b:8b00:8d08:9e5c:e1c9:70c3	Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:134.0) Gecko/20100101 Firefox/134.0	\N	2025-01-27 14:21:15.874799	\N
2024	admin	admin	\N	2c0f:ef58:162b:8b00:d433:d69a:830a:3e39	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36	Y	2025-01-27 14:21:17.912164	\N
2024	admin	admin	\N	2c0f:ef58:162b:8b00:d433:d69a:830a:3e39	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36	Y	2025-01-27 14:23:18.296345	\N
2024	admin	admin	\N	2c0f:ef58:162b:8b00:d433:d69a:830a:3e39	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36	Y	2025-01-27 14:28:11.100197	\N
2024	admin	admin	\N	2c0f:ef58:162b:8b00:d433:d69a:830a:3e39	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36	Y	2025-01-27 14:28:56.255328	\N
2024	admin	admin	\N	2c0f:ef58:162b:8b00:8d08:9e5c:e1c9:70c3	Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:134.0) Gecko/20100101 Firefox/134.0	Y	2025-01-27 14:29:13.715372	\N
2024	admin	\N	\N	2c0f:ef58:162b:8b00:8d08:9e5c:e1c9:70c3	Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:134.0) Gecko/20100101 Firefox/134.0	\N	2025-01-27 14:29:40.945721	\N
2024	admin	admin	\N	2c0f:ef58:162b:8b00:8d08:9e5c:e1c9:70c3	Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:134.0) Gecko/20100101 Firefox/134.0	Y	2025-01-27 14:29:55.513418	\N
2024	admin	admin	\N	2c0f:ef58:162b:8b00:d433:d69a:830a:3e39	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36	Y	2025-01-27 15:49:24.098275	\N
2024	madzousancty	admin	\N	2c0f:ef58:1687:d600:e06a:629c:e68:612f	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/132.0.0.0 Safari/537.36	Y	2025-01-28 09:27:35.016898	\N
2024	madzousancty	admin	\N	2c0f:ef58:1687:d600:e06a:629c:e68:612f	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/132.0.0.0 Safari/537.36	Y	2025-01-28 09:27:59.887538	\N
2024	madzousancty	admin	\N	2c0f:ef58:1687:d600:e06a:629c:e68:612f	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/132.0.0.0 Safari/537.36	Y	2025-01-28 09:29:27.743122	\N
2024	ange	parent	\N	2c0f:ef58:1687:d600:e06a:629c:e68:612f	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/132.0.0.0 Safari/537.36	Y	2025-01-28 09:38:44.214163	\N
2024	madzousancty	admin	\N	2c0f:ef58:1687:d600:e06a:629c:e68:612f	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/132.0.0.0 Safari/537.36	Y	2025-01-28 09:42:42.19086	\N
2024	marynat	admin	\N	2c0f:ef58:162b:8b00:b8bc:7e6b:bdc:85f0	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/132.0.0.0 Safari/537.36	Y	2025-01-28 12:23:41.848111	\N
2024	admin	admin	\N	2c0f:ef58:162b:8b00:6572:5657:a7c1:8b53	Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:134.0) Gecko/20100101 Firefox/134.0	Y	2025-01-28 14:55:36.221353	\N
2024	madzousancty	admin	\N	2c0f:ef58:160d:5f00:dce4:d5b8:863c:9e68	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/132.0.0.0 Safari/537.36	Y	2025-01-28 20:01:07.901591	\N
2024	admin	admin	\N	2c0f:ef58:162b:8b00:64c2:9a76:839c:9402	Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:134.0) Gecko/20100101 Firefox/134.0	Y	2025-01-28 22:45:35.294776	\N
2024	admin	\N	\N	2c0f:ef58:162b:8b00:a149:d586:af1e:26fd	Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:134.0) Gecko/20100101 Firefox/134.0	\N	2025-01-28 22:47:23.909802	\N
2024	admin	admin	\N	2c0f:ef58:162b:8b00:64c2:9a76:839c:9402	Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:134.0) Gecko/20100101 Firefox/134.0	Y	2025-01-28 22:51:36.081812	\N
2024	admin	admin	\N	2c0f:ef58:162b:8b00:64c2:9a76:839c:9402	Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:134.0) Gecko/20100101 Firefox/134.0	Y	2025-01-28 23:00:53.811954	\N
2024	admin	admin	\N	2c0f:ef58:162b:8b00:64c2:9a76:839c:9402	Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:134.0) Gecko/20100101 Firefox/134.0	Y	2025-01-28 23:09:40.91795	\N
2024	admin	admin	\N	2c0f:ef58:162b:8b00:3850:5307:8849:c491	Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:134.0) Gecko/20100101 Firefox/134.0	Y	2025-01-28 23:16:21.071874	\N
2024	marynat	admin	\N	2c0f:ef58:162b:8b00:8897:4b33:ba84:936c	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/132.0.0.0 Safari/537.36	Y	2025-01-29 09:08:54.232713	\N
2024	marynat	admin	\N	2c0f:ef58:162b:8b00:c5fd:3812:b5:1531	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/132.0.0.0 Safari/537.36	Y	2025-01-29 11:28:43.774696	\N
2024	marynat	admin	\N	2c0f:ef58:162b:8b00:509:bc95:3ac8:4784	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/132.0.0.0 Safari/537.36	Y	2025-01-30 09:55:46.607872	\N
2024	admin	\N	\N	2c0f:ef58:162b:8b00:ccda:107:251f:e123	Mozilla/5.0 (iPhone; CPU iPhone OS 15_0 like Mac OS X) AppleWebKit/603.1.30 (KHTML, like Gecko) Version/17.5 Mobile/15A5370a Safari/602.1	\N	2025-01-30 11:54:16.194753	\N
2024	Marynat	admin	\N	2c0f:ef58:162b:8b00:ccda:107:251f:e123	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36	Y	2025-01-30 11:56:06.927468	\N
2024	marynat	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/132.0.0.0 Safari/537.36	Y	2025-01-30 12:29:53.994726	\N
2024	admin	admin	\N	102.141.42.184	Mozilla/5.0 (iPhone; CPU iPhone OS 17_5_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) CriOS/132.0.6834.100 Mobile/15E148 Safari/604.1	Y	2025-01-30 14:50:35.870385	\N
2024	Marynat	admin	\N	2c0f:ef58:162b:8b00:ccda:107:251f:e123	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36	Y	2025-01-30 14:52:53.99788	\N
2024	marynat	admin	\N	2c0f:ef58:162b:8b00:3119:2be:4029:b813	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/132.0.0.0 Safari/537.36	Y	2025-01-30 15:34:15.669361	\N
2024	marynat	admin	\N	2c0f:ef58:162b:8b00:16e:721b:2c28:c3ca	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/132.0.0.0 Safari/537.36	Y	2025-02-04 14:22:18.176494	\N
2024	marynat	admin	\N	2c0f:ef58:162b:8b00:1966:4e59:849c:ac66	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/132.0.0.0 Safari/537.36	Y	2025-02-06 09:08:55.151872	\N
2024	admin	\N	\N	2c0f:ef58:162b:8b00:31b2:a2d:3708:2635	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/132.0.0.0 Safari/537.36	\N	2025-02-10 23:17:00.69722	\N
2024	admin	\N	\N	2c0f:ef58:162b:8b00:7849:1753:906d:97cd	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/132.0.0.0 Safari/537.36	\N	2025-02-12 12:24:27.825113	\N
2024	marynat	admin	\N	2c0f:ef58:162b:8b00:7849:1753:906d:97cd	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/132.0.0.0 Safari/537.36	Y	2025-02-12 12:26:58.949657	\N
2024	madzousancty	admin	\N	2c0f:ef58:160d:5f00:1c2a:ad0f:4a70:a503	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/132.0.0.0 Safari/537.36	Y	2025-02-12 20:24:33.862174	\N
2024	madzousancty	admin	\N	2c0f:ef58:1687:d600:d425:bb0d:d98d:33f3	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/132.0.0.0 Safari/537.36	Y	2025-02-13 09:12:34.327695	\N
2024	madzousancty	admin	\N	2c0f:ef58:1687:d600:85eb:4b52:c893:bebd	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/132.0.0.0 Safari/537.36	Y	2025-02-14 09:01:02.182012	\N
2024	admin	\N	\N	2c0f:ef58:1201:ba00:fdf3:79b1:eb30:ecd0	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/132.0.0.0 Safari/537.36	\N	2025-02-17 09:09:14.648447	\N
2024	admin	\N	\N	2c0f:ef58:1201:ba00:fdf3:79b1:eb30:ecd0	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/132.0.0.0 Safari/537.36	\N	2025-02-17 09:09:44.522779	\N
2024	admin	\N	\N	2c0f:ef58:1201:ba00:fdf3:79b1:eb30:ecd0	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/132.0.0.0 Safari/537.36	\N	2025-02-17 09:10:09.531793	\N
2024	madzousancty	admin	\N	2c0f:ef58:162b:8b00:9d7b:e3ac:1f8:88ce	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/133.0.0.0 Safari/537.36	Y	2025-02-17 11:06:11.835439	\N
2024	marynat	admin	\N	2c0f:ef58:162b:8b00:87f:af06:1605:d3aa	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/133.0.0.0 Safari/537.36	Y	2025-02-17 13:09:15.344707	\N
2024	marynat	admin	\N	160.113.0.3	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/133.0.0.0 Safari/537.36	Y	2025-02-17 13:36:54.85979	\N
2024	admin	admin	\N	2c0f:ef58:652:e700:a444:8eb:51ec:2018	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/132.0.0.0 Safari/537.36	Y	2025-02-17 14:59:07.215815	\N
2024	admin	admin	\N	2c0f:ef58:652:e700:a444:8eb:51ec:2018	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/132.0.0.0 Safari/537.36	Y	2025-02-17 15:38:46.948114	\N
2024	admin	admin	\N	102.141.49.192	Mozilla/5.0 (iPhone; CPU iPhone OS 18_1_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) GSA/355.0.723646882 Mobile/15E148 Safari/604.1	Y	2025-02-17 15:40:19.308432	\N
2024	madzousancty	admin	\N	2c0f:ef58:1687:d600:acf5:3c8f:2e52:459a	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/132.0.0.0 Safari/537.36	Y	2025-02-18 08:18:10.955431	\N
2024	madzousancty	admin	\N	2c0f:ef58:1687:d600:e9ff:8207:6e66:fd1a	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/132.0.0.0 Safari/537.36	Y	2025-02-18 08:35:42.704196	\N
2024	madzousancty	admin	\N	2c0f:ef58:160d:5f00:31ac:2701:ecfb:6c0d	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/133.0.0.0 Safari/537.36	Y	2025-02-18 17:22:13.727761	\N
2024	madzousancty	admin	\N	2c0f:ef58:1687:d600:a4ef:5992:10a0:f984	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/132.0.0.0 Safari/537.36	Y	2025-02-19 08:54:38.482337	\N
2024	madzousancty	admin	\N	2c0f:ef58:1687:d600:51aa:844d:926c:b831	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/132.0.0.0 Safari/537.36	Y	2025-02-19 10:41:54.637005	\N
2024	madzousancty	admin	\N	2c0f:ef58:162b:8b00:7c85:b64c:9718:fe11	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/132.0.0.0 Safari/537.36	Y	2025-02-19 11:19:35.773299	\N
2024	madzousancty	admin	\N	2c0f:ef58:1687:d600:b5ea:7334:2c41:e609	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/132.0.0.0 Safari/537.36	Y	2025-02-20 06:52:46.559303	\N
2024	marynat	admin	\N	169.255.121.10	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/133.0.0.0 Safari/537.36	Y	2025-02-20 10:12:49.550778	\N
2024	madzousancty	admin	\N	2c0f:ef58:1687:d600:68e2:74f8:40dc:e059	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/133.0.0.0 Safari/537.36	Y	2025-02-21 06:45:24.481255	\N
2024	marynat	admin	\N	2c0f:ef58:162b:8b00:7173:4410:ebea:90f4	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/133.0.0.0 Safari/537.36	Y	2025-02-21 07:51:57.91122	\N
2024	Marynat	admin	\N	2c0f:ef58:162b:8b00:802e:eba7:3f0d:3389	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/133.0.0.0 Safari/537.36	Y	2025-02-21 09:40:13.53057	\N
2024	marynat	admin	\N	160.113.21.54	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/133.0.0.0 Safari/537.36	Y	2025-02-21 10:08:38.996349	\N
2024	Marynat	admin	\N	2c0f:ef58:162b:8b00:151a:c33e:f79d:d59b	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/133.0.0.0 Safari/537.36	Y	2025-02-21 16:13:54.972793	\N
2024	madzousancty	admin	\N	2c0f:ef58:162b:8b00:7dd1:7844:7686:da55	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/133.0.0.0 Safari/537.36	Y	2025-02-24 09:13:24.2937	\N
2024	marynat	admin	\N	2c0f:ef58:162b:8b00:70f3:7ca2:3996:b4ab	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/133.0.0.0 Safari/537.36	Y	2025-02-27 08:30:31.692921	\N
2024	admin	admin	\N	2c0f:ef58:162b:8b00:64a4:808c:59e7:93db	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/133.0.0.0 Safari/537.36	Y	2025-02-27 14:01:52.79557	\N
2024	gloire	admin	\N	2c0f:ef58:162b:8b00:64a4:808c:59e7:93db	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/133.0.0.0 Safari/537.36	Y	2025-02-27 14:08:59.860846	\N
2024	gloire	admin	\N	2c0f:ef58:631:a200:7c81:3f44:623f:e499	Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:135.0) Gecko/20100101 Firefox/135.0	Y	2025-02-27 14:22:43.449388	\N
2024	gloire	admin	\N	102.141.49.146	Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:135.0) Gecko/20100101 Firefox/135.0	Y	2025-03-03 08:06:58.810957	\N
2024	gloire	admin	\N	102.141.49.146	Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:135.0) Gecko/20100101 Firefox/135.0	Y	2025-03-03 08:10:43.402979	\N
2024	gloire	admin	\N	51.89.164.169	Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:136.0) Gecko/20100101 Firefox/136.0	Y	2025-03-06 09:30:44.980793	\N
2024	gloire	admin	\N	102.141.49.146	Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:136.0) Gecko/20100101 Firefox/136.0	Y	2025-03-09 16:07:04.24167	\N
2024	madzousancty	admin	\N	2c0f:ef58:1687:d600:6cec:a2e4:6c4b:e626	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/133.0.0.0 Safari/537.36	Y	2025-03-10 10:15:10.774059	\N
2024	madzousancty	admin	\N	2c0f:ef58:160d:5f00:d8e5:651:c29d:c0c2	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/133.0.0.0 Safari/537.36	Y	2025-03-10 19:45:17.563632	\N
2024	gloire	admin	\N	102.141.49.146	Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:136.0) Gecko/20100101 Firefox/136.0	Y	2025-03-19 08:02:49.583225	\N
2024	madzousancty	admin	\N	2c0f:ef58:1687:d600:7181:3590:1b6e:7dc8	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0.0.0 Safari/537.36 Edg/135.0.0.0	Y	2025-04-22 12:18:02.495469	\N
2024	madzousancty	admin	\N	2c0f:ef58:1687:d600:7181:3590:1b6e:7dc8	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0.0.0 Safari/537.36 Edg/135.0.0.0	Y	2025-04-22 12:23:05.379602	\N
2024	madzousancty	admin	\N	2c0f:ef58:1687:d600:7181:3590:1b6e:7dc8	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0.0.0 Safari/537.36 Edg/135.0.0.0	Y	2025-04-22 12:30:42.322117	\N
2024	madzousancty	admin	\N	2c0f:ef58:1687:d600:442f:1f73:12f3:406a	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0.0.0 Safari/537.36 Edg/135.0.0.0	Y	2025-04-23 07:13:19.271365	\N
2024	madzousancty	admin	\N	2c0f:ef58:1687:d600:442f:1f73:12f3:406a	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0.0.0 Safari/537.36 Edg/135.0.0.0	Y	2025-04-23 07:24:05.314689	\N
2024	madzousancty	admin	\N	2c0f:ef58:1687:d600:442f:1f73:12f3:406a	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0.0.0 Safari/537.36 Edg/135.0.0.0	Y	2025-04-23 07:25:18.625972	\N
2024	madzousancty	admin	\N	2c0f:ef58:1687:d600:b859:3e21:f6d7:dc7b	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0.0.0 Safari/537.36 Edg/135.0.0.0	Y	2025-04-23 08:53:56.421166	\N
2024	madzousancty	admin	\N	2c0f:ef58:160d:5f00:2879:7924:3618:90c6	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36	Y	2025-05-07 13:41:17.655194	\N
2024	madzousancty	admin	\N	2c0f:ef58:1687:d600:c1ad:f454:48bf:abea	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0.0.0 Safari/537.36 Edg/135.0.0.0	Y	2025-05-08 08:42:51.710322	\N
2024	madzousancty	admin	\N	2c0f:ef58:1687:d600:e12a:6e55:da6c:dbaf	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/136.0.0.0 Safari/537.36	Y	2025-05-08 10:00:09.554682	\N
2024	madzousancty	admin	\N	2c0f:ef58:1687:d600:34b5:b004:5e9b:c539	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/136.0.0.0 Safari/537.36 Edg/136.0.0.0	Y	2025-05-10 08:09:02.291372	\N
2024	madzousancty	admin	\N	2c0f:ef58:1687:d600:5881:6e83:7c5b:ef2	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/136.0.0.0 Safari/537.36 Edg/136.0.0.0	Y	2025-05-10 08:46:52.13504	\N
2024	marynat	admin	\N	2c0f:ef58:162b:8b00:7de8:3afe:ef09:c47c	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36	Y	2025-05-30 15:20:03.974334	\N
2024	marynat	admin	\N	2c0f:ef58:162b:8b00:4c1f:15c:6845:7137	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.6261.95 Safari/537.36	Y	2025-06-02 13:46:30.140118	\N
2024	2nhem5Hd7M54T6ZDKb	\N	\N	2c0f:ef58:162b:8b00:2018:a198:21ee:943e	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36 Edg/137.0.0.0	\N	2025-06-03 13:13:24.117842	\N
2024	marynat	admin	\N	2c0f:ef58:162b:8b00:2018:a198:21ee:943e	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36 Edg/137.0.0.0	Y	2025-06-03 13:13:51.320928	\N
2024	marynat	admin	\N	2c0f:ef58:162b:8b00:c97d:eafb:5539:be1a	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36 Edg/137.0.0.0	Y	2025-06-04 08:58:06.896333	\N
2024	marynat	admin	\N	2c0f:ef58:162b:8b00:dd3f:4e09:c4fd:edd5	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/136.0.0.0 Safari/537.36 Edg/136.0.0.0	Y	2025-06-04 09:07:20.107225	\N
2024	marynat	admin	\N	2c0f:ef58:162b:8b00:dce8:499b:ef41:16a2	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36	Y	2025-06-04 15:18:50.527743	\N
2024	admin	\N	\N	2c0f:ef58:162b:8b00:91d0:c7fa:592f:4a57	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36	\N	2025-06-05 08:18:13.256891	\N
2024	admin	admin	\N	2c0f:ef58:162b:8b00:91d0:c7fa:592f:4a57	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36	Y	2025-06-05 08:18:20.155857	\N
2024	Elion 	\N	\N	2c0f:ef58:162b:8b00:b0c2:3e3:f8a8:766d	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/136.0.0.0 Safari/537.36 Edg/136.0.0.0	\N	2025-06-05 08:33:26.38719	\N
2024	Elion	admin	\N	2c0f:ef58:162b:8b00:b0c2:3e3:f8a8:766d	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/136.0.0.0 Safari/537.36 Edg/136.0.0.0	Y	2025-06-05 08:34:05.397037	\N
2024	marynat	admin	\N	2c0f:ef58:162b:8b00:b0c2:3e3:f8a8:766d	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/136.0.0.0 Safari/537.36 Edg/136.0.0.0	Y	2025-06-05 08:35:06.216691	\N
2024	Elion	admin	\N	2c0f:ef58:162b:8b00:b0c2:3e3:f8a8:766d	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/136.0.0.0 Safari/537.36 Edg/136.0.0.0	Y	2025-06-05 08:36:28.761195	\N
2024	marynat	admin	\N	2c0f:ef58:162b:8b00:b0c2:3e3:f8a8:766d	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/136.0.0.0 Safari/537.36 Edg/136.0.0.0	Y	2025-06-05 08:37:41.898076	\N
2024	Fredy	parent	\N	2c0f:ef58:162b:8b00:9461:3720:bdda:ba63	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/136.0.0.0 Safari/537.36 Edg/136.0.0.0	Y	2025-06-05 09:14:16.019411	\N
2024	marynat	admin	\N	2c0f:ef58:162b:8b00:9461:3720:bdda:ba63	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/136.0.0.0 Safari/537.36 Edg/136.0.0.0	Y	2025-06-05 09:17:39.052275	\N
2024	marynat	\N	\N	::1	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36	\N	2025-06-24 12:24:59.207028	\N
2024	marynat	admin	\N	2c0f:ef58:162b:8b00:95aa:37dc:2ae:5fe8	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/136.0.0.0 Safari/537.36 Edg/136.0.0.0	Y	2025-06-05 11:53:05.46723	\N
2024	marynat	admin	\N	2c0f:ef58:162b:8b00:c03e:ce82:4a96:3782	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36 Edg/137.0.0.0	Y	2025-06-05 13:20:58.465761	\N
2024	marynat	admin	\N	2c0f:ef58:162b:8b00:c03e:ce82:4a96:3782	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36	Y	2025-06-05 13:59:03.326119	\N
2024	marynat	admin	\N	2c0f:ef58:162b:8b00:79fc:5f4b:d10b:727	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36 Edg/137.0.0.0	Y	2025-06-06 09:00:19.538849	\N
2024	marynat	admin	\N	2c0f:ef58:162b:8b00:79fc:5f4b:d10b:727	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36	Y	2025-06-06 09:04:01.570405	\N
2024	marynat	admin	\N	2c0f:ef58:162b:8b00:90b4:8c11:9cdb:e427	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/136.0.0.0 Safari/537.36 Edg/136.0.0.0	Y	2025-06-06 10:33:20.712875	\N
2024	admin	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36	Y	2025-06-07 23:28:11.130773	\N
2024	marynat	admin	\N	2c0f:ef58:162b:8b00:340c:49ff:7675:e3f	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36	Y	2025-06-11 08:21:29.11074	\N
2024	marynat	admin	\N	2c0f:ef58:162b:8b00:f85b:11ec:2dd0:8eb2	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36	Y	2025-06-12 08:11:29.141194	\N
2024	admin	\N	\N	::1	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36 Edg/137.0.0.0	\N	2025-06-13 14:33:19.620554	\N
2024	marynat	admin	\N	::1	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36 Edg/137.0.0.0	Y	2025-06-13 14:34:08.682026	\N
2024	marynat	admin	\N	::1	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36 Edg/137.0.0.0	Y	2025-06-16 09:25:08.148819	\N
2024	marynat	admin	\N	::1	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36 Edg/137.0.0.0	Y	2025-06-16 21:56:10.732202	\N
2024	marynat	admin	\N	::1	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36 Edg/137.0.0.0	Y	2025-06-17 09:11:13.586885	\N
2024	marynat	admin	\N	::1	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36 Edg/137.0.0.0	Y	2025-06-17 09:49:32.683623	\N
2024	marynat	admin	\N	::1	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36 Edg/137.0.0.0	Y	2025-06-18 09:23:11.737835	\N
2024	marynat	admin	\N	::1	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36 Edg/137.0.0.0	Y	2025-06-18 14:14:31.477271	\N
2024	marynat	admin	\N	::1	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36 Edg/137.0.0.0	Y	2025-06-20 09:11:33.237891	\N
2024	marynat	admin	\N	::1	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36	Y	2025-06-20 09:12:39.298754	\N
2024	marynat	admin	\N	::1	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36	Y	2025-06-20 16:21:52.643059	\N
2024	marynat	admin	\N	::1	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36 Edg/137.0.0.0	Y	2025-06-23 09:23:22.708039	\N
2024	marynat	admin	\N	::1	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36 Edg/137.0.0.0	Y	2025-06-24 08:59:40.794351	\N
2024	marynat	\N	\N	::1	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36	\N	2025-06-24 11:56:10.587091	\N
2024	marynat	\N	\N	::1	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36	\N	2025-06-24 11:56:15.535519	\N
2024	marynat	\N	\N	::1	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36	\N	2025-06-24 11:56:19.409669	\N
2024	marynat	\N	\N	::1	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36	\N	2025-06-24 11:56:24.307298	\N
2024	marynat	\N	\N	::1	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36	\N	2025-06-24 11:56:42.743293	\N
2024	marynat	\N	\N	::1	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36	\N	2025-06-24 12:06:24.591125	\N
2024	marynat	\N	\N	::1	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36	\N	2025-06-24 12:06:27.016483	\N
2024	marynat	\N	\N	::1	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36	\N	2025-06-24 12:06:30.783729	\N
2024	marynat	\N	\N	::1	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36	\N	2025-06-24 12:06:58.821066	\N
2024	marynat	\N	\N	::1	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36	\N	2025-06-24 12:07:38.949091	\N
2024	marynat	\N	\N	::1	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36	\N	2025-06-24 12:07:40.953844	\N
2024	marynat	\N	\N	::1	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36	\N	2025-06-24 12:08:08.941867	\N
2024	marynat	\N	\N	::1	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36	\N	2025-06-24 12:08:43.74166	\N
2024	marynat	\N	\N	::1	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36	\N	2025-06-24 12:08:45.393776	\N
2024	marynat	\N	\N	::1	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36	\N	2025-06-24 12:10:47.154861	\N
2024	marynat	\N	\N	::1	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36	\N	2025-06-24 12:10:53.668185	\N
2024	admin	\N	\N	::1	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36	\N	2025-06-24 12:11:01.768512	\N
2024	marynat	\N	\N	::1	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36	\N	2025-06-24 12:11:13.034147	\N
2024	marynat	\N	\N	::1	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36	\N	2025-06-24 12:11:21.443601	\N
2024	marynat	\N	\N	::1	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36	\N	2025-06-24 12:24:46.588284	\N
2024	marynat	\N	\N	::1	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36	\N	2025-06-24 12:25:17.942475	\N
2024	marynat	\N	\N	::1	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36	\N	2025-06-24 12:25:29.382972	\N
2024	marynat	\N	\N	::1	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36	\N	2025-06-24 12:25:59.410626	\N
2024	marynat	\N	\N	::1	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36	\N	2025-06-24 12:28:47.702626	\N
2024	marynat	\N	\N	::1	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36	\N	2025-06-24 12:28:49.3804	\N
2024	marynat	\N	\N	::1	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36	\N	2025-06-24 12:28:50.743065	\N
2024	marynat	\N	\N	::1	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36	\N	2025-06-24 12:28:52.07331	\N
2024	marynat	\N	\N	::1	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36	\N	2025-06-24 12:29:36.492188	\N
2024	marynat	\N	\N	::1	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36	\N	2025-06-24 12:29:47.599082	\N
2024	marynat	\N	\N	::1	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36	\N	2025-06-24 12:29:54.718568	\N
2024	marynat	\N	\N	::1	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36	\N	2025-06-24 12:29:56.502769	\N
2024	marynat	\N	\N	::1	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36	\N	2025-06-24 12:29:58.37975	\N
2024	marynat	\N	\N	::1	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36	\N	2025-06-24 12:30:00.365032	\N
2024	pablorocknes	\N	\N	::1	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36	\N	2025-06-24 12:32:13.100581	\N
2024	marynat	\N	\N	::1	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36	\N	2025-06-24 12:32:23.188424	\N
2024	pablorocknes	admin	\N	::1	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36	Y	2025-06-24 12:34:24.889301	\N
2024	pablorocknes	admin	\N	::1	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36 Edg/137.0.0.0	Y	2025-06-25 09:16:42.529365	\N
2024	marynat	\N	\N	::1	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36 Edg/137.0.0.0	\N	2025-06-26 09:57:26.828885	\N
2024	marynat	\N	\N	::1	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36 Edg/137.0.0.0	\N	2025-06-26 09:57:34.636036	\N
2024	pablorocknes	admin	\N	::1	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36 Edg/137.0.0.0	Y	2025-06-26 09:57:37.338629	\N
2024	marynat	\N	\N	::1	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36 Edg/137.0.0.0	\N	2025-06-26 10:08:03.519241	\N
2024	marynat	\N	\N	::1	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36 Edg/137.0.0.0	\N	2025-06-26 10:08:16.49245	\N
2024	pablorocknes	admin	\N	::1	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36 Edg/137.0.0.0	Y	2025-06-26 10:24:40.660768	\N
2024	pablorocknes	admin	\N	::1	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36 Edg/137.0.0.0	Y	2025-06-27 09:22:09.852178	\N
2024	pablorocknes	admin	\N	::1	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36 Edg/137.0.0.0	Y	2025-06-30 02:31:56.817935	\N
2024	pablorocknes	admin	\N	::1	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36 Edg/138.0.0.0	Y	2025-07-01 09:24:29.768206	\N
2024	pablorocknes	admin	\N	::1	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36 Edg/138.0.0.0	Y	2025-07-02 10:01:32.436081	\N
2024	pablorocknes	admin	\N	::1	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36 Edg/138.0.0.0	Y	2025-07-03 09:14:03.622157	\N
2024	pablorocknes	admin	\N	::1	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36 Edg/138.0.0.0	Y	2025-07-04 09:43:37.749102	\N
2024	pablorocknes	admin	\N	::1	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36 Edg/138.0.0.0	Y	2025-07-07 09:05:28.979778	\N
2024	pablorocknes	admin	\N	::1	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36	Y	2025-07-07 12:55:46.457407	\N
2024	pablorocknes	admin	\N	::1	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36 Edg/138.0.0.0	Y	2025-07-08 09:21:19.460973	\N
2024	pablorocknes	admin	\N	::1	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36 Edg/138.0.0.0	Y	2025-07-09 09:51:19.22609	\N
2024	Admin	admin	\N	::1	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36 Edg/138.0.0.0	Y	2025-07-09 09:53:16.492339	\N
2024	Admin	admin	\N	::1	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36 Edg/138.0.0.0	Y	2025-07-09 11:36:19.835487	\N
2024	Admin	admin	\N	::1	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36 Edg/138.0.0.0	Y	2025-07-10 09:39:27.938152	\N
2024	Admin	admin	\N	::1	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36 Edg/138.0.0.0	Y	2025-07-11 09:57:07.113038	\N
2024	Admin	admin	\N	::1	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36 Edg/138.0.0.0	Y	2025-07-11 13:48:40.579631	\N
2024	Admin	admin	\N	::1	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36 Edg/138.0.0.0	Y	2025-07-11 14:25:16.474324	\N
2024	Admin	admin	\N	::1	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36 Edg/138.0.0.0	Y	2025-07-11 20:20:11.413522	\N
2024	Admin	admin	\N	::1	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36 Edg/138.0.0.0	Y	2025-07-12 01:52:51.940377	\N
2024	Admin	admin	\N	::1	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36 Edg/138.0.0.0	Y	2025-07-12 12:14:09.905202	\N
2024	Admin	admin	\N	::1	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36 Edg/138.0.0.0	Y	2025-07-12 12:14:19.375606	\N
2024	Admin	admin	\N	::1	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36 Edg/138.0.0.0	Y	2025-07-12 12:24:31.765471	\N
2024	Admin	admin	\N	::1	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36 Edg/138.0.0.0	Y	2025-07-12 12:25:25.000768	\N
2024	Admin	admin	\N	::1	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36 Edg/138.0.0.0	Y	2025-07-12 12:25:41.862961	\N
2024	Admin	admin	\N	::1	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36 Edg/138.0.0.0	Y	2025-07-12 12:25:59.457308	\N
2024	admin	admin	\N	::1	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36	Y	2025-07-12 12:28:13.980163	\N
2024	pablorocknes	admin	\N	::1	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36	Y	2025-07-12 12:28:28.517004	\N
2024	Admin	admin	\N	::1	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36 Edg/138.0.0.0	Y	2025-07-12 12:28:56.651308	\N
2024	Admin	admin	\N	::1	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36 Edg/138.0.0.0	Y	2025-07-12 12:30:59.39467	\N
2024	Admin	admin	\N	::1	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36 Edg/138.0.0.0	Y	2025-07-12 12:31:12.89433	\N
2024	Admin	admin	\N	::1	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36 Edg/138.0.0.0	Y	2025-07-12 12:31:49.908749	\N
2024	Admin	admin	\N	::1	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36 Edg/138.0.0.0	Y	2025-07-12 12:41:22.808913	\N
2024	Admin	admin	\N	::1	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36 Edg/138.0.0.0	Y	2025-07-12 12:43:31.335865	\N
2024	Admin	admin	\N	::1	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36 Edg/138.0.0.0	Y	2025-07-12 12:49:13.570412	\N
2024	Admin	admin	\N	::1	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36 Edg/138.0.0.0	Y	2025-07-12 13:40:55.827335	\N
2024	Admin	admin	\N	::1	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36 Edg/138.0.0.0	Y	2025-07-13 07:09:44.540587	\N
2024	Admin	admin	\N	::1	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36 Edg/138.0.0.0	Y	2025-07-14 09:45:28.91958	\N
2024	Admin	admin	\N	::1	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36 Edg/138.0.0.0	Y	2025-07-14 14:15:14.95627	\N
2024	Admin	admin	\N	::1	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36 Edg/138.0.0.0	Y	2025-07-14 14:15:42.27961	\N
2024	Admin	admin	\N	::1	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36 Edg/138.0.0.0	Y	2025-07-14 14:27:11.154153	\N
2024	Admin	admin	\N	::1	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36 Edg/138.0.0.0	Y	2025-07-14 14:42:26.636724	\N
2024	LeTerrible	teacher	\N	::1	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36 Edg/138.0.0.0	Y	2025-07-14 15:48:08.082409	\N
2024	Admin	admin	\N	::1	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36 Edg/138.0.0.0	Y	2025-07-14 15:48:54.460518	\N
2024	LeTerrible	teacher	\N	::1	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36 Edg/138.0.0.0	Y	2025-07-14 15:49:37.302458	\N
2024	Admin	admin	\N	::1	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36 Edg/138.0.0.0	Y	2025-07-14 15:54:17.989568	\N
2024	Admin	admin	\N	::1	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36 Edg/138.0.0.0	Y	2025-07-15 09:56:28.737272	\N
2024	Admin	admin	\N	::1	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36 Edg/138.0.0.0	Y	2025-07-15 17:10:19.664115	\N
2024	Admin	admin	\N	::1	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36 Edg/138.0.0.0	Y	2025-07-16 06:21:17.770202	\N
2024	Admin	admin	\N	::1	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36 Edg/138.0.0.0	Y	2025-07-16 09:52:55.970478	\N
2024	Admin	admin	\N	::1	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36 Edg/138.0.0.0	Y	2025-07-16 10:25:49.98968	\N
2024	Admin	admin	\N	::1	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36 Edg/138.0.0.0	Y	2025-07-17 09:31:09.305841	\N
2024	Admin	admin	\N	::1	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36 Edg/138.0.0.0	Y	2025-07-18 09:52:48.029468	\N
2024	Admin	admin	\N	::1	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36 Edg/138.0.0.0	Y	2025-07-18 11:36:13.043322	\N
2024	Admin	admin	\N	::1	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36 Edg/138.0.0.0	Y	2025-07-18 14:35:19.122794	\N
2024	Admin	admin	\N	::1	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36 Edg/138.0.0.0	Y	2025-07-21 09:36:54.812172	\N
2024	Admin	admin	\N	::1	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36 Edg/138.0.0.0	Y	2025-07-21 10:54:33.379762	\N
2024	Admin	admin	\N	::1	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36 Edg/138.0.0.0	Y	2025-07-21 16:28:24.587766	\N
2024	Admin	admin	\N	::1	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36 Edg/138.0.0.0	Y	2025-07-22 09:52:28.336584	\N
2024	Admin	admin	\N	::1	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36 Edg/138.0.0.0	Y	2025-07-22 15:21:06.695622	\N
2024	Admin	admin	\N	::1	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36 Edg/138.0.0.0	Y	2025-07-22 17:03:53.0463	\N
2024	Admin	admin	\N	::1	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36 Edg/138.0.0.0	Y	2025-07-23 13:16:28.34755	\N
2024	Admin	admin	\N	::1	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36 Edg/138.0.0.0	Y	2025-07-23 13:21:15.704869	\N
2024	Admin	admin	\N	::1	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36 Edg/138.0.0.0	Y	2025-07-24 14:58:01.679051	\N
2024	Admin	admin	\N	::1	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36 Edg/138.0.0.0	Y	2025-07-25 09:43:53.590413	\N
2024	Admin	admin	\N	::1	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36 Edg/138.0.0.0	Y	2025-07-25 12:41:54.48637	\N
2024	Admin	admin	\N	::1	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36 Edg/138.0.0.0	Y	2025-07-25 13:05:40.267862	\N
2025	Admin	admin	\N	172.18.0.1	Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36	Y	2025-08-06 11:33:28.289309	\N
2025	Admin	admin	\N	172.18.0.1	Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36	Y	2025-08-07 14:16:21.567376	\N
2025	Admin	admin	\N	172.18.0.1	Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36	Y	2025-08-07 16:52:30.439206	\N
2025	Admin	admin	\N	172.18.0.1	Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36	Y	2025-08-08 09:05:13.514199	\N
2025	Admin	admin	\N	172.18.0.1	Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36	Y	2025-08-08 10:49:05.171865	\N
2025	lieloumloum@gmail.com	\N	\N	172.18.0.1	Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36	\N	2025-08-08 12:33:55.328751	\N
2025	Admin	admin	\N	172.18.0.1	Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36	Y	2025-08-08 12:34:11.846936	\N
2025	lieloumloum@gmail.com	student	\N	172.18.0.1	Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36	Y	2025-08-08 14:27:39.006261	\N
2025	Admin	admin	\N	172.18.0.1	Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36	Y	2025-08-08 14:28:26.867968	\N
2025	Admin	admin	\N	172.18.0.1	Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36	Y	2025-08-08 17:03:01.420117	\N
2025	Admin	admin	\N	172.18.0.1	Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36	Y	2025-08-08 17:17:34.927388	\N
2025	Admin	admin	\N	172.18.0.1	Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36	Y	2025-08-10 16:45:33.543811	\N
2025	Admin	admin	\N	172.18.0.1	Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36	Y	2025-08-10 18:29:05.243469	\N
2025	Admin	admin	\N	172.18.0.1	Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36	Y	2025-08-11 03:01:36.771529	\N
2025	Admin	admin	\N	172.18.0.1	Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36	Y	2025-08-11 19:44:25.639652	\N
2025	Admin	admin	\N	172.18.0.1	Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36	Y	2025-08-12 01:47:23.971416	\N
2025	Admin	admin	\N	172.18.0.1	Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36	Y	2025-08-12 05:50:27.95543	\N
2025	Admin	admin	\N	102.141.42.184	Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36	Y	2025-08-13 13:20:49.112713	\N
2025	Admin	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36	Y	2025-08-13 13:46:58.012153	\N
2025	Admin	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36	Y	2025-08-13 14:16:50.213096	\N
2025	Admin	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36	Y	2025-08-13 22:50:18.607377	\N
2025	Admin	admin	\N	102.141.42.184	Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36	Y	2025-08-14 08:03:15.909638	\N
2025	Admin	admin	\N	102.141.42.184	Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36	Y	2025-08-14 09:24:32.51769	\N
2025	Admin 	\N	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36 Edg/139.0.0.0	\N	2025-08-14 11:40:34.544402	\N
2025	Admin	admin	\N	102.141.42.184	Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36	Y	2025-08-14 11:40:56.202399	\N
2025	Admin 	\N	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36 Edg/139.0.0.0	\N	2025-08-14 11:41:02.621697	\N
2025	Admin	\N	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36 Edg/139.0.0.0	\N	2025-08-14 11:41:42.287017	\N
2025	Admin 	\N	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36 Edg/139.0.0.0	\N	2025-08-14 11:42:12.258416	\N
2025	Admin	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36 Edg/139.0.0.0	Y	2025-08-14 11:42:30.119627	\N
2025	Admin	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36	Y	2025-08-14 11:58:14.693934	\N
2025	Admin	admin	\N	102.141.42.184	Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36	Y	2025-08-14 14:38:15.51803	\N
2025	Admin	\N	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36	\N	2025-08-14 17:24:32.187333	\N
2025	Admin	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36	Y	2025-08-14 17:24:54.821381	\N
2025	Admin	admin	\N	102.141.42.184	Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36	Y	2025-08-18 09:55:44.489317	\N
2025	admin	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36	Y	2025-08-18 11:48:42.894934	\N
2025	Admin	admin	\N	102.141.42.184	Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36	Y	2025-08-18 12:01:21.850914	\N
2025	Admin	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36	Y	2025-08-18 12:35:53.414033	\N
2025	Admin	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36	Y	2025-08-18 14:11:31.10285	\N
2025	Admin	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36	Y	2025-08-18 15:22:15.590038	\N
2025	Admin	admin	\N	102.141.42.184	Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36	Y	2025-08-18 16:12:51.474382	\N
2025	admin	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36	Y	2025-08-18 18:24:05.018073	\N
2025	Admin	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36	Y	2025-08-19 07:41:36.207173	\N
2025	Admin	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36	Y	2025-08-19 09:36:17.652074	\N
2025	Admin	admin	\N	102.141.42.184	Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36	Y	2025-08-19 11:14:00.622646	\N
2025	Admin	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36	Y	2025-08-21 08:13:13.989071	\N
2025	admin	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36	Y	2025-08-21 15:39:49.38932	\N
2025	Admin	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36	Y	2025-08-22 10:42:13.607766	\N
2025	admin	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36	Y	2025-08-22 10:46:53.050431	\N
2025	admin	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36	Y	2025-08-22 11:15:28.423496	\N
2025	admin	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36	Y	2025-08-22 11:17:00.877028	\N
2025	admin	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36	Y	2025-08-22 11:18:50.573645	\N
2025	Admin	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36	Y	2025-08-22 11:22:01.924967	\N
2025	Admin	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36	Y	2025-08-22 11:22:16.293655	\N
2025	Admin	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36	Y	2025-08-22 11:23:06.088431	\N
2025	Admin	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36	Y	2025-08-22 11:24:27.87868	\N
2025	admin	admin	\N	102.141.42.184	Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Mobile Safari/537.36	Y	2025-08-22 11:47:39.351107	\N
2025	admin	admin	\N	102.141.42.184	Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36	Y	2025-08-22 11:48:53.679735	\N
2025	admin	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36	Y	2025-08-22 15:30:29.025797	\N
2025	Admin	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36	Y	2025-08-22 16:49:54.676215	\N
2025	Admin	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36	Y	2025-08-22 16:54:47.442904	\N
2025	admin	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36	Y	2025-08-24 16:20:22.643491	\N
2025	Admin	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36	Y	2025-08-25 08:15:56.030222	\N
2025	admin	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36	Y	2025-08-25 10:19:54.430853	\N
2025	admin	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36	Y	2025-08-25 10:23:05.875642	\N
2025	Admin	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36	Y	2025-08-25 10:23:55.17298	\N
2025	Admin	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36 Edg/139.0.0.0	Y	2025-08-25 12:01:48.821496	\N
2025	Admin	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36	Y	2025-08-25 13:20:46.84649	\N
2025	Admin	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36	Y	2025-08-25 13:21:47.061631	\N
2025	Admin	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36	Y	2025-08-25 13:27:03.200114	\N
2025	Admin	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36	Y	2025-08-26 08:18:30.558917	\N
2025	admin	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36	Y	2025-08-26 13:04:14.240406	\N
2025	Admin	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36	Y	2025-08-27 08:19:54.311985	\N
2025	Admin	admin	\N	169.255.121.160	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36	Y	2025-08-27 14:32:51.105462	\N
2025	Admin	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36	Y	2025-08-28 07:56:51.70068	\N
2025	Admin	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36	Y	2025-08-28 11:39:45.776425	\N
2025	Admin	admin	\N	102.141.42.184	Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36	Y	2025-08-28 14:19:52.332953	\N
2025	Admin	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36	Y	2025-08-28 14:24:49.842438	\N
2025	Admin	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36	Y	2025-08-28 14:28:53.873579	\N
2025	Admin	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36	Y	2025-08-29 08:15:48.6418	\N
2025	admin	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36	Y	2025-08-29 10:55:37.727185	\N
2025	Admin	admin	\N	102.141.46.37	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36	Y	2025-08-29 12:06:30.192765	\N
2025	Admin	admin	\N	102.141.46.37	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36	Y	2025-08-29 13:03:53.75336	\N
2025	Admin	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36	Y	2025-08-29 13:16:49.200144	\N
2025	admin	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36	Y	2025-08-29 13:21:46.461725	\N
2025	Admin	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36	Y	2025-09-01 07:33:51.304966	\N
2025	Admin	admin	\N	102.141.42.184	Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36	Y	2025-09-01 08:10:45.034569	\N
2025	Admin	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36	Y	2025-09-01 08:28:04.232951	\N
2025	Admin	admin	\N	102.141.42.184	Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36	Y	2025-09-01 09:15:30.704406	\N
2025	Admin	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36	Y	2025-09-01 09:37:29.865363	\N
2025	Admin	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36	Y	2025-09-01 13:29:12.263086	\N
2025	Admin	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36	Y	2025-09-02 07:59:05.951479	\N
2025	Admin	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36	Y	2025-09-02 08:00:07.059787	\N
2025	Admin	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36	Y	2025-09-02 08:08:32.605632	\N
2025	admin	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36	Y	2025-09-02 10:01:52.302611	\N
2025	Admin	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36	Y	2025-09-03 08:23:39.365904	\N
2025	Admin	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36	Y	2025-09-03 10:32:11.769197	\N
2025	Admin	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36	Y	2025-09-03 13:27:15.264487	\N
2025	Admin	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36	Y	2025-09-03 15:24:57.905916	\N
2025	admin	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36	Y	2025-09-03 16:09:42.012406	\N
2025	Admin	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36	Y	2025-09-04 08:12:25.21275	\N
2025	Admin	admin	\N	102.141.42.184	Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36	Y	2025-09-04 09:16:26.737975	\N
2025	Admin	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36	Y	2025-09-04 15:05:55.385578	\N
2025	Admin	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36	Y	2025-09-04 15:26:20.631885	\N
2025	Admin	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36	Y	2025-09-05 07:43:44.494159	\N
2025	Admin	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36	Y	2025-09-05 09:59:13.989466	\N
2025	admin	\N	\N	102.141.47.14	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36 Edg/139.0.0.0	\N	2025-09-05 11:57:29.120748	\N
2025	admin	\N	\N	102.141.47.14	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36 Edg/139.0.0.0	\N	2025-09-05 12:18:18.302791	\N
2025	admin	\N	\N	102.141.47.14	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36 Edg/139.0.0.0	\N	2025-09-05 12:18:31.088027	\N
2025	admin	\N	\N	102.141.47.14	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36 Edg/139.0.0.0	\N	2025-09-05 12:24:23.283599	\N
2025	admin	admin	\N	102.141.47.14	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36 Edg/139.0.0.0	Y	2025-09-05 12:27:45.861307	\N
2025	Admin	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36	Y	2025-09-05 13:56:34.026794	\N
2025	daryonrocknes@icloud.com	teacher	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36	Y	2025-09-05 14:05:46.844038	\N
2025	Admin	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36	Y	2025-09-05 14:12:28.430272	\N
2025	daryonrocknes@icloud.com	teacher	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36	Y	2025-09-05 14:13:12.708863	\N
2025	Admin	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36	Y	2025-09-05 14:15:50.9825	\N
2025	daryonrocknes@icloud.com	teacher	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36	Y	2025-09-05 14:49:12.801765	\N
2025	daryonrocknes@icloud.com	teacher	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36	Y	2025-09-05 14:50:49.146465	\N
2025	Admin	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36	Y	2025-09-05 14:51:12.246599	\N
2025	daryonrocknes@icloud.com	teacher	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36	Y	2025-09-05 14:51:47.836269	\N
2025	Admin	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36	Y	2025-09-05 14:53:10.66554	\N
2025	daryonrocknes@icloud.com	teacher	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36	Y	2025-09-05 15:16:19.788303	\N
2025	daryonrocknes@icloud.com	teacher	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36	Y	2025-09-08 08:07:50.875001	\N
2025	Admin	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36	Y	2025-09-08 08:08:56.768864	\N
2025	Admin	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36	Y	2025-09-08 13:51:00.927247	\N
2025	Admin	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36	Y	2025-09-08 13:53:34.79157	\N
2025	Admin	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36	Y	2025-09-08 13:58:07.804186	\N
2025	Admin	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36	Y	2025-09-08 14:11:47.179559	\N
2025	Admin	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36	Y	2025-09-09 08:10:16.612413	\N
2025	Admin	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36	Y	2025-09-09 08:13:40.405948	\N
2025	admin	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36	Y	2025-09-09 08:24:06.516721	\N
2025	Admin	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36	Y	2025-09-09 11:32:38.221681	\N
2025	Admin	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36	Y	2025-09-09 11:49:02.468158	\N
2025	Admin	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36	Y	2025-09-09 11:50:46.226346	\N
2025	Admin	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36	Y	2025-09-09 12:05:48.0475	\N
2025	Admin	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36	Y	2025-09-09 12:29:51.317009	\N
2025	Admin	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36	Y	2025-09-09 13:04:07.414882	\N
2025	admin	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36	Y	2025-09-09 13:25:14.181686	\N
2025	Admin	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36	Y	2025-09-09 16:42:21.613012	\N
2025	Admin	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36	Y	2025-09-10 08:00:17.452526	\N
2025	Admin	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36	Y	2025-09-10 09:59:54.924682	\N
2025	Admin	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36	Y	2025-09-10 11:11:28.064714	\N
2025	Admin	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36	Y	2025-09-10 11:19:45.808801	\N
2025	Admin	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36	Y	2025-09-10 13:11:38.369982	\N
2025	Admin	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36	Y	2025-09-10 14:22:59.861655	\N
2025	Admin	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36	Y	2025-09-10 14:32:50.104788	\N
2025	Admin	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36	Y	2025-09-10 15:01:19.838556	\N
2025	Admin	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36	Y	2025-09-10 15:33:39.903364	\N
2025	Admin	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36	Y	2025-09-10 16:32:33.547459	\N
2025	admin	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36	Y	2025-09-10 17:11:24.007244	\N
2025	Admin	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36	Y	2025-09-11 08:20:09.640964	\N
2025	Admin	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36	Y	2025-09-11 08:28:58.302039	\N
2025	Admin	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36	Y	2025-09-11 10:36:59.650742	\N
2025	Admin	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36	Y	2025-09-11 10:55:21.238301	\N
2025	Admin	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36	Y	2025-09-11 10:55:55.497758	\N
2025	Admin	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36	Y	2025-09-11 12:53:06.437096	\N
2025	Admin	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36	Y	2025-09-11 13:14:58.988487	\N
2025	Admin	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36	Y	2025-09-11 13:24:19.310034	\N
2025	Admin	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36	Y	2025-09-11 16:21:44.097835	\N
2025	Admin	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36	Y	2025-09-12 08:08:31.400627	\N
2025	Admin	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36	Y	2025-09-12 09:43:55.358596	\N
2025	Admin	admin	\N	149.36.51.9	Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36	Y	2025-09-12 11:01:16.192104	\N
2025	admin	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36	Y	2025-09-12 11:03:15.339976	\N
2025	admin	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36	Y	2025-09-12 11:05:21.428012	\N
2025	Admin	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36	Y	2025-09-12 11:06:56.060631	\N
2025	admin	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/136.0.0.0 Safari/537.36	Y	2025-09-12 11:08:46.142665	\N
2025	Admin	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36	Y	2025-09-12 11:09:23.97654	\N
2025	admin	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/136.0.0.0 Safari/537.36	Y	2025-09-12 11:18:41.347096	\N
2025	admin	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36	Y	2025-09-12 11:50:10.484956	\N
2025	Admin	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36	Y	2025-09-12 13:23:23.734251	\N
2025	admin	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36	Y	2025-09-12 13:40:47.645905	\N
2025	Admin	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36	Y	2025-09-12 15:59:24.88007	\N
2025	Admin	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36	Y	2025-09-12 16:21:38.741188	\N
2025	Admin	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36	Y	2025-09-16 13:24:52.446673	\N
2025	admin	\N	\N	102.141.42.184	Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36	\N	2025-09-16 14:04:49.133166	\N
2025	Admin	admin	\N	102.141.42.184	Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36	Y	2025-09-16 14:05:47.558445	\N
2025	admin	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36	Y	2025-09-16 14:24:07.704315	\N
2025	Admin	admin	\N	102.141.42.184	Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36	Y	2025-09-17 10:03:45.246547	\N
2025	Admin	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36	Y	2025-09-17 10:06:56.766217	\N
2025	Admin	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36	Y	2025-09-17 11:23:39.778956	\N
2025	admin	admin	\N	102.141.42.184	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36	Y	2025-09-17 13:21:55.326667	\N
2025	Admin	admin	\N	::1	Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36	Y	2025-09-19 10:46:32.019103	\N
2025	Admin	admin	\N	::1	Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36	Y	2025-09-19 11:15:08.553702	\N
2025	Admin	admin	\N	::1	Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36	Y	2025-09-20 11:20:07.46164	\N
2025	Admin	admin	\N	::1	Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36	Y	2025-09-24 21:36:42.870907	\N
2025	Admin	admin	\N	::1	Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36	Y	2025-09-24 22:19:05.852795	\N
2025	Admin	admin	\N	::1	Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36	Y	2025-09-19 11:26:29.392198	\N
2025	Admin	admin	\N	::1	Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36	Y	2025-09-20 11:35:34.816426	\N
2025	Admin	admin	\N	::1	Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36	Y	2025-09-24 21:39:43.121975	\N
2025	Admin	admin	\N	::1	Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36	Y	2025-09-24 22:26:36.210676	\N
2025	Admin	admin	\N	::1	Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36	Y	2025-09-19 16:24:40.096126	\N
2025	Admin	admin	\N	::1	Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36	Y	2025-09-20 11:39:15.0829	\N
2025	Admin	admin	\N	::1	Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36	Y	2025-09-24 21:44:50.052784	\N
2025	Admin	admin	\N	::1	Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36	Y	2025-09-24 22:36:17.838578	\N
2025	Admin	admin	\N	::1	Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36	Y	2025-09-19 22:47:18.421155	\N
2025	Admin	admin	\N	::1	Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36	Y	2025-09-24 21:54:23.39803	\N
\.


--
-- Data for Name: accounting_categories; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.accounting_categories (id, school_id, title, short_name, type, sort_order, created_at, updated_at) FROM stdin;
3	17	DONS	DONS	incomes	\N	2025-01-30 12:34:55.040646	2025-01-30 12:36:16.910144
6	17	MATERIEL PEDAGOGIQUES	MATERIEL	expenses	\N	2025-01-30 12:37:51.899763	\N
2	17	REVENUS SCOLAIRES	REVENU	incomes	\N	2025-01-30 12:34:26.321548	2025-01-30 12:36:16.912564
5	17	SALAIRES	SALAIRE	expenses	\N	2025-01-30 12:37:04.015028	\N
4	17	SUBVENTIONS	SUBVEN	incomes	\N	2025-01-30 12:36:16.913144	\N
7	17	FRAIS DE MAINTENANCE	MAINTENANC	expenses	\N	2025-01-30 12:38:52.16221	\N
\.


--
-- Data for Name: accounting_incomes; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.accounting_incomes (assigned_date, comments, id, title, category_id, amount, file_attached, school_id, syear, created_at, updated_at) FROM stdin;
2025-11-01	\N	3	500 000	2	300000.00	\N	17	2024	2025-02-12 13:48:32.673198	\N
2025-02-12	\N	4	500000	2	500000.00	\N	17	2024	2025-02-12 13:49:13.721253	\N
\.


--
-- Data for Name: accounting_payments; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.accounting_payments (id, syear, school_id, staff_id, title, category_id, amount, payment_date, comments, file_attached, created_at, updated_at) FROM stdin;
13	2025	21	\N	12 PAQUET RAM	\N	20000.00	2025-09-12	\N	\N	2025-09-12 13:04:24.735583	\N
12	2025	21	\N	12 paquet de ram	\N	20000.00	2025-09-12	\N	\N	2025-09-12 13:03:17.979679	\N
14	2025	21	\N	12 PAQUETS RAME	\N	20000.00	2025-09-12	\N	\N	2025-09-12 13:05:05.971411	\N
15	2025	21	\N	3 BOITE DE CRAIES	\N	1500.00	2025-09-12	\N	\N	2025-09-12 13:05:22.908052	\N
\.


--
-- Data for Name: accounting_salaries; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.accounting_salaries (staff_id, assigned_date, due_date, comments, id, title, amount, file_attached, school_id, syear, created_at, updated_at) FROM stdin;
4430	2025-09-12	2025-09-12	\N	7	Salaire de Septembre 2025	4125.00	assets/FileUploads/2025/staff_4430/bulletin_2025-09-12_13-34-32.pdf	21	2025	2025-09-12 13:34:34.007212	\N
4431	2025-09-25	\N	\N	8	1222	-0.04	\N	21	2025	2025-09-24 23:07:34.06523	\N
\.


--
-- Data for Name: address; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.address (address_id, house_no, direction, street, apt, zipcode, city, state, mail_street, mail_city, mail_state, mail_zipcode, address, mail_address, phone, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: address_field_categories; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.address_field_categories (id, title, sort_order, residence, mailing, bus, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: address_fields; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.address_fields (id, type, title, sort_order, select_options, category_id, required, default_selection, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: attendance_calendar; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.attendance_calendar (syear, school_id, school_date, minutes, block, calendar_id, created_at, updated_at) FROM stdin;
2024	16	2024-10-01	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2024-10-02	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2024-10-03	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2024-10-04	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2024-10-07	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2024-10-08	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2024-10-09	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2024-10-10	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2024-10-11	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2024-10-14	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2024-10-15	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2024-10-16	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2024-10-17	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2024-10-18	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2024-10-21	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2024-10-22	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2024-10-23	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2024-10-24	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2024-10-25	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2024-10-28	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2024-10-29	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2024-10-30	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2024-10-31	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2024-11-01	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2024-11-04	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2024-11-05	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2024-11-06	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2024-11-07	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2024-11-08	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2024-11-11	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2024-11-12	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2024-11-13	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2024-11-14	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2024-11-15	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2024-11-18	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2024-11-19	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2024-11-20	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2024-11-21	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2024-11-22	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2024-11-25	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2024-11-26	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2024-11-27	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2024-11-28	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2024-11-29	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2024-12-02	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2024-12-03	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2024-12-04	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2024-12-05	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2024-12-06	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2024-12-09	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2024-12-10	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2024-12-11	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2024-12-12	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2024-12-13	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2024-12-16	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2024-12-17	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2024-12-18	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2024-12-19	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2024-12-20	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2024-12-23	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2024-12-24	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2024-12-25	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2024-12-26	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2024-12-27	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2024-12-30	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2024-12-31	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2025-01-01	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2025-01-02	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2025-01-03	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2025-01-06	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2025-01-07	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2025-01-08	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2025-01-09	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2025-01-10	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2025-01-13	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2025-01-14	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2025-01-15	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2025-01-16	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2025-01-17	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2025-01-20	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2025-01-21	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2025-01-22	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2025-01-23	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2025-01-24	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2025-01-27	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2025-01-28	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2025-01-29	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2025-01-30	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2025-01-31	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2025-02-03	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2025-02-04	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2025-02-05	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2025-02-06	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2025-02-07	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2025-02-10	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2025-02-11	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2025-02-12	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2025-02-13	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2025-02-14	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2025-02-17	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2025-02-18	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2025-02-19	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2025-02-20	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2025-02-21	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2025-02-24	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2025-02-25	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2025-02-26	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2025-02-27	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2025-02-28	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2025-03-03	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2025-03-04	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2025-03-05	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2025-03-06	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2025-03-07	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2025-03-10	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2025-03-11	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2025-03-12	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2025-03-13	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2025-03-14	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2025-03-17	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2025-03-18	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2025-03-19	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2025-03-20	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2025-03-21	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2025-03-24	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2025-03-25	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2025-03-26	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2025-03-27	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2025-03-28	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2025-03-31	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2025-04-01	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2025-04-02	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2025-04-03	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2025-04-04	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2025-04-07	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2025-04-08	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2025-04-09	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2025-04-10	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2025-04-11	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2025-04-14	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2025-04-15	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2025-04-16	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2025-04-17	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2025-04-18	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2025-04-21	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2025-04-22	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2025-04-23	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2025-04-24	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2025-04-25	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2025-04-28	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2025-04-29	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2025-04-30	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2025-05-01	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2025-05-02	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2025-05-05	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2025-05-06	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2025-05-07	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2025-05-08	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2025-05-09	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2025-05-12	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2025-05-13	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2025-05-14	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2025-05-15	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2025-05-16	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2025-05-19	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2025-05-20	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2025-05-21	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2025-05-22	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2025-05-23	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2025-05-26	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2025-05-27	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2025-05-28	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2025-05-29	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2025-05-30	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2025-06-02	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2025-06-03	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2025-06-04	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2025-06-05	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	16	2025-06-06	999	\N	1	2024-12-17 14:19:45.754928	\N
2024	17	2024-10-01	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2024-10-02	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2024-10-03	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2024-10-04	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2024-10-07	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2024-10-08	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2024-10-09	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2024-10-10	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2024-10-11	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2024-10-14	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2024-10-15	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2024-10-16	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2024-10-17	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2024-10-18	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2024-10-21	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2024-10-22	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2024-10-23	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2024-10-24	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2024-10-25	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2024-10-28	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2024-10-29	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2024-10-30	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2024-10-31	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2024-11-01	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2024-11-04	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2024-11-05	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2024-11-06	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2024-11-07	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2024-11-08	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2024-11-11	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2024-11-12	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2024-11-13	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2024-11-14	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2024-11-15	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2024-11-18	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2024-11-19	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2024-11-20	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2024-11-21	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2024-11-22	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2024-11-25	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2024-11-26	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2024-11-27	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2024-11-28	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2024-11-29	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2024-12-02	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2024-12-03	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2024-12-04	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2024-12-05	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2024-12-06	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2024-12-09	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2024-12-10	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2024-12-11	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2024-12-12	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2024-12-13	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2024-12-16	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2024-12-17	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2024-12-18	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2024-12-19	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2024-12-20	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2024-12-23	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2024-12-24	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2024-12-25	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2024-12-26	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2024-12-27	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2024-12-30	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2024-12-31	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2025-01-01	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2025-01-02	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2025-01-03	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2025-01-06	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2025-01-07	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2025-01-08	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2025-01-09	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2025-01-10	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2025-01-13	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2025-01-14	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2025-01-15	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2025-01-16	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2025-01-17	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2025-01-20	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2025-01-21	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2025-01-22	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2025-01-23	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2025-01-24	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2025-01-27	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2025-01-28	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2025-01-29	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2025-01-30	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2025-01-31	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2025-02-03	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2025-02-04	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2025-02-05	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2025-02-06	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2025-02-07	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2025-02-10	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2025-02-11	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2025-02-12	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2025-02-13	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2025-02-14	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2025-02-17	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2025-02-18	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2025-02-19	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2025-02-20	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2025-02-21	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2025-02-24	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2025-02-25	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2025-02-26	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2025-02-27	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2025-02-28	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2025-03-03	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2025-03-04	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2025-03-05	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2025-03-06	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2025-03-07	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2025-03-10	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2025-03-11	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2025-03-12	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2025-03-13	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2025-03-14	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2025-03-17	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2025-03-18	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2025-03-19	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2025-03-20	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2025-03-21	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2025-03-24	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2025-03-25	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2025-03-26	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2025-03-27	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2025-03-28	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2025-03-31	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2025-04-01	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2025-04-02	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2025-04-03	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2025-04-04	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2025-04-07	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2025-04-08	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2025-04-09	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2025-04-10	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2025-04-11	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2025-04-14	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2025-04-15	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2025-04-16	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2025-04-17	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2025-04-18	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2025-04-21	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2025-04-22	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2025-04-23	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2025-04-24	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2025-04-25	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2025-04-28	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2025-04-29	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2025-04-30	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2025-05-01	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2025-05-02	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2025-05-05	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2025-05-06	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2025-05-07	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2025-05-08	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2025-05-09	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2025-05-12	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2025-05-13	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2025-05-14	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2025-05-15	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2025-05-16	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2025-05-19	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2025-05-20	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2025-05-21	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2025-05-22	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2025-05-23	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2025-05-26	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2025-05-27	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2025-05-28	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2025-05-29	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2025-05-30	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2025-06-02	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2025-06-03	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2025-06-04	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2025-06-05	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	17	2025-06-06	999	\N	2	2025-01-23 14:51:09.658036	\N
2024	19	2025-04-06	90	\N	3	2025-03-09 16:13:03.008495	\N
2024	19	2025-04-07	90	\N	3	2025-03-09 16:13:03.008495	\N
2024	19	2025-04-09	90	\N	3	2025-03-09 16:13:03.008495	\N
2024	19	2025-04-11	90	\N	3	2025-03-09 16:13:03.008495	\N
2024	19	2025-04-13	90	\N	3	2025-03-09 16:13:03.008495	\N
2024	19	2025-04-14	90	\N	3	2025-03-09 16:13:03.008495	\N
2024	19	2025-04-16	90	\N	3	2025-03-09 16:13:03.008495	\N
2024	19	2025-04-18	90	\N	3	2025-03-09 16:13:03.008495	\N
2024	19	2025-04-20	90	\N	3	2025-03-09 16:13:03.008495	\N
2024	19	2025-04-21	90	\N	3	2025-03-09 16:13:03.008495	\N
2024	19	2025-04-23	90	\N	3	2025-03-09 16:13:03.008495	\N
2024	19	2025-04-25	90	\N	3	2025-03-09 16:13:03.008495	\N
2024	19	2025-04-27	90	\N	3	2025-03-09 16:13:03.008495	\N
2024	19	2025-04-28	90	\N	3	2025-03-09 16:13:03.008495	\N
2024	19	2025-04-30	90	\N	3	2025-03-09 16:13:03.008495	\N
2024	19	2025-05-02	90	\N	3	2025-03-09 16:13:03.008495	\N
2024	19	2025-05-04	90	\N	3	2025-03-09 16:13:03.008495	\N
2024	19	2025-05-05	90	\N	3	2025-03-09 16:13:03.008495	\N
2024	19	2025-05-07	90	\N	3	2025-03-09 16:13:03.008495	\N
2024	19	2025-05-09	90	\N	3	2025-03-09 16:13:03.008495	\N
2024	19	2025-05-11	90	\N	3	2025-03-09 16:13:03.008495	\N
2024	19	2025-05-12	90	\N	3	2025-03-09 16:13:03.008495	\N
2024	19	2025-05-14	90	\N	3	2025-03-09 16:13:03.008495	\N
2024	19	2025-05-16	90	\N	3	2025-03-09 16:13:03.008495	\N
2024	19	2025-05-18	90	\N	3	2025-03-09 16:13:03.008495	\N
2024	19	2025-05-19	90	\N	3	2025-03-09 16:13:03.008495	\N
2024	19	2025-05-21	90	\N	3	2025-03-09 16:13:03.008495	\N
2024	19	2025-05-23	90	\N	3	2025-03-09 16:13:03.008495	\N
2024	19	2025-05-25	90	\N	3	2025-03-09 16:13:03.008495	\N
2024	19	2025-05-26	90	\N	3	2025-03-09 16:13:03.008495	\N
2024	19	2025-05-28	90	\N	3	2025-03-09 16:13:03.008495	\N
2024	19	2025-05-30	90	\N	3	2025-03-09 16:13:03.008495	\N
2024	19	2025-06-01	90	\N	3	2025-03-09 16:13:03.008495	\N
2024	19	2025-06-02	90	\N	3	2025-03-09 16:13:03.008495	\N
2024	19	2025-06-04	90	\N	3	2025-03-09 16:13:03.008495	\N
2024	19	2025-06-06	90	\N	3	2025-03-09 16:13:03.008495	\N
2024	19	2025-06-08	90	\N	3	2025-03-09 16:13:03.008495	\N
2024	19	2025-06-09	90	\N	3	2025-03-09 16:13:03.008495	\N
2024	19	2025-06-11	90	\N	3	2025-03-09 16:13:03.008495	\N
2024	19	2025-06-13	90	\N	3	2025-03-09 16:13:03.008495	\N
2024	19	2025-06-15	90	\N	3	2025-03-09 16:13:03.008495	\N
2024	19	2025-06-16	90	\N	3	2025-03-09 16:13:03.008495	\N
2024	19	2025-06-18	90	\N	3	2025-03-09 16:13:03.008495	\N
2024	19	2025-06-20	90	\N	3	2025-03-09 16:13:03.008495	\N
2024	19	2025-06-22	90	\N	3	2025-03-09 16:13:03.008495	\N
2024	19	2025-06-23	90	\N	3	2025-03-09 16:13:03.008495	\N
2024	19	2025-06-25	90	\N	3	2025-03-09 16:13:03.008495	\N
2024	19	2025-06-27	90	\N	3	2025-03-09 16:13:03.008495	\N
2024	19	2025-06-29	90	\N	3	2025-03-09 16:13:03.008495	\N
2024	19	2025-06-30	90	\N	3	2025-03-09 16:13:03.008495	\N
2024	19	2025-07-02	90	\N	3	2025-03-09 16:13:03.008495	\N
2024	19	2025-07-04	90	\N	3	2025-03-09 16:13:03.008495	\N
2024	19	2025-07-06	90	\N	3	2025-03-09 16:13:03.008495	\N
2024	19	2025-07-07	90	\N	3	2025-03-09 16:13:03.008495	\N
2024	19	2025-07-09	90	\N	3	2025-03-09 16:13:03.008495	\N
2024	19	2025-07-11	90	\N	3	2025-03-09 16:13:03.008495	\N
2024	19	2025-07-13	90	\N	3	2025-03-09 16:13:03.008495	\N
2024	19	2025-07-14	90	\N	3	2025-03-09 16:13:03.008495	\N
2024	19	2025-07-16	90	\N	3	2025-03-09 16:13:03.008495	\N
2024	19	2025-07-18	90	\N	3	2025-03-09 16:13:03.008495	\N
2024	19	2025-07-20	90	\N	3	2025-03-09 16:13:03.008495	\N
2024	19	2025-07-21	90	\N	3	2025-03-09 16:13:03.008495	\N
2024	19	2025-07-23	90	\N	3	2025-03-09 16:13:03.008495	\N
2024	19	2025-07-25	90	\N	3	2025-03-09 16:13:03.008495	\N
2024	19	2025-07-27	90	\N	3	2025-03-09 16:13:03.008495	\N
2024	19	2025-07-28	90	\N	3	2025-03-09 16:13:03.008495	\N
2024	19	2025-07-30	90	\N	3	2025-03-09 16:13:03.008495	\N
2024	19	2025-08-01	90	\N	3	2025-03-09 16:13:03.008495	\N
2024	19	2025-08-03	90	\N	3	2025-03-09 16:13:03.008495	\N
2024	19	2025-08-04	90	\N	3	2025-03-09 16:13:03.008495	\N
2024	19	2025-08-06	90	\N	3	2025-03-09 16:13:03.008495	\N
2024	19	2025-08-08	90	\N	3	2025-03-09 16:13:03.008495	\N
2024	19	2025-08-10	90	\N	3	2025-03-09 16:13:03.008495	\N
2024	19	2025-08-11	90	\N	3	2025-03-09 16:13:03.008495	\N
2024	19	2025-08-13	90	\N	3	2025-03-09 16:13:03.008495	\N
2024	19	2025-08-15	90	\N	3	2025-03-09 16:13:03.008495	\N
2024	19	2025-08-17	90	\N	3	2025-03-09 16:13:03.008495	\N
2024	19	2025-08-18	90	\N	3	2025-03-09 16:13:03.008495	\N
2024	19	2025-08-20	90	\N	3	2025-03-09 16:13:03.008495	\N
2024	19	2025-08-22	90	\N	3	2025-03-09 16:13:03.008495	\N
2024	19	2025-08-24	90	\N	3	2025-03-09 16:13:03.008495	\N
2024	19	2025-08-25	90	\N	3	2025-03-09 16:13:03.008495	\N
2024	19	2025-08-27	90	\N	3	2025-03-09 16:13:03.008495	\N
2024	19	2025-08-29	90	\N	3	2025-03-09 16:13:03.008495	\N
2024	19	2025-08-31	90	\N	3	2025-03-09 16:13:03.008495	\N
2024	19	2025-09-01	90	\N	3	2025-03-09 16:13:03.008495	\N
2024	19	2025-09-03	90	\N	3	2025-03-09 16:13:03.008495	\N
2024	19	2025-09-05	90	\N	3	2025-03-09 16:13:03.008495	\N
2024	19	2025-03-02	999	\N	3	2025-03-09 16:23:57.586835	\N
2024	19	2025-03-03	999	\N	3	2025-03-09 16:23:57.592019	\N
2024	19	2025-03-05	999	\N	3	2025-03-09 16:23:57.592792	\N
2024	19	2025-03-07	999	\N	3	2025-03-09 16:23:57.593387	\N
2024	19	2025-03-09	999	\N	3	2025-03-09 16:23:57.594284	\N
2024	19	2025-03-10	999	\N	3	2025-03-09 16:23:57.594902	\N
2024	19	2025-03-12	999	\N	3	2025-03-09 16:23:57.595622	\N
2024	19	2025-03-14	999	\N	3	2025-03-09 16:23:57.597159	\N
2024	19	2025-03-16	999	\N	3	2025-03-09 16:23:57.597969	\N
2024	19	2025-03-17	999	\N	3	2025-03-09 16:23:57.598781	\N
2024	19	2025-03-19	999	\N	3	2025-03-09 16:23:57.59984	\N
2024	19	2025-03-21	999	\N	3	2025-03-09 16:23:57.600444	\N
2024	19	2025-03-23	999	\N	3	2025-03-09 16:23:57.60109	\N
2024	19	2025-03-24	999	\N	3	2025-03-09 16:23:57.60176	\N
2024	19	2025-03-26	999	\N	3	2025-03-09 16:23:57.602427	\N
2024	19	2025-03-28	999	\N	3	2025-03-09 16:23:57.603086	\N
2024	19	2025-03-30	999	\N	3	2025-03-09 16:23:57.603716	\N
2024	19	2025-03-31	999	\N	3	2025-03-09 16:23:57.604274	\N
2025	21	2025-09-01	999	\N	4	2025-09-11 16:42:01.928724	\N
2025	21	2025-09-11	999	\N	4	2025-09-11 16:42:01.934314	\N
2025	21	2025-09-12	999	\N	4	2025-09-11 16:42:01.936407	\N
2025	21	2025-10-10	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2025-10-13	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2025-10-14	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2025-10-15	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2025-10-16	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2025-10-17	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2025-10-20	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2025-10-21	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2025-10-22	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2025-10-23	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2025-10-24	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2025-10-27	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2025-10-28	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2025-10-29	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2025-10-30	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2025-10-31	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2025-11-03	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2025-11-04	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2025-11-05	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2025-11-06	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2025-11-07	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2025-11-10	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2025-11-11	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2025-11-12	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2025-11-13	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2025-11-14	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2025-11-17	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2025-11-18	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2025-11-19	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2025-11-20	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2025-11-21	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2025-11-24	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2025-11-25	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2025-11-26	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2025-11-27	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2025-11-28	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2025-12-01	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2025-12-02	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2025-12-03	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2025-12-04	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2025-12-05	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2025-12-08	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2025-12-09	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2025-12-10	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2025-12-11	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2025-12-12	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2025-12-15	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2025-12-16	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2025-12-17	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2025-12-18	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2025-12-19	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2025-12-22	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2025-12-23	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2025-12-24	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2025-12-25	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2025-12-26	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2025-12-29	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2025-12-30	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2025-12-31	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-01-01	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-01-02	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-01-05	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-01-06	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-01-07	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-01-08	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-01-09	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-01-12	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-01-13	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-01-14	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-01-15	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-01-16	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-01-19	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-01-20	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-01-21	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-01-22	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-01-23	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-01-26	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-01-27	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-01-28	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-01-29	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-01-30	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-02-02	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-02-03	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-02-04	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-02-05	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-02-06	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-02-09	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-02-10	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-02-11	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-02-12	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-02-13	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-02-16	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-02-17	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-02-18	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-02-19	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-02-20	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-02-23	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-02-24	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-02-25	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-02-26	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-02-27	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-03-02	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-03-03	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-03-04	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-03-05	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-03-06	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-03-09	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-03-10	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-03-11	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-03-12	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-03-13	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-03-16	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-03-17	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-03-18	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-03-19	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-03-20	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-03-23	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-03-24	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-03-25	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-03-26	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-03-27	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-03-30	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-03-31	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-04-01	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-04-02	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-04-03	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-04-06	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-04-07	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-04-08	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-04-09	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-04-10	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-04-13	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-04-14	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-04-15	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-04-16	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-04-17	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-04-20	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-04-21	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-04-22	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-04-23	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-04-24	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-04-27	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-04-28	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-04-29	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-04-30	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-05-01	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-05-04	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-05-05	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-05-06	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-05-07	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-05-08	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-05-11	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-05-12	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-05-13	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-05-14	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-05-15	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-05-18	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-05-19	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-05-20	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-05-21	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-05-22	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-05-25	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-05-26	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-05-27	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-05-28	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-05-29	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-06-01	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-06-02	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-06-03	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-06-04	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-06-05	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-06-08	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-06-09	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-06-10	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-06-11	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-06-12	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-06-15	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-06-16	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-06-17	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-06-18	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-06-19	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-06-22	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-06-23	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-06-24	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-06-25	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-06-26	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-06-29	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-06-30	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-07-01	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-07-02	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-07-03	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-07-06	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-07-07	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-07-08	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-07-09	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-07-10	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-07-13	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-07-14	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-07-15	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-07-16	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-07-17	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-07-20	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-07-21	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-07-22	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-07-23	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-07-24	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-07-27	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-07-28	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-07-29	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-07-30	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-07-31	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-08-03	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-08-04	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-08-05	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-08-06	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-08-07	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-08-10	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-08-11	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-08-12	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-08-13	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-08-14	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-08-17	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-08-18	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-08-19	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-08-20	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-08-21	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-08-24	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-08-25	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-08-26	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-08-27	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-08-28	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-08-31	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-09-01	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-09-02	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-09-03	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-09-04	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-09-07	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-09-08	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-09-09	999	\N	4	2025-08-13 22:29:49.535234	\N
2025	21	2026-09-10	999	\N	4	2025-08-13 22:29:49.535234	\N
\.


--
-- Data for Name: attendance_calendars; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.attendance_calendars (school_id, title, syear, calendar_id, default_calendar, rollover_id, created_at, updated_at) FROM stdin;
16	Calendrier Royauté 2024-2025	2024	1	Y	\N	2024-12-17 14:19:45.750216	\N
17	Année 2024-2025	2024	2	Y	\N	2025-01-23 14:51:09.653983	\N
19	formation coupe et couture	2024	3	Y	\N	2025-03-09 16:13:02.992399	\N
21	Calendrier du Trimestre 1	2025	4	Y	\N	2025-08-06 12:14:08.128674	2025-08-13 22:29:49.529986
\.


--
-- Data for Name: attendance_code_categories; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.attendance_code_categories (id, syear, school_id, title, sort_order, rollover_id, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: attendance_codes; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.attendance_codes (id, syear, school_id, title, short_name, type, state_code, default_code, table_name, sort_order, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: attendance_completed; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.attendance_completed (staff_id, school_date, period_id, table_name, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: attendance_day; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.attendance_day (student_id, school_date, minutes_present, state_value, syear, marking_period_id, comment, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: attendance_period; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.attendance_period (student_id, school_date, period_id, attendance_code, attendance_teacher_code, attendance_reason, admin, course_period_id, marking_period_id, comment, created_at, updated_at, my_period_id) FROM stdin;
\.


--
-- Data for Name: billing_fees; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.billing_fees (student_id, assigned_date, due_date, comments, id, title, amount, file_attached, school_id, syear, waived_fee_id, created_at, updated_at, month) FROM stdin;
5	2025-08-25	\N	\N	1032	\N	10000.00	\N	21	2025	\N	2025-08-25 15:23:52.243207	\N	08
5	2025-08-25	\N	\N	1033	\N	10000.00	\N	21	2025	\N	2025-08-25 15:23:52.251224	\N	09
5	2025-08-25	\N	\N	1034	\N	10000.00	\N	21	2025	\N	2025-08-25 15:23:52.25232	\N	10
5	2025-08-25	\N	\N	1035	\N	10000.00	\N	21	2025	\N	2025-08-25 15:23:52.253338	\N	11
5	2025-08-25	\N	\N	1036	\N	10000.00	\N	21	2025	\N	2025-08-25 15:23:52.25419	\N	12
5	2025-08-25	\N	\N	1037	\N	10000.00	\N	21	2025	\N	2025-08-25 15:23:52.255318	\N	01
5	2025-08-25	\N	\N	1038	\N	10000.00	\N	21	2025	\N	2025-08-25 15:23:52.256104	\N	02
5	2025-08-25	\N	\N	1039	\N	10000.00	\N	21	2025	\N	2025-08-25 15:23:52.2668	\N	03
5	2025-08-25	\N	\N	1040	\N	10000.00	\N	21	2025	\N	2025-08-25 15:23:52.268028	\N	04
5	2025-08-25	\N	\N	1041	\N	10000.00	\N	21	2025	\N	2025-08-25 15:23:52.2692	\N	05
5	2025-08-25	\N	\N	1042	\N	10000.00	\N	21	2025	\N	2025-08-25 15:23:52.27049	\N	06
5	2025-08-25	\N	\N	1043	\N	10000.00	\N	21	2025	\N	2025-08-25 15:23:52.271488	\N	07
1111111	2025-08-25	\N	\N	1044	\N	10000.00	\N	21	2025	\N	2025-08-25 15:27:17.076554	\N	08
1111111	2025-08-25	\N	\N	1045	\N	10000.00	\N	21	2025	\N	2025-08-25 15:27:17.077876	\N	09
1111111	2025-08-25	\N	\N	1046	\N	10000.00	\N	21	2025	\N	2025-08-25 15:27:17.078615	\N	10
1111111	2025-08-25	\N	\N	1047	\N	10000.00	\N	21	2025	\N	2025-08-25 15:27:17.079248	\N	11
1111111	2025-08-25	\N	\N	1048	\N	10000.00	\N	21	2025	\N	2025-08-25 15:27:17.079911	\N	12
1111111	2025-08-25	\N	\N	1049	\N	10000.00	\N	21	2025	\N	2025-08-25 15:27:17.080627	\N	01
1111111	2025-08-25	\N	\N	1050	\N	10000.00	\N	21	2025	\N	2025-08-25 15:27:17.081335	\N	02
1111111	2025-08-25	\N	\N	1051	\N	10000.00	\N	21	2025	\N	2025-08-25 15:27:17.081938	\N	03
1111111	2025-08-25	\N	\N	1052	\N	10000.00	\N	21	2025	\N	2025-08-25 15:27:17.08292	\N	04
1111111	2025-08-25	\N	\N	1053	\N	10000.00	\N	21	2025	\N	2025-08-25 15:27:17.083753	\N	05
1111111	2025-08-25	\N	\N	1054	\N	10000.00	\N	21	2025	\N	2025-08-25 15:27:17.084692	\N	06
1111111	2025-08-25	\N	\N	1055	\N	10000.00	\N	21	2025	\N	2025-08-25 15:27:17.08532	\N	07
6	2025-08-25	\N	\N	1056	\N	10000.00	\N	21	2025	\N	2025-08-25 15:28:40.153819	\N	08
6	2025-08-25	\N	\N	1057	\N	10000.00	\N	21	2025	\N	2025-08-25 15:28:40.155662	\N	09
6	2025-08-25	\N	\N	1058	\N	10000.00	\N	21	2025	\N	2025-08-25 15:28:40.156327	\N	10
6	2025-08-25	\N	\N	1059	\N	10000.00	\N	21	2025	\N	2025-08-25 15:28:40.156962	\N	11
6	2025-08-25	\N	\N	1060	\N	10000.00	\N	21	2025	\N	2025-08-25 15:28:40.157558	\N	12
6	2025-08-25	\N	\N	1061	\N	10000.00	\N	21	2025	\N	2025-08-25 15:28:40.158176	\N	01
6	2025-08-25	\N	\N	1062	\N	10000.00	\N	21	2025	\N	2025-08-25 15:28:40.158882	\N	02
6	2025-08-25	\N	\N	1063	\N	10000.00	\N	21	2025	\N	2025-08-25 15:28:40.159519	\N	03
6	2025-08-25	\N	\N	1064	\N	10000.00	\N	21	2025	\N	2025-08-25 15:28:40.160283	\N	04
6	2025-08-25	\N	\N	1065	\N	10000.00	\N	21	2025	\N	2025-08-25 15:28:40.16098	\N	05
6	2025-08-25	\N	\N	1066	\N	10000.00	\N	21	2025	\N	2025-08-25 15:28:40.161533	\N	06
6	2025-08-25	\N	\N	1067	\N	10000.00	\N	21	2025	\N	2025-08-25 15:28:40.162074	\N	07
3	2025-08-27	\N	\N	1068	\N	10000.00	\N	21	2025	\N	2025-08-27 09:47:32.791174	\N	08
3	2025-08-27	\N	\N	1069	\N	10000.00	\N	21	2025	\N	2025-08-27 09:47:32.795449	\N	09
3	2025-08-27	\N	\N	1070	\N	10000.00	\N	21	2025	\N	2025-08-27 09:47:32.796348	\N	10
3	2025-08-27	\N	\N	1071	\N	10000.00	\N	21	2025	\N	2025-08-27 09:47:32.797206	\N	11
3	2025-08-27	\N	\N	1072	\N	10000.00	\N	21	2025	\N	2025-08-27 09:47:32.798064	\N	12
3	2025-08-27	\N	\N	1073	\N	10000.00	\N	21	2025	\N	2025-08-27 09:47:32.798932	\N	01
3	2025-08-27	\N	\N	1074	\N	10000.00	\N	21	2025	\N	2025-08-27 09:47:32.799619	\N	02
3	2025-08-27	\N	\N	1075	\N	10000.00	\N	21	2025	\N	2025-08-27 09:47:32.800248	\N	03
3	2025-08-27	\N	\N	1076	\N	10000.00	\N	21	2025	\N	2025-08-27 09:47:32.801177	\N	04
3	2025-08-27	\N	\N	1077	\N	10000.00	\N	21	2025	\N	2025-08-27 09:47:32.802	\N	05
3	2025-08-27	\N	\N	1078	\N	10000.00	\N	21	2025	\N	2025-08-27 09:47:32.802701	\N	06
3	2025-08-27	\N	\N	1079	\N	10000.00	\N	21	2025	\N	2025-08-27 09:47:32.803539	\N	07
3333333	2025-08-27	\N	\N	1080	\N	10000.00	\N	21	2025	\N	2025-08-27 10:11:39.561135	\N	08
3333333	2025-08-27	\N	\N	1081	\N	10000.00	\N	21	2025	\N	2025-08-27 10:11:39.563326	\N	09
3333333	2025-08-27	\N	\N	1082	\N	10000.00	\N	21	2025	\N	2025-08-27 10:11:39.564381	\N	10
3333333	2025-08-27	\N	\N	1083	\N	10000.00	\N	21	2025	\N	2025-08-27 10:11:39.565161	\N	11
3333333	2025-08-27	\N	\N	1084	\N	10000.00	\N	21	2025	\N	2025-08-27 10:11:39.565827	\N	12
3333333	2025-08-27	\N	\N	1085	\N	10000.00	\N	21	2025	\N	2025-08-27 10:11:39.566656	\N	01
3333333	2025-08-27	\N	\N	1086	\N	10000.00	\N	21	2025	\N	2025-08-27 10:11:39.567983	\N	02
3333333	2025-08-27	\N	\N	1087	\N	10000.00	\N	21	2025	\N	2025-08-27 10:11:39.568812	\N	03
3333333	2025-08-27	\N	\N	1088	\N	10000.00	\N	21	2025	\N	2025-08-27 10:11:39.570127	\N	04
3333333	2025-08-27	\N	\N	1089	\N	10000.00	\N	21	2025	\N	2025-08-27 10:11:39.571613	\N	05
3333333	2025-08-27	\N	\N	1090	\N	10000.00	\N	21	2025	\N	2025-08-27 10:11:39.57264	\N	06
3333333	2025-08-27	\N	\N	1091	\N	10000.00	\N	21	2025	\N	2025-08-27 10:11:39.573519	\N	07
2	2025-08-27	\N	\N	1092	\N	25000.00	\N	21	2025	\N	2025-08-27 10:12:05.016403	\N	08
2	2025-08-27	\N	\N	1093	\N	25000.00	\N	21	2025	\N	2025-08-27 10:12:05.018479	\N	09
2	2025-08-27	\N	\N	1094	\N	25000.00	\N	21	2025	\N	2025-08-27 10:12:05.019491	\N	10
2	2025-08-27	\N	\N	1095	\N	25000.00	\N	21	2025	\N	2025-08-27 10:12:05.020728	\N	11
2	2025-08-27	\N	\N	1096	\N	25000.00	\N	21	2025	\N	2025-08-27 10:12:05.021715	\N	12
2	2025-08-27	\N	\N	1097	\N	25000.00	\N	21	2025	\N	2025-08-27 10:12:05.023049	\N	01
2	2025-08-27	\N	\N	1098	\N	25000.00	\N	21	2025	\N	2025-08-27 10:12:05.024561	\N	02
2	2025-08-27	\N	\N	1099	\N	25000.00	\N	21	2025	\N	2025-08-27 10:12:05.025699	\N	03
2	2025-08-27	\N	\N	1100	\N	25000.00	\N	21	2025	\N	2025-08-27 10:12:05.026603	\N	04
2	2025-08-27	\N	\N	1101	\N	25000.00	\N	21	2025	\N	2025-08-27 10:12:05.027499	\N	05
2	2025-08-27	\N	\N	1102	\N	25000.00	\N	21	2025	\N	2025-08-27 10:12:05.028444	\N	06
2	2025-08-27	\N	\N	1103	\N	25000.00	\N	21	2025	\N	2025-08-27 10:12:05.029443	\N	07
222222	2025-08-27	\N	\N	1104	\N	10000.00	\N	21	2025	\N	2025-08-27 10:12:20.7213	\N	08
222222	2025-08-27	\N	\N	1105	\N	10000.00	\N	21	2025	\N	2025-08-27 10:12:20.724377	\N	09
222222	2025-08-27	\N	\N	1106	\N	10000.00	\N	21	2025	\N	2025-08-27 10:12:20.725758	\N	10
222222	2025-08-27	\N	\N	1107	\N	10000.00	\N	21	2025	\N	2025-08-27 10:12:20.727397	\N	11
222222	2025-08-27	\N	\N	1108	\N	10000.00	\N	21	2025	\N	2025-08-27 10:12:20.728642	\N	12
222222	2025-08-27	\N	\N	1109	\N	10000.00	\N	21	2025	\N	2025-08-27 10:12:20.729739	\N	01
222222	2025-08-27	\N	\N	1110	\N	10000.00	\N	21	2025	\N	2025-08-27 10:12:20.730583	\N	02
222222	2025-08-27	\N	\N	1111	\N	10000.00	\N	21	2025	\N	2025-08-27 10:12:20.731455	\N	03
222222	2025-08-27	\N	\N	1112	\N	10000.00	\N	21	2025	\N	2025-08-27 10:12:20.732439	\N	04
222222	2025-08-27	\N	\N	1113	\N	10000.00	\N	21	2025	\N	2025-08-27 10:12:20.733459	\N	05
222222	2025-08-27	\N	\N	1114	\N	10000.00	\N	21	2025	\N	2025-08-27 10:12:20.734931	\N	06
222222	2025-08-27	\N	\N	1115	\N	10000.00	\N	21	2025	\N	2025-08-27 10:12:20.736233	\N	07
1	2025-08-27	\N	\N	1116	\N	10000.00	\N	21	2025	\N	2025-08-27 10:12:33.145175	\N	08
1	2025-08-27	\N	\N	1117	\N	10000.00	\N	21	2025	\N	2025-08-27 10:12:33.146558	\N	09
1	2025-08-27	\N	\N	1118	\N	10000.00	\N	21	2025	\N	2025-08-27 10:12:33.147679	\N	10
1	2025-08-27	\N	\N	1119	\N	10000.00	\N	21	2025	\N	2025-08-27 10:12:33.14865	\N	11
1	2025-08-27	\N	\N	1120	\N	10000.00	\N	21	2025	\N	2025-08-27 10:12:33.149501	\N	12
1	2025-08-27	\N	\N	1121	\N	10000.00	\N	21	2025	\N	2025-08-27 10:12:33.150243	\N	01
1	2025-08-27	\N	\N	1122	\N	10000.00	\N	21	2025	\N	2025-08-27 10:12:33.15099	\N	02
1	2025-08-27	\N	\N	1123	\N	10000.00	\N	21	2025	\N	2025-08-27 10:12:33.151777	\N	03
1	2025-08-27	\N	\N	1124	\N	10000.00	\N	21	2025	\N	2025-08-27 10:12:33.15262	\N	04
1	2025-08-27	\N	\N	1125	\N	10000.00	\N	21	2025	\N	2025-08-27 10:12:33.153383	\N	05
1	2025-08-27	\N	\N	1126	\N	10000.00	\N	21	2025	\N	2025-08-27 10:12:33.154039	\N	06
1	2025-08-27	\N	\N	1127	\N	10000.00	\N	21	2025	\N	2025-08-27 10:12:33.154768	\N	07
12345	2025-08-27	\N	\N	1128	\N	10000.00	\N	21	2025	\N	2025-08-27 10:14:26.883813	\N	08
12345	2025-08-27	\N	\N	1129	\N	10000.00	\N	21	2025	\N	2025-08-27 10:14:26.886086	\N	09
12345	2025-08-27	\N	\N	1130	\N	10000.00	\N	21	2025	\N	2025-08-27 10:14:26.887666	\N	10
12345	2025-08-27	\N	\N	1131	\N	10000.00	\N	21	2025	\N	2025-08-27 10:14:26.88839	\N	11
12345	2025-08-27	\N	\N	1132	\N	10000.00	\N	21	2025	\N	2025-08-27 10:14:26.88915	\N	12
12345	2025-08-27	\N	\N	1133	\N	10000.00	\N	21	2025	\N	2025-08-27 10:14:26.889752	\N	01
12345	2025-08-27	\N	\N	1134	\N	10000.00	\N	21	2025	\N	2025-08-27 10:14:26.890505	\N	02
12345	2025-08-27	\N	\N	1135	\N	10000.00	\N	21	2025	\N	2025-08-27 10:14:26.891133	\N	03
12345	2025-08-27	\N	\N	1136	\N	10000.00	\N	21	2025	\N	2025-08-27 10:14:26.891862	\N	04
12345	2025-08-27	\N	\N	1137	\N	10000.00	\N	21	2025	\N	2025-08-27 10:14:26.892482	\N	05
12345	2025-08-27	\N	\N	1138	\N	10000.00	\N	21	2025	\N	2025-08-27 10:14:26.893236	\N	06
12345	2025-08-27	\N	\N	1139	\N	10000.00	\N	21	2025	\N	2025-08-27 10:14:26.893841	\N	07
44444445	2025-08-29	\N	\N	1140	\N	10000.00	\N	21	2025	\N	2025-08-29 17:20:08.253561	\N	08
44444445	2025-08-29	\N	\N	1141	\N	10000.00	\N	21	2025	\N	2025-08-29 17:20:08.261826	\N	09
44444445	2025-08-29	\N	\N	1142	\N	10000.00	\N	21	2025	\N	2025-08-29 17:20:08.262864	\N	10
44444445	2025-08-29	\N	\N	1143	\N	10000.00	\N	21	2025	\N	2025-08-29 17:20:08.264614	\N	11
44444445	2025-08-29	\N	\N	1144	\N	10000.00	\N	21	2025	\N	2025-08-29 17:20:08.265667	\N	12
44444445	2025-08-29	\N	\N	1145	\N	10000.00	\N	21	2025	\N	2025-08-29 17:20:08.266609	\N	01
44444445	2025-08-29	\N	\N	1146	\N	10000.00	\N	21	2025	\N	2025-08-29 17:20:08.267631	\N	02
44444445	2025-08-29	\N	\N	1147	\N	10000.00	\N	21	2025	\N	2025-08-29 17:20:08.26839	\N	03
44444445	2025-08-29	\N	\N	1148	\N	10000.00	\N	21	2025	\N	2025-08-29 17:20:08.269276	\N	04
44444445	2025-08-29	\N	\N	1149	\N	10000.00	\N	21	2025	\N	2025-08-29 17:20:08.270202	\N	05
44444445	2025-08-29	\N	\N	1150	\N	10000.00	\N	21	2025	\N	2025-08-29 17:20:08.27075	\N	06
44444445	2025-08-29	\N	\N	1151	\N	10000.00	\N	21	2025	\N	2025-08-29 17:20:08.271314	\N	07
851	2025-09-01	\N	\N	1152	\N	10000.00	\N	21	2025	\N	2025-09-01 07:52:56.596547	\N	08
851	2025-09-01	\N	\N	1153	\N	10000.00	\N	21	2025	\N	2025-09-01 07:52:56.599881	\N	09
851	2025-09-01	\N	\N	1154	\N	10000.00	\N	21	2025	\N	2025-09-01 07:52:56.600505	\N	10
851	2025-09-01	\N	\N	1155	\N	10000.00	\N	21	2025	\N	2025-09-01 07:52:56.601061	\N	11
851	2025-09-01	\N	\N	1156	\N	10000.00	\N	21	2025	\N	2025-09-01 07:52:56.601882	\N	12
851	2025-09-01	\N	\N	1157	\N	10000.00	\N	21	2025	\N	2025-09-01 07:52:56.602894	\N	01
851	2025-09-01	\N	\N	1158	\N	10000.00	\N	21	2025	\N	2025-09-01 07:52:56.603954	\N	02
851	2025-09-01	\N	\N	1159	\N	10000.00	\N	21	2025	\N	2025-09-01 07:52:56.604706	\N	03
851	2025-09-01	\N	\N	1160	\N	10000.00	\N	21	2025	\N	2025-09-01 07:52:56.605304	\N	04
851	2025-09-01	\N	\N	1161	\N	10000.00	\N	21	2025	\N	2025-09-01 07:52:56.605906	\N	05
851	2025-09-01	\N	\N	1162	\N	10000.00	\N	21	2025	\N	2025-09-01 07:52:56.606478	\N	06
851	2025-09-01	\N	\N	1163	\N	10000.00	\N	21	2025	\N	2025-09-01 07:52:56.607071	\N	07
853	2025-09-01	\N	\N	1164	\N	10000.00	\N	21	2025	\N	2025-09-01 07:53:20.599924	\N	08
853	2025-09-01	\N	\N	1165	\N	10000.00	\N	21	2025	\N	2025-09-01 07:53:20.601677	\N	09
853	2025-09-01	\N	\N	1166	\N	10000.00	\N	21	2025	\N	2025-09-01 07:53:20.602556	\N	10
853	2025-09-01	\N	\N	1167	\N	10000.00	\N	21	2025	\N	2025-09-01 07:53:20.603223	\N	11
853	2025-09-01	\N	\N	1168	\N	10000.00	\N	21	2025	\N	2025-09-01 07:53:20.603939	\N	12
853	2025-09-01	\N	\N	1169	\N	10000.00	\N	21	2025	\N	2025-09-01 07:53:20.604643	\N	01
853	2025-09-01	\N	\N	1170	\N	10000.00	\N	21	2025	\N	2025-09-01 07:53:20.605318	\N	02
853	2025-09-01	\N	\N	1171	\N	10000.00	\N	21	2025	\N	2025-09-01 07:53:20.60583	\N	03
853	2025-09-01	\N	\N	1172	\N	10000.00	\N	21	2025	\N	2025-09-01 07:53:20.606379	\N	04
853	2025-09-01	\N	\N	1173	\N	10000.00	\N	21	2025	\N	2025-09-01 07:53:20.606934	\N	05
853	2025-09-01	\N	\N	1174	\N	10000.00	\N	21	2025	\N	2025-09-01 07:53:20.607461	\N	06
853	2025-09-01	\N	\N	1175	\N	10000.00	\N	21	2025	\N	2025-09-01 07:53:20.608253	\N	07
849	2025-09-01	\N	\N	1176	\N	10000.00	\N	21	2025	\N	2025-09-01 07:54:08.638902	\N	08
849	2025-09-01	\N	\N	1177	\N	10000.00	\N	21	2025	\N	2025-09-01 07:54:08.640273	\N	09
849	2025-09-01	\N	\N	1178	\N	10000.00	\N	21	2025	\N	2025-09-01 07:54:08.641349	\N	10
849	2025-09-01	\N	\N	1179	\N	10000.00	\N	21	2025	\N	2025-09-01 07:54:08.642755	\N	11
849	2025-09-01	\N	\N	1180	\N	10000.00	\N	21	2025	\N	2025-09-01 07:54:08.64354	\N	12
849	2025-09-01	\N	\N	1181	\N	10000.00	\N	21	2025	\N	2025-09-01 07:54:08.644172	\N	01
849	2025-09-01	\N	\N	1182	\N	10000.00	\N	21	2025	\N	2025-09-01 07:54:08.644871	\N	02
849	2025-09-01	\N	\N	1183	\N	10000.00	\N	21	2025	\N	2025-09-01 07:54:08.645496	\N	03
849	2025-09-01	\N	\N	1184	\N	10000.00	\N	21	2025	\N	2025-09-01 07:54:08.646125	\N	04
849	2025-09-01	\N	\N	1185	\N	10000.00	\N	21	2025	\N	2025-09-01 07:54:08.646762	\N	05
849	2025-09-01	\N	\N	1186	\N	10000.00	\N	21	2025	\N	2025-09-01 07:54:08.647427	\N	06
849	2025-09-01	\N	\N	1187	\N	10000.00	\N	21	2025	\N	2025-09-01 07:54:08.648077	\N	07
850	2025-09-01	\N	\N	1188	\N	10000.00	\N	21	2025	\N	2025-09-01 07:54:25.560792	\N	08
850	2025-09-01	\N	\N	1189	\N	10000.00	\N	21	2025	\N	2025-09-01 07:54:25.562688	\N	09
850	2025-09-01	\N	\N	1190	\N	10000.00	\N	21	2025	\N	2025-09-01 07:54:25.563472	\N	10
850	2025-09-01	\N	\N	1191	\N	10000.00	\N	21	2025	\N	2025-09-01 07:54:25.564271	\N	11
850	2025-09-01	\N	\N	1192	\N	10000.00	\N	21	2025	\N	2025-09-01 07:54:25.565061	\N	12
850	2025-09-01	\N	\N	1193	\N	10000.00	\N	21	2025	\N	2025-09-01 07:54:25.565842	\N	01
850	2025-09-01	\N	\N	1194	\N	10000.00	\N	21	2025	\N	2025-09-01 07:54:25.566697	\N	02
850	2025-09-01	\N	\N	1195	\N	10000.00	\N	21	2025	\N	2025-09-01 07:54:25.567397	\N	03
850	2025-09-01	\N	\N	1196	\N	10000.00	\N	21	2025	\N	2025-09-01 07:54:25.568098	\N	04
850	2025-09-01	\N	\N	1197	\N	10000.00	\N	21	2025	\N	2025-09-01 07:54:25.569165	\N	05
850	2025-09-01	\N	\N	1198	\N	10000.00	\N	21	2025	\N	2025-09-01 07:54:25.570093	\N	06
850	2025-09-01	\N	\N	1199	\N	10000.00	\N	21	2025	\N	2025-09-01 07:54:25.570713	\N	07
44444447	2025-09-01	\N	\N	1200	\N	10000.00	\N	21	2025	\N	2025-09-01 07:54:33.361746	\N	08
44444447	2025-09-01	\N	\N	1201	\N	10000.00	\N	21	2025	\N	2025-09-01 07:54:33.363069	\N	09
44444447	2025-09-01	\N	\N	1202	\N	10000.00	\N	21	2025	\N	2025-09-01 07:54:33.363796	\N	10
44444447	2025-09-01	\N	\N	1203	\N	10000.00	\N	21	2025	\N	2025-09-01 07:54:33.364662	\N	11
44444447	2025-09-01	\N	\N	1204	\N	10000.00	\N	21	2025	\N	2025-09-01 07:54:33.365558	\N	12
44444447	2025-09-01	\N	\N	1205	\N	10000.00	\N	21	2025	\N	2025-09-01 07:54:33.366227	\N	01
44444447	2025-09-01	\N	\N	1206	\N	10000.00	\N	21	2025	\N	2025-09-01 07:54:33.36688	\N	02
44444447	2025-09-01	\N	\N	1207	\N	10000.00	\N	21	2025	\N	2025-09-01 07:54:33.367425	\N	03
44444447	2025-09-01	\N	\N	1208	\N	10000.00	\N	21	2025	\N	2025-09-01 07:54:33.367941	\N	04
44444447	2025-09-01	\N	\N	1209	\N	10000.00	\N	21	2025	\N	2025-09-01 07:54:33.368718	\N	05
44444447	2025-09-01	\N	\N	1210	\N	10000.00	\N	21	2025	\N	2025-09-01 07:54:33.369341	\N	06
44444447	2025-09-01	\N	\N	1211	\N	10000.00	\N	21	2025	\N	2025-09-01 07:54:33.370549	\N	07
848	2025-09-01	\N	\N	1212	\N	10000.00	\N	21	2025	\N	2025-09-01 07:54:40.633298	\N	08
848	2025-09-01	\N	\N	1213	\N	10000.00	\N	21	2025	\N	2025-09-01 07:54:40.634484	\N	09
848	2025-09-01	\N	\N	1214	\N	10000.00	\N	21	2025	\N	2025-09-01 07:54:40.635098	\N	10
848	2025-09-01	\N	\N	1215	\N	10000.00	\N	21	2025	\N	2025-09-01 07:54:40.635627	\N	11
848	2025-09-01	\N	\N	1216	\N	10000.00	\N	21	2025	\N	2025-09-01 07:54:40.636277	\N	12
848	2025-09-01	\N	\N	1217	\N	10000.00	\N	21	2025	\N	2025-09-01 07:54:40.636997	\N	01
848	2025-09-01	\N	\N	1218	\N	10000.00	\N	21	2025	\N	2025-09-01 07:54:40.637931	\N	02
848	2025-09-01	\N	\N	1219	\N	10000.00	\N	21	2025	\N	2025-09-01 07:54:40.638585	\N	03
848	2025-09-01	\N	\N	1220	\N	10000.00	\N	21	2025	\N	2025-09-01 07:54:40.639159	\N	04
848	2025-09-01	\N	\N	1221	\N	10000.00	\N	21	2025	\N	2025-09-01 07:54:40.640283	\N	05
848	2025-09-01	\N	\N	1222	\N	10000.00	\N	21	2025	\N	2025-09-01 07:54:40.641013	\N	06
848	2025-09-01	\N	\N	1223	\N	10000.00	\N	21	2025	\N	2025-09-01 07:54:40.641715	\N	07
852	2025-09-01	\N	\N	1224	\N	10000.00	\N	21	2025	\N	2025-09-01 07:55:11.467708	\N	08
852	2025-09-01	\N	\N	1225	\N	10000.00	\N	21	2025	\N	2025-09-01 07:55:11.468822	\N	09
852	2025-09-01	\N	\N	1226	\N	10000.00	\N	21	2025	\N	2025-09-01 07:55:11.469445	\N	10
852	2025-09-01	\N	\N	1227	\N	10000.00	\N	21	2025	\N	2025-09-01 07:55:11.4713	\N	11
852	2025-09-01	\N	\N	1228	\N	10000.00	\N	21	2025	\N	2025-09-01 07:55:11.472087	\N	12
852	2025-09-01	\N	\N	1229	\N	10000.00	\N	21	2025	\N	2025-09-01 07:55:11.472787	\N	01
852	2025-09-01	\N	\N	1230	\N	10000.00	\N	21	2025	\N	2025-09-01 07:55:11.473566	\N	02
852	2025-09-01	\N	\N	1231	\N	10000.00	\N	21	2025	\N	2025-09-01 07:55:11.474255	\N	03
852	2025-09-01	\N	\N	1232	\N	10000.00	\N	21	2025	\N	2025-09-01 07:55:11.474935	\N	04
852	2025-09-01	\N	\N	1233	\N	10000.00	\N	21	2025	\N	2025-09-01 07:55:11.475529	\N	05
852	2025-09-01	\N	\N	1234	\N	10000.00	\N	21	2025	\N	2025-09-01 07:55:11.476239	\N	06
852	2025-09-01	\N	\N	1235	\N	10000.00	\N	21	2025	\N	2025-09-01 07:55:11.476893	\N	07
44444454	2025-09-11	\N	\N	1260	\N	150000.00	\N	21	2025	\N	2025-09-11 15:43:41.131137	\N	08
44444454	2025-09-11	\N	\N	1261	\N	150000.00	\N	21	2025	\N	2025-09-11 15:43:41.134899	\N	09
44444454	2025-09-11	\N	\N	1262	\N	150000.00	\N	21	2025	\N	2025-09-11 15:43:41.136032	\N	10
44444454	2025-09-11	\N	\N	1263	\N	150000.00	\N	21	2025	\N	2025-09-11 15:43:41.137009	\N	11
44444454	2025-09-11	\N	\N	1264	\N	150000.00	\N	21	2025	\N	2025-09-11 15:43:41.137755	\N	12
44444454	2025-09-11	\N	\N	1265	\N	150000.00	\N	21	2025	\N	2025-09-11 15:43:41.138536	\N	01
44444454	2025-09-11	\N	\N	1266	\N	150000.00	\N	21	2025	\N	2025-09-11 15:43:41.139233	\N	02
44444454	2025-09-11	\N	\N	1267	\N	150000.00	\N	21	2025	\N	2025-09-11 15:43:41.140354	\N	03
44444454	2025-09-11	\N	\N	1268	\N	150000.00	\N	21	2025	\N	2025-09-11 15:43:41.141093	\N	04
44444454	2025-09-11	\N	\N	1269	\N	150000.00	\N	21	2025	\N	2025-09-11 15:43:41.142023	\N	05
44444454	2025-09-11	\N	\N	1270	\N	150000.00	\N	21	2025	\N	2025-09-11 15:43:41.143016	\N	06
44444454	2025-09-11	\N	\N	1271	\N	150000.00	\N	21	2025	\N	2025-09-11 15:43:41.144024	\N	07
44444455	2025-09-11	\N	\N	1272	\N	150000.00	\N	21	2025	\N	2025-09-11 15:45:03.420839	\N	08
44444455	2025-09-11	\N	\N	1273	\N	150000.00	\N	21	2025	\N	2025-09-11 15:45:03.423307	\N	09
44444455	2025-09-11	\N	\N	1274	\N	150000.00	\N	21	2025	\N	2025-09-11 15:45:03.424568	\N	10
44444455	2025-09-11	\N	\N	1275	\N	150000.00	\N	21	2025	\N	2025-09-11 15:45:03.4255	\N	11
44444455	2025-09-11	\N	\N	1276	\N	150000.00	\N	21	2025	\N	2025-09-11 15:45:03.426787	\N	12
44444455	2025-09-11	\N	\N	1277	\N	150000.00	\N	21	2025	\N	2025-09-11 15:45:03.427815	\N	01
44444455	2025-09-11	\N	\N	1278	\N	150000.00	\N	21	2025	\N	2025-09-11 15:45:03.428704	\N	02
44444455	2025-09-11	\N	\N	1279	\N	150000.00	\N	21	2025	\N	2025-09-11 15:45:03.429665	\N	03
44444455	2025-09-11	\N	\N	1280	\N	150000.00	\N	21	2025	\N	2025-09-11 15:45:03.431181	\N	04
44444455	2025-09-11	\N	\N	1281	\N	150000.00	\N	21	2025	\N	2025-09-11 15:45:03.432888	\N	05
44444455	2025-09-11	\N	\N	1282	\N	150000.00	\N	21	2025	\N	2025-09-11 15:45:03.435403	\N	06
44444455	2025-09-11	\N	\N	1283	\N	150000.00	\N	21	2025	\N	2025-09-11 15:45:03.436586	\N	07
44444462	2025-09-12	\N	\N	1284	\N	60000.00	\N	21	2025	\N	2025-09-12 12:18:35.425075	\N	08
44444462	2025-09-12	\N	\N	1285	\N	60000.00	\N	21	2025	\N	2025-09-12 12:18:35.427713	\N	09
44444462	2025-09-12	\N	\N	1286	\N	60000.00	\N	21	2025	\N	2025-09-12 12:18:35.428422	\N	10
44444462	2025-09-12	\N	\N	1287	\N	60000.00	\N	21	2025	\N	2025-09-12 12:18:35.429345	\N	11
44444462	2025-09-12	\N	\N	1288	\N	60000.00	\N	21	2025	\N	2025-09-12 12:18:35.430126	\N	12
44444462	2025-09-12	\N	\N	1289	\N	60000.00	\N	21	2025	\N	2025-09-12 12:18:35.431006	\N	01
44444462	2025-09-12	\N	\N	1290	\N	60000.00	\N	21	2025	\N	2025-09-12 12:18:35.431783	\N	02
44444462	2025-09-12	\N	\N	1291	\N	60000.00	\N	21	2025	\N	2025-09-12 12:18:35.432415	\N	03
44444462	2025-09-12	\N	\N	1292	\N	60000.00	\N	21	2025	\N	2025-09-12 12:18:35.433201	\N	04
44444462	2025-09-12	\N	\N	1293	\N	60000.00	\N	21	2025	\N	2025-09-12 12:18:35.434154	\N	05
44444462	2025-09-12	\N	\N	1294	\N	60000.00	\N	21	2025	\N	2025-09-12 12:18:35.435025	\N	06
44444462	2025-09-12	\N	\N	1295	\N	60000.00	\N	21	2025	\N	2025-09-12 12:18:35.435616	\N	07
44444463	2025-09-12	\N	\N	1296	\N	10000.00	\N	21	2025	\N	2025-09-12 12:35:10.322724	\N	08
44444463	2025-09-12	\N	\N	1297	\N	10000.00	\N	21	2025	\N	2025-09-12 12:35:10.325706	\N	09
44444463	2025-09-12	\N	\N	1298	\N	10000.00	\N	21	2025	\N	2025-09-12 12:35:10.326877	\N	10
44444463	2025-09-12	\N	\N	1299	\N	10000.00	\N	21	2025	\N	2025-09-12 12:35:10.327893	\N	11
44444463	2025-09-12	\N	\N	1300	\N	10000.00	\N	21	2025	\N	2025-09-12 12:35:10.329416	\N	12
44444463	2025-09-12	\N	\N	1301	\N	10000.00	\N	21	2025	\N	2025-09-12 12:35:10.330462	\N	01
44444463	2025-09-12	\N	\N	1302	\N	10000.00	\N	21	2025	\N	2025-09-12 12:35:10.331975	\N	02
44444463	2025-09-12	\N	\N	1303	\N	10000.00	\N	21	2025	\N	2025-09-12 12:35:10.333047	\N	03
44444463	2025-09-12	\N	\N	1304	\N	10000.00	\N	21	2025	\N	2025-09-12 12:35:10.333873	\N	04
44444463	2025-09-12	\N	\N	1305	\N	10000.00	\N	21	2025	\N	2025-09-12 12:35:10.334745	\N	05
44444463	2025-09-12	\N	\N	1306	\N	10000.00	\N	21	2025	\N	2025-09-12 12:35:10.335628	\N	06
44444463	2025-09-12	\N	\N	1307	\N	10000.00	\N	21	2025	\N	2025-09-12 12:35:10.336367	\N	07
124	2025-09-12	\N	\N	1308	\N	10000.00	\N	21	2025	\N	2025-09-12 12:40:32.153565	\N	08
124	2025-09-12	\N	\N	1309	\N	10000.00	\N	21	2025	\N	2025-09-12 12:40:32.155467	\N	09
124	2025-09-12	\N	\N	1310	\N	10000.00	\N	21	2025	\N	2025-09-12 12:40:32.156218	\N	10
124	2025-09-12	\N	\N	1311	\N	10000.00	\N	21	2025	\N	2025-09-12 12:40:32.15685	\N	11
124	2025-09-12	\N	\N	1312	\N	10000.00	\N	21	2025	\N	2025-09-12 12:40:32.157564	\N	12
124	2025-09-12	\N	\N	1313	\N	10000.00	\N	21	2025	\N	2025-09-12 12:40:32.158618	\N	01
124	2025-09-12	\N	\N	1314	\N	10000.00	\N	21	2025	\N	2025-09-12 12:40:32.15956	\N	02
124	2025-09-12	\N	\N	1315	\N	10000.00	\N	21	2025	\N	2025-09-12 12:40:32.160193	\N	03
124	2025-09-12	\N	\N	1316	\N	10000.00	\N	21	2025	\N	2025-09-12 12:40:32.160818	\N	04
124	2025-09-12	\N	\N	1317	\N	10000.00	\N	21	2025	\N	2025-09-12 12:40:32.161451	\N	05
124	2025-09-12	\N	\N	1318	\N	10000.00	\N	21	2025	\N	2025-09-12 12:40:32.162284	\N	06
124	2025-09-12	\N	\N	1319	\N	10000.00	\N	21	2025	\N	2025-09-12 12:40:32.163138	\N	07
44444464	2025-09-12	\N	\N	1320	\N	10000.00	\N	21	2025	\N	2025-09-12 12:45:21.069044	\N	08
44444464	2025-09-12	\N	\N	1321	\N	10000.00	\N	21	2025	\N	2025-09-12 12:45:21.070929	\N	09
44444464	2025-09-12	\N	\N	1322	\N	10000.00	\N	21	2025	\N	2025-09-12 12:45:21.071735	\N	10
44444464	2025-09-12	\N	\N	1323	\N	10000.00	\N	21	2025	\N	2025-09-12 12:45:21.072445	\N	11
44444464	2025-09-12	\N	\N	1324	\N	10000.00	\N	21	2025	\N	2025-09-12 12:45:21.07325	\N	12
44444464	2025-09-12	\N	\N	1325	\N	10000.00	\N	21	2025	\N	2025-09-12 12:45:21.074025	\N	01
44444464	2025-09-12	\N	\N	1326	\N	10000.00	\N	21	2025	\N	2025-09-12 12:45:21.075298	\N	02
44444464	2025-09-12	\N	\N	1327	\N	10000.00	\N	21	2025	\N	2025-09-12 12:45:21.076681	\N	03
44444464	2025-09-12	\N	\N	1328	\N	10000.00	\N	21	2025	\N	2025-09-12 12:45:21.0776	\N	04
44444464	2025-09-12	\N	\N	1329	\N	10000.00	\N	21	2025	\N	2025-09-12 12:45:21.078314	\N	05
44444464	2025-09-12	\N	\N	1330	\N	10000.00	\N	21	2025	\N	2025-09-12 12:45:21.078987	\N	06
44444464	2025-09-12	\N	\N	1331	\N	10000.00	\N	21	2025	\N	2025-09-12 12:45:21.079869	\N	07
\.


--
-- Data for Name: billing_payments; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.billing_payments (id, syear, school_id, student_id, amount, payment_date, comments, refunded_payment_id, lunch_payment, file_attached, created_at, updated_at, month, intitule_caissier, imprimer) FROM stdin;
582	2025	21	5	9000.00	2025-08-25	\N	\N	\N	\N	2025-08-25 15:32:26.666611	\N	09	Super Admin	0
584	2025	21	44444455	100000.00	2025-09-11	\N	\N	\N	\N	2025-09-11 11:04:49.474545	\N	09	Super Admin	0
588	2025	21	44444463	10000.00	2025-09-12	\N	\N	\N	\N	2025-09-12 12:35:10.343252	\N	09	Super Admin	0
587	2025	21	44444462	20000.00	2025-09-12	INSUFFISANT	\N	\N	\N	2025-09-12 12:30:55.97464	2025-09-12 12:38:05.597028	10	Super Admin	0
589	2025	21	44444463	10000.00	2025-09-12	Payé	\N	\N	\N	2025-09-12 12:38:20.791532	\N	10	Super Admin	0
590	2025	21	124	8000.00	2025-09-12	Cas d''urgence hospitalisation	\N	\N	\N	2025-09-12 12:44:26.43734	\N	09	Super Admin	0
585	2025	21	44444462	40000.00	2025-09-12	AVANCE SEPTEMBRE	\N	\N	\N	2025-09-12 12:27:31.61468	2025-09-12 12:50:56.295551	09	Super Admin	0
586	2025	21	44444462	20000.00	2025-09-12	RESTE FRAIS SEPTEMBRE	\N	\N	\N	2025-09-12 12:28:48.677878	2025-09-12 12:50:56.299909	09	Super Admin	0
\.


--
-- Data for Name: calendar_events; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.calendar_events (id, syear, school_id, school_date, title, description, created_at, updated_at) FROM stdin;
5	2025	21	2025-08-12	Conférence Les Mathématiques appliquées à L'IA	\N	2025-08-08 13:16:21.575175	\N
6	2025	21	2025-08-13	Conférence Les Mathématiques appliquées à L'IA	\N	2025-08-08 13:16:21.584551	\N
7	2025	21	2025-08-14	Conférence Les Mathématiques appliquées à L'IA	\N	2025-08-08 13:16:21.586293	\N
8	2025	21	2025-08-15	Conférence Les Mathématiques appliquées à L'IA	\N	2025-08-08 13:16:21.587968	\N
\.


--
-- Data for Name: config; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.config (school_id, title, config_value, created_at, updated_at) FROM stdin;
0	VERSION	11.0.2	2023-08-01 22:43:31.104393	\N
0	DISPLAY_NAME	CONCAT(FIRST_NAME,coalesce(NULLIF(CONCAT(' ',MIDDLE_NAME,' '),'  '),' '),LAST_NAME)	2023-08-01 22:43:31.104393	\N
1	DISPLAY_NAME	CONCAT(FIRST_NAME,coalesce(NULLIF(CONCAT(' ',MIDDLE_NAME,' '),'  '),' '),LAST_NAME)	2023-08-01 22:43:31.104393	\N
0	LIMIT_EXISTING_CONTACTS_ADDRESSES	\N	2023-08-01 22:43:31.104393	\N
0	FAILED_LOGIN_LIMIT	30	2023-08-01 22:43:31.104393	\N
0	FORCE_PASSWORD_CHANGE_ON_FIRST_LOGIN	\N	2023-08-01 22:43:31.104393	\N
1	SCHOOL_SYEAR_OVER_2_YEARS	Y	2023-08-01 22:43:31.104393	\N
1	ATTENDANCE_FULL_DAY_MINUTES	300	2023-08-01 22:43:31.104393	\N
1	STUDENTS_USE_MAILING	\N	2023-08-01 22:43:31.104393	\N
0	REGISTRATION_FORM	a:4:{s:6:"parent";a:2:{i:0;a:6:{s:8:"relation";s:6:"Elève";s:7:"custody";s:0:"";s:9:"emergency";s:0:"";s:13:"info_required";s:0:"";s:4:"info";s:0:"";s:6:"fields";s:0:"";}i:1;a:6:{s:8:"relation";s:6:"Parent";s:7:"custody";s:0:"";s:9:"emergency";s:0:"";s:7:"address";s:0:"";s:4:"info";s:0:"";s:6:"fields";s:0:"";}}s:7:"address";a:1:{s:6:"fields";s:0:"";}s:7:"contact";a:0:{}s:7:"student";a:1:{s:6:"fields";s:5:"||1||";}}	2023-08-02 08:50:43.345399	2023-10-10 18:23:15.131414
1	DECIMAL_SEPARATOR	,	2023-08-01 22:43:31.104393	2023-08-01 22:43:35.376882
1	THOUSANDS_SEPARATOR	&nbsp;	2023-08-01 22:43:31.104393	2023-08-01 22:43:35.376882
0	LOGIN	Yes	2023-08-01 22:43:31.104393	2023-08-01 22:45:49.065328
1	CURRENCY	FCFA	2023-08-01 22:43:31.104393	2023-08-01 22:54:23.401499
0	GRADEBOOK_CONFIG_ADMIN_OVERRIDE	Y	2023-08-01 22:43:31.104393	2023-08-25 12:12:30.591676
0	THEME_FORCE	Y	2023-08-01 22:43:31.104393	2023-08-01 23:04:27.357312
0	CREATE_STUDENT_ACCOUNT_DEFAULT_SCHOOL	1	2023-08-01 22:43:31.104393	2023-08-01 23:04:27.357829
0	STUDENTS_EMAIL_FIELD	USERNAME	2023-08-01 22:43:31.104393	2023-08-01 23:04:27.358351
1	COURSE_WIDGET_METHOD	\N	2023-08-01 22:54:23.406472	2023-08-10 04:18:32.847287
0	PASSWORD_STRENGTH	3	2023-08-01 22:43:31.104393	2023-08-10 04:22:00.669052
0	REMOVE_ACCESS_USERNAME_PREFIX_ADD	Djessy	2023-08-01 22:43:31.104393	2023-08-10 22:31:24.926041
0	NAME	EDUVERSE	2023-08-01 22:43:31.104393	2024-11-04 14:57:17.747747
0	TITLE	Logiciel de gestion scolaire IZAR|fr_FR.utf8:Logiciel de gestion scolaire EDUVERSE|en_US.utf8:Logiciel de gestion scolaire EDUVERSE	2023-08-01 22:43:31.104393	2024-11-07 17:04:03.303535
0	CREATE_USER_ACCOUNT	\N	2023-08-01 22:43:31.104393	2024-11-07 17:04:43.046148
0	CREATE_STUDENT_ACCOUNT	\N	2023-08-01 22:43:31.104393	2024-11-07 17:05:43.907609
1	CLASS_RANK_CALCULATE_MPS	\N	2023-08-01 22:43:31.104393	2023-09-16 18:40:22.583321
0	CREATE_STUDENT_ACCOUNT_AUTOMATIC_ACTIVATION	Y	2023-08-01 22:43:31.104393	2024-08-06 12:24:56.685182
16	DISPLAY_NAME	CONCAT(FIRST_NAME,coalesce(NULLIF(CONCAT(' ',MIDDLE_NAME,' '),'  '),' '),LAST_NAME)	2024-12-16 13:41:03.887674	\N
16	SCHOOL_SYEAR_OVER_2_YEARS	Y	2024-12-16 13:41:03.887674	\N
16	ATTENDANCE_FULL_DAY_MINUTES	300	2024-12-16 13:41:03.887674	\N
16	STUDENTS_USE_MAILING	\N	2024-12-16 13:41:03.887674	\N
16	DECIMAL_SEPARATOR	,	2024-12-16 13:41:03.887674	\N
16	THOUSANDS_SEPARATOR	&nbsp;	2024-12-16 13:41:03.887674	\N
16	CURRENCY	FCFA	2024-12-16 13:41:03.887674	\N
16	COURSE_WIDGET_METHOD	\N	2024-12-16 13:41:03.887674	\N
16	CLASS_RANK_CALCULATE_MPS	\N	2024-12-16 13:41:03.887674	\N
17	DISPLAY_NAME	CONCAT(FIRST_NAME,coalesce(NULLIF(CONCAT(' ',MIDDLE_NAME,' '),'  '),' '),LAST_NAME)	2025-01-23 14:25:08.537077	\N
17	SCHOOL_SYEAR_OVER_2_YEARS	Y	2025-01-23 14:25:08.537077	\N
17	ATTENDANCE_FULL_DAY_MINUTES	300	2025-01-23 14:25:08.537077	\N
17	STUDENTS_USE_MAILING	\N	2025-01-23 14:25:08.537077	\N
17	DECIMAL_SEPARATOR	,	2025-01-23 14:25:08.537077	\N
17	THOUSANDS_SEPARATOR	&nbsp;	2025-01-23 14:25:08.537077	\N
17	CURRENCY	FCFA	2025-01-23 14:25:08.537077	\N
17	COURSE_WIDGET_METHOD	\N	2025-01-23 14:25:08.537077	\N
17	CLASS_RANK_CALCULATE_MPS	\N	2025-01-23 14:25:08.537077	\N
18	DISPLAY_NAME	CONCAT(FIRST_NAME,coalesce(NULLIF(CONCAT(' ',MIDDLE_NAME,' '),'  '),' '),LAST_NAME)	2025-01-23 16:47:37.946515	\N
18	SCHOOL_SYEAR_OVER_2_YEARS	Y	2025-01-23 16:47:37.946515	\N
18	ATTENDANCE_FULL_DAY_MINUTES	300	2025-01-23 16:47:37.946515	\N
18	STUDENTS_USE_MAILING	\N	2025-01-23 16:47:37.946515	\N
18	DECIMAL_SEPARATOR	,	2025-01-23 16:47:37.946515	\N
18	THOUSANDS_SEPARATOR	&nbsp;	2025-01-23 16:47:37.946515	\N
18	CURRENCY	FCFA	2025-01-23 16:47:37.946515	\N
18	COURSE_WIDGET_METHOD	\N	2025-01-23 16:47:37.946515	\N
18	CLASS_RANK_CALCULATE_MPS	\N	2025-01-23 16:47:37.946515	\N
0	PLUGINS	a:1:{s:6:"Moodle";b:1;}	2023-08-01 22:43:31.104393	2025-01-27 14:47:50.00915
19	DISPLAY_NAME	CONCAT(FIRST_NAME,coalesce(NULLIF(CONCAT(' ',MIDDLE_NAME,' '),'  '),' '),LAST_NAME)	2025-02-27 14:03:05.000374	\N
19	SCHOOL_SYEAR_OVER_2_YEARS	Y	2025-02-27 14:03:05.000374	\N
19	ATTENDANCE_FULL_DAY_MINUTES	300	2025-02-27 14:03:05.000374	\N
19	STUDENTS_USE_MAILING	\N	2025-02-27 14:03:05.000374	\N
19	DECIMAL_SEPARATOR	,	2025-02-27 14:03:05.000374	\N
19	THOUSANDS_SEPARATOR	&nbsp;	2025-02-27 14:03:05.000374	\N
19	CURRENCY	FCFA	2025-02-27 14:03:05.000374	\N
19	COURSE_WIDGET_METHOD	\N	2025-02-27 14:03:05.000374	\N
19	CLASS_RANK_CALCULATE_MPS	\N	2025-02-27 14:03:05.000374	\N
20	DISPLAY_NAME	CONCAT(FIRST_NAME,coalesce(NULLIF(CONCAT(' ',MIDDLE_NAME,' '),'  '),' '),LAST_NAME)	2025-03-03 08:33:48.001663	\N
20	SCHOOL_SYEAR_OVER_2_YEARS	Y	2025-03-03 08:33:48.001663	\N
20	ATTENDANCE_FULL_DAY_MINUTES	300	2025-03-03 08:33:48.001663	\N
20	STUDENTS_USE_MAILING	\N	2025-03-03 08:33:48.001663	\N
20	DECIMAL_SEPARATOR	,	2025-03-03 08:33:48.001663	\N
20	THOUSANDS_SEPARATOR	&nbsp;	2025-03-03 08:33:48.001663	\N
20	CURRENCY	FCFA	2025-03-03 08:33:48.001663	\N
20	COURSE_WIDGET_METHOD	\N	2025-03-03 08:33:48.001663	\N
20	CLASS_RANK_CALCULATE_MPS	\N	2025-03-03 08:33:48.001663	\N
0	MODULES	a:20:{s:12:"School_Setup";b:1;s:8:"Students";b:1;s:5:"Users";b:1;s:10:"Scheduling";b:1;s:6:"Grades";b:0;s:10:"Attendance";b:1;s:11:"Eligibility";b:1;s:10:"Discipline";b:1;s:10:"Accounting";b:1;s:15:"Student_Billing";b:1;s:12:"Food_Service";b:1;s:9:"Resources";b:1;s:6:"Custom";b:1;s:9:"Wx_Custom";b:1;s:15:"Student_ID_Card";b:1;s:16:"GlobalSearchFull";b:0;s:22:"Students_Import-master";b:0;s:11:"Attendance_";b:1;s:15:"Students_Import";b:1;s:9:"Messaging";b:1;}	2023-08-01 22:43:31.104393	2025-09-09 11:07:19.567803
21	DECIMAL_SEPARATOR	.	2025-09-09 11:55:39.338968	\N
21	THOUSANDS_SEPARATOR	,	2025-09-09 11:55:39.337477	\N
21	COURSE_WIDGET_METHOD	\N	2025-09-09 11:55:39.341324	\N
21	CURRENCY	FCFA	2025-09-09 11:55:39.334035	2025-09-09 11:56:03.446109
21	TYPE_IMPRESSION	ticket_caisse	2025-09-09 11:55:39.340412	2025-09-11 13:38:49.525608
0	THEME	WPadmin	2023-08-01 22:43:31.104393	2025-09-24 22:29:26.829436
\.


--
-- Data for Name: course_period_school_periods; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.course_period_school_periods (course_period_school_periods_id, course_period_id, period_id, days, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: course_periods; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.course_periods (syear, school_id, course_period_id, course_id, title, short_name, mp, marking_period_id, teacher_id, secondary_teacher_id, room, total_seats, filled_seats, does_attendance, does_honor_roll, does_class_rank, gender_restriction, house_restriction, availability, parent_id, calendar_id, half_day, does_breakoff, rollover_id, grade_scale_id, credits, created_at, updated_at, echelle_notation, semester_type, frais_classe, total_mentant) FROM stdin;
2025	21	25	\N	6B	6ème B	\N	\N	4431	\N	\N	40	0	\N	\N	\N	\N	\N	\N	25	\N	\N	\N	\N	\N	\N	2025-09-05 15:16:11.5219	2025-09-05 15:16:11.52824	10	pair	150000.00	\N
2025	21	24	\N	6 eme A	6 eme A	\N	\N	4430	\N	\N	30	0	\N	\N	\N	\N	\N	\N	24	\N	\N	\N	\N	\N	\N	2025-08-13 23:30:58.506591	2025-08-25 15:23:36.47048	20	pair	10000.00	10000
\.


--
-- Data for Name: course_subjects; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.course_subjects (syear, school_id, subject_id, title, short_name, sort_order, rollover_id, created_at, updated_at) FROM stdin;
2024	16	12	Histoire Géographie	HG	\N	\N	2024-12-27 10:48:46.57393	\N
2024	16	13	Physique Chimie	PC	\N	\N	2024-12-27 10:51:05.850131	\N
2024	16	14	Science de la vie et la Terre	SVT	\N	\N	2024-12-27 10:52:04.05918	\N
2024	16	15	Education Physique et Sportive	EPS	\N	\N	2024-12-27 10:52:31.613557	\N
2024	16	34	Expression écrite	EXP E	\N	\N	2024-12-27 15:13:19.870748	\N
2024	16	35	Orthographe	ORTHO	\N	\N	2024-12-27 15:13:39.728354	2024-12-27 15:16:07.872492
2024	16	1	Sciences de la vie et de la terre	SVT	\N	\N	2024-12-26 11:30:46.954457	\N
2024	16	2	Francais 	FR	\N	\N	2024-12-27 10:06:49.836558	2025-01-07 11:46:12.43986
2024	16	4	Physique Chimie	PC	\N	\N	2024-12-27 10:10:44.709249	\N
2024	16	43	CALCUL RAPIDE	CAL R	\N	\N	2025-01-10 16:20:36.345002	\N
2024	16	44	QUESTIONS DE COURS	QDC	\N	\N	2025-01-10 16:21:14.639314	\N
2024	16	5	Histoire Géographie	HG	\N	\N	2024-12-27 10:13:30.295267	\N
2024	16	6	Mathématiques	MATH	\N	\N	2024-12-27 10:14:09.675573	\N
2024	16	7	Anglais	ANG	\N	\N	2024-12-27 10:14:44.796811	\N
2024	16	8	Education Physique et Sportive	EPS	\N	\N	2024-12-27 10:19:28.065833	\N
2024	16	36	Expression écrite	EXP E	\N	\N	2024-12-27 15:15:37.073692	\N
2024	16	37	Orthographe	ORTHO	\N	\N	2024-12-27 15:15:55.182041	\N
2024	16	23	Francais	FRAN	\N	\N	2024-12-27 11:00:02.748542	2024-12-27 13:39:45.927107
2024	16	24	Anglais	ANG	\N	\N	2024-12-27 11:00:47.070905	\N
2024	16	25	Mathématiques	MATH	\N	\N	2024-12-27 11:01:03.364322	\N
2024	16	26	Histoire Géographie	HG	\N	\N	2024-12-27 11:01:33.597356	\N
2024	16	27	Science de la vie et la Terre	SVT	\N	\N	2024-12-27 11:02:00.812068	\N
2024	16	28	Physique Chimie	PC	\N	\N	2024-12-27 11:02:21.969857	\N
2024	16	29	Education Physique et Sportive	EPS	\N	\N	2024-12-27 11:02:37.16815	\N
2024	16	30	Expression Ecrite	Exp E	\N	\N	2024-12-27 13:38:29.175913	\N
2024	16	31	Orthographe	ORTHO	\N	\N	2024-12-27 13:38:51.534107	2024-12-27 15:12:45.024362
2024	16	62	DESSIN	DESS	\N	\N	2025-01-13 12:26:17.038815	\N
2024	16	63	LECTURE	LECT	\N	\N	2025-01-13 12:26:33.883751	\N
2024	16	64	POESIE	POESI	\N	\N	2025-01-13 12:26:49.456479	\N
2024	16	45	DESSIN	DESS	\N	\N	2025-01-10 16:21:37.640848	\N
2024	16	16	Francais	FRAN	\N	\N	2024-12-27 10:54:43.940104	2024-12-27 15:12:09.200548
2024	16	17	Physique Chimie	PC	\N	\N	2024-12-27 10:55:05.634648	\N
2024	16	18	Anglais	ANG	\N	\N	2024-12-27 10:55:27.650794	\N
2024	16	19	Mathématiques	MATH	\N	\N	2024-12-27 10:55:38.296279	\N
2024	16	20	Histoire Géographie	HG	\N	\N	2024-12-27 10:56:04.169131	\N
2024	16	21	Education Physique et Sportive	EPS	\N	\N	2024-12-27 10:57:58.193493	\N
2024	16	22	Science de la vie et la Terre	SVT	\N	\N	2024-12-27 10:58:21.577913	\N
2024	16	32	Expression écrite	EXP E	\N	\N	2024-12-27 15:12:09.210133	\N
2024	16	61	ECRITURE	ECRI	\N	\N	2025-01-13 12:25:52.36548	\N
2024	16	33	Orthographe	ORTHO	\N	\N	2024-12-27 15:12:26.250424	2024-12-27 15:16:22.960133
2024	16	74	POESIE	POESI	\N	\N	2025-01-13 13:27:21.784391	\N
2024	16	46	LECTURE	LECT	\N	\N	2025-01-10 16:21:51.437611	\N
2024	16	47	POESIE	POESI	\N	\N	2025-01-10 16:22:09.150546	\N
2024	16	38	DICTEE	DIC	\N	\N	2025-01-10 16:17:55.377488	2025-01-10 16:18:57.082979
2024	16	39	QUESTION	QTS	\N	\N	2025-01-10 16:18:57.08559	\N
2024	16	94	EPS	Eps	\N	\N	2025-01-21 09:59:08.495454	\N
2024	16	9	Francais	FRAN	\N	\N	2024-12-27 10:44:53.595256	2024-12-27 15:14:19.628544
2024	16	10	Anglais	ANG	\N	\N	2024-12-27 10:47:48.78276	\N
2024	16	11	Mathématiques	MATH	\N	\N	2024-12-27 10:48:18.905183	\N
2024	16	54	CALCUL RAPIDE	CAL R	\N	\N	2025-01-13 11:38:35.730491	\N
2024	16	50	DESSIN	DESS	\N	\N	2025-01-13 11:36:45.236739	\N
2024	16	72	ECRITURE	ECRI	\N	\N	2025-01-13 13:26:50.726666	\N
2024	16	71	LECTURE	LECT	\N	\N	2025-01-13 13:26:34.292028	\N
2024	16	73	DESSIN	DESS	\N	\N	2025-01-13 13:27:06.942014	\N
2024	16	52	FRANCAIS	FRAN	\N	\N	2025-01-13 11:37:43.918974	\N
2024	16	40	FRANCAIS	FRAN	\N	\N	2025-01-10 16:19:18.035482	\N
2024	16	41	ECRITURE	ECRI	\N	\N	2025-01-10 16:19:36.710097	\N
2024	16	88	EDUCATION POUR LA PAIX	Ed.P	\N	\N	2025-01-21 09:55:33.186082	\N
2024	16	42	MATHEMATIQUES	MATH	\N	\N	2025-01-10 16:20:01.436201	\N
2024	16	81	ECRITURE	Ecrit	\N	\N	2025-01-21 09:39:51.131993	\N
2024	16	89	LANGAGE	Lang	\N	\N	2025-01-21 09:55:59.315388	\N
2024	16	90	NUMERISATION	Num	\N	\N	2025-01-21 09:56:28.975598	\N
2024	16	96	EDUCTION MORALE	Ed.M	\N	\N	2025-01-21 10:00:47.4699	\N
2024	16	86	POESIE	Poes	\N	\N	2025-01-21 09:44:09.925397	\N
2024	16	91	MESURE	Mesur	\N	\N	2025-01-21 09:57:05.206864	\N
2024	16	92	EDUCATION CIVIQUE	ED.c	\N	\N	2025-01-21 09:57:56.223024	\N
2024	16	85	LECTURE	Lect	\N	\N	2025-01-21 09:43:16.526421	\N
2024	16	51	LECTURE	LECT	\N	\N	2025-01-13 11:37:18.544573	\N
2024	16	57	ECRITURE	ECRI	\N	\N	2025-01-13 11:41:28.459718	\N
2024	16	49	POESIE	POESI	\N	\N	2025-01-13 11:36:25.091259	\N
2024	16	93	OPERATION	Opera	\N	\N	2025-01-21 09:58:37.068244	\N
2024	16	84	DESSIN	Dsin	\N	\N	2025-01-21 09:41:48.938186	\N
2024	16	114	POESIE	Poes	\N	\N	2025-02-13 11:25:51.856571	\N
2024	16	115	ECRITURE	Ecrit	\N	\N	2025-02-13 11:26:11.151597	\N
2024	16	107	EDUCATION POUR LA PAIX	Ed.P	\N	\N	2025-02-13 11:17:04.312547	\N
2024	16	108	LANGAGE	Lang	\N	\N	2025-02-13 11:17:29.909709	\N
2024	16	122	EPS	Eps	\N	\N	2025-02-13 11:33:10.569481	\N
2024	16	123	SCIENCE ET TECHNOLOGIE	St	\N	\N	2025-02-13 11:35:06.856342	\N
2024	16	109	LECTURE	Lect	\N	\N	2025-02-13 11:19:12.774956	\N
2024	16	137	MESURE	Mesur	\N	\N	2025-02-13 11:50:23.630678	\N
2024	16	147	EPS	Eps	\N	\N	2025-02-13 12:03:53.460795	\N
2024	16	127	REDACTION	Red	\N	\N	2025-02-13 11:43:08.289641	\N
2024	16	152	INFORMATIQUE	Infor	\N	\N	2025-02-13 12:11:01.572138	\N
2024	16	128	OPERATION	Opera	\N	\N	2025-02-13 11:43:30.05643	\N
2024	16	131	ECRITURE	Ecrit	\N	\N	2025-02-13 11:45:26.265523	\N
2024	16	154	EDUCATION MORALE	Ed.M	\N	\N	2025-02-13 12:17:29.765819	\N
2024	16	132	PROPORTIONNALITE	Propo	\N	\N	2025-02-13 11:46:00.853187	\N
2024	16	177	EDUCATION A LA VIE FAMILIALE	EVF	\N	\N	2025-02-13 12:33:47.982285	\N
2024	16	178	EDUCATION MUSICALE	Ed.mu	\N	\N	2025-02-13 12:34:36.760971	2025-02-19 09:18:24.106366
2024	16	133	EXPRESSION ORALE	Exp o	\N	\N	2025-02-13 11:47:18.479303	2025-02-13 11:51:08.531616
2024	17	100	KHISTOIRE GEOGRAPHIE	HG	\N	\N	2025-01-24 11:16:19.932697	2025-06-16 10:45:24.892536
2024	17	101	MATHEMATIQUES	MATH	\N	\N	2025-01-24 11:16:35.441854	\N
2024	16	148	DEVELOPPEMENT DURABLE	Dvd	\N	\N	2025-02-13 12:05:00.169369	\N
2024	16	129	EDUCATION MORALE	Ed M	\N	\N	2025-02-13 11:44:05.102659	\N
2024	16	149	ORTHOGRAPHE  GRAMMATICALE	Ort g	\N	\N	2025-02-13 12:07:11.146287	\N
2024	16	150	ACTIVITE D'OBSERVATION ET D'EVEIL	AOE	\N	\N	2025-02-13 12:08:46.811355	\N
2024	16	145	CONJUGAISON	Conj	\N	\N	2025-02-13 12:01:04.971195	\N
2024	16	146	EXERCICE DE DICTEE	Ex d	\N	\N	2025-02-13 12:02:06.092253	\N
2024	16	165	HISTOIRE	Hst	\N	\N	2025-02-13 12:26:06.564155	\N
2024	16	179	VOCABULAIRE	Voca	\N	\N	2025-02-13 12:35:22.544234	\N
2024	16	170	LECTURE commun	L c	\N	\N	2025-02-13 12:28:21.582384	\N
2024	16	167	INFORMATIQUE	Infor	\N	\N	2025-02-13 12:27:01.912462	\N
2024	16	116	OPERATION	Opera	\N	\N	2025-02-13 11:26:36.329714	\N
2024	16	117	COPIE	Copie	\N	\N	2025-02-13 11:27:09.562548	\N
2024	16	118	EDUCATION MORALE	Ed M	\N	\N	2025-02-13 11:29:37.223835	\N
2024	16	119	STE DES NOMBRES	Ste 	\N	\N	2025-02-13 11:30:50.888483	\N
2024	16	120	DENOMBREMENT	Denom	\N	\N	2025-02-13 11:31:27.551502	\N
2024	16	174	REMEDIATION	Remed	\N	\N	2025-02-13 12:31:10.820975	\N
2024	16	176	EXPRESSION ORAL	Exp o	\N	\N	2025-02-13 12:32:29.045409	\N
2024	16	141	SCIENCE ET TECHNOLOGIE	St	\N	\N	2025-02-13 11:55:49.208135	\N
2024	16	124	EDUCATION CIVIQUE	ED.c	\N	\N	2025-02-13 11:40:34.454388	\N
2024	16	121	GEOMETRIE	Géo	\N	\N	2025-02-13 11:32:04.255113	\N
2024	16	110	NUMERISATION	Num	\N	\N	2025-02-13 11:19:31.994698	\N
2024	16	111	DESSIN	Dsin	\N	\N	2025-02-13 11:20:41.488828	\N
2024	16	112	EDUCATION CIVIQUE	ED.c	\N	\N	2025-02-13 11:22:11.044168	\N
2024	16	113	MESURE	Mesur	\N	\N	2025-02-13 11:22:37.577928	\N
2024	16	151	ANGLAIS	Angl	\N	\N	2025-02-13 12:10:18.295942	\N
2024	16	125	LECTURE COMP	L c	\N	\N	2025-02-13 11:41:21.279649	\N
2024	16	126	NUMERISATION	Num	\N	\N	2025-02-13 11:41:53.964569	\N
2024	16	143	JEUX DE LECTURE	J L	\N	\N	2025-02-13 11:57:24.068678	\N
2024	16	144	VOCABULAIRE	Voca	\N	\N	2025-02-13 11:59:35.425316	\N
2024	16	134	GEOMETRIE	Géo	\N	\N	2025-02-13 11:48:08.835575	\N
2024	16	130	LECTURE COMMUN	L c	\N	\N	2025-02-13 11:44:50.605684	2025-02-13 12:03:13.917713
2024	16	163	EXPRESSION ECRITE	Ex e	\N	\N	2025-02-13 12:24:52.974494	\N
2024	16	139	ORTHOGRAPHE D'USAGE	Ort u	\N	\N	2025-02-13 11:53:16.467566	\N
2024	16	140	REMEDIATION	Remed	\N	\N	2025-02-13 11:55:10.797811	\N
2024	16	135	EDUCATION POUR LA PAIX	Ed.P	\N	\N	2025-02-13 11:48:51.818255	\N
2024	16	166	GEOMETRIE	Géo	\N	\N	2025-02-13 12:26:38.568752	\N
2024	16	175	EDUCATION POUR LA PAIX	Ed.P	\N	\N	2025-02-13 12:31:37.505446	\N
2024	16	160	SCIENCE ET TECHNOLOGIE	St	\N	\N	2025-02-13 12:22:16.091255	\N
2024	16	180	EPS	Eps	\N	\N	2025-02-13 12:35:45.492847	\N
2024	16	153	INITIATION A LA PRODUCTION	In p	\N	\N	2025-02-13 12:14:38.880143	2025-02-19 09:25:38.2914
2024	16	157	GRAMMAIRE	Gram	\N	\N	2025-02-13 12:21:01.095735	\N
2024	16	181	OPERATION	Opera	\N	\N	2025-02-13 12:36:36.594466	\N
2024	16	158	ORTHOGRAPHE D'USAGE	Ort u	\N	\N	2025-02-13 12:21:27.361128	\N
2024	16	138	GRAMMAIRE	Gram	\N	\N	2025-02-13 11:51:42.691096	\N
2024	16	142	DOSSIER	Doss	\N	\N	2025-02-13 11:56:33.800089	\N
2024	16	188	EXPRESSION ECRITE	Ex e	\N	\N	2025-02-13 12:43:41.565685	\N
2024	16	182	ANGLAIS	Angl	\N	\N	2025-02-13 12:37:23.262056	\N
2024	16	164	ORTHOGRAPHE  GRAMMATICALE	Ort g	\N	\N	2025-02-13 12:25:31.396214	\N
2024	16	183	EXERCICE DE DICTEE	Ex d	\N	\N	2025-02-13 12:37:49.564253	\N
2024	16	155	LECTURE COMP	L c	\N	\N	2025-02-13 12:20:20.358898	\N
2024	16	184	MESURE	Mesur	\N	\N	2025-02-13 12:38:37.893675	\N
2024	16	161	DOSSIER	Doss	\N	\N	2025-02-13 12:22:34.846088	\N
2024	16	162	EXPRESSION ECRITE	Ex e	\N	\N	2025-02-13 12:24:09.918551	\N
2024	16	159	NUMERISATION	Num	\N	\N	2025-02-13 12:21:48.723755	\N
2024	16	185	EDUCATION POUR LA SANTE	Ed s	\N	\N	2025-02-13 12:40:12.345261	\N
2024	16	171	CONJUGAISON	Conj	\N	\N	2025-02-13 12:29:00.129287	\N
2024	16	169	EDUCATION CIVIQUE	ED.c	\N	\N	2025-02-13 12:27:50.295813	\N
2024	16	168	JEUX DE LECTURE	J L	\N	\N	2025-02-13 12:27:24.452364	\N
2024	16	172	GEOGRAPHIE	Géo	\N	\N	2025-02-13 12:29:47.82531	\N
2024	16	173	PROPORTIONNALITE	Propo	\N	\N	2025-02-13 12:30:15.018072	\N
2024	16	136	EDUCATION MUSICALE	Ed M	\N	\N	2025-02-13 11:49:40.832174	\N
2024	16	186	EDUCATION CIVIQUE	ED.c	\N	\N	2025-02-13 12:42:23.97272	\N
2024	16	189	EXPRESSION ORAL	Exp o	\N	\N	2025-02-13 12:44:12.950005	\N
2024	16	156	DEVELOPPEMENT DURABLE	Dvd	\N	\N	2025-02-13 12:20:41.851171	\N
2024	16	187	LECTURE COMP	L c	\N	\N	2025-02-13 12:42:52.585478	\N
2024	16	218	EDUCATION POUR LA PAIX	Ed.P	\N	\N	2025-02-14 10:47:44.448719	\N
2024	16	217	SCIENCE ET TECHNOLOGIE	St	\N	\N	2025-02-14 10:32:29.554556	\N
2024	16	212	COPIE	Copie	\N	\N	2025-02-14 10:28:10.938968	\N
2024	16	213	STE DES NOMBRES	STE N	\N	\N	2025-02-14 10:29:42.251467	\N
2024	16	214	DENOMBREMENT	Denom	\N	\N	2025-02-14 10:30:19.329362	\N
2024	16	215	GEOMETRIE	Géom	\N	\N	2025-02-14 10:31:02.525941	\N
2024	16	207	MESURE	Mesur	\N	\N	2025-02-13 12:59:21.819579	\N
2024	16	204	ANGLAIS	Angl	\N	\N	2025-02-13 12:54:17.953411	\N
2024	16	247	INITIATION A LA PRODUCTION	I p	\N	\N	2025-03-10 10:45:02.490968	\N
2024	16	219	EDUCATION CIVIQUE	ED.c	\N	\N	2025-02-14 10:48:22.986455	\N
2024	16	220	LECTURE COMP	L c	\N	\N	2025-02-14 10:48:46.282275	\N
2024	16	221	EXPRESSION ORAL	Exp o	\N	\N	2025-02-14 10:49:15.049583	\N
2024	16	231	ANGLAIS	Angl	\N	\N	2025-02-14 10:53:55.711824	\N
2024	16	232	ART MUSICALE	Art M	\N	\N	2025-02-14 10:54:20.499277	\N
2024	16	233	PROPORTIONNALITE	Propo	\N	\N	2025-02-14 10:54:58.278197	\N
2024	16	234	SCIENCE ET TECHNOLOGIE	St	\N	\N	2025-02-14 10:55:40.589641	\N
2024	16	235	CONJUGAISON	Conj	\N	\N	2025-02-14 10:56:19.430295	\N
2024	16	236	INITIATION A LA PRODUCTION	I p	\N	\N	2025-02-14 10:57:00.16572	\N
2024	16	226	INFORMATIQUE	Infor	\N	\N	2025-02-14 10:51:44.797873	\N
2024	16	227	GEOMETRIE	Géom	\N	\N	2025-02-14 10:52:20.813068	\N
2024	16	239	EDUCATION A LA VIE FAMILIALE	EVF	\N	\N	2025-02-14 11:00:25.457472	\N
2024	16	201	CONJUGAISON	Conj	\N	\N	2025-02-13 12:52:47.864196	\N
2024	16	211	DEVELOPPEMENT DURABLE	Dvd	\N	\N	2025-02-13 13:06:39.821582	\N
2024	16	199	EDUCATION MORALE	Ed M	\N	\N	2025-02-13 12:51:47.584551	\N
2024	16	197	GEOGRAPHIE	Géo	\N	\N	2025-02-13 12:48:49.038879	\N
2024	16	196	GEOMETRIE	Géom	\N	\N	2025-02-13 12:48:15.565895	\N
2024	16	192	GRAMMAIRE	Gram	\N	\N	2025-02-13 12:46:49.933942	\N
2024	16	191	HISTOIRE	Hst	\N	\N	2025-02-13 12:46:34.634028	\N
2024	16	194	INFORMATIQUE	Infor	\N	\N	2025-02-13 12:47:21.415337	\N
2024	16	193	LECTURE commun	L com	\N	\N	2025-02-13 12:47:06.25889	2025-03-10 10:36:09.512151
2024	16	195	ORTHOGRAPHE  GRAMMATICALE	Ort g	\N	\N	2025-02-13 12:47:44.454514	\N
2024	16	198	ORTHOGRAPHE D'USAGE	Ort u	\N	\N	2025-02-13 12:50:53.391031	\N
2024	16	202	PROPORTIONNALITE	Propo	\N	\N	2025-02-13 12:53:26.561247	\N
2024	16	200	SCIENCE ET TECHNOLOGIE	St	\N	\N	2025-02-13 12:52:21.860036	\N
2024	16	240	EXPRESSION ECRITE	Ex e	\N	\N	2025-02-14 11:01:33.72965	\N
2024	16	228	GEOGRAPHIE	Géo	\N	\N	2025-02-14 10:52:47.21504	\N
2024	16	229	ORTHOGRAPHE  GRAMMATICALE	Ort g	\N	\N	2025-02-14 10:53:10.936557	\N
2024	16	208	ART MUSICALE	Art M	\N	\N	2025-02-13 13:00:17.532689	\N
2024	16	209	EDUCATION A LA VIE FAMILIALE	EVF	\N	\N	2025-02-13 13:01:28.146877	\N
2024	16	210	OPERATION	Opera	\N	\N	2025-02-13 13:04:53.73772	\N
2024	16	230	ORTHOGRAPHE D'USAGE	Ort u	\N	\N	2025-02-14 10:53:32.985398	\N
2024	16	222	VOCABULAIRE	Voca	\N	\N	2025-02-14 10:49:37.824214	\N
2024	16	223	NUMERISATION	Num	\N	\N	2025-02-14 10:50:00.990943	\N
2024	16	224	HISTOIRE	Hst	\N	\N	2025-02-14 10:50:24.483843	\N
2024	16	225	GRAMMAIRE	Gram	\N	\N	2025-02-14 10:51:01.841292	\N
2024	16	190	VOCABULAIRE	Voca	\N	\N	2025-02-13 12:44:28.980611	\N
2024	16	205	EDUCATION POUR LA PAIX	Ed.P	\N	\N	2025-02-13 12:56:56.521543	\N
2024	16	206	EDUCATION POUR LA SANTE	Ed s	\N	\N	2025-02-13 12:58:49.970309	\N
2024	16	237	EDUCATION MORALE	Ed M	\N	\N	2025-02-14 10:58:30.280404	\N
2024	16	238	DEVELOPPEMENT DURABLE	Dvd	\N	\N	2025-02-14 10:59:25.957391	\N
2024	16	241	EDUCATION POUR LA SANTE	Ed s	\N	\N	2025-02-14 11:02:29.706933	\N
2024	16	242	EDUCATION POUR LA SANTE	Ed s	\N	\N	2025-02-18 11:05:42.49397	\N
2024	16	243	RECREATION	Récré	\N	\N	2025-02-18 12:39:26.550936	\N
2024	17	244	ANGLAIS	ANG	\N	\N	2025-02-27 08:59:10.550328	\N
2024	17	245	MATHEMATIQUES	MATH	\N	\N	2025-02-27 08:59:23.294734	\N
2024	17	246	FRANCAIS	FRAN	\N	\N	2025-02-27 08:59:34.975083	\N
2024	17	250	stgrd	dyht	-2	\N	2025-06-16 15:27:19.376843	\N
2024	17	251	physique	pc	2	\N	2025-06-16 22:03:35.775057	\N
2024	17	253	logistique	lg	1	\N	2025-07-01 16:22:57.890914	\N
2024	17	254	Mathématique	MATH	1	\N	2025-07-07 11:50:17.838175	\N
2025	21	261	SCIENCES PHYSIQUES	PC	5	\N	2025-08-10 16:50:14.791062	2025-08-29 12:14:32.771687
2025	21	258	ORTHOGRAPHE	Ort	7	\N	2025-08-10 16:48:09.335588	2025-08-29 12:14:40.66452
2025	21	255	EXPRESSION ECRITE	EECR	8	\N	2025-08-06 12:51:02.213239	2025-08-29 12:14:48.05466
2025	21	260	ANGLAIS	Ang	9	\N	2025-08-10 16:49:12.104898	2025-08-29 12:14:51.264501
2025	21	256	HISTOIRE GEOGRAPHIE	HG	10	\N	2025-08-10 16:47:05.590311	2025-08-29 12:14:58.462024
2025	21	276	INFORMATIQUE	Inf	1	\N	2025-08-28 16:33:15.636851	2025-08-29 12:15:51.312779
2025	21	278	SCIENCE DE LA VIE ET DE LA TERRE	SVT	3	\N	2025-08-29 12:16:18.798085	\N
2025	21	279	EDUCATION PHYSIQUE ET SPORTIF	EPS	4	\N	2025-08-29 12:16:42.974723	\N
2025	21	280	SCIENCES PHYSIQUES	PC	5	\N	2025-08-29 12:17:06.185329	2025-08-29 12:17:11.843948
2025	21	281	ECMP	ECMP	6	\N	2025-08-29 12:17:37.546183	\N
2025	21	282	ORTHOGRAPHE	ORTH	7	\N	2025-08-29 12:17:53.688795	\N
2025	21	283	EXPRESSION ECRITE	EECR	8	\N	2025-08-29 12:18:23.960789	\N
2025	21	284	ANGLAIS	ANG	9	\N	2025-08-29 12:18:58.037827	\N
2025	21	285	HISTOIRE GEOGRAPHIE	HG	10	\N	2025-08-29 12:19:50.244118	\N
2025	21	286	ORTHOGRAPHE	ORTH	1	\N	2025-08-29 12:30:26.88708	2025-08-29 12:44:25.180123
2025	21	287	EXPRESSION ECRITE	EECR	2	\N	2025-08-29 12:44:25.183308	\N
2025	21	288	ANGLAIS	ANG	3	\N	2025-08-29 12:47:14.484673	\N
2025	21	257	ECMP	ECMP	6	\N	2025-08-10 16:47:34.50385	2025-08-28 14:37:27.586449
2025	21	289	HISTOIRE GEOGRAPHIE	HG	4	\N	2025-08-29 12:47:22.277557	\N
2025	21	267	MATHEMATIQUES	MATHS	2	\N	2025-08-28 15:03:03.967239	2025-08-28 15:03:19.020831
2025	21	268	SCIENCE DE LA VIE ET DE LA TERRE	SVT	3	\N	2025-08-28 15:03:19.024039	\N
2025	21	269	EDUCATION PHYSIQUE ET SPORTIF	EPS	4	\N	2025-08-28 15:03:47.0323	\N
2025	21	270	SCIENCES PHYSIQUES	PC	5	\N	2025-08-28 16:31:17.214848	\N
2025	21	271	ECMP	ECMP	6	\N	2025-08-28 16:31:34.241201	\N
2025	21	272	ORTHOGRAPHE	ORTH	7	\N	2025-08-28 16:31:52.226815	\N
2025	21	273	EXPRESSION ECRITE	EECR	8	\N	2025-08-28 16:32:02.108759	\N
2025	21	274	ANGLAIS	ANG	9	\N	2025-08-28 16:32:20.366683	\N
2025	21	275	HISTOIRE GEOGRAPHIE	HG	10	\N	2025-08-28 16:32:40.214855	\N
2025	21	266	INFORMATIQUE	INF	1	\N	2025-08-28 14:56:38.921729	2025-08-28 16:32:56.826694
2025	21	277	MATHEMATIQUES	MATHS	2	\N	2025-08-28 16:33:41.274822	\N
2025	21	264	INFORMATIQUE	INF	1	\N	2025-08-13 23:24:36.11697	2025-08-29 12:13:42.513952
2025	21	290	SCIENCE DE LA VIE ET DE LA TERRE	SVT	5	\N	2025-08-29 12:47:45.666381	\N
2025	21	263	MATHEMATIQUES	Maths	2	\N	2025-08-10 16:51:09.163561	2025-08-29 12:14:03.981251
2025	21	259	SCIENCE DE LA VIE ET DE LA TERRE	S.V.T	3	\N	2025-08-10 16:48:45.516038	2025-08-29 12:14:15.579052
2025	21	262	EDUCATION PHYSIQUE ET SPORTIVE	EPS	4	\N	2025-08-10 16:50:34.304568	2025-08-29 12:14:26.070929
2025	21	291	MATHEMATIQUES	MATHS	6	\N	2025-08-29 12:47:59.039194	\N
2025	21	292	SCIENCES PHYSIQUES	PC	7	\N	2025-08-29 12:48:28.743089	\N
2025	21	293	EDUCATION PHYSIQUE ET SPORTIF	EPS	8	\N	2025-08-29 12:49:01.779609	\N
\.


--
-- Data for Name: courses; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.courses (syear, course_id, subject_id, school_id, grade_level, title, short_name, rollover_id, credit_hours, description, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: custom_fields; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.custom_fields (id, type, title, sort_order, select_options, category_id, required, default_selection, created_at, updated_at) FROM stdin;
200000000	select	Gender|fr_FR.utf8:Sexe	0	Masculin\nFéminin	1	\N	\N	2023-08-01 22:43:31.104393	2023-08-01 22:43:35.376882
200000001	select	Ethnicity|fr_FR.utf8:Origine ethnique	1	Blanc, non hispanique\nNoir, non hispanique\nAsiatique\nHispanique\nAutre	1	\N	\N	2023-08-01 22:43:31.104393	2023-08-01 22:43:35.376882
200000002	text	Common Name|fr_FR.utf8:Surnom	2	\N	1	\N	\N	2023-08-01 22:43:31.104393	2023-08-01 22:43:35.376882
200000003	text	Identification Number|fr_FR.utf8:Numéro d'identification	3	\N	1	\N	\N	2023-08-01 22:43:31.104393	2023-08-01 22:43:35.376882
200000004	date	Birthdate|fr_FR.utf8:Date de naissance	4	\N	1	\N	\N	2023-08-01 22:43:31.104393	2023-08-01 22:43:35.376882
200000005	select	Language|fr_FR.utf8:Langue	5	Français\nAnglais	1	\N	\N	2023-08-01 22:43:31.104393	2023-08-01 22:43:35.376882
200000006	text	Physician|fr_FR.utf8:Médecin	6	\N	2	\N	\N	2023-08-01 22:43:31.104393	2023-08-01 22:43:35.376882
200000007	text	Physician Phone|fr_FR.utf8:Téléphone médecin	7	\N	2	\N	\N	2023-08-01 22:43:31.104393	2023-08-01 22:43:35.376882
200000008	text	Preferred Hospital|fr_FR.utf8:Hôpital préféré	8	\N	2	\N	\N	2023-08-01 22:43:31.104393	2023-08-01 22:43:35.376882
200000009	textarea	Comments|fr_FR.utf8:Commentaires	9	\N	2	\N	\N	2023-08-01 22:43:31.104393	2023-08-01 22:43:35.376882
200000010	radio	Has Doctor's Note|fr_FR.utf8:A un mot du docteur	10	\N	2	\N	\N	2023-08-01 22:43:31.104393	2023-08-01 22:43:35.376882
200000011	textarea	Doctor's Note Comments|fr_FR.utf8:Commentaires du mot du docteur	11	\N	2	\N	\N	2023-08-01 22:43:31.104393	2023-08-01 22:43:35.376882
\.


--
-- Data for Name: discipline_field_usage; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.discipline_field_usage (id, discipline_field_id, syear, school_id, title, select_options, sort_order, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: discipline_fields; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.discipline_fields (id, title, short_name, data_type, column_name, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: discipline_referrals; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.discipline_referrals (id, syear, student_id, school_id, staff_id, entry_date, referral_date, category_1, category_2, category_3, category_4, category_5, category_6, created_at, updated_at, category_7) FROM stdin;
\.


--
-- Data for Name: eligibility; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.eligibility (student_id, syear, school_date, period_id, eligibility_code, course_period_id, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: eligibility_activities; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.eligibility_activities (id, syear, school_id, title, start_date, end_date, comment, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: eligibility_completed; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.eligibility_completed (staff_id, school_date, period_id, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: food_service_accounts; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.food_service_accounts (account_id, balance, transaction_id, created_at, updated_at) FROM stdin;
1	0.00	0	2024-12-17 14:24:01.744593	\N
2	0.00	0	2024-12-17 14:31:01.635675	\N
3	0.00	0	2024-12-17 14:34:02.942145	\N
4	0.00	0	2024-12-17 15:56:28.144543	\N
5	0.00	0	2024-12-17 15:59:01.578384	\N
6	0.00	0	2024-12-17 16:03:28.869401	\N
7	0.00	0	2024-12-17 16:06:15.772946	\N
8	0.00	0	2024-12-18 09:21:37.346325	\N
9	0.00	0	2024-12-18 09:24:17.115088	\N
10	0.00	0	2024-12-18 09:27:08.063055	\N
11	0.00	0	2024-12-18 09:28:58.168532	\N
12	0.00	0	2024-12-18 10:20:13.772304	\N
13	0.00	0	2024-12-18 10:23:56.444461	\N
14	0.00	0	2024-12-18 10:26:26.918832	\N
15	0.00	0	2024-12-18 10:29:36.749164	\N
16	0.00	0	2024-12-18 10:31:32.618129	\N
17	0.00	0	2024-12-18 10:33:20.672949	\N
18	0.00	0	2024-12-18 10:35:14.248624	\N
19	0.00	0	2024-12-18 10:36:58.730719	\N
20	0.00	0	2024-12-18 10:40:14.690594	\N
21	0.00	0	2024-12-18 10:48:39.16258	\N
22	0.00	0	2024-12-18 10:50:23.162415	\N
23	0.00	0	2024-12-18 10:52:35.078859	\N
24	0.00	0	2024-12-18 10:57:36.293322	\N
25	0.00	0	2024-12-18 11:02:12.600857	\N
26	0.00	0	2024-12-18 11:03:45.570429	\N
27	0.00	0	2024-12-18 11:06:44.281741	\N
28	0.00	0	2024-12-18 11:22:09.313217	\N
29	0.00	0	2024-12-18 11:24:22.346153	\N
30	0.00	0	2024-12-18 11:27:20.845918	\N
31	0.00	0	2024-12-18 11:31:34.347109	\N
32	0.00	0	2024-12-18 11:33:24.613928	\N
33	0.00	0	2024-12-18 11:35:22.656879	\N
34	0.00	0	2024-12-18 11:37:22.976806	\N
35	0.00	0	2024-12-18 11:39:12.826397	\N
36	0.00	0	2024-12-18 11:40:57.371777	\N
37	0.00	0	2024-12-18 11:43:51.317645	\N
38	0.00	0	2024-12-18 14:27:58.886202	\N
39	0.00	0	2024-12-18 14:30:08.688865	\N
40	0.00	0	2024-12-18 14:32:29.118782	\N
41	0.00	0	2024-12-18 14:34:35.56954	\N
42	0.00	0	2024-12-18 14:37:21.17136	\N
43	0.00	0	2024-12-18 14:39:41.057192	\N
44	0.00	0	2024-12-18 14:41:42.219266	\N
45	0.00	0	2024-12-18 14:44:15.173383	\N
46	0.00	0	2024-12-18 14:46:09.888294	\N
47	0.00	0	2024-12-18 14:48:30.144321	\N
48	0.00	0	2024-12-18 14:50:52.256949	\N
49	0.00	0	2024-12-18 14:53:34.474692	\N
50	0.00	0	2024-12-18 14:56:48.065944	\N
51	0.00	0	2024-12-18 14:58:27.312107	\N
52	0.00	0	2024-12-18 15:00:03.628162	\N
53	0.00	0	2024-12-18 15:01:44.538124	\N
54	0.00	0	2024-12-18 15:08:07.061356	\N
55	0.00	0	2024-12-18 15:09:27.038884	\N
56	0.00	0	2024-12-18 15:11:14.898965	\N
57	0.00	0	2024-12-18 15:13:47.189491	\N
58	0.00	0	2024-12-18 15:17:22.930543	\N
59	0.00	0	2024-12-18 15:19:12.89855	\N
60	0.00	0	2024-12-18 15:20:55.359167	\N
61	0.00	0	2024-12-18 15:24:23.970285	\N
62	0.00	0	2024-12-18 15:25:51.990925	\N
63	0.00	0	2024-12-18 15:27:38.597348	\N
64	0.00	0	2024-12-18 15:29:41.268248	\N
65	0.00	0	2024-12-18 15:31:28.950818	\N
66	0.00	0	2024-12-18 15:33:44.991818	\N
67	0.00	0	2024-12-18 15:36:08.708524	\N
68	0.00	0	2024-12-18 15:37:28.553789	\N
69	0.00	0	2024-12-18 15:39:22.311394	\N
70	0.00	0	2024-12-18 15:43:32.451049	\N
71	0.00	0	2024-12-18 15:45:10.892746	\N
72	0.00	0	2024-12-18 15:46:31.777323	\N
73	0.00	0	2024-12-18 15:48:15.17917	\N
74	0.00	0	2024-12-18 15:49:42.083778	\N
75	0.00	0	2024-12-18 15:51:43.044017	\N
76	0.00	0	2024-12-18 15:53:20.061685	\N
77	0.00	0	2024-12-18 15:56:17.610081	\N
78	0.00	0	2024-12-18 15:57:54.613803	\N
79	0.00	0	2024-12-18 16:02:44.734859	\N
80	0.00	0	2024-12-18 16:03:52.243576	\N
81	0.00	0	2024-12-18 16:05:59.396972	\N
82	0.00	0	2024-12-18 16:08:15.825821	\N
83	0.00	0	2024-12-18 16:09:43.881661	\N
84	0.00	0	2024-12-18 16:11:07.154903	\N
85	0.00	0	2024-12-18 16:12:35.125385	\N
86	0.00	0	2024-12-18 16:14:31.15002	\N
87	0.00	0	2024-12-18 16:16:54.842805	\N
88	0.00	0	2024-12-18 16:18:26.625378	\N
89	0.00	0	2024-12-18 16:20:44.219933	\N
90	0.00	0	2024-12-18 16:22:39.355888	\N
91	0.00	0	2024-12-18 16:25:20.042808	\N
92	0.00	0	2024-12-18 16:27:05.785892	\N
93	0.00	0	2024-12-18 16:28:26.055842	\N
94	0.00	0	2024-12-18 16:30:15.843821	\N
95	0.00	0	2024-12-19 11:26:25.989426	\N
96	0.00	0	2024-12-19 12:01:09.272827	\N
97	0.00	0	2024-12-19 12:02:40.222266	\N
98	0.00	0	2024-12-19 12:04:08.266938	\N
99	0.00	0	2024-12-19 12:05:49.98959	\N
100	0.00	0	2024-12-19 12:07:27.385333	\N
101	0.00	0	2024-12-19 12:09:28.288382	\N
102	0.00	0	2024-12-19 12:11:32.829642	\N
103	0.00	0	2024-12-19 12:14:38.634583	\N
104	0.00	0	2024-12-19 12:16:22.808897	\N
105	0.00	0	2024-12-19 12:17:39.440791	\N
106	0.00	0	2024-12-19 12:19:40.415906	\N
107	0.00	0	2024-12-19 12:21:05.56178	\N
108	0.00	0	2024-12-19 12:22:46.020362	\N
109	0.00	0	2024-12-19 12:28:45.211788	\N
110	0.00	0	2025-01-20 09:26:46.446659	\N
111	0.00	0	2025-01-20 09:34:12.261808	\N
112	0.00	0	2025-01-20 09:41:58.763282	\N
115	0.00	0	2025-01-23 16:38:04.034299	\N
116	0.00	0	2025-01-24 10:25:50.73148	\N
117	0.00	0	2025-01-24 10:28:47.327425	\N
118	0.00	0	2025-01-24 10:31:40.987146	\N
119	0.00	0	2025-01-24 10:33:44.675813	\N
120	0.00	0	2025-01-24 10:35:56.328043	\N
121	0.00	0	2025-01-24 10:37:35.382003	\N
122	0.00	0	2025-01-24 10:38:56.68526	\N
123	0.00	0	2025-01-24 10:40:36.235193	\N
124	0.00	0	2025-01-24 10:42:44.165784	\N
125	0.00	0	2025-01-29 12:18:34.798812	\N
126	0.00	0	2025-03-09 17:01:26.45785	\N
127	0.00	0	2025-03-09 21:18:01.044259	\N
128	0.00	0	2025-03-09 21:23:16.680001	\N
129	0.00	0	2025-03-09 21:25:17.893893	\N
130	0.00	0	2025-03-09 21:27:13.120396	\N
131	0.00	0	2025-06-04 09:32:53.863184	\N
132	0.00	0	2025-06-04 09:34:54.863769	\N
11111	0.00	0	2025-07-01 12:46:46.964826	\N
111111111	0.00	0	2025-07-07 12:10:03.33647	\N
1111111	0.00	0	2025-08-14 16:07:25.510249	\N
222222	0.00	0	2025-08-14 16:08:14.584299	\N
3333333	0.00	0	2025-08-14 16:09:04.239231	\N
12345	0.00	0	2025-08-14 16:35:50.961747	\N
1212	0.00	0	2025-08-14 16:47:02.410964	\N
121345	0.00	0	2025-08-27 14:13:34.296015	\N
167	0.00	0	2025-08-28 08:58:31.338019	\N
189	0.00	0	2025-08-28 09:43:23.581897	\N
188	0.00	0	2025-08-28 09:57:49.968899	\N
181	0.00	0	2025-08-28 10:04:54.667094	\N
175	0.00	0	2025-08-28 10:17:02.788538	\N
173	0.00	0	2025-08-28 10:23:59.888518	\N
171	0.00	0	2025-08-28 11:10:08.835046	\N
170	0.00	0	2025-08-28 12:23:05.102993	\N
1800	0.00	0	2025-08-28 14:01:58.249919	\N
888	0.00	0	2025-08-28 14:52:44.974363	\N
889	0.00	0	2025-08-28 14:57:36.12211	\N
887	0.00	0	2025-08-28 15:10:10.62003	\N
885	0.00	0	2025-08-28 15:15:11.913583	\N
884	0.00	0	2025-08-28 15:21:45.452095	\N
883	0.00	0	2025-08-28 15:35:54.111608	\N
882	0.00	0	2025-08-28 15:41:32.682969	\N
881	0.00	0	2025-08-28 15:53:16.418309	\N
880	0.00	0	2025-08-28 16:05:15.676821	\N
879	0.00	0	2025-08-28 16:13:42.864558	\N
876	0.00	0	2025-08-28 16:25:45.273288	\N
870	0.00	0	2025-08-29 08:50:59.054495	\N
869	0.00	0	2025-08-29 11:18:56.56859	\N
868	0.00	0	2025-08-29 11:26:36.207015	\N
866	0.00	0	2025-08-29 11:30:53.502061	\N
862	0.00	0	2025-08-29 11:38:11.267874	\N
863	0.00	0	2025-08-29 11:45:23.01993	\N
860	0.00	0	2025-08-29 11:47:36.731053	\N
44444444	0.00	0	2025-08-29 12:01:04.159165	\N
859	0.00	0	2025-08-29 12:06:59.174666	\N
852	0.00	0	2025-08-29 13:24:45.170034	\N
851	0.00	0	2025-08-29 13:46:14.964097	\N
850	0.00	0	2025-08-29 13:49:21.773473	\N
853	0.00	0	2025-08-29 13:51:14.672489	\N
849	0.00	0	2025-08-29 14:01:53.214045	\N
848	0.00	0	2025-08-29 14:05:01.84869	\N
44444445	0.00	0	2025-08-29 14:21:41.300358	\N
44444446	0.00	0	2025-08-29 15:04:06.186623	\N
44444447	0.00	0	2025-08-29 15:09:15.940354	\N
44444448	0.00	0	2025-09-08 10:26:01.067388	\N
44444449	0.00	0	2025-09-08 10:40:48.39901	\N
44444450	0.00	0	2025-09-08 10:44:20.178172	\N
44444451	0.00	0	2025-09-08 11:14:09.937928	\N
44444452	0.00	0	2025-09-08 11:19:20.16556	\N
44444453	0.00	0	2025-09-08 11:37:04.844557	\N
44444454	0.00	0	2025-09-08 11:40:35.439777	\N
44444455	0.00	0	2025-09-08 11:41:49.078439	\N
44444456	0.00	0	2025-09-08 14:46:10.509649	\N
44444457	0.00	0	2025-09-08 14:52:45.847986	\N
44444458	0.00	0	2025-09-09 12:30:52.845587	\N
44444459	0.00	0	2025-09-12 10:47:59.702202	\N
44444460	0.00	0	2025-09-12 10:49:26.946365	\N
44444461	0.00	0	2025-09-12 11:28:27.877046	\N
44444462	0.00	0	2025-09-12 11:36:37.909258	\N
44444463	0.00	0	2025-09-12 11:36:50.121856	\N
44444464	0.00	0	2025-09-12 11:37:05.682741	\N
44444465	0.00	0	2025-09-12 11:37:43.133491	\N
\.


--
-- Data for Name: food_service_categories; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.food_service_categories (category_id, school_id, menu_id, title, sort_order, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: food_service_items; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.food_service_items (item_id, school_id, short_name, sort_order, description, icon, price, price_reduced, price_free, price_staff, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: food_service_menu_items; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.food_service_menu_items (menu_item_id, school_id, menu_id, item_id, category_id, sort_order, does_count, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: food_service_menus; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.food_service_menus (menu_id, school_id, title, sort_order, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: food_service_staff_accounts; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.food_service_staff_accounts (staff_id, status, barcode, balance, transaction_id, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: food_service_staff_transaction_items; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.food_service_staff_transaction_items (item_id, transaction_id, amount, short_name, description, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: food_service_staff_transactions; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.food_service_staff_transactions (transaction_id, staff_id, school_id, syear, balance, "timestamp", short_name, description, seller_id, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: food_service_student_accounts; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.food_service_student_accounts (student_id, account_id, discount, status, barcode, created_at, updated_at) FROM stdin;
1	1	\N	\N	\N	2025-08-07 17:30:46.667506	\N
2	2	\N	\N	\N	2025-08-08 09:09:33.856864	\N
3	3	\N	\N	\N	2025-08-08 09:11:58.730397	\N
5	5	\N	\N	\N	2025-08-08 09:28:50.173164	\N
6	6	\N	\N	\N	2025-08-08 13:38:22.033363	\N
1111111	1111111	\N	\N	\N	2025-08-14 16:07:25.504538	\N
222222	222222	\N	\N	\N	2025-08-14 16:08:14.582188	\N
3333333	3333333	\N	\N	\N	2025-08-14 16:09:04.236919	\N
12345	12345	\N	\N	\N	2025-08-14 16:35:50.960144	\N
1212	1212	\N	\N	\N	2025-08-14 16:47:02.40935	\N
121345	121345	\N	\N	\N	2025-08-27 14:13:34.287848	\N
99	99	\N	\N	\N	2025-08-27 14:26:14.081311	\N
98	98	\N	\N	\N	2025-08-27 14:45:22.881471	\N
97	97	\N	\N	\N	2025-08-27 15:24:34.647853	\N
94	94	\N	\N	\N	2025-08-27 15:40:54.894527	\N
101	101	\N	\N	\N	2025-08-27 15:56:39.597924	\N
167	167	\N	\N	\N	2025-08-28 08:58:31.334599	\N
88	88	\N	\N	\N	2025-08-28 09:04:25.172422	\N
189	189	\N	\N	\N	2025-08-28 09:43:23.580201	\N
188	188	\N	\N	\N	2025-08-28 09:57:49.966482	\N
181	181	\N	\N	\N	2025-08-28 10:04:54.6657	\N
175	175	\N	\N	\N	2025-08-28 10:17:02.786568	\N
173	173	\N	\N	\N	2025-08-28 10:23:59.887322	\N
171	171	\N	\N	\N	2025-08-28 11:10:08.833516	\N
170	170	\N	\N	\N	2025-08-28 12:23:05.100876	\N
1800	1800	\N	\N	\N	2025-08-28 14:01:58.247224	\N
888	888	\N	\N	\N	2025-08-28 14:52:44.972775	\N
889	889	\N	\N	\N	2025-08-28 14:57:36.120213	\N
887	887	\N	\N	\N	2025-08-28 15:10:10.618208	\N
885	885	\N	\N	\N	2025-08-28 15:15:11.912066	\N
884	884	\N	\N	\N	2025-08-28 15:21:45.449989	\N
883	883	\N	\N	\N	2025-08-28 15:35:54.11002	\N
882	882	\N	\N	\N	2025-08-28 15:41:32.680879	\N
881	881	\N	\N	\N	2025-08-28 15:53:16.417019	\N
880	880	\N	\N	\N	2025-08-28 16:05:15.675297	\N
879	879	\N	\N	\N	2025-08-28 16:13:42.86265	\N
876	876	\N	\N	\N	2025-08-28 16:25:45.271545	\N
870	870	\N	\N	\N	2025-08-29 08:50:59.051744	\N
869	869	\N	\N	\N	2025-08-29 11:18:56.564248	\N
868	868	\N	\N	\N	2025-08-29 11:26:36.205063	\N
866	866	\N	\N	\N	2025-08-29 11:30:53.49973	\N
862	862	\N	\N	\N	2025-08-29 11:38:11.266118	\N
863	863	\N	\N	\N	2025-08-29 11:45:23.018291	\N
860	860	\N	\N	\N	2025-08-29 11:47:36.729186	\N
44444444	44444444	\N	\N	\N	2025-08-29 12:01:04.155925	\N
859	859	\N	\N	\N	2025-08-29 12:06:59.172853	\N
852	852	\N	\N	\N	2025-08-29 13:24:45.168656	\N
851	851	\N	\N	\N	2025-08-29 13:46:14.961783	\N
850	850	\N	\N	\N	2025-08-29 13:49:21.771614	\N
853	853	\N	\N	\N	2025-08-29 13:51:14.670945	\N
849	849	\N	\N	\N	2025-08-29 14:01:53.21244	\N
848	848	\N	\N	\N	2025-08-29 14:05:01.839496	\N
44444445	44444445	\N	\N	\N	2025-08-29 14:21:41.298476	\N
44444446	44444446	\N	\N	\N	2025-08-29 15:04:06.182882	\N
44444447	44444447	\N	\N	\N	2025-08-29 15:09:15.938166	\N
44444448	44444448	\N	\N	\N	2025-09-08 10:26:01.064335	\N
44444449	44444449	\N	\N	\N	2025-09-08 10:40:48.397205	\N
44444450	44444450	\N	\N	\N	2025-09-08 10:44:20.176557	\N
44444451	44444451	\N	\N	\N	2025-09-08 11:14:09.936126	\N
44444452	44444452	\N	\N	\N	2025-09-08 11:19:20.163198	\N
44444453	44444453	\N	\N	\N	2025-09-08 11:37:04.84235	\N
44444454	44444454	\N	\N	\N	2025-09-08 11:40:35.43836	\N
44444455	44444455	\N	\N	\N	2025-09-08 11:41:49.075931	\N
44444456	44444456	\N	\N	\N	2025-09-08 14:46:10.506915	\N
44444457	44444457	\N	\N	\N	2025-09-08 14:52:45.846484	\N
44444458	44444458	\N	\N	\N	2025-09-09 12:30:52.843612	\N
44444459	44444459	\N	\N	\N	2025-09-12 10:47:59.700512	\N
44444460	44444460	\N	\N	\N	2025-09-12 10:49:26.944875	\N
44444461	44444461	\N	\N	\N	2025-09-12 11:28:27.874887	\N
44444462	44444462	\N	\N	\N	2025-09-12 11:36:37.908089	\N
44444463	44444463	\N	\N	\N	2025-09-12 11:36:50.120503	\N
44444464	44444464	\N	\N	\N	2025-09-12 11:37:05.681366	\N
44444465	44444465	\N	\N	\N	2025-09-12 11:37:43.13112	\N
124	124	\N	\N	\N	2025-09-12 11:41:57.803234	\N
\.


--
-- Data for Name: food_service_transaction_items; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.food_service_transaction_items (item_id, transaction_id, amount, discount, short_name, description, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: food_service_transactions; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.food_service_transactions (transaction_id, account_id, student_id, school_id, syear, discount, balance, "timestamp", short_name, description, seller_id, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: grade_levels; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.grade_levels (id, title, sort_order) FROM stdin;
1	6ème	1
2	5ème	2
3	4ème	3
4	3ème	4
5	6ème	1
6	5ème	2
7	4ème	3
8	3ème	4
\.


--
-- Data for Name: gradebook_assignment_types; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.gradebook_assignment_types (assignment_type_id, staff_id, course_id, title, final_grade_percent, sort_order, color, created_mp, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: gradebook_assignments; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.gradebook_assignments (assignment_id, staff_id, marking_period_id, course_period_id, course_id, assignment_type_id, title, assigned_date, due_date, points, description, file, default_points, submission, weight, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: gradebook_grades; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.gradebook_grades (student_id, period_id, course_period_id, assignment_id, points, comment, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: grades_completed; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.grades_completed (staff_id, marking_period_id, course_period_id, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: history_marking_periods; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.history_marking_periods (parent_id, mp_type, name, short_name, post_end_date, school_id, syear, marking_period_id, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: lunch_period; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.lunch_period (student_id, school_date, period_id, attendance_code, attendance_teacher_code, attendance_reason, admin, course_period_id, marking_period_id, comment, table_name, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: messages; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.messages (message_id, syear, school_id, "from", recipients, subject, data, created_at) FROM stdin;
\.


--
-- Data for Name: messagexuser; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.messagexuser (user_id, key, message_id, status) FROM stdin;
\.


--
-- Data for Name: moodlexrosario; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.moodlexrosario ("column", rosario_id, moodle_id, created_at, updated_at) FROM stdin;
staff_id	1	2	2023-08-01 22:43:31.104393	\N
\.


--
-- Data for Name: people; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.people (person_id, last_name, first_name, middle_name, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: people_field_categories; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.people_field_categories (id, title, sort_order, custody, emergency, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: people_fields; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.people_fields (id, type, title, sort_order, select_options, category_id, required, default_selection, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: people_join_contacts; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.people_join_contacts (id, person_id, title, value, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: portal_notes; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.portal_notes (id, school_id, syear, title, content, sort_order, published_user, published_date, start_date, end_date, published_profiles, file_attached, created_at, updated_at) FROM stdin;
4	17	2024	dzdzdz	\N	\N	1	\N	\N	\N	\N	assets/PortalNotesFiles/capture d_ecran _190__2025-07-21_123125.826960.png	2025-07-21 11:31:26.203405	\N
3	17	2024	DddFF	\N	\N	1	\N	\N	\N	\N	assets/PortalNotesFiles/photo_2025-06-19_10-33-28_2025-07-21_122403.875901.jpg	2025-07-21 11:24:03.89034	\N
1	17	2024	MARDI	\N	\N	1	\N	\N	\N	\N	assets/PortalNotesFiles/capture d_ecran 2025-07-18 131057_2025-07-21_111013.243482.png	2025-07-21 10:10:13.510802	\N
6	21	2025	ORTHOGRAPHE	DFM POUR LA CLASSE DE 6EME	\N	1	\N	2025-09-11	2025-09-12	,0,2,3,	assets/PortalNotesFiles/ic-project-action-plan-8595_word_fr_2025-09-11_113028.155945.docx	2025-09-11 11:30:28.15727	\N
\.


--
-- Data for Name: portal_poll_questions; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.portal_poll_questions (id, portal_poll_id, question, type, options, votes, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: portal_polls; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.portal_polls (id, school_id, syear, title, votes_number, display_votes, sort_order, published_user, published_date, start_date, end_date, published_profiles, students_teacher_id, excluded_users, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: profile_exceptions; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.profile_exceptions (profile_id, modname, can_use, can_edit, created_at, updated_at) FROM stdin;
1	Scheduling/MassRequests.php	Y	Y	2023-08-15 16:45:54.462429	2023-08-15 16:45:54.463024
1	Scheduling/MassDrops.php	Y	Y	2023-08-15 16:45:54.463865	2023-08-15 16:45:54.464539
1	Grades/FixGPA.php	Y	Y	2023-08-01 22:43:31.104393	\N
1	Grades/ReportCardGrades.php	Y	Y	2023-08-15 16:45:54.481273	2023-08-15 16:45:54.482126
9	School_Setup/PortalNotes.php	Y	\N	2023-08-15 14:05:32.154978	2023-10-15 20:15:09.401768
1	Users/TeacherPrograms.php&include=Grades/AnomalousGrades.php	Y	Y	2023-08-01 22:43:31.104393	2023-08-13 15:35:19.670364
1	Users/TeacherPrograms.php&include=Attendance/TakeAttendance.php	Y	Y	2023-08-01 22:43:31.104393	2023-08-13 15:35:19.671018
1	Users/TeacherPrograms.php&include=Eligibility/EnterEligibility.php	Y	Y	2023-08-01 22:43:31.104393	2023-08-13 15:35:19.671705
1	Scheduling/Schedule.php	Y	Y	2023-08-15 16:45:54.458383	2023-08-15 16:45:54.458805
1	Scheduling/Requests.php	Y	Y	2023-08-15 16:45:54.459438	2023-08-15 16:45:54.460057
1	Scheduling/MassSchedule.php	Y	Y	2023-08-15 16:45:54.461109	2023-08-15 16:45:54.461761
1	Grades/ReportCardComments.php	Y	Y	2023-08-15 16:45:54.482814	2023-08-15 16:45:54.48329
1	Grades/ReportCardCommentCodes.php	Y	Y	2023-08-15 16:45:54.483839	2023-08-15 16:45:54.484329
1	Grades/EditHistoryMarkingPeriods.php	Y	Y	2023-08-15 16:45:54.484854	2023-08-15 16:45:54.485306
1	Grades/EditReportCardGrades.php	Y	Y	2023-08-15 16:45:54.485827	2023-08-15 16:45:54.486276
1	Attendance/Percent.php	Y	Y	2023-08-01 22:43:31.104393	2023-08-15 16:45:54.490545
1	Attendance/DailySummary.php	Y	Y	2023-08-01 22:43:31.104393	2023-08-15 16:45:54.491075
1	Attendance/FixDailyAttendance.php	Y	Y	2023-08-01 22:43:31.104393	2023-08-15 16:45:54.492656
1	Attendance/DuplicateAttendance.php	Y	Y	2023-08-01 22:43:31.104393	2023-08-15 16:45:54.49352
1	Attendance/AttendanceCodes.php	Y	Y	2023-08-01 22:43:31.104393	2023-08-15 16:45:54.494202
1	Eligibility/Activities.php	Y	Y	2023-08-01 22:43:31.104393	2023-08-15 16:45:54.497236
1	Eligibility/EntryTimes.php	Y	Y	2023-08-01 22:43:31.104393	2023-08-15 16:45:54.498216
1	Student_Billing/StudentBalances.php	Y	Y	2023-08-15 16:45:54.5208	2023-08-15 16:45:54.521556
1	Student_Billing/DailyTransactions.php	Y	Y	2023-08-15 16:45:54.522147	2023-08-15 16:45:54.522655
1	Scheduling/PrintClassLists.php	Y	Y	2023-08-01 22:43:31.104393	2023-08-15 16:45:54.466651
1	Scheduling/PrintClassPictures.php	Y	Y	2023-08-01 22:43:31.104393	2023-08-15 16:45:54.467458
1	Scheduling/PrintRequests.php	Y	Y	2023-08-01 22:43:31.104393	2023-08-15 16:45:54.468227
1	Scheduling/ScheduleReport.php	Y	Y	2023-08-01 22:43:31.104393	2023-08-15 16:45:54.468954
1	Scheduling/RequestsReport.php	Y	Y	2023-08-01 22:43:31.104393	2023-08-15 16:45:54.46965
1	Scheduling/IncompleteSchedules.php	Y	Y	2023-08-01 22:43:31.104393	2023-08-15 16:45:54.470329
1	Scheduling/AddDrop.php	Y	Y	2023-08-01 22:43:31.104393	2023-08-15 16:45:54.470964
1	Scheduling/Courses.php	Y	Y	2023-08-01 22:43:31.104393	2023-08-15 16:45:54.471751
1	Scheduling/Scheduler.php	Y	Y	2023-08-01 22:43:31.104393	2023-08-15 16:45:54.472429
1	Grades/ReportCards.php	Y	Y	2023-08-01 22:43:31.104393	2023-08-15 16:45:54.473069
1	Grades/HonorRoll.php	Y	Y	2023-08-01 22:43:31.104393	2023-08-15 16:45:54.473716
1	Grades/Transcripts.php	Y	Y	2023-08-01 22:43:31.104393	2023-08-15 16:45:54.474398
1	Grades/StudentGrades.php	Y	Y	2023-08-01 22:43:31.104393	2023-08-15 16:45:54.475094
1	Grades/ProgressReports.php	Y	Y	2023-08-01 22:43:31.104393	2023-08-15 16:45:54.475915
1	Grades/TeacherCompletion.php	Y	Y	2023-08-01 22:43:31.104393	2023-08-15 16:45:54.476687
1	Grades/GradeBreakdown.php	Y	Y	2023-08-01 22:43:31.104393	2023-08-15 16:45:54.47736
1	Grades/FinalGrades.php	Y	Y	2023-08-01 22:43:31.104393	2023-08-15 16:45:54.478185
1	Grades/GPARankList.php	Y	Y	2023-08-01 22:43:31.104393	2023-08-15 16:45:54.479164
1	Grades/Configuration.php	Y	Y	2023-08-15 16:45:54.47999	2023-08-15 16:45:54.480605
1	Grades/MassCreateAssignments.php	Y	Y	2023-08-15 16:45:54.486805	2023-08-15 16:45:54.487269
1	Attendance/Administration.php	Y	Y	2023-08-01 22:43:31.104393	2023-08-15 16:45:54.488134
1	Attendance/AddAbsences.php	Y	Y	2023-08-01 22:43:31.104393	2023-08-15 16:45:54.488847
1	Attendance/TeacherCompletion.php	Y	Y	2023-08-01 22:43:31.104393	2023-08-15 16:45:54.489556
1	Eligibility/Student.php	Y	\N	2023-08-01 22:43:31.104393	2023-08-13 15:26:48.132596
1	Eligibility/AddActivity.php	Y	\N	2023-08-01 22:43:31.104393	2023-08-13 15:26:48.133165
1	Eligibility/StudentList.php	Y	Y	2023-08-01 22:43:31.104393	2023-08-15 16:45:54.496037
1	Student_Billing/Statements.php	Y	Y	2023-08-15 16:45:54.523194	2023-08-15 16:45:54.523844
1	Food_Service/Accounts.php	Y	Y	2023-08-15 16:45:54.524883	2023-08-15 16:45:54.525341
1	Food_Service/Statements.php	Y	Y	2023-08-15 16:45:54.525827	2023-08-15 16:45:54.526278
1	Food_Service/Transactions.php	Y	Y	2023-08-15 16:45:54.52706	2023-08-15 16:45:54.527597
1	Food_Service/ServeMenus.php	Y	Y	2023-08-15 16:45:54.528349	2023-08-15 16:45:54.529097
1	Food_Service/ActivityReport.php	Y	Y	2023-08-15 16:45:54.529693	2023-08-15 16:45:54.530162
1	Food_Service/TransactionsReport.php	Y	Y	2023-08-15 16:45:54.530976	2023-08-15 16:45:54.531509
1	Resources/Resources.php	Y	Y	2023-08-01 22:43:31.104393	2023-08-15 16:45:54.54397
1	Wx_Custom/Resources.php	Y	Y	2024-01-23 21:22:10.98368	\N
0	Food_Service/DailyMenus.php	Y	\N	2023-08-01 22:43:31.104393	\N
0	Food_Service/MenuItems.php	Y	\N	2023-08-01 22:43:31.104393	\N
0	School_Setup/Schools.php	Y	\N	2023-08-01 22:43:31.104393	\N
0	School_Setup/MarkingPeriods.php	Y	\N	2023-08-01 22:43:31.104393	\N
0	Students/Student.php	Y	\N	2023-08-01 22:43:31.104393	\N
1	Students/PrintStudentInfo.php	Y	Y	2023-08-01 22:43:31.104393	2023-08-13 15:35:19.653469
0	Custom/Registration.php	Y	\N	2023-08-01 22:43:31.104393	\N
2	Grades/Assignments-new.php	Y	\N	2023-08-01 22:43:31.104393	\N
0	Grades/ProgressReports.php	Y	\N	2023-08-01 22:43:31.104393	\N
1	Students/AssignOtherInfo.php	Y	Y	2023-08-01 22:43:31.104393	2023-08-13 15:35:19.648885
1	Students/AddUsers.php	Y	Y	2023-08-01 22:43:31.104393	2023-08-13 15:35:19.650051
1	Students/AdvancedReport.php	Y	Y	2023-08-01 22:43:31.104393	2023-08-13 15:35:19.650769
1	Students/AddDrop.php	Y	Y	2023-08-01 22:43:31.104393	2023-08-13 15:35:19.651373
1	Students/Letters.php	Y	Y	2023-08-01 22:43:31.104393	2023-08-13 15:35:19.652418
1	Students/StudentFields.php	Y	Y	2023-08-01 22:43:31.104393	2023-08-13 15:35:19.653893
1	Students/EnrollmentCodes.php	Y	Y	2023-08-01 22:43:31.104393	2023-08-13 15:35:19.654341
1	Custom/MyReport.php	Y	Y	2023-08-15 16:45:54.436139	2023-08-15 16:45:54.436779
1	Students/Student.php&category_id=1	Y	Y	2023-08-01 22:43:31.104393	2023-08-13 15:35:19.65721
1	Students/Student.php&category_id=2	Y	Y	2023-08-01 22:43:31.104393	2023-08-13 15:35:19.657956
1	Users/User.php	Y	Y	2023-08-01 22:43:31.104393	2023-08-13 15:35:19.663166
1	Users/User.php&staff_id=new	Y	Y	2023-08-01 22:43:31.104393	2023-08-13 15:35:19.6646
1	Users/AddStudents.php	Y	Y	2023-08-01 22:43:31.104393	2023-08-13 15:35:19.665573
1	Users/Preferences.php	Y	Y	2023-08-01 22:43:31.104393	2023-08-13 15:35:19.666221
1	Users/Profiles.php	Y	Y	2023-08-01 22:43:31.104393	\N
1	Users/Exceptions.php	Y	Y	2023-08-01 22:43:31.104393	2023-08-13 15:35:19.667986
1	Users/User.php&category_id=1	Y	Y	2023-08-01 22:43:31.104393	2023-08-13 15:35:19.673271
1	Users/User.php&category_id=1&user_profile	Y	Y	2023-08-01 22:43:31.104393	2023-08-13 15:35:19.673889
1	Users/User.php&category_id=2	Y	Y	2023-08-01 22:43:31.104393	2023-08-13 15:35:19.674988
1	Users/User.php&category_id=3	Y	Y	2023-08-01 22:43:31.104393	2023-08-13 15:35:19.675707
1	Accounting/Incomes.php	Y	Y	2023-08-01 22:43:31.104393	2023-08-15 16:45:54.503429
1	Accounting/Expenses.php	Y	Y	2023-08-01 22:43:31.104393	2023-08-15 16:45:54.503969
1	Accounting/Salaries.php	Y	Y	2023-08-01 22:43:31.104393	2023-08-15 16:45:54.508388
1	Accounting/StaffPayments.php	Y	Y	2023-08-01 22:43:31.104393	2023-08-15 16:45:54.511485
1	Accounting/DailyTransactions.php	Y	Y	2023-08-01 22:43:31.104393	2023-08-15 16:45:54.512342
1	Accounting/StaffBalances.php	Y	Y	2023-08-01 22:43:31.104393	2023-08-15 16:45:54.512986
1	Accounting/Statements.php	Y	Y	2023-08-01 22:43:31.104393	2023-08-15 16:45:54.513785
0	Grades/Transcripts.php	Y	\N	2023-08-01 22:43:31.104393	\N
0	Students/Student.php&category_id=1	Y	\N	2023-08-01 22:43:31.104393	\N
0	Scheduling/Requests.php	Y	\N	2023-08-01 22:43:31.104393	\N
0	Scheduling/Courses.php	Y	\N	2023-08-01 22:43:31.104393	\N
0	Scheduling/PrintSchedules.php	Y	\N	2023-08-01 22:43:31.104393	\N
0	Scheduling/PrintClassPictures.php	Y	\N	2023-08-01 22:43:31.104393	\N
0	Grades/StudentGrades.php	Y	\N	2023-08-01 22:43:31.104393	\N
0	Grades/StudentAssignments.php	Y	\N	2023-08-01 22:43:31.104393	\N
0	Grades/FinalGrades.php	Y	\N	2023-08-01 22:43:31.104393	\N
0	Grades/ReportCards.php	Y	\N	2023-08-01 22:43:31.104393	\N
0	Grades/GPARankList.php	Y	\N	2023-08-01 22:43:31.104393	\N
0	Attendance/DailySummary.php	Y	\N	2023-08-01 22:43:31.104393	\N
0	Eligibility/Student.php	Y	\N	2023-08-01 22:43:31.104393	\N
0	Attendance/StudentSummary.php	Y	\N	2023-08-01 22:43:31.104393	\N
0	Eligibility/StudentList.php	Y	\N	2023-08-01 22:43:31.104393	\N
0	Food_Service/Accounts.php	Y	\N	2023-08-01 22:43:31.104393	\N
3	Grades/ReportCards.php	Y	\N	2023-08-01 22:43:31.104393	\N
3	Food_Service/Statements.php	Y	\N	2023-08-01 22:43:31.104393	\N
3	Food_Service/DailyMenus.php	Y	\N	2023-08-01 22:43:31.104393	\N
3	Food_Service/MenuItems.php	Y	\N	2023-08-01 22:43:31.104393	\N
0	Food_Service/Statements.php	Y	\N	2023-08-01 22:43:31.104393	\N
0	Students/Student.php&category_id=3	Y	\N	2023-08-01 22:43:31.104393	\N
0	Users/Preferences.php	Y	\N	2023-08-01 22:43:31.104393	\N
3	Scheduling/Schedule.php	Y	\N	2023-08-01 22:43:31.104393	\N
3	Scheduling/Courses.php	Y	\N	2023-08-01 22:43:31.104393	\N
3	Scheduling/PrintSchedules.php	Y	\N	2023-08-01 22:43:31.104393	\N
1	Custom/AttendanceSummary.php	Y	Y	2023-08-01 22:43:31.104393	2023-08-15 16:45:54.491678
9	Users/User.php	Y	\N	2023-09-16 16:25:53.045725	2023-09-19 10:42:09.927421
2	Grades/Configuration.php	Y	\N	2023-08-01 22:43:31.104393	\N
2	Grades/ReportCardGrades.php	Y	\N	2023-08-01 22:43:31.104393	\N
2	Grades/ReportCardComments.php	Y	\N	2023-08-01 22:43:31.104393	\N
0	School_Setup/Calendar.php	Y	\N	2023-08-01 22:43:31.104393	\N
3	Scheduling/PrintClassPictures.php	Y	\N	2023-08-01 22:43:31.104393	\N
3	Grades/StudentGrades.php	Y	\N	2023-08-01 22:43:31.104393	\N
3	Grades/StudentAssignments.php	Y	\N	2023-08-01 22:43:31.104393	\N
3	Grades/ProgressReports.php	Y	\N	2023-08-01 22:43:31.104393	\N
3	Grades/Transcripts.php	Y	\N	2023-08-01 22:43:31.104393	\N
3	Grades/GPARankList.php	Y	\N	2023-08-01 22:43:31.104393	\N
3	Attendance/DailySummary.php	Y	\N	2023-08-01 22:43:31.104393	\N
3	Grades/FinalGrades.php	Y	\N	2023-08-01 22:43:31.104393	\N
3	Eligibility/Student.php	Y	\N	2023-08-01 22:43:31.104393	\N
2	Scheduling/Courses.php	Y	\N	2023-08-01 22:43:31.104393	\N
2	Scheduling/PrintSchedules.php	Y	\N	2023-08-01 22:43:31.104393	\N
2	Scheduling/PrintClassLists.php	Y	\N	2023-08-01 22:43:31.104393	\N
2	Grades/Grades.php	Y	\N	2023-08-01 22:43:31.104393	\N
2	Grades/Assignments.php	Y	\N	2023-08-01 22:43:31.104393	\N
2	Grades/AnomalousGrades.php	Y	\N	2023-08-01 22:43:31.104393	\N
2	Grades/ProgressReports.php	Y	\N	2023-08-01 22:43:31.104393	\N
2	Grades/StudentGrades.php	Y	\N	2023-08-01 22:43:31.104393	\N
2	Grades/FinalGrades.php	Y	\N	2023-08-01 22:43:31.104393	\N
2	Grades/ReportCardCommentCodes.php	Y	\N	2023-08-01 22:43:31.104393	\N
3	Eligibility/StudentList.php	Y	\N	2023-08-01 22:43:31.104393	\N
3	Food_Service/Accounts.php	Y	\N	2023-08-01 22:43:31.104393	\N
0	Scheduling/Schedule.php	Y	\N	2023-08-01 22:43:31.104393	\N
1	School_Setup/Periods.php	Y	Y	2023-08-15 14:26:23.169475	2023-08-15 14:26:23.170112
2	Scheduling/Schedule.php	Y	\N	2023-08-01 22:43:31.104393	\N
2	Scheduling/PrintClassPictures.php	Y	\N	2023-08-01 22:43:31.104393	\N
2	Grades/InputFinalGrades.php	Y	\N	2023-08-01 22:43:31.104393	\N
2	Grades/ReportCards.php	Y	\N	2023-08-01 22:43:31.104393	\N
1	School_Setup/Rollover.php	Y	Y	2023-08-15 14:26:23.175611	2023-08-15 14:26:23.176206
1	Discipline/ReferralForm.php	Y	Y	2023-08-01 22:43:31.104393	\N
9	Users/User.php&category_id=1&user_profile	Y	\N	2023-09-16 16:25:53.058135	2023-09-19 10:42:09.938687
9	Users/User.php&category_id=1&schools	Y	\N	2023-09-16 16:25:53.059013	2023-09-19 10:42:09.939171
9	Users/User.php&category_id=2	Y	\N	2023-09-16 16:25:53.060114	2023-09-19 10:42:09.939667
1	Student_Billing/Fees.php	Y	Y	2023-08-01 22:43:31.104393	\N
1	Food_Service/MenuItems.php	Y	Y	2023-08-15 16:45:54.539162	2023-08-15 16:45:54.539842
1	Food_Service/Menus.php	Y	Y	2023-08-15 16:45:54.54067	2023-08-15 16:45:54.541368
1	Food_Service/Kiosk.php	Y	Y	2023-08-15 16:45:54.542	2023-08-15 16:45:54.542885
16	Accounting/Incomes.php	Y	Y	2023-10-15 20:51:37.168964	2023-10-15 20:51:37.17137
9	Users/User.php&staff_id=new	Y	\N	2023-09-16 16:25:53.048274	2023-09-19 10:42:09.928241
9	Users/Preferences.php	Y	\N	2023-09-16 16:25:53.050705	2023-09-19 10:42:09.929823
9	Users/User.php&category_id=1	Y	\N	2023-09-16 16:25:53.057228	2023-09-19 10:42:09.93809
14	Users/User.php	Y	Y	2023-09-20 07:36:05.488144	2023-09-22 13:01:20.628918
1	School_Setup/PortalPolls.php	Y	Y	2023-08-15 14:26:23.165721	2023-08-15 14:26:23.166227
1	School_Setup/Calendar.php	Y	Y	2023-08-15 14:26:23.166934	2023-08-15 14:26:23.167421
1	School_Setup/MarkingPeriods.php	Y	Y	2023-08-15 14:26:23.16791	2023-08-15 14:26:23.168713
1	School_Setup/GradeLevels.php	Y	Y	2023-08-15 14:26:23.170788	2023-08-15 14:26:23.17123
1	School_Setup/Schools.php	Y	Y	2023-08-15 14:26:23.171807	2023-08-15 14:26:23.172259
1	School_Setup/CopySchool.php	Y	Y	2023-08-15 14:26:23.172832	2023-08-15 14:26:23.173281
1	School_Setup/SchoolFields.php	Y	Y	2023-08-15 14:26:23.173808	2023-08-15 14:26:23.174222
1	School_Setup/Configuration.php	Y	Y	2023-08-15 14:26:23.174669	2023-08-15 14:26:23.175116
1	School_Setup/AccessLog.php	Y	Y	2023-08-15 14:26:23.176688	2023-08-15 14:26:23.177117
1	Custom/Registration.php	Y	Y	2023-08-01 22:43:31.104393	2023-08-15 16:45:54.43852
1	Custom/RemoveAccess.php	Y	Y	2023-08-01 22:43:31.104393	2023-08-15 16:45:54.439283
1	Custom/NotifyParents.php	Y	Y	2023-08-01 22:43:31.104393	2023-08-15 16:45:54.450781
1	Wx_Custom/Wx_CustomCourses.php	Y	Y	2024-01-23 21:22:22.836878	\N
1	Wx_Custom/Wx_CustomClasses.php	Y	Y	2024-01-23 21:22:34.83016	\N
1	Wx_Custom/Wx_CustomStudentClassesAllocate.php	Y	Y	2024-01-23 21:22:46.04498	\N
1	Accounting/Categories.php	Y	Y	2023-08-01 22:43:31.104393	2023-08-15 16:45:54.517371
3	Students/Student.php&category_id=3	Y	\N	2023-08-01 22:43:31.104393	\N
3	Students/Student.php&category_id=5	Y	\N	2023-08-05 07:13:02.087599	2023-08-05 07:13:02.088526
3	School_Setup/MarkingPeriods.php	Y	\N	2023-08-01 22:43:31.104393	\N
3	Students/Student.php	Y	\N	2023-08-01 22:43:31.104393	\N
3	Students/Student.php&category_id=1	Y	\N	2023-08-01 22:43:31.104393	\N
2	Grades/GradebookBreakdown.php	Y	\N	2023-08-01 22:43:31.104393	2023-08-04 20:13:28.025511
1	Scheduling/PrintSchedules.php	Y	Y	2023-08-01 22:43:31.104393	2023-08-15 16:45:54.465306
1	Eligibility/TeacherCompletion.php	Y	Y	2023-08-01 22:43:31.104393	2023-08-15 16:45:54.496687
1	Discipline/MakeReferral.php	Y	Y	2023-08-01 22:43:31.104393	2023-08-15 16:45:54.498808
1	Discipline/Referrals.php	Y	Y	2023-08-01 22:43:31.104393	2023-08-15 16:45:54.499347
1	Discipline/CategoryBreakdown.php	Y	Y	2023-08-01 22:43:31.104393	2023-08-15 16:45:54.500227
2	Students/Letters.php	Y	\N	2023-08-01 22:43:31.104393	\N
2	Attendance/TakeAttendance.php	Y	\N	2023-08-01 22:43:31.104393	\N
2	Attendance/DailySummary.php	Y	\N	2023-08-01 22:43:31.104393	\N
2	Eligibility/EnterEligibility.php	Y	\N	2023-08-01 22:43:31.104393	\N
2	Food_Service/DailyMenus.php	Y	\N	2023-08-01 22:43:31.104393	\N
2	Food_Service/MenuItems.php	Y	\N	2023-08-01 22:43:31.104393	\N
2	Students/AdvancedReport.php	Y	\N	2023-08-01 22:43:31.104393	\N
1	Discipline/CategoryBreakdownTime.php	Y	Y	2023-08-01 22:43:31.104393	2023-08-15 16:45:54.500929
1	Discipline/StudentFieldBreakdown.php	Y	Y	2023-08-01 22:43:31.104393	2023-08-15 16:45:54.501536
1	Discipline/ReferralLog.php	Y	Y	2023-08-01 22:43:31.104393	2023-08-15 16:45:54.502098
1	Discipline/DisciplineForm.php	Y	Y	2023-08-01 22:43:31.104393	2023-08-15 16:45:54.502727
1	Student_Billing/StudentFees.php	Y	Y	2023-08-01 22:43:31.104393	2023-08-15 16:45:54.518235
1	Student_Billing/StudentPayments.php	Y	Y	2023-08-01 22:43:31.104393	2023-08-15 16:45:54.5189
1	Student_Billing/MassAssignFees.php	Y	Y	2023-08-01 22:43:31.104393	2023-08-15 16:45:54.519512
1	Student_Billing/MassAssignPayments.php	Y	Y	2023-08-01 22:43:31.104393	2023-08-15 16:45:54.520271
1	Food_Service/MenuReports.php	Y	Y	2023-08-15 16:45:54.532234	2023-08-15 16:45:54.533064
1	Food_Service/Reminders.php	Y	Y	2023-08-15 16:45:54.534536	2023-08-15 16:45:54.535162
1	Food_Service/DailyMenus.php	Y	Y	2023-08-15 16:45:54.535856	2023-08-15 16:45:54.53804
14	Users/AddStudents.php	Y	Y	2023-09-20 07:36:05.490527	2023-09-22 12:22:04.047781
16	Student_Billing/StudentFees.php	Y	Y	2023-10-15 20:51:37.181638	2023-10-15 20:51:37.182082
16	Student_Billing/StudentPayments.php	Y	Y	2023-10-15 20:51:37.182559	2023-10-15 20:51:37.182969
10	School_Setup/Periods.php	Y	\N	2023-09-19 11:51:45.741774	2023-09-19 11:51:45.742382
9	School_Setup/Periods.php	Y	\N	2023-08-15 14:05:32.178583	2023-10-15 20:15:09.407996
9	Students/Student.php&category_id=1	Y	\N	2023-08-15 14:05:32.231038	2023-08-15 14:05:32.23209
9	Students/Student.php&category_id=3	Y	\N	2023-08-15 14:05:32.235088	2023-08-15 14:05:32.236062
9	Students/Student.php&category_id=4	Y	\N	2023-08-15 14:05:32.237006	2023-08-15 14:05:32.247124
9	Users/TeacherPrograms.php&include=Grades/InputFinalGrades.php	Y	\N	2023-08-15 14:05:32.249268	2023-09-19 10:42:09.935007
9	Users/TeacherPrograms.php&include=Grades/Grades.php	Y	\N	2023-08-15 14:05:32.250689	2023-09-19 10:42:09.935522
9	Users/TeacherPrograms.php&include=Grades/AnomalousGrades.php	Y	\N	2023-08-15 14:05:32.251731	2023-09-19 10:42:09.936176
9	Users/TeacherPrograms.php&include=Attendance/TakeAttendance.php	Y	\N	2023-08-15 14:05:32.253027	2023-09-19 10:42:09.936872
9	Users/TeacherPrograms.php&include=Eligibility/EnterEligibility.php	Y	\N	2023-08-15 14:05:32.253879	2023-09-19 10:42:09.937487
9	Scheduling/Schedule.php	Y	\N	2023-08-15 14:05:32.256221	2023-09-19 10:42:09.940592
9	Scheduling/Requests.php	Y	\N	2023-08-15 14:05:32.259675	2023-09-19 10:42:09.941072
9	Scheduling/MassSchedule.php	Y	\N	2023-08-15 14:05:32.260702	2023-09-19 10:42:09.941553
9	Scheduling/MassRequests.php	Y	\N	2023-08-15 14:05:32.263839	2023-09-19 10:42:09.942118
16	Accounting/Salaries.php	Y	Y	2023-10-15 20:51:37.175378	2023-10-15 20:51:37.175852
16	Accounting/DailyTransactions.php	Y	Y	2023-10-15 20:51:37.177441	2023-10-15 20:51:37.178017
16	Accounting/StaffBalances.php	Y	Y	2023-10-15 20:51:37.178607	2023-10-15 20:51:37.179091
16	Accounting/Statements.php	Y	Y	2023-10-15 20:51:37.17966	2023-10-15 20:51:37.180087
16	Accounting/Categories.php	Y	Y	2023-10-15 20:51:37.180766	2023-10-15 20:51:37.181155
16	Accounting/Expenses.php	Y	Y	2023-10-15 20:51:37.174288	2023-10-15 20:51:37.174714
10	School_Setup/Calendar.php	Y	Y	2023-09-19 11:51:45.738832	2024-10-26 17:06:01.658079
10	School_Setup/Schools.php	Y	Y	2023-09-19 11:51:45.744494	2024-10-26 17:06:01.661728
9	Scheduling/MassDrops.php	Y	\N	2023-08-15 14:05:32.264824	2023-09-19 10:42:09.942722
9	Scheduling/PrintSchedules.php	Y	Y	2023-08-15 14:05:32.265673	2023-10-15 20:15:09.433267
9	Scheduling/PrintClassLists.php	Y	Y	2023-08-15 14:05:32.266845	2023-10-15 20:15:09.433682
9	Scheduling/PrintClassPictures.php	Y	\N	2023-08-15 14:05:32.267766	2023-09-19 10:42:09.94426
9	Scheduling/PrintRequests.php	Y	\N	2023-08-15 14:05:32.268763	2023-09-19 10:42:09.944747
9	Scheduling/ScheduleReport.php	Y	\N	2023-08-15 14:05:32.276293	2023-09-19 10:42:09.945214
9	Scheduling/RequestsReport.php	Y	\N	2023-08-15 14:05:32.27796	2023-09-19 10:42:09.945657
9	Scheduling/Courses.php	Y	Y	2023-08-15 14:05:32.281997	2023-10-15 20:15:09.436947
9	Grades/ReportCards.php	Y	\N	2023-08-15 14:05:32.295101	2023-08-15 14:05:32.296044
1	Students/StudentBreakdown.php	Y	Y	2023-08-01 22:43:31.104393	2023-08-13 15:35:19.651864
1	Students/Student.php&category_id=3	Y	Y	2023-08-01 22:43:31.104393	2023-08-13 15:35:19.658607
1	Students/Student.php&category_id=4	Y	Y	2023-08-13 15:35:19.659404	2023-08-13 15:35:19.66022
1	Wx_Custom/Wx_CustomSetupNotes.php	Y	Y	2024-01-23 21:23:07.381125	2024-08-27 13:06:36.072174
1	Student_Billing/StudentPayments.php&modfunc=remove	Y	Y	2023-08-01 22:43:31.104393	2023-08-15 16:45:54.524418
3	Custom/Registration.php	Y	\N	2023-08-01 22:43:31.104393	\N
9	Grades/HonorRoll.php	Y	\N	2023-08-15 14:05:32.296859	2023-08-15 14:05:32.297542
9	Grades/Transcripts.php	Y	\N	2023-08-15 14:05:32.298339	2023-08-15 14:05:32.29899
9	Grades/StudentGrades.php	Y	\N	2023-08-15 14:05:32.299653	2023-08-15 14:05:32.300226
9	Grades/ProgressReports.php	Y	\N	2023-08-15 14:05:32.301045	2023-08-15 14:05:32.302134
9	Grades/TeacherCompletion.php	Y	\N	2023-08-15 14:05:32.303197	2023-08-15 14:05:32.304225
9	Grades/GradeBreakdown.php	Y	\N	2023-08-15 14:05:32.305361	2023-08-15 14:05:32.30686
1	Wx_Custom/Setup.php	Y	Y	2024-01-23 21:24:19.800078	\N
9	Grades/FinalGrades.php	Y	\N	2023-08-15 14:05:32.307535	2023-08-15 14:05:32.308375
0	Wx_Custom/Resources.php	Y	\N	2024-01-23 21:24:30.946425	\N
9	Grades/GPARankList.php	Y	\N	2023-08-15 14:05:32.309272	2023-08-15 14:05:32.313051
9	Attendance/Administration.php	Y	\N	2023-08-15 14:05:32.345256	2023-08-15 14:05:32.345805
0	Wx_Custom/Wx_CustomCourses.php	Y	\N	2024-01-23 21:24:41.690241	\N
9	Attendance/AddAbsences.php	Y	\N	2023-08-15 14:05:32.346354	2023-08-15 14:05:32.346843
9	Attendance/TeacherCompletion.php	Y	\N	2023-08-15 14:05:32.347413	2023-08-15 14:05:32.347902
9	Attendance/Percent.php	Y	\N	2023-08-15 14:05:32.348471	2023-08-15 14:05:32.348995
0	Wx_Custom/Wx_CustomClasses.php	Y	\N	2024-01-23 21:24:51.523675	\N
9	Attendance/DailySummary.php	Y	\N	2023-08-15 14:05:32.34956	2023-08-15 14:05:32.350038
9	Attendance/FixDailyAttendance.php	Y	\N	2023-08-15 14:05:32.350573	2023-08-15 14:05:32.351057
9	Attendance/DuplicateAttendance.php	Y	\N	2023-08-15 14:05:32.351661	2023-08-15 14:05:32.352172
9	Attendance/AttendanceCodes.php	Y	\N	2023-08-15 14:05:32.35271	2023-08-15 14:05:32.353464
9	Student_Billing/StudentFees.php	Y	\N	2023-08-15 14:05:32.364117	2023-08-15 14:05:32.364568
9	Student_Billing/StudentPayments.php	Y	\N	2023-08-15 14:05:32.365073	2023-08-15 14:05:32.365769
9	Student_Billing/MassAssignFees.php	Y	\N	2023-08-15 14:05:32.366371	2023-08-15 14:05:32.366939
9	Student_Billing/MassAssignPayments.php	Y	\N	2023-08-15 14:05:32.367615	2023-08-15 14:05:32.369898
9	Student_Billing/StudentBalances.php	Y	\N	2023-08-15 14:05:32.370534	2023-08-15 14:05:32.371002
0	Wx_Custom/Wx_CustomSchedule.php	Y	\N	2024-01-23 21:25:04.097972	\N
0	Wx_Custom/Wx_CustomSchoolRepportStudent.php	Y	\N	2024-01-23 21:25:14.239793	\N
0	Wx_Custom/Wx_CustomSchoolRepportClasses.php	Y	\N	2024-01-23 21:25:25.325392	\N
0	Wx_Custom/Setup.php	Y	\N	2024-01-23 21:25:36.757233	\N
2	Wx_Custom/Resources.php	Y	\N	2024-01-23 21:25:51.842199	\N
2	Wx_Custom/Wx_CustomCourses.php	Y	\N	2024-01-23 21:26:01.275841	\N
2	Wx_Custom/Wx_CustomClasses.php	Y	\N	2024-01-23 21:26:13.652153	\N
2	Wx_Custom/Setup.php	Y	\N	2024-01-23 21:27:06.298745	\N
3	Wx_Custom/Resources.php	Y	\N	2024-01-23 21:27:18.665459	\N
3	Wx_Custom/Wx_CustomCourses.php	Y	\N	2024-01-23 21:27:29.514816	\N
3	Wx_Custom/Wx_CustomClasses.php	Y	\N	2024-01-23 21:27:38.209769	\N
3	Wx_Custom/Wx_CustomSchedule.php	Y	\N	2024-01-23 21:27:48.470875	\N
9	School_Setup/PortalPolls.php	Y	\N	2023-08-15 14:05:32.167638	2023-10-15 20:15:09.406084
9	School_Setup/Calendar.php	Y	\N	2023-08-15 14:05:32.174818	2023-10-15 20:15:09.406788
9	School_Setup/MarkingPeriods.php	Y	\N	2023-08-15 14:05:32.177165	2023-10-15 20:15:09.407448
9	School_Setup/GradeLevels.php	Y	\N	2023-08-15 14:05:32.183392	2023-10-15 20:15:09.408564
9	School_Setup/Schools.php	Y	Y	2023-08-15 14:05:32.184532	2023-08-15 14:05:32.18503
9	School_Setup/CopySchool.php	Y	\N	2023-08-15 14:05:32.185536	2023-10-15 20:15:09.409628
9	School_Setup/SchoolFields.php	Y	\N	2023-08-15 14:05:32.186855	2023-10-15 20:15:09.410123
9	School_Setup/Configuration.php	Y	\N	2023-08-15 14:05:32.187856	2023-10-15 20:15:09.41064
9	School_Setup/Rollover.php	Y	\N	2023-08-15 14:05:32.189173	2023-10-15 20:15:09.411119
9	School_Setup/AccessLog.php	Y	\N	2023-08-15 14:05:32.190371	2023-10-15 20:15:09.411606
9	School_Setup/DatabaseBackup.php	Y	\N	2023-08-15 14:05:32.191669	2023-10-15 20:15:09.412068
9	Students/Student.php	Y	\N	2023-08-15 14:05:32.192914	2023-08-15 14:05:32.193442
9	Students/AssignOtherInfo.php	Y	\N	2023-08-15 14:05:32.196051	2023-08-15 14:05:32.196685
9	Students/AddUsers.php	Y	\N	2023-08-15 14:05:32.197394	2023-08-15 14:05:32.197918
9	Students/AdvancedReport.php	Y	Y	2023-08-15 14:05:32.198616	2023-10-15 20:15:09.41501
9	Students/AddDrop.php	Y	\N	2023-08-15 14:05:32.203843	2023-08-15 14:05:32.204649
9	Students/StudentBreakdown.php	Y	\N	2023-08-15 14:05:32.205874	2023-08-15 14:05:32.206447
9	Students/Letters.php	Y	\N	2023-08-15 14:05:32.207005	2023-08-15 14:05:32.207773
9	Students/StudentLabels.php	Y	\N	2023-08-15 14:05:32.208639	2023-08-15 14:05:32.209271
9	Students/PrintStudentInfo.php	Y	Y	2023-08-15 14:05:32.209845	2023-10-15 20:15:09.41723
2	School_Setup/Periods.php	Y	\N	2023-08-09 17:05:17.14573	2023-08-09 17:05:17.148025
9	Custom/AttendanceSummary.php	Y	\N	2023-09-19 10:42:09.96035	2023-09-19 10:42:09.961093
9	Accounting/Incomes.php	Y	\N	2023-09-19 10:42:09.967353	2023-09-19 10:42:09.967858
13	Scheduling/PrintRequests.php	Y	\N	2023-09-17 10:47:24.379846	2023-09-17 10:47:24.380357
13	Scheduling/ScheduleReport.php	Y	\N	2023-09-17 10:47:24.380902	2023-09-17 10:47:24.381425
13	School_Setup/PortalNotes.php	Y	\N	2023-09-17 10:47:24.338342	2023-09-17 10:47:24.339652
13	School_Setup/PortalPolls.php	Y	\N	2023-09-17 10:47:24.342565	2023-09-17 10:47:24.343063
13	School_Setup/Calendar.php	Y	\N	2023-09-17 10:47:24.343556	2023-09-17 10:47:24.344095
13	School_Setup/MarkingPeriods.php	Y	\N	2023-09-17 10:47:24.344748	2023-09-17 10:47:24.3453
13	School_Setup/Periods.php	Y	\N	2023-09-17 10:47:24.345819	2023-09-17 10:47:24.346302
13	School_Setup/GradeLevels.php	Y	\N	2023-09-17 10:47:24.346833	2023-09-17 10:47:24.347234
13	School_Setup/Schools.php	Y	\N	2023-09-17 10:47:24.347708	2023-09-17 10:47:24.348073
13	School_Setup/CopySchool.php	Y	\N	2023-09-17 10:47:24.348882	2023-09-17 10:47:24.349503
13	School_Setup/SchoolFields.php	Y	\N	2023-09-17 10:47:24.350031	2023-09-17 10:47:24.350535
13	School_Setup/Configuration.php	Y	\N	2023-09-17 10:47:24.351151	2023-09-17 10:47:24.351903
13	School_Setup/Rollover.php	Y	\N	2023-09-17 10:47:24.352444	2023-09-17 10:47:24.353104
13	School_Setup/AccessLog.php	Y	\N	2023-09-17 10:47:24.353709	2023-09-17 10:47:24.354138
13	School_Setup/DatabaseBackup.php	Y	\N	2023-09-17 10:47:24.354647	2023-09-17 10:47:24.355063
13	Students/Student.php	Y	\N	2023-09-17 10:47:24.355537	2023-09-17 10:47:24.356005
3	Wx_Custom/Setup.php	Y	\N	2024-01-23 21:28:21.070576	\N
2	Wx_Custom/Wx_CustomSchoolRepportStudent.php	Y	\N	2024-01-23 21:26:47.058761	\N
2	Wx_Custom/Wx_CustomSchedule.php	Y	\N	2024-01-23 21:26:26.146079	\N
1	Wx_Custom/Wx_CustomSetupNotes.php&modfunc=update_method_evaluation_student	Y	Y	2024-01-23 21:23:20.317983	\N
13	Students/Student.php&include=General_Info&student_id=new	Y	\N	2023-09-17 10:47:24.356508	2023-09-17 10:47:24.357473
13	Students/AssignOtherInfo.php	Y	\N	2023-09-17 10:47:24.358037	2023-09-17 10:47:24.358502
13	Students/AddUsers.php	Y	\N	2023-09-17 10:47:24.359151	2023-09-17 10:47:24.359609
13	Students/AdvancedReport.php	Y	\N	2023-09-17 10:47:24.360156	2023-09-17 10:47:24.360588
13	Students/AddDrop.php	Y	\N	2023-09-17 10:47:24.361098	2023-09-17 10:47:24.361577
13	Students/StudentBreakdown.php	Y	\N	2023-09-17 10:47:24.362074	2023-09-17 10:47:24.362604
13	Students/Letters.php	Y	\N	2023-09-17 10:47:24.363086	2023-09-17 10:47:24.363483
9	Student_Billing/DailyTransactions.php	Y	\N	2023-08-15 14:05:32.379139	2023-08-15 14:05:32.379998
9	Student_Billing/Statements.php	Y	\N	2023-08-15 14:05:32.380993	2023-08-15 14:05:32.381738
16	Student_Billing/StudentBalances.php	Y	Y	2023-10-15 20:51:37.18563	2023-10-15 20:51:37.186065
16	Student_Billing/DailyTransactions.php	Y	Y	2023-10-15 20:51:37.186528	2023-10-15 20:51:37.186991
1	Wx_Custom/Wx_CustomNotes.php	Y	Y	2024-01-23 21:23:44.442765	\N
1	Wx_Custom/Wx_CustomSchoolRepportClasses.php	Y	Y	2024-01-23 21:24:08.003574	\N
1	Wx_Custom/Wx_CustomSchoolRepportStudent.php	Y	Y	2024-01-23 21:23:57.10403	\N
3	Wx_Custom/Wx_CustomSchoolRepportStudent.php	Y	\N	2024-01-23 21:28:02.814537	\N
3	School_Setup/Schools.php	Y	\N	2023-08-01 22:43:31.104393	\N
3	Students/Student.php&category_id=4	Y	\N	2023-08-09 17:05:45.056486	2023-08-09 17:05:45.057093
3	Wx_Custom/Wx_CustomSchoolRepportClasses.php	Y	\N	2024-01-23 21:28:11.942233	\N
13	Students/StudentLabels.php	Y	\N	2023-09-17 10:47:24.363948	2023-09-17 10:47:24.364492
13	Students/PrintStudentInfo.php	Y	\N	2023-09-17 10:47:24.365013	2023-09-17 10:47:24.365455
13	Students/StudentFields.php	Y	\N	2023-09-17 10:47:24.365921	2023-09-17 10:47:24.366326
13	Students/EnrollmentCodes.php	Y	\N	2023-09-17 10:47:24.36683	2023-09-17 10:47:24.367335
13	Students/Student.php&category_id=1	Y	\N	2023-09-17 10:47:24.367803	2023-09-17 10:47:24.368259
13	Students/Student.php&category_id=2	Y	\N	2023-09-17 10:47:24.36871	2023-09-17 10:47:24.369178
13	Students/Student.php&category_id=3	Y	\N	2023-09-17 10:47:24.369735	2023-09-17 10:47:24.370188
13	Students/Student.php&category_id=4	Y	\N	2023-09-17 10:47:24.370697	2023-09-17 10:47:24.371098
13	Students/Student.php&category_id=5	Y	\N	2023-09-17 10:47:24.371667	2023-09-17 10:47:24.372289
13	Scheduling/Schedule.php	Y	\N	2023-09-17 10:47:24.372855	2023-09-17 10:47:24.37333
13	Scheduling/Requests.php	Y	\N	2023-09-17 10:47:24.373795	2023-09-17 10:47:24.374205
13	Scheduling/MassSchedule.php	Y	\N	2023-09-17 10:47:24.374662	2023-09-17 10:47:24.375042
13	Scheduling/MassRequests.php	Y	\N	2023-09-17 10:47:24.375459	2023-09-17 10:47:24.375849
13	Scheduling/MassDrops.php	Y	\N	2023-09-17 10:47:24.37624	2023-09-17 10:47:24.376609
13	Scheduling/PrintSchedules.php	Y	\N	2023-09-17 10:47:24.377033	2023-09-17 10:47:24.377511
13	Scheduling/PrintClassLists.php	Y	\N	2023-09-17 10:47:24.37803	2023-09-17 10:47:24.378455
13	Scheduling/PrintClassPictures.php	Y	\N	2023-09-17 10:47:24.37896	2023-09-17 10:47:24.379368
13	Scheduling/RequestsReport.php	Y	\N	2023-09-17 10:47:24.381927	2023-09-17 10:47:24.382412
13	Scheduling/IncompleteSchedules.php	Y	\N	2023-09-17 10:47:24.38289	2023-09-17 10:47:24.383306
13	Scheduling/AddDrop.php	Y	\N	2023-09-17 10:47:24.383725	2023-09-17 10:47:24.384192
13	Scheduling/Courses.php	Y	\N	2023-09-17 10:47:24.384898	2023-09-17 10:47:24.385466
13	Scheduling/Scheduler.php	Y	\N	2023-09-17 10:47:24.386051	2023-09-17 10:47:24.386578
13	Grades/ReportCards.php	Y	\N	2023-09-17 10:47:24.387295	2023-09-17 10:47:24.388211
13	Grades/HonorRoll.php	Y	\N	2023-09-17 10:47:24.388777	2023-09-17 10:47:24.389363
13	Grades/Transcripts.php	Y	\N	2023-09-17 10:47:24.389805	2023-09-17 10:47:24.390176
13	Grades/StudentGrades.php	Y	\N	2023-09-17 10:47:24.390647	2023-09-17 10:47:24.391026
16	Student_Billing/Statements.php	Y	Y	2023-10-15 20:51:37.187518	2023-10-15 20:51:37.187971
13	Grades/ProgressReports.php	Y	\N	2023-09-17 10:47:24.391474	2023-09-17 10:47:24.391826
13	Grades/TeacherCompletion.php	Y	\N	2023-09-17 10:47:24.392268	2023-09-17 10:47:24.392727
13	Grades/GradeBreakdown.php	Y	\N	2023-09-17 10:47:24.393279	2023-09-17 10:47:24.393735
13	Grades/FinalGrades.php	Y	\N	2023-09-17 10:47:24.394224	2023-09-17 10:47:24.394668
13	Grades/GPARankList.php	Y	\N	2023-09-17 10:47:24.39536	2023-09-17 10:47:24.395847
13	Grades/Configuration.php	Y	\N	2023-09-17 10:47:24.396363	2023-09-17 10:47:24.396968
13	Grades/ReportCardGrades.php	Y	\N	2023-09-17 10:47:24.397871	2023-09-17 10:47:24.398341
13	Grades/ReportCardComments.php	Y	\N	2023-09-17 10:47:24.398926	2023-09-17 10:47:24.399405
13	Grades/ReportCardCommentCodes.php	Y	\N	2023-09-17 10:47:24.39992	2023-09-17 10:47:24.400282
13	Grades/EditHistoryMarkingPeriods.php	Y	\N	2023-09-17 10:47:24.400684	2023-09-17 10:47:24.401488
13	Grades/EditReportCardGrades.php	Y	\N	2023-09-17 10:47:24.401961	2023-09-17 10:47:24.402358
13	Grades/MassCreateAssignments.php	Y	\N	2023-09-17 10:47:24.402805	2023-09-17 10:47:24.403172
13	Attendance/Administration.php	Y	\N	2023-09-17 10:47:24.403651	2023-09-17 10:47:24.404054
13	Attendance/AddAbsences.php	Y	\N	2023-09-17 10:47:24.4046	2023-09-17 10:47:24.404966
13	Attendance/TeacherCompletion.php	Y	\N	2023-09-17 10:47:24.405435	2023-09-17 10:47:24.405967
13	Attendance/Percent.php	Y	\N	2023-09-17 10:47:24.406476	2023-09-17 10:47:24.406857
13	Attendance/DailySummary.php	Y	\N	2023-09-17 10:47:24.407284	2023-09-17 10:47:24.40764
13	Attendance/FixDailyAttendance.php	Y	\N	2023-09-17 10:47:24.408035	2023-09-17 10:47:24.40844
13	Attendance/DuplicateAttendance.php	Y	\N	2023-09-17 10:47:24.408878	2023-09-17 10:47:24.409287
13	Attendance/AttendanceCodes.php	Y	\N	2023-09-17 10:47:24.409956	2023-09-17 10:47:24.410379
13	Discipline/MakeReferral.php	Y	\N	2023-09-17 10:47:24.410992	2023-09-17 10:47:24.411412
13	Discipline/Referrals.php	Y	\N	2023-09-17 10:47:24.411846	2023-09-17 10:47:24.412247
13	Discipline/CategoryBreakdown.php	Y	\N	2023-09-17 10:47:24.412743	2023-09-17 10:47:24.413394
13	Discipline/CategoryBreakdownTime.php	Y	\N	2023-09-17 10:47:24.413904	2023-09-17 10:47:24.414371
13	Discipline/StudentFieldBreakdown.php	Y	\N	2023-09-17 10:47:24.414901	2023-09-17 10:47:24.415429
13	Discipline/ReferralLog.php	Y	\N	2023-09-17 10:47:24.416613	2023-09-17 10:47:24.417118
13	Discipline/DisciplineForm.php	Y	\N	2023-09-17 10:47:24.417869	2023-09-17 10:47:24.418288
1	Users/TeacherPrograms.php&include=Grades/InputFinalGrades.php	Y	Y	2023-08-01 22:43:31.104393	2023-08-13 15:35:19.669192
1	Users/TeacherPrograms.php&include=Grades/Grades.php	Y	Y	2023-08-01 22:43:31.104393	2023-08-13 15:35:19.669832
16	Student_Billing/MassAssignFees.php	Y	Y	2023-10-15 20:51:37.183492	2023-10-15 20:51:37.184003
16	Student_Billing/MassAssignPayments.php	Y	Y	2023-10-15 20:51:37.184625	2023-10-15 20:51:37.185131
9	Accounting/Statements.php	Y	\N	2023-09-19 10:42:09.97381	2023-09-19 10:42:09.974272
9	Accounting/Expenses.php	Y	\N	2023-09-19 10:42:09.968433	2023-09-19 10:42:09.96902
9	Accounting/Salaries.php	Y	\N	2023-09-19 10:42:09.969589	2023-09-19 10:42:09.970071
3	Scheduling/Requests.php	Y	\N	2023-08-09 17:07:03.107096	2023-08-09 17:07:03.107504
9	Accounting/Categories.php	Y	\N	2023-09-19 10:42:09.974773	2023-09-19 10:42:09.975169
9	Student_Billing/StudentPayments.php&modfunc=remove	Y	\N	2023-08-15 14:05:32.382674	2023-08-15 14:05:32.383495
9	Accounting/StaffPayments.php	Y	\N	2023-09-19 10:42:09.970655	2023-09-19 10:42:09.971176
9	Accounting/DailyTransactions.php	Y	\N	2023-09-19 10:42:09.971759	2023-09-19 10:42:09.972359
9	Accounting/StaffBalances.php	Y	\N	2023-09-19 10:42:09.972882	2023-09-19 10:42:09.973314
10	Students/Student.php&category_id=1	Y	Y	2023-09-19 11:51:45.758827	2024-08-19 13:47:46.204382
10	Students/Student.php&category_id=4	Y	Y	2023-09-19 11:51:45.762584	2024-08-19 13:47:46.208251
10	Students/Student.php&category_id=3	Y	Y	2023-09-19 11:51:45.761605	2024-08-19 13:47:46.207876
10	Students/Student.php&category_id=2	Y	Y	2023-09-19 11:51:45.7605	2024-08-19 13:47:46.207486
10	Students/Student.php&category_id=5	Y	Y	2023-09-19 11:51:45.76354	2024-08-19 13:47:46.208617
16	School_Setup/Calendar.php	Y	\N	2023-10-15 20:52:45.074228	2023-10-15 20:52:45.075311
10	Users/TeacherPrograms.php&include=Grades/InputFinalGrades.php	Y	\N	2023-09-19 11:51:45.770156	2023-09-19 11:51:45.770727
10	Users/TeacherPrograms.php&include=Grades/Grades.php	Y	\N	2023-09-19 11:51:45.771333	2023-09-19 11:51:45.771909
10	Users/TeacherPrograms.php&include=Grades/AnomalousGrades.php	Y	\N	2023-09-19 11:51:45.772762	2023-09-19 11:51:45.773447
3	Students/Student.php&category_id=2	Y	Y	2023-08-09 17:07:03.101792	2023-10-12 09:32:03.827201
10	Users/TeacherPrograms.php&include=Attendance/TakeAttendance.php	Y	\N	2023-09-19 11:51:45.774151	2023-09-19 11:51:45.774949
10	School_Setup/Rollover.php	Y	\N	2023-09-19 11:51:45.749831	2023-09-19 11:51:45.750466
10	Grades/MassCreateAssignments.php	Y	\N	2023-09-19 11:51:45.805145	2023-09-19 11:51:45.80552
10	Attendance/Administration.php	Y	\N	2023-09-19 11:51:45.805971	2023-09-19 11:51:45.806388
10	Attendance/AddAbsences.php	Y	\N	2023-09-19 11:51:45.806814	2023-09-19 11:51:45.80724
10	Attendance/TeacherCompletion.php	Y	\N	2023-09-19 11:51:45.807749	2023-09-19 11:51:45.808123
10	Attendance/Percent.php	Y	\N	2023-09-19 11:51:45.808536	2023-09-19 11:51:45.808894
10	Attendance/DailySummary.php	Y	\N	2023-09-19 11:51:45.809358	2023-09-19 11:51:45.809919
10	Attendance/FixDailyAttendance.php	Y	\N	2023-09-19 11:51:45.810486	2023-09-19 11:51:45.811092
10	Attendance/DuplicateAttendance.php	Y	\N	2023-09-19 11:51:45.811734	2023-09-19 11:51:45.812235
10	Attendance/AttendanceCodes.php	Y	\N	2023-09-19 11:51:45.812764	2023-09-19 11:51:45.81326
10	Discipline/MakeReferral.php	Y	\N	2023-09-19 11:51:45.813927	2023-09-19 11:51:45.814607
10	Discipline/Referrals.php	Y	\N	2023-09-19 11:51:45.815207	2023-09-19 11:51:45.815718
10	Discipline/CategoryBreakdown.php	Y	\N	2023-09-19 11:51:45.816318	2023-09-19 11:51:45.816811
10	Discipline/CategoryBreakdownTime.php	Y	\N	2023-09-19 11:51:45.817305	2023-09-19 11:51:45.817772
10	Discipline/StudentFieldBreakdown.php	Y	\N	2023-09-19 11:51:45.81834	2023-09-19 11:51:45.818736
10	Discipline/ReferralLog.php	Y	\N	2023-09-19 11:51:45.819376	2023-09-19 11:51:45.820051
10	Student_Billing/StudentPayments.php	Y	\N	2023-09-19 11:51:45.831291	2023-09-19 11:51:45.831821
10	Student_Billing/MassAssignFees.php	Y	\N	2023-09-19 11:51:45.832408	2023-09-19 11:51:45.832956
10	Student_Billing/MassAssignPayments.php	Y	\N	2023-09-19 11:51:45.833579	2023-09-19 11:51:45.834499
10	Student_Billing/StudentBalances.php	Y	\N	2023-09-19 11:51:45.835038	2023-09-19 11:51:45.835466
10	Student_Billing/DailyTransactions.php	Y	\N	2023-09-19 11:51:45.83597	2023-09-19 11:51:45.836526
10	Student_Billing/Statements.php	Y	\N	2023-09-19 11:51:45.837079	2023-09-19 11:51:45.837545
14	Students/AdvancedReport.php	Y	\N	2023-09-20 07:36:05.474565	2023-09-30 14:45:56.55004
14	Students/StudentBreakdown.php	Y	\N	2023-09-20 07:36:05.476843	2023-09-30 14:45:56.550629
14	Students/Student.php&category_id=2	Y	\N	2023-09-20 07:36:05.484403	2023-09-20 07:36:05.484809
14	Students/Student.php&category_id=3	Y	Y	2023-09-20 07:36:05.485289	2023-10-15 20:50:12.186409
14	Users/User.php&staff_id=new	Y	Y	2023-10-23 09:53:01.566245	2023-10-23 09:53:01.567339
14	School_Setup/Schools.php	Y	Y	2023-09-20 07:36:05.463191	2023-10-15 20:50:12.178154
10	Scheduling/Schedule.php	Y	\N	2023-09-19 11:51:45.78321	2023-09-19 11:51:45.783723
10	Scheduling/MassSchedule.php	Y	\N	2023-09-19 11:51:45.784251	2023-09-19 11:51:45.784678
10	Scheduling/PrintSchedules.php	Y	\N	2023-09-19 11:51:45.78514	2023-09-19 11:51:45.785562
10	Scheduling/PrintClassLists.php	Y	\N	2023-09-19 11:51:45.78603	2023-09-19 11:51:45.786465
10	Scheduling/PrintClassPictures.php	Y	\N	2023-09-19 11:51:45.786917	2023-09-19 11:51:45.787336
10	Scheduling/ScheduleReport.php	Y	\N	2023-09-19 11:51:45.787834	2023-09-19 11:51:45.788246
10	Scheduling/IncompleteSchedules.php	Y	\N	2023-09-19 11:51:45.788799	2023-09-19 11:51:45.78919
10	Scheduling/AddDrop.php	Y	\N	2023-09-19 11:51:45.789627	2023-09-19 11:51:45.790003
10	Scheduling/Courses.php	Y	\N	2023-09-19 11:51:45.790503	2023-09-19 11:51:45.790905
10	Scheduling/Scheduler.php	Y	\N	2023-09-19 11:51:45.791359	2023-09-19 11:51:45.791939
10	Grades/ReportCards.php	Y	\N	2023-09-19 11:51:45.792473	2023-09-19 11:51:45.792945
10	Grades/HonorRoll.php	Y	\N	2023-09-19 11:51:45.793479	2023-09-19 11:51:45.793951
10	Discipline/DisciplineForm.php	Y	\N	2023-09-19 11:51:45.820591	2023-09-19 11:51:45.821002
14	Students/Student.php	Y	Y	2023-09-20 07:36:05.470124	2023-10-15 20:50:12.181594
14	Students/AssignOtherInfo.php	Y	\N	2023-09-20 07:36:05.472166	2023-09-30 14:45:56.54889
14	Students/AddUsers.php	Y	Y	2023-09-20 07:36:05.473268	2023-10-15 20:50:12.183184
14	Students/PrintStudentInfo.php	Y	Y	2023-09-20 07:36:05.479701	2023-10-15 20:50:12.184758
14	Students/Student.php&category_id=1	Y	Y	2023-09-20 07:36:05.483497	2023-10-15 20:50:12.185265
14	Students/Student.php&category_id=4	Y	\N	2023-09-20 07:36:05.486239	2023-09-30 14:45:56.55416
14	Students/Student.php&category_id=5	Y	\N	2023-09-20 07:36:05.487175	2023-09-30 14:45:56.554761
10	Users/TeacherPrograms.php&include=Eligibility/EnterEligibility.php	Y	\N	2023-09-19 11:51:45.77568	2023-09-19 11:51:45.776591
10	Grades/Transcripts.php	Y	\N	2023-09-19 11:51:45.794503	2023-09-19 11:51:45.794998
10	Grades/StudentGrades.php	Y	\N	2023-09-19 11:51:45.795595	2023-09-19 11:51:45.7961
10	Grades/ProgressReports.php	Y	\N	2023-09-19 11:51:45.79659	2023-09-19 11:51:45.796977
10	Grades/TeacherCompletion.php	Y	\N	2023-09-19 11:51:45.797427	2023-09-19 11:51:45.797827
10	Grades/GradeBreakdown.php	Y	\N	2023-09-19 11:51:45.798305	2023-09-19 11:51:45.798975
10	Grades/FinalGrades.php	Y	\N	2023-09-19 11:51:45.799611	2023-09-19 11:51:45.800122
10	Grades/GPARankList.php	Y	\N	2023-09-19 11:51:45.800682	2023-09-19 11:51:45.801254
10	Grades/ReportCardComments.php	Y	\N	2023-09-19 11:51:45.801989	2023-09-19 11:51:45.802605
10	Students/AssignOtherInfo.php	Y	Y	2023-09-19 11:51:45.755968	2024-08-19 13:47:46.192577
10	Users/User.php	Y	Y	2023-09-19 11:51:45.764573	2024-08-17 23:14:34.150439
10	Users/Preferences.php	Y	Y	2023-09-19 11:51:45.767973	2024-08-14 13:07:46.064138
10	Accounting/Incomes.php	Y	\N	2023-09-19 11:51:45.821618	2023-09-19 11:51:45.82205
10	Accounting/Expenses.php	Y	\N	2023-09-19 11:51:45.822606	2023-09-19 11:51:45.823099
10	Accounting/Salaries.php	Y	\N	2023-09-19 11:51:45.823699	2023-09-19 11:51:45.824174
10	Accounting/StaffPayments.php	Y	\N	2023-09-19 11:51:45.824724	2023-09-19 11:51:45.825312
10	Accounting/DailyTransactions.php	Y	\N	2023-09-19 11:51:45.826111	2023-09-19 11:51:45.826973
10	Accounting/StaffBalances.php	Y	\N	2023-09-19 11:51:45.82761	2023-09-19 11:51:45.828098
10	School_Setup/Configuration.php	Y	Y	2023-09-19 11:51:45.748588	2023-09-19 12:04:01.731004
10	School_Setup/AccessLog.php	Y	Y	2023-09-19 11:51:45.751154	2024-10-26 17:06:01.665076
16	Accounting/StaffPayments.php	Y	Y	2023-10-15 20:51:37.176394	2023-10-15 20:51:37.176868
10	Students/Student.php	Y	Y	2023-09-19 11:51:45.75338	2024-08-19 13:47:46.191769
10	Students/Student.php&include=General_Info&student_id=new	Y	Y	2023-09-19 11:51:45.754531	2024-08-19 13:47:46.192206
16	School_Setup/Schools.php	Y	\N	2023-10-15 20:52:45.077983	2023-10-15 20:52:45.078442
10	Student_Billing/StudentFees.php	Y	\N	2023-09-19 11:51:45.830357	2023-09-19 11:51:45.830727
10	Grades/EditHistoryMarkingPeriods.php	Y	\N	2023-09-19 11:51:45.803344	2023-09-19 11:51:45.803838
14	School_Setup/PortalNotes.php	Y	Y	2023-09-20 07:36:05.454207	2023-10-15 20:50:12.171677
10	Grades/EditReportCardGrades.php	Y	\N	2023-09-19 11:51:45.804266	2023-09-19 11:51:45.804707
14	School_Setup/PortalPolls.php	Y	\N	2023-09-20 07:36:05.458	2023-09-30 14:33:55.277581
14	School_Setup/Calendar.php	Y	\N	2023-09-20 07:36:05.459462	2023-09-21 07:13:13.386598
14	School_Setup/MarkingPeriods.php	Y	\N	2023-09-20 07:36:05.46044	2023-09-21 07:13:13.387179
14	School_Setup/Periods.php	Y	\N	2023-09-20 07:36:05.461384	2023-09-21 07:13:13.387734
14	School_Setup/GradeLevels.php	Y	\N	2023-09-20 07:36:05.462249	2023-09-21 07:13:13.388234
14	Accounting/Categories.php	Y	Y	2023-09-20 07:36:05.503494	2023-09-20 07:36:05.503871
14	Student_Billing/StudentFees.php	Y	Y	2023-09-20 07:36:05.504316	2023-09-20 07:36:05.504694
14	Student_Billing/StudentPayments.php	Y	Y	2023-09-20 07:36:05.505123	2023-09-20 07:36:05.505516
14	Student_Billing/MassAssignFees.php	Y	Y	2023-09-20 07:36:05.506637	2023-09-20 07:36:05.507047
14	Student_Billing/MassAssignPayments.php	Y	Y	2023-09-20 07:36:05.507504	2023-09-20 07:36:05.507933
14	Student_Billing/StudentBalances.php	Y	Y	2023-09-20 07:36:05.508794	2023-09-20 07:36:05.509284
14	Student_Billing/DailyTransactions.php	Y	Y	2023-09-20 07:36:05.50985	2023-09-20 07:36:05.510252
14	Student_Billing/Statements.php	Y	Y	2023-09-20 07:36:05.510698	2023-09-20 07:36:05.511074
14	Student_Billing/StudentPayments.php&modfunc=remove	Y	Y	2023-09-20 07:36:05.51153	2023-09-20 07:36:05.511911
14	Students/Student.php&include=General_Info&student_id=new	Y	Y	2023-09-20 07:36:05.471101	2023-10-15 20:50:12.182195
14	Users/User.php&category_id=1	Y	Y	2023-09-20 07:36:05.493761	2023-10-23 09:57:17.639083
14	Accounting/Incomes.php	Y	Y	2023-09-20 07:36:05.497376	2023-09-20 07:36:05.497723
14	Accounting/Expenses.php	Y	Y	2023-09-20 07:36:05.498139	2023-09-20 07:36:05.498511
14	Accounting/Salaries.php	Y	Y	2023-09-20 07:36:05.498915	2023-09-20 07:36:05.499341
14	Accounting/StaffPayments.php	Y	Y	2023-09-20 07:36:05.500132	2023-09-20 07:36:05.500544
14	Accounting/DailyTransactions.php	Y	Y	2023-09-20 07:36:05.501012	2023-09-20 07:36:05.501411
14	Accounting/StaffBalances.php	Y	Y	2023-09-20 07:36:05.501865	2023-09-20 07:36:05.50225
14	Accounting/Statements.php	Y	Y	2023-09-20 07:36:05.50269	2023-09-20 07:36:05.503044
0	Student_Billing/StudentFees.php	Y	\N	2023-09-21 20:19:04.135605	2023-09-21 20:19:04.136196
0	Student_Billing/StudentPayments.php	Y	\N	2023-09-21 20:19:04.136854	2023-09-21 20:19:04.137367
0	Student_Billing/DailyTransactions.php	Y	\N	2023-09-21 20:19:04.137876	2023-09-21 20:19:04.138326
0	Student_Billing/Statements.php&_ROSARIO_PDF	Y	\N	2023-09-21 20:19:04.138856	2023-09-21 20:19:04.139368
14	School_Setup/CopySchool.php	Y	\N	2023-09-30 14:33:55.292957	2023-09-30 14:33:55.293749
14	School_Setup/SchoolFields.php	Y	\N	2023-09-30 14:33:55.294355	2023-09-30 14:33:55.294907
14	School_Setup/Configuration.php	Y	\N	2023-09-30 14:33:55.295495	2023-09-30 14:33:55.296053
14	Attendance/Administration.php	Y	Y	2023-09-30 14:33:55.309396	2023-10-15 20:50:12.189823
14	Attendance/AddAbsences.php	Y	Y	2023-09-30 14:33:55.310324	2023-10-15 20:50:12.190368
2	Grades/GPARankList.php	Y	\N	2023-09-22 12:25:44.524607	2023-09-22 12:25:44.525068
0	Wx_CustomStudentSchedule.php	Y	Y	2024-08-01 22:31:57.742004	\N
0	Wx_Custom/Wx_CustomStudentSchedule.php	Y	Y	2024-08-01 22:40:43.4276	\N
10	Wx_Custom/FacturationEleves/Soldes.php	Y	Y	2024-08-03 20:26:31.45771	2024-10-26 17:06:01.693667
10	Wx_Custom/FacturationEleves/TransactionsPeriodiques.php	Y	Y	2024-08-03 20:26:31.458399	2024-10-26 17:06:01.694066
10	Wx_Custom/FacturationEleves/Statements.php	Y	Y	2024-08-03 20:26:31.459074	2024-10-26 17:06:01.69447
10	School_Setup/GradeLevels.php	Y	Y	2023-09-19 12:18:38.368459	2024-10-26 17:06:01.661277
10	Accounting/Statements.php	Y	\N	2023-09-19 11:51:45.8286	2023-09-19 11:51:45.829005
10	Wx_Custom/FacturationEleves/FraisScolarite.php	Y	Y	2024-08-03 20:26:31.45516	2024-10-26 17:06:01.692468
16	Wx_Custom/FacturationEleves/MassFraisScolarite.php	Y	Y	2024-08-03 20:28:38.200072	2024-08-03 20:28:38.200499
16	Wx_Custom/FacturationEleves/Paiements.php	Y	Y	2024-08-03 20:28:38.20094	2024-08-03 20:28:38.201328
16	Wx_Custom/FacturationEleves/Soldes.php	Y	Y	2024-08-03 20:28:38.201799	2024-08-03 20:28:38.202191
16	Wx_Custom/FacturationEleves/TransactionsPeriodiques.php	Y	Y	2024-08-03 20:28:38.202625	2024-08-03 20:28:38.20301
10	Wx_Custom/FacturationEleves/MassFraisScolarite.php	Y	Y	2024-08-03 20:26:31.456126	2024-10-26 17:06:01.692868
16	Wx_Custom/FacturationEleves/FraisScolarite.php	Y	Y	2024-08-03 20:28:38.198551	2024-08-03 20:28:38.199549
10	Wx_Custom/FacturationEleves/Paiements.php	Y	Y	2024-08-03 20:26:31.456903	2024-10-26 17:06:01.693267
10	School_Setup/PortalNotes.php	Y	Y	2023-09-19 11:51:45.727035	2024-08-14 14:53:41.966745
10	Students/AddUsers.php	Y	Y	2023-09-19 11:51:45.75731	2024-08-19 13:47:46.19303
10	Accounting/Categories.php	Y	\N	2023-09-19 11:51:45.829484	2023-09-19 11:51:45.829865
1	Wx_Custom/Users/User.php	Y	Y	2024-07-29 12:20:13.309805	\N
1	Wx_Custom/Users/User.php&staff_id=new	Y	Y	2024-07-29 12:20:13.309805	\N
10	Custom/RemoveAccess.php	Y	Y	2024-08-19 13:47:46.203741	2024-08-19 13:47:46.204019
16	Wx_Custom/FacturationEleves/Statements.php	Y	Y	2024-08-03 20:28:38.203577	2024-08-03 20:28:38.204793
10	Users/User.php&staff_id=new	Y	Y	2024-08-19 11:39:22.237035	2024-08-19 11:39:22.23786
10	Users/AddStudents.php	Y	Y	2024-08-19 11:43:08.005461	2024-08-19 11:43:08.007837
10	Wx_Custom/Users/User.php	Y	Y	2024-08-14 13:07:46.060311	2024-08-17 19:15:14.961191
10	Wx_Custom/Users/User.php&staff_id=new	Y	Y	2024-08-14 13:07:46.063136	2024-08-14 13:07:46.063409
10	Wx_Custom/Wx_CustomSchoolRepportClasses.php	Y	Y	2024-08-19 11:43:53.804874	2024-08-19 11:43:53.805174
10	Users/Profiles.php	Y	Y	2024-10-26 17:06:01.678079	2024-10-26 17:06:01.678418
10	Users/Exceptions.php	Y	Y	2024-10-26 17:06:01.678852	2024-10-26 17:06:01.680384
2	Students/AddUsers.php	Y	\N	2023-09-22 12:25:44.509132	2023-09-22 12:25:44.509876
2	Students/Student.php&category_id=1	Y	\N	2023-09-21 11:37:14.558775	2024-08-19 13:28:39.214648
2	Students/Student.php&category_id=4	\N	Y	2023-08-01 22:43:31.104393	2023-08-04 20:13:28.015932
2	Users/User.php	Y	\N	2023-09-21 11:37:14.560502	2023-09-21 11:37:14.560997
2	Users/Preferences.php	Y	\N	2023-09-22 12:25:44.513458	2023-09-22 12:25:44.513867
2	Users/User.php&category_id=1	Y	Y	2024-08-02 18:46:30.649142	2024-08-03 16:22:37.525022
2	Users/User.php&category_id=2	Y	Y	2023-09-21 11:37:14.561469	2023-09-21 11:37:14.561907
2	Users/User.php&category_id=3	Y	Y	2023-09-21 11:37:14.56242	2023-09-21 11:37:14.562801
2	Wx_Custom/Wx_CustomSchoolRepportClasses.php	Y	\N	2024-01-23 21:26:55.752544	\N
2	Discipline/MakeReferral.php	Y	\N	2023-08-01 22:43:31.104393	2023-08-04 20:13:28.032389
2	Accounting/Salaries.php	Y	\N	2023-09-30 14:41:23.912256	2023-09-30 14:41:23.912968
2	Accounting/StaffPayments.php	Y	\N	2023-09-30 14:41:23.913697	2023-09-30 14:41:23.914276
2	Accounting/Statements.php&_ROSARIO_PDF	Y	\N	2023-09-30 14:41:23.914837	2023-09-30 14:41:23.915308
2	Students/Student.php	Y	\N	2023-09-21 11:37:14.55614	2023-09-21 11:37:14.556751
10	School_Setup/PortalPolls.php	Y	Y	2024-08-14 14:37:39.554302	2024-10-26 17:06:01.657247
10	School_Setup/MarkingPeriods.php	Y	Y	2024-10-26 17:06:01.658612	2024-10-26 17:06:01.660808
10	School_Setup/CopySchool.php	Y	Y	2024-10-26 17:06:01.662183	2024-10-26 17:06:01.662529
10	School_Setup/SchoolFields.php	Y	Y	2024-10-26 17:06:01.662964	2024-10-26 17:06:01.663307
10	Wx_Custom/Wx_CustomSchoolRepportStudent.php	Y	Y	2024-08-19 11:43:53.805544	2024-08-19 11:43:53.805841
10	Student_Billing/StudentPayments.php&modfunc=remove	Y	Y	2024-10-26 17:06:01.69486	2024-10-26 17:06:01.695172
1	Students/StudentLabels.php	Y	Y	2023-08-01 22:43:31.104393	2023-08-13 15:35:19.652888
1	Wx_Custom/PrintStudentInfo/PrintStudentInfo.php	Y	Y	2024-08-20 11:13:34.915962	\N
1	Users/User.php&category_id=1&schools	Y	\N	2024-08-17 20:14:03.635402	2024-12-16 17:01:59.257083
1	Wx_Custom/Wx_CustomStudentClassesStats.php	Y	Y	2024-01-23 21:22:57.457492	\N
1	Wx_Custom/Wx_CustomSetupNotes.php&modfunc=config_moyennes_passage_niveau_superieur	Y	Y	2024-07-24 19:56:57.511446	\N
1	Wx_Custom/Wx_CustomSetupNotes.php&modfunc=config_publication_resultats	Y	Y	2024-07-24 19:55:31.215815	\N
1	Wx_Custom/EchelleNotationAppreciation/Wx_CustomEchelleNotationAppreciation.php	Y	Y	2024-07-29 12:20:13.309805	\N
1	Wx_Custom/FacturationEleves/MassFraisScolarite.php	Y	Y	2024-07-24 19:58:09.454694	\N
1	Wx_Custom/FacturationEleves/Paiements.php	Y	Y	2024-07-24 19:41:21.525755	\N
1	Wx_Custom/FacturationEleves/Soldes.php	Y	Y	2024-07-24 19:43:08.530214	\N
1	Wx_Custom/FacturationEleves/TransactionsPeriodiques.php	Y	Y	2024-07-24 19:43:08.530214	\N
1	Wx_Custom/FacturationEleves/Statements.php	Y	Y	2024-07-24 19:58:09.454694	\N
3	Users/User.php&category_id=1	Y	Y	2024-08-07 23:36:02.73185	2024-08-07 23:36:02.732237
3	Wx_Custom/Wx_CustomStudentSchedule.php	Y	\N	2024-08-02 12:01:46.211587	2024-08-03 23:36:26.77756
3	School_Setup/Calendar.php	Y	\N	2023-08-01 22:43:31.104393	\N
3	Users/User.php	Y	\N	2024-08-07 23:36:02.730446	2024-08-07 23:36:02.730861
3	Users/Preferences.php	Y	\N	2024-08-03 23:53:44.222403	2024-08-03 23:53:44.224522
10	Users/UserFields.php	Y	Y	2024-10-26 17:06:01.680787	2024-10-26 17:06:01.681096
10	Users/User.php&category_id=1	Y	Y	2024-08-17 13:11:34.416172	2024-08-17 13:11:34.418571
10	Users/User.php&category_id=1&user_profile	Y	Y	2024-08-17 15:14:12.736825	2024-08-17 15:14:39.973919
10	Wx_Custom/School_Setup/Rollover.php	Y	Y	2024-10-26 17:06:01.66422	2024-10-26 17:06:01.664642
10	School_Setup/DatabaseBackup.php	Y	Y	2024-10-26 17:06:01.6655	2024-10-26 17:06:01.665839
10	Students/AdvancedReport.php	Y	Y	2024-08-19 13:47:46.193549	2024-08-19 13:47:46.196343
10	Students/AddDrop.php	Y	Y	2024-08-19 13:47:46.197043	2024-08-19 13:47:46.19736
10	Users/User.php&category_id=1&schools	Y	Y	2024-10-26 17:06:01.68228	2024-10-26 17:06:01.682585
10	Users/User.php&category_id=2	Y	Y	2024-08-19 11:37:06.433708	2024-08-19 11:37:06.435295
10	Students/PrintStudentInfo.php	Y	Y	2024-08-19 13:47:46.199787	2024-08-19 13:47:46.20008
10	Users/User.php&category_id=3	Y	Y	2024-08-17 13:11:34.421708	2024-08-17 13:11:34.422047
10	Wx_Custom/Wx_CustomSetupNotes.php&modfunc=update_method_evaluation_student	Y	Y	2024-08-19 11:43:53.799706	2024-08-19 11:43:53.800924
10	Students/StudentBreakdown.php	Y	Y	2024-08-19 13:47:46.197744	2024-08-19 13:47:46.198043
10	Students/Letters.php	Y	Y	2024-08-19 13:47:46.198429	2024-08-19 13:47:46.198732
10	Wx_Custom/Wx_CustomCourses.php	Y	Y	2024-08-19 11:43:08.010662	2024-08-19 11:43:08.011115
10	Wx_Custom/Wx_CustomClasses.php	Y	Y	2024-08-19 11:43:53.795617	2024-08-19 11:43:53.796685
10	Wx_Custom/Wx_CustomSchedule.php	Y	Y	2024-08-19 11:43:53.797215	2024-08-19 11:43:53.797574
10	Wx_Custom/Wx_CustomStudentClassesAllocate.php	Y	Y	2024-08-19 11:43:53.798035	2024-08-19 11:43:53.798426
10	Wx_Custom/Wx_CustomStudentClassesStats.php	Y	Y	2024-08-19 11:43:53.798885	2024-08-19 11:43:53.799269
10	Students/StudentLabels.php	Y	Y	2024-08-19 13:47:46.199108	2024-08-19 13:47:46.199409
10	Wx_Custom/PrintStudentInfo/PrintStudentInfo.php	Y	Y	2024-10-26 17:06:01.670133	2024-10-26 17:06:01.670522
10	Students/StudentFields.php	Y	Y	2024-08-19 13:47:46.200432	2024-08-19 13:47:46.200724
10	Students/EnrollmentCodes.php	Y	Y	2024-08-19 13:47:46.201076	2024-08-19 13:47:46.201352
10	Custom/MyReport.php	Y	Y	2024-08-19 13:47:46.201718	2024-08-19 13:47:46.201994
10	Custom/CreateParents.php	Y	Y	2024-08-19 13:47:46.202345	2024-08-19 13:47:46.202631
10	Custom/Registration.php	Y	Y	2024-08-19 13:47:46.202992	2024-08-19 13:47:46.203365
10	Wx_Custom/Wx_CustomSetupNotes.php	Y	Y	2024-10-26 17:06:01.685707	2024-10-26 17:06:01.686083
10	Wx_Custom/Wx_CustomSetupNotes.php&modfunc=config_moyennes_passage_niveau_superieur	Y	Y	2024-08-19 11:43:53.801399	2024-08-19 11:43:53.80183
10	Wx_Custom/Wx_CustomSetupNotes.php&modfunc=config_publication_resultats	Y	Y	2024-08-19 11:43:53.802325	2024-08-19 11:43:53.802804
10	Wx_Custom/Wx_CustomNotes.php	Y	Y	2024-08-19 11:43:53.803276	2024-08-19 11:43:53.803658
10	Wx_Custom/EchelleNotationAppreciation/Wx_CustomEchelleNotationAppreciation.php	Y	Y	2024-08-19 11:43:53.804098	2024-08-19 11:43:53.804482
1	School_Setup/PortalNotes.php	Y	Y	2023-08-15 14:26:23.160041	2023-08-15 14:26:23.162503
1	Wx_Custom/School_Setup/Rollover.php	Y	Y	2024-07-25 21:49:17.254606	\N
1	School_Setup/DatabaseBackup.php	Y	Y	2023-08-15 14:26:23.177635	2023-08-15 14:26:23.17808
1	Students/Student.php	Y	Y	2023-08-01 22:43:31.104393	2023-08-13 15:35:19.64244
1	Students/Student.php&include=General_Info&student_id=new	Y	Y	2023-08-01 22:43:31.104393	2023-08-13 15:35:19.647221
1	Custom/CreateParents.php	Y	Y	2023-08-01 22:43:31.104393	2023-08-15 16:45:54.437644
1	Students/Student.php&category_id=5	Y	Y	2023-08-13 15:35:19.660723	2023-08-13 15:35:19.661358
1	Users/UserFields.php	Y	Y	2023-08-01 22:43:31.104393	2023-08-13 15:35:19.668622
1	Wx_Custom/Wx_CustomSchedule.php	Y	Y	2024-01-23 21:23:33.975491	\N
1	Wx_Custom/FacturationEleves/FraisScolarite.php	Y	Y	2024-04-14 18:07:53.991176	\N
18	Accounting/Incomes.php	Y	Y	2025-06-05 08:20:49.849001	2025-06-05 08:20:49.850514
18	Accounting/Expenses.php	Y	Y	2025-06-05 08:20:49.85253	2025-06-05 08:20:49.853235
18	Accounting/Salaries.php	Y	Y	2025-06-05 08:20:49.85392	2025-06-05 08:20:49.85495
18	Accounting/StaffPayments.php	Y	Y	2025-06-05 08:20:49.855686	2025-06-05 08:20:49.856216
18	Accounting/DailyTransactions.php	Y	Y	2025-06-05 08:20:49.856886	2025-06-05 08:20:49.857426
18	Accounting/StaffBalances.php	Y	Y	2025-06-05 08:20:49.858109	2025-06-05 08:20:49.858723
18	Accounting/Statements.php	Y	Y	2025-06-05 08:20:49.85933	2025-06-05 08:20:49.859853
18	Accounting/Categories.php	Y	Y	2025-06-05 08:20:49.860469	2025-06-05 08:20:49.861276
18	Wx_Custom/FacturationEleves/FraisScolarite.php	Y	Y	2025-06-05 08:36:20.866565	2025-06-05 08:36:20.867801
18	Wx_Custom/FacturationEleves/MassFraisScolarite.php	Y	Y	2025-06-05 08:36:20.868741	2025-06-05 08:36:20.869399
18	Wx_Custom/FacturationEleves/Paiements.php	Y	Y	2025-06-05 08:36:20.870123	2025-06-05 08:36:20.870698
18	Wx_Custom/FacturationEleves/Soldes.php	Y	Y	2025-06-05 08:36:20.871449	2025-06-05 08:36:20.872089
18	Wx_Custom/FacturationEleves/TransactionsPeriodiques.php	Y	Y	2025-06-05 08:36:20.872779	2025-06-05 08:36:20.873352
18	Wx_Custom/FacturationEleves/Statements.php	Y	Y	2025-06-05 08:36:20.874021	2025-06-05 08:36:20.874543
18	Student_Billing/StudentPayments.php&modfunc=remove	Y	Y	2025-06-05 08:20:49.861861	2025-06-05 08:20:49.86234
1	Student_ID_Card/StudentIDCard.php	Y	Y	2025-07-18 11:37:10.507411	\N
1	Students_Import/StudentsImport.php	Y	Y	2025-09-08 14:32:01.690474	\N
1	Messaging/Messages.php	Y	Y	2025-09-09 11:07:19.498361	\N
1	Messaging/Write.php	Y	Y	2025-09-09 11:07:19.498361	\N
3	Messaging/Messages.php	Y	\N	2025-09-09 11:07:19.498361	\N
3	Messaging/Write.php	Y	\N	2025-09-09 11:07:19.498361	\N
0	Messaging/Messages.php	Y	\N	2025-09-09 11:07:19.498361	\N
2	Students/Student.php&category_id=5	\N	Y	2024-08-19 12:36:04.775903	2024-08-19 12:36:04.77625
2	Messaging/Messages.php	Y	\N	2025-09-09 11:07:19.498361	\N
2	Messaging/Write.php	Y	\N	2025-09-09 11:07:19.498361	\N
2	Students/Student.php&category_id=3	\N	Y	2024-08-19 12:36:04.774652	2024-08-19 12:36:04.775016
0	Messaging/Write.php	Y	\N	2025-09-09 11:07:19.498361	\N
2	School_Setup/Schools.php	Y	\N	2023-08-01 22:43:31.104393	\N
2	School_Setup/Calendar.php	Y	\N	2023-08-01 22:43:31.104393	\N
2	School_Setup/MarkingPeriods.php	Y	\N	2023-08-01 22:43:31.104393	\N
2	Students/StudentLabels.php	Y	\N	2023-08-01 22:43:31.104393	\N
2	Students/Student.php&category_id=2	\N	Y	2024-08-19 12:36:04.771486	2024-08-19 12:36:04.774125
2	Wx_Custom/Wx_CustomTeacherSchedule.php	Y	\N	2024-07-29 12:20:13.309805	2024-08-02 18:46:30.648537
2	Discipline/Referrals.php	Y	\N	2023-08-01 22:43:31.104393	2023-08-04 20:13:28.035473
\.


--
-- Data for Name: program_config; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.program_config (syear, school_id, program, title, value, created_at, updated_at) FROM stdin;
2023	1	eligibility	START_DAY	1	2023-08-01 22:43:31.104393	\N
2023	1	eligibility	START_HOUR	23	2023-08-01 22:43:31.104393	\N
2023	1	eligibility	START_MINUTE	30	2023-08-01 22:43:31.104393	\N
2023	1	eligibility	START_M	PM	2023-08-01 22:43:31.104393	\N
2023	1	eligibility	END_DAY	5	2023-08-01 22:43:31.104393	\N
2023	1	eligibility	END_HOUR	23	2023-08-01 22:43:31.104393	\N
2023	1	eligibility	END_MINUTE	30	2023-08-01 22:43:31.104393	\N
2023	1	eligibility	END_M	PM	2023-08-01 22:43:31.104393	\N
2023	1	attendance	ATTENDANCE_EDIT_DAYS_BEFORE	\N	2023-08-01 22:43:31.104393	\N
2023	1	attendance	ATTENDANCE_EDIT_DAYS_AFTER	\N	2023-08-01 22:43:31.104393	\N
2023	1	grades	GRADES_DOES_LETTER_PERCENT	0	2023-08-01 22:43:31.104393	\N
2023	1	grades	GRADES_HIDE_NON_ATTENDANCE_COMMENT	\N	2023-08-01 22:43:31.104393	\N
2023	1	grades	GRADES_TEACHER_ALLOW_EDIT	\N	2023-08-01 22:43:31.104393	\N
2023	1	grades	GRADES_GRADEBOOK_TEACHER_ALLOW_EDIT	Y	2023-08-01 22:43:31.104393	\N
2023	1	grades	GRADES_DO_STATS_STUDENTS_PARENTS	\N	2023-08-01 22:43:31.104393	\N
2023	1	grades	GRADES_DO_STATS_ADMIN_TEACHERS	Y	2023-08-01 22:43:31.104393	\N
2023	1	students	STUDENTS_USE_BUS	Y	2023-08-01 22:43:31.104393	\N
2023	1	students	STUDENTS_USE_CONTACT	Y	2023-08-01 22:43:31.104393	\N
2023	1	students	STUDENTS_SEMESTER_COMMENTS	\N	2023-08-01 22:43:31.104393	\N
2023	1	moodle	MOODLE_URL	\N	2023-08-01 22:43:31.104393	\N
2023	1	moodle	MOODLE_TOKEN	\N	2023-08-01 22:43:31.104393	\N
2023	1	moodle	MOODLE_PARENT_ROLE_ID	\N	2023-08-01 22:43:31.104393	\N
2023	1	food_service	FOOD_SERVICE_BALANCE_WARNING	5	2023-08-01 22:43:31.104393	\N
2023	1	food_service	FOOD_SERVICE_BALANCE_MINIMUM	-40	2023-08-01 22:43:31.104393	\N
2023	1	food_service	FOOD_SERVICE_BALANCE_TARGET	19	2023-08-01 22:43:31.104393	\N
2025	1	eligibility	START_DAY	1	2024-11-04 14:22:35.289584	\N
2025	1	eligibility	START_HOUR	23	2024-11-04 14:22:35.289584	\N
2025	1	eligibility	START_MINUTE	30	2024-11-04 14:22:35.289584	\N
2025	1	eligibility	START_M	PM	2024-11-04 14:22:35.289584	\N
2025	1	eligibility	END_DAY	5	2024-11-04 14:22:35.289584	\N
2025	1	eligibility	END_HOUR	23	2024-11-04 14:22:35.289584	\N
2025	1	eligibility	END_MINUTE	30	2024-11-04 14:22:35.289584	\N
2025	1	eligibility	END_M	PM	2024-11-04 14:22:35.289584	\N
2025	1	attendance	ATTENDANCE_EDIT_DAYS_BEFORE	\N	2024-11-04 14:22:35.289584	\N
2025	1	attendance	ATTENDANCE_EDIT_DAYS_AFTER	\N	2024-11-04 14:22:35.289584	\N
2025	1	grades	GRADES_DOES_LETTER_PERCENT	0	2024-11-04 14:22:35.289584	\N
2025	1	grades	GRADES_HIDE_NON_ATTENDANCE_COMMENT	\N	2024-11-04 14:22:35.289584	\N
2025	1	grades	GRADES_TEACHER_ALLOW_EDIT	\N	2024-11-04 14:22:35.289584	\N
2025	1	grades	GRADES_GRADEBOOK_TEACHER_ALLOW_EDIT	Y	2024-11-04 14:22:35.289584	\N
2025	1	grades	GRADES_DO_STATS_STUDENTS_PARENTS	\N	2024-11-04 14:22:35.289584	\N
2025	1	grades	GRADES_DO_STATS_ADMIN_TEACHERS	Y	2024-11-04 14:22:35.289584	\N
2025	1	students	STUDENTS_USE_BUS	Y	2024-11-04 14:22:35.289584	\N
2025	1	students	STUDENTS_USE_CONTACT	Y	2024-11-04 14:22:35.289584	\N
2025	1	students	STUDENTS_SEMESTER_COMMENTS	\N	2024-11-04 14:22:35.289584	\N
2025	1	moodle	MOODLE_URL	\N	2024-11-04 14:22:35.289584	\N
2025	1	moodle	MOODLE_TOKEN	\N	2024-11-04 14:22:35.289584	\N
2025	1	moodle	MOODLE_PARENT_ROLE_ID	\N	2024-11-04 14:22:35.289584	\N
2025	1	food_service	FOOD_SERVICE_BALANCE_WARNING	5	2024-11-04 14:22:35.289584	\N
2025	1	food_service	FOOD_SERVICE_BALANCE_MINIMUM	-40	2024-11-04 14:22:35.289584	\N
2025	1	food_service	FOOD_SERVICE_BALANCE_TARGET	19	2024-11-04 14:22:35.289584	\N
2025	1	wx_custom	WX_CUSTOM_CONFIG	5	2024-11-04 14:22:35.289584	\N
2024	1	eligibility	START_DAY	1	2024-10-24 12:34:04.283745	\N
2024	1	eligibility	START_HOUR	23	2024-10-24 12:34:04.283745	\N
2024	1	eligibility	START_MINUTE	30	2024-10-24 12:34:04.283745	\N
2024	1	eligibility	START_M	PM	2024-10-24 12:34:04.283745	\N
2024	1	eligibility	END_DAY	5	2024-10-24 12:34:04.283745	\N
2024	1	eligibility	END_HOUR	23	2024-10-24 12:34:04.283745	\N
2024	1	eligibility	END_MINUTE	30	2024-10-24 12:34:04.283745	\N
2024	1	eligibility	END_M	PM	2024-10-24 12:34:04.283745	\N
2024	1	attendance	ATTENDANCE_EDIT_DAYS_BEFORE	\N	2024-10-24 12:34:04.283745	\N
2024	1	attendance	ATTENDANCE_EDIT_DAYS_AFTER	\N	2024-10-24 12:34:04.283745	\N
2024	1	grades	GRADES_DOES_LETTER_PERCENT	0	2024-10-24 12:34:04.283745	\N
2024	1	grades	GRADES_HIDE_NON_ATTENDANCE_COMMENT	\N	2024-10-24 12:34:04.283745	\N
2024	1	grades	GRADES_TEACHER_ALLOW_EDIT	\N	2024-10-24 12:34:04.283745	\N
2024	1	grades	GRADES_GRADEBOOK_TEACHER_ALLOW_EDIT	Y	2024-10-24 12:34:04.283745	\N
2024	1	grades	GRADES_DO_STATS_STUDENTS_PARENTS	\N	2024-10-24 12:34:04.283745	\N
2024	1	grades	GRADES_DO_STATS_ADMIN_TEACHERS	Y	2024-10-24 12:34:04.283745	\N
2024	1	students	STUDENTS_USE_BUS	Y	2024-10-24 12:34:04.283745	\N
2024	1	students	STUDENTS_USE_CONTACT	Y	2024-10-24 12:34:04.283745	\N
2024	1	students	STUDENTS_SEMESTER_COMMENTS	\N	2024-10-24 12:34:04.283745	\N
2024	1	moodle	MOODLE_URL	\N	2024-10-24 12:34:04.283745	\N
2024	1	moodle	MOODLE_TOKEN	\N	2024-10-24 12:34:04.283745	\N
2024	1	moodle	MOODLE_PARENT_ROLE_ID	\N	2024-10-24 12:34:04.283745	\N
2024	1	food_service	FOOD_SERVICE_BALANCE_WARNING	5	2024-10-24 12:34:04.283745	\N
2024	1	food_service	FOOD_SERVICE_BALANCE_MINIMUM	-40	2024-10-24 12:34:04.283745	\N
2024	1	food_service	FOOD_SERVICE_BALANCE_TARGET	19	2024-10-24 12:34:04.283745	\N
2023	1	wx_custom	WX_CUSTOM_CONFIG	5	2024-01-23 21:28:32.993863	\N
2024	1	wx_custom	WX_CUSTOM_CONFIG	5	2024-10-24 12:34:04.283745	\N
2024	16	eligibility	START_DAY	1	2024-12-16 13:41:03.889081	\N
2024	16	eligibility	START_HOUR	23	2024-12-16 13:41:03.889081	\N
2024	16	eligibility	START_MINUTE	30	2024-12-16 13:41:03.889081	\N
2024	16	eligibility	START_M	PM	2024-12-16 13:41:03.889081	\N
2024	16	eligibility	END_DAY	5	2024-12-16 13:41:03.889081	\N
2024	16	eligibility	END_HOUR	23	2024-12-16 13:41:03.889081	\N
2024	16	eligibility	END_MINUTE	30	2024-12-16 13:41:03.889081	\N
2024	16	eligibility	END_M	PM	2024-12-16 13:41:03.889081	\N
2024	16	attendance	ATTENDANCE_EDIT_DAYS_BEFORE	\N	2024-12-16 13:41:03.889081	\N
2024	16	attendance	ATTENDANCE_EDIT_DAYS_AFTER	\N	2024-12-16 13:41:03.889081	\N
2024	16	grades	GRADES_DOES_LETTER_PERCENT	0	2024-12-16 13:41:03.889081	\N
2024	16	grades	GRADES_HIDE_NON_ATTENDANCE_COMMENT	\N	2024-12-16 13:41:03.889081	\N
2024	16	grades	GRADES_TEACHER_ALLOW_EDIT	\N	2024-12-16 13:41:03.889081	\N
2024	16	grades	GRADES_GRADEBOOK_TEACHER_ALLOW_EDIT	Y	2024-12-16 13:41:03.889081	\N
2024	16	grades	GRADES_DO_STATS_STUDENTS_PARENTS	\N	2024-12-16 13:41:03.889081	\N
2024	16	grades	GRADES_DO_STATS_ADMIN_TEACHERS	Y	2024-12-16 13:41:03.889081	\N
2024	16	students	STUDENTS_USE_BUS	Y	2024-12-16 13:41:03.889081	\N
2024	16	students	STUDENTS_USE_CONTACT	Y	2024-12-16 13:41:03.889081	\N
2024	16	students	STUDENTS_SEMESTER_COMMENTS	\N	2024-12-16 13:41:03.889081	\N
2024	16	moodle	MOODLE_URL	\N	2024-12-16 13:41:03.889081	\N
2024	16	moodle	MOODLE_TOKEN	\N	2024-12-16 13:41:03.889081	\N
2024	16	moodle	MOODLE_PARENT_ROLE_ID	\N	2024-12-16 13:41:03.889081	\N
2024	16	food_service	FOOD_SERVICE_BALANCE_WARNING	5	2024-12-16 13:41:03.889081	\N
2024	16	food_service	FOOD_SERVICE_BALANCE_MINIMUM	-40	2024-12-16 13:41:03.889081	\N
2024	16	food_service	FOOD_SERVICE_BALANCE_TARGET	19	2024-12-16 13:41:03.889081	\N
2024	16	wx_custom	WX_CUSTOM_CONFIG	5	2024-12-16 13:41:03.889081	\N
2024	17	eligibility	START_DAY	1	2025-01-23 14:25:08.538087	\N
2024	17	eligibility	START_HOUR	23	2025-01-23 14:25:08.538087	\N
2024	17	eligibility	START_MINUTE	30	2025-01-23 14:25:08.538087	\N
2024	17	eligibility	START_M	PM	2025-01-23 14:25:08.538087	\N
2024	17	eligibility	END_DAY	5	2025-01-23 14:25:08.538087	\N
2024	17	eligibility	END_HOUR	23	2025-01-23 14:25:08.538087	\N
2024	17	eligibility	END_MINUTE	30	2025-01-23 14:25:08.538087	\N
2024	17	eligibility	END_M	PM	2025-01-23 14:25:08.538087	\N
2024	17	attendance	ATTENDANCE_EDIT_DAYS_BEFORE	\N	2025-01-23 14:25:08.538087	\N
2024	17	attendance	ATTENDANCE_EDIT_DAYS_AFTER	\N	2025-01-23 14:25:08.538087	\N
2024	17	grades	GRADES_DOES_LETTER_PERCENT	0	2025-01-23 14:25:08.538087	\N
2024	17	grades	GRADES_HIDE_NON_ATTENDANCE_COMMENT	\N	2025-01-23 14:25:08.538087	\N
2024	17	grades	GRADES_TEACHER_ALLOW_EDIT	\N	2025-01-23 14:25:08.538087	\N
2024	17	grades	GRADES_GRADEBOOK_TEACHER_ALLOW_EDIT	Y	2025-01-23 14:25:08.538087	\N
2024	17	grades	GRADES_DO_STATS_STUDENTS_PARENTS	\N	2025-01-23 14:25:08.538087	\N
2024	17	grades	GRADES_DO_STATS_ADMIN_TEACHERS	Y	2025-01-23 14:25:08.538087	\N
2024	17	students	STUDENTS_USE_BUS	Y	2025-01-23 14:25:08.538087	\N
2024	17	students	STUDENTS_USE_CONTACT	Y	2025-01-23 14:25:08.538087	\N
2024	17	students	STUDENTS_SEMESTER_COMMENTS	\N	2025-01-23 14:25:08.538087	\N
2024	17	moodle	MOODLE_URL	\N	2025-01-23 14:25:08.538087	\N
2024	17	moodle	MOODLE_TOKEN	\N	2025-01-23 14:25:08.538087	\N
2024	17	moodle	MOODLE_PARENT_ROLE_ID	\N	2025-01-23 14:25:08.538087	\N
2024	17	food_service	FOOD_SERVICE_BALANCE_WARNING	5	2025-01-23 14:25:08.538087	\N
2024	17	food_service	FOOD_SERVICE_BALANCE_MINIMUM	-40	2025-01-23 14:25:08.538087	\N
2024	17	food_service	FOOD_SERVICE_BALANCE_TARGET	19	2025-01-23 14:25:08.538087	\N
2024	17	wx_custom	WX_CUSTOM_CONFIG	5	2025-01-23 14:25:08.538087	\N
2024	18	eligibility	START_DAY	1	2025-01-23 16:47:37.947193	\N
2024	18	eligibility	START_HOUR	23	2025-01-23 16:47:37.947193	\N
2024	18	eligibility	START_MINUTE	30	2025-01-23 16:47:37.947193	\N
2024	18	eligibility	START_M	PM	2025-01-23 16:47:37.947193	\N
2024	18	eligibility	END_DAY	5	2025-01-23 16:47:37.947193	\N
2024	18	eligibility	END_HOUR	23	2025-01-23 16:47:37.947193	\N
2024	18	eligibility	END_MINUTE	30	2025-01-23 16:47:37.947193	\N
2024	18	eligibility	END_M	PM	2025-01-23 16:47:37.947193	\N
2024	18	attendance	ATTENDANCE_EDIT_DAYS_BEFORE	\N	2025-01-23 16:47:37.947193	\N
2024	18	attendance	ATTENDANCE_EDIT_DAYS_AFTER	\N	2025-01-23 16:47:37.947193	\N
2024	18	grades	GRADES_DOES_LETTER_PERCENT	0	2025-01-23 16:47:37.947193	\N
2024	18	grades	GRADES_HIDE_NON_ATTENDANCE_COMMENT	\N	2025-01-23 16:47:37.947193	\N
2024	18	grades	GRADES_TEACHER_ALLOW_EDIT	\N	2025-01-23 16:47:37.947193	\N
2024	18	grades	GRADES_GRADEBOOK_TEACHER_ALLOW_EDIT	Y	2025-01-23 16:47:37.947193	\N
2024	18	grades	GRADES_DO_STATS_STUDENTS_PARENTS	\N	2025-01-23 16:47:37.947193	\N
2024	18	grades	GRADES_DO_STATS_ADMIN_TEACHERS	Y	2025-01-23 16:47:37.947193	\N
2024	18	students	STUDENTS_USE_BUS	Y	2025-01-23 16:47:37.947193	\N
2024	18	students	STUDENTS_USE_CONTACT	Y	2025-01-23 16:47:37.947193	\N
2024	18	students	STUDENTS_SEMESTER_COMMENTS	\N	2025-01-23 16:47:37.947193	\N
2024	18	moodle	MOODLE_URL	\N	2025-01-23 16:47:37.947193	\N
2024	18	moodle	MOODLE_TOKEN	\N	2025-01-23 16:47:37.947193	\N
2024	18	moodle	MOODLE_PARENT_ROLE_ID	\N	2025-01-23 16:47:37.947193	\N
2024	18	food_service	FOOD_SERVICE_BALANCE_WARNING	5	2025-01-23 16:47:37.947193	\N
2024	18	food_service	FOOD_SERVICE_BALANCE_MINIMUM	-40	2025-01-23 16:47:37.947193	\N
2024	18	food_service	FOOD_SERVICE_BALANCE_TARGET	19	2025-01-23 16:47:37.947193	\N
2024	18	wx_custom	WX_CUSTOM_CONFIG	5	2025-01-23 16:47:37.947193	\N
2024	19	eligibility	START_DAY	1	2025-02-27 14:03:05.001783	\N
2024	19	eligibility	START_HOUR	23	2025-02-27 14:03:05.001783	\N
2024	19	eligibility	START_MINUTE	30	2025-02-27 14:03:05.001783	\N
2024	19	eligibility	START_M	PM	2025-02-27 14:03:05.001783	\N
2024	19	eligibility	END_DAY	5	2025-02-27 14:03:05.001783	\N
2024	19	eligibility	END_HOUR	23	2025-02-27 14:03:05.001783	\N
2024	19	eligibility	END_MINUTE	30	2025-02-27 14:03:05.001783	\N
2024	19	eligibility	END_M	PM	2025-02-27 14:03:05.001783	\N
2024	19	attendance	ATTENDANCE_EDIT_DAYS_BEFORE	\N	2025-02-27 14:03:05.001783	\N
2024	19	attendance	ATTENDANCE_EDIT_DAYS_AFTER	\N	2025-02-27 14:03:05.001783	\N
2024	19	grades	GRADES_DOES_LETTER_PERCENT	0	2025-02-27 14:03:05.001783	\N
2024	19	grades	GRADES_HIDE_NON_ATTENDANCE_COMMENT	\N	2025-02-27 14:03:05.001783	\N
2024	19	grades	GRADES_TEACHER_ALLOW_EDIT	\N	2025-02-27 14:03:05.001783	\N
2024	19	grades	GRADES_GRADEBOOK_TEACHER_ALLOW_EDIT	Y	2025-02-27 14:03:05.001783	\N
2024	19	grades	GRADES_DO_STATS_STUDENTS_PARENTS	\N	2025-02-27 14:03:05.001783	\N
2024	19	grades	GRADES_DO_STATS_ADMIN_TEACHERS	Y	2025-02-27 14:03:05.001783	\N
2024	19	students	STUDENTS_USE_BUS	Y	2025-02-27 14:03:05.001783	\N
2024	19	students	STUDENTS_USE_CONTACT	Y	2025-02-27 14:03:05.001783	\N
2024	19	students	STUDENTS_SEMESTER_COMMENTS	\N	2025-02-27 14:03:05.001783	\N
2024	19	moodle	MOODLE_URL	\N	2025-02-27 14:03:05.001783	\N
2024	19	moodle	MOODLE_TOKEN	\N	2025-02-27 14:03:05.001783	\N
2024	19	moodle	MOODLE_PARENT_ROLE_ID	\N	2025-02-27 14:03:05.001783	\N
2024	19	food_service	FOOD_SERVICE_BALANCE_WARNING	5	2025-02-27 14:03:05.001783	\N
2024	19	food_service	FOOD_SERVICE_BALANCE_MINIMUM	-40	2025-02-27 14:03:05.001783	\N
2024	19	food_service	FOOD_SERVICE_BALANCE_TARGET	19	2025-02-27 14:03:05.001783	\N
2024	19	wx_custom	WX_CUSTOM_CONFIG	5	2025-02-27 14:03:05.001783	\N
2024	20	eligibility	START_DAY	1	2025-03-03 08:33:48.002722	\N
2024	20	eligibility	START_HOUR	23	2025-03-03 08:33:48.002722	\N
2024	20	eligibility	START_MINUTE	30	2025-03-03 08:33:48.002722	\N
2024	20	eligibility	START_M	PM	2025-03-03 08:33:48.002722	\N
2024	20	eligibility	END_DAY	5	2025-03-03 08:33:48.002722	\N
2024	20	eligibility	END_HOUR	23	2025-03-03 08:33:48.002722	\N
2024	20	eligibility	END_MINUTE	30	2025-03-03 08:33:48.002722	\N
2024	20	eligibility	END_M	PM	2025-03-03 08:33:48.002722	\N
2024	20	attendance	ATTENDANCE_EDIT_DAYS_BEFORE	\N	2025-03-03 08:33:48.002722	\N
2024	20	attendance	ATTENDANCE_EDIT_DAYS_AFTER	\N	2025-03-03 08:33:48.002722	\N
2024	20	grades	GRADES_DOES_LETTER_PERCENT	0	2025-03-03 08:33:48.002722	\N
2024	20	grades	GRADES_HIDE_NON_ATTENDANCE_COMMENT	\N	2025-03-03 08:33:48.002722	\N
2024	20	grades	GRADES_TEACHER_ALLOW_EDIT	\N	2025-03-03 08:33:48.002722	\N
2024	20	grades	GRADES_GRADEBOOK_TEACHER_ALLOW_EDIT	Y	2025-03-03 08:33:48.002722	\N
2024	20	grades	GRADES_DO_STATS_STUDENTS_PARENTS	\N	2025-03-03 08:33:48.002722	\N
2024	20	grades	GRADES_DO_STATS_ADMIN_TEACHERS	Y	2025-03-03 08:33:48.002722	\N
2024	20	students	STUDENTS_USE_BUS	Y	2025-03-03 08:33:48.002722	\N
2024	20	students	STUDENTS_USE_CONTACT	Y	2025-03-03 08:33:48.002722	\N
2024	20	students	STUDENTS_SEMESTER_COMMENTS	\N	2025-03-03 08:33:48.002722	\N
2024	20	moodle	MOODLE_URL	\N	2025-03-03 08:33:48.002722	\N
2024	20	moodle	MOODLE_TOKEN	\N	2025-03-03 08:33:48.002722	\N
2024	20	moodle	MOODLE_PARENT_ROLE_ID	\N	2025-03-03 08:33:48.002722	\N
2024	20	food_service	FOOD_SERVICE_BALANCE_WARNING	5	2025-03-03 08:33:48.002722	\N
2024	20	food_service	FOOD_SERVICE_BALANCE_MINIMUM	-40	2025-03-03 08:33:48.002722	\N
2024	20	food_service	FOOD_SERVICE_BALANCE_TARGET	19	2025-03-03 08:33:48.002722	\N
2024	20	wx_custom	WX_CUSTOM_CONFIG	5	2025-03-03 08:33:48.002722	\N
2024	17	student_id_card	custom_css	{"card_top_bottom_padding":"30","card_left_right_padding":"20","text_top_bottom_padding":"20","text_left_right_padding":"13","photo_top_bottom_padding":"48","photo_left_right_padding":"6","photo_max_width":"132","photo_float":"left","background_image":false}	2025-07-18 11:38:26.545312	2025-07-18 17:21:51.493561
2025	21	moodle	MOODLE_URL	https://moodle.webtinix.com/	2025-08-06 12:02:17.412607	\N
2025	21	moodle	MOODLE_TOKEN	5fcc7da0e8f0ec25c82c5faac1082a19	2025-08-06 12:02:17.419096	\N
2025	21	moodle	MOODLE_PARENT_ROLE_ID	\N	2025-08-06 12:02:17.42161	\N
2025	21	student_id_card	custom_css	{"card_top_bottom_padding":"46","card_left_right_padding":"13","text_top_bottom_padding":"18","text_left_right_padding":"13","photo_top_bottom_padding":"32","photo_left_right_padding":"13","photo_max_width":"132","photo_float":"left","background_image":false}	2025-08-14 17:27:58.405501	2025-08-22 17:40:44.35785
\.


--
-- Data for Name: program_user_config; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.program_user_config (user_id, program, title, value, school_id, created_at, updated_at) FROM stdin;
1	Preferences	SORT	Name	\N	2023-08-04 18:22:38.853481	\N
1	Preferences	DELIMITER	Tab	\N	2023-08-04 18:22:38.854932	\N
1	Preferences	E_DATE	YYYY-MM-DD	\N	2023-08-04 18:22:38.855384	\N
1	Preferences	SEARCH	Y	\N	2023-08-04 18:22:38.855809	\N
1	Preferences	DEFAULT_FAMILIES	N	\N	2023-08-04 18:22:38.856221	\N
1	Preferences	DEFAULT_ALL_SCHOOLS	N	\N	2023-08-04 18:22:38.856627	\N
56	Preferences	SORT	Name	\N	2023-09-23 06:50:48.186372	\N
56	Preferences	DELIMITER	Tab	\N	2023-09-23 06:50:48.187465	\N
56	Preferences	E_DATE	\N	\N	2023-09-23 06:50:48.188022	\N
56	Preferences	SEARCH	Y	\N	2023-09-23 06:50:48.188527	\N
848	Preferences	HIGHLIGHT	#6334bc	\N	2024-08-03 23:54:17.518449	\N
848	Preferences	DATE	%d %B %Y	\N	2024-08-03 23:54:17.521007	\N
848	Preferences	HIDE_ALERTS	N	\N	2024-08-03 23:54:17.521875	\N
4034	Preferences	HIDE_ALERTS	N	\N	2024-10-24 12:34:04.164179	\N
4034	Preferences	DATE	%d %B %Y	\N	2024-10-24 12:34:04.164179	\N
4034	Preferences	HIGHLIGHT	#6334bc	\N	2024-10-24 12:34:04.164179	\N
4268	Preferences	SEARCH	Y	\N	2024-10-24 12:34:04.164179	\N
4268	Preferences	E_DATE	\N	\N	2024-10-24 12:34:04.164179	\N
4268	Preferences	DELIMITER	Tab	\N	2024-10-24 12:34:04.164179	\N
4268	Preferences	SORT	Name	\N	2024-10-24 12:34:04.164179	\N
4321	Preferences	DEFAULT_ALL_SCHOOLS	N	\N	2024-10-24 12:34:04.164179	\N
4321	Preferences	DEFAULT_FAMILIES	N	\N	2024-10-24 12:34:04.164179	\N
4321	Preferences	SEARCH	Y	\N	2024-10-24 12:34:04.164179	\N
4321	Preferences	E_DATE	YYYY-MM-DD	\N	2024-10-24 12:34:04.164179	\N
4321	Preferences	DELIMITER	Tab	\N	2024-10-24 12:34:04.164179	\N
4321	Preferences	SORT	Name	\N	2024-10-24 12:34:04.164179	\N
4384	Preferences	SORT	Name	\N	2024-11-04 14:22:35.235592	\N
4384	Preferences	DELIMITER	Tab	\N	2024-11-04 14:22:35.235592	\N
4384	Preferences	E_DATE	YYYY-MM-DD	\N	2024-11-04 14:22:35.235592	\N
4384	Preferences	SEARCH	Y	\N	2024-11-04 14:22:35.235592	\N
4384	Preferences	DEFAULT_FAMILIES	N	\N	2024-11-04 14:22:35.235592	\N
4384	Preferences	DEFAULT_ALL_SCHOOLS	N	\N	2024-11-04 14:22:35.235592	\N
\.


--
-- Data for Name: report_card_comment_categories; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.report_card_comment_categories (id, syear, school_id, course_id, sort_order, title, rollover_id, color, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: report_card_comment_code_scales; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.report_card_comment_code_scales (id, school_id, title, comment, sort_order, rollover_id, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: report_card_comment_codes; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.report_card_comment_codes (id, school_id, scale_id, title, short_name, comment, sort_order, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: report_card_comments; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.report_card_comments (id, syear, school_id, course_id, category_id, scale_id, sort_order, title, created_at, updated_at) FROM stdin;
1	2023	1	\N	\N	\N	1	^n n'apprend pas ses leçons	2023-08-01 22:43:31.104393	2023-08-01 22:43:35.376882
2	2023	1	\N	\N	\N	2	^n ne fait pas ses devoirs	2023-08-01 22:43:31.104393	2023-08-01 22:43:35.376882
3	2023	1	\N	\N	\N	3	^n a une influence positive	2023-08-01 22:43:31.104393	2023-08-01 22:43:35.376882
\.


--
-- Data for Name: report_card_grade_scales; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.report_card_grade_scales (id, syear, school_id, title, comment, hhr_gpa_value, hr_gpa_value, sort_order, rollover_id, gp_scale, gp_passing_value, hrs_gpa_value, created_at, updated_at) FROM stdin;
9	2023	1	20	\N	18.00	\N	\N	\N	20.00	10.00	\N	2023-09-16 18:03:36.365143	2023-09-16 18:05:08.331583
\.


--
-- Data for Name: report_card_grades; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.report_card_grades (id, syear, school_id, title, sort_order, gpa_value, break_off, comment, grade_scale_id, unweighted_gp, created_at, updated_at) FROM stdin;
93	2023	1	20	1	20.00	100.00	\N	9	\N	2023-09-16 18:25:55.927652	2023-09-16 18:34:49.739156
94	2023	1	19	2	19.00	\N	\N	9	\N	2023-09-16 18:26:16.33941	2023-09-16 18:34:49.744396
95	2023	1	18	3	18.00	\N	\N	9	\N	2023-09-16 18:26:32.617352	2023-09-16 18:34:49.744928
96	2023	1	17	4	17.00	\N	\N	9	\N	2023-09-16 18:26:43.40666	2023-09-16 18:34:49.745504
97	2023	1	16	5	16.00	\N	\N	9	\N	2023-09-16 18:26:48.931284	2023-09-16 18:34:49.747754
98	2023	1	15	6	15.00	\N	\N	9	\N	2023-09-16 18:26:53.124131	2023-09-16 18:34:49.748267
99	2023	1	14	7	13.90	\N	\N	9	\N	2023-09-16 18:27:00.257507	2023-09-16 18:34:49.748748
100	2023	1	13	8	13.00	0.01	\N	9	\N	2023-09-16 18:27:06.028649	2023-09-16 18:34:49.743362
104	2023	1	12	\N	12.00	\N	\N	9	\N	2023-09-16 18:27:33.076635	2023-09-16 18:34:49.756278
103	2023	1	11	\N	11.00	\N	\N	9	\N	2023-09-16 18:27:25.863938	2023-09-16 18:34:49.754886
102	2023	1	10	\N	10.00	\N	\N	9	\N	2023-09-16 18:27:17.352216	2023-09-16 18:34:49.755582
106	2023	1	9	\N	9.00	\N	\N	9	\N	2023-09-16 18:28:00.63522	2023-09-16 18:34:49.757976
107	2023	1	8	\N	8.00	\N	\N	9	\N	2023-09-16 18:28:09.83155	2023-09-16 18:34:49.754023
108	2023	1	7	\N	7.00	\N	\N	9	\N	2023-09-16 18:28:25.217211	2023-09-16 18:34:49.74921
109	2023	1	6	\N	6.00	\N	\N	9	\N	2023-09-16 18:28:31.062472	2023-09-16 18:35:47.529247
110	2023	1	5	\N	5.00	\N	\N	9	\N	2023-09-16 18:28:36.676577	2023-09-16 18:35:47.52972
101	2023	1	4	\N	4.00	\N	\N	9	\N	2023-09-16 18:27:11.594835	2023-09-16 18:35:47.5303
111	2023	1	3	\N	3.00	\N	\N	9	\N	2023-09-16 18:28:55.191077	2023-09-16 18:35:47.530982
112	2023	1	2	\N	2.00	\N	\N	9	\N	2023-09-16 18:29:13.996944	2023-09-16 18:35:47.534039
113	2023	1	1	\N	1.00	\N	\N	9	\N	2023-09-16 18:29:19.933239	2023-09-16 18:35:47.537455
114	2023	1	0,5	\N	0.50	\N	\N	9	\N	2023-09-16 18:30:38.323245	2023-09-16 18:35:47.536944
115	2023	1	0	\N	0.00	0.00	\N	9	\N	2023-09-16 18:30:45.271481	2023-09-16 18:35:47.508167
\.


--
-- Data for Name: resources; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.resources (id, school_id, title, link, published_profiles, published_grade_levels, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: schedule; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.schedule (syear, school_id, student_id, start_date, end_date, modified_date, modified_by, course_id, course_period_id, mp, marking_period_id, scheduler_lock, id, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: schedule_requests; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.schedule_requests (syear, school_id, request_id, student_id, subject_id, course_id, marking_period_id, priority, with_teacher_id, not_teacher_id, with_period_id, not_period_id, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: school_fields; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.school_fields (id, type, title, sort_order, select_options, required, default_selection, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: school_gradelevels; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.school_gradelevels (id, school_id, short_name, title, next_grade_id, sort_order, created_at, updated_at, marking_period_type) FROM stdin;
28	18	CP1	CEP 1	\N	1	2024-12-17 13:30:44.422615	2024-12-17 13:43:24.785747	\N
29	18	CE1	CE 1	\N	3	2024-12-17 13:33:35.556518	2024-12-17 13:43:24.789631	\N
30	18	CE2	CE 2	\N	4	2024-12-17 13:34:02.370273	2024-12-17 13:43:24.790676	\N
31	18	CM1	CEM 1	\N	5	2024-12-17 13:35:39.436437	2024-12-17 13:43:24.791289	\N
32	18	CM2	CEM 2	\N	6	2024-12-17 13:36:03.038912	2024-12-17 13:43:24.792181	\N
33	18	6e	SIXIÈME	\N	7	2024-12-17 13:40:10.65052	2024-12-17 13:43:24.792811	\N
34	18	5e	CINQUIÈME	\N	8	2024-12-17 13:41:18.482955	2024-12-17 13:48:33.772776	\N
35	18	4e	QUATRIÈME	\N	9	2024-12-17 13:43:24.794285	2024-12-17 13:48:33.775379	\N
36	18	CP2	CEP 2	\N	2	2024-12-17 13:31:15.137273	2024-12-17 13:43:24.788708	\N
37	18	3e	TROISIÈME	\N	10	2024-12-17 13:44:31.533172	\N	\N
38	18	2nd	SECONDE	\N	11	2024-12-17 13:48:33.777206	\N	\N
39	18	PA	PREMIERE	\N	12	2025-01-20 09:13:59.200564	\N	\N
21	17	L1	LICENCE 1	22	1	2024-12-17 13:40:10.65052	2025-06-05 08:46:10.393769	\N
22	17	L2	LICENCE 2	23	2	2024-12-17 13:41:18.482955	2025-06-05 08:46:22.356028	\N
23	17	L3	LICENCE 3	25	3	2024-12-17 13:43:24.794285	2025-06-05 08:46:59.127594	\N
25	17	M1	MASTER 1	26	4	2024-12-17 13:44:31.533172	2025-06-05 08:46:31.049502	\N
1	16	CP1	CEP 1	2	1	2024-12-17 13:30:44.422615	2024-12-17 13:43:24.785747	\N
26	17	M2	MASTER 2	27	5	2024-12-17 13:48:33.777206	2025-06-05 08:46:59.132507	\N
3	16	CE1	CE 1	4	3	2024-12-17 13:33:35.556518	2024-12-17 13:43:24.789631	\N
4	16	CE2	CE 2	5	4	2024-12-17 13:34:02.370273	2024-12-17 13:43:24.790676	\N
5	16	CM1	CEM 1	6	5	2024-12-17 13:35:39.436437	2024-12-17 13:43:24.791289	\N
6	16	CM2	CEM 2	7	6	2024-12-17 13:36:03.038912	2024-12-17 13:43:24.792181	\N
7	16	6e	SIXIÈME	8	7	2024-12-17 13:40:10.65052	2024-12-17 13:43:24.792811	\N
8	16	5e	CINQUIÈME	9	8	2024-12-17 13:41:18.482955	2024-12-17 13:48:33.772776	\N
9	16	4e	QUATRIÈME	10	9	2024-12-17 13:43:24.794285	2024-12-17 13:48:33.775379	\N
2	16	CP2	CEP 2	3	2	2024-12-17 13:31:15.137273	2024-12-17 13:43:24.788708	\N
43	19	3em	troisièmes 	43	2	2025-03-09 16:44:58.472895	2025-03-09 16:47:45.26515	\N
10	16	3e	TROISIÈME	\N	10	2024-12-17 13:44:31.533172	\N	\N
11	16	2nd	SECONDE	\N	11	2024-12-17 13:48:33.777206	\N	\N
12	16	PA	PREMIERE	\N	12	2025-01-20 09:13:59.200564	\N	\N
44	19	T	terminale	44	2	2025-03-09 16:47:45.269845	2025-03-09 16:48:55.544543	\N
45	19	CU	cicle universitaire 	45	2	2025-03-09 16:48:55.547945	2025-03-09 16:49:13.195774	\N
27	17	PA	DOCTORAT	27	6	2025-01-20 09:13:59.200564	2025-06-04 09:19:41.860989	\N
46	17	da1	Doctorat 2	\N	\N	2025-07-18 13:35:54.811318	\N	\N
52	21	P	Première	56	6	2025-08-13 23:14:06.442983	2025-08-29 13:26:03.856713	\N
56	21	T	Terminal 	57	10	2025-08-29 13:10:20.892748	2025-08-29 13:26:03.860152	\N
47	21	6è	6ème	48	1	2025-08-06 12:04:20.797511	2025-08-28 14:15:56.580987	\N
48	21	5è	5ème	49	2	2025-08-06 12:04:34.769768	2025-08-28 14:15:56.591305	\N
49	21	4è	4ème	50	3	2025-08-06 12:04:56.68636	2025-08-28 14:15:56.592281	\N
50	21	3è	3ème	51	4	2025-08-13 23:12:55.436981	2025-08-28 14:15:56.593034	\N
51	21	STC	Seconde Tronc Commun	52	5	2025-08-13 23:13:29.518545	2025-08-29 13:01:59.27284	\N
\.


--
-- Data for Name: school_marking_periods; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.school_marking_periods (marking_period_id, syear, mp, school_id, parent_id, title, short_name, sort_order, start_date, end_date, post_start_date, post_end_date, does_grades, does_comments, rollover_id, created_at, updated_at) FROM stdin;
180	2025	FY	21	\N	Année Scolaire 2025-2026	2025-2026	1	2025-08-02	2026-07-02	\N	\N	\N	\N	\N	2025-08-06 12:07:57.100599	2025-08-14 00:03:03.790218
181	2025	SEM	21	180	Semestre 1	S1	1	2025-08-02	2026-04-04	2025-08-02	2026-04-04	\N	\N	\N	2025-08-06 12:10:35.080269	2025-08-14 00:04:52.67275
183	2025	QTR	21	181	Trimestre 1	T1	\N	2025-10-02	2025-12-19	\N	\N	\N	\N	\N	2025-08-10 18:31:11.613594	2025-08-14 15:56:51.556173
182	2025	SEM	21	180	Semestre 2	T2	\N	2026-01-14	2026-03-02	\N	\N	\N	\N	\N	2025-08-06 12:40:33.867597	2025-08-14 15:58:27.957553
184	2025	QTR	21	181	Trimestre 2	T2	\N	2026-01-06	2026-03-04	2026-01-06	2026-04-04	Y	\N	\N	2025-08-13 23:04:10.950083	2025-08-14 15:59:31.518167
185	2025	QTR	21	182	Trimestre 3	T3	\N	2026-04-21	2026-06-02	\N	\N	\N	\N	\N	2025-08-13 23:07:30.794604	2025-08-14 16:00:31.604857
\.


--
-- Data for Name: school_periods; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.school_periods (period_id, syear, school_id, sort_order, title, short_name, length, start_time, end_time, block, attendance, rollover_id, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: schools; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.schools (syear, id, title, address, city, state, zipcode, phone, principal, www_address, school_number, short_name, reporting_gp_scale, number_days_rotation, created_at, updated_at) FROM stdin;
2023	1	ECOLE MODELE	13 rue Jules Ferry	Brazzaville	POOL	75001	\N	M. Principal	\N	1	ECOLE MODELE	20.000	\N	2023-08-01 22:43:31.104393	2024-10-27 01:22:07.172499
2024	1	ECOLE MODELE	13 rue Jules Ferry	Brazzaville	POOL	75001	\N	M. Principal	\N	1	ECOLE MODELE	20.000	\N	2023-08-22 19:19:27.310741	2024-10-31 11:56:25.774953
2025	1	ECOLE MODELE	13 rue Jules Ferry	Brazzaville	POOL	75001	\N	M. Principal	\N	1	ECOLE MODELE	20.000	\N	2024-11-04 14:22:35.227591	\N
2024	16	Complexe Scolaire la Royauté	18 rue Alpin Batota Mfilou Ngamaba	Brazzaville	Brazzavill	\N	068096277	Madzou Sancty	\N	\N	La Royauté	20.000	\N	2024-12-16 13:41:03.872686	2025-01-21 16:39:14.004147
2024	17	Ecole test	\N	\N	\N	\N	\N	\N	\N	\N	\N	20.000	\N	2025-01-23 14:25:08.526124	\N
2024	18	Test canadian	\N	\N	\N	\N	\N	\N	\N	\N	\N	20.000	\N	2025-01-23 16:47:37.942112	\N
2024	19	APACCA DE VINCIA	appacadevincia@gmail.com	MPITA	P/N	99324	POINTE_NOIRE	044343333	KIBANGOU Gloire	APV	\N	20.000	5	2025-02-27 14:03:04.992243	2025-03-03 08:31:21.869833
2024	20	appaca de vincia site 2	\N	\N	\N	\N	\N	\N	\N	\N	\N	20.000	\N	2025-03-03 08:33:47.993366	\N
2025	21	AKEELAH SCHOOL	64 Rue Mpangala, Ouénzé Brazzaville 	Brazzaville 	\N	\N	065790008	\N	\N	\N	\N	\N	\N	2025-08-06 10:29:21.35881	2025-08-28 14:16:28.788638
\.


--
-- Data for Name: staff; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.staff (syear, staff_id, current_school_id, title, first_name, last_name, middle_name, name_suffix, username, password, email, custom_200000001, profile, homeroom, schools, last_login, failed_login, profile_id, rollover_id, created_at, updated_at, custom_200000002, custom_200000003, custom_200000004, custom_200000005) FROM stdin;
2025	4430	\N	Mme	Melse	Mbelani	Stevez	\N	melse	$6$4ca175aad0d971db$FiWFjSvbCcOTYGQjMnb1AS6c/t5pjGCnapam3ZAzvyMP9.0ejZ5XjrV4iCz3c0/II/JbfU.6emKQNXlyHSDQ1.	\N	\N	teacher	\N	,21,	\N	\N	2	\N	2025-08-07 16:54:08.882693	2025-08-07 17:39:49.555546	\N	\N	\N	1997-07-18
2025	4440	21	Mr	Daryon	Rocknes	\N	\N	daryonrocknes@icloud.com	$6$546a13831fbed2ea$KvI5WcvJkJD5f5.DgnbEGJ.T1QQM/OxBaEe6OHLmyPcOAkQ9A/4JjPcYCvSXSlxW9eGr.uhgdi2r8YjYN6IGD1	daryonrocknes@icloud.com	069629784	teacher	\N	,21,	2025-09-08 08:07:50.882821	\N	2	\N	2025-09-05 14:05:18.944173	2025-09-08 08:07:50.882821	\N	\N	informatique	1992-07-05
2025	4431	\N	Mr	Alfred	MOUZINGA	\N	\N	\N	\N	\N	\N	teacher	\N	,21,	\N	\N	2	\N	2025-08-13 23:33:47.172068	\N	\N	\N	\N	1952-10-17
2025	4432	\N	\N	HOUESSOU	Ange	\N	\N	\N	\N	\N	\N	teacher	\N	,21,	\N	\N	2	\N	2025-08-13 23:35:10.331708	\N	\N	\N	\N	1956-10-18
2025	4433	\N	\N	Nancy	KONGO	\N	\N	\N	\N	\N	\N	teacher	\N	,21,	\N	\N	2	\N	2025-08-13 23:35:56.994412	\N	\N	\N	\N	1954-07-17
2025	4434	\N	\N	MOUAGA	Lyce	\N	\N	\N	\N	\N	\N	teacher	\N	,21,	\N	\N	2	\N	2025-08-13 23:36:43.728211	\N	\N	\N	\N	1995-08-18
2025	4435	\N	\N	OKO	rose	\N	\N	\N	\N	\N	\N	teacher	\N	,21,	\N	\N	2	\N	2025-08-13 23:37:51.65914	\N	\N	\N	\N	1959-09-18
2025	4436	\N	\N	LEGOUNGA	Basilia	\N	\N	\N	\N	\N	\N	teacher	\N	,21,	\N	\N	2	\N	2025-08-13 23:39:07.45464	\N	\N	\N	\N	1995-12-16
2025	4437	\N	\N	Bernish	NGAKOSSO	\N	\N	\N	\N	\N	\N	teacher	\N	,21,	\N	\N	2	\N	2025-08-13 23:40:40.531027	\N	\N	\N	\N	1957-09-18
2025	4438	\N	\N	Sandrine	EBAKA	\N	\N	\N	\N	\N	\N	parent	\N	\N	\N	\N	3	\N	2025-08-13 23:41:32.613675	\N	\N	\N	\N	1999-10-18
2025	4439	\N	\N	Sandrine	Ebata	\N	\N	\N	\N	\N	\N	teacher	\N	,21,	\N	\N	2	\N	2025-08-13 23:42:40.41324	\N	\N	\N	\N	1965-11-18
2025	1	21	Mr	Super	Admin	\N	\N	admin	$6$8feef8e679ca880d$JpsUJKuSu7v5FUEo25np1/eWKzUTwA5M5SlrfsKX0rX7psiFP6YwW0pNUvnspRXgYahhLKB2EefIroNm5ocSH/	\N	\N	admin	\N	,21,16,17,18,19,	2025-09-24 22:36:17.840188	\N	1	\N	2023-08-01 22:43:31.104393	2025-09-24 22:36:17.840188	\N	\N	\N	1961-10-18
\.


--
-- Data for Name: staff_exceptions; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.staff_exceptions (user_id, modname, can_use, can_edit, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: staff_field_categories; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.staff_field_categories (id, title, sort_order, columns, include, admin, teacher, parent, "none", created_at, updated_at) FROM stdin;
1	General Info|fr_FR.utf8:Infos générales	1	\N	\N	Y	Y	Y	Y	2023-08-01 22:43:31.104393	2023-08-01 22:43:35.376882
2	Schedule|fr_FR.utf8:Emploi du temps	2	\N	\N	\N	Y	\N	\N	2023-08-01 22:43:31.104393	2023-08-01 22:43:35.376882
3	Food Service|fr_FR.utf8:Cantine	3	\N	Food_Service/User	Y	Y	\N	\N	2023-08-01 22:43:31.104393	2023-08-01 22:43:35.376882
5	Profil utilisateur	4	1	\N	\N	\N	\N	\N	2023-08-15 14:44:22.636415	2023-08-15 14:47:22.317778
\.


--
-- Data for Name: staff_fields; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.staff_fields (id, type, title, sort_order, select_options, category_id, required, default_selection, created_at, updated_at) FROM stdin;
200000000	text	Email Address|fr_FR.utf8:Adresse email	0	\N	1	\N	\N	2023-08-01 22:43:31.104393	2023-08-01 22:43:35.376882
200000001	text	Phone Number|fr_FR.utf8:Numéro de téléphone	1	\N	1	\N	\N	2023-08-01 22:43:31.104393	2023-08-01 22:43:35.376882
200000003	select	Pomoteur	\N	\N	5	\N	\N	2023-08-15 14:48:56.50295	\N
200000004	text	Occupation|fr_FR.utf8:Profession	2	\N	1	\N	\N	2024-07-30 14:31:22.055677	\N
200000005	date	date of birth |fr_FR.utf8: date de naissance	3	\N	1	Y	\N	2024-07-30 14:32:07.159775	\N
\.


--
-- Data for Name: student_assignments; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.student_assignments (assignment_id, student_id, data, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: student_eligibility_activities; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.student_eligibility_activities (syear, student_id, activity_id, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: student_enrollment; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.student_enrollment (id, syear, school_id, student_id, grade_id, start_date, end_date, enrollment_code, drop_code, next_school, calendar_id, last_school, created_at, updated_at, second_course_period_id, semester, second_semester, course_period_id, second_grade_id) FROM stdin;
196	2025	21	44444454	47	2025-09-08	\N	2	\N	21	4	\N	2025-09-08 11:40:35.443146	2025-09-08 11:55:21.492569	\N	\N	\N	25	\N
197	2025	21	44444455	47	2025-09-08	\N	2	\N	21	4	\N	2025-09-08 11:41:49.083176	2025-09-08 11:56:40.325773	\N	\N	\N	25	\N
232	2025	21	44444461	47	2025-09-12	\N	2	\N	21	4	\N	2025-09-12 11:28:27.880746	\N	\N	\N	\N	25	\N
234	2025	21	44444463	47	2025-09-12	\N	2	\N	21	4	\N	2025-09-12 11:36:50.124886	\N	\N	\N	\N	24	\N
235	2025	21	44444464	47	2025-09-12	\N	2	\N	21	4	\N	2025-09-12 11:37:05.68522	\N	\N	\N	\N	24	\N
236	2025	21	44444465	47	2025-09-12	\N	2	\N	21	4	\N	2025-09-12 11:37:43.137674	\N	\N	\N	\N	24	\N
237	2025	21	124	47	2025-09-12	\N	2	\N	21	4	\N	2025-09-12 11:41:57.806508	\N	\N	\N	\N	24	\N
233	2025	21	44444462	47	2025-09-12	\N	2	\N	21	4	\N	2025-09-12 11:36:37.912465	\N	\N	\N	\N	24	\N
238	2025	21	133	47	2025-09-24	\N	1	\N	21	4	\N	2025-09-24 22:41:41.93859	\N	\N	\N	\N	\N	\N
239	2025	21	134	47	2025-09-24	\N	1	\N	21	4	\N	2025-09-24 22:41:41.943547	\N	\N	\N	\N	\N	\N
240	2025	21	135	47	2025-09-24	\N	1	\N	21	4	\N	2025-09-24 22:41:41.94545	\N	\N	\N	\N	\N	\N
241	2025	21	136	47	2025-09-24	\N	1	\N	21	4	\N	2025-09-24 22:41:41.94976	\N	\N	\N	\N	\N	\N
242	2025	21	137	47	2025-09-24	\N	1	\N	21	4	\N	2025-09-24 22:41:41.952126	\N	\N	\N	\N	\N	\N
243	2025	21	138	47	2025-09-24	\N	1	\N	21	4	\N	2025-09-24 22:41:41.954067	\N	\N	\N	\N	\N	\N
244	2025	21	139	47	2025-09-24	\N	1	\N	21	4	\N	2025-09-24 22:41:41.95646	\N	\N	\N	\N	\N	\N
245	2025	21	140	47	2025-09-24	\N	1	\N	21	4	\N	2025-09-24 22:41:41.957858	\N	\N	\N	\N	\N	\N
246	2025	21	141	47	2025-09-24	\N	1	\N	21	4	\N	2025-09-24 22:41:41.959361	\N	\N	\N	\N	\N	\N
247	2025	21	142	47	2025-09-24	\N	1	\N	21	4	\N	2025-09-24 22:41:41.960895	\N	\N	\N	\N	\N	\N
248	2025	21	143	47	2025-09-24	\N	1	\N	21	4	\N	2025-09-24 22:41:41.962444	\N	\N	\N	\N	\N	\N
249	2025	21	144	47	2025-09-24	\N	1	\N	21	4	\N	2025-09-24 22:41:41.965114	\N	\N	\N	\N	\N	\N
250	2025	21	145	47	2025-09-24	\N	1	\N	21	4	\N	2025-09-24 22:41:41.967089	\N	\N	\N	\N	\N	\N
251	2025	21	146	47	2025-09-24	\N	1	\N	21	4	\N	2025-09-24 22:41:41.968915	\N	\N	\N	\N	\N	\N
252	2025	21	147	47	2025-09-24	\N	1	\N	21	4	\N	2025-09-24 22:41:41.971115	\N	\N	\N	\N	\N	\N
253	2025	21	148	47	2025-09-24	\N	1	\N	21	4	\N	2025-09-24 22:41:41.972505	\N	\N	\N	\N	\N	\N
\.


--
-- Data for Name: student_enrollment_codes; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.student_enrollment_codes (id, syear, title, short_name, type, default_code, sort_order, created_at, updated_at) FROM stdin;
1	2025	Transfert	TRAN	Drop	Y	2	2025-08-08 13:50:29.902413	\N
2	2025	Début d'année	DEB	Add	Y	1	2025-08-08 13:51:51.73564	\N
3	2025	Autre district	AUTR	Add	Y	3	2025-08-08 13:53:28.306967	\N
4	2025	Expulsé	EXP	Drop	Y	4	2025-08-08 13:55:16.941019	\N
5	2025	Départ	DEP	Drop	Y	5	2025-08-08 13:56:42.353594	\N
\.


--
-- Data for Name: student_enrollment_course_periods; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.student_enrollment_course_periods (id, student_enrollment_id, course_period_id, created_at, updated_at) FROM stdin;
49	196	25	2025-09-08 11:55:21.527811	2025-09-08 11:55:21.527811
50	197	25	2025-09-08 11:56:40.361194	2025-09-08 11:56:40.361194
51	232	25	2025-09-12 11:35:12.592029	2025-09-12 11:35:12.592029
52	196	25	2025-09-12 11:35:28.901485	2025-09-12 11:35:28.901485
53	233	24	2025-09-12 11:36:37.937741	2025-09-12 11:36:37.937741
54	234	24	2025-09-12 11:36:50.151803	2025-09-12 11:36:50.151803
55	235	24	2025-09-12 11:37:05.706058	2025-09-12 11:37:05.706058
56	236	24	2025-09-12 11:37:43.162552	2025-09-12 11:37:43.162552
57	233	24	2025-09-12 11:38:00.600725	2025-09-12 11:38:00.600725
58	237	24	2025-09-12 11:41:57.832397	2025-09-12 11:41:57.832397
59	233	24	2025-09-12 12:30:40.545266	2025-09-12 12:30:40.545266
60	233	24	2025-09-12 12:33:03.119205	2025-09-12 12:33:03.119205
61	233	24	2025-09-12 12:41:24.981363	2025-09-12 12:41:24.981363
62	233	24	2025-09-12 12:42:15.167776	2025-09-12 12:42:15.167776
63	233	24	2025-09-12 13:32:35.746907	2025-09-12 13:32:35.746907
64	233	24	2025-09-12 13:32:39.423467	2025-09-12 13:32:39.423467
65	237	24	2025-09-24 22:36:46.579054	2025-09-24 22:36:46.579054
66	237	24	2025-09-24 22:37:55.892449	2025-09-24 22:37:55.892449
68	237	24	2025-09-24 22:42:25.544903	2025-09-24 22:42:25.544903
\.


--
-- Data for Name: student_field_categories; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.student_field_categories (id, title, sort_order, columns, include, created_at, updated_at) FROM stdin;
1	General Info|fr_FR.utf8:Infos générales	1	\N	\N	2023-08-01 22:43:31.104393	2023-08-01 22:43:35.376882
2	Medical|fr_FR.utf8:Médical	3	\N	\N	2023-08-01 22:43:31.104393	2023-08-01 22:43:35.376882
3	Addresses & Contacts|fr_FR.utf8:Adresses et contacts	2	\N	\N	2023-08-01 22:43:31.104393	2023-08-01 22:43:35.376882
4	Comments|fr_FR.utf8:Commentaires	4	\N	\N	2023-08-01 22:43:31.104393	2023-08-01 22:43:35.376882
5	Food Service|fr_FR.utf8:Cantine	5	\N	Food_Service/Student	2023-08-01 22:43:31.104393	2023-08-01 22:43:35.376882
\.


--
-- Data for Name: student_medical; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.student_medical (id, student_id, type, medical_date, comments, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: student_medical_alerts; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.student_medical_alerts (id, student_id, title, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: student_medical_visits; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.student_medical_visits (id, student_id, school_date, time_in, time_out, reason, result, comments, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: student_mp_comments; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.student_mp_comments (student_id, syear, marking_period_id, comment, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: student_mp_stats; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.student_mp_stats (student_id, marking_period_id, cum_weighted_factor, cum_unweighted_factor, cum_rank, mp_rank, class_size, sum_weighted_factors, sum_unweighted_factors, count_weighted_factors, count_unweighted_factors, grade_level_short, cr_weighted_factors, cr_unweighted_factors, count_cr_factors, cum_cr_weighted_factor, cum_cr_unweighted_factor, credit_attempted, credit_earned, gp_credits, cr_credits, comments, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: student_report_card_comments; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.student_report_card_comments (syear, school_id, student_id, course_period_id, report_card_comment_id, comment, marking_period_id, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: student_report_card_grades; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.student_report_card_grades (syear, school_id, student_id, course_period_id, report_card_grade_id, report_card_comment_id, comment, grade_percent, marking_period_id, grade_letter, weighted_gp, unweighted_gp, gp_scale, credit_attempted, credit_earned, credit_category, course_title, id, school, class_rank, credit_hours, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: students; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.students (student_id, last_name, first_name, middle_name, name_suffix, username, password, last_login, failed_login, custom_200000000, custom_200000001, custom_200000002, custom_200000003, custom_200000004, custom_200000005, custom_200000006, custom_200000007, custom_200000008, custom_200000009, custom_200000010, custom_200000011, created_at, updated_at) FROM stdin;
2	Daryon	Daryon	Dd	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2025-08-08 09:09:33.852878	\N
3	Daryon	Daryon	Dd	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2025-08-08 09:11:58.72826	\N
6	Doe	John	Do	\N	\N	\N	\N	\N	Masculin	Noir, non hispanique	\N	\N	2004-04-01	\N	\N	\N	\N	\N	\N	\N	2025-08-08 13:38:22.021794	\N
1	Lié	Orphée	\N	\N	lieloumloum@gmail.com	$6$a336c6f06cf3ee3f$IJCnCX7PwVzC0C4.kdpeDmpV0JPzdHrg0s/JvnKVIj3AUY3b2yPFkazeLJXL47a9U/MYe1AG0cB8AgjoycTSA1	2025-08-08 14:27:39.023875	\N	Masculin	Noir, non hispanique	Phée	ttytytyi	2002-12-01	Français	\N	\N	\N	\N	\N	\N	2025-08-07 17:30:46.611175	2025-08-08 14:27:39.023875
3333333	b'boy	b'boy	\N	\N	b'boy@icloud.com	$6$7661a66403083152$ctfudFHO.Idw1dR77gLN.XjMqS./uzM9o/x40IHapO9C6a4Is71b8Tddro7/jCImB8VIJOciqGvzQFx2kPfM10	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2025-08-14 16:09:04.235451	\N
12345	lucas	michel	\N	\N	lucas@gmil.com	$6$431863b676abe9e9$v7c1h68KtI/sIN8ny1xhC.btdxbIy3KgvGQn/YRfpAtnaDB3gf/b75m4VGpiEuIMIWuB0P9WLFaL8e8tiuo2H1	\N	\N	Masculin	Noir, non hispanique	speedy	\N	2012-01-06	Français	\N	\N	\N	\N	\N	\N	2025-08-14 16:35:50.958859	\N
1212	Speedy	daryon	\N	Sr	dar@icloud.com	$6$a9d042c9f45f3910$LGtMjT66wN33d23us07y1IhL.lvnk3v/tCBTKRym6TL9gCFNe1Xt.ZZF671ZktmfquqFtAzcFViFpleSz2pD2/	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2025-08-14 16:47:02.407731	\N
1111111	rocknes	daryon	\N	\N	daryon@icloud.com	$6$59ddef1eed31b7bf$h53gnToNaNCt2ciA9nFJBAmLozOcGm7hwAxdj20G62C5iZh7p6KLf05J219mGLj/mLkVyjGvNW/BDQtHXNTJI.	\N	\N	Masculin	Noir, non hispanique	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2025-08-14 16:07:25.501769	\N
222222	Speedy	michel	\N	\N	michel@icloud.cm	$6$3b7daaf36da8a363$9oZ31kHbCJgFsY86HNIllKZCNq16rUzxOemEfEagyp7rJHhDOxnZqUn.wSFzYDq0ICLpQrfvqo0plNu2uPspO.	\N	\N	Masculin	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2025-08-14 16:08:14.581208	\N
5	Mouanz	Ange	Mahd	\N	lie@gmail.com	$6$d6d92e90f1dfcce0$Q9dtstQWrubtzmg9hu.aWhHYJppwAIWifxsYnZhZfGlvRgEBr2AJL6prG2gXfEKt747lajjbaAMvYTlCnLAMO0	\N	\N	Masculin	Noir, non hispanique	\N	\N	2002-03-01	Français	\N	\N	\N	\N	\N	\N	2025-08-08 09:28:50.168803	\N
121345	daryon	daryon	encore	\N	rocknes@icloud.com	$6$9b84fdd868eb2701$Lx4ROBQdlpN2w9tT9lgqDk.iTLtfj3TaYIa1eJe1l42jdjxsH6B0Js.zS9AJCcgPp8HlOsfOOKW5PiGQqCdTy.	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2025-08-27 14:13:34.279887	\N
99	malonga	jonathn	\N	\N	jonathan@gmail.com	$6$6700fef95bdd1ebd$ALUP49Cgyx07Xnx51t7ncdWaKn6GZla1Nb3tTTfkQtvu8KPh/z0.I/giBRVq0l1/3LnA8co1oStj8EpkHpGHO.	\N	\N	Masculin	Blanc, non hispanique	\N	\N	1945-01-01	Français	\N	\N	\N	\N	\N	\N	2025-08-27 14:26:14.078648	\N
98	malanda	mercia	\N	\N	mercia@gmail.com	$6$b9f27f5c299c90d1$3E7uEKyM8/QkqPy4RRdb/ezhAk2Sqyb9wPuZksFxPJfmXrmkTM4bpY3oIBHgtFVtMw7.ntC4asDTRmppTrPqr.	\N	\N	Féminin	Blanc, non hispanique	\N	\N	1960-07-13	Français	\N	\N	\N	\N	\N	\N	2025-08-27 14:45:22.879746	\N
97	malonga	mercia	\N	\N	mmercia@icloud.com	$6$04f72610bc7ca017$Ob6q2Ws9PpP1K2QsDR8.bb.3XVnvjNxPykG8sRWPQ43wsZLaX2rohvL.oPWTccRqq9CjxVIbXvPeZy/InbSdo0	\N	\N	Masculin	Noir, non hispanique	\N	\N	\N	Français	\N	\N	\N	\N	\N	\N	2025-08-27 15:24:34.646498	\N
94	malonga	mercia	\N	\N	mercia@icloud.com	$6$8cc832c9d6925761$ik1qdY/za4fXW6kaWqRDlNuJVur0UpUPM3E95MEPNcOq6L7EtXTHnH6WH/.fFvNcDsOjuGyA7yjD7WauyfOaF1	\N	\N	Masculin	Blanc, non hispanique	\N	\N	1958-09-16	Français	\N	\N	\N	\N	\N	\N	2025-08-27 15:40:54.89303	\N
101	tomba	junior	\N	\N	junior@icloud.com	$6$9e65c01a52cdcebd$sKx5d7qNkwERpX4nNkkELzO87l/amuXiIpxBx2ABhr8lGMOd7P1Z0GwWHS25OSg9Dh8PTQQQadBEliqmhd4vF1	\N	\N	Masculin	Hispanique	\N	\N	\N	Français	\N	\N	\N	\N	\N	\N	2025-08-27 15:56:39.596237	\N
167	mavila	danielle	\N	\N	danielle@gmail.com	$6$30bdd954ef7e82ee$1OKwRT5bzqof.T4dmdfgmCi2uYI/vc7So/6.U9TR4835rm.jXWdqmuVOmNdIGJlRIL9Ou/G9yjArKUIuwqW9a.	\N	\N	Féminin	Noir, non hispanique	\N	\N	1946-02-02	Français	\N	\N	\N	\N	\N	\N	2025-08-28 08:58:31.331568	\N
88	mavila	danielle	\N	\N	danielle@gmail	$6$7301e75a3d58bf03$sIRHG6TIVOjLMEZLhWfhRUPJn1Wboe1R9/kg5RU6brcv6FN9Eu7byKD4.9Inj.SIn2QPSqCYf0z61NU9wxqtC1	\N	\N	Féminin	\N	\N	\N	1945-02-02	\N	\N	\N	\N	\N	\N	\N	2025-08-28 09:04:25.170061	\N
189	ndala	espoir	\N	\N	espoir@gmail.com	$6$7f5577b0b69a9849$78/OWmUt3lo5k.mY2gxlv8bLKjg8FNFIShnyJ2sQrVi.iMlaeXSlXghyp4XWZGFbfBg7ZELo2gxwfdmKNYuAo/	\N	\N	Masculin	Blanc, non hispanique	\N	\N	1945-01-02	Français	\N	\N	\N	\N	\N	\N	2025-08-28 09:43:23.578895	\N
188	merite	divin	\N	\N	merite@icloud.com	$6$94db6d33635c82cc$TGYZpxOMVo7CE3W5HAlX6gnFALhMdDVLM4W7urDSduBWS5OjV5MgP5hTUv59D.DuvfKCifRcya2oa2U9Jp6OS1	\N	\N	Masculin	Noir, non hispanique	\N	\N	1945-01-02	\N	\N	\N	\N	\N	\N	\N	2025-08-28 09:57:49.964955	\N
181	mika	yoan	\N	\N	yoan@icloud.com	$6$b540fa557bb88b35$7IAXXG4goQhDbrlxUmKEf9R6ThTQdE/Q/RL9AxtotFiB8VRIrkvK8LeV8UImXQjCzS/uP8mQbZ3yiZy1Bves6.	\N	\N	Masculin	Blanc, non hispanique	\N	\N	\N	Français	\N	\N	\N	\N	\N	\N	2025-08-28 10:04:54.66434	\N
175	ngoma	leon	\N	\N	leon@gmail.com	$6$57d9a5669fe2fb44$f9XbMTHs2MjIwlM6vBVC9kzznm4BHgd38m1FokmwbYrtH8bLG3df/YjpGdiQKYeARDo/pBmDmB3eY1NGJzgMA0	\N	\N	Masculin	\N	\N	\N	1959-03-01	Français	\N	\N	\N	\N	\N	\N	2025-08-28 10:17:02.784532	\N
173	oba	daniella	\N	\N	daniella@gmaill	$6$5ff878a89a85bb43$/LlcKrSDaSogXf8vu5i4ZrBvHdhFy4/nzbo700Hvuagjhw4pwp03lUu9K.atAcksUn8LUtwEwnr0o2xQbkVrL/	\N	\N	Masculin	Hispanique	\N	\N	1945-01-03	Français	\N	\N	\N	\N	\N	\N	2025-08-28 10:23:59.886094	\N
171	Samba	melanie	\N	\N	melanie@gmail.com	$6$be4f352a86d01dd1$Dp090qQxSaxh1xH1h0f.xo/XEUe2c6mN.pKTMRqyZzcw7WcsE0SVI7nClSqAwmHRT18oNjlVSa0uODYqywX.s.	\N	\N	\N	Blanc, non hispanique	\N	\N	1956-02-11	Français	\N	\N	\N	\N	\N	\N	2025-08-28 11:10:08.832065	\N
170	hortomi	oumba	\N	\N	oumba@gmail.com	$6$685e6c3969a31950$OgTUbdHL0TW1em.x4X327t8EacMXHh/Y1NUJsSKnmNi4exZtvCkkY1feAdm878g7O3Dn/CeEqLy0lv21byIpG1	\N	\N	Masculin	Blanc, non hispanique	\N	\N	1969-02-12	Français	\N	\N	\N	\N	\N	\N	2025-08-28 12:23:05.099336	\N
1800	mouz	rodri 	\N	\N	rodri@gmail.com	$6$b7d69100cfd54e19$XwO2DPzd05WlVMMZrywUQCq0Vr6MFnzGHY8yQ8MzX.hZk/fj7auuaWdsRhGnjPWNJLqoB.k/C.GvLJ.Zi..Gh0	\N	\N	Masculin	Asiatique	\N	\N	1947-04-02	Français	\N	\N	\N	\N	\N	\N	2025-08-28 14:01:58.244495	\N
888	tokyo	tokyo	\N	\N	tokyo@gmail.com	$6$8bb970badbfda69f$cmaskJz1ihV5r5p.SC/N0c/ABKKQr6j53a8/dWkSzBGvvxyDDg3DYyvkLkl319L.59MGYQowE5Xv.4VYkVMHP0	\N	\N	Masculin	Asiatique	\N	\N	1945-02-02	\N	\N	\N	\N	\N	\N	\N	2025-08-28 14:52:44.971447	\N
889	boua	henry	\N	\N	henry@icloud.com	$6$1d6f87e889df2fb2$Tj1GcX4JRroQ2CXZmAp4lk60xwl5H0cCsd832XhwPcKTF5MOUq0xf5zyEBt5DXYjxUX4OChGqs8aU0CbNKwzl/	\N	\N	Masculin	Blanc, non hispanique	\N	\N	1956-03-11	Français	\N	\N	\N	\N	\N	\N	2025-08-28 14:57:36.118943	\N
887	bokaz	harris	\N	\N	harris@gmail.com	$6$596d5010369b15a9$PiNVOXNzMLQXUCGgCIu0rCGRvkg1OTXlpuaB2n4PkNih3Z9BvuoP4BNC2KV3oqRj8FNHiXHGcXb9zBnV/6NXG0	\N	\N	Masculin	Hispanique	\N	\N	1946-01-02	Français	\N	\N	\N	\N	\N	\N	2025-08-28 15:10:10.616559	\N
885	noki	noki	\N	\N	noki@gmail.com	$6$0aac9d6ad5601e04$ENSNANQThpFen4FIh4dXT5Vc/rdkw57vPEsiRBY0CPmy2f3Zz9EdC0SFUjzV4fV9BIRcihSbsrnl/BpgrhJ8h0	\N	\N	Masculin	Hispanique	\N	\N	2014-06-09	\N	\N	\N	\N	\N	\N	\N	2025-08-28 15:15:11.910685	\N
884	omba	meddy	\N	\N	meddy@gmail.com	$6$a820786d08c21472$0MFhCIrNYeMndkCtgSDxhUf/FPGk93W2B7Dxv9/FFtiosxqAB2mwiB6GVM9m/ZsjdYMU5pcLT/IavUgltu8n1/	\N	\N	Masculin	Asiatique	\N	\N	1960-03-03	\N	\N	\N	\N	\N	\N	\N	2025-08-28 15:21:45.448666	\N
883	fils	eto	\N	\N	eto@gmail.com	$6$38dc141d03f4e7ac$br615P6.hfcnZ6ngl.HjGQTvecN8ci0HrwQGvG8aXTXMxr3TXR9s51.aOHbj75V9WOqxD7hoqvEmvApaFHgC41	\N	\N	Masculin	Asiatique	\N	\N	1946-03-03	Français	\N	\N	\N	\N	\N	\N	2025-08-28 15:35:54.108563	\N
882	mouz882	mouz	\N	\N	mouz@gmail	$6$984e3e681753ac38$OH9LADovlhOgR3iMcxLgmppnlZHI/Ih1aXTXU1pivbRCslrUNeBSxhNrN/QMMo2TZqSxWDeTvIMMGXb8ethBb.	\N	\N	Masculin	Blanc, non hispanique	\N	\N	1946-03-02	Français	\N	\N	\N	\N	\N	\N	2025-08-28 15:41:32.679428	\N
881	home	hume	\N	\N	home@gmai.com	$6$915c03745f760c6d$wTQSqp11io5DPbiU2ItlkOjfwPRbay/xrZJsaeqjkp1V1yIDsW2iUyySrObUWGlV6sm4NGxGUrG4I3QFXb1YX1	\N	\N	Masculin	Blanc, non hispanique	\N	\N	1959-10-18	\N	\N	\N	\N	\N	\N	\N	2025-08-28 15:53:16.415933	\N
880	pouma	pouma	\N	\N	pouma@gmail.com	$6$7fb990003f0c5af7$GrjtsLpPvtOOkuCfhxuIKiIcU0Yxd5VvqArzjaobVwbpOTknknBYru4Tnr/pQunok/t6aeuPy4auIsukWaDEs1	\N	\N	Masculin	Asiatique	\N	\N	1960-10-18	Français	\N	\N	\N	\N	\N	\N	2025-08-28 16:05:15.673663	\N
879	gomez	pedri	\N	\N	pedri@gmail.com	$6$4ab04e6583e1ef84$boiiJyiZm41Sjh7iYbRQvJwlnOMISUwzlPLSlcWfeRQuuQMc1YdRSUN3lyem0NNvECKFRa29I2lRkGEryg7Jo0	\N	\N	Masculin	Blanc, non hispanique	\N	\N	1946-03-02	\N	\N	\N	\N	\N	\N	\N	2025-08-28 16:13:42.860734	\N
876	ange	mariz	\N	\N	mariz@gmail.com	$6$64095715a00dc533$RdLsfFi5oSKmlXT31yrXkgZJ9nt7e6Y1f3wvBNeXiwW0zvnsv4blwAFqBraHQLiKWb2viXZfI8fkmyfWbWwZ31	\N	\N	Masculin	Blanc, non hispanique	\N	\N	1957-10-15	Anglais	\N	\N	\N	\N	\N	\N	2025-08-28 16:25:45.270122	\N
870	ondelé	Grace	benie	\N	grace@gmail.com	$6$5cb2fe2948712c46$dewP2xavQnhtSsiRB52dNV/97UlhnNnpXyYcQtk8lhtes21FvoDj819PgVY.IhXYyM3LYMhhPOI1Fs2.YTNzN/	\N	\N	Masculin	Blanc, non hispanique	GraceBeni 	\N	1953-09-09	Français	\N	\N	\N	\N	\N	\N	2025-08-29 08:50:59.049253	\N
869	mitikou	horcia	\N	\N	horcia@gmail.com	$6$6ffc3c5ea05e4a14$zUQ0PMFCSSYhhzuffefU7VuybSAHy/3OWxIiuu6cNb6txWPRjYY/eez8dwvo.D5gEB5StIiUeyG.lAz/26MDI1	\N	\N	Masculin	Blanc, non hispanique	\N	\N	1960-11-18	Français	\N	\N	\N	\N	\N	\N	2025-08-29 11:18:56.560646	\N
868	mora	horci	\N	\N	horci@gmal.com	$6$84735664daec118e$mtQEhGcjlwcJ9w3WTwBZRjZUjbemGv4oXG/j6LI2/INFEss4iJRGosQnQUDwTnkrvc5jtNZfvQuIXXtE4W5x.1	\N	\N	Masculin	Blanc, non hispanique	\N	\N	1960-09-17	Français	\N	\N	\N	\N	\N	\N	2025-08-29 11:26:36.203206	\N
866	koumou	rodricia	\N	\N	rodricia@gmail.com	$6$942acab711e8fa53$5BlDZGjKYpce4anTipFbpFgPCMalSJp9YsecYtGWYayarkuJac6gzPgqz8uDtp3802QNTj4lQXb4YWy16BznC/	\N	\N	Masculin	Noir, non hispanique	\N	\N	1958-03-14	\N	\N	\N	\N	\N	\N	\N	2025-08-29 11:30:53.498362	\N
862	mbalanganza	Gegrouard	\N	\N	gegrouard@gmail.com	$6$ea32b32cf5bf5aa0$q7KU4ow6CPihKVhVXRkcKMPDvghuvtFbmDTl/GkRadWcJTR2L2.6AK.QKfF4vFspLTN4rF5UMYgKSAcfgrzml/	\N	\N	Masculin	Blanc, non hispanique	\N	\N	1961-10-12	Français	\N	\N	\N	\N	\N	\N	2025-08-29 11:38:11.264606	\N
863	moussa	grada	\N	\N	grada@gmail.com	$6$e85654184c5a63af$8eCP2Su9cg0gf9ZxWEwoIkKyYtF8e7L8Pksp37XtLF4SOAQ0Xs6u2N9IvHeLLR3fGAG9xS2sMV2JLdYDJqBLx1	\N	\N	Masculin	Noir, non hispanique	\N	\N	1957-08-13	Français	\N	\N	\N	\N	\N	\N	2025-08-29 11:45:23.016428	\N
860	ouma	marie	\N	\N	marie@gmail	$6$d099c5de31ce0920$C/SH8x.EIHsOGPfeB61T66Q29VVBCn1qKDPJOgP8PmM9T9tlWL/.DWDstWcQZLmKx4cQD25iaPZVv.jWRH2Ue1	\N	\N	Masculin	Asiatique	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2025-08-29 11:47:36.728092	\N
44444444	mouka	mika	\N	\N	mika@gmail.com	$6$b4dba3152f2722e9$WQfxZqUylbXU.KvT9edPzDEohW2SeUlS3yHdjfw9GPUvuh6g65RFmTDrcWnZWFF6JN5gMgL6anMVEZsmncv5x1	\N	\N	Masculin	Blanc, non hispanique	\N	\N	1947-02-04	\N	\N	\N	\N	\N	\N	\N	2025-08-29 12:01:04.153217	\N
859	boua	jonathn	\N	\N	jonathan@icloud.com	$6$346a068c1b969530$V80HJd1Hpw943uQOozDuONAqobNUkHwwVg9iNHf55NEK1X0Q/cOKm.gvY6h5cysjIjzYlBeu4OgEIMHUivGbn1	\N	\N	Masculin	Noir, non hispanique	\N	\N	1958-02-13	\N	\N	\N	\N	\N	\N	\N	2025-08-29 12:06:59.171378	\N
852	dorcas	dorcas	\N	\N	dorcas@icloud.com	$6$ac3ba01c5942197f$YCktApX3iUAp71w0r3Tgd21ICMFEGdBLoHESUE6sGGmsUZFI/Es/tYeq8TI/RMJaNVKnYeIMWK24/kcUfVi18.	\N	\N	Masculin	Noir, non hispanique	\N	\N	1954-01-14	\N	\N	\N	\N	\N	\N	\N	2025-08-29 13:24:45.167366	\N
851	dom	domunique	\N	\N	domunique@gmail	$6$d36049ff0f13fd87$DY5OUnHV6Mg.MwIgWNjVGw7SAKQB6uiqwKu1zM8rKfAt1d.PIYlFJbwNNJUmHzgEKyjKb5yZ4len3ws8gRgF70	\N	\N	Féminin	Blanc, non hispanique	\N	\N	1946-02-02	\N	\N	\N	\N	\N	\N	\N	2025-08-29 13:46:14.960183	\N
850	malou	moula	\N	\N	moula@gmail.com	$6$ef63caf122625800$D6sQ/8l27yIyfRjXeU0eTFYm2EQfKyGhpP0KSKMjJDFCnKolzcEtfWof5Xzy8Z3S7oadcCMoXlzcIcH8XPzGz0	\N	\N	Masculin	Blanc, non hispanique	\N	\N	1959-08-15	Français	\N	\N	\N	\N	\N	\N	2025-08-29 13:49:21.770584	\N
853	koumu	doria	\N	\N	doria@gmail.com	$6$00be8392db41904f$U8IPs.7FhgwE1HhpwPXDVDh.c0D4Ee585UZUDGNrk/Q8T3pRvz6.tfvzgLcPFFULwi9RNQdDdg2.XTo/70S4N/	\N	\N	Masculin	Blanc, non hispanique	\N	\N	1957-01-12	Français	\N	\N	\N	\N	\N	\N	2025-08-29 13:51:14.669669	\N
849	mampouya	doricina	\N	\N	doricina@gmail.com	$6$22a5a4759b6ce514$c6pJs.M6krBUmtCF0pklyKmYIx0lDXibqesI0fVzdLSE3enOxWz/bmkOfXd9dUDCiWQ85jQw4K9Tr.LYDJd9k0	\N	\N	Masculin	Blanc, non hispanique	\N	\N	1955-07-10	\N	\N	\N	\N	\N	\N	\N	2025-08-29 14:01:53.210972	\N
848	samba	viviane	\N	\N	viviane@gmail.com	$6$ae9b2468776a09a1$GwvfVYfvODnPaCEDpTTdZuBBDjQM5OzFCDvB6zGCfqW1we.Z5ebwug5uGUfo7PVRaVLPcQnhKHRdUkJIAYmUS0	\N	\N	Masculin	Blanc, non hispanique	\N	\N	1958-09-13	\N	\N	\N	\N	\N	\N	\N	2025-08-29 14:05:01.834345	\N
44444445	malonga	daryon	encore	\N	pure@gmail.com	$6$83fac521cd3ec08a$iSFP0sVf7S5ui5yn8BPv1jTWmmr3Vhjf2frDoacwLkgQYPVN2Sb3xJeUOaNl.n5Y3MNNiIoS2a0QqI8yxLsnt/	\N	\N	Masculin	Noir, non hispanique	\N	\N	1957-02-11	Français	\N	\N	\N	\N	\N	\N	2025-08-29 14:21:41.296856	\N
44444446	morgan	parise 	\N	\N	parise@gmail.com	$6$c6b7d6386ec63e5a$9lzs9EZ1tOIZXzOX2Fxc/GHnU.91e77V0stBh2NHocB5YmUETATGSB3r8mGWpHaEYq5Xxbzm/Wwo.yrYCdwil/	\N	\N	Masculin	Blanc, non hispanique	\N	\N	1961-10-28	Français	\N	\N	\N	\N	\N	\N	2025-08-29 15:04:06.179	\N
44444447	nzo	patrick	\N	\N	patrick@gmail.com	$6$d35aa46b21f4f884$5.gyk/8.QrIN/y.qVbwZ7t7itaccgsho4sZiyHWn1eGWCl2/7Dyfo8m1iE3FlMwtk8coHKmcJG9Om5.10QjUw1	\N	\N	Masculin	Blanc, non hispanique	\N	\N	1960-09-28	\N	\N	\N	\N	\N	\N	\N	2025-08-29 15:09:15.936859	\N
44444454	ngoma	dieuveil	\N	\N	ngoma@gmail.com	$6$0c6f80bc1ba07d06$RSmDKrg1p5XLoLUp2QEfmH89EOmteGb7AiJGRNyKyB.R1iQm5ON7dc.qLTJ0UyeiZJtPh6SCmMhslR7WF.AZP1	\N	\N	Masculin	Noir, non hispanique	\N	\N	1953-09-09	\N	\N	\N	\N	\N	\N	\N	2025-09-08 11:40:35.437255	\N
44444450	moup	merica	\N	\N	moup@icloud.com	$6$4dd39a2df7b87e82$HNjMtpLRSu4r/4J3B7qt5jZ5Hi3gkS5gjgCzWS3dNt4fLEz5B/RBIQ0qcv1a9s8MxQxIXRIoQS2nPUOB99FAg/	\N	\N	Masculin	Blanc, non hispanique	\N	\N	1954-04-09	Français	\N	\N	\N	\N	\N	\N	2025-09-08 10:44:20.175478	\N
44444455	merite	divin	\N	\N	merite@gmail.com	$6$fa47adece8bd58e9$3eN9xB9bneX8UfPQN4pXaMSLwkerRmhUnxSsv8cS7m8gllXx7rn/rqmK.eRs32lNEZ665piE.ZQhvVzdV0XlR0	\N	\N	Masculin	Blanc, non hispanique	\N	\N	1956-09-12	Français	\N	\N	\N	\N	\N	\N	2025-09-08 11:41:49.073875	\N
44444449	batou	henry	\N	\N	batou@gmail.com	$6$1bd51745bd9eaac0$KMH17L3Nroo5T5DWEqndHx0L.iuT0gaFAcWjwg2u6.nvsd.e6XKdhLFChVvU2ibwWAWNVanLf8rlFaCft3YDl1	\N	\N	Masculin	Blanc, non hispanique	\N	\N	1958-10-08	\N	\N	\N	\N	\N	\N	\N	2025-09-08 10:40:48.395635	\N
44444448	rocknes	daryon	\N	\N	pablo@icloud.com	$6$e5f44f2f3d3955a9$Hp3plRpPkABAqQhlAlXRFXElWg8Yyv2KW7WpPtUfJnGt0juMykqeSvw3W5plfRH9mEFAMAK9CWV8mq4rohNyT/	\N	\N	Masculin	Noir, non hispanique	\N	\N	1953-11-18	\N	\N	\N	\N	\N	\N	\N	2025-09-08 10:26:01.060541	\N
44444452	mouzka	donad	\N	\N	mouzka@gmail.com	$6$361acf0c75fb52be$bDCY8BYnJrGM74wiuVtrbPcFmNikKT.867gMZL/WmKGyDOglV1FRMcRUrAIbSxYuhhhINNV53r3Oi8tJuJjp2/	\N	\N	Masculin	Blanc, non hispanique	\N	\N	1957-08-08	\N	\N	\N	\N	\N	\N	\N	2025-09-08 11:19:20.161512	\N
44444451	moukoko	Divine	\N	\N	moukoko@gmail.com	$6$5a534557d7cef3c3$n5za6qBaW.TCCrzAaIaVLM1xAP.4WklrFYEGlHYo/Cu2G5ha4D0uPwCVbHUUHC6JMpuu9bIV2s7RlmNgH5CK60	\N	\N	Masculin	Blanc, non hispanique	\N	\N	1958-09-17	\N	\N	\N	\N	\N	\N	\N	2025-09-08 11:14:09.934645	\N
44444453	nkaza	dieuveil	\N	\N	nkaza@gmail	$6$42223f9265cb1083$I.szna60Mrllj0ConMJqJAp.gUJxAlXwesYkl41jvig.zFKg2PG9SqvTfMiXPHjfv3TXz0ca3R/I7nQmDL2/G.	\N	\N	Masculin	Noir, non hispanique	\N	\N	1946-02-01	Français	\N	\N	\N	\N	\N	\N	2025-09-08 11:37:04.840772	\N
300012	Leroux	Noah	\N	\N	noah.leroux@example.com	$6$07dcc384ddc30012$Y.p15lrUJ6gV5z/AEqQpRBXRP9ovUPcwpXoYl2jNzoIP668ODjXGZsCH3vEXq74woggFKw9KUeV2q1QSH0fmP/	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2025-09-10 09:46:53.035148	\N
44444456	NGOMA	Albert	Michel	\N	\N	\N	\N	\N	Masculin	\N	\N	\N	2005-02-02	Français	\N	\N	\N	\N	\N	\N	2025-09-08 14:46:10.5047	\N
44444457	BAZOLA	Alino	Marco	\N	\N	\N	\N	\N	Masculin	\N	\N	\N	2011-04-06	Anglais	\N	\N	\N	\N	\N	\N	2025-09-08 14:52:45.844941	\N
2024001	Dupont	Jean	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2025-09-09 10:35:58.81619	\N
2024002	Martin	Marie	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2025-09-09 10:35:58.820806	\N
2024003	Durand	Pierre	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2025-09-09 10:35:58.822152	\N
2024004	Laurent	Sophie	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2025-09-09 10:35:58.823477	\N
2024005	Moreau	Thomas	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2025-09-09 10:35:58.824546	\N
44444458	OKO	Ruth	Erika	\N	\N	\N	\N	\N	Féminin	Blanc, non hispanique	\N	\N	2011-11-27	Français	\N	\N	\N	\N	\N	\N	2025-09-09 12:30:52.841566	\N
300006	Fontaine	Hugo	\N	\N	hugo.fontaine@example.com	$6$0ee962b5354d75f8$.MO5bcPYo9ryNuBcluVUfJ4NU7bhcVb82E.awSWYnOujP6ModMgY1JAShWpumzKSRfkYM/CwoJfZq62yqbbdd.	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2025-09-10 08:10:36.224242	\N
300007	Marchand	Emma	\N	\N	emma.marchand@example.com	$6$aa5bc3311be97aa2$iAS/W.EYQ8Afzp10A1SnDTmRi1LZ.kDRpfsX1V7iaKW/V3jr0QQ53RKoVY2DDZd3QSOv0aolqaVin.toZL6Qf.	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2025-09-10 08:10:36.233661	\N
300013	Barbier	Camille	\N	\N	camille.barbier@example.com	$6$80a42e31543d93ce$rbZb7XsWSfW2kamyQ3EiC.8z6Fq3qZk7Xtl3n40lBM/UX22BVwPRlLZZEmN4zhuptbQkEMX3bwulyb1FNSyvs.	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2025-09-10 09:49:59.343286	\N
300017	Blanchard	Théo	\N	\N	theo.blanchard@example.com	$6$74c91f16056e06bd$PTIwAFCdbNojt2HEZeg7SszzVWarczeZzk14i8R3h4L0axnpzdNkPAJa8wieSTLeqAl2ADJLrw2brGPKQ5ocE1	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2025-09-11 13:54:24.319529	\N
300018	Dumont	Clara	\N	\N	clara.dumont@example.com	$6$dd86652255c5998f$8RlKa/ssd7P2coAbQAqXKf5yH0yjnTLGNA7V2dF2QMa7rGOjRrPY0B/bRWEDLZ7XacnOvNJ363rvidW99j3d20	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2025-09-11 13:54:24.331866	\N
300015	Faure	Julien	\N	\N	julien.faure@example.com	$6$0c1ad2d62571901c$Z6Ci/qa4FGL2TJkrLGyWVZkBO2EpOUw8WFBERIySpsBtrElyl4r74PcN0U8yxKFzfn3aK0.bzUYJfE37OhEeg0	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2025-09-11 14:11:07.486536	\N
300016	Perrin	Manon	\N	\N	manon.perrin@example.com	$6$592841e0e96a2a2e$ncPsHgfyRXIylQsq6ReN7UotrDql0wdu862TYfw99PuSvcfWRnWituCCcwTuRLrZftEkk6RPlmHwnwKr3S6p70	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2025-09-11 14:37:02.026159	\N
300019	Renault	Lucas	\N	\N	lucas.renault@example.com	$6$74100e8fbe13c870$xpLOsQw9HziMCZA8fBC.7ocaPWtiXtfdWUyWCJofqFCSALhAZhcdYu7pfl73KPLUTzlddJvlibTWdxoumeRa8/	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2025-09-11 14:42:38.033212	\N
300020	Baron	Léa	\N	\N	lea.baron@example.com	$6$9fd41bce30b839c1$ATjR9x2UU8EYcWcqfoWJQ3U4GR.6wBcx6A6PXspPYmzzOcjBL/5Ieya4x2DW7yxSD0vflw0jSB09WPkHN0gcI.	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2025-09-11 14:44:51.073811	\N
300021	Giraud	Nathan	\N	\N	nathan.giraud@example.com	$6$119c8294c790e471$r76TbHr4B4qE4.BL3Ep1s.qT3L8809GVJVsQzzgIbugTlQ84UYPkqpfXiSHmZBbwOHc9BwX91GU.tyUrPBGn91	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2025-09-11 14:47:56.628012	\N
300022	Royer	Emma	\N	\N	emma.royer@example.com	$6$11375e92d94f9b47$hlqDfACpyXFGjjAn33vhPWA3vGv/aWrU9ybcms4X5232kt4fPWpRfSX217n4DMK5cjLc/leEEyGOeYdYuiRtI.	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2025-09-11 14:50:41.094906	\N
300023	Lopez	Tom	\N	\N	tom.lopez@example.com	$6$e21718a7df3c17cb$i2zl4BKdEU1ilC/U0r15ZxaHPhKfSM573vCR9t6w/giV8MvUQD4E4pfnewwLqOHAnIbRwdrderCnGxnMI4tg2/	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2025-09-11 14:57:32.540835	\N
300027	Poulain	Mathis	\N	\N	mathis.poulain@example.com	$6$cf19060dcd62ecb9$3m03qHc.6azuv33hZCJk15o5iA/skJeC1HIMP9Qj5sS7KHNiLXd3jvYqxfg9X/2WwZj2frn5bZ/p.8h79zDY81	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2025-09-11 15:09:22.245306	\N
300028	Fontaine	Zoé	\N	\N	zoe.fontaine@example.com	$6$2a61660c288cf79b$GVXt1lbqET0sZcV3O3zN841xTfOGTwkw/MWYybQaUCmPx8MvX1lg9xNCL7QoCmsJvEuBzB5je3QuEOyy2omBs/	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2025-09-11 15:11:10.365936	\N
300025	Perret	Ethan	\N	\N	ethan.perret@example.com	$6$0862b64605cac7af$Qt.8SMLvTqpEVCv3bnnxh41gH5oJqvpBWqh1m2hbWI7RM6M2PNBerA8g8j/fr4dMV1gYh2KjZAA05sYzVmVX//	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2025-09-11 15:16:35.030926	\N
300026	Inès	Inès	\N	\N	ines.collet@example.com	$6$04bdce9ab4268b93$W1g8tc94Gks8vF8WhoPGc/qzn9kFW6zvYQ7iLHjJPJC4M3/SNSmOL3YoheRYcPF0flnfHTuaHhAeV6GibVin70	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2025-09-11 15:19:42.793366	\N
300024	Guillon	Chloé	\N	\N	chloe.guillon@example.com	$6$ea68c8cd02f540bc$u3eE96oFdaQ3vZ4Lfetn/xw.ruGp/moX4nNDYuEp6z6QRvVq4opLtkjTan98ef56gvMHp1tBD1tcKkYEUSkYY1	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2025-09-11 15:24:53.804946	\N
300032	Roussel	Jade	\N	\N	jade.roussel@example.com	$6$0c4ce4cc042f9f28$HFeMF8X5Gy8y8xFgZhcd81ECS.UCZYXQ31KWCX7KAaS/UtadbirOmIwTlWF3zTnjxcVU4tKf5wmpJWizeBuqp0	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2025-09-11 15:53:03.072762	\N
300033	Marin	Tom	\N	\N	tom.marin@example.com	$6$0a297b6c877f95c6$j3Y7X6EFv.qdtqSXcj0JvLNjpw6I4QeDTjVlWpXDb/yLcW59lQdsMsbU/H/CWFqo92YlTJ7571QSW9eadkgqK1	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2025-09-11 15:59:40.172533	\N
300037	Fabre	Zoé	\N	\N	zoe.fabre@example.com	$6$76490028cd7630d5$2Tj/FQmEaxVHhKqFDST00THHhipytezOU/bn1rov9jFjacO2KEP.b7hfc724jtBVrWlGFjqKOXyvgHw7JBjeu0	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2025-09-12 09:10:49.974614	\N
300038	Chevalier	Raphaël	\N	\N	raphael.chevalier@example.com	$6$144b912e2bf39dc7$3EKATgkXhsZXuMKforC2mLjaPeyvVLl0/FneWSx.0bZ5f3Xuy8GXefNf084CMIxzcTCk5qGuCW1tJ7xYC2oWn1	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2025-09-12 09:10:49.989002	\N
300035	Robert	Louise	\N	\N	louise.robert@example.com	$6$7b03425e29b8ff75$/wECl1EKrqaOgcdq6aFTIkn6Yv7iynv/8cdT5P6RxooU7B5XIdHQGS1zhvyl8DbFkTKFOsVFDud8U7vcJRT1k1	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2025-09-12 09:18:21.841869	\N
300031	Laurent	Sarah	\N	\N	sarah.laurent@example.com	$6$9f170d6dbade5c2b$b5qTvYe42DQgljbnd50ksyEBH9erFm92lDb4Gq2NWEzd9xAUK7txUB13G/l4r1oIrC1kHXPlaWKPV6An7JVXb/	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2025-09-12 09:56:47.77716	\N
300029	Gauthier	Clara	\N	\N	clara.gauthier@example.com	$6$af1f2967e8b31ce3$4ZR3vcANwjdRo2OkUAcDP3FM43EGGoIoBnOr5zJ/QMylWajYr9bZHrfYPvDaQAN.eCSEI8tUY80V6kRiw19A.0	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2025-09-12 09:58:51.798174	\N
44444459	nsayi	mercia	\N	\N	nsayi@gmail.com	$6$e1c3c618e8061a55$/Wv6hAYG80g2hiW5xFIziTprTchmAK8by7g4TqiYrm8LRJhM5StAWNzdllDWx1a7W9EnKLe9v3ZaoOe5WZLCZ/	\N	\N	Masculin	Blanc, non hispanique	\N	\N	1954-04-07	\N	\N	\N	\N	\N	\N	\N	2025-09-12 10:47:59.698925	\N
44444460	bouesso	nina	\N	\N	bouesso@gmail.com	$6$319500878f793f4d$aVTjbLnfJAMV78zRiA8421vah0remeaLth1cwF5b6s5KmlTQPXwMTbA0Naw36kdxSR68LRJna26Sg21b7gicJ/	\N	\N	Masculin	Blanc, non hispanique	\N	\N	1955-06-10	\N	\N	\N	\N	\N	\N	\N	2025-09-12 10:49:26.943736	\N
44444461	makendi	moussa	\N	\N	makendi@gmail.com	$6$8f8cce00c05378b2$sz/ou2Sh/pjP/8AUFoeJePS5BM3kD.XF03zQ3F18REdh82YevObjlz8YpCCKxtcafnEzkDQ/cg/P4r0KWP9NC.	\N	\N	Masculin	Blanc, non hispanique	\N	\N	1954-01-12	\N	\N	\N	\N	\N	\N	\N	2025-09-12 11:28:27.873707	\N
44444463	ABE	FRED	\N	\N	\N	\N	\N	\N	Masculin	\N	\N	\N	1969-02-04	\N	\N	\N	\N	\N	\N	\N	2025-09-12 11:36:50.119451	\N
44444464	madzou	angela	laduchesse	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2025-09-12 11:37:05.680506	\N
44444465	mavoungou	crhistiana	\N	\N	\N	\N	\N	\N	Féminin	\N	\N	\N	2014-09-12	\N	\N	\N	\N	\N	\N	\N	2025-09-12 11:37:43.12976	\N
124	BALLOTELLI	Albert	\N	\N	\N	\N	\N	\N	Masculin	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2025-09-12 11:41:57.802112	\N
44444462	KIBOKO MBOKO	NICK	Ephraim	\N	\N	\N	\N	\N	Masculin	\N	\N	\N	1945-03-06	\N	\N	\N	\N	\N	\N	\N	2025-09-12 11:36:37.906951	\N
133	Gérer la Politique et la stratégie de l'entreprise	Gérer la Politique et la stratégie de l'entreprise	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2025-09-24 22:41:41.93859	\N
134	Gérer le Risque, la Conformité, les Correctifs et 	Gérer le Risque, la Conformité, les Correctifs et 	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2025-09-24 22:41:41.943547	\N
135	Piloter l'Amélioration Continue (Amélioration cont	Piloter l'Amélioration Continue (Amélioration cont	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2025-09-24 22:41:41.94545	\N
136	Développer et industrialiser des nouveaux process 	Développer et industrialiser des nouveaux process 	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2025-09-24 22:41:41.94976	\N
137	Etudier et développer un nouveau projet / affaire 	Etudier et développer un nouveau projet / affaire 	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2025-09-24 22:41:41.952126	\N
138	Commercialiser et réaliser le SAV (vente)	Commercialiser et réaliser le SAV (vente)	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2025-09-24 22:41:41.954067	\N
139	Réaliser les commandes client (produit A : Boitier	Réaliser les commandes client (produit A : Boitier	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2025-09-24 22:41:41.95646	\N
140	Gérer le négoce de pièce	Gérer le négoce de pièce	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2025-09-24 22:41:41.957858	\N
141	Réaliser de la production pour le compte d'une aut	Réaliser de la production pour le compte d'une aut	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2025-09-24 22:41:41.959361	\N
142	Faire produire en sous-traitance	Faire produire en sous-traitance	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2025-09-24 22:41:41.960895	\N
143	Achat & supply chain	Achat & supply chain	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2025-09-24 22:41:41.962444	\N
144	Gérer & développer les Ressources Humaines	Gérer & développer les Ressources Humaines	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2025-09-24 22:41:41.965114	\N
145	Gérer & développer le système d'information	Gérer & développer le système d'information	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2025-09-24 22:41:41.967089	\N
146	Maintenance des ressources & équipements	Maintenance des ressources & équipements	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2025-09-24 22:41:41.968915	\N
147	QHSE / RSE / Energie …	QHSE / RSE / Energie …	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2025-09-24 22:41:41.971115	\N
148	Métrologie	Métrologie	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	2025-09-24 22:41:41.972505	\N
\.


--
-- Data for Name: students_join_address; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.students_join_address (id, student_id, address_id, contact_seq, gets_mail, primary_residence, legal_residence, am_bus, pm_bus, mailing, residence, bus, bus_pickup, bus_dropoff, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: students_join_people; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.students_join_people (id, student_id, person_id, address_id, custody, emergency, student_relation, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: students_join_users; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.students_join_users (student_id, staff_id, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: templates; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.templates (modname, staff_id, template, created_at, updated_at) FROM stdin;
Students/Letters.php	0	<p></p>	2023-08-01 22:43:31.104393	\N
Grades/HonorRoll.php	0	<br /><br /><br />\n<div style="text-align: center;"><span style="font-size: xx-large;"><strong>__SCHOOL_ID__</strong><br /></span><br /><span style="font-size: xx-large;">Nous reconnaissons par la présente<br /><br /></span></div>\n<div style="text-align: center;"><span style="font-size: xx-large;"><strong>__FIRST_NAME__ __LAST_NAME__</strong><br /><br /></span></div>\n<div style="text-align: center;"><span style="font-size: xx-large;">Qui a obtenu les <br />mentions</span></div>	2023-08-01 22:43:31.104393	2023-08-01 22:43:35.376882
Grades/Transcripts.php	0	<h2 style="text-align: center;">Certificat d'Études</h2>\n<p>Le Recteur et le Secrétariat certifient:</p>\n<p>Que __FIRST_NAME__ __LAST_NAME__ identifié avec le numéro __SSECURITY__ a suivi les études dans cet établissement correspondant au niveau __GRADE_ID__ pour l'année __YEAR__ et a obtenu les notes ici mentionnées.</p>\n<p>L'Élève est promu au niveau __NEXT_GRADE_ID__.</p>\n<p>__BLOCK2__</p>\n<p>&nbsp;</p>\n<table style="border-collapse: collapse; width: 100%;" border="0" cellpadding="10"><tbody><tr>\n<td style="width: 50%; text-align: center;"><hr />\n<p>Signature</p>\n<p>&nbsp;</p><hr />\n<p>Titre</p></td>\n<td style="width: 50%; text-align: center;"><hr />\n<p>Signature</p>\n<p>&nbsp;</p><hr />\n<p>Titre</p></td></tr></tbody></table>	2023-08-01 22:43:31.104393	2023-08-01 22:43:35.376882
Custom/CreateParents.php	0	Cher __PARENT_NAME__,\n\nUn compte Parent pour l'école __SCHOOL_ID__ a été créé pour accéder aux informations de l'école et des élèves suivants :\n__ASSOCIATED_STUDENTS__\n\nVos identifiants :\nNom d'utilisateur : __USERNAME__\nMot de passe : __PASSWORD__\n\nUn lien vers le site du logiciel de gestion scolaire et les instructions pour y accéder sont disponibles sur le site de l'école.__BLOCK2__Cher __PARENT_NAME__,\n\nLes élèves suivants ont été associé à votre compte parent dans le logiciel de gestion scolaire:\n__ASSOCIATED_STUDENTS__	2023-08-01 22:43:31.104393	2023-08-01 22:43:35.376882
Custom/NotifyParents.php	0	Cher __PARENT_NAME__,\n\nUn compte Parent pour l'école __SCHOOL_ID__ a été créé pour accéder aux informations de l'école et des élèves suivants :\n__ASSOCIATED_STUDENTS__\n\nVos identifiants :\nNom d'utilisateur : __USERNAME__\nMot de passe : __PASSWORD__\n\nUn lien vers le site du logiciel de gestion scolaire et les instructions pour y accéder sont disponibles sur le site de l'école.	2023-08-01 22:43:31.104393	2023-08-01 22:43:35.376882
Custom/NotifyParents.php	1	Cher ____PARENT_NAME____,\r\n\r\nUn compte Parent pour l'école __SCHOOL_ID__ a été créé pour accéder aux informations de l'école et des élèves suivants :\r\n__ASSOCIATED_STUDENTS__\r\n\r\nVos identifiants :\r\nNom d'utilisateur : __USERNAME__\r\nMot de passe : __PASSWORD__\r\n\r\nUn lien vers le site du logiciel de gestion scolaire et les instructions pour y accéder sont disponibles sur le site de l'école.	2023-08-04 18:28:31.25587	2023-08-15 16:54:48.829988
Students/Letters.php	1	<p>Bonjour, j&#039;espère que vous allez bien. </p>	2023-09-17 12:41:45.944553	\N
Custom/CreateParents.php	55	Cher __PARENT_NAME__,\r\n\r\nUn compte Parent pour l'école __SCHOOL_ID__ a été créé pour accéder aux informations de l'école et des élèves suivants :\r\n__ASSOCIATED_STUDENTS__\r\n\r\nVos identifiants :\r\nNom d'utilisateur : __USERNAME__\r\nMot de passe : __PASSWORD__\r\n\r\nUn lien vers le site du logiciel de gestion scolaire et les instructions pour y accéder sont disponibles sur le site de l'école.__BLOCK2__Cher __PARENT_NAME__,\r\n\r\nLes élèves suivants ont été associé à votre compte parent dans le logiciel de gestion scolaire:\r\n__ASSOCIATED_STUDENTS__	2023-10-09 17:41:12.324633	\N
Custom/NotifyParents.php	54	Cher __PARENT_NAME__,\r\n\r\nUn compte Parent pour l'école __SCHOOL_ID__ a été créé pour accéder aux informations de l'école et des élèves suivants :\r\n__ASSOCIATED_STUDENTS__\r\n\r\nVos identifiants :\r\nNom d'utilisateur : __USERNAME__\r\nMot de passe : __PASSWORD__\r\n\r\nUn lien vers le site du logiciel de gestion scolaire et les instructions pour y accéder sont disponibles sur le site de l'école.	2023-10-09 18:24:28.698032	\N
Grades/HonorRoll.php	1	<p><br><br><br></p>\r\n<div style="text-align: center;"><span style="font-size: xx-large;"><strong>__SCHOOL_ID__</strong><br></span><br><span style="font-size: xx-large;">Nous reconnaissons par la présente<br><br></span></div>\r\n<div style="text-align: center;"><span style="font-size: xx-large;"><strong>__FIRST_NAME__ __LAST_NAME__</strong><br><br></span></div>\r\n<div style="text-align: center;"><span style="font-size: xx-large;">Qui a obtenu les <br>mentions</span></div>	2023-10-26 17:26:36.86444	\N
Students/Letters.php	58	<p>Bonjour <strong>__FIRST_NAME__ </strong>nous avons examen bientôt</p>	2024-08-02 16:51:46.726589	2024-08-02 18:12:14.305591
Students/Letters.php	4328	<p>Bonjour __FULL_NAME__</p>	2024-08-19 13:39:31.173969	\N
Student_ID_Card/StudentIDCard.php	0	<p style="font-size: 12px;"><strong>Nom :</strong> __LAST_NAME__</p>\r\n<p style="font-size: 12px;"><strong>Prénom :</strong> __FIRST_NAME__</p>\r\n<p style="font-size: 12px;"><strong>ID Élève :</strong> __STUDENT_ID__</p>\r\n<p style="font-size: 12px;"><strong>Né(e) le :</strong> __STUDENT_200000004__</p>\r\n<p style="font-size: 12px;"><strong>Niveau :</strong> __GRADE_ID__</p>\r\n<p style="font-size: 12px;"><strong>Année scolaire :</strong> __SCHOOL_YEAR__</p>\r\n<p style="font-size: 12px;"><strong>Sexe :</strong> __STUDENT_200000000__</p>\r\n<p style="font-size: 12px;"><strong>Adresse :</strong> __ADDRESS__</p>	2025-07-18 11:37:10.507411	2025-08-22 17:41:26.333418
\.


--
-- Data for Name: user_profiles; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.user_profiles (id, profile, title, created_at, updated_at) FROM stdin;
0	student	Student	2023-08-01 22:43:31.104393	\N
1	admin	Administrator	2023-08-01 22:43:31.104393	\N
2	teacher	Teacher	2023-08-01 22:43:31.104393	\N
3	parent	Parent	2023-08-01 22:43:31.104393	\N
16	admin	Commissaire aux Comptes	2023-10-15 20:51:00.68503	\N
9	admin	Promotrice	2023-08-13 15:27:36.062657	\N
10	admin	Promoteur	2023-08-15 13:59:34.604621	\N
13	admin	Directeur des études	2023-09-17 10:46:37.015305	\N
14	admin	Sécrétaire	2023-09-20 07:33:46.445756	\N
17	admin	Admin test 2	2024-08-07 23:46:21.2492	\N
18	admin	COMPTABLE	2025-06-05 08:20:00.938772	\N
\.


--
-- Data for Name: wx_appreciations; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.wx_appreciations (id, grade_id, appreciation, note_1, note_2) FROM stdin;
1	5	sbbss	\N	\N
2	5	cza	\N	\N
3	5	a	\N	\N
4	27	dafa	\N	\N
9	1	Très bon travail	\N	\N
10	999	TEST	\N	\N
11	999	TEST	\N	\N
39	25	mal	1	2
40	25	bien	2	3
45	25	bien	3	4
46	25	wee	4	5
54	26	bien	1	2
6	23	bien	1	2
55	26	ece	2	3
67	21	null	1	5
72	21	je t'encourage sur ce chemin, j'espère que tu vas faire encore plus !	10	15
\.


--
-- Data for Name: wx_config_publication_resultats; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.wx_config_publication_resultats (id, school_gradelevels_id, period, valeur, syear) FROM stdin;
101	47	S1	3	2025
102	47	SESSION_RATTRAPAGE_S1	\N	2025
103	47	S2	3	2025
104	47	SESSION_RATTRAPAGE_S2	\N	2025
105	47	AN	\N	2025
120	47	SESSION_RATTRAPAGE_T1	\N	2025
108	47	T3	3	2025
107	47	T2	3	2025
115	47	01	1	2025
116	47	02	\N	2025
117	47	03	\N	2025
118	47	04	\N	2025
109	47	08	1	2025
110	47	09	1	2025
111	47	10	1	2025
112	47	11	\N	2025
113	47	12	\N	2025
119	47	T1	2	2025
121	48	10	4	2025
122	48	11	4	2025
123	48	12	4	2025
124	48	T1	4	2025
\.


--
-- Data for Name: wx_course_periods_gradelevels; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.wx_course_periods_gradelevels (wx_course_periods_gradelevels_id, course_periods_id, school_gradelevels_id) FROM stdin;
24	24	47
25	25	47
\.


--
-- Data for Name: wx_course_periods_subjects; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.wx_course_periods_subjects (wx_course_periods_subjects_id, course_periods_id, course_subjects_id, coefficient, teacher_id, secondary_teacher_id, created_at, updated_at, ue_id, period_position, taux_horaires, ue_compensation) FROM stdin;
313	24	263	1	4430	\N	2025-08-13 23:30:58.513863	2025-08-13 23:30:58.513863	\N	\N	1500.00	false
314	24	264	1	4440	\N	2025-08-13 23:45:45.265647	2025-08-13 23:45:45.265647	\N	\N	1500.00	false
323	24	259	1	4431	\N	2025-09-05 14:48:53.544053	2025-09-05 14:48:53.544053	\N	\N	15000.00	false
325	24	261	1	4433	\N	2025-09-12 11:27:00.181993	2025-09-12 11:27:00.181993	\N	\N	1500.00	false
324	25	263	1	4431	\N	2025-09-05 15:16:11.531063	2025-09-05 15:16:11.531063	\N	\N	10000.00	false
\.


--
-- Data for Name: wx_course_periods_subjects_periods; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.wx_course_periods_subjects_periods (wx_course_periods_subjects_periods_id, wx_course_periods_subjects_id, day, start_time, end_time) FROM stdin;
307	313	M	12:00	14:30
308	314	M	14:30	16:30
309	313	T	12:00	14:30
311	313	F	10:00	12:45
312	324	H	08:00	09:00
313	325	M	17:30	18:30
314	323	F	16:21	17:21
\.


--
-- Data for Name: wx_course_subjects_gradelevels; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.wx_course_subjects_gradelevels (wx_course_subjects_gradelevels_id, course_subjects_id, school_gradelevels_id, coefficient, semester_type) FROM stdin;
256	256	47	1.00	\N
258	258	47	1.00	\N
260	260	47	1.00	\N
262	262	47	1.00	\N
257	257	47	1.00	\N
259	259	47	1.00	\N
261	261	47	1.00	\N
263	263	47	1.00	\N
255	255	47	1.00	\N
264	264	47	1.00	\N
266	266	48	1.00	\N
267	267	48	1.00	\N
268	268	48	1.00	\N
269	269	48	1.00	\N
270	270	48	1.00	\N
271	271	48	1.00	\N
272	272	48	1.00	\N
273	273	48	1.00	\N
274	274	48	1.00	\N
275	275	48	1.00	\N
276	276	49	1.00	\N
277	277	49	1.00	\N
278	278	49	1.00	\N
279	279	49	1.00	\N
280	280	49	1.00	\N
281	281	49	1.00	\N
282	282	49	1.00	\N
283	283	49	1.00	\N
284	284	49	1.00	\N
285	285	49	1.00	\N
286	286	50	1.00	\N
287	287	50	1.00	\N
288	288	50	1.00	\N
289	289	50	1.00	\N
290	290	50	1.00	\N
291	291	50	1.00	\N
292	292	50	1.00	\N
293	293	50	1.00	\N
\.


--
-- Data for Name: wx_custom_configuration_school; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.wx_custom_configuration_school (id_custom_configuration_school, school_id, type_school) FROM stdin;
2	21	ens_primary_secondary_general_and_technical
\.


--
-- Data for Name: wx_echelle_notation_appreciation; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.wx_echelle_notation_appreciation (id, note_debut, note_fin, echelle_notation, appreciation, year, school_id) FROM stdin;
12	10	15	20	B	2025	21
13	10	15	20	B	2025	21
\.


--
-- Data for Name: wx_families; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.wx_families (id, name, amount, school_id, syear, created_at) FROM stdin;
3	dorcas	15000.00	21	2025	2025-09-01 07:58:40.74676
10	LEPANA	28000.00	21	2025	2025-09-12 12:10:48.209857
11	FAMILLEMAVOUNGOU	60000.00	21	2025	2025-09-12 12:12:09.638837
\.


--
-- Data for Name: wx_family_members; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.wx_family_members (id, family_id, student_id, is_representative) FROM stdin;
5	3	851	t
6	3	852	f
15	10	44444455	t
16	10	44444454	f
17	11	44444462	t
18	11	44444461	f
19	11	44444465	f
\.


--
-- Data for Name: wx_gradel_period_evaluation; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.wx_gradel_period_evaluation (id_gradel_period_evaluation, school_gradelevels_id, type_period_evaluation, year, allow_debt_passage, debt_passage_percentage, eliminatory_note, debt_passage_percentage_devoir, debt_passage_percentage_session, eliminatory_mark, is_passage_with_debt, percentage_of_credit_for_passage, is_compensable) FROM stdin;
29	49	TRI	2025	f	0.00	0.00	0.00	0.00	6.00	1	80.00	0
30	50	TRI	2025	f	0.00	0.00	0.00	0.00	6.00	1	100.00	0
31	51	TRI	2025	f	0.00	0.00	0.00	0.00	6.00	1	100.00	0
32	52	TRI	2025	f	0.00	0.00	0.00	0.00	6.00	1	100.00	0
33	53	TRI	2025	f	0.00	0.00	0.00	0.00	6.00	1	100.00	0
27	47	TRI	2025	f	0.00	0.00	0.00	0.00	5.00	1	70.00	0
28	48	MENTRI	2025	f	0.00	0.00	0.00	0.00	6.00	1	80.00	0
34	56	\N	2025	f	0.00	0.00	0.00	0.00	6.00	1	100.00	0
\.


--
-- Data for Name: wx_moyennes_finales_students; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.wx_moyennes_finales_students (id, student_enrollment_id, moyenne, exam_type) FROM stdin;
\.


--
-- Data for Name: wx_moyennes_validation_gradelevel; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.wx_moyennes_validation_gradelevel (id, school_gradelevels_id, moyenne, syear) FROM stdin;
7	47	10	2025
8	48	10	2025
9	49	10	2025
10	50	10	2025
11	51	10	2025
12	52	10	2025
\.


--
-- Data for Name: wx_notes_details; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.wx_notes_details (id_notes_details, type_dev, numero_dev, course_period_id, mounth, discipline, date_dev) FROM stdin;
\.


--
-- Data for Name: wx_notes_student_details; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.wx_notes_student_details (id_notes_student_details, wx_course_periods_subjects_id, type_dev, numero_dev, student_id, course_period_id, mounth, discipline, note) FROM stdin;
5446	313	DEV	1	3	24	T1	263	12
5447	313	DEV	2	3	24	T1	263	12
6146	314	DEV	1	44444445	24	T1	264	11
5449	313	DEV_DEP	1	3	24	T1	263	11
5451	313	DEV	1	6	24	T1	263	2
5452	313	DEV	2	6	24	T1	263	9
5460	313	MOY_CLASSE	1	1	24	T1	263	14.5
5454	313	DEV_DEP	1	6	24	T1	263	11
6148	314	DEV	3	44444445	24	T1	264	13
6150	314	COMPO	1	44444445	24	T1	264	14
6153	314	DEV	1	852	24	T1	264	13
5456	313	DEV	1	1	24	T1	263	13
5457	313	DEV	2	1	24	T1	263	15
5450	313	MOY_CLASSE	1	3	24	T1	263	11.5
5459	313	DEV_DEP	1	1	24	T1	263	15
6154	314	DEV	2	852	24	T1	264	12
5461	314	DEV	1	3	24	T1	264	12
5462	314	DEV	2	3	24	T1	264	11
5464	314	DEV_DEP	1	3	24	T1	264	10
5466	314	DEV	1	6	24	T1	264	11
5467	314	DEV	2	6	24	T1	264	9
5469	314	DEV_DEP	1	6	24	T1	264	9
5471	314	DEV	1	1	24	T1	264	12
5472	314	DEV	2	1	24	T1	264	17
5474	314	DEV_DEP	1	1	24	T1	264	12
6155	314	DEV	3	852	24	T1	264	10
6147	314	DEV	2	44444445	24	T1	264	12
6149	314	DEV_DEP	1	44444445	24	T1	264	\N
6151	314	MOY_CLASSE	1	44444445	24	T1	264	12
6152	314	MOY_GLOBALE	1	44444445	24	T1	264	13
6156	314	DEV_DEP	1	852	24	T1	264	\N
5458	313	DEV	3	1	24	T1	263	\N
5463	314	DEV	3	3	24	T1	264	\N
5465	314	MOY_CLASSE	1	3	24	T1	264	10.75
5468	314	DEV	3	6	24	T1	264	\N
5470	314	MOY_CLASSE	1	6	24	T1	264	9.5
5473	314	DEV	3	1	24	T1	264	\N
5475	314	MOY_CLASSE	1	1	24	T1	264	13.25
5453	313	DEV	3	6	24	T1	263	\N
6157	314	COMPO	1	852	24	T1	264	15
6160	314	DEV	1	853	24	T1	264	11
6162	314	DEV	3	853	24	T1	264	12
6164	314	COMPO	1	853	24	T1	264	10
6158	314	MOY_CLASSE	1	852	24	T1	264	11.666666666667
6159	314	MOY_GLOBALE	1	852	24	T1	264	13.333333333333
6161	314	DEV	2	853	24	T1	264	8
6163	314	DEV_DEP	1	853	24	T1	264	\N
6165	314	MOY_CLASSE	1	853	24	T1	264	10.333333333333
6166	314	MOY_GLOBALE	1	853	24	T1	264	10.166666666667
5596	313	DEV	1	5	24	T1	263	17
5597	313	DEV	2	5	24	T1	263	18
5601	313	DEV	1	3333333	24	T1	263	12
5602	313	DEV	2	3333333	24	T1	263	12
5604	313	DEV_DEP	1	3333333	24	T1	263	12
5615	313	MOY_CLASSE	1	1111111	24	T1	263	11.75
5618	313	DEV	3	1212	24	T1	263	\N
5606	313	DEV	1	2	24	T1	263	15
5607	313	DEV	2	2	24	T1	263	15
5620	313	MOY_CLASSE	1	1212	24	T1	263	8.75
5614	313	DEV_DEP	1	1111111	24	T1	263	14
5611	313	DEV	1	1111111	24	T1	263	11
5612	313	DEV	2	1111111	24	T1	263	8
5619	313	DEV_DEP	1	1212	24	T1	263	12
5625	313	MOY_CLASSE	1	12345	24	T1	263	13.25
5628	313	DEV	3	222222	24	T1	263	\N
5616	313	DEV	1	1212	24	T1	263	6
5617	313	DEV	2	1212	24	T1	263	5
5630	313	MOY_CLASSE	1	222222	24	T1	263	13
5624	313	DEV_DEP	1	12345	24	T1	263	16
5621	313	DEV	1	12345	24	T1	263	18
5622	313	DEV	2	12345	24	T1	263	3
5629	313	DEV_DEP	1	222222	24	T1	263	18
5600	313	MOY_CLASSE	1	5	24	T1	263	18.25
5626	313	DEV	1	222222	24	T1	263	9
5627	313	DEV	2	222222	24	T1	263	7
5666	313	COMPO	1	5	24	T1	263	14
5603	313	DEV	3	3333333	24	T1	263	\N
5623	313	DEV	3	12345	24	T1	263	\N
5598	313	DEV	3	5	24	T1	263	\N
5455	313	MOY_CLASSE	1	6	24	T1	263	8.25
5669	313	MOY_GLOBALE	1	3333333	24	T1	263	14
5610	313	MOY_CLASSE	1	2	24	T1	263	14.5
5613	313	DEV	3	1111111	24	T1	263	\N
5605	313	MOY_CLASSE	1	3333333	24	T1	263	12
5668	313	COMPO	1	3333333	24	T1	263	16
5448	313	DEV	3	3	24	T1	263	\N
5609	313	DEV_DEP	1	2	24	T1	263	14
5599	313	DEV_DEP	1	5	24	T1	263	19
5667	313	MOY_GLOBALE	1	5	24	T1	263	16.125
6167	313	DEV	1	44444445	24	T1	263	12
6168	313	DEV	2	44444445	24	T1	263	16
6169	313	DEV	3	44444445	24	T1	263	15
6170	313	DEV_DEP	1	44444445	24	T1	263	\N
6171	313	COMPO	1	44444445	24	T1	263	14
6172	313	MOY_CLASSE	1	44444445	24	T1	263	14.333333333333
6173	313	MOY_GLOBALE	1	44444445	24	T1	263	14.166666666667
6174	313	DEV	1	852	24	T1	263	9
6175	313	DEV	2	852	24	T1	263	10
6176	313	DEV	3	852	24	T1	263	13
6177	313	DEV_DEP	1	852	24	T1	263	\N
6178	313	COMPO	1	852	24	T1	263	9
6179	313	MOY_CLASSE	1	852	24	T1	263	10.666666666667
6180	313	MOY_GLOBALE	1	852	24	T1	263	9.8333333333333
6181	313	DEV	1	853	24	T1	263	11
5753	314	MOY_CLASSE	1	3333333	24	T1	264	14
5754	314	MOY_GLOBALE	1	3333333	24	T1	264	11
5755	314	DEV	1	2	24	T1	264	14
5675	313	MOY_GLOBALE	1	1111111	24	T1	263	14.375
5670	313	COMPO	1	2	24	T1	263	13
5677	313	MOY_GLOBALE	1	1212	24	T1	263	9.875
5672	313	COMPO	1	3	24	T1	263	14
5679	313	MOY_GLOBALE	1	6	24	T1	263	12.125
5674	313	COMPO	1	1111111	24	T1	263	17
5681	313	MOY_GLOBALE	1	12345	24	T1	263	13.625
5676	313	COMPO	1	1212	24	T1	263	11
5683	313	MOY_GLOBALE	1	222222	24	T1	263	12
5678	313	COMPO	1	6	24	T1	263	16
5685	313	MOY_GLOBALE	1	1	24	T1	263	16.75
5680	313	COMPO	1	12345	24	T1	263	14
6182	313	DEV	2	853	24	T1	263	9
5682	313	COMPO	1	222222	24	T1	263	11
5608	313	DEV	3	2	24	T1	263	\N
5684	313	COMPO	1	1	24	T1	263	19
5673	313	MOY_GLOBALE	1	3	24	T1	263	12.75
6183	313	DEV	3	853	24	T1	263	9
6184	313	DEV_DEP	1	853	24	T1	263	\N
6185	313	COMPO	1	853	24	T1	263	14
6186	313	MOY_CLASSE	1	853	24	T1	263	9.6666666666667
6187	313	MOY_GLOBALE	1	853	24	T1	263	11.833333333333
5756	314	DEV	2	2	24	T1	264	18
5741	314	DEV	1	5	24	T1	264	12
5742	314	DEV	2	5	24	T1	264	17
5743	314	DEV	3	5	24	T1	264	\N
5744	314	DEV_DEP	1	5	24	T1	264	14
5745	314	COMPO	1	5	24	T1	264	19
5746	314	MOY_CLASSE	1	5	24	T1	264	14.25
5747	314	MOY_GLOBALE	1	5	24	T1	264	16.625
5748	314	DEV	1	3333333	24	T1	264	16
5749	314	DEV	2	3333333	24	T1	264	16
5750	314	DEV	3	3333333	24	T1	264	\N
5751	314	DEV_DEP	1	3333333	24	T1	264	12
5752	314	COMPO	1	3333333	24	T1	264	8
5757	314	DEV	3	2	24	T1	264	\N
5758	314	DEV_DEP	1	2	24	T1	264	18
5759	314	COMPO	1	2	24	T1	264	12
5760	314	MOY_CLASSE	1	2	24	T1	264	17
5761	314	MOY_GLOBALE	1	2	24	T1	264	14.5
5762	314	COMPO	1	3	24	T1	264	17
5763	314	MOY_GLOBALE	1	3	24	T1	264	13.875
5764	314	DEV	1	1111111	24	T1	264	15
5765	314	DEV	2	1111111	24	T1	264	14
5766	314	DEV	3	1111111	24	T1	264	\N
5767	314	DEV_DEP	1	1111111	24	T1	264	19
5768	314	COMPO	1	1111111	24	T1	264	9
5769	314	MOY_CLASSE	1	1111111	24	T1	264	16.75
5770	314	MOY_GLOBALE	1	1111111	24	T1	264	12.875
5771	314	DEV	1	1212	24	T1	264	16
5772	314	DEV	2	1212	24	T1	264	12
5773	314	DEV	3	1212	24	T1	264	\N
5774	314	DEV_DEP	1	1212	24	T1	264	14
5775	314	COMPO	1	1212	24	T1	264	8
5776	314	MOY_CLASSE	1	1212	24	T1	264	14
5777	314	MOY_GLOBALE	1	1212	24	T1	264	11
5778	314	COMPO	1	6	24	T1	264	16
5779	314	MOY_GLOBALE	1	6	24	T1	264	12.75
5780	314	DEV	1	12345	24	T1	264	12
5781	314	DEV	2	12345	24	T1	264	11
5782	314	DEV	3	12345	24	T1	264	\N
5783	314	DEV_DEP	1	12345	24	T1	264	9
5784	314	COMPO	1	12345	24	T1	264	15
5785	314	MOY_CLASSE	1	12345	24	T1	264	10.25
5786	314	MOY_GLOBALE	1	12345	24	T1	264	12.625
5787	314	DEV	1	222222	24	T1	264	19
5788	314	DEV	2	222222	24	T1	264	20
5789	314	DEV	3	222222	24	T1	264	\N
5790	314	DEV_DEP	1	222222	24	T1	264	16
5791	314	COMPO	1	222222	24	T1	264	15
5792	314	MOY_CLASSE	1	222222	24	T1	264	17.75
5793	314	MOY_GLOBALE	1	222222	24	T1	264	16.375
5794	314	COMPO	1	1	24	T1	264	17
5795	314	MOY_GLOBALE	1	1	24	T1	264	15.125
5671	313	MOY_GLOBALE	1	2	24	T1	263	13.75
6188	323	DEV	1	124	24	T2	259	\N
6189	323	DEV	2	124	24	T2	259	\N
6190	323	DEV	3	124	24	T2	259	\N
6191	323	DEV_DEP	1	124	24	T2	259	\N
6192	323	COMPO	1	124	24	T2	259	\N
6193	323	MOY_CLASSE	1	124	24	T2	259	\N
6194	323	MOY_GLOBALE	1	124	24	T2	259	\N
6195	323	DEV	1	44444464	24	T2	259	\N
6196	323	DEV	2	44444464	24	T2	259	\N
6197	323	DEV	3	44444464	24	T2	259	\N
6198	323	DEV_DEP	1	44444464	24	T2	259	\N
6199	323	COMPO	1	44444464	24	T2	259	\N
6200	323	MOY_CLASSE	1	44444464	24	T2	259	\N
6201	323	MOY_GLOBALE	1	44444464	24	T2	259	\N
6202	323	DEV	1	44444465	24	T2	259	\N
6203	323	DEV	2	44444465	24	T2	259	\N
6204	323	DEV	3	44444465	24	T2	259	\N
6205	323	DEV_DEP	1	44444465	24	T2	259	\N
6206	323	COMPO	1	44444465	24	T2	259	\N
6207	323	MOY_CLASSE	1	44444465	24	T2	259	\N
6208	323	MOY_GLOBALE	1	44444465	24	T2	259	\N
6209	323	DEV	1	44444463	24	T2	259	\N
6210	323	DEV	2	44444463	24	T2	259	\N
6211	323	DEV	3	44444463	24	T2	259	\N
6212	323	DEV_DEP	1	44444463	24	T2	259	\N
6213	323	COMPO	1	44444463	24	T2	259	\N
6214	323	MOY_CLASSE	1	44444463	24	T2	259	\N
6215	323	MOY_GLOBALE	1	44444463	24	T2	259	\N
6216	323	DEV	1	44444462	24	T2	259	\N
6217	323	DEV	2	44444462	24	T2	259	\N
6218	323	DEV	3	44444462	24	T2	259	\N
6219	323	DEV_DEP	1	44444462	24	T2	259	\N
6220	323	COMPO	1	44444462	24	T2	259	\N
6221	323	MOY_CLASSE	1	44444462	24	T2	259	\N
6222	323	MOY_GLOBALE	1	44444462	24	T2	259	\N
\.


--
-- Data for Name: wx_rules_school; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.wx_rules_school (id, title, config_value, year, school_id) FROM stdin;
\.


--
-- Data for Name: wx_teacher_attendance; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.wx_teacher_attendance (id, staff_id, date, start_time, end_time, created_at, done, comments, hour_type) FROM stdin;
5	4430	2025-09-12	10:00:00	12:45:00	2025-09-12 13:21:53.045857	t	\N	programmed
6	4430	2025-09-12	17:30:00	18:30:00	2025-09-12 13:22:49.645093	t	\N	non_programmed
7	4430	2025-09-12	16:21:00	17:21:00	2025-09-12 13:35:13.33354	t	\N	programmed
\.


--
-- Data for Name: wx_ues; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.wx_ues (id, title, gradelevel_id, is_required, credit, syear, school_id, course_period_id) FROM stdin;
61	Ue1	47	1	1	2025	21	23
62	Ue2	47	1	3	2025	21	23
63	Ue3	47	0	2	2025	21	23
\.


--
-- Data for Name: wx_ues_subjects; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.wx_ues_subjects (id, ue_id, subject_id) FROM stdin;
89	61	255
90	61	256
91	61	258
92	62	259
93	62	262
94	62	263
95	63	260
96	63	261
\.


--
-- Name: accounting_categories_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.accounting_categories_id_seq', 7, true);


--
-- Name: accounting_incomes_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.accounting_incomes_id_seq', 5, true);


--
-- Name: accounting_payments_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.accounting_payments_id_seq', 15, true);


--
-- Name: accounting_salaries_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.accounting_salaries_id_seq', 8, true);


--
-- Name: address_address_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.address_address_id_seq', 1, false);


--
-- Name: address_field_categories_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.address_field_categories_id_seq', 1, false);


--
-- Name: address_fields_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.address_fields_id_seq', 1, false);


--
-- Name: attendance_calendars_calendar_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.attendance_calendars_calendar_id_seq', 4, true);


--
-- Name: attendance_code_categories_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.attendance_code_categories_id_seq', 1, false);


--
-- Name: attendance_codes_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.attendance_codes_id_seq', 1, false);


--
-- Name: billing_fees_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.billing_fees_id_seq', 1331, true);


--
-- Name: billing_payments_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.billing_payments_id_seq', 590, true);


--
-- Name: calendar_events_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.calendar_events_id_seq', 8, true);


--
-- Name: course_period_school_periods_course_period_school_periods_i_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.course_period_school_periods_course_period_school_periods_i_seq', 1, false);


--
-- Name: course_periods_course_period_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.course_periods_course_period_id_seq', 25, true);


--
-- Name: course_subjects_subject_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.course_subjects_subject_id_seq', 293, true);


--
-- Name: courses_course_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.courses_course_id_seq', 1, false);


--
-- Name: custom_fields_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.custom_fields_id_seq', 200000011, true);


--
-- Name: discipline_field_usage_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.discipline_field_usage_id_seq', 1, false);


--
-- Name: discipline_fields_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.discipline_fields_id_seq', 1, false);


--
-- Name: discipline_referrals_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.discipline_referrals_id_seq', 1, false);


--
-- Name: eligibility_activities_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.eligibility_activities_id_seq', 1, false);


--
-- Name: food_service_categories_category_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.food_service_categories_category_id_seq', 1, false);


--
-- Name: food_service_items_item_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.food_service_items_item_id_seq', 1, false);


--
-- Name: food_service_menu_items_menu_item_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.food_service_menu_items_menu_item_id_seq', 1, false);


--
-- Name: food_service_menus_menu_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.food_service_menus_menu_id_seq', 1, false);


--
-- Name: food_service_staff_transactions_transaction_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.food_service_staff_transactions_transaction_id_seq', 1, false);


--
-- Name: food_service_transactions_transaction_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.food_service_transactions_transaction_id_seq', 1, false);


--
-- Name: grade_levels_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.grade_levels_id_seq', 8, true);


--
-- Name: gradebook_assignment_types_assignment_type_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.gradebook_assignment_types_assignment_type_id_seq', 1, false);


--
-- Name: gradebook_assignments_assignment_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.gradebook_assignments_assignment_id_seq', 1, false);


--
-- Name: messages_message_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.messages_message_id_seq', 1, false);


--
-- Name: people_field_categories_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.people_field_categories_id_seq', 1, false);


--
-- Name: people_fields_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.people_fields_id_seq', 1, false);


--
-- Name: people_join_contacts_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.people_join_contacts_id_seq', 1, false);


--
-- Name: people_person_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.people_person_id_seq', 1, false);


--
-- Name: portal_notes_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.portal_notes_id_seq', 6, true);


--
-- Name: portal_poll_questions_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.portal_poll_questions_id_seq', 1, false);


--
-- Name: portal_polls_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.portal_polls_id_seq', 1, false);


--
-- Name: report_card_comment_categories_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.report_card_comment_categories_id_seq', 1, false);


--
-- Name: report_card_comment_code_scales_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.report_card_comment_code_scales_id_seq', 1, false);


--
-- Name: report_card_comment_codes_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.report_card_comment_codes_id_seq', 1, false);


--
-- Name: report_card_comments_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.report_card_comments_id_seq', 27, true);


--
-- Name: report_card_grade_scales_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.report_card_grade_scales_id_seq', 23, true);


--
-- Name: report_card_grades_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.report_card_grades_id_seq', 228, true);


--
-- Name: resources_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.resources_id_seq', 1, false);


--
-- Name: rules_school_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.rules_school_id_seq', 1, false);


--
-- Name: schedule_requests_request_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.schedule_requests_request_id_seq', 1, true);


--
-- Name: school_fields_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.school_fields_id_seq', 1, false);


--
-- Name: school_gradelevels_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.school_gradelevels_id_seq', 57, true);


--
-- Name: school_marking_periods_marking_period_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.school_marking_periods_marking_period_id_seq', 185, true);


--
-- Name: school_periods_period_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.school_periods_period_id_seq', 162, true);


--
-- Name: schools_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.schools_id_seq', 21, true);


--
-- Name: staff_field_categories_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.staff_field_categories_id_seq', 5, true);


--
-- Name: staff_fields_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.staff_fields_id_seq', 200000003, true);


--
-- Name: staff_staff_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.staff_staff_id_seq', 4440, true);


--
-- Name: student_enrollment_codes_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.student_enrollment_codes_id_seq', 5, true);


--
-- Name: student_enrollment_course_periods_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.student_enrollment_course_periods_id_seq', 68, true);


--
-- Name: student_enrollment_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.student_enrollment_id_seq', 253, true);


--
-- Name: student_field_categories_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.student_field_categories_id_seq', 5, true);


--
-- Name: student_medical_alerts_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.student_medical_alerts_id_seq', 1, false);


--
-- Name: student_medical_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.student_medical_id_seq', 1, false);


--
-- Name: student_medical_visits_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.student_medical_visits_id_seq', 1, false);


--
-- Name: student_report_card_grades_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.student_report_card_grades_id_seq', 1, false);


--
-- Name: students_join_address_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.students_join_address_id_seq', 1, false);


--
-- Name: students_join_people_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.students_join_people_id_seq', 1, false);


--
-- Name: students_student_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.students_student_id_seq', 148, true);


--
-- Name: user_profiles_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.user_profiles_id_seq', 18, true);


--
-- Name: wx_appreciations_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.wx_appreciations_id_seq', 72, true);


--
-- Name: wx_config_publication_resultats_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.wx_config_publication_resultats_id_seq', 124, true);


--
-- Name: wx_course_periods_gradelevels_wx_course_periods_gradelevels_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.wx_course_periods_gradelevels_wx_course_periods_gradelevels_seq', 25, true);


--
-- Name: wx_course_periods_subjects_pe_wx_course_periods_subjects_pe_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.wx_course_periods_subjects_pe_wx_course_periods_subjects_pe_seq', 314, true);


--
-- Name: wx_course_periods_subjects_wx_course_periods_subjects_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.wx_course_periods_subjects_wx_course_periods_subjects_id_seq', 325, true);


--
-- Name: wx_course_subjects_gradelevel_wx_course_subjects_gradelevel_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.wx_course_subjects_gradelevel_wx_course_subjects_gradelevel_seq', 293, true);


--
-- Name: wx_custom_configuration_schoo_id_custom_configuration_schoo_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.wx_custom_configuration_schoo_id_custom_configuration_schoo_seq', 2, true);


--
-- Name: wx_echelle_notation_appreciation_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.wx_echelle_notation_appreciation_id_seq', 13, true);


--
-- Name: wx_families_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.wx_families_id_seq', 12, true);


--
-- Name: wx_family_members_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.wx_family_members_id_seq', 21, true);


--
-- Name: wx_gradel_period_evaluation_id_gradel_period_evaluation_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.wx_gradel_period_evaluation_id_gradel_period_evaluation_seq', 34, true);


--
-- Name: wx_moyennes_finales_students_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.wx_moyennes_finales_students_id_seq', 4, true);


--
-- Name: wx_moyennes_validation_gradelevel_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.wx_moyennes_validation_gradelevel_id_seq', 13, true);


--
-- Name: wx_notes_details_id_notes_details_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.wx_notes_details_id_notes_details_seq', 1, false);


--
-- Name: wx_notes_student_details_id_notes_student_details_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.wx_notes_student_details_id_notes_student_details_seq', 6222, true);


--
-- Name: wx_teacher_attendance_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.wx_teacher_attendance_id_seq', 7, true);


--
-- Name: wx_ues_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.wx_ues_id_seq', 63, true);


--
-- Name: wx_ues_subjects_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.wx_ues_subjects_id_seq', 96, true);


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

