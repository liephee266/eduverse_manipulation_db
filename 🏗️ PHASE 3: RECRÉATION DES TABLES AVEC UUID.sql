-- 🏗️ PHASE 3: RECRÉATION DES TABLES AVEC UUID
-- =============================================

-- Table: access_log
CREATE TABLE public.access_log (
    access_log_id uuid_type PRIMARY KEY,
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

-- Table: accounting_categories
CREATE TABLE public.accounting_categories (
    accounting_category_id uuid_type PRIMARY KEY,
    school_id uuid_type NOT NULL,
    title text NOT NULL,
    short_name character varying(10),
    type character varying(100),
    sort_order numeric,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);

-- Table: accounting_incomes
CREATE TABLE public.accounting_incomes (
    accounting_income_id uuid_type PRIMARY KEY,
    assigned_date date,
    comments text,
    title text NOT NULL,
    category_id uuid_type,
    amount numeric(14,2) NOT NULL,
    file_attached text,
    school_id uuid_type NOT NULL,
    syear numeric(4,0) NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);

-- Table: accounting_payments
CREATE TABLE public.accounting_payments (
    accounting_payment_id uuid_type PRIMARY KEY,
    syear numeric(4,0) NOT NULL,
    school_id uuid_type NOT NULL,
    staff_id uuid_type,
    title text,
    category_id uuid_type,
    amount numeric(14,2) NOT NULL,
    payment_date date,
    comments text,
    file_attached text,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);

-- Table: accounting_salaries
CREATE TABLE public.accounting_salaries (
    accounting_salary_id uuid_type PRIMARY KEY,
    staff_id uuid_type NOT NULL,
    assigned_date date,
    due_date date,
    comments text,
    title text NOT NULL,
    amount numeric(14,2) NOT NULL,
    file_attached text,
    school_id uuid_type NOT NULL,
    syear numeric(4,0) NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);

-- Table: address
CREATE TABLE public.address (
    address_id uuid_type PRIMARY KEY,
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

-- Table: address_field_categories
CREATE TABLE public.address_field_categories (
    address_field_category_id uuid_type PRIMARY KEY,
    title text NOT NULL,
    sort_order numeric,
    residence character(1),
    mailing character(1),
    bus character(1),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);

-- Table: address_fields
CREATE TABLE public.address_fields (
    address_field_id uuid_type PRIMARY KEY,
    type character varying(10) NOT NULL,
    title text NOT NULL,
    sort_order numeric,
    select_options text,
    category_id uuid_type,
    required character varying(1),
    default_selection text,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);

-- Table: attendance_calendar
CREATE TABLE public.attendance_calendar (
    attendance_calendar_id uuid_type PRIMARY KEY,
    syear numeric(4,0) NOT NULL,
    school_id uuid_type NOT NULL,
    school_date date NOT NULL,
    minutes integer,
    block character varying(10),
    calendar_id integer NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);

-- Table: attendance_calendars
CREATE TABLE public.attendance_calendars (
    calendar_id uuid_type PRIMARY KEY,
    school_id uuid_type NOT NULL,
    title character varying(100) NOT NULL,
    syear numeric(4,0) NOT NULL,
    default_calendar character varying(1),
    rollover_id uuid_type,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);

-- Table: attendance_code_categories
CREATE TABLE public.attendance_code_categories (
    attendance_code_category_id uuid_type PRIMARY KEY,
    syear numeric(4,0) NOT NULL,
    school_id uuid_type NOT NULL,
    title text NOT NULL,
    sort_order numeric,
    rollover_id uuid_type,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);

-- Table: attendance_codes
CREATE TABLE public.attendance_codes (
    attendance_code_id uuid_type PRIMARY KEY,
    syear numeric(4,0) NOT NULL,
    school_id uuid_type NOT NULL,
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

-- Table: attendance_completed
CREATE TABLE public.attendance_completed (
    attendance_completed_id uuid_type PRIMARY KEY,
    staff_id uuid_type NOT NULL,
    school_date date NOT NULL,
    period_id uuid_type NOT NULL,
    table_name integer NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);

-- Table: attendance_day
CREATE TABLE public.attendance_day (
    attendance_day_id uuid_type PRIMARY KEY,
    student_id uuid_type NOT NULL,
    school_date date NOT NULL,
    minutes_present integer,
    state_value numeric(2,1),
    syear numeric(4,0),
    marking_period_id uuid_type,
    comment text,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);

-- Table: attendance_period
CREATE TABLE public.attendance_period (
    attendance_period_id uuid_type PRIMARY KEY,
    student_id uuid_type NOT NULL,
    school_date date NOT NULL,
    period_id uuid_type,
    attendance_code integer,
    attendance_teacher_code integer,
    attendance_reason character varying(100),
    admin character varying(1),
    course_period_id uuid_type,
    marking_period_id uuid_type,
    comment character varying(100),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone,
    my_period_id integer
);

-- Table: billing_fees
CREATE TABLE public.billing_fees (
    billing_fee_id uuid_type PRIMARY KEY,
    student_id uuid_type NOT NULL,
    assigned_date date,
    due_date date,
    comments text,
    title text,
    amount numeric(14,2) NOT NULL,
    file_attached text,
    school_id uuid_type NOT NULL,
    syear numeric(4,0) NOT NULL,
    waived_fee_id uuid_type,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone,
    month character varying(5)
);

-- Table: billing_payments
CREATE TABLE public.billing_payments (
    billing_payment_id uuid_type PRIMARY KEY,
    syear numeric(4,0) NOT NULL,
    school_id uuid_type NOT NULL,
    student_id uuid_type NOT NULL,
    amount numeric(14,2) NOT NULL,
    payment_date date,
    comments text,
    refunded_payment_id uuid_type,
    lunch_payment character varying(1),
    file_attached text,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone,
    month character varying(5),
    intitule_caissier character varying(255),
    imprimer character varying(10)
);

-- Table: calendar_events
CREATE TABLE public.calendar_events (
    calendar_event_id uuid_type PRIMARY KEY,
    syear numeric(4,0) NOT NULL,
    school_id uuid_type NOT NULL,
    school_date date,
    title character varying(50) NOT NULL,
    description text,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);

-- Table: config
CREATE TABLE public.config (
    config_id uuid_type PRIMARY KEY,
    school_id integer NOT NULL,
    title character varying(100) NOT NULL,
    config_value text,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);

-- Table: course_subjects
CREATE TABLE public.course_subjects (
    subject_id uuid_type PRIMARY KEY,
    syear numeric(4,0) NOT NULL,
    school_id uuid_type NOT NULL,
    title character varying(100) NOT NULL,
    short_name character varying(25),
    sort_order numeric,
    rollover_id uuid_type,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);

-- Table: courses
CREATE TABLE public.courses (
    course_id uuid_type PRIMARY KEY,
    syear numeric(4,0) NOT NULL,
    subject_id uuid_type NOT NULL,
    school_id uuid_type NOT NULL,
    grade_level integer,
    title character varying(100) NOT NULL,
    short_name character varying(25),
    rollover_id uuid_type,
    credit_hours numeric(6,2),
    description text,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);

-- Table: course_periods
CREATE TABLE public.course_periods (
    course_period_id uuid_type PRIMARY KEY,
    syear numeric(4,0) NOT NULL,
    school_id uuid_type NOT NULL,
    course_id uuid_type,
    title text,
    short_name character varying(25) NOT NULL,
    mp character varying(3),
    marking_period_id uuid_type,
    teacher_id uuid_type,
    secondary_teacher_id uuid_type,
    room character varying(10),
    total_seats numeric,
    filled_seats numeric,
    does_attendance text,
    does_honor_roll character varying(1),
    does_class_rank character varying(1),
    gender_restriction character varying(1),
    house_restriction character varying(1),
    availability numeric,
    parent_id uuid_type,
    calendar_id integer,
    half_day character varying(1),
    does_breakoff character varying(1),
    rollover_id uuid_type,
    grade_scale_id integer,
    credits numeric(6,2),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone,
    echelle_notation integer,
    semester_type character varying(20) DEFAULT 'pair'::character varying,
    frais_classe numeric(10,2),
    total_mentant integer
);

-- Table: course_period_school_periods
CREATE TABLE public.course_period_school_periods (
    course_period_school_periods_id uuid_type PRIMARY KEY,
    course_period_id uuid_type NOT NULL,
    period_id uuid_type NOT NULL,
    days character varying(7),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);

-- Table: custom_fields
CREATE TABLE public.custom_fields (
    custom_field_id uuid_type PRIMARY KEY,
    type character varying(10) NOT NULL,
    title text NOT NULL,
    sort_order numeric,
    select_options text,
    category_id uuid_type,
    required character varying(1),
    default_selection text,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);

-- Table: discipline_field_usage
CREATE TABLE public.discipline_field_usage (
    discipline_field_usage_id uuid_type PRIMARY KEY,
    discipline_field_id uuid_type NOT NULL,
    syear numeric(4,0) NOT NULL,
    school_id uuid_type NOT NULL,
    title text NOT NULL,
    select_options text,
    sort_order numeric,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);

-- Table: discipline_fields
CREATE TABLE public.discipline_fields (
    discipline_field_id uuid_type PRIMARY KEY,
    title text NOT NULL,
    short_name character varying(20),
    data_type character varying(30) NOT NULL,
    column_name text NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);

-- Table: discipline_referrals
CREATE TABLE public.discipline_referrals (
    discipline_referral_id uuid_type PRIMARY KEY,
    syear numeric(4,0) NOT NULL,
    student_id uuid_type NOT NULL,
    school_id uuid_type NOT NULL,
    staff_id uuid_type,
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

-- Table: eligibility
CREATE TABLE public.eligibility (
    eligibility_id uuid_type PRIMARY KEY,
    student_id uuid_type NOT NULL,
    syear numeric(4,0),
    school_date date,
    period_id uuid_type,
    eligibility_code character varying(20),
    course_period_id uuid_type NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);

-- Table: eligibility_activities
CREATE TABLE public.eligibility_activities (
    eligibility_activity_id uuid_type PRIMARY KEY,
    syear numeric(4,0) NOT NULL,
    school_id uuid_type NOT NULL,
    title text NOT NULL,
    start_date date,
    end_date date,
    comment text,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);

-- Table: eligibility_completed
CREATE TABLE public.eligibility_completed (
    eligibility_completed_id uuid_type PRIMARY KEY,
    staff_id uuid_type NOT NULL,
    school_date date NOT NULL,
    period_id uuid_type NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);

-- Table: food_service_accounts
CREATE TABLE public.food_service_accounts (
    account_id uuid_type PRIMARY KEY,
    balance numeric(9,2) NOT NULL,
    transaction_id integer,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);

-- Table: food_service_categories
CREATE TABLE public.food_service_categories (
    category_id uuid_type PRIMARY KEY,
    school_id uuid_type NOT NULL,
    menu_id uuid_type NOT NULL,
    title character varying(25) NOT NULL,
    sort_order numeric,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);

-- Table: food_service_items
CREATE TABLE public.food_service_items (
    item_id uuid_type PRIMARY KEY,
    school_id uuid_type NOT NULL,
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

-- Table: food_service_menu_items
CREATE TABLE public.food_service_menu_items (
    menu_item_id uuid_type PRIMARY KEY,
    school_id uuid_type NOT NULL,
    menu_id uuid_type NOT NULL,
    item_id uuid_type NOT NULL,
    category_id uuid_type,
    sort_order numeric,
    does_count character varying(1),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);

-- Table: food_service_menus
CREATE TABLE public.food_service_menus (
    menu_id uuid_type PRIMARY KEY,
    school_id uuid_type NOT NULL,
    title character varying(25) NOT NULL,
    sort_order numeric,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);

-- Table: food_service_staff_accounts
CREATE TABLE public.food_service_staff_accounts (
    staff_account_id uuid_type PRIMARY KEY,
    staff_id uuid_type NOT NULL,
    status character varying(25),
    barcode character varying(50),
    balance numeric(9,2) NOT NULL,
    transaction_id integer,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);

-- Table: food_service_staff_transaction_items
CREATE TABLE public.food_service_staff_transaction_items (
    staff_transaction_item_id uuid_type PRIMARY KEY,
    item_id integer NOT NULL,
    transaction_id integer NOT NULL,
    amount numeric(9,2),
    short_name character varying(25),
    description character varying(50),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);

-- Table: food_service_staff_transactions
CREATE TABLE public.food_service_staff_transactions (
    transaction_id uuid_type PRIMARY KEY,
    staff_id uuid_type NOT NULL,
    school_id uuid_type NOT NULL,
    syear numeric(4,0) NOT NULL,
    balance numeric(9,2),
    "timestamp" timestamp without time zone,
    short_name character varying(25),
    description character varying(50),
    seller_id integer,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);

-- Table: food_service_student_accounts
CREATE TABLE public.food_service_student_accounts (
    student_account_id uuid_type PRIMARY KEY,
    student_id uuid_type NOT NULL,
    account_id uuid_type NOT NULL,
    discount character varying(25),
    status character varying(25),
    barcode character varying(50),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);

-- Table: food_service_transaction_items
CREATE TABLE public.food_service_transaction_items (
    transaction_item_id uuid_type PRIMARY KEY,
    item_id integer NOT NULL,
    transaction_id integer NOT NULL,
    amount numeric(9,2),
    discount character varying(25),
    short_name character varying(25),
    description character varying(50),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);

-- Table: food_service_transactions
CREATE TABLE public.food_service_transactions (
    transaction_id uuid_type PRIMARY KEY,
    account_id uuid_type NOT NULL,
    student_id uuid_type,
    school_id uuid_type NOT NULL,
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

-- Table: grade_levels
CREATE TABLE public.grade_levels (
    grade_level_id uuid_type PRIMARY KEY,
    title character varying(100) NOT NULL,
    sort_order integer DEFAULT 0
);

-- Table: gradebook_assignment_types
CREATE TABLE public.gradebook_assignment_types (
    assignment_type_id uuid_type PRIMARY KEY,
    staff_id uuid_type NOT NULL,
    course_id uuid_type NOT NULL,
    title text NOT NULL,
    final_grade_percent numeric(6,5),
    sort_order numeric,
    color character varying(30),
    created_mp integer,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);

-- Table: gradebook_assignments
CREATE TABLE public.gradebook_assignments (
    assignment_id uuid_type PRIMARY KEY,
    staff_id uuid_type NOT NULL,
    marking_period_id uuid_type NOT NULL,
    course_period_id uuid_type,
    course_id uuid_type,
    assignment_type_id uuid_type NOT NULL,
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

-- Table: gradebook_grades
CREATE TABLE public.gradebook_grades (
    gradebook_grade_id uuid_type PRIMARY KEY,
    student_id uuid_type NOT NULL,
    period_id uuid_type,
    course_period_id uuid_type NOT NULL,
    assignment_id uuid_type NOT NULL,
    points numeric(6,2),
    comment text,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);

-- Table: grades_completed
CREATE TABLE public.grades_completed (
    grades_completed_id uuid_type PRIMARY KEY,
    staff_id uuid_type NOT NULL,
    marking_period_id uuid_type NOT NULL,
    course_period_id uuid_type NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);

-- Table: school_marking_periods
CREATE TABLE public.school_marking_periods (
    marking_period_id uuid_type PRIMARY KEY,
    syear numeric(4,0) NOT NULL,
    mp character varying(3) NOT NULL,
    school_id uuid_type NOT NULL,
    parent_id uuid_type,
    title character varying(50) NOT NULL,
    short_name character varying(10),
    sort_order numeric,
    start_date date NOT NULL,
    end_date date NOT NULL,
    post_start_date date,
    post_end_date date,
    does_grades character varying(1),
    does_comments character varying(1),
    rollover_id uuid_type,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);

-- Table: history_marking_periods
CREATE TABLE public.history_marking_periods (
    history_marking_period_id uuid_type PRIMARY KEY,
    parent_id uuid_type,
    mp_type character varying(20),
    name character varying(50) NOT NULL,
    short_name character varying(10),
    post_end_date date,
    school_id uuid_type NOT NULL,
    syear numeric(4,0),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);

-- Table: lunch_period
CREATE TABLE public.lunch_period (
    lunch_period_id uuid_type PRIMARY KEY,
    student_id uuid_type NOT NULL,
    school_date date NOT NULL,
    period_id uuid_type NOT NULL,
    attendance_code integer,
    attendance_teacher_code integer,
    attendance_reason character varying(100),
    admin character varying(1),
    course_period_id uuid_type,
    marking_period_id uuid_type,
    comment character varying(100),
    table_name integer,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);

-- Table: messages
CREATE TABLE public.messages (
    message_id uuid_type PRIMARY KEY,
    syear numeric(4,0) NOT NULL,
    school_id uuid_type NOT NULL,
    "from" character varying(255),
    recipients text,
    subject character varying(100),
    data text,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);

-- Table: messagexuser
CREATE TABLE public.messagexuser (
    messagexuser_id uuid_type PRIMARY KEY,
    user_id integer NOT NULL,
    key character varying(10),
    message_id uuid_type NOT NULL,
    status character varying(10) NOT NULL
);

-- Table: moodlexrosario
CREATE TABLE public.moodlexrosario (
    moodlexrosario_id uuid_type PRIMARY KEY,
    "column" character varying(100) NOT NULL,
    rosario_id integer NOT NULL,
    moodle_id integer NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);

-- Table: people
CREATE TABLE public.people (
    person_id uuid_type PRIMARY KEY,
    last_name character varying(50) NOT NULL,
    first_name character varying(50) NOT NULL,
    middle_name character varying(50),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);

-- Table: people_field_categories
CREATE TABLE public.people_field_categories (
    people_field_category_id uuid_type PRIMARY KEY,
    title text NOT NULL,
    sort_order numeric,
    custody character(1),
    emergency character(1),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);

-- Table: people_fields
CREATE TABLE public.people_fields (
    people_field_id uuid_type PRIMARY KEY,
    type character varying(10),
    title text NOT NULL,
    sort_order numeric,
    select_options text,
    category_id uuid_type,
    required character varying(1),
    default_selection text,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);

-- Table: people_join_contacts
CREATE TABLE public.people_join_contacts (
    people_join_contact_id uuid_type PRIMARY KEY,
    person_id uuid_type,
    title character varying(100),
    value character varying(100),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);

-- Table: portal_notes
CREATE TABLE public.portal_notes (
    portal_note_id uuid_type PRIMARY KEY,
    school_id uuid_type NOT NULL,
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

-- Table: portal_poll_questions
CREATE TABLE public.portal_poll_questions (
    portal_poll_question_id uuid_type PRIMARY KEY,
    portal_poll_id uuid_type NOT NULL,
    question text NOT NULL,
    type character varying(20),
    options text,
    votes text,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);

-- Table: portal_polls
CREATE TABLE public.portal_polls (
    portal_poll_id uuid_type PRIMARY KEY,
    school_id uuid_type NOT NULL,
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

-- Table: profile_exceptions
CREATE TABLE public.profile_exceptions (
    profile_exception_id uuid_type PRIMARY KEY,
    profile_id integer NOT NULL,
    modname character varying(150) NOT NULL,
    can_use character varying(1),
    can_edit character varying(1),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);

-- Table: program_config
CREATE TABLE public.program_config (
    program_config_id uuid_type PRIMARY KEY,
    syear numeric(4,0) NOT NULL,
    school_id uuid_type NOT NULL,
    program character varying(100) NOT NULL,
    title character varying(100) NOT NULL,
    value text,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);

-- Table: program_user_config
CREATE TABLE public.program_user_config (
    program_user_config_id uuid_type PRIMARY KEY,
    user_id integer NOT NULL,
    program character varying(100) NOT NULL,
    title character varying(100) NOT NULL,
    value text,
    school_id uuid_type,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);

-- Table: report_card_comment_categories
CREATE TABLE public.report_card_comment_categories (
    report_card_comment_category_id uuid_type PRIMARY KEY,
    syear numeric(4,0) NOT NULL,
    school_id uuid_type NOT NULL,
    course_id uuid_type,
    sort_order numeric,
    title text NOT NULL,
    rollover_id uuid_type,
    color character varying(30),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);

-- Table: report_card_comment_code_scales
CREATE TABLE public.report_card_comment_code_scales (
    report_card_comment_code_scale_id uuid_type PRIMARY KEY,
    school_id uuid_type NOT NULL,
    title character varying(25) NOT NULL,
    comment character varying(100),
    sort_order numeric,
    rollover_id uuid_type,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);

-- Table: report_card_comment_codes
CREATE TABLE public.report_card_comment_codes (
    report_card_comment_code_id uuid_type PRIMARY KEY,
    school_id uuid_type NOT NULL,
    scale_id uuid_type NOT NULL,
    title character varying(5) NOT NULL,
    short_name character varying(100),
    comment character varying(100),
    sort_order numeric,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);

-- Table: report_card_comments
CREATE TABLE public.report_card_comments (
    report_card_comment_id uuid_type PRIMARY KEY,
    syear numeric(4,0) NOT NULL,
    school_id uuid_type NOT NULL,
    course_id uuid_type,
    category_id uuid_type,
    scale_id uuid_type,
    sort_order numeric,
    title text NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);

-- Table: report_card_grade_scales
CREATE TABLE public.report_card_grade_scales (
    report_card_grade_scale_id uuid_type PRIMARY KEY,
    syear numeric(4,0) NOT NULL,
    school_id uuid_type NOT NULL,
    title text NOT NULL,
    comment text,
    hhr_gpa_value numeric(7,2),
    hr_gpa_value numeric(7,2),
    sort_order numeric,
    rollover_id uuid_type,
    gp_scale numeric(7,2) NOT NULL,
    gp_passing_value numeric(7,2),
    hrs_gpa_value numeric(7,2),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);

-- Table: report_card_grades
CREATE TABLE public.report_card_grades (
    report_card_grade_id uuid_type PRIMARY KEY,
    syear numeric(4,0) NOT NULL,
    school_id uuid_type NOT NULL,
    title character varying(5) NOT NULL,
    sort_order numeric,
    gpa_value numeric(7,2),
    break_off numeric(7,2),
    comment text,
    grade_scale_id uuid_type,
    unweighted_gp numeric(7,2),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);

-- Table: resources
CREATE TABLE public.resources (
    resource_id uuid_type PRIMARY KEY,
    school_id uuid_type NOT NULL,
    title text NOT NULL,
    link text,
    published_profiles text,
    published_grade_levels text,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);

-- Table: wx_rules_school
CREATE TABLE public.wx_rules_school (
    wx_rule_school_id uuid_type PRIMARY KEY,
    title character varying(255) NOT NULL,
    config_value text,
    year numeric(4,0),
    school_id uuid_type NOT NULL
);

-- Table: schedule
CREATE TABLE public.schedule (
    schedule_id uuid_type PRIMARY KEY,
    syear numeric(4,0) NOT NULL,
    school_id uuid_type NOT NULL,
    student_id uuid_type NOT NULL,
    start_date date NOT NULL,
    end_date date,
    modified_date date,
    modified_by character varying(255),
    course_id uuid_type NOT NULL,
    course_period_id uuid_type NOT NULL,
    mp character varying(3),
    marking_period_id uuid_type,
    scheduler_lock character varying(1),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);

-- Table: schedule_requests
CREATE TABLE public.schedule_requests (
    schedule_request_id uuid_type PRIMARY KEY,
    syear numeric(4,0) NOT NULL,
    school_id uuid_type NOT NULL,
    student_id uuid_type NOT NULL,
    subject_id uuid_type,
    course_id uuid_type,
    marking_period_id uuid_type,
    priority integer,
    with_teacher_id uuid_type,
    not_teacher_id uuid_type,
    with_period_id uuid_type,
    not_period_id uuid_type,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);

-- Table: school_fields
CREATE TABLE public.school_fields (
    school_field_id uuid_type PRIMARY KEY,
    type character varying(10) NOT NULL,
    title text NOT NULL,
    sort_order numeric,
    select_options text,
    required character varying(1),
    default_selection text,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);

-- Table: school_gradelevels
CREATE TABLE public.school_gradelevels (
    gradelevel_id uuid_type PRIMARY KEY,
    school_id uuid_type NOT NULL,
    short_name character varying(3),
    title character varying(50) NOT NULL,
    next_grade_id uuid_type,
    sort_order numeric,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone,
    marking_period_type character varying(20)
);

-- Table: school_periods
CREATE TABLE public.school_periods (
    period_id uuid_type PRIMARY KEY,
    syear numeric(4,0) NOT NULL,
    school_id uuid_type NOT NULL,
    sort_order numeric,
    title character varying(100) NOT NULL,
    short_name character varying(10),
    length integer,
    start_time character varying(10),
    end_time character varying(10),
    block character varying(10),
    attendance character varying(1),
    rollover_id uuid_type,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);

-- Table: schools
CREATE TABLE public.schools (
    school_id uuid_type PRIMARY KEY,
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

-- Table: staff
CREATE TABLE public.staff (
    staff_id uuid_type PRIMARY KEY,
    syear numeric(4,0) NOT NULL,
    current_school_id uuid_type,
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
    rollover_id uuid_type,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone,
    custom_200000002 character varying(1),
    custom_200000003 text,
    custom_200000004 text,
    custom_200000005 date,
    a_salaire_fixe character(1),
    salaire_fixe numeric(12,2),
    date_debut_contrat date,
    date_fin_contrat date
);

-- Table: staff_exceptions
CREATE TABLE public.staff_exceptions (
    staff_exception_id uuid_type PRIMARY KEY,
    user_id integer NOT NULL,
    modname character varying(150) NOT NULL,
    can_use character varying(1),
    can_edit character varying(1),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);

-- Table: staff_field_categories
CREATE TABLE public.staff_field_categories (
    staff_field_category_id uuid_type PRIMARY KEY,
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

-- Table: staff_fields
CREATE TABLE public.staff_fields (
    staff_field_id uuid_type PRIMARY KEY,
    type character varying(10) NOT NULL,
    title text NOT NULL,
    sort_order numeric,
    select_options text,
    category_id uuid_type,
    required character varying(1),
    default_selection text,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);

-- Table: student_assignments
CREATE TABLE public.student_assignments (
    student_assignment_id uuid_type PRIMARY KEY,
    assignment_id integer NOT NULL,
    student_id uuid_type NOT NULL,
    data text,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);

-- Table: student_eligibility_activities
CREATE TABLE public.student_eligibility_activities (
    student_eligibility_activity_id uuid_type PRIMARY KEY,
    syear numeric(4,0),
    student_id uuid_type NOT NULL,
    activity_id uuid_type NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);

-- Table: student_enrollment_codes
CREATE TABLE public.student_enrollment_codes (
    student_enrollment_code_id uuid_type PRIMARY KEY,
    syear numeric(4,0) NOT NULL,
    title character varying(100) NOT NULL,
    short_name character varying(10),
    type character varying(4),
    default_code character varying(1),
    sort_order numeric,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);

-- Table: student_enrollment
CREATE TABLE public.student_enrollment (
    enrollment_id uuid_type PRIMARY KEY,
    syear numeric(4,0) NOT NULL,
    school_id uuid_type NOT NULL,
    student_id uuid_type NOT NULL,
    grade_id uuid_type,
    start_date date,
    end_date date,
    enrollment_code integer,
    drop_code integer,
    next_school integer,
    calendar_id integer,
    last_school integer,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone,
    second_course_period_id uuid_type,
    semester character varying(10),
    second_semester character varying(10),
    course_period_id uuid_type,
    second_grade_id uuid_type
);

-- Table: student_enrollment_course_periods
CREATE TABLE public.student_enrollment_course_periods (
    student_enrollment_course_period_id uuid_type PRIMARY KEY,
    student_enrollment_id uuid_type NOT NULL,
    course_period_id uuid_type NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);

-- Table: student_field_categories
CREATE TABLE public.student_field_categories (
    student_field_category_id uuid_type PRIMARY KEY,
    title text NOT NULL,
    sort_order numeric,
    columns numeric(4,0),
    include character varying(100),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);

-- Table: student_medical
CREATE TABLE public.student_medical (
    student_medical_id uuid_type PRIMARY KEY,
    student_id uuid_type NOT NULL,
    type character varying(25),
    medical_date date,
    comments character varying(100),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);

-- Table: student_medical_alerts
CREATE TABLE public.student_medical_alerts (
    student_medical_alert_id uuid_type PRIMARY KEY,
    student_id uuid_type NOT NULL,
    title character varying(100),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);

-- Table: student_medical_visits
CREATE TABLE public.student_medical_visits (
    student_medical_visit_id uuid_type PRIMARY KEY,
    student_id uuid_type NOT NULL,
    school_date date,
    time_in character varying(20),
    time_out character varying(20),
    reason character varying(100),
    result character varying(100),
    comments text,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);

-- Table: student_mp_comments
CREATE TABLE public.student_mp_comments (
    student_mp_comment_id uuid_type PRIMARY KEY,
    student_id uuid_type NOT NULL,
    syear numeric(4,0) NOT NULL,
    marking_period_id uuid_type NOT NULL,
    comment text,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);

-- Table: student_mp_stats
CREATE TABLE public.student_mp_stats (
    student_mp_stat_id uuid_type PRIMARY KEY,
    student_id uuid_type NOT NULL,
    marking_period_id uuid_type NOT NULL,
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

-- Table: student_report_card_comments
CREATE TABLE public.student_report_card_comments (
    student_report_card_comment_id uuid_type PRIMARY KEY,
    syear numeric(4,0) NOT NULL,
    school_id uuid_type NOT NULL,
    student_id uuid_type NOT NULL,
    course_period_id uuid_type NOT NULL,
    report_card_comment_id integer NOT NULL,
    comment character varying(5),
    marking_period_id uuid_type NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);

-- Table: student_report_card_grades
CREATE TABLE public.student_report_card_grades (
    student_report_card_grade_id uuid_type PRIMARY KEY,
    syear numeric(4,0) NOT NULL,
    school_id uuid_type NOT NULL,
    student_id uuid_type NOT NULL,
    course_period_id uuid_type,
    report_card_grade_id integer,
    report_card_comment_id integer,
    comment text,
    grade_percent numeric(4,1),
    marking_period_id uuid_type NOT NULL,
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

-- Table: students
CREATE TABLE public.students (
    student_id uuid_type PRIMARY KEY,
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
    frais_inscriptions numeric(10,2)
);

-- Table: students_join_address
CREATE TABLE public.students_join_address (
    student_join_address_id uuid_type PRIMARY KEY,
    student_id uuid_type NOT NULL,
    address_id uuid_type NOT NULL,
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

-- Table: students_join_people
CREATE TABLE public.students_join_people (
    student_join_people_id uuid_type PRIMARY KEY,
    student_id uuid_type NOT NULL,
    person_id uuid_type NOT NULL,
    address_id uuid_type,
    custody character varying(1),
    emergency character varying(1),
    student_relation character varying(100),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);

-- Table: students_join_users
CREATE TABLE public.students_join_users (
    student_join_user_id uuid_type PRIMARY KEY,
    student_id uuid_type NOT NULL,
    staff_id uuid_type NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);

-- Table: templates
CREATE TABLE public.templates (
    template_id uuid_type PRIMARY KEY,
    modname character varying(150) NOT NULL,
    staff_id uuid_type NOT NULL,
    template text,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);

-- Table: user_profiles
CREATE TABLE public.user_profiles (
    user_profile_id uuid_type PRIMARY KEY,
    profile character varying(30),
    title text NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone
);

-- =============================================
-- TABLES CUSTOMISÉES (wx_*) AVEC UUID
-- =============================================

-- Table: wx_appreciations
CREATE TABLE public.wx_appreciations (
    wx_appreciation_id uuid_type PRIMARY KEY,
    grade_id integer NOT NULL,
    appreciation character varying(255) NOT NULL,
    note_1 character varying(255),
    note_2 character varying(255)
);

-- Table: wx_config_publication_resultats
CREATE TABLE public.wx_config_publication_resultats (
    wx_config_publication_resultat_id uuid_type PRIMARY KEY,
    school_gradelevels_id uuid_type NOT NULL,
    period character varying(50),
    valeur integer,
    syear numeric(4,0)
);

-- Table: wx_course_periods_gradelevels
CREATE TABLE public.wx_course_periods_gradelevels (
    wx_course_periods_gradelevels_id uuid_type PRIMARY KEY,
    course_periods_id uuid_type NOT NULL,
    school_gradelevels_id uuid_type NOT NULL
);

-- Table: wx_course_periods_subjects
CREATE TABLE public.wx_course_periods_subjects (
    wx_course_periods_subjects_id uuid_type PRIMARY KEY,
    course_periods_id uuid_type NOT NULL,
    course_subjects_id uuid_type NOT NULL,
    coefficient character varying(10) DEFAULT '1' NOT NULL,
    teacher_id uuid_type NOT NULL,
    secondary_teacher_id uuid_type,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    ue_id uuid_type,
    period_position character varying(255),
    taux_horaires numeric(10,2),
    ue_compensation character varying(10) DEFAULT 'false',
    CONSTRAINT chk_taux_horaires_positive CHECK ((taux_horaires >= (0)::numeric))
);

-- Table: wx_course_periods_subjects_periods
CREATE TABLE public.wx_course_periods_subjects_periods (
    wx_course_periods_subjects_periods_id uuid_type PRIMARY KEY,
    wx_course_periods_subjects_id uuid_type NOT NULL,
    day character(1) NOT NULL,
    start_time character varying(10) NOT NULL,
    end_time character varying(10) NOT NULL
);

-- Table: wx_course_subjects_gradelevels
CREATE TABLE public.wx_course_subjects_gradelevels (
    wx_course_subjects_gradelevels_id uuid_type PRIMARY KEY,
    course_subjects_id uuid_type NOT NULL,
    school_gradelevels_id uuid_type NOT NULL,
    coefficient numeric(5,2) DEFAULT 1.00,
    semester_type character varying(10)
);

-- Table: wx_custom_configuration_school
CREATE TABLE public.wx_custom_configuration_school (
    id_custom_configuration_school uuid_type PRIMARY KEY,
    school_id uuid_type NOT NULL,
    type_school character varying(255)
);

-- Table: wx_echelle_notation_appreciation
CREATE TABLE public.wx_echelle_notation_appreciation (
    wx_echelle_notation_appreciation_id uuid_type PRIMARY KEY,
    note_debut double precision NOT NULL,
    note_fin double precision NOT NULL,
    echelle_notation integer NOT NULL,
    appreciation character varying(5),
    year numeric(4,0),
    school_id uuid_type NOT NULL
);

-- Table: wx_families
CREATE TABLE public.wx_families (
    wx_family_id uuid_type PRIMARY KEY,
    name character varying(100) NOT NULL,
    amount numeric(10,2) DEFAULT 0.00 NOT NULL,
    school_id uuid_type NOT NULL,
    syear integer NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);

-- Table: wx_family_members
CREATE TABLE public.wx_family_members (
    wx_family_member_id uuid_type PRIMARY KEY,
    family_id uuid_type NOT NULL,
    student_id uuid_type NOT NULL,
    is_representative boolean DEFAULT false NOT NULL
);

-- Table: wx_gradel_period_evaluation
CREATE TABLE public.wx_gradel_period_evaluation (
    id_gradel_period_evaluation uuid_type PRIMARY KEY,
    school_gradelevels_id uuid_type NOT NULL,
    type_period_evaluation character varying(20),
    year numeric(4,0) NOT NULL,
    allow_debt_passage boolean DEFAULT false,
    debt_passage_percentage numeric(5,2) DEFAULT 0.00,
    eliminatory_note numeric(5,2) DEFAULT 0.00,
    debt_passage_percentage_devoir numeric(5,2) DEFAULT 0,
    debt_passage_percentage_session numeric(5,2) DEFAULT 0,
    eliminatory_mark numeric(5,2) DEFAULT 0,
    is_passage_with_debt character varying(1) DEFAULT '0',
    percentage_of_credit_for_passage numeric(5,2) DEFAULT 0,
    is_compensable character varying(1) DEFAULT '0'
);

-- Table: wx_moyennes_finales_students
CREATE TABLE public.wx_moyennes_finales_students (
    wx_moyenne_finale_student_id uuid_type PRIMARY KEY,
    student_enrollment_id uuid_type NOT NULL,
    moyenne double precision NOT NULL,
    exam_type character varying(10)
);

-- Table: wx_moyennes_validation_gradelevel
CREATE TABLE public.wx_moyennes_validation_gradelevel (
    wx_moyenne_validation_gradelevel_id uuid_type PRIMARY KEY,
    school_gradelevels_id uuid_type NOT NULL,
    moyenne double precision NOT NULL,
    syear numeric(4,0)
);

-- Table: wx_notes_details
CREATE TABLE public.wx_notes_details (
    id_notes_details uuid_type PRIMARY KEY,
    type_dev character varying(255) NOT NULL,
    numero_dev integer NOT NULL,
    course_period_id uuid_type NOT NULL,
    mounth character varying(3) NOT NULL,
    discipline integer NOT NULL,
    date_dev timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);

-- Table: wx_notes_student_details
CREATE TABLE public.wx_notes_student_details (
    id_notes_student_details uuid_type PRIMARY KEY,
    wx_course_periods_subjects_id uuid_type NOT NULL,
    type_dev character varying(255) NOT NULL,
    numero_dev integer NOT NULL,
    student_id uuid_type NOT NULL,
    course_period_id uuid_type NOT NULL,
    mounth character varying(3) NOT NULL,
    discipline integer NOT NULL,
    note double precision
);

-- Table: wx_teacher_attendance
CREATE TABLE public.wx_teacher_attendance (
    wx_teacher_attendance_id uuid_type PRIMARY KEY,
    staff_id uuid_type NOT NULL,
    date date NOT NULL,
    start_time time without time zone NOT NULL,
    end_time time without time zone NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    done boolean DEFAULT true NOT NULL,
    comments text,
    hour_type character varying DEFAULT 'non_programmed'::character varying NOT NULL
);

-- Table: wx_ues
CREATE TABLE public.wx_ues (
    ue_id uuid_type PRIMARY KEY,
    title character varying(100),
    gradelevel_id uuid_type,
    is_required character(1) DEFAULT 'N'::bpchar,
    credit double precision,
    syear integer,
    school_id uuid_type,
    course_period_id uuid_type
);

-- Table: wx_ues_subjects
CREATE TABLE public.wx_ues_subjects (
    wx_ues_subject_id uuid_type PRIMARY KEY,
    ue_id uuid_type,
    subject_id uuid_type
);

-- Table: wx_rules_school (redondant mais assure la création finale)
CREATE TABLE public.wx_rules_school (
    wx_rule_school_id uuid_type PRIMARY KEY,
    title character varying(255) NOT NULL,
    config_value text,
    year numeric(4,0),
    school_id uuid_type NOT NULL
);

-- Table: public.wx_ues_subjects

-- DROP TABLE IF EXISTS public.wx_ues_subjects;

CREATE TABLE IF NOT EXISTS public.wx_ues_subjects
(
    id uuid NOT NULL,
    wx_ues_subjects_subject_id_fkey_uuid uuid,
    wx_ues_subjects_ue_id_fkey_uuid uuid,
    subject_id uuid,
    ue_id uuid,
    CONSTRAINT wx_ues_subjects_pkey PRIMARY KEY (id)
)

TABLESPACE pg_default;

ALTER TABLE IF EXISTS public.wx_ues_subjects
    OWNER to wxu_school;
-- Index: idx_wx_ues_subjects_id

-- DROP INDEX IF EXISTS public.idx_wx_ues_subjects_id;

CREATE UNIQUE INDEX IF NOT EXISTS idx_wx_ues_subjects_id
    ON public.wx_ues_subjects USING btree
    (id ASC NULLS LAST)
    TABLESPACE pg_default;

-- Trigger: trigger_wx_ues_subjects_id

-- DROP TRIGGER IF EXISTS trigger_wx_ues_subjects_id ON public.wx_ues_subjects;

CREATE OR REPLACE TRIGGER trigger_wx_ues_subjects_id
    BEFORE INSERT
    ON public.wx_ues_subjects
    FOR EACH ROW
    EXECUTE FUNCTION public.generate_uuid_trigger();

-- Message de confirmation pour cette étape
DO $$
BEGIN
    RAISE NOTICE '✅ Étape 3 (Recréation des Tables) terminée avec succès.';
END $$;
