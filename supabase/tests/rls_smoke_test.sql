-- =============================================================================
-- 04_rls_smoke_test.sql · CRM Inmobiliario RK Santos · Solfico
-- Versión 1.1 (final) · 17/11/2026
-- -----------------------------------------------------------------------------
-- Prueba de humo de RLS, pipeline, checklists, valorador (bloqueo del informe al
-- cliente), audios (incl. vinculación posterior a expediente), storage, cruce y RGPD.
--
-- SÓLO para una base de datos desechable (local o rama de Supabase): crea usuarios
-- y datos ficticios y deja funciones auxiliares test_* que se eliminan al final.
-- Orden en local:
--   psql -v ON_ERROR_STOP=1 -f 00_supabase_stubs.sql   (sólo fuera de Supabase)
--   psql -v ON_ERROR_STOP=1 -f 02_schema.sql
--   psql -v ON_ERROR_STOP=1 -f seed.sql
--   psql -v ON_ERROR_STOP=1 -f 04_rls_smoke_test.sql
-- Cualquier aserción fallida aborta con "FAIL: ...".
-- =============================================================================
\set QUIET on
\set VERBOSITY terse
\o /dev/null

\set SUP   '''00000000-0000-0000-0000-000000000001'''
\set COORD '''00000000-0000-0000-0000-000000000002'''
\set ANA   '''00000000-0000-0000-0000-0000000000a1'''
\set BETO  '''00000000-0000-0000-0000-0000000000b2'''


-- Helper de identidad (más legible que macros psql)
create or replace function public.test_login(p_uid uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated')::text, false);
end $$;
grant execute on function public.test_login(uuid) to authenticated;

create or replace function public.test_assert(p_ok boolean, p_msg text) returns void language plpgsql as $$
begin
  if p_ok is distinct from true then raise exception 'FAIL: %', p_msg; end if;
  raise notice 'OK   %', p_msg;
end $$;
grant execute on function public.test_assert(boolean, text) to authenticated;

-- Devuelve true si la sentencia falla (cualquier error)
create or replace function public.test_fails(p_sql text) returns boolean language plpgsql as $$
begin
  execute p_sql;
  return false;
exception when others then
  raise notice '     (error esperado) %', sqlerrm;
  return true;
end $$;
grant execute on function public.test_fails(text) to authenticated;

-- ---------- 1. Usuarios (como service/postgres) ----------
insert into auth.users (id, email, raw_user_meta_data) values
  (:SUP,   'raul@rksantos.es',  '{"full_name":"Raúl Santos","role":"supervisor"}'),
  (:COORD, 'coord@rksantos.es', '{"full_name":"Coordinación RK"}'),
  (:ANA,   'ana@rksantos.es',   '{"full_name":"Ana Agente"}'),
  (:BETO,  'beto@rksantos.es',  '{"full_name":"Beto Agente"}');

select public.test_assert((select count(*) = 4 and bool_and(role = 'agent' and not is_active) from public.profiles),
  'handle_new_user crea perfiles inactivos con rol agent (ignora user_metadata.role)');

update public.profiles set is_active = true, role = 'supervisor'  where id = :SUP;
update public.profiles set is_active = true, role = 'coordinator' where id = :COORD;
update public.profiles set is_active = true where id in (:ANA, :BETO);

-- Zonas: se usan las de seed.sql (Eixample > Dreta de l'Eixample)
select public.test_assert((select count(*) > 40 from public.zones), 'seed.sql cargado (zonas de Barcelona y Vilanova i la Geltrú)');

-- ---------- 2. Agente Ana crea su cartera ----------
select public.test_login(:ANA);
set role authenticated;

select public.test_assert(public.test_fails($$update public.profiles set role = 'supervisor' where id = '00000000-0000-0000-0000-0000000000a1'$$),
  'Un agente no puede auto-ascenderse de rol');

insert into public.contacts (id, owner_agent_id, first_name, last_name, phone, source, in_influence_circle)
values ('20000000-0000-0000-0000-000000000001', :ANA, 'Lucía', 'Propietaria', '600000001', 'influence_circle', true);
insert into public.contact_sensitive (contact_id, national_id_type, national_id_number)
values ('20000000-0000-0000-0000-000000000001', 'dni', '12345678Z');
insert into public.consent_records (contact_id, purpose, legal_basis, granted, policy_version, channel, collected_by)
values ('20000000-0000-0000-0000-000000000001', 'audio_recording', 'consent', true, 'v1.0', 'firma_papel', :ANA);

insert into public.properties (id, reference, owner_agent_id, status, operation_type, property_type, street, city,
                               zone_id, built_area_m2, bedrooms, bathrooms, has_elevator, has_terrace, features, asking_price)
values ('30000000-0000-0000-0000-000000000001', 'RK-2026-0001', :ANA, 'available', 'sale', 'flat', 'Carrer Secret 1', 'Barcelona',
        (select id from public.zones where city = 'Barcelona' and name = 'Dreta de l''Eixample'), 90, 3, 2, true, true, '{luminoso,reformado}', 450000);
insert into public.property_internal (property_id, owner_min_price, commission_pct, exclusivity)
values ('30000000-0000-0000-0000-000000000001', 420000, 3.5, true);

insert into public.deals (id, agent_id, primary_contact_id, property_id)
values ('40000000-0000-0000-0000-000000000001', :ANA, '20000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000001');

select public.test_assert(public.test_fails($$insert into public.deals (agent_id, primary_contact_id, phase)
  values ('00000000-0000-0000-0000-0000000000a1', '20000000-0000-0000-0000-000000000001', 'cierre')$$),
  'Un expediente nuevo no puede nacer en fase cierre');

select public.change_deal_phase('40000000-0000-0000-0000-000000000001', 'prospecto') \g /dev/null
select public.test_assert((select phase = 'prospecto' from public.deals where id = '40000000-0000-0000-0000-000000000001'),
  'Avance correcto circulo_influencia -> prospecto');
select public.test_assert(public.test_fails($$select public.change_deal_phase('40000000-0000-0000-0000-000000000001', 'documentacion')$$),
  'No se pueden saltar fases (prospecto -> documentacion)');
select public.test_assert(public.test_fails($$select public.change_deal_phase('40000000-0000-0000-0000-000000000001', 'circulo_influencia', 'error')$$),
  'Un agente no puede retroceder fases');

-- Storage: Ana sube a su expediente; ruta ajena falla
insert into storage.objects (bucket_id, name) values ('deal-documents', '40000000-0000-0000-0000-000000000001/nota_simple/ns.pdf');
insert into storage.objects (bucket_id, name) values ('audio-recordings', 'deal/40000000-0000-0000-0000-000000000001/a1.webm');
select public.test_assert(public.test_fails($$insert into storage.objects (bucket_id, name) values ('deal-documents', 'no-es-uuid/x.pdf')$$),
  'Storage rechaza rutas cuyo primer segmento no es un expediente accesible');

-- ---------- 3. Agente Beto: aislamiento ----------
select public.test_login(:BETO);
select public.test_assert((select count(*) = 0 from public.contacts),          'Beto NO ve contactos de Ana');
select public.test_assert((select count(*) = 0 from public.contact_sensitive), 'Beto NO ve DNI de Ana');
select public.test_assert((select count(*) = 0 from public.deals),             'Beto NO ve expedientes de Ana');
select public.test_assert((select count(*) = 0 from public.property_internal), 'Beto NO ve datos internos del encargo');
select public.test_assert((select count(*) = 1 from public.properties),        'Beto SÍ ve la ficha del inmueble disponible (bolsa común)');
select public.test_assert((select province = 'Barcelona' from public.properties) and (select bool_and(province = 'Barcelona') from public.zones),
  'Provincia por defecto = Barcelona (zonas e inmuebles)');
select public.test_assert((select count(*) = 0 from storage.objects),          'Beto NO ve archivos del expediente de Ana');
select public.test_assert(public.test_fails($$insert into storage.objects (bucket_id, name) values ('deal-documents', '40000000-0000-0000-0000-000000000001/x.pdf')$$),
  'Beto NO puede subir archivos al expediente de Ana');
update public.properties set asking_price = 1 where id = '30000000-0000-0000-0000-000000000001';
select public.test_assert((select asking_price = 450000 from public.properties where id = '30000000-0000-0000-0000-000000000001'),
  'Beto NO puede modificar el inmueble de Ana (update filtrado por RLS)');
select public.test_assert(public.test_fails($$insert into public.valuation_parameters (params) values ('{}')$$),
  'Un agente NO puede crear parámetros de valoración');

-- Cruce: Beto tiene un comprador
insert into public.contacts (id, owner_agent_id, first_name, source) values ('20000000-0000-0000-0000-000000000002', :BETO, 'Carlos Comprador', 'website');
insert into public.demands (id, contact_id, agent_id, operation_type, property_types, price_min, price_max, bedrooms_min, needs_elevator, desired_features)
values ('50000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000002', :BETO, 'sale', '{flat,penthouse}', 350000, 460000, 3, true, '{luminoso,garaje}');
insert into public.demand_zones
select '50000000-0000-0000-0000-000000000001', id from public.zones where city = 'Barcelona' and name = 'Eixample';
select public.test_assert((select score = 95 from public.match_properties_for_demand('50000000-0000-0000-0000-000000000001')),
  'Cruce: inmueble de Ana puntúa 95/100 para la demanda de Beto (distrito ancestro, precio en rango, 1/2 extras)');
select public.test_assert((select count(*) = 1 from public.property_demand_matches),
  'Cruce persistido automáticamente por trigger y visible para el agente de la demanda');

-- ---------- 4. Coordinador ----------
select public.test_login(:COORD);
select public.test_assert((select count(*) = 1 from public.deals),             'Coordinador ve todos los expedientes');
select public.test_assert((select count(*) = 2 from public.contacts),          'Coordinador ve todos los contactos');
select public.test_assert((select count(*) = 1 from public.contact_sensitive), 'Coordinador ve datos sensibles (revisión documental)');
select public.test_assert((select count(*) = 0 from public.property_internal), 'Coordinador NO ve comisiones/precio mínimo');
select public.test_assert((select count(*) = 1 from storage.objects where bucket_id = 'deal-documents'),  'Coordinador ve documentos del expediente');
select public.test_assert((select count(*) = 0 from storage.objects where bucket_id = 'audio-recordings'), 'Coordinador NO ve audios');
select public.test_assert((select count(*) = 0 from public.audit_log),         'Coordinador NO ve auditoría');

-- Plantilla de checklist para la fase Captación
insert into public.checklist_templates (id, name, phase, created_by)
values ('60000000-0000-0000-0000-000000000001', 'Captación franquicia', 'captacion', :COORD);
insert into public.checklist_template_items (template_id, position, title, is_required, requires_document, document_type) values
  ('60000000-0000-0000-0000-000000000001', 1, 'Hoja de encargo firmada', true, true, 'hoja_encargo'),
  ('60000000-0000-0000-0000-000000000001', 2, 'Nota simple actualizada',  true, true, 'nota_simple');

-- ---------- 5. Ana avanza a Captación: se instancia el checklist ----------
select public.test_login(:ANA);
select public.change_deal_phase('40000000-0000-0000-0000-000000000001', 'captacion') \g /dev/null
select public.test_assert((select count(*) = 2 from public.deal_checklist_items), 'Checklist de Captación instanciado al entrar en la fase');
select public.test_assert(public.test_fails($$select public.change_deal_phase('40000000-0000-0000-0000-000000000001', 'documentacion')$$),
  'No se avanza con checklist obligatorio pendiente');
update public.deal_checklist_items set status = 'submitted';
select public.test_assert(public.test_fails($$update public.deal_checklist_items set status = 'approved'$$),
  'El agente NO puede aprobar puntos de checklist');
select public.test_assert(public.test_fails($$update public.deal_checklist_items set status = 'not_applicable'$$),
  'El agente NO puede marcar puntos como no aplicables');

select public.test_login(:COORD);
update public.deal_checklist_items set status = 'approved', review_comment = 'OK';
select public.test_assert(public.test_fails($$update public.deals set expected_fee = 1$$) is false,
  'El update del coordinador sobre deals no da error (simplemente no afecta filas)');
select public.test_assert((select expected_fee is null from public.deals),
  'Coordinador NO puede editar el expediente (update sin efecto por RLS)');

select public.test_login(:ANA);
select public.change_deal_phase('40000000-0000-0000-0000-000000000001', 'documentacion') \g /dev/null
select public.test_assert((select phase = 'documentacion' from public.deals), 'Tras aprobación del coordinador, Ana avanza a documentacion');
select public.test_assert((select count(*) = 4 from public.deal_phase_history), 'Historial de fases con 4 registros (alta + 3 avances)');

-- ---------- 6. Supervisor: parámetros + valoración ----------
select public.test_login(:SUP);
insert into public.valuation_parameters (id, params, notes)
values ('70000000-0000-0000-0000-000000000001',
        '{"max_agent_adjustment_pct": 10, "weights": {"comparables": 0.6, "zone_benchmark": 0.4}, "condition_coefficients": {"to_reform": 0.85, "good": 1.0, "reformed": 1.08}}',
        'Versión inicial');
select public.activate_valuation_parameters('70000000-0000-0000-0000-000000000001') \g /dev/null
select public.test_assert(public.test_fails($$update public.valuation_parameters set params = '{}' where version = 1$$),
  'Los parámetros son inmutables (se versiona)');
select public.test_assert((select count(*) = 1 from public.deals) and (select count(*) = 1 from public.property_internal)
                          and (select count(*) > 0 from public.audit_log),
  'Supervisor ve todo (expedientes, datos internos, auditoría)');

select public.test_login(:ANA);
insert into public.valuation_requests (id, property_id, deal_id, requested_by)
values ('80000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000001', '40000000-0000-0000-0000-000000000001', :ANA);
select public.test_assert((select parameters_id = '70000000-0000-0000-0000-000000000001'
                                  and not (input_snapshot ? 'street') and not (input_snapshot ? 'cadastral_reference')
                           from public.valuation_requests),
  'La solicitud fija la versión de parámetros activa y el snapshot no incluye dirección exacta (minimización)');
insert into public.valuation_ai_runs (id, valuation_id, provider, model, prompt_version, output_schema_version, input_payload,
                                      output, estimated_value, estimated_min, estimated_max, confidence, success)
values ('81000000-0000-0000-0000-000000000001', '80000000-0000-0000-0000-000000000001', 'openai', 'gpt-x', 'valuator-v1', '1.0',
        '{}', '{"estimatedValue": 440000}', 440000, 420000, 460000, 0.78, true);
select public.test_assert((select status = 'ai_completed' from public.valuation_requests), 'Estado ai_completed tras la ejecución IA');
select public.test_assert(public.test_fails($$update public.valuation_ai_runs set confidence = 1$$),
  'Las ejecuciones IA son inmutables');

-- ---------- 6b. Audio sin expediente (valoración rápida) ----------
insert into public.valuation_requests (id, property_id, requested_by, purpose)
values ('80000000-0000-0000-0000-000000000002', '30000000-0000-0000-0000-000000000001', :ANA, 'quick_estimate');
insert into storage.objects (bucket_id, name) values ('audio-recordings', 'valuation/80000000-0000-0000-0000-000000000002/a2.webm');
insert into public.documents (id, bucket_id, object_path, document_type, sensitivity, valuation_request_id, deal_id, uploaded_by) values
  ('90000000-0000-0000-0000-000000000001', 'audio-recordings', 'valuation/80000000-0000-0000-0000-000000000002/a2.webm', 'otro', 'sensitive', '80000000-0000-0000-0000-000000000002', null, :ANA),
  ('90000000-0000-0000-0000-000000000002', 'audio-recordings', 'valuation/80000000-0000-0000-0000-000000000002/a3.webm', 'otro', 'sensitive', '80000000-0000-0000-0000-000000000002', null, :ANA),
  ('90000000-0000-0000-0000-000000000003', 'audio-recordings', 'deal/40000000-0000-0000-0000-000000000001/a1.webm',      'otro', 'sensitive', null, '40000000-0000-0000-0000-000000000001', :ANA);
insert into public.audio_recordings (id, document_id, recorded_by, valuation_request_id, consent_record_id, context)
values ('91000000-0000-0000-0000-000000000001', '90000000-0000-0000-0000-000000000001', :ANA, '80000000-0000-0000-0000-000000000002',
        (select id from public.consent_records where purpose = 'audio_recording' limit 1), 'valoracion');
select public.test_assert((select count(*) = 1 from public.audio_recordings where deal_id is null and property_id is null
                           and valuation_request_id = '80000000-0000-0000-0000-000000000002'),
  'Audio vinculado SOLO a una valoración (sin expediente) permitido para la agente titular');
select public.test_assert(public.test_fails($$insert into public.audio_recordings (document_id, recorded_by, context)
  values ('90000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-0000000000a1', 'nota_voz')$$),
  'Audio sin ningún vínculo (expediente/inmueble/valoración) rechazado');
reset role;  -- también a nivel de BD (service_role/postgres): lo rechaza el CHECK audio_owner_chk
select public.test_assert(public.test_fails($$insert into public.audio_recordings (document_id, recorded_by, context)
  values ('90000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-0000000000a1', 'nota_voz')$$),
  'Audio sin vínculos rechazado también para service_role (CHECK audio_owner_chk)');
set role authenticated;
select public.test_assert(public.test_fails($$insert into public.audio_recordings (document_id, recorded_by, valuation_request_id, context)
  values ('90000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-0000000000a1', '80000000-0000-0000-0000-000000000002', 'valoracion')$$),
  'Audio de valoración sin consentimiento rechazado (se mantiene audio_consent_chk)');
select public.test_assert(public.test_fails($$insert into public.audio_recordings (document_id, recorded_by, valuation_request_id, context)
  values ('90000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-0000000000a1', '80000000-0000-0000-0000-000000000002', 'nota_voz')$$),
  'Audio cuya ruta de Storage no corresponde a sus vínculos rechazado');

select public.test_login(:BETO);
select public.test_assert((select count(*) = 0 from public.audio_recordings), 'Beto NO ve el audio de la valoración de Ana');
select public.test_assert((select count(*) = 0 from storage.objects where bucket_id = 'audio-recordings'), 'Beto NO ve el archivo de audio en Storage');
select public.test_assert(public.test_fails($$insert into storage.objects (bucket_id, name) values ('audio-recordings', 'valuation/80000000-0000-0000-0000-000000000002/x.webm')$$),
  'Beto NO puede subir audio bajo la valoración de Ana');
select public.test_login(:COORD);
select public.test_assert((select count(*) = 0 from public.audio_recordings), 'Coordinador NO ve audios de valoración');
select public.test_login(:ANA);
select public.test_assert((select count(*) = 2 from storage.objects where bucket_id = 'audio-recordings'),
  'Ana ve sus audios en Storage (prefijos deal/ y valuation/)');

-- Ajuste del 25% => requiere supervisor
select public.test_assert(public.test_fails($$insert into public.valuation_reviews (valuation_id, ai_run_id, ai_value, adjusted_value, adjustment_reason, reviewed_by, is_final)
  values ('80000000-0000-0000-0000-000000000001', '81000000-0000-0000-0000-000000000001', 0, 550000, 'Vistas', '00000000-0000-0000-0000-0000000000a1', true)$$),
  'Ajuste > umbral no puede ser final sin supervisor');
insert into public.valuation_reviews (id, valuation_id, ai_run_id, ai_value, adjusted_value, adjustment_reason, reviewed_by)
values ('82000000-0000-0000-0000-000000000001', '80000000-0000-0000-0000-000000000001', '81000000-0000-0000-0000-000000000001', 0, 550000, 'Vistas', :ANA);
select public.test_assert((select status = 'pending_supervisor' from public.valuation_requests where id = '80000000-0000-0000-0000-000000000001'), 'Valoración queda pendiente de supervisor');
select public.test_assert(public.test_fails($$update public.valuation_reviews set approved_by = '00000000-0000-0000-0000-0000000000a1'$$),
  'El agente NO puede auto-aprobar su ajuste');

-- Informe al cliente: revisión NO final => bloqueado
select public.test_assert(public.test_fails($$insert into public.valuation_client_reports (valuation_id, review_id, display_value, client_summary)
  values ('80000000-0000-0000-0000-000000000001', '82000000-0000-0000-0000-000000000001', 550000, 'Informe')$$),
  'Informe al cliente BLOQUEADO si la revisión no es final');

-- Revisión final con ajuste > umbral SIN approved_by (forzada saltándose triggers, como dato corrupto/importado)
reset role;
set session_replication_role = replica;
insert into public.valuation_reviews (id, valuation_id, ai_run_id, ai_value, adjusted_value, adjustment_reason, requires_supervisor, reviewed_by, is_final)
values ('83000000-0000-0000-0000-000000000001', '80000000-0000-0000-0000-000000000001', '81000000-0000-0000-0000-000000000001',
        440000, 550000, 'Forzada', false, :ANA, true);
set session_replication_role = origin;
set role authenticated;
select public.test_assert(public.test_fails($$insert into public.valuation_client_reports (valuation_id, review_id, display_value, client_summary)
  values ('80000000-0000-0000-0000-000000000001', '83000000-0000-0000-0000-000000000001', 550000, 'Informe')$$),
  'Informe BLOQUEADO si el ajuste supera el umbral sin approved_by (aunque requires_supervisor venga a false)');
reset role;
delete from public.valuation_reviews where id = '83000000-0000-0000-0000-000000000001';
set role authenticated;

select public.test_login(:SUP);
update public.valuation_reviews set approved_by = :SUP, is_final = true where id = '82000000-0000-0000-0000-000000000001';
select public.test_assert((select status = 'approved' from public.valuation_requests where id = '80000000-0000-0000-0000-000000000001'), 'Supervisor aprueba el ajuste: valoración aprobada');

select public.test_login(:ANA);
select public.test_assert(public.test_fails($$insert into public.valuation_client_reports (valuation_id, review_id, display_value, client_summary)
  values ('80000000-0000-0000-0000-000000000002', '82000000-0000-0000-0000-000000000001', 550000, 'Informe')$$),
  'Informe BLOQUEADO si la revisión pertenece a otra valoración');
select public.test_assert(public.test_fails($$insert into public.valuation_client_reports (valuation_id, review_id, display_value, client_summary)
  values ('80000000-0000-0000-0000-000000000001', '82000000-0000-0000-0000-000000000001', 550000, 'Valor de mercado estimado: 550.000 EUR')$$) is false,
  'Informe PERMITIDO con revisión final y aprobada por el supervisor');
select public.test_assert((select count(*) = 1 from public.valuation_client_reports), 'Informe al cliente persistido');
select public.test_login(:SUP);
select public.test_assert(public.test_fails($$update public.valuation_reviews set is_final = false where id = '82000000-0000-0000-0000-000000000001'$$),
  'No se puede desvalidar una revisión que ya respalda un informe');

-- RGPD: anonimización
select public.test_assert(public.test_fails($$select public.anonymize_contact('20000000-0000-0000-0000-000000000002', 'Solicitud de supresión')$$) is false,
  'anonymize_contact se ejecuta sin error para el supervisor');
select public.test_assert((select first_name is null and anonymized_at is not null from public.contacts where id = '20000000-0000-0000-0000-000000000002'),
  'Supervisor anonimiza un contacto (derecho de supresión)');

select public.test_login(:BETO);
select public.test_assert(public.test_fails($$select public.anonymize_contact('20000000-0000-0000-0000-000000000001', 'x')$$),
  'Un agente NO puede anonimizar');

-- ---------- 7. Audio de valoración rápida vinculado DESPUÉS a un expediente ----------
-- Decisión v1.1: el archivo NO se mueve; sólo se rellena deal_id en audio y documento.
select public.test_login(:ANA);
select public.link_audio_to_deal('91000000-0000-0000-0000-000000000001', '40000000-0000-0000-0000-000000000001') \g /dev/null
select public.test_assert((select deal_id = '40000000-0000-0000-0000-000000000001' and valuation_request_id is not null
                           from public.audio_recordings where id = '91000000-0000-0000-0000-000000000001'),
  'link_audio_to_deal: el audio queda vinculado al expediente y conserva la valoración original');
select public.test_assert((select deal_id = '40000000-0000-0000-0000-000000000001'
                                  and object_path = 'valuation/80000000-0000-0000-0000-000000000002/a2.webm'
                           from public.documents where id = '90000000-0000-0000-0000-000000000001'),
  'El documento se vincula al expediente y su ruta física NO cambia (valuation/…)');
select public.test_assert((select count(*) = 1 from storage.objects
                           where bucket_id = 'audio-recordings' and name = 'valuation/80000000-0000-0000-0000-000000000002/a2.webm'),
  'Ana sigue leyendo el archivo en Storage en su ruta original');
select public.test_assert(public.test_fails($$update public.documents set object_path = 'deal/40000000-0000-0000-0000-000000000001/a2.webm'
  where id = '90000000-0000-0000-0000-000000000001'$$),
  'La ruta física de un documento es inmutable');
select public.test_assert(public.test_fails($$update public.audio_recordings set valuation_request_id = null
  where id = '91000000-0000-0000-0000-000000000001'$$),
  'No se puede desvincular la entidad original del prefijo (valuation/) aunque haya expediente');

select public.test_login(:SUP);
select public.test_assert((select count(*) = 1 from public.audio_recordings where id = '91000000-0000-0000-0000-000000000001')
                          and (select count(*) = 1 from storage.objects where name = 'valuation/80000000-0000-0000-0000-000000000002/a2.webm'),
  'Supervisor lee el audio vinculado (fila y archivo)');

select public.test_login(:COORD);
select public.test_assert((select count(*) = 0 from public.audio_recordings)
                          and (select count(*) = 0 from storage.objects where bucket_id = 'audio-recordings'),
  'Coordinador sigue sin ver audios aunque estén vinculados a un expediente');

select public.test_login(:BETO);
select public.test_assert((select count(*) = 0 from public.audio_recordings)
                          and (select count(*) = 0 from public.documents where bucket_id = 'audio-recordings')
                          and (select count(*) = 0 from storage.objects where bucket_id = 'audio-recordings'),
  'Beto (sin entidades) sigue bloqueado: ni fila, ni documento, ni archivo');
select public.test_assert(public.test_fails($$select public.link_audio_to_deal('91000000-0000-0000-0000-000000000001', '40000000-0000-0000-0000-000000000001')$$),
  'Beto NO puede vincular audios ajenos');

-- Reasignación del expediente a Beto por el supervisor
select public.test_login(:SUP);
update public.deals set agent_id = :BETO where id = '40000000-0000-0000-0000-000000000001';
select public.test_login(:BETO);
select public.test_assert((select count(*) = 1 from public.audio_recordings where id = '91000000-0000-0000-0000-000000000001'),
  'Tras reasignar el expediente, Beto ve el audio por el vínculo deal_id');
select public.test_assert((select count(*) = 1 from public.documents where id = '90000000-0000-0000-0000-000000000001'),
  'Beto ve el documento del audio por el vínculo deal_id');
select public.test_assert((select count(*) = 1 from storage.objects
                           where bucket_id = 'audio-recordings' and name = 'valuation/80000000-0000-0000-0000-000000000002/a2.webm'),
  'Beto lee el archivo en valuation/… resolviendo la fila (no sólo el prefijo)');
select public.test_assert(public.test_fails($$insert into storage.objects (bucket_id, name) values ('audio-recordings', 'valuation/80000000-0000-0000-0000-000000000002/nuevo.webm')$$),
  'Beto sigue sin poder escribir bajo la valoración de Ana (escritura por prefijo)');
select public.test_assert(public.test_fails($$update public.audio_recordings set context = 'reunion' where id = '91000000-0000-0000-0000-000000000001'$$) is false
                          , 'El update de Beto sobre el audio no da error (RLS lo filtra)');
select public.test_assert((select context = 'valoracion' from public.audio_recordings where id = '91000000-0000-0000-0000-000000000001'),
  'Beto NO puede editar el audio (requiere gestionar también la valoración original)');
select public.test_login(:ANA);
select public.test_assert((select count(*) = 1 from public.audio_recordings where id = '91000000-0000-0000-0000-000000000001'),
  'Ana conserva la lectura por la valoración que solicitó');

-- Usuario inactivo pierde acceso
reset role;
select set_config('request.jwt.claims', '', false);   -- contexto service (sin usuario)
update public.profiles set is_active = false where id = :BETO;
select public.test_login(:BETO);
set role authenticated;
select public.test_assert((select count(*) = 0 from public.properties) and (select count(*) = 0 from public.demands),
  'Usuario desactivado no ve nada');

reset role;
drop function public.test_login(uuid);
drop function public.test_assert(boolean, text);
drop function public.test_fails(text);
\o
\echo '==== SMOKE TEST COMPLETADO: todas las aserciones OK ===='
