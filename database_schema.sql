--
-- PostgreSQL database dump
--

\restrict WdYQWVlQQgdxVzfoTaj60VTEGTbceaNLjUXyxaCeg5HePktnrwKz3Y69LMslZNT

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
-- Name: EXTENSION pg_trgm; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION pg_trgm IS 'text similarity measurement and index searching based on trigrams';


--
-- Name: oban_job_state; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.oban_job_state AS ENUM (
    'available',
    'suspended',
    'scheduled',
    'executing',
    'retryable',
    'completed',
    'discarded',
    'cancelled'
);


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: alerts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.alerts (
    id uuid NOT NULL,
    severity character varying(255) DEFAULT 'medium'::character varying NOT NULL,
    status character varying(255) DEFAULT 'pending'::character varying NOT NULL,
    validation_details text,
    alpr_event_id uuid NOT NULL,
    watchlist_id uuid NOT NULL,
    operator_id uuid,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: alpr_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.alpr_events (
    id uuid NOT NULL,
    normalized_plate character varying(255) NOT NULL,
    original_plate character varying(255) NOT NULL,
    confidence double precision NOT NULL,
    plate_image_url character varying(255),
    context_image_url character varying(255),
    status character varying(255) DEFAULT 'new'::character varying NOT NULL,
    location_name character varying(255),
    camera_id uuid,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: audit_logs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.audit_logs (
    id uuid NOT NULL,
    action character varying(255) NOT NULL,
    plate_queried character varying(255),
    filters_applied jsonb DEFAULT '{}'::jsonb,
    justification text,
    result_count integer,
    ip_address character varying(255),
    user_id uuid,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: cameras; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.cameras (
    id uuid NOT NULL,
    code character varying(255) NOT NULL,
    type character varying(255) NOT NULL,
    location_name character varying(255) NOT NULL,
    latitude double precision,
    longitude double precision,
    orientation character varying(255),
    status character varying(255) DEFAULT 'active'::character varying NOT NULL,
    stream_url character varying(255),
    zone character varying(255),
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    source_type character varying(255) DEFAULT 'video'::character varying NOT NULL
);


--
-- Name: configurations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.configurations (
    parameter_key character varying(255) NOT NULL,
    value text NOT NULL,
    module character varying(255) NOT NULL,
    updated_by_id uuid,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: geofences; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.geofences (
    id uuid NOT NULL,
    name character varying(255) NOT NULL,
    type character varying(255) DEFAULT 'polygon'::character varying NOT NULL,
    coordinates jsonb NOT NULL,
    zone character varying(255),
    status character varying(255) DEFAULT 'active'::character varying NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: oban_jobs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.oban_jobs (
    id bigint NOT NULL,
    state public.oban_job_state DEFAULT 'available'::public.oban_job_state NOT NULL,
    queue text DEFAULT 'default'::text NOT NULL,
    worker text NOT NULL,
    args jsonb DEFAULT '{}'::jsonb NOT NULL,
    errors jsonb[] DEFAULT ARRAY[]::jsonb[] NOT NULL,
    attempt integer DEFAULT 0 NOT NULL,
    max_attempts integer DEFAULT 20 NOT NULL,
    inserted_at timestamp without time zone DEFAULT timezone('UTC'::text, now()) NOT NULL,
    scheduled_at timestamp without time zone DEFAULT timezone('UTC'::text, now()) NOT NULL,
    attempted_at timestamp without time zone,
    completed_at timestamp without time zone,
    attempted_by text[],
    discarded_at timestamp without time zone,
    priority integer DEFAULT 0 NOT NULL,
    tags text[] DEFAULT ARRAY[]::text[],
    meta jsonb DEFAULT '{}'::jsonb,
    cancelled_at timestamp without time zone,
    CONSTRAINT attempt_range CHECK (((attempt >= 0) AND (attempt <= max_attempts))),
    CONSTRAINT positive_max_attempts CHECK ((max_attempts > 0)),
    CONSTRAINT queue_length CHECK (((char_length(queue) > 0) AND (char_length(queue) < 128))),
    CONSTRAINT worker_length CHECK (((char_length(worker) > 0) AND (char_length(worker) < 128)))
);


--
-- Name: TABLE oban_jobs; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.oban_jobs IS '14';


--
-- Name: oban_jobs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.oban_jobs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: oban_jobs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.oban_jobs_id_seq OWNED BY public.oban_jobs.id;


--
-- Name: oban_peers; Type: TABLE; Schema: public; Owner: -
--

CREATE UNLOGGED TABLE public.oban_peers (
    name text NOT NULL,
    node text NOT NULL,
    started_at timestamp without time zone NOT NULL,
    expires_at timestamp without time zone NOT NULL
);


--
-- Name: observed_vehicles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.observed_vehicles (
    plate character varying(255) NOT NULL,
    detected_attributes jsonb DEFAULT '{}'::jsonb,
    frequency integer DEFAULT 0 NOT NULL,
    last_seen_at timestamp without time zone,
    interest_status boolean DEFAULT false NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: official_integrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.official_integrations (
    id uuid NOT NULL,
    entity_name character varying(255) NOT NULL,
    type character varying(255) NOT NULL,
    credentials jsonb DEFAULT '{}'::jsonb,
    agreement_details text,
    status character varying(255) DEFAULT 'active'::character varying NOT NULL,
    last_sync_at timestamp without time zone,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: reports; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.reports (
    id uuid NOT NULL,
    type character varying(255) NOT NULL,
    filters_used jsonb DEFAULT '{}'::jsonb,
    file_url character varying(255),
    file_hash character varying(255),
    status character varying(255) DEFAULT 'pending'::character varying NOT NULL,
    user_id uuid,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: roles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.roles (
    id uuid NOT NULL,
    name character varying(255) NOT NULL,
    description text,
    permissions character varying(255)[] DEFAULT ARRAY[]::character varying[],
    access_level integer DEFAULT 0 NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schema_migrations (
    version bigint NOT NULL,
    inserted_at timestamp(0) without time zone
);


--
-- Name: users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.users (
    id uuid NOT NULL,
    name character varying(255) NOT NULL,
    email character varying(255) NOT NULL,
    password_hash character varying(255) NOT NULL,
    status character varying(255) DEFAULT 'active'::character varying NOT NULL,
    last_login_at timestamp without time zone,
    permissions character varying(255)[] DEFAULT ARRAY[]::character varying[],
    role_id uuid NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: watchlists; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.watchlists (
    id uuid NOT NULL,
    plate character varying(255) NOT NULL,
    source character varying(255) NOT NULL,
    reason text NOT NULL,
    severity character varying(255) DEFAULT 'medium'::character varying NOT NULL,
    start_date date,
    end_date date,
    status character varying(255) DEFAULT 'active'::character varying NOT NULL,
    assigned_by_id uuid,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: oban_jobs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oban_jobs ALTER COLUMN id SET DEFAULT nextval('public.oban_jobs_id_seq'::regclass);


--
-- Name: alerts alerts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.alerts
    ADD CONSTRAINT alerts_pkey PRIMARY KEY (id);


--
-- Name: alpr_events alpr_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.alpr_events
    ADD CONSTRAINT alpr_events_pkey PRIMARY KEY (id);


--
-- Name: audit_logs audit_logs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_logs
    ADD CONSTRAINT audit_logs_pkey PRIMARY KEY (id);


--
-- Name: cameras cameras_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cameras
    ADD CONSTRAINT cameras_pkey PRIMARY KEY (id);


--
-- Name: configurations configurations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.configurations
    ADD CONSTRAINT configurations_pkey PRIMARY KEY (parameter_key);


--
-- Name: geofences geofences_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.geofences
    ADD CONSTRAINT geofences_pkey PRIMARY KEY (id);


--
-- Name: oban_jobs non_negative_priority; Type: CHECK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE public.oban_jobs
    ADD CONSTRAINT non_negative_priority CHECK ((priority >= 0)) NOT VALID;


--
-- Name: oban_jobs oban_jobs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oban_jobs
    ADD CONSTRAINT oban_jobs_pkey PRIMARY KEY (id);


--
-- Name: oban_peers oban_peers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oban_peers
    ADD CONSTRAINT oban_peers_pkey PRIMARY KEY (name);


--
-- Name: observed_vehicles observed_vehicles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.observed_vehicles
    ADD CONSTRAINT observed_vehicles_pkey PRIMARY KEY (plate);


--
-- Name: official_integrations official_integrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.official_integrations
    ADD CONSTRAINT official_integrations_pkey PRIMARY KEY (id);


--
-- Name: reports reports_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reports
    ADD CONSTRAINT reports_pkey PRIMARY KEY (id);


--
-- Name: roles roles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.roles
    ADD CONSTRAINT roles_pkey PRIMARY KEY (id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: watchlists watchlists_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.watchlists
    ADD CONSTRAINT watchlists_pkey PRIMARY KEY (id);


--
-- Name: alerts_alpr_event_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX alerts_alpr_event_id_index ON public.alerts USING btree (alpr_event_id);


--
-- Name: alerts_inserted_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX alerts_inserted_at_index ON public.alerts USING btree (inserted_at);


--
-- Name: alerts_operator_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX alerts_operator_id_index ON public.alerts USING btree (operator_id);


--
-- Name: alerts_severity_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX alerts_severity_index ON public.alerts USING btree (severity);


--
-- Name: alerts_status_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX alerts_status_index ON public.alerts USING btree (status);


--
-- Name: alerts_watchlist_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX alerts_watchlist_id_index ON public.alerts USING btree (watchlist_id);


--
-- Name: alpr_events_camera_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX alpr_events_camera_id_index ON public.alpr_events USING btree (camera_id);


--
-- Name: alpr_events_inserted_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX alpr_events_inserted_at_index ON public.alpr_events USING btree (inserted_at);


--
-- Name: alpr_events_normalized_plate_gin_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX alpr_events_normalized_plate_gin_idx ON public.alpr_events USING gin (normalized_plate public.gin_trgm_ops);


--
-- Name: alpr_events_normalized_plate_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX alpr_events_normalized_plate_index ON public.alpr_events USING btree (normalized_plate);


--
-- Name: alpr_events_status_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX alpr_events_status_index ON public.alpr_events USING btree (status);


--
-- Name: audit_logs_action_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX audit_logs_action_index ON public.audit_logs USING btree (action);


--
-- Name: audit_logs_inserted_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX audit_logs_inserted_at_index ON public.audit_logs USING btree (inserted_at);


--
-- Name: audit_logs_plate_queried_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX audit_logs_plate_queried_index ON public.audit_logs USING btree (plate_queried);


--
-- Name: audit_logs_user_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX audit_logs_user_id_index ON public.audit_logs USING btree (user_id);


--
-- Name: cameras_code_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX cameras_code_index ON public.cameras USING btree (code);


--
-- Name: cameras_status_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX cameras_status_index ON public.cameras USING btree (status);


--
-- Name: cameras_zone_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX cameras_zone_index ON public.cameras USING btree (zone);


--
-- Name: configurations_module_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX configurations_module_index ON public.configurations USING btree (module);


--
-- Name: configurations_updated_by_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX configurations_updated_by_id_index ON public.configurations USING btree (updated_by_id);


--
-- Name: geofences_name_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX geofences_name_index ON public.geofences USING btree (name);


--
-- Name: geofences_status_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX geofences_status_index ON public.geofences USING btree (status);


--
-- Name: geofences_zone_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX geofences_zone_index ON public.geofences USING btree (zone);


--
-- Name: oban_jobs_args_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX oban_jobs_args_index ON public.oban_jobs USING gin (args);


--
-- Name: oban_jobs_meta_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX oban_jobs_meta_index ON public.oban_jobs USING gin (meta);


--
-- Name: oban_jobs_state_cancelled_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX oban_jobs_state_cancelled_at_index ON public.oban_jobs USING btree (state, cancelled_at);


--
-- Name: oban_jobs_state_discarded_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX oban_jobs_state_discarded_at_index ON public.oban_jobs USING btree (state, discarded_at);


--
-- Name: oban_jobs_state_queue_priority_scheduled_at_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX oban_jobs_state_queue_priority_scheduled_at_id_index ON public.oban_jobs USING btree (state, queue, priority, scheduled_at, id);


--
-- Name: observed_vehicles_frequency_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX observed_vehicles_frequency_index ON public.observed_vehicles USING btree (frequency);


--
-- Name: observed_vehicles_interest_status_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX observed_vehicles_interest_status_index ON public.observed_vehicles USING btree (interest_status);


--
-- Name: observed_vehicles_last_seen_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX observed_vehicles_last_seen_at_index ON public.observed_vehicles USING btree (last_seen_at);


--
-- Name: official_integrations_entity_name_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX official_integrations_entity_name_index ON public.official_integrations USING btree (entity_name);


--
-- Name: official_integrations_status_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX official_integrations_status_index ON public.official_integrations USING btree (status);


--
-- Name: official_integrations_type_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX official_integrations_type_index ON public.official_integrations USING btree (type);


--
-- Name: reports_inserted_at_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX reports_inserted_at_index ON public.reports USING btree (inserted_at);


--
-- Name: reports_status_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX reports_status_index ON public.reports USING btree (status);


--
-- Name: reports_type_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX reports_type_index ON public.reports USING btree (type);


--
-- Name: reports_user_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX reports_user_id_index ON public.reports USING btree (user_id);


--
-- Name: roles_name_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX roles_name_index ON public.roles USING btree (name);


--
-- Name: users_email_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX users_email_index ON public.users USING btree (email);


--
-- Name: users_role_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX users_role_id_index ON public.users USING btree (role_id);


--
-- Name: users_status_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX users_status_index ON public.users USING btree (status);


--
-- Name: watchlists_assigned_by_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX watchlists_assigned_by_id_index ON public.watchlists USING btree (assigned_by_id);


--
-- Name: watchlists_plate_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX watchlists_plate_index ON public.watchlists USING btree (plate);


--
-- Name: watchlists_severity_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX watchlists_severity_index ON public.watchlists USING btree (severity);


--
-- Name: watchlists_status_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX watchlists_status_index ON public.watchlists USING btree (status);


--
-- Name: alerts alerts_alpr_event_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.alerts
    ADD CONSTRAINT alerts_alpr_event_id_fkey FOREIGN KEY (alpr_event_id) REFERENCES public.alpr_events(id) ON DELETE RESTRICT;


--
-- Name: alerts alerts_operator_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.alerts
    ADD CONSTRAINT alerts_operator_id_fkey FOREIGN KEY (operator_id) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: alerts alerts_watchlist_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.alerts
    ADD CONSTRAINT alerts_watchlist_id_fkey FOREIGN KEY (watchlist_id) REFERENCES public.watchlists(id) ON DELETE RESTRICT;


--
-- Name: alpr_events alpr_events_camera_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.alpr_events
    ADD CONSTRAINT alpr_events_camera_id_fkey FOREIGN KEY (camera_id) REFERENCES public.cameras(id) ON DELETE SET NULL;


--
-- Name: audit_logs audit_logs_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_logs
    ADD CONSTRAINT audit_logs_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: configurations configurations_updated_by_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.configurations
    ADD CONSTRAINT configurations_updated_by_id_fkey FOREIGN KEY (updated_by_id) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: reports reports_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reports
    ADD CONSTRAINT reports_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: users users_role_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_role_id_fkey FOREIGN KEY (role_id) REFERENCES public.roles(id) ON DELETE RESTRICT;


--
-- Name: watchlists watchlists_assigned_by_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.watchlists
    ADD CONSTRAINT watchlists_assigned_by_id_fkey FOREIGN KEY (assigned_by_id) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- PostgreSQL database dump complete
--

\unrestrict WdYQWVlQQgdxVzfoTaj60VTEGTbceaNLjUXyxaCeg5HePktnrwKz3Y69LMslZNT

