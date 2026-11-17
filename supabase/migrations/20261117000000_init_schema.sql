-- =============================================================================
-- CRM Inmobiliario RK Santos · Solfico
-- Migración inicial (Database-First) · Supabase / PostgreSQL 15+
-- Versión 1.1 (final) · 17/11/2026
-- Aplicar como migración de Supabase (supabase migration new init_crm) y, a
-- continuación, seed.sql. No contiene datos de prueba.
-- -----------------------------------------------------------------------------
-- Diseño completo del CRM. Cada tabla lleva en su COMMENT la fase en la que
-- se opera:  [F1] = MVP (Core + Valorador IA) · [F2] = Fase 2 · [F3] = Fase 3
--
-- Principios:
--   * RLS activado en TODAS las tablas del esquema public.
--   * Funciones SECURITY DEFINER sólo en el esquema `private` (no expuesto por
--     la Data API), con search_path = '' y nombres totalmente cualificados.
--   * Patrón (select ...) en las políticas para que Postgres cachee el valor
--     (initPlan) en lugar de evaluarlo por fila.
--   * Datos sensibles / internos separados físicamente de los publicables.
--   * Inmovilla es la ÚNICA pasarela a portales/MLS: aquí sólo se guarda una
--     referencia externa y un estado marcado manualmente. Sin scraping.
-- =============================================================================

begin;

-- -----------------------------------------------------------------------------
-- 0. Extensiones y esquemas
-- -----------------------------------------------------------------------------
create schema if not exists extensions;
create schema if not exists private;
revoke all on schema private from public;
grant usage on schema private to authenticated, service_role;

-- pg_trgm/unaccent (búsqueda difusa futura): se crean sólo si el servidor las ofrece.
do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_trgm') then
    execute 'create extension if not exists pg_trgm with schema extensions';
  end if;
  if exists (select 1 from pg_available_extensions where name = 'unaccent') then
    execute 'create extension if not exists unaccent with schema extensions';
  end if;
end $$;

-- -----------------------------------------------------------------------------
-- 1. Tipos enumerados
-- -----------------------------------------------------------------------------
create type public.app_role as enum ('agent', 'coordinator', 'supervisor');

-- Proceso comercial cerrado: el ORDEN de declaración ES el orden del pipeline.
create type public.pipeline_phase as enum (
  'circulo_influencia',  -- 1. Círculo de influencia
  'prospecto',           -- 2. Prospecto
  'captacion',           -- 3. Captación
  'documentacion',       -- 4. Documentación
  'publicacion',         -- 5. Publicación (vía Inmovilla, externo)
  'visitas',             -- 6. Visitas
  'cierre',              -- 7. Cierre (arras / reserva)
  'notaria'              -- 8. Notaría (escritura)
);

create type public.deal_status        as enum ('open', 'paused', 'won', 'lost');
create type public.operation_type     as enum ('sale', 'rent', 'transfer');
create type public.property_type      as enum ('flat', 'penthouse', 'duplex', 'studio', 'house', 'semi_detached',
                                               'townhouse', 'rustic', 'land', 'commercial', 'office', 'warehouse',
                                               'garage', 'storage_room', 'building', 'other');
create type public.property_status    as enum ('draft', 'in_acquisition', 'available', 'reserved', 'sold', 'rented', 'withdrawn');
create type public.property_condition as enum ('new', 'like_new', 'good', 'needs_update', 'to_reform', 'reformed');
create type public.energy_rating      as enum ('A', 'B', 'C', 'D', 'E', 'F', 'G', 'in_process', 'exempt');
create type public.heating_type       as enum ('none', 'individual_gas', 'individual_electric', 'central', 'heat_pump', 'other');
create type public.orientation        as enum ('N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW');
create type public.publication_status as enum ('not_published', 'pending_inmovilla', 'published_via_inmovilla', 'withdrawn');
create type public.contact_kind       as enum ('person', 'company');
create type public.lead_source        as enum ('influence_circle', 'referral', 'portal_via_inmovilla', 'website', 'walk_in',
                                               'signage', 'phone', 'social', 'mls', 'other');
create type public.deal_contact_role  as enum ('seller', 'buyer', 'landlord', 'tenant', 'co_owner', 'legal_representative',
                                               'heir', 'referrer', 'other');
create type public.interaction_type   as enum ('call', 'whatsapp', 'email', 'meeting', 'visit', 'note', 'valuation_delivery');
create type public.interaction_dir    as enum ('inbound', 'outbound', 'internal');
create type public.task_status        as enum ('pending', 'done', 'cancelled');
create type public.task_priority      as enum ('low', 'normal', 'high', 'urgent');
create type public.document_type      as enum ('dni', 'nie', 'passport', 'cif', 'nota_simple', 'escritura', 'cee', 'ibi',
                                               'cedula_habitabilidad', 'hoja_encargo', 'contrato_arras', 'contrato_alquiler',
                                               'hoja_visita', 'plano', 'certificado_comunidad', 'consentimiento_rgpd',
                                               'informe_valoracion', 'foto', 'otro');
create type public.data_sensitivity   as enum ('publishable', 'internal', 'sensitive');
create type public.consent_purpose    as enum ('service_provision', 'commercial_communications', 'property_matching',
                                               'audio_recording', 'share_with_mls', 'share_with_franchise', 'identity_verification');
create type public.legal_basis        as enum ('consent', 'contract', 'legal_obligation', 'legitimate_interest');
create type public.gdpr_request_type  as enum ('access', 'rectification', 'erasure', 'restriction', 'portability', 'objection');
create type public.gdpr_request_status as enum ('received', 'in_progress', 'completed', 'rejected');
create type public.processing_status  as enum ('uploaded', 'processing', 'completed', 'failed');
create type public.valuation_status   as enum ('draft', 'processing', 'ai_completed', 'in_review', 'pending_supervisor',
                                               'approved', 'delivered', 'failed', 'cancelled');
create type public.valuation_purpose  as enum ('acquisition', 'revaluation', 'quick_estimate', 'rental');
create type public.comparable_source  as enum ('internal_closed_deal', 'inmovilla_export', 'manual_market_observation',
                                               'notary_registry_stats', 'other');
create type public.demand_status      as enum ('active', 'paused', 'satisfied', 'cancelled');
create type public.financing_type     as enum ('cash', 'mortgage_preapproved', 'mortgage_pending', 'unknown');
create type public.match_status       as enum ('suggested', 'sent', 'interested', 'discarded', 'visit_scheduled');
create type public.visit_status       as enum ('scheduled', 'done', 'cancelled', 'no_show');
create type public.checklist_status   as enum ('in_progress', 'submitted', 'approved', 'rejected');
create type public.checklist_item_status as enum ('pending', 'submitted', 'approved', 'rejected', 'not_applicable');
create type public.offer_status       as enum ('draft', 'presented', 'accepted', 'rejected', 'withdrawn', 'expired');

-- -----------------------------------------------------------------------------
-- 2. Utilidades genéricas (sin dependencias de tablas)
-- -----------------------------------------------------------------------------
create or replace function private.try_uuid(p text)
returns uuid language plpgsql immutable set search_path = '' as $$
begin
  return p::uuid;
exception when others then
  return null;
end $$;

create or replace function private.set_updated_at()
returns trigger language plpgsql set search_path = '' as $$
begin
  new.updated_at := now();
  return new;
end $$;

create or replace function private.phase_index(p public.pipeline_phase)
returns int language sql stable set search_path = '' as $$
  select array_position(enum_range(null::public.pipeline_phase), p)
$$;

-- =============================================================================
-- 3. MÓDULO CORE · Usuarios, zonas, contactos  [F1]
-- =============================================================================
create table public.profiles (
  id          uuid primary key references auth.users(id) on delete cascade,
  full_name   text not null,
  email       text not null,
  phone       text,
  role        public.app_role not null default 'agent',
  is_active   boolean not null default false,  -- alta controlada por supervisor
  franchise_agent_code text,                    -- código de agente en la franquicia / Inmovilla
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
comment on table public.profiles is '[F1] Perfil interno de cada usuario de Supabase Auth. El rol vive aquí (no en user_metadata).';
create index profiles_role_idx on public.profiles (role) where is_active;

create table public.zones (
  id           uuid primary key default gen_random_uuid(),
  parent_id    uuid references public.zones(id) on delete restrict,
  name         text not null,
  city         text not null,
  province     text not null default 'Barcelona',
  postal_codes text[] not null default '{}',
  is_active    boolean not null default true,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  unique (city, name)
);
comment on table public.zones is '[F1] Zonificación comercial propia (barrio > distrito > municipio). Base del cruce y del valorador.';
create index zones_parent_idx on public.zones (parent_id);

create table public.contacts (
  id               uuid primary key default gen_random_uuid(),
  owner_agent_id   uuid not null references public.profiles(id) on delete restrict,
  kind             public.contact_kind not null default 'person',
  first_name       text,
  last_name        text,
  company_name     text,
  email            text,
  phone            text,
  phone_secondary  text,
  preferred_channel public.interaction_type,
  source           public.lead_source not null default 'other',
  in_influence_circle boolean not null default false,  -- Círculo de influencia del agente
  relationship_note   text,                             -- "vecino", "cliente 2021", ...
  referred_by_contact_id uuid references public.contacts(id) on delete set null,
  tags             text[] not null default '{}',
  last_interaction_at timestamptz,
  retention_until  date,          -- fecha prevista de supresión/anonimización
  anonymized_at    timestamptz,
  deleted_at       timestamptz,   -- soft delete
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  constraint contacts_name_chk check (
    anonymized_at is not null
    or (kind = 'person' and coalesce(first_name, last_name) is not null)
    or (kind = 'company' and company_name is not null)
  )
);
comment on table public.contacts is '[F1] Contactos (propietarios, compradores, inquilinos, círculo de influencia). SOLO datos no sensibles.';
create index contacts_owner_idx   on public.contacts (owner_agent_id) where deleted_at is null;
create index contacts_email_idx   on public.contacts (lower(email)) where email is not null;
create index contacts_phone_idx   on public.contacts (phone) where phone is not null;
create index contacts_referred_idx on public.contacts (referred_by_contact_id);

create table public.contact_sensitive (
  contact_id        uuid primary key references public.contacts(id) on delete cascade,
  national_id_type  text check (national_id_type in ('dni', 'nie', 'passport', 'cif')),
  national_id_number text,
  birth_date        date,
  nationality       text,
  marital_status    text,
  postal_address    text,
  iban              text,
  pbc_verified_at   timestamptz,   -- verificación identidad Ley 10/2010 (PBC)
  pbc_verified_by   uuid references public.profiles(id),
  internal_notes    text,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);
comment on table public.contact_sensitive is '[F1] Datos personales sensibles (DNI, dirección, IBAN, PBC). RLS restringido: agente titular, coordinador, supervisor. Auditado.';

create table public.consent_records (
  id             uuid primary key default gen_random_uuid(),
  contact_id     uuid not null references public.contacts(id) on delete cascade,
  purpose        public.consent_purpose not null,
  legal_basis    public.legal_basis not null,
  granted        boolean not null,
  policy_version text not null,               -- versión del texto informativo aceptado
  channel        text not null,               -- 'firma_papel', 'web', 'audio', 'email'...
  evidence_document_id uuid,                  -- FK diferida a documents (ver más abajo)
  collected_by   uuid references public.profiles(id),
  collected_at   timestamptz not null default now(),
  expires_at     date,
  revoked_at     timestamptz,
  created_at     timestamptz not null default now()
);
comment on table public.consent_records is '[F1] Registro inmutable (append-only) de consentimientos y bases de legitimación. Un cambio = una fila nueva.';
create index consent_contact_idx on public.consent_records (contact_id, purpose, collected_at desc);

create table public.gdpr_requests (
  id            uuid primary key default gen_random_uuid(),
  contact_id    uuid references public.contacts(id) on delete set null,
  request_type  public.gdpr_request_type not null,
  status        public.gdpr_request_status not null default 'received',
  received_at   timestamptz not null default now(),
  due_at        timestamptz not null default (now() + interval '1 month'),
  resolved_at   timestamptz,
  resolution    text,
  handled_by    uuid references public.profiles(id),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
comment on table public.gdpr_requests is '[F1] Ejercicio de derechos RGPD (plazo legal 1 mes). Gestionado por supervisor.';
create index gdpr_requests_contact_idx on public.gdpr_requests (contact_id);

-- =============================================================================
-- 4. MÓDULO INMUEBLES · Ficha técnica (absorbe Inmovilla/Horus)  [F1 / F2]
-- =============================================================================
create table public.properties (
  id                 uuid primary key default gen_random_uuid(),
  reference          text not null unique,          -- ref. interna RK (p.ej. RK-2026-0001)
  owner_agent_id     uuid not null references public.profiles(id) on delete restrict,
  status             public.property_status not null default 'draft',
  operation_type     public.operation_type not null default 'sale',
  property_type      public.property_type not null,
  -- Localización interna (dirección exacta = dato interno)
  street             text,
  street_number      text,
  floor_label        text,
  door               text,
  postal_code        text,
  city               text not null,
  province           text not null default 'Barcelona',
  zone_id            uuid references public.zones(id) on delete set null,
  latitude           numeric(9,6),
  longitude          numeric(9,6),
  cadastral_reference text,
  -- Ficha técnica
  built_area_m2      numeric(10,2) check (built_area_m2 > 0),
  useful_area_m2     numeric(10,2) check (useful_area_m2 > 0),
  plot_area_m2       numeric(12,2) check (plot_area_m2 > 0),
  bedrooms           smallint check (bedrooms >= 0),
  bathrooms          smallint check (bathrooms >= 0),
  floor_number       smallint,
  total_floors       smallint,
  year_built         smallint check (year_built between 1700 and 2100),
  condition          public.property_condition,
  energy_rating      public.energy_rating,
  energy_consumption_kwh numeric(8,2),
  emissions_kgco2    numeric(8,2),
  orientation        public.orientation,
  heating            public.heating_type,
  is_exterior        boolean,
  has_elevator       boolean,
  has_terrace        boolean,
  terrace_m2         numeric(8,2),
  has_balcony        boolean,
  has_garage         boolean,
  garage_spaces      smallint,
  has_storage_room   boolean,
  has_pool           boolean,
  has_garden         boolean,
  has_air_conditioning boolean,
  is_furnished       boolean,
  is_accessible      boolean,
  features           text[] not null default '{}',   -- extras libres normalizados (slug)
  community_fee_month numeric(10,2),
  ibi_year           numeric(10,2),
  -- Precio
  asking_price       numeric(12,2) check (asking_price >= 0),
  price_per_m2       numeric(10,2) generated always as
                     (case when built_area_m2 > 0 then round(asking_price / built_area_m2, 2) end) stored,
  -- Frontera Inmovilla (solo referencia + estado manual)
  inmovilla_ref      text unique,
  publication_status public.publication_status not null default 'not_published',
  publication_status_at timestamptz,
  deleted_at         timestamptz,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);
comment on table public.properties is '[F1] Ficha técnica operativa del inmueble (dato interno). Lo publicable vive en property_public_profile. inmovilla_ref/publication_status se marcan MANUALMENTE: la publicación ocurre en Inmovilla.';
create index properties_owner_idx    on public.properties (owner_agent_id) where deleted_at is null;
create index properties_zone_idx     on public.properties (zone_id);
create index properties_match_idx    on public.properties (operation_type, status, property_type, asking_price) where deleted_at is null;

create table public.property_internal (
  property_id         uuid primary key references public.properties(id) on delete cascade,
  owner_min_price     numeric(12,2),   -- precio mínimo aceptado por la propiedad (confidencial)
  commission_pct      numeric(5,2) check (commission_pct between 0 and 100),
  commission_fixed    numeric(12,2),
  exclusivity         boolean not null default false,
  mandate_start       date,
  mandate_end         date,
  pending_mortgage    numeric(12,2),
  keys_location       text,
  alarm_info          text,
  occupancy_notes     text,           -- inquilinos, okupación, herencias...
  legal_notes         text,
  internal_notes      text,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  constraint mandate_dates_chk check (mandate_end is null or mandate_start is null or mandate_end >= mandate_start)
);
comment on table public.property_internal is '[F1] Datos internos/confidenciales del encargo (precio mínimo, comisión, llaves). Solo agente titular y supervisor.';

create table public.property_owners (
  property_id   uuid not null references public.properties(id) on delete cascade,
  contact_id    uuid not null references public.contacts(id) on delete restrict,
  ownership_pct numeric(5,2) check (ownership_pct > 0 and ownership_pct <= 100),
  role          public.deal_contact_role not null default 'seller',
  created_at    timestamptz not null default now(),
  primary key (property_id, contact_id)
);
comment on table public.property_owners is '[F1] Titulares del inmueble (proindivisos, herencias, usufructos).';
create index property_owners_contact_idx on public.property_owners (contact_id);

create table public.property_public_profile (
  property_id        uuid primary key references public.properties(id) on delete cascade,
  public_title       text not null,
  public_description text,
  public_zone_label  text,          -- zona aproximada, NUNCA la dirección exacta
  show_price         boolean not null default true,
  public_price       numeric(12,2),
  highlights         text[] not null default '{}',
  virtual_tour_url   text,
  approved_by        uuid references public.profiles(id),
  approved_at        timestamptz,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);
comment on table public.property_public_profile is '[F2] Contenido publicable al cliente / a cargar en Inmovilla. Sin dirección exacta ni datos de propietarios.';

-- =============================================================================
-- 5. MÓDULO EXPEDIENTES · Pipeline de 8 fases  [F1]
-- =============================================================================
create sequence public.deal_code_seq;

create table public.deals (
  id                 uuid primary key default gen_random_uuid(),
  code               text not null unique default ('EXP-' || to_char(now(), 'YYYY') || '-' || lpad(nextval('public.deal_code_seq')::text, 5, '0')),
  agent_id           uuid not null references public.profiles(id) on delete restrict,
  primary_contact_id uuid not null references public.contacts(id) on delete restrict,
  property_id        uuid references public.properties(id) on delete set null,
  operation_type     public.operation_type not null default 'sale',
  phase              public.pipeline_phase not null default 'circulo_influencia',
  status             public.deal_status not null default 'open',
  phase_changed_at   timestamptz not null default now(),
  expected_price     numeric(12,2),
  expected_fee       numeric(12,2),
  expected_close_date date,
  lost_reason        text,
  closed_at          timestamptz,
  deleted_at         timestamptz,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  constraint deals_won_chk  check (status <> 'won'  or phase = 'notaria'),
  constraint deals_lost_chk check (status <> 'lost' or lost_reason is not null)
);
comment on table public.deals is '[F1] Expediente comercial. La columna phase sólo puede avanzar de una en una (trigger) y cada cambio queda en deal_phase_history.';
create index deals_agent_idx    on public.deals (agent_id) where deleted_at is null;
create index deals_phase_idx    on public.deals (phase, status) where deleted_at is null;
create index deals_contact_idx  on public.deals (primary_contact_id);
create index deals_property_idx on public.deals (property_id);

create table public.deal_contacts (
  deal_id    uuid not null references public.deals(id) on delete cascade,
  contact_id uuid not null references public.contacts(id) on delete restrict,
  role       public.deal_contact_role not null,
  created_at timestamptz not null default now(),
  primary key (deal_id, contact_id, role)
);
comment on table public.deal_contacts is '[F1] Intervinientes del expediente (vendedor, comprador, representante...).';
create index deal_contacts_contact_idx on public.deal_contacts (contact_id);

create table public.deal_phase_history (
  id          bigint generated always as identity primary key,
  deal_id     uuid not null references public.deals(id) on delete cascade,
  from_phase  public.pipeline_phase,
  to_phase    public.pipeline_phase not null,
  changed_by  uuid references public.profiles(id),
  changed_at  timestamptz not null default now(),
  reason      text,
  is_rollback boolean not null default false
);
comment on table public.deal_phase_history is '[F1] Auditoría inmutable de cambios de fase (la escribe sólo el trigger).';
create index deal_phase_history_deal_idx on public.deal_phase_history (deal_id, changed_at desc);

-- =============================================================================
-- 6. DOCUMENTOS / ARCHIVOS (metadatos de Storage privado)  [F1]
-- =============================================================================
create table public.documents (
  id              uuid primary key default gen_random_uuid(),
  bucket_id       text not null,
  object_path     text not null,
  document_type   public.document_type not null,
  sensitivity     public.data_sensitivity not null default 'internal',
  deal_id         uuid references public.deals(id) on delete set null,
  contact_id      uuid references public.contacts(id) on delete set null,
  property_id     uuid references public.properties(id) on delete set null,
  original_filename text,
  mime_type       text,
  size_bytes      bigint,
  sha256          text,
  uploaded_by     uuid not null references public.profiles(id),
  review_status   public.checklist_item_status not null default 'pending',
  reviewed_by     uuid references public.profiles(id),
  reviewed_at     timestamptz,
  review_comment  text,
  retention_until date,                      -- p.ej. DNI/PBC: 10 años (Ley 10/2010)
  purge_requested_at timestamptz,            -- marcado para borrado físico vía Storage API
  deleted_at      timestamptz,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  unique (bucket_id, object_path),
  constraint documents_owner_chk check (num_nonnulls(deal_id, contact_id, property_id) >= 1)
);
comment on table public.documents is '[F1] Metadatos de cada archivo en buckets privados (DNI, notas simples, contratos, audios...).';
create index documents_deal_idx     on public.documents (deal_id);
create index documents_contact_idx  on public.documents (contact_id);
create index documents_property_idx on public.documents (property_id);
create index documents_uploader_idx on public.documents (uploaded_by);
create index documents_review_idx   on public.documents (review_status) where deleted_at is null;

alter table public.consent_records
  add constraint consent_evidence_fk foreign key (evidence_document_id) references public.documents(id) on delete set null;
create index consent_evidence_idx on public.consent_records (evidence_document_id);

-- =============================================================================
-- 7. SEGUIMIENTO DE CLIENTES (interacciones y tareas)  [F1]
-- =============================================================================
create table public.interactions (
  id           uuid primary key default gen_random_uuid(),
  agent_id     uuid not null references public.profiles(id) on delete restrict,
  contact_id   uuid not null references public.contacts(id) on delete cascade,
  deal_id      uuid references public.deals(id) on delete set null,
  property_id  uuid references public.properties(id) on delete set null,
  type         public.interaction_type not null,
  direction    public.interaction_dir not null default 'outbound',
  occurred_at  timestamptz not null default now(),
  summary      text not null,
  outcome      text,
  next_action_at timestamptz,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
comment on table public.interactions is '[F1] Historial de seguimiento (llamadas, WhatsApp, reuniones, notas).';
create index interactions_agent_idx   on public.interactions (agent_id, occurred_at desc);
create index interactions_contact_idx on public.interactions (contact_id, occurred_at desc);
create index interactions_deal_idx    on public.interactions (deal_id);
create index interactions_property_idx on public.interactions (property_id);

create table public.tasks (
  id           uuid primary key default gen_random_uuid(),
  assigned_to  uuid not null references public.profiles(id) on delete restrict,
  created_by   uuid not null references public.profiles(id) on delete restrict,
  contact_id   uuid references public.contacts(id) on delete cascade,
  deal_id      uuid references public.deals(id) on delete cascade,
  property_id  uuid references public.properties(id) on delete cascade,
  title        text not null,
  description  text,
  due_at       timestamptz,
  priority     public.task_priority not null default 'normal',
  status       public.task_status not null default 'pending',
  completed_at timestamptz,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
comment on table public.tasks is '[F1] Tareas / recordatorios de seguimiento.';
create index tasks_assigned_idx on public.tasks (assigned_to, status, due_at);
create index tasks_creator_idx  on public.tasks (created_by);
create index tasks_deal_idx     on public.tasks (deal_id);
create index tasks_contact_idx  on public.tasks (contact_id);
create index tasks_property_idx on public.tasks (property_id);

-- =============================================================================
-- 8. AUDIOS Y TRANSCRIPCIONES  [F1]
-- =============================================================================
create table public.audio_recordings (
  id              uuid primary key default gen_random_uuid(),
  deal_id         uuid references public.deals(id) on delete cascade,             -- opcional
  property_id     uuid references public.properties(id) on delete cascade,        -- opcional
  -- valuation_request_id se añade tras crear valuation_requests (dependencia circular vía transcriptions)
  document_id     uuid not null unique references public.documents(id) on delete restrict,
  recorded_by     uuid not null references public.profiles(id),
  contact_id      uuid references public.contacts(id) on delete set null,
  consent_record_id uuid references public.consent_records(id) on delete restrict,
  context         text not null default 'captacion' check (context in ('captacion', 'visita', 'valoracion', 'reunion', 'nota_voz')),
  duration_seconds integer check (duration_seconds >= 0),
  status          public.processing_status not null default 'uploaded',
  recorded_at     timestamptz not null default now(),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  constraint audio_consent_chk check (context = 'nota_voz' or consent_record_id is not null)
);
comment on table public.audio_recordings is '[F1] Grabaciones (bucket privado audio-recordings, ruta {deal|property|valuation}/{id}/...). Vinculadas a expediente, inmueble y/o valoración (al menos uno). Requiere consentimiento salvo notas de voz internas del agente.';
create index audio_deal_idx     on public.audio_recordings (deal_id);
create index audio_property_idx on public.audio_recordings (property_id);
create index audio_recorder_idx on public.audio_recordings (recorded_by);
create index audio_contact_idx  on public.audio_recordings (contact_id);
create index audio_consent_idx  on public.audio_recordings (consent_record_id);

create table public.transcriptions (
  id              uuid primary key default gen_random_uuid(),
  audio_id        uuid not null references public.audio_recordings(id) on delete cascade,
  model           text not null,
  language        text not null default 'es',
  full_text       text not null,
  segments        jsonb,                    -- [{start, end, speaker, text}]
  summary         text,
  extracted_facts jsonb,                    -- validado con Zod (TranscriptFactsSchema)
  created_at      timestamptz not null default now()
);
comment on table public.transcriptions is '[F1] Transcripción + hechos extraídos (alimentan ficha técnica y valoración).';
create index transcriptions_audio_idx on public.transcriptions (audio_id);

-- =============================================================================
-- 9. VALORADOR IA  [F1]
-- =============================================================================
create table public.valuation_parameters (
  id            uuid primary key default gen_random_uuid(),
  version       integer not null unique check (version > 0),
  is_active     boolean not null default false,
  params        jsonb not null,               -- ver ValuationParamsSchema (Zod)
  notes         text,
  created_by    uuid references public.profiles(id),  -- null = versión de sistema cargada por seed.sql
  created_at    timestamptz not null default now(),
  activated_at  timestamptz,
  constraint valuation_params_obj_chk check (jsonb_typeof(params) = 'object')
);
comment on table public.valuation_parameters is '[F1] Parámetros del valorador, versionados e inmutables. Sólo el supervisor crea/activa versiones.';
create unique index valuation_parameters_one_active on public.valuation_parameters ((true)) where is_active;
create index valuation_parameters_creator_idx on public.valuation_parameters (created_by);

create table public.valuation_zone_benchmarks (
  id              uuid primary key default gen_random_uuid(),
  parameters_id   uuid not null references public.valuation_parameters(id) on delete cascade,
  zone_id         uuid not null references public.zones(id) on delete cascade,
  property_type   public.property_type,       -- null = todos
  operation_type  public.operation_type not null default 'sale',
  base_price_m2   numeric(10,2) not null check (base_price_m2 > 0),
  source_note     text,
  is_placeholder  boolean not null default false,  -- true = valor de EJEMPLO (seed); el valorador no debe usarlo sin validar
  unique nulls not distinct (parameters_id, zone_id, property_type, operation_type)
);
comment on table public.valuation_zone_benchmarks is '[F1] €/m² de referencia por zona y tipología, ligados a una versión de parámetros (sólo supervisor).';
create index vzb_zone_idx on public.valuation_zone_benchmarks (zone_id);

create table public.valuation_requests (
  id              uuid primary key default gen_random_uuid(),
  property_id     uuid not null references public.properties(id) on delete restrict,
  deal_id         uuid references public.deals(id) on delete set null,
  requested_by    uuid not null references public.profiles(id),
  purpose         public.valuation_purpose not null default 'acquisition',
  status          public.valuation_status not null default 'draft',
  parameters_id   uuid references public.valuation_parameters(id),
  input_snapshot  jsonb,                 -- foto de la ficha técnica en el momento de valorar
  transcription_id uuid references public.transcriptions(id) on delete set null,
  error_message   text,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
comment on table public.valuation_requests is '[F1] Solicitud de valoración. Fija la versión de parámetros usada (trazabilidad).';
create index valuation_requests_property_idx on public.valuation_requests (property_id);
create index valuation_requests_deal_idx     on public.valuation_requests (deal_id);
create index valuation_requests_agent_idx    on public.valuation_requests (requested_by, created_at desc);
create index valuation_requests_params_idx   on public.valuation_requests (parameters_id);
create index valuation_requests_tx_idx       on public.valuation_requests (transcription_id);

create table public.valuation_comparables (
  id              uuid primary key default gen_random_uuid(),
  valuation_id    uuid not null references public.valuation_requests(id) on delete cascade,
  source          public.comparable_source not null,
  source_reference text,                  -- ref. interna, ref. Inmovilla, nota del agente (sin scraping)
  source_deal_id  uuid references public.deals(id) on delete set null,
  zone_id         uuid references public.zones(id) on delete set null,
  approx_address  text,
  property_type   public.property_type not null,
  operation_type  public.operation_type not null default 'sale',
  built_area_m2   numeric(10,2) not null check (built_area_m2 > 0),
  bedrooms        smallint,
  bathrooms       smallint,
  condition       public.property_condition,
  price           numeric(12,2) not null check (price > 0),
  price_per_m2    numeric(10,2) generated always as (round(price / built_area_m2, 2)) stored,
  is_closing_price boolean not null default false,  -- precio de cierre vs. precio de oferta
  observed_at     date not null,
  distance_m      integer,
  similarity_score numeric(5,2) check (similarity_score between 0 and 100),
  adjustment_pct  numeric(6,2),
  included        boolean not null default true,
  added_by        uuid references public.profiles(id),
  created_at      timestamptz not null default now()
);
comment on table public.valuation_comparables is '[F1] Testigos/comparables. Fuentes internas o introducidas manualmente: NO hay scraping de portales.';
create index valuation_comparables_val_idx on public.valuation_comparables (valuation_id);
create index valuation_comparables_deal_idx on public.valuation_comparables (source_deal_id);
create index valuation_comparables_zone_idx on public.valuation_comparables (zone_id);
create index valuation_comparables_adder_idx on public.valuation_comparables (added_by);

create table public.valuation_ai_runs (
  id                uuid primary key default gen_random_uuid(),
  valuation_id      uuid not null references public.valuation_requests(id) on delete cascade,
  parameters_id     uuid not null references public.valuation_parameters(id),
  provider          text not null,
  model             text not null,
  prompt_version    text not null,
  output_schema_version text not null,
  input_payload     jsonb not null,
  output            jsonb,               -- salida validada con ValuationAIOutputSchema
  estimated_value   numeric(12,2),
  estimated_min     numeric(12,2),
  estimated_max     numeric(12,2),
  estimated_price_m2 numeric(10,2),
  confidence        numeric(4,3) check (confidence between 0 and 1),
  success           boolean not null,
  error_message     text,
  latency_ms        integer,
  input_tokens      integer,
  output_tokens     integer,
  created_by        uuid references public.profiles(id),
  created_at        timestamptz not null default now(),
  constraint ai_run_range_chk check (
    not success or (estimated_min <= estimated_value and estimated_value <= estimated_max and output is not null)
  )
);
comment on table public.valuation_ai_runs is '[F1] Cada ejecución del modelo (inmutable): modelo, versión de prompt, entrada, salida JSON validada, confianza.';
create index valuation_ai_runs_val_idx on public.valuation_ai_runs (valuation_id, created_at desc);
create index valuation_ai_runs_params_idx on public.valuation_ai_runs (parameters_id);
create index valuation_ai_runs_creator_idx on public.valuation_ai_runs (created_by);

create table public.valuation_reviews (
  id                uuid primary key default gen_random_uuid(),
  valuation_id      uuid not null references public.valuation_requests(id) on delete cascade,
  ai_run_id         uuid not null references public.valuation_ai_runs(id) on delete restrict,
  ai_value          numeric(12,2) not null,  -- copia del valor IA (para medir desviación)
  adjusted_value    numeric(12,2) not null check (adjusted_value > 0),
  adjusted_min      numeric(12,2),
  adjusted_max      numeric(12,2),
  adjustment_pct    numeric(7,2) generated always as (round((adjusted_value - ai_value) / nullif(ai_value, 0) * 100, 2)) stored,
  adjustment_reason text,
  requires_supervisor boolean not null default false,
  reviewed_by       uuid not null references public.profiles(id),
  approved_by       uuid references public.profiles(id),
  approved_at       timestamptz,
  is_final          boolean not null default false,
  created_at        timestamptz not null default now(),
  constraint review_reason_chk check (adjusted_value = ai_value or adjustment_reason is not null)
);
comment on table public.valuation_reviews is '[F1] Ajustes humanos sobre la propuesta IA. Si la desviación supera el umbral de parámetros, requiere aprobación del supervisor.';
create index valuation_reviews_val_idx on public.valuation_reviews (valuation_id);
create index valuation_reviews_run_idx on public.valuation_reviews (ai_run_id);
create index valuation_reviews_reviewer_idx on public.valuation_reviews (reviewed_by);
create unique index valuation_reviews_one_final on public.valuation_reviews (valuation_id) where is_final;

create table public.valuation_client_reports (
  valuation_id    uuid primary key references public.valuation_requests(id) on delete cascade,
  review_id       uuid not null references public.valuation_reviews(id) on delete restrict,
  display_value   numeric(12,2) not null,
  display_min     numeric(12,2),
  display_max     numeric(12,2),
  client_summary  text not null,          -- texto publicable (sin razonamiento interno)
  public_comparables jsonb not null default '[]'::jsonb,  -- testigos anonimizados
  report_document_id uuid references public.documents(id) on delete set null,
  delivered_at    timestamptz,
  delivered_by    uuid references public.profiles(id),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
comment on table public.valuation_client_reports is '[F1] Versión PUBLICABLE de la valoración entregada al cliente (separada del razonamiento interno).';
create index vcr_review_idx on public.valuation_client_reports (review_id);
create index vcr_doc_idx on public.valuation_client_reports (report_document_id);

-- Audios y documentos ligados a una valoración sin expediente (valoración rápida)
alter table public.audio_recordings
  add column valuation_request_id uuid references public.valuation_requests(id) on delete cascade,
  add constraint audio_owner_chk check (num_nonnulls(deal_id, property_id, valuation_request_id) >= 1);
create index audio_valuation_idx on public.audio_recordings (valuation_request_id);

alter table public.documents
  add column valuation_request_id uuid references public.valuation_requests(id) on delete set null,
  drop constraint documents_owner_chk,
  add constraint documents_owner_chk check (num_nonnulls(deal_id, contact_id, property_id, valuation_request_id) >= 1);
create index documents_valuation_idx on public.documents (valuation_request_id);

-- =============================================================================
-- 10. DEMANDAS Y CRUCE AUTOMÁTICO  [F2]
-- =============================================================================
create table public.demands (
  id              uuid primary key default gen_random_uuid(),
  contact_id      uuid not null references public.contacts(id) on delete cascade,
  agent_id        uuid not null references public.profiles(id) on delete restrict,
  deal_id         uuid references public.deals(id) on delete set null,
  operation_type  public.operation_type not null default 'sale',
  status          public.demand_status not null default 'active',
  property_types  public.property_type[] not null default '{}',   -- vacío = cualquiera
  price_min       numeric(12,2) check (price_min >= 0),
  price_max       numeric(12,2) check (price_max >= 0),
  bedrooms_min    smallint,
  bathrooms_min   smallint,
  area_min_m2     numeric(10,2),
  area_max_m2     numeric(10,2),
  needs_elevator  boolean not null default false,
  needs_garage    boolean not null default false,
  needs_terrace   boolean not null default false,
  needs_exterior  boolean not null default false,
  needs_storage_room boolean not null default false,
  needs_pool      boolean not null default false,
  needs_garden    boolean not null default false,
  desired_features text[] not null default '{}',
  financing       public.financing_type not null default 'unknown',
  urgency         smallint check (urgency between 1 and 5),
  notes           text,
  last_matched_at timestamptz,
  deleted_at      timestamptz,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  constraint demand_price_chk check (price_min is null or price_max is null or price_min <= price_max),
  constraint demand_area_chk  check (area_min_m2 is null or area_max_m2 is null or area_min_m2 <= area_max_m2)
);
comment on table public.demands is '[F2] Demandas de compradores/inquilinos (modelo Inmovilla/Horus mejorado).';
create index demands_agent_idx   on public.demands (agent_id) where deleted_at is null;
create index demands_contact_idx on public.demands (contact_id);
create index demands_deal_idx    on public.demands (deal_id);
create index demands_match_idx   on public.demands (operation_type, status) where deleted_at is null;

create table public.demand_zones (
  demand_id uuid not null references public.demands(id) on delete cascade,
  zone_id   uuid not null references public.zones(id) on delete cascade,
  primary key (demand_id, zone_id)
);
comment on table public.demand_zones is '[F2] Zonas de interés de una demanda.';
create index demand_zones_zone_idx on public.demand_zones (zone_id);

create table public.property_demand_matches (
  id              uuid primary key default gen_random_uuid(),
  property_id     uuid not null references public.properties(id) on delete cascade,
  demand_id       uuid not null references public.demands(id) on delete cascade,
  score           numeric(5,2) not null check (score between 0 and 100),
  score_breakdown jsonb not null,
  status          public.match_status not null default 'suggested',
  computed_at     timestamptz not null default now(),
  sent_at         timestamptz,
  feedback        text,
  updated_at      timestamptz not null default now(),
  unique (property_id, demand_id)
);
comment on table public.property_demand_matches is '[F2] Resultado persistido del cruce automático inmueble↔demanda con desglose de puntuación.';
create index pdm_demand_idx on public.property_demand_matches (demand_id, score desc);

create table public.visits (
  id              uuid primary key default gen_random_uuid(),
  deal_id         uuid references public.deals(id) on delete set null,
  property_id     uuid not null references public.properties(id) on delete cascade,
  demand_id       uuid references public.demands(id) on delete set null,
  visitor_contact_id uuid not null references public.contacts(id) on delete restrict,
  agent_id        uuid not null references public.profiles(id) on delete restrict,
  scheduled_at    timestamptz not null,
  status          public.visit_status not null default 'scheduled',
  visit_sheet_document_id uuid references public.documents(id) on delete set null,  -- hoja de visita firmada
  rating          smallint check (rating between 1 and 5),
  feedback        text,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
comment on table public.visits is '[F2] Visitas (fase Visitas) con hoja de visita firmada.';
create index visits_agent_idx    on public.visits (agent_id, scheduled_at);
create index visits_property_idx on public.visits (property_id);
create index visits_deal_idx     on public.visits (deal_id);
create index visits_demand_idx   on public.visits (demand_id);
create index visits_contact_idx  on public.visits (visitor_contact_id);
create index visits_sheet_idx    on public.visits (visit_sheet_document_id);

-- =============================================================================
-- 11. CHECKLISTS DE FRANQUICIA  [F2]
-- =============================================================================
create table public.checklist_templates (
  id             uuid primary key default gen_random_uuid(),
  name           text not null,
  franchise_code text,
  phase          public.pipeline_phase not null,
  operation_type public.operation_type,     -- null = aplica a todas
  version        integer not null default 1,
  is_active      boolean not null default true,
  created_by     uuid references public.profiles(id),
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  unique (name, version)
);
comment on table public.checklist_templates is '[F2] Plantillas de checklist por fase (franquicia). Gestionadas por coordinador/supervisor.';
create index checklist_templates_phase_idx on public.checklist_templates (phase) where is_active;

create table public.checklist_template_items (
  id                uuid primary key default gen_random_uuid(),
  template_id       uuid not null references public.checklist_templates(id) on delete cascade,
  position          integer not null,
  title             text not null,
  description       text,
  is_required       boolean not null default true,
  requires_document boolean not null default false,
  document_type     public.document_type,
  due_days          integer,
  unique (template_id, position)
);
comment on table public.checklist_template_items is '[F2] Puntos de cada plantilla.';

create table public.deal_checklists (
  id           uuid primary key default gen_random_uuid(),
  deal_id      uuid not null references public.deals(id) on delete cascade,
  template_id  uuid not null references public.checklist_templates(id) on delete restrict,
  phase        public.pipeline_phase not null,
  status       public.checklist_status not null default 'in_progress',
  submitted_at timestamptz,
  reviewed_by  uuid references public.profiles(id),
  reviewed_at  timestamptz,
  review_comment text,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  unique (deal_id, template_id)
);
comment on table public.deal_checklists is '[F2] Instancia de checklist por expediente y fase. Su aprobación por el coordinador desbloquea el avance de fase.';
create index deal_checklists_deal_idx on public.deal_checklists (deal_id, phase);
create index deal_checklists_template_idx on public.deal_checklists (template_id);
create index deal_checklists_review_idx on public.deal_checklists (status);

create table public.deal_checklist_items (
  id                uuid primary key default gen_random_uuid(),
  deal_checklist_id uuid not null references public.deal_checklists(id) on delete cascade,
  template_item_id  uuid references public.checklist_template_items(id) on delete set null,
  position          integer not null,
  title             text not null,
  is_required       boolean not null,
  requires_document boolean not null default false,
  status            public.checklist_item_status not null default 'pending',
  document_id       uuid references public.documents(id) on delete set null,
  due_at            timestamptz,
  completed_by      uuid references public.profiles(id),
  completed_at      timestamptz,
  reviewed_by       uuid references public.profiles(id),
  reviewed_at       timestamptz,
  review_comment    text,
  updated_at        timestamptz not null default now()
);
comment on table public.deal_checklist_items is '[F2] Puntos instanciados. El agente marca submitted; sólo coordinador/supervisor aprueba o rechaza.';
create index dci_checklist_idx on public.deal_checklist_items (deal_checklist_id);
create index dci_template_item_idx on public.deal_checklist_items (template_item_id);
create index dci_document_idx on public.deal_checklist_items (document_id);

-- =============================================================================
-- 12. CIERRE Y NOTARÍA  [F3]
-- =============================================================================
create table public.deal_offers (
  id               uuid primary key default gen_random_uuid(),
  deal_id          uuid not null references public.deals(id) on delete cascade,
  buyer_contact_id uuid not null references public.contacts(id) on delete restrict,
  amount           numeric(12,2) not null check (amount > 0),
  conditions       text,
  status           public.offer_status not null default 'draft',
  presented_at     timestamptz,
  expires_at       timestamptz,
  created_by       uuid not null references public.profiles(id),
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);
comment on table public.deal_offers is '[F3] Ofertas/contraofertas (fase Cierre).';
create index deal_offers_deal_idx on public.deal_offers (deal_id);
create index deal_offers_buyer_idx on public.deal_offers (buyer_contact_id);
create index deal_offers_creator_idx on public.deal_offers (created_by);

create table public.deal_closings (
  deal_id            uuid primary key references public.deals(id) on delete cascade,
  accepted_offer_id  uuid references public.deal_offers(id) on delete set null,
  arras_type         text check (arras_type in ('penitenciales', 'confirmatorias', 'penales')),
  arras_amount       numeric(12,2),
  arras_signed_at    date,
  final_price        numeric(12,2),
  commission_amount  numeric(12,2),
  notary_name        text,
  notary_appointment timestamptz,
  deed_signed_at     date,
  protocol_number    text,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);
comment on table public.deal_closings is '[F3] Datos de arras, precio final, comisión y notaría.';
create index deal_closings_offer_idx on public.deal_closings (accepted_offer_id);

-- =============================================================================
-- 13. AUDITORÍA  [F1]
-- =============================================================================
create table public.audit_log (
  id          bigint generated always as identity primary key,
  table_name  text not null,
  record_id   text,
  action      text not null check (action in ('INSERT', 'UPDATE', 'DELETE')),
  actor_id    uuid,
  changed_at  timestamptz not null default now(),
  old_data    jsonb,
  new_data    jsonb
);
comment on table public.audit_log is '[F1] Auditoría de tablas sensibles (RGPD art. 5.2 responsabilidad proactiva). Sólo lectura para supervisor.';
create index audit_log_table_idx on public.audit_log (table_name, record_id, changed_at desc);

create unique index checklist_templates_one_active_per_name on public.checklist_templates (name) where is_active;

-- =============================================================================
-- 14. FUNCIONES AUXILIARES DE SEGURIDAD (private, SECURITY DEFINER)
--     Leen tablas saltándose RLS => evitan recursión en las políticas.
-- =============================================================================
create or replace function private.auth_role()
returns public.app_role language sql stable security definer set search_path = '' as $$
  select p.role from public.profiles p
  where p.id = (select auth.uid()) and p.is_active
$$;
comment on function private.auth_role() is 'Rol del usuario actual (null si no existe o está inactivo).';

create or replace function private.current_user_id()
returns uuid language sql stable security definer set search_path = '' as $$
  select p.id from public.profiles p
  where p.id = (select auth.uid()) and p.is_active
$$;
comment on function private.current_user_id() is 'auth.uid() sólo si el perfil está activo; si no, null (bloquea a usuarios dados de baja).';

create or replace function private.is_supervisor()
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce(private.auth_role() = 'supervisor', false)
$$;

create or replace function private.is_coordinator_or_supervisor()
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce(private.auth_role() in ('coordinator', 'supervisor'), false)
$$;

-- Expedientes -----------------------------------------------------------------
create or replace function private.can_read_deal(p_deal_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.deals d
    where d.id = p_deal_id
      and (
        private.is_supervisor()
        or (d.deleted_at is null and (private.auth_role() = 'coordinator' or d.agent_id = private.current_user_id()))
      )
  )
$$;

create or replace function private.can_manage_deal(p_deal_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.deals d
    where d.id = p_deal_id
      and (private.is_supervisor() or (d.deleted_at is null and d.agent_id = private.current_user_id()))
  )
$$;

create or replace function private.can_manage_deal_docs(p_deal_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select private.can_read_deal(p_deal_id)   -- agente titular, coordinador o supervisor
$$;

create or replace function private.can_access_deal_audio(p_deal_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select private.can_manage_deal(p_deal_id) -- audios: sólo agente titular y supervisor
$$;

-- Contactos -------------------------------------------------------------------
create or replace function private.agent_has_contact_via_deal(p_contact_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.deals d
    where d.deleted_at is null
      and d.agent_id = private.current_user_id()
      and (d.primary_contact_id = p_contact_id
           or exists (select 1 from public.deal_contacts dc where dc.deal_id = d.id and dc.contact_id = p_contact_id))
  )
$$;

create or replace function private.can_read_contact(p_contact_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.contacts c
    where c.id = p_contact_id
      and (
        private.is_supervisor()
        or (c.deleted_at is null and (
              private.auth_role() = 'coordinator'
              or c.owner_agent_id = private.current_user_id()
              or private.agent_has_contact_via_deal(c.id)))
      )
  )
$$;

create or replace function private.can_manage_contact(p_contact_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.contacts c
    where c.id = p_contact_id
      and (private.is_supervisor() or (c.deleted_at is null and c.owner_agent_id = private.current_user_id()))
  )
$$;

create or replace function private.can_read_contact_sensitive(p_contact_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select private.can_read_contact(p_contact_id)  -- titular, agente con expediente, coordinador, supervisor
$$;

create or replace function private.can_write_contact_sensitive(p_contact_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select private.can_manage_contact(p_contact_id) or private.is_coordinator_or_supervisor()
$$;

-- Inmuebles -------------------------------------------------------------------
create or replace function private.can_read_property(p_property_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.properties p
    where p.id = p_property_id
      and (
        private.is_supervisor()
        or (p.deleted_at is null and private.current_user_id() is not null and (
              private.auth_role() = 'coordinator'
              or p.owner_agent_id = private.current_user_id()
              or p.status in ('available', 'reserved')))   -- bolsa común de producto
      )
  )
$$;

create or replace function private.can_manage_property(p_property_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.properties p
    where p.id = p_property_id
      and (private.is_supervisor() or (p.deleted_at is null and p.owner_agent_id = private.current_user_id()))
  )
$$;

-- Valoraciones ----------------------------------------------------------------
create or replace function private.can_access_valuation(p_valuation_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.valuation_requests v
    where v.id = p_valuation_id
      and (private.is_supervisor()
           or v.requested_by = private.current_user_id()
           or private.can_manage_property(v.property_id))
  )
$$;

-- Demandas --------------------------------------------------------------------
create or replace function private.can_manage_demand(p_demand_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.demands d
    where d.id = p_demand_id
      and (private.is_supervisor() or (d.deleted_at is null and d.agent_id = private.current_user_id()))
  )
$$;

-- Audios -----------------------------------------------------------------------
-- Lectura: basta con tener acceso a CUALQUIERA de las entidades vinculadas.
create or replace function private.can_read_audio(p_deal_id uuid, p_property_id uuid, p_valuation_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select private.is_supervisor()
      or (p_deal_id      is not null and private.can_access_deal_audio(p_deal_id))
      or (p_property_id  is not null and private.can_manage_property(p_property_id))
      or (p_valuation_id is not null and private.can_access_valuation(p_valuation_id))
$$;

-- Escritura: hay que tener acceso a TODAS las entidades vinculadas (y al menos una).
create or replace function private.can_write_audio(p_deal_id uuid, p_property_id uuid, p_valuation_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select private.current_user_id() is not null
     and num_nonnulls(p_deal_id, p_property_id, p_valuation_id) >= 1
     and (p_deal_id      is null or private.can_access_deal_audio(p_deal_id))
     and (p_property_id  is null or private.can_manage_property(p_property_id))
     and (p_valuation_id is null or private.can_access_valuation(p_valuation_id))
$$;

-- ¿La ruta física corresponde a alguna de las entidades vinculadas? (prefijo original)
create or replace function private.audio_path_matches(p_path text, p_deal_id uuid, p_property_id uuid, p_valuation_id uuid)
returns boolean language sql immutable set search_path = '' as $$
  select coalesce(
       (p_deal_id      is not null and p_path like 'deal/'      || p_deal_id      || '/%')
    or (p_property_id  is not null and p_path like 'property/'  || p_property_id  || '/%')
    or (p_valuation_id is not null and p_path like 'valuation/' || p_valuation_id || '/%'), false)
$$;

-- Ruta de Storage del bucket audio-recordings: {deal|property|valuation}/{uuid}/{archivo}
create or replace function private.can_access_audio_path(p_name text)
returns boolean language sql stable security definer set search_path = '' as $$
  select case (storage.foldername(p_name))[1]
           when 'deal'      then private.can_write_audio(private.try_uuid((storage.foldername(p_name))[2]), null, null)
           when 'property'  then private.can_write_audio(null, private.try_uuid((storage.foldername(p_name))[2]), null)
           when 'valuation' then private.can_write_audio(null, null, private.try_uuid((storage.foldername(p_name))[2]))
           else false
         end
$$;

-- Lectura de un objeto de Storage resolviendo su fila en documents/audio_recordings.
-- Permite leer un archivo que sigue en su ruta original (valuation/… o property/…)
-- cuando el usuario accede por el expediente al que se vinculó después.
create or replace function private.can_read_document_object(p_bucket text, p_name text)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1
    from public.documents d
    left join public.audio_recordings a on a.document_id = d.id
    where d.bucket_id = p_bucket and d.object_path = p_name
      and (
        private.is_supervisor()
        or (d.deleted_at is null and private.current_user_id() is not null and (
              case when d.bucket_id = 'audio-recordings' then
                     private.can_read_audio(d.deal_id, d.property_id, d.valuation_request_id)
                     or (a.id is not null and private.can_read_audio(a.deal_id, a.property_id, a.valuation_request_id))
                   else
                     d.uploaded_by = private.current_user_id()
                     or private.is_coordinator_or_supervisor()
                     or (d.deal_id is not null and private.can_manage_deal(d.deal_id))
                     or (d.contact_id is not null and private.can_manage_contact(d.contact_id))
                     or (d.property_id is not null and private.can_manage_property(d.property_id))
                     or (d.valuation_request_id is not null and private.can_access_valuation(d.valuation_request_id))
              end))
      )
  )
$$;

-- =============================================================================
-- 15. TRIGGERS DE NEGOCIO
-- =============================================================================

-- 15.1 updated_at en todas las tablas que lo tienen ---------------------------
do $$
declare r record;
begin
  for r in
    select c.table_name from information_schema.columns c
    join information_schema.tables t on t.table_schema = c.table_schema and t.table_name = c.table_name
    where c.table_schema = 'public' and c.column_name = 'updated_at' and t.table_type = 'BASE TABLE'
  loop
    execute format('create trigger set_updated_at before update on public.%I
                    for each row execute function private.set_updated_at()', r.table_name);
  end loop;
end $$;

-- 15.2 Alta automática de perfil al registrarse en Auth (inactivo, rol agent) --
create or replace function private.handle_new_user()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (id, full_name, email, role, is_active)
  values (new.id,
          coalesce(new.raw_user_meta_data ->> 'full_name', split_part(coalesce(new.email, ''), '@', 1), 'Usuario'),
          coalesce(new.email, ''),
          'agent',     -- NUNCA se toma el rol de user_metadata
          false)       -- el supervisor activa la cuenta
  on conflict (id) do nothing;
  return new;
end $$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function private.handle_new_user();

-- 15.3 Sólo el supervisor cambia rol / activación ----------------------------
create or replace function private.guard_profile_privileges()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if (new.role, new.is_active, new.id) is distinct from (old.role, old.is_active, old.id)
     and (select auth.uid()) is not null
     and not private.is_supervisor() then
    raise exception 'Sólo el supervisor puede cambiar rol o estado de un usuario' using errcode = '42501';
  end if;
  return new;
end $$;

create trigger guard_profile_privileges before update on public.profiles
  for each row execute function private.guard_profile_privileges();

-- 15.4 Máquina de estados del pipeline ----------------------------------------
create or replace function private.guard_deal()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_uid     uuid := (select auth.uid());
  v_role    public.app_role := private.auth_role();
  v_from    int;
  v_to      int;
  v_pending int;
  v_reason  text := nullif(current_setting('app.phase_change_reason', true), '');
begin
  if tg_op = 'INSERT' then
    if new.phase not in ('circulo_influencia', 'prospecto')
       and v_uid is not null and v_role is distinct from 'supervisor' then
      raise exception 'Un expediente nuevo sólo puede empezar en circulo_influencia o prospecto (recibido: %)', new.phase
        using errcode = 'P0001';
    end if;
    new.phase_changed_at := now();
    return new;
  end if;

  -- Cambios de estado (status)
  if new.status is distinct from old.status then
    if old.status in ('won', 'lost') and v_uid is not null and v_role is distinct from 'supervisor' then
      raise exception 'Sólo el supervisor puede reabrir un expediente cerrado' using errcode = '42501';
    end if;
    if new.status in ('won', 'lost') then
      new.closed_at := now();
    else
      new.closed_at := null;
    end if;
  end if;

  -- Cambios de fase
  if new.phase is distinct from old.phase then
    if old.status <> 'open' then
      raise exception 'No se puede cambiar la fase de un expediente en estado %', old.status using errcode = 'P0001';
    end if;
    v_from := private.phase_index(old.phase);
    v_to   := private.phase_index(new.phase);

    if v_to = v_from + 1 then
      -- Puerta de calidad: checklists obligatorios de la fase actual aprobados
      select count(*) into v_pending
      from public.deal_checklist_items i
      join public.deal_checklists c on c.id = i.deal_checklist_id
      where c.deal_id = new.id and c.phase = old.phase
        and i.is_required and i.status not in ('approved', 'not_applicable');
      if v_pending > 0 then
        raise exception 'Hay % punto(s) obligatorios del checklist de la fase % sin aprobar por coordinación', v_pending, old.phase
          using errcode = 'P0001';
      end if;
    elsif v_to < v_from then
      if v_uid is not null and v_role is distinct from 'supervisor' then
        raise exception 'Sólo el supervisor puede retroceder un expediente de fase' using errcode = '42501';
      end if;
      if v_reason is null then
        raise exception 'Retroceder de fase exige un motivo (usa public.change_deal_phase)' using errcode = 'P0001';
      end if;
    else
      raise exception 'Transición no permitida: % -> %. Las fases avanzan de una en una', old.phase, new.phase
        using errcode = 'P0001';
    end if;
    new.phase_changed_at := now();
  end if;
  return new;
end $$;

create trigger guard_deal before insert or update on public.deals
  for each row execute function private.guard_deal();

create or replace function private.instantiate_checklists(p_deal_id uuid, p_phase public.pipeline_phase)
returns void language plpgsql security definer set search_path = '' as $$
begin
  insert into public.deal_checklists (deal_id, template_id, phase)
  select d.id, t.id, t.phase
  from public.deals d
  join public.checklist_templates t
    on t.is_active and t.phase = p_phase
   and (t.operation_type is null or t.operation_type = d.operation_type)
  where d.id = p_deal_id
  on conflict (deal_id, template_id) do nothing;

  insert into public.deal_checklist_items
    (deal_checklist_id, template_item_id, position, title, is_required, requires_document, due_at)
  select c.id, ti.id, ti.position, ti.title, ti.is_required, ti.requires_document,
         case when ti.due_days is not null then now() + make_interval(days => ti.due_days) end
  from public.deal_checklists c
  join public.checklist_template_items ti on ti.template_id = c.template_id
  where c.deal_id = p_deal_id and c.phase = p_phase
    and not exists (select 1 from public.deal_checklist_items x
                    where x.deal_checklist_id = c.id and x.template_item_id = ti.id);
end $$;

create or replace function private.log_deal_phase()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'INSERT' or new.phase is distinct from old.phase then
    insert into public.deal_phase_history (deal_id, from_phase, to_phase, changed_by, reason, is_rollback)
    values (new.id,
            case when tg_op = 'UPDATE' then old.phase end,
            new.phase,
            (select auth.uid()),
            nullif(current_setting('app.phase_change_reason', true), ''),
            tg_op = 'UPDATE' and new.phase < old.phase);
    perform private.instantiate_checklists(new.id, new.phase);
  end if;
  return null;
end $$;

create trigger log_deal_phase after insert or update of phase on public.deals
  for each row execute function private.log_deal_phase();

-- 15.5 Revisión de checklists/documentos: sólo coordinador o supervisor -------
create or replace function private.guard_review()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := (select auth.uid());
  v_reviewer boolean := v_uid is null or private.is_coordinator_or_supervisor();
  v_old text;
  v_new text;
begin
  if tg_table_name = 'documents' then
    v_old := old.review_status::text; v_new := new.review_status::text;
  else
    v_old := old.status::text; v_new := new.status::text;
  end if;

  if v_new is distinct from v_old then
    if (v_new in ('approved', 'rejected', 'not_applicable') or v_old in ('approved', 'rejected', 'not_applicable'))
       and not v_reviewer then
      raise exception 'Sólo coordinación o supervisión puede aprobar/rechazar (o reabrir) puntos revisados' using errcode = '42501';
    end if;
    if v_new in ('approved', 'rejected', 'not_applicable') then
      new.reviewed_by := v_uid;
      new.reviewed_at := now();
    end if;
  end if;

  if tg_table_name = 'deal_checklist_items' then
    if (new.is_required, new.title, new.deal_checklist_id) is distinct from (old.is_required, old.title, old.deal_checklist_id)
       and not v_reviewer then
      raise exception 'El agente no puede modificar la definición de un punto de checklist' using errcode = '42501';
    end if;
    if new.status = 'submitted' and old.status is distinct from 'submitted' then
      new.completed_by := v_uid;
      new.completed_at := now();
    end if;
  elsif tg_table_name = 'deal_checklists' then
    if new.status = 'submitted' and old.status is distinct from 'submitted' then
      new.submitted_at := now();
    end if;
  end if;
  return new;
end $$;

create trigger guard_review before update on public.deal_checklist_items
  for each row execute function private.guard_review();
create trigger guard_review before update on public.deal_checklists
  for each row execute function private.guard_review();
create trigger guard_review before update on public.documents
  for each row execute function private.guard_review();

-- 15.6 Inmuebles: sello de publicación (manual, vía Inmovilla) ----------------
alter table public.properties
  add constraint properties_published_needs_ref_chk
  check (publication_status <> 'published_via_inmovilla' or inmovilla_ref is not null);

create or replace function private.stamp_publication_status()
returns trigger language plpgsql set search_path = '' as $$
begin
  if tg_op = 'INSERT' or new.publication_status is distinct from old.publication_status then
    new.publication_status_at := now();
  end if;
  return new;
end $$;

create trigger stamp_publication_status before insert or update on public.properties
  for each row execute function private.stamp_publication_status();

-- 15.7 Seguimiento: última interacción del contacto ---------------------------
create or replace function private.touch_contact_last_interaction()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  update public.contacts
     set last_interaction_at = greatest(coalesce(last_interaction_at, '-infinity'::timestamptz), new.occurred_at)
   where id = new.contact_id;
  return null;
end $$;

create trigger touch_contact_last_interaction after insert on public.interactions
  for each row execute function private.touch_contact_last_interaction();

-- 15.8 Valorador: parámetros versionados e inmutables -------------------------
create or replace function private.guard_valuation_parameters()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'INSERT' then
    new.created_by := coalesce((select auth.uid()), new.created_by);
    if new.version is null then
      select coalesce(max(version), 0) + 1 into new.version from public.valuation_parameters;
    end if;
    if new.is_active then new.activated_at := now(); end if;
    return new;
  end if;
  if (new.params, new.version, new.created_by, new.created_at)
     is distinct from (old.params, old.version, old.created_by, old.created_at) then
    raise exception 'Los parámetros de valoración son inmutables: crea una nueva versión' using errcode = 'P0001';
  end if;
  if new.is_active and not old.is_active then
    new.activated_at := now();
  end if;
  return new;
end $$;

create trigger guard_valuation_parameters before insert or update on public.valuation_parameters
  for each row execute function private.guard_valuation_parameters();

-- 15.9 Valorador: solicitud fija versión de parámetros + snapshot minimizado --
create or replace function private.prepare_valuation_request()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  new.requested_by := coalesce(new.requested_by, (select auth.uid()));
  if new.parameters_id is null then
    select id into new.parameters_id from public.valuation_parameters where is_active;
  end if;
  if new.input_snapshot is null then
    -- Minimización RGPD: al modelo no viajan dirección exacta, catastro ni geoposición precisa
    select to_jsonb(p) - array['street', 'street_number', 'floor_label', 'door', 'cadastral_reference',
                               'latitude', 'longitude', 'owner_agent_id', 'inmovilla_ref', 'deleted_at']
      into new.input_snapshot
    from public.properties p where p.id = new.property_id;
  end if;
  return new;
end $$;

create trigger prepare_valuation_request before insert on public.valuation_requests
  for each row execute function private.prepare_valuation_request();

-- 15.10 Valorador: ejecuciones IA (inmutables) actualizan el estado -----------
create or replace function private.prepare_ai_run()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  new.created_by := coalesce(new.created_by, (select auth.uid()));
  if new.parameters_id is null then
    select parameters_id into new.parameters_id from public.valuation_requests where id = new.valuation_id;
  end if;
  return new;
end $$;

create trigger prepare_ai_run before insert on public.valuation_ai_runs
  for each row execute function private.prepare_ai_run();

create or replace function private.after_ai_run()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  update public.valuation_requests
     set status = case when new.success then 'ai_completed'::public.valuation_status else 'failed'::public.valuation_status end,
         error_message = case when new.success then null else new.error_message end
   where id = new.valuation_id;
  return null;
end $$;

create trigger after_ai_run after insert on public.valuation_ai_runs
  for each row execute function private.after_ai_run();

-- 15.11 Valorador: ajuste humano con umbral de aprobación del supervisor ------
create or replace function private.guard_valuation_review()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := (select auth.uid());
  v_sup boolean := private.is_supervisor();
  v_threshold numeric;
begin
  if tg_op = 'INSERT' then
    select r.estimated_value into new.ai_value
    from public.valuation_ai_runs r
    where r.id = new.ai_run_id and r.valuation_id = new.valuation_id and r.success;
    if new.ai_value is null then
      raise exception 'La revisión debe referirse a una ejecución IA correcta de esta valoración' using errcode = 'P0001';
    end if;
    new.reviewed_by := coalesce(v_uid, new.reviewed_by);
    select coalesce((vp.params ->> 'max_agent_adjustment_pct')::numeric, 10) into v_threshold
    from public.valuation_requests vr
    left join public.valuation_parameters vp on vp.id = vr.parameters_id
    where vr.id = new.valuation_id;
    if v_sup or v_uid is null then
      new.requires_supervisor := false;
      new.approved_by := v_uid;
      new.approved_at := now();
    else
      new.requires_supervisor := abs(new.adjusted_value - new.ai_value) / new.ai_value * 100 > coalesce(v_threshold, 10);
      new.approved_by := null;
      new.approved_at := null;
    end if;
  else
    if (new.adjusted_value, new.ai_value, new.ai_run_id, new.valuation_id, new.reviewed_by, new.requires_supervisor)
       is distinct from (old.adjusted_value, old.ai_value, old.ai_run_id, old.valuation_id, old.reviewed_by, old.requires_supervisor) then
      raise exception 'Una revisión es inmutable: registra una nueva revisión' using errcode = 'P0001';
    end if;
    if new.approved_by is distinct from old.approved_by then
      if v_uid is not null and not v_sup then
        raise exception 'Sólo el supervisor puede aprobar ajustes de valoración' using errcode = '42501';
      end if;
      new.approved_at := case when new.approved_by is null then null else now() end;
    end if;
  end if;

  if new.is_final and new.requires_supervisor and new.approved_by is null then
    raise exception 'El ajuste supera el umbral permitido: requiere aprobación del supervisor' using errcode = 'P0001';
  end if;
  return new;
end $$;

create trigger guard_valuation_review before insert or update on public.valuation_reviews
  for each row execute function private.guard_valuation_review();

create or replace function private.after_valuation_review()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  update public.valuation_requests
     set status = case
                    when new.is_final then 'approved'::public.valuation_status
                    when new.requires_supervisor and new.approved_by is null then 'pending_supervisor'::public.valuation_status
                    else 'in_review'::public.valuation_status
                  end
   where id = new.valuation_id
     and status not in ('delivered', 'cancelled');
  return null;
end $$;

create trigger after_valuation_review after insert or update on public.valuation_reviews
  for each row execute function private.after_valuation_review();

-- 15.11b Bloqueo duro: no hay informe al cliente sin validación humana completa
create or replace function private.guard_valuation_client_report()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  r record;
  v_threshold numeric;
  v_over boolean;
begin
  select rv.valuation_id, rv.is_final, rv.requires_supervisor, rv.approved_by, rv.ai_value, rv.adjusted_value,
         vp.params
    into r
  from public.valuation_reviews rv
  join public.valuation_requests vq on vq.id = rv.valuation_id
  left join public.valuation_parameters vp on vp.id = vq.parameters_id
  where rv.id = new.review_id;

  if not found then
    raise exception 'Informe bloqueado: la revisión % no existe', new.review_id using errcode = 'P0001';
  end if;
  if r.valuation_id is distinct from new.valuation_id then
    raise exception 'Informe bloqueado: la revisión % no pertenece a la valoración %', new.review_id, new.valuation_id
      using errcode = 'P0001';
  end if;
  if not r.is_final then
    raise exception 'Informe bloqueado: la revisión humana no está marcada como final (is_final)' using errcode = 'P0001';
  end if;
  -- Se recalcula el umbral (defensa en profundidad, no sólo el flag requires_supervisor)
  v_threshold := coalesce((r.params ->> 'max_agent_adjustment_pct')::numeric, 10);
  v_over := r.requires_supervisor
            or (r.ai_value > 0 and abs(r.adjusted_value - r.ai_value) / r.ai_value * 100 > v_threshold);
  if v_over and r.approved_by is null then
    raise exception 'Informe bloqueado: el ajuste supera el umbral del % %% y no está aprobado por el supervisor', v_threshold
      using errcode = 'P0001';
  end if;
  return new;
end $$;

create trigger guard_valuation_client_report
  before insert or update of valuation_id, review_id, display_value, display_min, display_max,
                             client_summary, public_comparables, report_document_id, delivered_at
  on public.valuation_client_reports
  for each row execute function private.guard_valuation_client_report();

-- Una revisión que respalda un informe ya generado no puede perder is_final ni la aprobación
create or replace function private.protect_reported_review()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if ((old.is_final and not new.is_final) or (old.approved_by is not null and new.approved_by is null))
     and exists (select 1 from public.valuation_client_reports c where c.review_id = old.id) then
    raise exception 'La revisión respalda un informe al cliente: no se puede desvalidar' using errcode = 'P0001';
  end if;
  return new;
end $$;

create trigger protect_reported_review before update on public.valuation_reviews
  for each row execute function private.protect_reported_review();

-- 15.11c Audios: el archivo debe estar en audio-recordings bajo una entidad vinculada
create or replace function private.guard_audio_recording()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_bucket text; v_path text;
begin
  if num_nonnulls(new.deal_id, new.property_id, new.valuation_request_id) = 0 then
    return new;  -- lo rechaza el CHECK audio_owner_chk con un mensaje explícito
  end if;
  if tg_op = 'UPDATE' and new.document_id is distinct from old.document_id then
    raise exception 'El archivo de un audio no se puede sustituir: registra un audio nuevo' using errcode = 'P0001';
  end if;
  select d.bucket_id, d.object_path into v_bucket, v_path from public.documents d where d.id = new.document_id;
  if v_bucket is distinct from 'audio-recordings' then
    raise exception 'El documento de un audio debe estar en el bucket audio-recordings' using errcode = 'P0001';
  end if;
  -- El archivo NO se mueve al vincular un expediente: el prefijo original (valuation/ o
  -- property/) debe seguir correspondiendo a uno de los vínculos.
  if not private.audio_path_matches(v_path, new.deal_id, new.property_id, new.valuation_request_id) then
    raise exception 'La ruta del audio (%) no corresponde a ninguna entidad vinculada (no se puede desvincular la entidad original)', v_path
      using errcode = 'P0001';
  end if;
  return new;
end $$;

create trigger guard_audio_recording before insert or update of document_id, deal_id, property_id, valuation_request_id
  on public.audio_recordings for each row execute function private.guard_audio_recording();

-- 15.11d Documentos: ruta física inmutable y vinculación posterior a un expediente
--   * bucket_id/object_path no cambian nunca (salvo supervisor/service_role).
--   * En audio-recordings el prefijo debe corresponder a uno de los vínculos.
--   * Poner deal_id después exige gestionar ese expediente Y tener acceso a la
--     entidad original (valoración/inmueble), o ser supervisor.
create or replace function private.guard_document_links()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := (select auth.uid());
  v_privileged boolean := v_uid is null or private.is_supervisor();
begin
  if tg_op = 'UPDATE' and (new.bucket_id, new.object_path) is distinct from (old.bucket_id, old.object_path)
     and not v_privileged then
    raise exception 'La ruta física de un documento es inmutable (el archivo no se mueve)' using errcode = '42501';
  end if;

  if new.bucket_id = 'audio-recordings'
     and num_nonnulls(new.deal_id, new.property_id, new.valuation_request_id) > 0
     and not private.audio_path_matches(new.object_path, new.deal_id, new.property_id, new.valuation_request_id) then
    raise exception 'La ruta del audio (%) no corresponde a ninguna entidad vinculada', new.object_path using errcode = 'P0001';
  end if;

  if tg_op = 'UPDATE' and new.deal_id is not null and new.deal_id is distinct from old.deal_id and not v_privileged then
    if new.bucket_id = 'audio-recordings' then
      if not private.can_write_audio(new.deal_id, new.property_id, new.valuation_request_id) then
        raise exception 'Para vincular el audio al expediente debes gestionar el expediente y la entidad original' using errcode = '42501';
      end if;
    elsif not (private.can_manage_deal_docs(new.deal_id)
               and (old.valuation_request_id is null or private.can_access_valuation(old.valuation_request_id))
               and (old.property_id is null or private.can_manage_property(old.property_id)
                    or private.is_coordinator_or_supervisor())) then
      raise exception 'Para vincular el documento al expediente debes gestionar el expediente y la entidad original' using errcode = '42501';
    end if;
  end if;
  return new;
end $$;

create trigger guard_document_links before insert or update on public.documents
  for each row execute function private.guard_document_links();

-- 15.12 Auditoría genérica ------------------------------------------------------
-- TG_ARGV[0] = 'keys_only' => sólo se registran los NOMBRES de columnas
-- modificadas (no se duplica PII en la auditoría; facilita el derecho de supresión).
create or replace function private.audit_row()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_old jsonb := case when tg_op <> 'INSERT' then to_jsonb(old) end;
  v_new jsonb := case when tg_op <> 'DELETE' then to_jsonb(new) end;
  v_any jsonb := coalesce(v_new, v_old);
  v_keys jsonb;
begin
  if tg_nargs > 0 and tg_argv[0] = 'keys_only' then
    select coalesce(jsonb_agg(k), '[]'::jsonb) into v_keys
    from (select key as k from jsonb_each(coalesce(v_new, v_old)) e
          where v_old is null or v_new is null or (v_old -> e.key) is distinct from (v_new -> e.key)) s;
    v_old := null;
    v_new := jsonb_build_object('changed_columns', v_keys);
  end if;
  insert into public.audit_log (table_name, record_id, action, actor_id, old_data, new_data)
  values (tg_table_name,
          coalesce(v_any ->> 'id', v_any ->> 'contact_id', v_any ->> 'property_id', v_any ->> 'valuation_id'),
          tg_op, (select auth.uid()), v_old, v_new);
  return null;
end $$;

create trigger audit_contact_sensitive after insert or update or delete on public.contact_sensitive
  for each row execute function private.audit_row('keys_only');
create trigger audit_property_internal after insert or update or delete on public.property_internal
  for each row execute function private.audit_row('keys_only');
create trigger audit_consent_records after insert or update or delete on public.consent_records
  for each row execute function private.audit_row();
create trigger audit_documents after insert or update or delete on public.documents
  for each row execute function private.audit_row();
create trigger audit_valuation_parameters after insert or update or delete on public.valuation_parameters
  for each row execute function private.audit_row();
create trigger audit_profiles after update or delete on public.profiles
  for each row execute function private.audit_row();
create trigger audit_gdpr_requests after insert or update or delete on public.gdpr_requests
  for each row execute function private.audit_row();
create trigger audit_valuation_reviews after insert or update on public.valuation_reviews
  for each row execute function private.audit_row();

-- =============================================================================
-- 16. CRUCE AUTOMÁTICO INMUEBLE ↔ DEMANDA  [F2]
--     Filtros duros: operación, tipología, disponibilidad, precio ≤ máx+tolerancia,
--     "imprescindibles" (ascensor, garaje...) cuando el inmueble los niega.
--     Puntuación 0-100: precio 35 · zona 30 · dormitorios/baños 15 · m² 10 · extras 10
-- =============================================================================
-- Zona y todos sus ancestros (barrio → distrito → municipio)
create or replace function private.zone_lineage(p_zone_id uuid)
returns uuid[] language sql stable set search_path = '' as $$
  with recursive up as (
    select z.id, z.parent_id, 1 as depth from public.zones z where z.id = p_zone_id
    union all
    select z.id, z.parent_id, up.depth + 1 from public.zones z join up on z.id = up.parent_id where up.depth < 10
  )
  select coalesce(array_agg(id), '{}') from up
$$;

create or replace function public.match_candidates(
  p_property_id     uuid    default null,
  p_demand_id       uuid    default null,
  p_price_tolerance numeric default 0.10
)
returns table (property_id uuid, demand_id uuid, score numeric, breakdown jsonb)
language sql stable security invoker set search_path = '' as $$
  select p.id, d.id,
         round(s.price + s.zone + s.rooms + s.area + s.features, 2) as score,
         jsonb_build_object(
           'price', round(s.price, 2), 'zone', s.zone, 'rooms', s.rooms,
           'area', s.area, 'features', round(s.features, 2),
           'weights', jsonb_build_object('price', 35, 'zone', 30, 'rooms', 15, 'area', 10, 'features', 10)
         ) as breakdown
  from public.demands d
  join public.properties p
    on p.operation_type = d.operation_type
   and p.status = 'available'
   and p.deleted_at is null
   and p.asking_price is not null
   and (cardinality(d.property_types) = 0 or p.property_type = any (d.property_types))
   and (d.price_max is null or p.asking_price <= d.price_max * (1 + p_price_tolerance))
   and not (d.needs_elevator     and p.has_elevator     is false)
   and not (d.needs_garage       and p.has_garage       is false)
   and not (d.needs_terrace      and p.has_terrace      is false)
   and not (d.needs_exterior     and p.is_exterior      is false)
   and not (d.needs_storage_room and p.has_storage_room is false)
   and not (d.needs_pool         and p.has_pool         is false)
   and not (d.needs_garden       and p.has_garden       is false)
  cross join lateral (
    select
      (case
         when d.price_min is not null and p.asking_price < d.price_min then 25
         when d.price_max is null or p.asking_price <= d.price_max then 35
         else greatest(0, 35 * (1 - (p.asking_price - d.price_max) / (d.price_max * p_price_tolerance)))
       end)::numeric as price,
      (case
         when not exists (select 1 from public.demand_zones dz where dz.demand_id = d.id) then 20
         when exists (select 1 from public.demand_zones dz
                      where dz.demand_id = d.id and dz.zone_id = any (private.zone_lineage(p.zone_id))) then 30
         when exists (select 1 from public.demand_zones dz
                      join public.zones zd on zd.id = dz.zone_id
                      join public.zones zp on zp.id = p.zone_id
                      where dz.demand_id = d.id and zd.parent_id is not null and zd.parent_id = zp.parent_id) then 12
         else 0
       end)::numeric as zone,
      (case
         when d.bedrooms_min is null then 10
         when p.bedrooms is null then 5
         when p.bedrooms >= d.bedrooms_min then 10
         when p.bedrooms = d.bedrooms_min - 1 then 4
         else 0
       end
       + case
         when d.bathrooms_min is null then 5
         when p.bathrooms is null then 2
         when p.bathrooms >= d.bathrooms_min then 5
         else 0
       end)::numeric as rooms,
      (case
         when d.area_min_m2 is null and d.area_max_m2 is null then 10
         when p.built_area_m2 is null then 5
         when (d.area_min_m2 is null or p.built_area_m2 >= d.area_min_m2)
          and (d.area_max_m2 is null or p.built_area_m2 <= d.area_max_m2) then 10
         when (d.area_min_m2 is null or p.built_area_m2 >= d.area_min_m2 * 0.9)
          and (d.area_max_m2 is null or p.built_area_m2 <= d.area_max_m2 * 1.1) then 5
         else 0
       end)::numeric as area,
      (case
         when cardinality(d.desired_features) = 0 then 10
         else 10.0 * (select count(*) from unnest(d.desired_features) f where f = any (p.features))
                   / cardinality(d.desired_features)
       end)::numeric as features
  ) s
  where d.status = 'active'
    and d.deleted_at is null
    and (p_property_id is null or p.id = p_property_id)
    and (p_demand_id  is null or d.id = p_demand_id)
$$;
comment on function public.match_candidates(uuid, uuid, numeric) is
  '[F2] Cruce automático. SECURITY INVOKER: respeta RLS del usuario que la llama.';

create or replace function public.match_properties_for_demand(p_demand_id uuid, p_min_score numeric default 50, p_limit int default 50)
returns table (property_id uuid, reference text, asking_price numeric, score numeric, breakdown jsonb)
language sql stable security invoker set search_path = '' as $$
  select m.property_id, p.reference, p.asking_price, m.score, m.breakdown
  from public.match_candidates(null, p_demand_id) m
  join public.properties p on p.id = m.property_id
  where m.score >= p_min_score
  order by m.score desc, p.asking_price
  limit p_limit
$$;

create or replace function public.match_demands_for_property(p_property_id uuid, p_min_score numeric default 50, p_limit int default 50)
returns table (demand_id uuid, contact_id uuid, agent_id uuid, score numeric, breakdown jsonb)
language sql stable security invoker set search_path = '' as $$
  select m.demand_id, d.contact_id, d.agent_id, m.score, m.breakdown
  from public.match_candidates(p_property_id, null) m
  join public.demands d on d.id = m.demand_id
  where m.score >= p_min_score
  order by m.score desc
  limit p_limit
$$;

-- Persistencia del cruce (corre con privilegios para ver TODA la cartera y
-- TODAS las demandas; el resultado se filtra después por RLS en la tabla).
create or replace function private.refresh_matches(p_property_id uuid default null, p_demand_id uuid default null, p_min_score numeric default 40)
returns integer language plpgsql security definer set search_path = '' as $$
declare v_count integer;
begin
  with up as (
    insert into public.property_demand_matches (property_id, demand_id, score, score_breakdown, computed_at)
    select c.property_id, c.demand_id, c.score, c.breakdown, now()
    from public.match_candidates(p_property_id, p_demand_id) c
    where c.score >= p_min_score
    on conflict (property_id, demand_id) do update
      set score = excluded.score, score_breakdown = excluded.score_breakdown, computed_at = excluded.computed_at
    returning 1
  )
  select count(*) into v_count from up;

  -- Sugerencias que ya no cumplen (las gestionadas por el agente se conservan)
  delete from public.property_demand_matches m
  where m.status = 'suggested'
    and m.computed_at < now()
    and (p_property_id is null or m.property_id = p_property_id)
    and (p_demand_id  is null or m.demand_id  = p_demand_id);

  if p_demand_id is not null then
    update public.demands set last_matched_at = now() where id = p_demand_id;
  end if;
  return v_count;
end $$;

create or replace function public.refresh_matches(p_property_id uuid default null, p_demand_id uuid default null)
returns integer language plpgsql security invoker set search_path = '' as $$
begin
  if p_property_id is null and p_demand_id is null and not private.is_supervisor() then
    raise exception 'El recálculo global sólo lo lanza el supervisor (o un cron con service_role)' using errcode = '42501';
  end if;
  if p_property_id is not null and not private.can_read_property(p_property_id) then
    raise exception 'Sin acceso al inmueble' using errcode = '42501';
  end if;
  if p_demand_id is not null and not private.can_manage_demand(p_demand_id) then
    raise exception 'Sin acceso a la demanda' using errcode = '42501';
  end if;
  return private.refresh_matches(p_property_id, p_demand_id);
end $$;

create or replace function private.trg_refresh_matches()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if tg_table_name = 'properties' then
    perform private.refresh_matches(new.id, null);
  elsif tg_table_name = 'demands' then
    perform private.refresh_matches(null, new.id);
  elsif tg_table_name = 'demand_zones' then
    perform private.refresh_matches(null, coalesce(new.demand_id, old.demand_id));
  end if;
  return null;
end $$;

create trigger refresh_matches_property
  after insert or update of status, operation_type, property_type, asking_price, zone_id, bedrooms, bathrooms,
                            built_area_m2, features, has_elevator, has_garage, has_terrace, is_exterior,
                            has_storage_room, has_pool, has_garden, deleted_at
  on public.properties for each row execute function private.trg_refresh_matches();
create trigger refresh_matches_demand
  after insert or update of status, operation_type, property_types, price_min, price_max, bedrooms_min, bathrooms_min,
                            area_min_m2, area_max_m2, needs_elevator, needs_garage, needs_terrace, needs_exterior,
                            needs_storage_room, needs_pool, needs_garden, desired_features, deleted_at
  on public.demands for each row execute function private.trg_refresh_matches();
create trigger refresh_matches_demand_zones
  after insert or delete on public.demand_zones
  for each row execute function private.trg_refresh_matches();

-- =============================================================================
-- 17. RPCs DE NEGOCIO (SECURITY INVOKER: respetan RLS)
-- =============================================================================
create or replace function public.change_deal_phase(p_deal_id uuid, p_to public.pipeline_phase, p_reason text default null)
returns public.deals language plpgsql security invoker set search_path = '' as $$
declare v_deal public.deals;
begin
  perform set_config('app.phase_change_reason', coalesce(p_reason, ''), true);
  update public.deals set phase = p_to where id = p_deal_id returning * into v_deal;
  perform set_config('app.phase_change_reason', '', true);
  if v_deal.id is null then
    raise exception 'Expediente no encontrado o sin permisos' using errcode = '42501';
  end if;
  return v_deal;
end $$;
comment on function public.change_deal_phase(uuid, public.pipeline_phase, text) is
  'Avanza (o, sólo supervisor y con motivo, retrocede) la fase de un expediente.';

-- Vincula un audio (y su documento) a un expediente abierto después de una valoración
-- rápida. El archivo físico NO se mueve: conserva su ruta valuation/… o property/….
create or replace function public.link_audio_to_deal(p_audio_id uuid, p_deal_id uuid)
returns void language plpgsql security invoker set search_path = '' as $$
declare v_doc uuid;
begin
  update public.audio_recordings set deal_id = p_deal_id where id = p_audio_id returning document_id into v_doc;
  if v_doc is null then
    raise exception 'Audio no encontrado o sin permisos' using errcode = '42501';
  end if;
  update public.documents set deal_id = p_deal_id where id = v_doc;
  if not found then
    raise exception 'Documento del audio no accesible' using errcode = '42501';
  end if;
end $$;
comment on function public.link_audio_to_deal(uuid, uuid) is
  'Vincula audio + documento a un expediente sin mover el archivo. Exige gestionar el expediente y la entidad original (o ser supervisor).';

create or replace function public.activate_valuation_parameters(p_parameters_id uuid)
returns void language plpgsql security invoker set search_path = '' as $$
begin
  if not private.is_supervisor() then
    raise exception 'Sólo el supervisor puede activar parámetros de valoración' using errcode = '42501';
  end if;
  update public.valuation_parameters set is_active = false where is_active and id <> p_parameters_id;
  update public.valuation_parameters set is_active = true where id = p_parameters_id;
  if not found then
    raise exception 'Versión de parámetros inexistente' using errcode = 'P0002';
  end if;
end $$;

-- RGPD: anonimización (derecho de supresión) -----------------------------------
create or replace function public.anonymize_contact(p_contact_id uuid, p_reason text)
returns void language plpgsql security invoker set search_path = '' as $$
begin
  if not private.is_supervisor() then
    raise exception 'Sólo el supervisor puede anonimizar contactos' using errcode = '42501';
  end if;
  update public.contacts
     set first_name = null, last_name = null, company_name = null,
         email = null, phone = null, phone_secondary = null,
         relationship_note = null, tags = '{}', referred_by_contact_id = null,
         anonymized_at = now()
   where id = p_contact_id;
  if not found then
    raise exception 'Contacto inexistente' using errcode = 'P0002';
  end if;
  delete from public.contact_sensitive where contact_id = p_contact_id;
  update public.interactions set summary = '[anonimizado]', outcome = null where contact_id = p_contact_id;
  -- Los archivos se marcan para purga física vía Storage API (job con service_role),
  -- salvo los sujetos a conservación legal (retention_until futura, p.ej. PBC 10 años).
  update public.documents
     set purge_requested_at = now()
   where contact_id = p_contact_id
     and (retention_until is null or retention_until <= current_date);
  update public.gdpr_requests
     set status = 'completed', resolved_at = now(), resolution = coalesce(p_reason, 'Anonimización'),
         handled_by = (select auth.uid())
   where contact_id = p_contact_id and request_type = 'erasure' and status in ('received', 'in_progress');
end $$;

-- =============================================================================
-- 18. VISTAS (security_invoker => respetan RLS)
-- =============================================================================
create view public.v_pipeline_summary with (security_invoker = true) as
select d.agent_id, d.phase,
       count(*) filter (where d.status = 'open')            as open_deals,
       coalesce(sum(d.expected_fee) filter (where d.status = 'open'), 0) as expected_fees,
       min(d.phase_changed_at) filter (where d.status = 'open') as oldest_in_phase_since
from public.deals d
where d.deleted_at is null
group by d.agent_id, d.phase;
comment on view public.v_pipeline_summary is '[F1] Tablero de pipeline por agente y fase.';

create view public.v_review_queue with (security_invoker = true) as
select c.id as deal_checklist_id, c.deal_id, d.code as deal_code, d.agent_id, c.phase, c.status,
       count(i.*) filter (where i.status = 'submitted') as items_submitted,
       count(i.*) filter (where i.is_required and i.status not in ('approved', 'not_applicable')) as required_pending
from public.deal_checklists c
join public.deals d on d.id = c.deal_id
left join public.deal_checklist_items i on i.deal_checklist_id = c.id
group by c.id, d.code, d.agent_id;
comment on view public.v_review_queue is '[F2] Cola de revisión del coordinador.';

create view public.v_gdpr_retention_due with (security_invoker = true) as
select 'contact'::text as kind, c.id, c.retention_until
from public.contacts c
where c.retention_until <= current_date and c.anonymized_at is null
union all
select 'document', d.id, d.retention_until
from public.documents d
where d.retention_until <= current_date and d.purge_requested_at is null;
comment on view public.v_gdpr_retention_due is '[F1] Registros cuyo plazo de conservación ha vencido (job RGPD).';

-- =============================================================================
-- 19. ROW LEVEL SECURITY
--     Convención: (select private.fn()) para cachear por sentencia.
--     uid_activo = (select private.current_user_id())
-- =============================================================================
do $$
declare r record;
begin
  for r in select tablename from pg_tables where schemaname = 'public' loop
    execute format('alter table public.%I enable row level security', r.tablename);
  end loop;
end $$;

-- profiles ---------------------------------------------------------------------
create policy profiles_select on public.profiles for select to authenticated
  using (id = (select auth.uid()) or (select private.current_user_id()) is not null);
create policy profiles_update on public.profiles for update to authenticated
  using (id = (select private.current_user_id()) or (select private.is_supervisor()))
  with check (id = (select private.current_user_id()) or (select private.is_supervisor()));
-- INSERT: sólo vía trigger handle_new_user. DELETE: vía borrado en Auth (cascade).

-- zones ------------------------------------------------------------------------
create policy zones_select on public.zones for select to authenticated
  using ((select private.current_user_id()) is not null);
create policy zones_write on public.zones for all to authenticated
  using ((select private.is_supervisor())) with check ((select private.is_supervisor()));

-- contacts ---------------------------------------------------------------------
create policy contacts_select on public.contacts for select to authenticated
  using (
    (select private.is_supervisor())
    or (deleted_at is null and (
          owner_agent_id = (select private.current_user_id())
          or (select private.is_coordinator_or_supervisor())
          or private.agent_has_contact_via_deal(id)))
  );
create policy contacts_insert on public.contacts for insert to authenticated
  with check (owner_agent_id = (select private.current_user_id()) or (select private.is_supervisor()));
create policy contacts_update on public.contacts for update to authenticated
  using (owner_agent_id = (select private.current_user_id()) or (select private.is_supervisor()))
  with check (owner_agent_id = (select private.current_user_id()) or (select private.is_supervisor()));
create policy contacts_delete on public.contacts for delete to authenticated
  using ((select private.is_supervisor()));

-- contact_sensitive -------------------------------------------------------------
create policy contact_sensitive_select on public.contact_sensitive for select to authenticated
  using (private.can_read_contact_sensitive(contact_id));
create policy contact_sensitive_insert on public.contact_sensitive for insert to authenticated
  with check (private.can_write_contact_sensitive(contact_id));
create policy contact_sensitive_update on public.contact_sensitive for update to authenticated
  using (private.can_write_contact_sensitive(contact_id))
  with check (private.can_write_contact_sensitive(contact_id));
create policy contact_sensitive_delete on public.contact_sensitive for delete to authenticated
  using ((select private.is_supervisor()));

-- consent_records (append-only) -------------------------------------------------
create policy consent_select on public.consent_records for select to authenticated
  using (private.can_read_contact(contact_id));
create policy consent_insert on public.consent_records for insert to authenticated
  with check (private.can_read_contact(contact_id) and collected_by = (select private.current_user_id()));

-- gdpr_requests ------------------------------------------------------------------
create policy gdpr_select on public.gdpr_requests for select to authenticated
  using ((select private.is_supervisor()) or handled_by = (select private.current_user_id()));
create policy gdpr_insert on public.gdpr_requests for insert to authenticated
  with check ((select private.current_user_id()) is not null
              and (contact_id is null or private.can_read_contact(contact_id)));
create policy gdpr_update on public.gdpr_requests for update to authenticated
  using ((select private.is_supervisor())) with check ((select private.is_supervisor()));

-- properties --------------------------------------------------------------------
create policy properties_select on public.properties for select to authenticated
  using (
    (select private.is_supervisor())
    or (deleted_at is null and (select private.current_user_id()) is not null and (
          owner_agent_id = (select private.current_user_id())
          or (select private.is_coordinator_or_supervisor())
          or status in ('available', 'reserved')))
  );
create policy properties_insert on public.properties for insert to authenticated
  with check (owner_agent_id = (select private.current_user_id()) or (select private.is_supervisor()));
create policy properties_update on public.properties for update to authenticated
  using (owner_agent_id = (select private.current_user_id()) or (select private.is_supervisor()))
  with check (owner_agent_id = (select private.current_user_id()) or (select private.is_supervisor()));
create policy properties_delete on public.properties for delete to authenticated
  using ((select private.is_supervisor()));

-- property_internal (sólo agente titular + supervisor) ---------------------------
create policy property_internal_all on public.property_internal for all to authenticated
  using (private.can_manage_property(property_id))
  with check (private.can_manage_property(property_id));

-- property_owners -----------------------------------------------------------------
create policy property_owners_select on public.property_owners for select to authenticated
  using (private.can_manage_property(property_id) or (select private.is_coordinator_or_supervisor()));
create policy property_owners_write on public.property_owners for all to authenticated
  using (private.can_manage_property(property_id))
  with check (private.can_manage_property(property_id) and private.can_read_contact(contact_id));

-- property_public_profile (publicable) ---------------------------------------------
create policy ppp_select on public.property_public_profile for select to authenticated
  using (private.can_read_property(property_id));
create policy ppp_write on public.property_public_profile for all to authenticated
  using (private.can_manage_property(property_id))
  with check (private.can_manage_property(property_id));

-- deals ------------------------------------------------------------------------------
create policy deals_select on public.deals for select to authenticated
  using (
    (select private.is_supervisor())
    or (deleted_at is null and (agent_id = (select private.current_user_id())
                                or (select private.is_coordinator_or_supervisor())))
  );
create policy deals_insert on public.deals for insert to authenticated
  with check ((agent_id = (select private.current_user_id()) and private.can_read_contact(primary_contact_id))
              or (select private.is_supervisor()));
create policy deals_update on public.deals for update to authenticated
  using (agent_id = (select private.current_user_id()) or (select private.is_supervisor()))
  with check (agent_id = (select private.current_user_id()) or (select private.is_supervisor()));
create policy deals_delete on public.deals for delete to authenticated
  using ((select private.is_supervisor()));

-- deal_contacts ------------------------------------------------------------------------
create policy deal_contacts_select on public.deal_contacts for select to authenticated
  using (private.can_read_deal(deal_id));
create policy deal_contacts_write on public.deal_contacts for all to authenticated
  using (private.can_manage_deal(deal_id))
  with check (private.can_manage_deal(deal_id) and private.can_read_contact(contact_id));

-- deal_phase_history (sólo lectura; escribe el trigger) ---------------------------------
create policy deal_phase_history_select on public.deal_phase_history for select to authenticated
  using (private.can_read_deal(deal_id));

-- documents -----------------------------------------------------------------------------
create policy documents_select on public.documents for select to authenticated
  using (
    (select private.is_supervisor())
    or (deleted_at is null and (
          case when bucket_id = 'audio-recordings' then
                 -- audios: acceso por CUALQUIER entidad vinculada (doc o fila de audio); nunca coordinador
                 private.can_read_audio(deal_id, property_id, valuation_request_id)
                 or exists (select 1 from public.audio_recordings a where a.document_id = documents.id)
               else
                 uploaded_by = (select private.current_user_id())
                 or (select private.is_coordinator_or_supervisor())
                 or (deal_id is not null and private.can_manage_deal(deal_id))
                 or (contact_id is not null and private.can_manage_contact(contact_id))
                 or (property_id is not null and private.can_manage_property(property_id))
                 or (valuation_request_id is not null and private.can_access_valuation(valuation_request_id))
          end))
  );
create policy documents_insert on public.documents for insert to authenticated
  with check (
    uploaded_by = (select private.current_user_id())
    and (deal_id is null or private.can_manage_deal_docs(deal_id))
    and (contact_id is null or private.can_write_contact_sensitive(contact_id))
    and (property_id is null or private.can_manage_property(property_id)
         or (select private.is_coordinator_or_supervisor())
         or (valuation_request_id is not null and private.can_access_valuation(valuation_request_id)))
    and (valuation_request_id is null or private.can_access_valuation(valuation_request_id))
  );
create policy documents_update on public.documents for update to authenticated
  using (uploaded_by = (select private.current_user_id()) or (select private.is_coordinator_or_supervisor()))
  with check (uploaded_by = (select private.current_user_id()) or (select private.is_coordinator_or_supervisor()));
create policy documents_delete on public.documents for delete to authenticated
  using ((select private.is_supervisor()));

-- interactions ---------------------------------------------------------------------------
create policy interactions_select on public.interactions for select to authenticated
  using (agent_id = (select private.current_user_id()) or (select private.is_supervisor()));
create policy interactions_insert on public.interactions for insert to authenticated
  with check (agent_id = (select private.current_user_id()) and private.can_read_contact(contact_id));
create policy interactions_update on public.interactions for update to authenticated
  using (agent_id = (select private.current_user_id()) or (select private.is_supervisor()))
  with check (agent_id = (select private.current_user_id()) or (select private.is_supervisor()));
create policy interactions_delete on public.interactions for delete to authenticated
  using ((select private.is_supervisor()));

-- tasks -------------------------------------------------------------------------------------
create policy tasks_select on public.tasks for select to authenticated
  using (assigned_to = (select private.current_user_id()) or created_by = (select private.current_user_id())
         or (select private.is_supervisor()));
create policy tasks_insert on public.tasks for insert to authenticated
  with check (created_by = (select private.current_user_id())
              and (assigned_to = (select private.current_user_id()) or (select private.is_coordinator_or_supervisor())));
create policy tasks_update on public.tasks for update to authenticated
  using (assigned_to = (select private.current_user_id()) or created_by = (select private.current_user_id())
         or (select private.is_supervisor()))
  with check (assigned_to = (select private.current_user_id()) or created_by = (select private.current_user_id())
              or (select private.is_supervisor()));
create policy tasks_delete on public.tasks for delete to authenticated
  using (created_by = (select private.current_user_id()) or (select private.is_supervisor()));

-- audio_recordings / transcriptions (titular de expediente/inmueble/valoración + supervisor; nunca coordinador)
create policy audio_select on public.audio_recordings for select to authenticated
  using (private.can_read_audio(deal_id, property_id, valuation_request_id));
create policy audio_insert on public.audio_recordings for insert to authenticated
  with check (private.can_write_audio(deal_id, property_id, valuation_request_id)
              and recorded_by = (select private.current_user_id()));
create policy audio_update on public.audio_recordings for update to authenticated
  using (private.can_write_audio(deal_id, property_id, valuation_request_id))
  with check (private.can_write_audio(deal_id, property_id, valuation_request_id));
create policy audio_delete on public.audio_recordings for delete to authenticated
  using ((select private.is_supervisor()));

create policy transcriptions_select on public.transcriptions for select to authenticated
  using (exists (select 1 from public.audio_recordings a where a.id = audio_id));
create policy transcriptions_insert on public.transcriptions for insert to authenticated
  with check (exists (select 1 from public.audio_recordings a where a.id = audio_id));
create policy transcriptions_update on public.transcriptions for update to authenticated
  using (exists (select 1 from public.audio_recordings a where a.id = audio_id))
  with check (exists (select 1 from public.audio_recordings a where a.id = audio_id));

-- valuation_parameters / benchmarks (lectura todos; escritura supervisor) ----------------------
create policy vparams_select on public.valuation_parameters for select to authenticated
  using ((select private.current_user_id()) is not null);
create policy vparams_insert on public.valuation_parameters for insert to authenticated
  with check ((select private.is_supervisor()));
create policy vparams_update on public.valuation_parameters for update to authenticated
  using ((select private.is_supervisor())) with check ((select private.is_supervisor()));

create policy vzb_select on public.valuation_zone_benchmarks for select to authenticated
  using ((select private.current_user_id()) is not null);
create policy vzb_write on public.valuation_zone_benchmarks for all to authenticated
  using ((select private.is_supervisor())) with check ((select private.is_supervisor()));

-- valuation_requests --------------------------------------------------------------------------
create policy vreq_select on public.valuation_requests for select to authenticated
  using (requested_by = (select private.current_user_id()) or (select private.is_supervisor())
         or private.can_manage_property(property_id));
create policy vreq_insert on public.valuation_requests for insert to authenticated
  with check (requested_by = (select private.current_user_id()) and private.can_read_property(property_id)
              and (deal_id is null or private.can_manage_deal(deal_id)));
create policy vreq_update on public.valuation_requests for update to authenticated
  using (requested_by = (select private.current_user_id()) or (select private.is_supervisor()))
  with check (requested_by = (select private.current_user_id()) or (select private.is_supervisor()));
create policy vreq_delete on public.valuation_requests for delete to authenticated
  using ((select private.is_supervisor()));

-- valuation_comparables -----------------------------------------------------------------------
create policy vcomp_all on public.valuation_comparables for all to authenticated
  using (private.can_access_valuation(valuation_id))
  with check (private.can_access_valuation(valuation_id));

-- valuation_ai_runs (inmutables: sólo select + insert) ----------------------------------------
create policy vrun_select on public.valuation_ai_runs for select to authenticated
  using (private.can_access_valuation(valuation_id));
create policy vrun_insert on public.valuation_ai_runs for insert to authenticated
  with check (private.can_access_valuation(valuation_id));

-- valuation_reviews -----------------------------------------------------------------------------
create policy vrev_select on public.valuation_reviews for select to authenticated
  using (private.can_access_valuation(valuation_id));
create policy vrev_insert on public.valuation_reviews for insert to authenticated
  with check (private.can_access_valuation(valuation_id));
create policy vrev_update on public.valuation_reviews for update to authenticated
  using (private.can_access_valuation(valuation_id))
  with check (private.can_access_valuation(valuation_id));

-- valuation_client_reports ----------------------------------------------------------------------
create policy vcr_all on public.valuation_client_reports for all to authenticated
  using (private.can_access_valuation(valuation_id))
  with check (private.can_access_valuation(valuation_id));

-- demands / demand_zones ------------------------------------------------------------------------
create policy demands_select on public.demands for select to authenticated
  using ((select private.is_supervisor()) or (deleted_at is null and agent_id = (select private.current_user_id())));
create policy demands_insert on public.demands for insert to authenticated
  with check ((agent_id = (select private.current_user_id()) and private.can_read_contact(contact_id))
              or (select private.is_supervisor()));
create policy demands_update on public.demands for update to authenticated
  using (agent_id = (select private.current_user_id()) or (select private.is_supervisor()))
  with check (agent_id = (select private.current_user_id()) or (select private.is_supervisor()));
create policy demands_delete on public.demands for delete to authenticated
  using ((select private.is_supervisor()));

create policy demand_zones_all on public.demand_zones for all to authenticated
  using (private.can_manage_demand(demand_id)) with check (private.can_manage_demand(demand_id));

-- property_demand_matches (escribe el cruce; el agente gestiona estado/feedback) -----------------
create policy pdm_select on public.property_demand_matches for select to authenticated
  using (private.can_manage_property(property_id) or private.can_manage_demand(demand_id));
create policy pdm_update on public.property_demand_matches for update to authenticated
  using (private.can_manage_demand(demand_id) or private.can_manage_property(property_id))
  with check (private.can_manage_demand(demand_id) or private.can_manage_property(property_id));

-- visits ------------------------------------------------------------------------------------------
create policy visits_select on public.visits for select to authenticated
  using (agent_id = (select private.current_user_id()) or (select private.is_supervisor())
         or private.can_manage_property(property_id));
create policy visits_insert on public.visits for insert to authenticated
  with check (agent_id = (select private.current_user_id()) and private.can_read_property(property_id)
              and private.can_read_contact(visitor_contact_id));
create policy visits_update on public.visits for update to authenticated
  using (agent_id = (select private.current_user_id()) or (select private.is_supervisor())
         or private.can_manage_property(property_id))
  with check (agent_id = (select private.current_user_id()) or (select private.is_supervisor())
              or private.can_manage_property(property_id));
create policy visits_delete on public.visits for delete to authenticated
  using ((select private.is_supervisor()));

-- checklist templates ---------------------------------------------------------------------------------
create policy ct_select on public.checklist_templates for select to authenticated
  using ((select private.current_user_id()) is not null);
create policy ct_write on public.checklist_templates for all to authenticated
  using ((select private.is_coordinator_or_supervisor())) with check ((select private.is_coordinator_or_supervisor()));
create policy cti_select on public.checklist_template_items for select to authenticated
  using ((select private.current_user_id()) is not null);
create policy cti_write on public.checklist_template_items for all to authenticated
  using ((select private.is_coordinator_or_supervisor())) with check ((select private.is_coordinator_or_supervisor()));

-- deal checklists (lee agente titular + coordinador + supervisor) ---------------------------------------
create policy dc_select on public.deal_checklists for select to authenticated
  using (private.can_read_deal(deal_id));
create policy dc_insert on public.deal_checklists for insert to authenticated
  with check ((select private.is_coordinator_or_supervisor()) and private.can_read_deal(deal_id));
create policy dc_update on public.deal_checklists for update to authenticated
  using (private.can_manage_deal_docs(deal_id)) with check (private.can_manage_deal_docs(deal_id));
create policy dc_delete on public.deal_checklists for delete to authenticated
  using ((select private.is_supervisor()));

create policy dci_select on public.deal_checklist_items for select to authenticated
  using (exists (select 1 from public.deal_checklists c where c.id = deal_checklist_id));
create policy dci_insert on public.deal_checklist_items for insert to authenticated
  with check ((select private.is_coordinator_or_supervisor())
              and exists (select 1 from public.deal_checklists c where c.id = deal_checklist_id));
create policy dci_update on public.deal_checklist_items for update to authenticated
  using (exists (select 1 from public.deal_checklists c where c.id = deal_checklist_id
                 and private.can_manage_deal_docs(c.deal_id)))
  with check (exists (select 1 from public.deal_checklists c where c.id = deal_checklist_id
                      and private.can_manage_deal_docs(c.deal_id)));
create policy dci_delete on public.deal_checklist_items for delete to authenticated
  using ((select private.is_supervisor()));

-- cierre / notaría ----------------------------------------------------------------------------------------
create policy offers_select on public.deal_offers for select to authenticated
  using (private.can_read_deal(deal_id));
create policy offers_write on public.deal_offers for all to authenticated
  using (private.can_manage_deal(deal_id))
  with check (private.can_manage_deal(deal_id) and created_by = (select private.current_user_id())
              or (select private.is_supervisor()));
create policy closings_select on public.deal_closings for select to authenticated
  using (private.can_read_deal(deal_id));
create policy closings_write on public.deal_closings for all to authenticated
  using (private.can_manage_deal(deal_id)) with check (private.can_manage_deal(deal_id));

-- audit_log -------------------------------------------------------------------------------------------------
create policy audit_select on public.audit_log for select to authenticated
  using ((select private.is_supervisor()));

-- =============================================================================
-- 20. STORAGE: buckets PRIVADOS + políticas por ruta
--     Convención de rutas (primer segmento = id de la entidad dueña):
--       deal-documents/{deal_id}/{document_type}/{uuid}.{ext}
--       contact-identity/{contact_id}/{uuid}.{ext}       (DNI/NIE/pasaporte)
--       audio-recordings/deal/{deal_id}/{audio_id}.{ext}
--       audio-recordings/property/{property_id}/{audio_id}.{ext}      (sin expediente)
--       audio-recordings/valuation/{valuation_id}/{audio_id}.{ext}    (valoración rápida)
--       property-media/{property_id}/{uuid}.{ext}         (fotos/planos; se sirven con signed URLs)
--       valuation-reports/{valuation_id}/{uuid}.pdf
-- =============================================================================
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values
  ('deal-documents',    'deal-documents',    false, 26214400,  array['application/pdf', 'image/jpeg', 'image/png', 'image/heic', 'image/webp']),
  ('contact-identity',  'contact-identity',  false, 10485760,  array['application/pdf', 'image/jpeg', 'image/png', 'image/heic', 'image/webp']),
  ('audio-recordings',  'audio-recordings',  false, 209715200, array['audio/mpeg', 'audio/mp4', 'audio/x-m4a', 'audio/webm', 'audio/ogg', 'audio/wav']),
  ('property-media',    'property-media',    false, 26214400,  array['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'application/pdf']),
  ('valuation-reports', 'valuation-reports', false, 15728640,  array['application/pdf'])
on conflict (id) do update
  set public = false,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

create or replace function private.storage_owner_id(p_name text)
returns uuid language sql immutable set search_path = '' as $$
  select private.try_uuid((storage.foldername(p_name))[1])
$$;

-- deal-documents
create policy "deal_docs_select" on storage.objects for select to authenticated
  using (bucket_id = 'deal-documents' and private.can_read_deal(private.storage_owner_id(name)));
create policy "deal_docs_insert" on storage.objects for insert to authenticated
  with check (bucket_id = 'deal-documents' and private.can_manage_deal_docs(private.storage_owner_id(name)));
create policy "deal_docs_update" on storage.objects for update to authenticated
  using (bucket_id = 'deal-documents' and private.can_manage_deal_docs(private.storage_owner_id(name)))
  with check (bucket_id = 'deal-documents' and private.can_manage_deal_docs(private.storage_owner_id(name)));
create policy "deal_docs_delete" on storage.objects for delete to authenticated
  using (bucket_id = 'deal-documents' and (select private.is_supervisor()));

-- contact-identity (DNI): titular / agente con expediente / coordinador / supervisor
create policy "identity_select" on storage.objects for select to authenticated
  using (bucket_id = 'contact-identity' and private.can_read_contact_sensitive(private.storage_owner_id(name)));
create policy "identity_insert" on storage.objects for insert to authenticated
  with check (bucket_id = 'contact-identity' and private.can_write_contact_sensitive(private.storage_owner_id(name)));
create policy "identity_update" on storage.objects for update to authenticated
  using (bucket_id = 'contact-identity' and private.can_write_contact_sensitive(private.storage_owner_id(name)))
  with check (bucket_id = 'contact-identity' and private.can_write_contact_sensitive(private.storage_owner_id(name)));
create policy "identity_delete" on storage.objects for delete to authenticated
  using (bucket_id = 'contact-identity' and (select private.is_supervisor()));

-- audio-recordings: titular de la entidad del prefijo (deal/property/valuation) + supervisor
create policy "audio_select" on storage.objects for select to authenticated
  using (bucket_id = 'audio-recordings' and private.can_access_audio_path(name));
create policy "audio_insert" on storage.objects for insert to authenticated
  with check (bucket_id = 'audio-recordings' and private.can_access_audio_path(name));
create policy "audio_update" on storage.objects for update to authenticated
  using (bucket_id = 'audio-recordings' and private.can_access_audio_path(name))
  with check (bucket_id = 'audio-recordings' and private.can_access_audio_path(name));
create policy "audio_delete" on storage.objects for delete to authenticated
  using (bucket_id = 'audio-recordings' and (select private.is_supervisor()));

-- Lectura resolviendo la fila de documents/audio_recordings (archivos que siguen en su
-- ruta original pero ahora están vinculados a un expediente). Políticas permisivas: se suman (OR).
create policy "crm_select_via_document_row" on storage.objects for select to authenticated
  using (bucket_id in ('deal-documents', 'contact-identity', 'audio-recordings', 'property-media', 'valuation-reports')
         and private.can_read_document_object(bucket_id, name));

-- property-media
create policy "media_select" on storage.objects for select to authenticated
  using (bucket_id = 'property-media' and private.can_read_property(private.storage_owner_id(name)));
create policy "media_insert" on storage.objects for insert to authenticated
  with check (bucket_id = 'property-media' and private.can_manage_property(private.storage_owner_id(name)));
create policy "media_update" on storage.objects for update to authenticated
  using (bucket_id = 'property-media' and private.can_manage_property(private.storage_owner_id(name)))
  with check (bucket_id = 'property-media' and private.can_manage_property(private.storage_owner_id(name)));
create policy "media_delete" on storage.objects for delete to authenticated
  using (bucket_id = 'property-media' and private.can_manage_property(private.storage_owner_id(name)));

-- valuation-reports
create policy "vreports_select" on storage.objects for select to authenticated
  using (bucket_id = 'valuation-reports' and private.can_access_valuation(private.storage_owner_id(name)));
create policy "vreports_insert" on storage.objects for insert to authenticated
  with check (bucket_id = 'valuation-reports' and private.can_access_valuation(private.storage_owner_id(name)));
create policy "vreports_update" on storage.objects for update to authenticated
  using (bucket_id = 'valuation-reports' and private.can_access_valuation(private.storage_owner_id(name)))
  with check (bucket_id = 'valuation-reports' and private.can_access_valuation(private.storage_owner_id(name)));
create policy "vreports_delete" on storage.objects for delete to authenticated
  using (bucket_id = 'valuation-reports' and (select private.is_supervisor()));

-- =============================================================================
-- 21. PRIVILEGIOS
-- =============================================================================
-- anon: sin acceso a nada del CRM (no hay parte pública en la BD)
revoke all on all tables    in schema public from anon;
revoke all on all sequences in schema public from anon;
revoke all on all functions in schema public from anon, public;

grant select, insert, update, delete on all tables in schema public to authenticated;
grant usage, select on all sequences in schema public to authenticated;
grant execute on all functions in schema public to authenticated;
grant all on all tables in schema public to service_role;
grant usage, select on all sequences in schema public to service_role;
grant execute on all functions in schema public to service_role;

-- Tablas inmutables / sólo-trigger: se retiran privilegios de escritura además de RLS
revoke insert, update, delete on public.deal_phase_history, public.audit_log from authenticated;
revoke update, delete on public.consent_records, public.valuation_ai_runs from authenticated;

-- Helpers privados: ejecutables por authenticated (las políticas los invocan)
revoke all on all functions in schema private from public, anon;
grant execute on all functions in schema private to authenticated, service_role;
revoke execute on function private.instantiate_checklists(uuid, public.pipeline_phase) from authenticated;

commit;
