-- =============================================================================
-- seed.sql · CRM Inmobiliario RK Santos · Solfico
-- Versión 1.1 (final) · 17/11/2026
-- -----------------------------------------------------------------------------
-- Datos iniciales de referencia. Ejecutar DESPUÉS de 02_schema.sql
-- (en Supabase: supabase/seed.sql, o `psql -f seed.sql` con rol postgres/service).
-- Idempotente: se puede ejecutar varias veces (ON CONFLICT / NOT EXISTS).
--
-- Contenido:
--   1. Zonas: Barcelona ciudad (municipio > distrito > barrio) y
--      Vilanova i la Geltrú (comarca del Garraf, provincia de Barcelona).
--   2. Parámetros del valorador v1 (activos si no hay otra versión activa).
--   3. Benchmarks €/m² de EJEMPLO (is_placeholder = true) → NO son datos de mercado.
--   4. Plantilla de checklist de EJEMPLO (inactiva) a sustituir por la oficial de la franquicia.
--
-- Nota sobre autoría: el seed corre sin usuario de Auth, por eso
-- valuation_parameters.created_by y checklist_templates.created_by quedan a NULL
-- (= "versión de sistema"). Las versiones posteriores las crea Raúl desde la app y
-- llevan su id automáticamente (trigger guard_valuation_parameters).
-- =============================================================================

begin;

-- -----------------------------------------------------------------------------
-- 1. ZONAS
-- La jerarquía alimenta el cruce: una demanda con un distrito (o el municipio)
-- casa con inmuebles de cualquiera de sus barrios (private.zone_lineage).
-- Lista inicial a validar/ampliar por RK Santos (añadir códigos postales en postal_codes).
-- -----------------------------------------------------------------------------
create temporary table seed_zones (name text, parent_name text, city text, sort int) on commit drop;

insert into seed_zones (name, parent_name, city, sort) values
  -- Barcelona: municipio
  ('Barcelona', null, 'Barcelona', 0),
  -- Barcelona: distritos
  ('Ciutat Vella',        'Barcelona', 'Barcelona', 1),
  ('Eixample',            'Barcelona', 'Barcelona', 1),
  ('Sants-Montjuïc',      'Barcelona', 'Barcelona', 1),
  ('Les Corts',           'Barcelona', 'Barcelona', 1),
  ('Sarrià-Sant Gervasi', 'Barcelona', 'Barcelona', 1),
  ('Gràcia',              'Barcelona', 'Barcelona', 1),
  ('Horta-Guinardó',      'Barcelona', 'Barcelona', 1),
  ('Nou Barris',          'Barcelona', 'Barcelona', 1),
  ('Sant Andreu',         'Barcelona', 'Barcelona', 1),
  ('Sant Martí',          'Barcelona', 'Barcelona', 1),
  -- Barcelona: barrios
  ('El Raval',                                    'Ciutat Vella', 'Barcelona', 2),
  ('El Barri Gòtic',                              'Ciutat Vella', 'Barcelona', 2),
  ('La Barceloneta',                              'Ciutat Vella', 'Barcelona', 2),
  ('Sant Pere, Santa Caterina i la Ribera',       'Ciutat Vella', 'Barcelona', 2),
  ('Dreta de l''Eixample',                        'Eixample', 'Barcelona', 2),
  ('Antiga Esquerra de l''Eixample',              'Eixample', 'Barcelona', 2),
  ('Nova Esquerra de l''Eixample',                'Eixample', 'Barcelona', 2),
  ('Sant Antoni',                                 'Eixample', 'Barcelona', 2),
  ('La Sagrada Família',                          'Eixample', 'Barcelona', 2),
  ('El Fort Pienc',                               'Eixample', 'Barcelona', 2),
  ('Sants',                                       'Sants-Montjuïc', 'Barcelona', 2),
  ('Hostafrancs',                                 'Sants-Montjuïc', 'Barcelona', 2),
  ('La Bordeta',                                  'Sants-Montjuïc', 'Barcelona', 2),
  ('El Poble-sec',                                'Sants-Montjuïc', 'Barcelona', 2),
  ('Les Corts (barri)',                           'Les Corts', 'Barcelona', 2),
  ('Pedralbes',                                   'Les Corts', 'Barcelona', 2),
  ('Sarrià',                                      'Sarrià-Sant Gervasi', 'Barcelona', 2),
  ('Sant Gervasi - Galvany',                      'Sarrià-Sant Gervasi', 'Barcelona', 2),
  ('Sant Gervasi - la Bonanova',                  'Sarrià-Sant Gervasi', 'Barcelona', 2),
  ('La Vila de Gràcia',                           'Gràcia', 'Barcelona', 2),
  ('El Camp d''en Grassot i Gràcia Nova',         'Gràcia', 'Barcelona', 2),
  ('Vallcarca i els Penitents',                   'Gràcia', 'Barcelona', 2),
  ('El Guinardó',                                 'Horta-Guinardó', 'Barcelona', 2),
  ('Horta',                                       'Horta-Guinardó', 'Barcelona', 2),
  ('Sant Andreu de Palomar',                      'Sant Andreu', 'Barcelona', 2),
  ('El Poblenou',                                 'Sant Martí', 'Barcelona', 2),
  ('El Clot',                                     'Sant Martí', 'Barcelona', 2),
  ('Diagonal Mar i el Front Marítim del Poblenou','Sant Martí', 'Barcelona', 2),
  ('La Vila Olímpica del Poblenou',               'Sant Martí', 'Barcelona', 2),
  ('Sant Martí de Provençals',                    'Sant Martí', 'Barcelona', 2),
  -- Vilanova i la Geltrú (Garraf): municipio + zonas comerciales
  ('Vilanova i la Geltrú', null, 'Vilanova i la Geltrú', 0),
  ('Centre',               'Vilanova i la Geltrú', 'Vilanova i la Geltrú', 1),
  ('La Geltrú',            'Vilanova i la Geltrú', 'Vilanova i la Geltrú', 1),
  ('Barri de Mar',         'Vilanova i la Geltrú', 'Vilanova i la Geltrú', 1),
  ('Ribes Roges',          'Vilanova i la Geltrú', 'Vilanova i la Geltrú', 1),
  ('Sant Joan',            'Vilanova i la Geltrú', 'Vilanova i la Geltrú', 1),
  ('Molí de Vent',         'Vilanova i la Geltrú', 'Vilanova i la Geltrú', 1),
  ('Zona Estació',         'Vilanova i la Geltrú', 'Vilanova i la Geltrú', 1);

-- Se insertan por niveles para poder resolver el padre por (city, name)
do $$
declare lvl int;
begin
  for lvl in 0..2 loop
    insert into public.zones (name, parent_id, city, province)
    select s.name, p.id, s.city, 'Barcelona'
    from seed_zones s
    left join public.zones p on p.city = s.city and p.name = s.parent_name
    where s.sort = lvl
    on conflict (city, name) do update
      set parent_id = excluded.parent_id, province = excluded.province, is_active = true;
  end loop;
end $$;

-- -----------------------------------------------------------------------------
-- 2. PARÁMETROS DEL VALORADOR v1 (estructura = ValuationParamsSchema en 03_zod_types.ts)
-- Valores por defecto prudentes, a revisar por Raúl antes del uso real.
-- -----------------------------------------------------------------------------
insert into public.valuation_parameters (version, is_active, params, notes, created_by)
select 1,
       not exists (select 1 from public.valuation_parameters where is_active),
       jsonb_build_object(
         'max_agent_adjustment_pct', 10,
         'weights', jsonb_build_object('comparables', 0.7, 'zone_benchmark', 0.3),
         'condition_coefficients', jsonb_build_object(
           'new', 1.10, 'like_new', 1.05, 'good', 1.00, 'reformed', 1.05, 'needs_update', 0.92, 'to_reform', 0.82),
         'floor_adjustments', jsonb_build_object(
           'ground_floor_pct', -8, 'no_elevator_per_floor_pct', -3, 'penthouse_pct', 10),
         'feature_premiums_pct', jsonb_build_object(
           'terraza', 5, 'garaje', 4, 'piscina', 3, 'vistas_mar', 6, 'exterior', 3, 'ascensor', 0),
         'comparables', jsonb_build_object(
           'max_age_months', 12, 'max_distance_m', 1500, 'min_count', 3, 'closing_price_weight', 1.5),
         'negotiation_margin_pct', 5,
         'min_confidence_to_deliver', 0.6
       ),
       'v1 de sistema (seed). Valores por defecto a validar por Raúl Santos.',
       null
where not exists (select 1 from public.valuation_parameters where version = 1);

-- -----------------------------------------------------------------------------
-- 3. BENCHMARKS €/m² · *** EJEMPLO ***
-- Cifras FICTICIAS y redondas sólo para probar el flujo del valorador.
-- NO son datos de mercado. Marcadas con is_placeholder = true: el route handler del
-- valorador las excluye (o muestra aviso) hasta que Raúl cargue valores validados.
-- -----------------------------------------------------------------------------
insert into public.valuation_zone_benchmarks
  (parameters_id, zone_id, property_type, operation_type, base_price_m2, source_note, is_placeholder)
select vp.id, z.id, null, 'sale', b.price,
       'EJEMPLO - valor ficticio pendiente de validación por Raúl Santos. NO es dato de mercado.', true
from (values
        ('Barcelona',            'Eixample',             1000.00),
        ('Barcelona',            'Gràcia',               1000.00),
        ('Barcelona',            'Sant Martí',           1000.00),
        ('Barcelona',            'Sants-Montjuïc',       1000.00),
        ('Vilanova i la Geltrú', 'Vilanova i la Geltrú', 1000.00)
     ) as b(city, zone_name, price)
join public.zones z on z.city = b.city and z.name = b.zone_name
join public.valuation_parameters vp on vp.version = 1
on conflict (parameters_id, zone_id, property_type, operation_type) do nothing;

-- -----------------------------------------------------------------------------
-- 4. PLANTILLA DE CHECKLIST · *** EJEMPLO ***
-- Pendiente de sustituir por el checklist OFICIAL de la franquicia.
-- Se crea INACTIVA (is_active = false): si estuviera activa bloquearía el avance de
-- fase de todos los expedientes. Coordinación la activa (o carga la oficial) desde la app.
-- -----------------------------------------------------------------------------
insert into public.checklist_templates (name, franchise_code, phase, operation_type, version, is_active, created_by)
values ('EJEMPLO · Captación venta', 'EJEMPLO', 'captacion', 'sale', 1, false, null)
on conflict (name, version) do nothing;

insert into public.checklist_template_items
  (template_id, position, title, description, is_required, requires_document, document_type, due_days)
select t.id, i.position, i.title, i.description, i.is_required, i.requires_document, i.document_type::public.document_type, i.due_days
from public.checklist_templates t
cross join (values
  (1, 'Hoja de encargo firmada',               'Exclusiva o compartida, con honorarios y duración',   true,  true,  'hoja_encargo',          3),
  (2, 'DNI/NIE de todos los titulares',         'Verificación de identidad (Ley 10/2010 PBC)',          true,  true,  'dni',                   3),
  (3, 'Consentimiento RGPD firmado',            'Información de tratamiento y finalidades',             true,  true,  'consentimiento_rgpd',   3),
  (4, 'Nota simple actualizada (< 3 meses)',    'Titularidad y cargas',                                 true,  true,  'nota_simple',           7),
  (5, 'Certificado de eficiencia energética',   'Obligatorio para publicitar',                          true,  true,  'cee',                   15),
  (6, 'Último recibo de IBI',                   null,                                                   false, true,  'ibi',                   15),
  (7, 'Certificado de deudas de la comunidad',  'Puede aportarse en fase de cierre',                    false, true,  'certificado_comunidad', null),
  (8, 'Valoración entregada al propietario',    'Informe del valorador validado',                       true,  false, null,                    7)
) as i(position, title, description, is_required, requires_document, document_type, due_days)
where t.name = 'EJEMPLO · Captación venta' and t.version = 1
on conflict (template_id, position) do nothing;

commit;
